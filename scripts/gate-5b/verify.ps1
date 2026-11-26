# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('mediastore-single')]
    [string]$Case
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$androidProject = Join-Path $root 'src-tauri\gen\android'
$gradle = Join-Path $androidProject 'gradlew.bat'
$logDirectory = Join-Path $root 'work\android\gate-5b'
$sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$pinnedJdk = Join-Path $root 'work\android\gate-5a\5a-03-cpython\host-tools\corretto-windows\jdk21.0.11_10'
if (-not (Test-Path -LiteralPath (Join-Path $pinnedJdk 'bin\java.exe') -PathType Leaf)) {
    throw 'The Gate 5A Corretto 21 JDK is missing; follow the recorded setup in docs/toolchain.md.'
}
$env:JAVA_HOME = (Resolve-Path -LiteralPath $pinnedJdk).Path
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
$env:ANDROID_HOME = $sdk
$env:ANDROID_SDK_ROOT = $sdk
$env:NDK_HOME = Join-Path $sdk 'ndk\30.0.16248370'
New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null

function Invoke-Logged {
    param(
        [string]$Name,
        [string]$Executable,
        [string[]]$Arguments
    )

    $log = Join-Path $logDirectory "$Case-$Name.log"
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $Executable @Arguments 2>&1 | Out-File -LiteralPath $log
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($exitCode -ne 0) {
        Get-Content -LiteralPath $log -Tail 50
        throw "$Name failed with exit code $exitCode. Full log: $log"
    }
    Get-Content -LiteralPath $log -Tail 12
}

Invoke-Logged -Name 'rust' -Executable 'cargo' -Arguments @(
    'test', '--manifest-path', (Join-Path $root 'src-tauri\Cargo.toml'),
    '--locked', '--lib', 'android_contract::tests'
)
Invoke-Logged -Name 'kotlin-unit' -Executable $gradle -Arguments @(
    '--no-daemon', '--project-dir', $androidProject, ':app:testArmDebugUnitTest',
    '--tests', 'com.zownload.app.MediaStoreOutputNamesTest'
)
Invoke-Logged -Name 'device-test-compile' -Executable $gradle -Arguments @(
    '--no-daemon', '--project-dir', $androidProject, ':app:compileArmDebugAndroidTestKotlin'
)

$cargoToml = Join-Path $root 'src-tauri\Cargo.toml'
$cargoOriginalBytes = [System.IO.File]::ReadAllBytes($cargoToml)
$cargoOriginalText = [System.Text.Encoding]::UTF8.GetString($cargoOriginalBytes)
$tauriGeneratedCargoText = $cargoOriginalText.Replace(
    'tauri-build = { version = "=2.7.3" }',
    'tauri-build = { version = "=2.7.3", features = [] }'
).Replace(
    'tauri = { version = "=2.12.4" }',
    'tauri = { version = "=2.12.4", features = [] }'
)
Push-Location $root
try {
    Invoke-Logged -Name 'android-debug-build' -Executable 'npm.cmd' -Arguments @('run', 'android:debug')
}
finally {
    Pop-Location
    $cargoCurrentText = [System.IO.File]::ReadAllText($cargoToml)
    if ($cargoCurrentText -ceq $tauriGeneratedCargoText) {
        [System.IO.File]::WriteAllBytes($cargoToml, $cargoOriginalBytes)
    }
}

$adb = Join-Path $sdk 'platform-tools\adb.exe'
if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) {
    throw 'Android platform-tools adb is required for the MediaStore device test.'
}
$connected = @(& $adb devices | Where-Object { $_ -match '^\S+\s+device$' })
if ($connected.Count -eq 0) {
    throw 'Connect an arm64 Android 10 (API 29) or newer device to run the MediaStore visibility test.'
}
$serial = $null
$api = $null
$abi = $null
foreach ($row in $connected) {
    $candidate = ($row -split '\s+')[0]
    $candidateApi = (& $adb -s $candidate shell getprop ro.build.version.sdk | Out-String).Trim()
    $candidateAbi = (& $adb -s $candidate shell getprop ro.product.cpu.abi | Out-String).Trim()
    if ([int]$candidateApi -ge 29 -and $candidateAbi -eq 'arm64-v8a') {
        $serial = $candidate
        $api = $candidateApi
        $abi = $candidateAbi
        break
    }
}
if (-not $serial) { throw 'The connected devices do not include an arm64 Android 10 (API 29) or newer device.' }
$env:ANDROID_SERIAL = $serial
$booted = $false
for ($attempt = 0; $attempt -lt 120 -and -not $booted; $attempt++) {
    $booted = ((& $adb -s $serial shell getprop sys.boot_completed | Out-String).Trim() -eq '1')
    if (-not $booted) { Start-Sleep -Seconds 2 }
}
if (-not $booted) { throw "Android device '$serial' did not finish booting." }

Invoke-Logged -Name 'mediastore-device' -Executable $gradle -Arguments @(
    '--no-daemon', '--project-dir', $androidProject, '--no-configuration-cache',
    ':app:connectedUniversalDebugAndroidTest',
    '-x', ':app:rustBuildUniversalDebug',
    '-x', ':app:rustBuildArm64Debug',
    '-x', ':app:rustBuildArmDebug',
    '-x', ':app:rustBuildX86Debug',
    '-x', ':app:rustBuildX86_64Debug',
    '-Pandroid.testInstrumentationRunnerArguments.class=com.zownload.app.MediaStoreSingleOutputDeviceTest'
)
