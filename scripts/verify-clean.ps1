$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\', '/')
$clonePath = [System.IO.Path]::GetFullPath(
    (Join-Path $tempRoot ("zownload-clean-{0}" -f [guid]::NewGuid().ToString('N')))
)
$tempPrefix = $tempRoot + [System.IO.Path]::DirectorySeparatorChar
if (-not $clonePath.StartsWith($tempPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
    -not (Split-Path $clonePath -Leaf).StartsWith('zownload-clean-')) {
    throw "Refusing to use unexpected temporary path: $clonePath"
}

function Assert-ExitCode {
    param([string]$Step)
    if ($LASTEXITCODE -ne 0) {
        throw "$Step failed with exit code $LASTEXITCODE."
    }
}

$branch = (& git -C $repoRoot branch --show-current).Trim()
Assert-ExitCode 'read source branch'
if (-not $branch) {
    throw 'A named branch is required for the clean-clone check.'
}
$sourceCommit = (& git -C $repoRoot rev-parse HEAD).Trim()
Assert-ExitCode 'read source commit'

Write-Output "Cloning $branch at $sourceCommit into $clonePath"
try {
    & git clone --no-local --single-branch --branch $branch -- $repoRoot $clonePath
    Assert-ExitCode 'git clone'

    $cloneCommit = (& git -C $clonePath rev-parse HEAD).Trim()
    Assert-ExitCode 'read clone commit'
    if ($cloneCommit -ne $sourceCommit) {
        throw "Clone commit $cloneCommit differs from source commit $sourceCommit."
    }
    $trackedChanges = & git -C $clonePath status --porcelain
    Assert-ExitCode 'check fresh clone status'
    if ($trackedChanges) {
        throw "Fresh clone is not clean: $trackedChanges"
    }

    Push-Location $clonePath
    try {
        $nodeVersion = (& node --version).Trim()
        Assert-ExitCode 'node --version'
        $npmVersion = (& npm --version).Trim()
        Assert-ExitCode 'npm --version'
        $rustVersion = (& rustc --version).Trim()
        Assert-ExitCode 'rustc --version'
        $cargoVersion = (& cargo --version).Trim()
        Assert-ExitCode 'cargo --version'

        Write-Output "Tool versions: Node $nodeVersion; npm $npmVersion; $rustVersion; $cargoVersion"
        if ($nodeVersion -ne 'v24.22.0' -or $npmVersion -ne '11.19.1' -or
            $rustVersion -notmatch '^rustc 1\.99\.1 \(' -or
            $cargoVersion -notmatch '^cargo 1\.99\.1 \(') {
            throw 'Installed tool versions differ from the Gate 0A pins in docs/toolchain.md.'
        }

        Write-Output 'Installing locked JavaScript dependencies with npm ci...'
        & npm ci
        Assert-ExitCode 'npm ci'

        Write-Output 'Running frontend, contract, Rust, and design checks in the fresh clone...'
        & powershell -NoProfile -File scripts/verify-foundation.ps1
        Assert-ExitCode 'foundation verification'

        Write-Output "Clean-checkout verification passed at $cloneCommit."
    }
    finally {
        Pop-Location
    }
}
finally {
    if (Test-Path -LiteralPath $clonePath) {
        # Only the validated, uniquely named child of the system temp directory is removed.
        Remove-Item -LiteralPath $clonePath -Recurse -Force
    }
}
