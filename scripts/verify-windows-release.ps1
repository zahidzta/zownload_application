# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BundleRoot,

    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $true)]
    [string]$MinisignPath,

    [string]$LatestJsonPath,

    [string[]]$ReleaseAssets = @(),

    [string]$ExpectedVersion,

    [string]$PublicKey,

    [switch]$SkipSignatures
)

$ErrorActionPreference = 'Stop'

function Get-OnlyPackage([string]$Directory, [string]$Filter, [string]$Description) {
    $matches = @(Get-ChildItem -LiteralPath $Directory -File -Filter $Filter)
    if ($matches.Count -ne 1) {
        throw "Expected exactly one $Description package in $Directory; found $($matches.Count)."
    }

    return $matches[0]
}

function Assert-OnlyFiles([string]$Directory, [string[]]$ExpectedNames) {
    $artifactExtensions = @('.exe', '.msi', '.sig', '.appx', '.msix', '.zip', '.dmg', '.deb', '.rpm', '.appimage', '.apk', '.aab')
    $actualNames = @(Get-ChildItem -LiteralPath $Directory -File |
        Where-Object { $artifactExtensions -contains $_.Extension.ToLowerInvariant() } |
        ForEach-Object Name | Sort-Object)
    $expectedSorted = @($ExpectedNames | Sort-Object)
    if (($actualNames -join "`n") -ne ($expectedSorted -join "`n")) {
        throw "Unexpected files in $Directory. Expected: $($expectedSorted -join ', '); found: $($actualNames -join ', ')."
    }
}

function Invoke-MinisinVerify([string]$Path, [string]$SignaturePath, [string]$PublicKeyPath) {
    # Capture expected signature failures as process results. This also avoids
    # PowerShell 5.1 promoting Minisign's stderr into a terminating error.
    $result = Start-Process -FilePath $MinisignPath -ArgumentList @(
        '-V', '-m', ('"' + $Path + '"'), '-x', ('"' + $SignaturePath + '"'), '-p', ('"' + $PublicKeyPath + '"')
    ) -WindowStyle Hidden -Wait -PassThru `
        -RedirectStandardOutput (Join-Path $verificationDirectory 'minisign.out.log') `
        -RedirectStandardError (Join-Path $verificationDirectory 'minisign.err.log')
    return $result.ExitCode
}

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$version = if ($ExpectedVersion) { $ExpectedVersion } else { [string]$config.version }
$root = (Resolve-Path -LiteralPath $BundleRoot).Path
$bundleDirectories = @(Get-ChildItem -LiteralPath $root -Directory | ForEach-Object Name | Sort-Object)
if (($bundleDirectories -join "`n") -ne "msi`nnsis") {
    throw "The Windows release build may contain only NSIS and MSI bundle directories; found: $($bundleDirectories -join ', ')."
}
$nsisDirectory = Join-Path $root 'nsis'
$msiDirectory = Join-Path $root 'msi'

if (!(Test-Path -LiteralPath $nsisDirectory) -or !(Test-Path -LiteralPath $msiDirectory)) {
    throw 'The Windows build must contain both NSIS and MSI bundle directories.'
}

$nsis = Get-OnlyPackage $nsisDirectory '*-setup.exe' 'NSIS'
$msi = Get-OnlyPackage $msiDirectory '*.msi' 'MSI'
if ($nsis.Name -notlike "*_$version`_*-setup.exe" -or $msi.Name -notlike "*_$version`_*.msi") {
    throw "The package filenames do not contain the expected version $version."
}

if ($SkipSignatures) {
    Assert-OnlyFiles $nsisDirectory @($nsis.Name)
    Assert-OnlyFiles $msiDirectory @($msi.Name)
    Write-Output "Windows x64 package allowlist passed for version $version (unsigned pull-request build)."
    return
}

if (!$PublicKey) {
    $PublicKey = [string]$config.plugins.updater.pubkey
}
if ([string]::IsNullOrWhiteSpace($PublicKey)) {
    throw 'The updater public key is missing from the Tauri configuration.'
}

$nsisSignaturePath = $nsis.FullName + '.sig'
$msiSignaturePath = $msi.FullName + '.sig'
foreach ($path in @($nsisSignaturePath, $msiSignaturePath)) {
    if (!(Test-Path -LiteralPath $path)) {
        throw "Missing updater signature for $([IO.Path]::GetFileNameWithoutExtension($path))."
    }
}
Assert-OnlyFiles $nsisDirectory @($nsis.Name, [IO.Path]::GetFileName($nsisSignaturePath))
Assert-OnlyFiles $msiDirectory @($msi.Name, [IO.Path]::GetFileName($msiSignaturePath))

$verificationDirectory = Join-Path $env:TEMP ('zownload-release-verify-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $verificationDirectory | Out-Null
try {
    $publicKeyPath = Join-Path $verificationDirectory 'updater.pub'
    $publicKeyText = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($PublicKey))
    [IO.File]::WriteAllText($publicKeyPath, $publicKeyText, [Text.UTF8Encoding]::new($false))

    $packages = @(
        [pscustomobject]@{ Name = 'NSIS'; Package = $nsis; Signature = $nsisSignaturePath },
        [pscustomobject]@{ Name = 'MSI'; Package = $msi; Signature = $msiSignaturePath }
    )
    foreach ($item in $packages) {
        $signatureText = [IO.File]::ReadAllText($item.Signature).Trim()
        $decodedSignature = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($signatureText))
        $minisignSignature = Join-Path $verificationDirectory ($item.Name + '.minisig')
        [IO.File]::WriteAllText($minisignSignature, $decodedSignature, [Text.UTF8Encoding]::new($false))

        if ((Invoke-MinisinVerify $item.Package.FullName $minisignSignature $publicKeyPath) -ne 0) {
            throw "The $($item.Name) updater signature did not verify."
        }

        $tamperedPath = Join-Path $verificationDirectory $item.Package.Name
        [IO.File]::Copy($item.Package.FullName, $tamperedPath, $true)
        $stream = [IO.File]::Open($tamperedPath, [IO.FileMode]::Append, [IO.FileAccess]::Write)
        try {
            $changedByte = [byte[]]@(0)
            $stream.Write($changedByte, 0, 1)
        }
        finally {
            $stream.Dispose()
        }

        if ((Invoke-MinisinVerify $tamperedPath $minisignSignature $publicKeyPath) -eq 0) {
            throw "The $($item.Name) signature accepted a tampered package."
        }
        [IO.File]::Delete($tamperedPath)
        Write-Output "$($item.Name) signature verified; tampered package rejected."
    }

    if ($LatestJsonPath) {
        $latest = Get-Content -LiteralPath $LatestJsonPath -Raw | ConvertFrom-Json
        if ([string]$latest.version -ne $version) {
            throw "latest.json version '$($latest.version)' does not match package version $version."
        }

        $platforms = $latest.platforms
        $platformNames = @($platforms.PSObject.Properties.Name)
        $unsupported = @($platformNames | Where-Object { $_ -notmatch '^windows-x86_64(?:-[a-z0-9]+)?$' })
        if ($unsupported.Count -gt 0) {
            throw "latest.json contains unsupported platform entries: $($unsupported -join ', ')."
        }

        foreach ($entry in @(
            [pscustomobject]@{ Key = 'windows-x86_64-nsis'; Package = $nsis; Signature = $nsisSignaturePath },
            [pscustomobject]@{ Key = 'windows-x86_64-msi'; Package = $msi; Signature = $msiSignaturePath }
        )) {
            $property = $platforms.PSObject.Properties[$entry.Key]
            if (!$property) {
                throw "latest.json is missing its $($entry.Key) entry."
            }
            $platform = $property.Value
            $uri = [Uri]$platform.url
            if ([IO.Path]::GetFileName($uri.AbsolutePath) -ne $entry.Package.Name) {
                throw "The $($entry.Key) entry does not point to its matching package."
            }
            if ([string]$platform.signature -ne [IO.File]::ReadAllText($entry.Signature).Trim()) {
                throw "The $($entry.Key) metadata signature does not match its package signature."
            }
        }

        $genericWindows = $platforms.PSObject.Properties['windows-x86_64']
        if ($genericWindows -and [IO.Path]::GetFileName(([Uri]$genericWindows.Value.url).AbsolutePath) -ne $msi.Name) {
            throw 'The generic Windows x64 updater entry must retain the MSI fallback.'
        }

        Write-Output 'latest.json contains matching NSIS and MSI entries and no non-Windows targets.'

        if ($ReleaseAssets.Count -gt 0) {
            $expectedAssets = @(
                $nsis.Name,
                [IO.Path]::GetFileName($nsisSignaturePath),
                $msi.Name,
                [IO.Path]::GetFileName($msiSignaturePath),
                'latest.json'
            ) | Sort-Object
            $actualAssets = @($ReleaseAssets | Sort-Object)
            if (($actualAssets -join "`n") -ne ($expectedAssets -join "`n")) {
                throw "Draft release assets do not match the Windows x64 allowlist. Found: $($actualAssets -join ', ')."
            }
            Write-Output 'Draft release asset allowlist passed.'
        }
    }
}
finally {
    Get-ChildItem -LiteralPath $verificationDirectory -File | ForEach-Object {
        [IO.File]::Delete($_.FullName)
    }
    Remove-Item -LiteralPath $verificationDirectory -Force
}

# Signature checks include expected nonzero Minisign exits. Report the
# verifier's success only after all checks and cleanup have completed; failures
# above still throw before reaching this exit and remain failures in Actions.
exit 0
