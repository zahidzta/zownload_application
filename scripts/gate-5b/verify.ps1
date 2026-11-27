# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('mediastore-single', 'mediastore-zip', 'foreground-service', 'lifecycle-recovery', 'foreground-timeout')]
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

function Invoke-Instrumentation {
    param(
        [string]$Adb,
        [string]$Serial,
        [string]$ClassSpec,
        [string[]]$ExtraArgs = @(),
        [string]$LogName = 'device'
    )

    $testLog = Join-Path $logDirectory "$Case-$LogName.log"
    $testErr = Join-Path $logDirectory "$Case-$LogName-err.log"
    $args = @('-s', $Serial, 'shell', 'am', 'instrument', '-w', '-r', '-e', 'class', $ClassSpec) +
        $ExtraArgs +
        @('com.zownload.app.test/androidx.test.runner.AndroidJUnitRunner')
    $proc = Start-Process -FilePath $Adb -ArgumentList $args -PassThru `
        -RedirectStandardOutput $testLog -RedirectStandardError $testErr -WindowStyle Hidden
    $null = $proc.WaitForExit(300000)
    if (-not $proc.HasExited) {
        $proc.Kill()
        throw "Instrumentation $ClassSpec exceeded 5 minutes."
    }
    $report = Get-Content -LiteralPath $testLog -Raw
    if (-not $report.Contains('OK (') -or -not $report.Contains('INSTRUMENTATION_CODE: -1')) {
        Get-Content -LiteralPath $testLog -Tail 50
        throw "Instrumentation $ClassSpec failed. Full log: $testLog"
    }
    Get-Content -LiteralPath $testLog -Tail 10
}

function Reset-AppState {
    param([string]$Adb, [string]$Serial, [int]$Api)
    $cleared = (& $Adb -s $Serial shell pm clear com.zownload.app | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $cleared.Contains('Success')) {
        throw "Could not clear app state: $cleared"
    }
    if ($Api -ge 33) {
        & $Adb -s $Serial shell pm grant com.zownload.app android.permission.POST_NOTIFICATIONS | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw 'Could not grant POST_NOTIFICATIONS permission.'
        }
    }
}

function Select-PhysicalArm64Device {
    param([string]$Adb, [int]$MinApi = 29)
    $connected = @(& $Adb devices | Where-Object { $_ -match '^\S+\s+device$' })
    if ($connected.Count -eq 0) {
        throw 'Connect a physical arm64 Android device to run Gate 5B verification.'
    }
    foreach ($row in $connected) {
        $candidate = ($row -split '\s+')[0]
        $candidateApi = (& $Adb -s $candidate shell getprop ro.build.version.sdk | Out-String).Trim()
        $candidateAbi = (& $Adb -s $candidate shell getprop ro.product.cpu.abi | Out-String).Trim()
        $candidateQemu = (& $Adb -s $candidate shell getprop ro.kernel.qemu | Out-String).Trim()
        if ($candidateQemu -ne '1' -and [int]$candidateApi -ge $MinApi -and $candidateAbi -eq 'arm64-v8a') {
            return @{ Serial = $candidate; Api = [int]$candidateApi; Abi = $candidateAbi }
        }
    }
    return $null
}

Invoke-Logged -Name 'rust' -Executable 'cargo' -Arguments @(
    'test', '--manifest-path', (Join-Path $root 'src-tauri\Cargo.toml'),
    '--locked', '--lib', 'android_'
)
Invoke-Logged -Name 'kotlin-unit' -Executable $gradle -Arguments @(
    '--no-daemon', '--project-dir', $androidProject, ':app:testArmDebugUnitTest'
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

$apk = Join-Path $root 'src-tauri\gen\android\app\build\outputs\apk\universal\debug\app-universal-debug.apk'
$apkHash = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Output "Debug APK SHA-256: $apkHash"

$adb = Join-Path $sdk 'platform-tools\adb.exe'
if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) {
    throw 'Android platform-tools adb is required for Gate 5B device verification.'
}

$device = if ($Case -eq 'foreground-timeout') {
    $api35 = Select-PhysicalArm64Device -Adb $adb -MinApi 35
    if ($api35) { $api35 } else { Select-PhysicalArm64Device -Adb $adb -MinApi 29 }
} else {
    Select-PhysicalArm64Device -Adb $adb -MinApi 29
}
if (-not $device) {
    throw 'No physical arm64-v8a Android 10+ (API 29+) device is attached.'
}
$serial = $device.Serial
$api = $device.Api
$abi = $device.Abi
$model = (& $adb -s $serial shell getprop ro.product.model | Out-String).Trim()
$env:ANDROID_SERIAL = $serial
Write-Output "Selected device: $model serial=$serial API=$api ABI=$abi"

$booted = $false
for ($attempt = 0; $attempt -lt 60 -and -not $booted; $attempt++) {
    $booted = ((& $adb -s $serial shell getprop sys.boot_completed | Out-String).Trim() -eq '1')
    if (-not $booted) { Start-Sleep -Seconds 2 }
}
if (-not $booted) { throw "Android device '$serial' did not finish booting." }

Invoke-Logged -Name 'android-test-apk' -Executable $gradle -Arguments @(
    '--no-daemon', '--project-dir', $androidProject, '--no-configuration-cache',
    ':app:assembleUniversalDebugAndroidTest',
    '-x', ':app:rustBuildUniversalDebug',
    '-x', ':app:rustBuildArm64Debug',
    '-x', ':app:rustBuildArmDebug',
    '-x', ':app:rustBuildX86Debug',
    '-x', ':app:rustBuildX86_64Debug'
)
$testApk = Join-Path $root 'src-tauri\gen\android\app\build\outputs\apk\androidTest\universal\debug\app-universal-debug-androidTest.apk'
foreach ($pkg in @($apk, $testApk)) {
    $installOut = (& $adb -s $serial install -r $pkg 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $installOut.Contains('Success')) {
        throw "Could not install $(Split-Path $pkg -Leaf): $installOut"
    }
}

if ($Case -eq 'mediastore-single') {
    Invoke-Instrumentation -Adb $adb -Serial $serial -ClassSpec 'com.zownload.app.MediaStoreSingleOutputDeviceTest'
    exit 0
}

$fixturePort = 18550
$fixtureLog = Join-Path $logDirectory "$Case-fixture-http.log"
if (Test-Path -LiteralPath $fixtureLog) { Remove-Item -LiteralPath $fixtureLog -Force }
$fixtureErrLog = Join-Path $logDirectory "$Case-fixture-http-err.log"
$fixtureProc = Start-Process -FilePath 'python' -ArgumentList @(
    (Join-Path $PSScriptRoot 'fixture-server.py'),
    '--port', "$fixturePort",
    '--rate-bps', '24000',
    '--log', $fixtureLog
) -PassThru -RedirectStandardOutput (Join-Path $logDirectory "$Case-fixture-stdout.log") `
  -RedirectStandardError $fixtureErrLog -WindowStyle Hidden

try {
    Start-Sleep -Seconds 1
    if ($fixtureProc.HasExited) {
        Get-Content -LiteralPath $fixtureErrLog -Tail 30
        throw 'Local HTTP fixture server failed to start.'
    }
    & $adb -s $serial reverse "tcp:$fixturePort" "tcp:$fixturePort" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'adb reverse failed for fixture port.' }

    $singleUrlB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("http://127.0.0.1:$fixturePort/long.mp3"))
    $playlistUrlB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("http://127.0.0.1:$fixturePort/playlist.xml"))

    if ($Case -eq 'mediastore-zip') {
        Reset-AppState -Adb $adb -Serial $serial -Api $api
        Invoke-Instrumentation -Adb $adb -Serial $serial `
            -ClassSpec 'com.zownload.app.MediaStoreZipOutputDeviceTest#pendingMediaStoreZipSupportsSeekableRwCollisionsAndCleanup' `
            -LogName 'zip-provider'
        Reset-AppState -Adb $adb -Serial $serial -Api $api
        Invoke-Instrumentation -Adb $adb -Serial $serial `
            -ClassSpec 'com.zownload.app.MediaStoreZipOutputDeviceTest#playlistZipDownloadsEndToEndThroughMediaStoreWithZeroLeftoverWorkFiles' `
            -ExtraArgs @('-e', 'playlistUrlB64', $playlistUrlB64) `
            -LogName 'zip-e2e'
    }
    elseif ($Case -eq 'foreground-service') {
        Reset-AppState -Adb $adb -Serial $serial -Api $api
        Invoke-Instrumentation -Adb $adb -Serial $serial `
            -ClassSpec 'com.zownload.app.ForegroundServiceProductionDeviceTest' `
            -ExtraArgs @('-e', 'singleUrlB64', $singleUrlB64)
    }
    elseif ($Case -eq 'lifecycle-recovery') {
        # Phase 1: Recents removal
        Reset-AppState -Adb $adb -Serial $serial -Api $api
        & $adb -s $serial logcat -c | Out-Null
        $recentsLog = Join-Path $logDirectory "$Case-recents-phase1.log"
        $recentsErr = Join-Path $logDirectory "$Case-recents-phase1-err.log"
        $recentsProc = Start-Process -FilePath $adb -ArgumentList @(
            '-s', $serial, 'shell', 'am', 'instrument', '-w', '-r',
            '-e', 'class', 'com.zownload.app.LifecycleRecoveryDeviceTest#recentsRemovalPausesQueueAndStopsService',
            '-e', 'singleUrlB64', $singleUrlB64,
            'com.zownload.app.test/androidx.test.runner.AndroidJUnitRunner'
        ) -PassThru -RedirectStandardOutput $recentsLog -RedirectStandardError $recentsErr -WindowStyle Hidden
        $null = $recentsProc.WaitForExit(180000)
        if (-not $recentsProc.HasExited) {
            $recentsProc.Kill()
            throw 'Recents removal phase 1 timed out.'
        }
        Start-Sleep -Seconds 2
        $appPids = (& $adb -s $serial shell ps -A | Select-String 'com\.zownload\.app|libqjs|libffmpeg' | Out-String).Trim()
        if ($appPids) {
            Write-Output "Post-recents process check:`n$appPids"
        }
        $notifDump = (& $adb -s $serial shell dumpsys notification --noredact | Out-String)
        $activeNotifSection = if ($notifDump -match '(?s)Notification List:(.*?)(?:mArchive=|Snoozed notifications:|$)') {
            $Matches[1]
        } else {
            $notifDump
        }
        if ($activeNotifSection -match 'pkg=com\.zownload\.app.*id=1001') {
            throw 'Notification 1001 remained active after recents removal.'
        }
        Invoke-Instrumentation -Adb $adb -Serial $serial `
            -ClassSpec 'com.zownload.app.LifecycleRecoveryDeviceTest#verifyPausedAfterRecentsAndCleanUp' `
            -LogName 'recents-phase2'

        # Phase 2: Process death & .part resume
        Reset-AppState -Adb $adb -Serial $serial -Api $api
        & $adb -s $serial logcat -c | Out-Null
        $deathLog = Join-Path $logDirectory "$Case-death-phase1.log"
        $deathErr = Join-Path $logDirectory "$Case-death-phase1-err.log"
        $deathProc = Start-Process -FilePath $adb -ArgumentList @(
            '-s', $serial, 'shell', 'am', 'instrument', '-w', '-r',
            '-e', 'class', 'com.zownload.app.LifecycleRecoveryDeviceTest#startDownloadForProcessDeath',
            '-e', 'singleUrlB64', $singleUrlB64,
            'com.zownload.app.test/androidx.test.runner.AndroidJUnitRunner'
        ) -PassThru -RedirectStandardOutput $deathLog -RedirectStandardError $deathErr -WindowStyle Hidden

        $sawPrekill = $false
        $deadline = (Get-Date).AddSeconds(120)
        while ((Get-Date) -lt $deadline) {
            if ($deathProc.HasExited) {
                Get-Content -LiteralPath $deathLog -Tail 40
                throw 'Process death phase 1 exited before PREKILL checkpoint.'
            }
            $logText = (& $adb -s $serial logcat -d -s 'Zownload5B05:I' '*:S' | Out-String)
            if ($logText.Contains('PREKILL')) {
                $sawPrekill = $true
                break
            }
            Start-Sleep -Milliseconds 500
        }
        if (-not $sawPrekill) {
            if (-not $deathProc.HasExited) { $deathProc.Kill() }
            throw 'Timed out waiting for PREKILL checkpoint.'
        }
        & $adb -s $serial shell am force-stop com.zownload.app | Out-Null
        $null = $deathProc.WaitForExit(15000)
        Start-Sleep -Seconds 2
        Invoke-Instrumentation -Adb $adb -Serial $serial `
            -ClassSpec 'com.zownload.app.LifecycleRecoveryDeviceTest#verifyProcessDeathRestoreAndContinue' `
            -LogName 'death-phase2'
        $httpText = Get-Content -LiteralPath $fixtureLog -Raw
        if (-not $httpText.Contains('range=bytes=')) {
            throw 'Expected HTTP Range request on Continue after process death.'
        }
    }
    elseif ($Case -eq 'foreground-timeout') {
        Reset-AppState -Adb $adb -Serial $serial -Api $api
        & $adb -s $serial logcat -c | Out-Null
        if ($api -ge 35) {
            $setting = 'data_sync_fgs_timeout_duration'
            $original = (& $adb -s $serial shell device_config get activity_manager $setting | Out-String).Trim()
            try {
                & $adb -s $serial shell device_config put activity_manager $setting 15000 | Out-Null
                Invoke-Instrumentation -Adb $adb -Serial $serial `
                    -ClassSpec 'com.zownload.app.ForegroundTimeoutProductionDeviceTest#android15SystemTimeoutPausesQueueAndPreservesPart' `
                    -ExtraArgs @('-e', 'singleUrlB64', $singleUrlB64)
            }
            finally {
                if ($original -eq 'null') {
                    & $adb -s $serial shell device_config delete activity_manager $setting | Out-Null
                } else {
                    & $adb -s $serial shell device_config put activity_manager $setting $original | Out-Null
                }
            }
        } else {
            Write-Output "NOTICE: Physical device $model is API $api (< 35); running live service timeout callback verification. Physical API 35 device sign-off remains required for AC-35."
            Invoke-Instrumentation -Adb $adb -Serial $serial `
                -ClassSpec 'com.zownload.app.ForegroundTimeoutProductionDeviceTest#simulatedTimeoutCallbackPausesQueueAndPreservesPart' `
                -ExtraArgs @('-e', 'singleUrlB64', $singleUrlB64)
        }
    }
}
finally {
    try { & $adb -s $serial reverse --remove "tcp:$fixturePort" | Out-Null } catch {}
    if ($fixtureProc -and -not $fixtureProc.HasExited) {
        try { $fixtureProc.Kill() } catch {}
    }
}
