# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta

[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$MinisignPath)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$verifier = Join-Path $PSScriptRoot 'verify-windows-release.ps1'
$fixtures = Join-Path $repoRoot 'tests/fixtures/app-updates'
$shellPath = (Get-Process -Id $PID).Path
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('zownload-release-exit-' + [guid]::NewGuid().ToString('N'))
$bundleRoot = Join-Path $testRoot 'bundle'
$configPath = Join-Path $testRoot 'config.json'
$wrapperPath = Join-Path $testRoot 'actions-wrapper.ps1'
$nsisPath = Join-Path $bundleRoot 'nsis/Zownload_0.0.1_x64-setup.exe'
$msiPath = Join-Path $bundleRoot 'msi/Zownload_0.0.1_x64_en-US.msi'

function Assert-VerifierExit([string]$Name, [bool]$Success, [string]$ExpectedText, [string]$Metadata = '') {
    $outputPath = Join-Path $testRoot "$Name.out.log"
    $errorPath = Join-Path $testRoot "$Name.err.log"
    $arguments = @('-NoProfile', '-File') + @(
        $wrapperPath, $verifier, $bundleRoot, $configPath, $MinisignPath
    ).ForEach({ '"' + $_ + '"' })
    if ($Metadata) { $arguments += @('-LatestJsonPath', ('"' + $Metadata + '"')) }
    $process = Start-Process -FilePath $shellPath -ArgumentList $arguments `
        -WindowStyle Hidden -Wait -PassThru `
        -RedirectStandardOutput $outputPath -RedirectStandardError $errorPath
    $output = [IO.File]::ReadAllText($outputPath) + [IO.File]::ReadAllText($errorPath)
    if (($process.ExitCode -eq 0) -ne $Success -or !$output.Contains($ExpectedText)) {
        throw "$Name returned exit $($process.ExitCode): $output"
    }
    Write-Output "$Name passed (exit $($process.ExitCode))."
}

try {
    foreach ($package in @($nsisPath, $msiPath)) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $package) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $fixtures 'update-fixture.bin') -Destination $package
        Copy-Item -LiteralPath (Join-Path $fixtures 'update-fixture.bin.sig') -Destination ($package + '.sig')
    }
    @{
        version = '0.0.1'
        plugins = @{ updater = @{ pubkey = [IO.File]::ReadAllText((Join-Path $fixtures 'test-key.pub')).Trim() } }
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $configPath -Encoding utf8

    # Reproduce the Actions footer, which propagates even an expected native
    # failure left in LASTEXITCODE. The caller must also continue after success.
    @'
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta
param($Verifier, $BundleRoot, $ConfigPath, $MinisignPath, $LatestJsonPath)
$ErrorActionPreference = 'Stop'
$nsis = Get-ChildItem -LiteralPath (Join-Path $BundleRoot 'nsis') -File -Filter '*-setup.exe' | Select-Object -First 1
$msi = Get-ChildItem -LiteralPath (Join-Path $BundleRoot 'msi') -File -Filter '*.msi' | Select-Object -First 1
$assetMap = @{
    '1001' = $nsis.Name
    '1002' = $msi.Name
}
& $Verifier -BundleRoot $BundleRoot -ConfigPath $ConfigPath -MinisignPath $MinisignPath `
    -LatestJsonPath $LatestJsonPath -ReleaseAssetMap $assetMap
Write-Output 'Verifier returned to caller.'
if ((Test-Path -LiteralPath variable:\LASTEXITCODE)) { exit $LASTEXITCODE }
'@ | Set-Content -LiteralPath $wrapperPath -Encoding utf8

    Assert-VerifierExit 'valid-packages-and-rejected-tampering' $true 'Verifier returned to caller.'
    $metadata = Join-Path $testRoot 'latest.json'
    $nsisSignature = [IO.File]::ReadAllText($nsisPath + '.sig').Trim()
    $msiSignature = [IO.File]::ReadAllText($msiPath + '.sig').Trim()
    @{
        version = '0.0.1'
        platforms = @{
            'windows-x86_64' = @{
                signature = $msiSignature
                url = 'https://api.github.com/repos/zahidzta/zownload_application/releases/assets/1002'
            }
            'windows-x86_64-nsis' = @{
                signature = $nsisSignature
                url = 'https://api.github.com/repos/zahidzta/zownload_application/releases/assets/1001'
            }
            'windows-x86_64-msi' = @{
                signature = $msiSignature
                url = 'https://api.github.com/repos/zahidzta/zownload_application/releases/assets/1002'
            }
        }
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $metadata -Encoding utf8
    Assert-VerifierExit 'bundle-asset-api-urls-resolve-to-matching-packages' $true `
        'latest.json contains matching NSIS and MSI entries' $metadata

    '{"version":"9.9.9"}' | Set-Content -LiteralPath $metadata -Encoding utf8
    Assert-VerifierExit 'invalid-metadata-after-signature-checks' $false 'does not match package version' $metadata
    [IO.File]::WriteAllText($nsisPath, 'tampered package')
    Assert-VerifierExit 'invalid-package-signature' $false 'updater signature did not verify'
}
finally {
    # Only remove this test's uniquely named child of the OS temporary folder.
    $resolved = [IO.Path]::GetFullPath($testRoot)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (!$resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Refusing to clean a release test directory outside the temporary folder.'
    }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
