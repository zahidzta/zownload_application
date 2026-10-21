# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('library-audit', 'engine-package', 'engine-reintegration', 'quickjs-device', 'youtube-mp3', 'foreground-service', 'home', 'recents')]
    [string]$Case
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($Case -eq 'recents') {
    try {
        $root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        if (-not $env:ANDROID_SERIAL) { throw 'Set ANDROID_SERIAL to the physical arm64 device serial.' }
        if (-not $env:ZOWNLOAD_ANDROID_LONG_URL) { throw 'Set ZOWNLOAD_ANDROID_LONG_URL to the approved rights-cleared long YouTube single.' }
        $url = [uri]$env:ZOWNLOAD_ANDROID_LONG_URL
        if ($url.Scheme -ne 'https' -or $url.Host -notin @('www.youtube.com', 'youtu.be')) {
            throw 'ZOWNLOAD_ANDROID_LONG_URL must be an HTTPS YouTube single.'
        }
        $sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
        $adb = Join-Path $sdk 'platform-tools/adb.exe'
        if (-not (Test-Path -LiteralPath $adb)) { throw "adb is missing: $adb" }
        $serial = $env:ANDROID_SERIAL
        $state = (& $adb -s $serial get-state 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $state -ne 'device') { throw "Device is not connected: $state" }
        $abi = (& $adb -s $serial shell getprop ro.product.cpu.abi | Out-String).Trim()
        $api = (& $adb -s $serial shell getprop ro.build.version.sdk | Out-String).Trim()
        $model = (& $adb -s $serial shell getprop ro.product.model | Out-String).Trim()
        $webView = (& $adb -s $serial shell dumpsys webviewupdate | Select-String 'Current WebView package' | Out-String).Trim()
        if ($abi -ne 'arm64-v8a' -or [int]$api -lt 24) { throw "Requires physical arm64 API 24+; found $abi API $api" }
        $logs = Join-Path $root 'work/android/0c-10'
        New-Item -ItemType Directory -Force -Path $logs | Out-Null
        $env:ANDROID_HOME = $sdk
        Push-Location $root
        try {
            $buildLog = Join-Path $logs 'android-build.log'
            $prior = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            try { & npm.cmd run android:debug 2>&1 | Out-File $buildLog }
            finally { $ErrorActionPreference = $prior }
            if ($LASTEXITCODE -ne 0) { throw "Android build failed:`n$((Get-Content $buildLog | Select-Object -Last 50) -join "`n")" }
        } finally { Pop-Location }
        $apk = Join-Path $root 'src-tauri/gen/android/app/build/outputs/apk/universal/debug/app-universal-debug.apk'
        if (-not (Test-Path -LiteralPath $apk)) { throw 'Android debug APK was not produced.' }
        Push-Location (Join-Path $root 'src-tauri/gen/android')
        try {
            $testBuildLog = Join-Path $logs 'android-test-build.log'
            $prior = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            try { & .\gradlew.bat :app:assembleUniversalDebugAndroidTest --no-configuration-cache `
                    -x :app:rustBuildUniversalDebug -x :app:rustBuildArm64Debug `
                    -x :app:rustBuildArmDebug -x :app:rustBuildX86Debug `
                    -x :app:rustBuildX86_64Debug 2>&1 | Out-File $testBuildLog }
            finally { $ErrorActionPreference = $prior }
            if ($LASTEXITCODE -ne 0) { throw "Android test build failed:`n$((Get-Content $testBuildLog | Select-Object -Last 50) -join "`n")" }
        } finally { Pop-Location }
        $testApk = Join-Path $root 'src-tauri/gen/android/app/build/outputs/apk/androidTest/universal/debug/app-universal-debug-androidTest.apk'
        if (-not (Test-Path -LiteralPath $testApk)) { throw 'Android instrumentation APK was not produced.' }
        foreach ($package in @($apk, $testApk)) {
            $installed = $false
            for ($attempt = 1; $attempt -le 3; $attempt++) {
                $prior = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
                try { $installReport = (& $adb -s $serial install -r $package 2>&1 | Out-String).Trim() }
                finally { $ErrorActionPreference = $prior }
                if ($LASTEXITCODE -eq 0 -and $installReport.Contains('Success')) { $installed = $true; break }
                Start-Sleep -Seconds 3
            }
            if (-not $installed) { throw "Could not install $(Split-Path $package -Leaf) after 3 attempts: $installReport" }
        }
        $cleared = (& $adb -s $serial shell pm clear com.zownload.app | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $cleared -ne 'Success') { throw "Could not clear prior spike queue: $cleared" }
        & $adb -s $serial logcat -c | Out-Null
        $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($url.AbsoluteUri))
        $testLog = Join-Path $logs 'device-test.log'
        & $adb -s $serial shell am instrument -w -r -e class 'com.zownload.app.RecentsRemovalDeviceTest#removingTaskPausesRustAndStopsEngineAndService' `
            -e youtubeUrlB64 $encoded 'com.zownload.app.test/androidx.test.runner.AndroidJUnitRunner' 2>&1 | Out-File $testLog
        $testOutput = Get-Content $testLog -Raw
        if (-not $testOutput.Contains('OK (1 test)') -and
                -not $testOutput.Contains('INSTRUMENTATION_RESULT: shortMsg=Process crashed.')) {
            throw "Task-removal phase failed:`n$((Get-Content $testLog | Select-Object -Last 50) -join "`n")"
        }
        $deviceLog = Join-Path $logs 'device-logcat.log'
        & $adb -s $serial logcat -d -s 'Zownload0C10:I' 'Zownload0C08:I' 'RustStdoutStderr:I' '*:S' | Out-File $deviceLog
        $report = Get-Content $deviceLog -Raw
        foreach ($term in @('RECENTS_REMOVING', 'TASK_REMOVED', 'RUST_PAUSED_ON_TASK_REMOVAL', 'ENGINE_CANCEL', 'RUST_SERVICE_STOP_REQUESTED', 'SERVICE_STOPPED')) {
            if (-not $report.Contains($term)) { throw "Device log lacks proof: $term" }
        }
        $proof = [regex]::Match($report, 'RECENTS_REMOVING at=\S+ item=([a-f0-9-]+) percent=([\d.]+) children=\[([0-9, ]+)\] bytes=(\d+)')
        if (-not $proof.Success -or [long]$proof.Groups[4].Value -le 0 -or
                -not $report.Contains('ENGINE_CANCEL') -or -not $report.Contains('workerExited=true')) {
            throw 'Task removal lacks active child, partial media, or completed engine cancellation proof.'
        }
        $processes = & $adb -s $serial shell ps -A -o PID,PPID,NAME | Out-String
        $livePids = @([regex]::Matches($processes, '(?m)^\s*(\d+)\s+') | ForEach-Object { $_.Groups[1].Value })
        foreach ($childPid in ($proof.Groups[3].Value -split ',\s*')) {
            if ($childPid -in $livePids) { throw "Engine child PID $childPid survived task removal." }
        }
        $notifications = & $adb -s $serial shell dumpsys notification --noredact | Out-String
        $activeNotifications = ($notifications -split 'mArchive=Archive')[0]
        if ($activeNotifications.Contains('StatusBarNotification(pkg=com.zownload.app user=UserHandle{0} id=108')) {
            throw 'Foreground-service notification 108 remained active.'
        }
        $filesAfter = (& $adb -s $serial shell run-as com.zownload.app find cache/zownload-0c-06 -type f 2>&1 | Out-String).Trim()
        Start-Sleep -Seconds 2
        $filesLater = (& $adb -s $serial shell run-as com.zownload.app find cache/zownload-0c-06 -type f 2>&1 | Out-String).Trim()
        if ($filesAfter -ne '' -or $filesLater -ne '') { throw "Private media remained or grew after cancellation: $filesLater" }
        $reopenLog = Join-Path $logs 'reopen-test.log'
        & $adb -s $serial shell am instrument -w -r -e class 'com.zownload.app.RecentsRemovalDeviceTest#reopenedQueueIsPaused' `
            'com.zownload.app.test/androidx.test.runner.AndroidJUnitRunner' 2>&1 | Out-File $reopenLog
        $reopenOutput = Get-Content $reopenLog -Raw
        if ($LASTEXITCODE -ne 0 -or -not $reopenOutput.Contains('OK (1 test)')) {
            throw "Reopen phase failed:`n$((Get-Content $reopenLog | Select-Object -Last 50) -join "`n")"
        }
        & $adb -s $serial logcat -d -s 'Zownload0C10:I' 'Zownload0C08:I' 'RustStdoutStderr:I' '*:S' | Out-File $deviceLog
        $report = Get-Content $deviceLog -Raw
        if (-not $report.Contains("REOPENED_PAUSED item=$($proof.Groups[1].Value)")) {
            throw 'Reopened get_queue did not return the same paused item.'
        }
        $apkHash = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
        Write-Output "0C-10 recents: PASS; $model API $api $abi serial $serial."
        Write-Output "WebView: $webView; APK SHA-256: $apkHash; child PIDs absent, no private media files, notification absent."
        Write-Output 'Local feasibility only; Android distribution remains blocked.'
        Get-Content $deviceLog | Where-Object { $_ -match 'RECENTS_REMOVING|TASK_REMOVED|RUST_PAUSED_ON_TASK_REMOVAL|ENGINE_CANCEL|SERVICE_STOPPED|REOPENED_PAUSED' } | Select-Object -Last 20
        exit 0
    } catch {
        Write-Error "0C-10 recents: FAIL: $($_.Exception.Message)"
        exit 1
    }
}

if ($Case -eq 'home') {
    try {
        $root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        if (-not $env:ANDROID_SERIAL) { throw 'Set ANDROID_SERIAL to the physical arm64 device serial.' }
        if (-not $env:ZOWNLOAD_ANDROID_LONG_URL) { throw 'Set ZOWNLOAD_ANDROID_LONG_URL to the approved rights-cleared long YouTube single.' }
        $url = [uri]$env:ZOWNLOAD_ANDROID_LONG_URL
        if ($url.Scheme -ne 'https' -or $url.Host -notin @('www.youtube.com', 'youtu.be')) {
            throw 'ZOWNLOAD_ANDROID_LONG_URL must be an HTTPS YouTube single.'
        }
        $sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
        $adb = Join-Path $sdk 'platform-tools/adb.exe'
        if (-not (Test-Path -LiteralPath $adb)) { throw "adb is missing: $adb" }
        $serial = $env:ANDROID_SERIAL
        $state = (& $adb -s $serial get-state 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $state -ne 'device') { throw "Device is not connected: $state" }
        $abi = (& $adb -s $serial shell getprop ro.product.cpu.abi | Out-String).Trim()
        $api = (& $adb -s $serial shell getprop ro.build.version.sdk | Out-String).Trim()
        $model = (& $adb -s $serial shell getprop ro.product.model | Out-String).Trim()
        $webView = (& $adb -s $serial shell dumpsys webviewupdate | Select-String 'Current WebView package' | Out-String).Trim()
        if ($abi -ne 'arm64-v8a' -or [int]$api -lt 24) { throw "Requires physical arm64 API 24+; found $abi API $api" }
        $logs = Join-Path $root 'work/android/0c-09'
        New-Item -ItemType Directory -Force -Path $logs | Out-Null
        $env:ANDROID_HOME = $sdk
        Push-Location $root
        try {
            $buildLog = Join-Path $logs 'android-build.log'
            $prior = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            try { & npm.cmd run android:debug 2>&1 | Out-File $buildLog }
            finally { $ErrorActionPreference = $prior }
            if ($LASTEXITCODE -ne 0) { throw "Android build failed:`n$((Get-Content $buildLog | Select-Object -Last 50) -join "`n")" }
        } finally { Pop-Location }
        $apk = Join-Path $root 'src-tauri/gen/android/app/build/outputs/apk/universal/debug/app-universal-debug.apk'
        if (-not (Test-Path -LiteralPath $apk)) { throw 'Android debug APK was not produced.' }
        Push-Location (Join-Path $root 'src-tauri/gen/android')
        try {
            $testBuildLog = Join-Path $logs 'android-test-build.log'
            $prior = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            try { & .\gradlew.bat :app:assembleUniversalDebugAndroidTest --no-configuration-cache `
                    -x :app:rustBuildUniversalDebug -x :app:rustBuildArm64Debug `
                    -x :app:rustBuildArmDebug -x :app:rustBuildX86Debug `
                    -x :app:rustBuildX86_64Debug 2>&1 | Out-File $testBuildLog }
            finally { $ErrorActionPreference = $prior }
            if ($LASTEXITCODE -ne 0) { throw "Android test build failed:`n$((Get-Content $testBuildLog | Select-Object -Last 50) -join "`n")" }
        } finally { Pop-Location }
        $testApk = Join-Path $root 'src-tauri/gen/android/app/build/outputs/apk/androidTest/universal/debug/app-universal-debug-androidTest.apk'
        if (-not (Test-Path -LiteralPath $testApk)) { throw 'Android instrumentation APK was not produced.' }
        foreach ($package in @($apk, $testApk)) {
            $installed = $false
            for ($attempt = 1; $attempt -le 3; $attempt++) {
                $prior = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
                try { $installReport = (& $adb -s $serial install -r $package 2>&1 | Out-String).Trim() }
                finally { $ErrorActionPreference = $prior }
                if ($LASTEXITCODE -eq 0 -and $installReport.Contains('Success')) { $installed = $true; break }
                Start-Sleep -Seconds 3
            }
            if (-not $installed) { throw "Could not install $(Split-Path $package -Leaf) after 3 attempts: $installReport" }
        }
        & $adb -s $serial logcat -c | Out-Null
        $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($url.AbsoluteUri))
        $testLog = Join-Path $logs 'device-test.log'
        & $adb -s $serial shell am instrument -w -r -e class 'com.zownload.app.HomeContinuationDeviceTest#rustQueueAndEngineAdvanceForThreeMinutesAfterHome' `
            -e youtubeUrlB64 $encoded 'com.zownload.app.test/androidx.test.runner.AndroidJUnitRunner' 2>&1 | Out-File $testLog
        $testOutput = Get-Content $testLog -Raw
        if ($LASTEXITCODE -ne 0 -or -not $testOutput.Contains('OK (1 test)')) {
            throw "Device test failed:`n$((Get-Content $testLog | Select-Object -Last 50) -join "`n")"
        }
        $deviceLog = Join-Path $logs 'device-logcat.log'
        & $adb -s $serial logcat -d -s 'Zownload0C09:I' 'Zownload0C08:I' 'RustStdoutStderr:I' '*:S' | Out-File $deviceLog
        $report = Get-Content $deviceLog -Raw
        foreach ($term in @('HOME_SAMPLE at=', 'RUST_PROGRESS item=', 'HOME_TEST_OK start=')) {
            if (-not $report.Contains($term)) { throw "Device log lacks proof: $term" }
        }
        $proof = [regex]::Match($report, 'HOME_TEST_OK start=(\S+) end=(\S+) elapsedMs=(\d+) item=([a-f0-9-]+) startPercent=([\d.]+) endPercent=([\d.]+) changes=(\d+) samples=(\d+) notification=true home=true')
        if (-not $proof.Success -or [long]$proof.Groups[3].Value -lt 180000 -or [int]$proof.Groups[7].Value -lt 2 -or
                [double]$proof.Groups[6].Value -le [double]$proof.Groups[5].Value) {
            throw 'Final Home record does not prove three minutes and changing durable progress.'
        }
        $screenshot = Join-Path $logs 'home-notification.png'
        & $adb -s $serial pull '/sdcard/zownload-0c09-home.png' $screenshot | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $screenshot)) { throw 'Notification screenshot is missing.' }
        & $adb -s $serial shell rm '/sdcard/zownload-0c09-home.png' | Out-Null
        $apkHash = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
        Write-Output "0C-09 home: PASS; $model API $api $abi serial $serial."
        Write-Output "WebView: $webView; APK SHA-256: $apkHash."
        Write-Output "Home and notification-icon screenshot: $screenshot; local feasibility only; Android distribution remains blocked."
        Get-Content $deviceLog | Where-Object { $_ -match 'HOME_PRESSED|HOME_SAMPLE|HOME_TEST_OK' } | Select-Object -Last 15
        exit 0
    } catch {
        Write-Error "0C-09 home: FAIL: $($_.Exception.Message)"
        exit 1
    }
}

if ($Case -eq 'foreground-service') {
    try {
        $root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        if (-not $env:ANDROID_SERIAL) { throw 'Set ANDROID_SERIAL to the physical arm64 device serial.' }
        if (-not $env:ZOWNLOAD_ANDROID_YOUTUBE_URL) { throw 'Set ZOWNLOAD_ANDROID_YOUTUBE_URL to the approved real YouTube single.' }
        $url = [uri]$env:ZOWNLOAD_ANDROID_YOUTUBE_URL
        if ($url.Scheme -ne 'https' -or $url.Host -notin @('www.youtube.com', 'youtu.be')) {
            throw 'ZOWNLOAD_ANDROID_YOUTUBE_URL must be an HTTPS YouTube single.'
        }
        $sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
        $adb = Join-Path $sdk 'platform-tools/adb.exe'
        if (-not (Test-Path -LiteralPath $adb)) { throw "adb is missing: $adb" }
        $serial = $env:ANDROID_SERIAL
        $state = (& $adb -s $serial get-state 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $state -ne 'device') { throw "Device is not connected: $state" }
        $abi = (& $adb -s $serial shell getprop ro.product.cpu.abi | Out-String).Trim()
        $api = (& $adb -s $serial shell getprop ro.build.version.sdk | Out-String).Trim()
        $model = (& $adb -s $serial shell getprop ro.product.model | Out-String).Trim()
        if ($abi -ne 'arm64-v8a' -or [int]$api -lt 24) { throw "Requires physical arm64 API 24+; found $abi API $api" }
        $logs = Join-Path $root 'work/android/0c-08'
        New-Item -ItemType Directory -Force -Path $logs | Out-Null
        $env:ANDROID_HOME = $sdk
        Push-Location $root
        try {
            $buildLog = Join-Path $logs 'android-build.log'
            $prior = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            try { & npm.cmd run android:debug 2>&1 | Out-File $buildLog }
            finally { $ErrorActionPreference = $prior }
            if ($LASTEXITCODE -ne 0) { throw "Android build failed:`n$((Get-Content $buildLog | Select-Object -Last 50) -join "`n")" }
        } finally { Pop-Location }
        $apk = Join-Path $root 'src-tauri/gen/android/app/build/outputs/apk/universal/debug/app-universal-debug.apk'
        if (-not (Test-Path -LiteralPath $apk)) { throw 'Android debug APK was not produced.' }
        Push-Location (Join-Path $root 'src-tauri/gen/android')
        try {
            $testBuildLog = Join-Path $logs 'android-test-build.log'
            $prior = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            try { & .\gradlew.bat :app:assembleUniversalDebugAndroidTest --no-configuration-cache `
                    -x :app:rustBuildUniversalDebug -x :app:rustBuildArm64Debug `
                    -x :app:rustBuildArmDebug -x :app:rustBuildX86Debug `
                    -x :app:rustBuildX86_64Debug 2>&1 | Out-File $testBuildLog }
            finally { $ErrorActionPreference = $prior }
            if ($LASTEXITCODE -ne 0) { throw "Android test build failed:`n$((Get-Content $testBuildLog | Select-Object -Last 50) -join "`n")" }
        } finally { Pop-Location }
        $testApk = Join-Path $root 'src-tauri/gen/android/app/build/outputs/apk/androidTest/universal/debug/app-universal-debug-androidTest.apk'
        if (-not (Test-Path -LiteralPath $testApk)) { throw 'Android instrumentation APK was not produced.' }
        & $adb -s $serial install -r $apk | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not install the app APK.' }
        & $adb -s $serial install -r $testApk | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not install the instrumentation APK.' }
        & $adb -s $serial logcat -c | Out-Null
        $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($url.AbsoluteUri))
        $testLog = Join-Path $logs 'device-test.log'
        & $adb -s $serial shell am instrument -w -r -e class 'com.zownload.app.ForegroundServiceDeviceTest#rustWorkShowsAndStopsDataSyncNotification' `
            -e youtubeUrlB64 $encoded 'com.zownload.app.test/androidx.test.runner.AndroidJUnitRunner' 2>&1 | Out-File $testLog
        if ($LASTEXITCODE -ne 0 -or -not ((Get-Content $testLog -Raw).Contains('OK (1 test)'))) {
            throw "Device test failed:`n$((Get-Content $testLog | Select-Object -Last 50) -join "`n")"
        }
        $deviceLog = Join-Path $logs 'device-logcat.log'
        & $adb -s $serial logcat -d -s 'Zownload0C08:I' 'RustStdoutStderr:I' '*:S' | Out-File $deviceLog
        $report = Get-Content $deviceLog -Raw
        foreach ($term in @('SERVICE_STARTED type=dataSync', 'RUST_SERVICE_STARTED', 'NOTIFICATION_OBSERVED active=true',
                'RUST_DOWNLOAD_CALLBACK', 'RUST_SERVICE_STOP_REQUESTED', 'SERVICE_STOPPED timedOut=false', 'SERVICE_TEST_OK')) {
            if (-not $report.Contains($term)) { throw "Device log lacks proof: $term" }
        }
        $apkHash = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
        Write-Output "0C-08 foreground-service: PASS; $model API $api $abi serial $serial."
        Write-Output "APK SHA-256: $apkHash; local feasibility only; Android distribution remains blocked."
        Get-Content $deviceLog | Where-Object { $_ -match 'SERVICE_STARTED|RUST_SERVICE_STARTED|NOTIFICATION_OBSERVED|RUST_DOWNLOAD_CALLBACK|RUST_SERVICE_STOP_REQUESTED|SERVICE_STOPPED|SERVICE_TEST_OK' } | Select-Object -Last 10
        exit 0
    } catch {
        Write-Error "0C-08 foreground-service: FAIL: $($_.Exception.Message)"
        exit 1
    }
}

if ($Case -eq 'youtube-mp3') {
    try {
        $root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        if (-not $env:ANDROID_SERIAL) { throw 'Set ANDROID_SERIAL to the physical arm64 device serial.' }
        if (-not $env:ZOWNLOAD_ANDROID_YOUTUBE_URL) { throw 'Set ZOWNLOAD_ANDROID_YOUTUBE_URL to the approved real YouTube single.' }
        $url = [uri]$env:ZOWNLOAD_ANDROID_YOUTUBE_URL
        if ($url.Scheme -ne 'https' -or $url.Host -notin @('www.youtube.com', 'youtu.be')) {
            throw 'ZOWNLOAD_ANDROID_YOUTUBE_URL must be an HTTPS YouTube single.'
        }
        $sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
        $adb = Join-Path $sdk 'platform-tools/adb.exe'
        if (-not (Test-Path -LiteralPath $adb)) { throw "adb is missing: $adb" }
        $env:ANDROID_HOME = $sdk
        $serial = $env:ANDROID_SERIAL
        $state = (& $adb -s $serial get-state 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $state -ne 'device') { throw "Device is not connected: $state" }
        $abi = (& $adb -s $serial shell getprop ro.product.cpu.abi | Out-String).Trim()
        $api = (& $adb -s $serial shell getprop ro.build.version.sdk | Out-String).Trim()
        $model = (& $adb -s $serial shell getprop ro.product.model | Out-String).Trim()
        if ($abi -ne 'arm64-v8a' -or [int]$api -lt 29) { throw "Requires physical arm64 API 29+; found $abi API $api" }
        $logs = Join-Path $root 'work/android/0c-06'
        New-Item -ItemType Directory -Force -Path $logs | Out-Null
        $buildLog = Join-Path $logs 'android-build.log'
        Push-Location $root
        try {
            $prior = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            try { & npm.cmd run android:debug 2>&1 | Out-File $buildLog }
            finally { $ErrorActionPreference = $prior }
            if ($LASTEXITCODE -ne 0) { throw "Android build failed:`n$((Get-Content $buildLog | Select-Object -Last 50) -join "`n")" }
        } finally { Pop-Location }
        $apk = Join-Path $root 'src-tauri/gen/android/app/build/outputs/apk/universal/debug/app-universal-debug.apk'
        if (-not (Test-Path -LiteralPath $apk)) { throw 'Android debug APK was not produced.' }
        $android = Join-Path $root 'src-tauri/gen/android'
        $testBuildLog = Join-Path $logs 'android-test-build.log'
        Push-Location $android
        try {
            $prior = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            try { & .\gradlew.bat :app:assembleUniversalDebugAndroidTest --no-configuration-cache `
                    -x :app:rustBuildUniversalDebug -x :app:rustBuildArm64Debug `
                    -x :app:rustBuildArmDebug -x :app:rustBuildX86Debug `
                    -x :app:rustBuildX86_64Debug 2>&1 | Out-File $testBuildLog }
            finally { $ErrorActionPreference = $prior }
            if ($LASTEXITCODE -ne 0) { throw "Android test build failed:`n$((Get-Content $testBuildLog | Select-Object -Last 50) -join "`n")" }
        } finally { Pop-Location }
        $testApk = Join-Path $root 'src-tauri/gen/android/app/build/outputs/apk/androidTest/universal/debug/app-universal-debug-androidTest.apk'
        if (-not (Test-Path -LiteralPath $testApk)) { throw 'Android instrumentation APK was not produced.' }
        & $adb -s $serial install -r $apk | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not install the app APK.' }
        & $adb -s $serial install -r $testApk | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not install the instrumentation APK.' }
        & $adb -s $serial logcat -c | Out-Null
        $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($url.AbsoluteUri))
        $testLog = Join-Path $logs 'device-test.log'
        & $adb -s $serial shell am instrument -w -r -e class 'com.zownload.app.YoutubeMp3DeviceTest#tauriRustKotlinPublishesRealYoutubeMp3' `
            -e youtubeUrlB64 $encoded 'com.zownload.app.test/androidx.test.runner.AndroidJUnitRunner' 2>&1 | Out-File $testLog
        if ($LASTEXITCODE -ne 0 -or -not ((Get-Content $testLog -Raw).Contains('OK (1 test)'))) {
            throw "Device test failed:`n$((Get-Content $testLog | Select-Object -Last 50) -join "`n")"
        }
        $deviceLog = Join-Path $logs 'device-logcat.log'
        & $adb -s $serial logcat -d -s 'Zownload0C06:I' '*:S' | Out-File $deviceLog
        $report = Get-Content $deviceLog -Raw
        foreach ($term in @('TAURI_RESULT OK:', 'PUBLISHED uri=content://', 'mime=audio/mpeg', 'sha256=', 'yt-dlp version stable@2026.08.19', 'JS runtimes: quickjs-2026-06-04', '[ExtractAudio]')) {
            if (-not $report.Contains($term)) { throw "Device log lacks proof: $term" }
        }
        $match = [regex]::Match($report, 'PUBLISHED uri=(content://\S+) name=(Zownload-0C06-[a-f0-9-]+\.mp3) mime=audio/mpeg sha256=([a-f0-9]{64}) bytes=(\d+)')
        if (-not $match.Success) { throw 'Could not parse the published MediaStore row.' }
        $name = $match.Groups[2].Value
        $media = Join-Path $logs $name
        & $adb -s $serial pull "/sdcard/Download/$name" $media | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Cannot read Downloads/$name from the device." }
        $hash = (Get-FileHash -LiteralPath $media -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($hash -ne $match.Groups[3].Value) { throw 'Host media SHA-256 differs from the published URI hash.' }
        if ((Get-Item -LiteralPath $media).Length -ne [long]$match.Groups[4].Value) { throw 'Host media length differs from the published URI length.' }
        $ffprobe = Join-Path $root 'work/engine/build/ffmpeg/windows-x64/recipe/ffmpeg-8.1.3/ffprobe.exe'
        if (-not (Test-Path -LiteralPath $ffprobe)) { throw 'Pinned Gate 0B ffprobe is missing.' }
        $probe = & $ffprobe -v error -show_entries 'format=format_name,duration:stream=codec_name,codec_type,bit_rate' -of json $media | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0 -or -not @($probe.streams | Where-Object { $_.codec_type -eq 'audio' -and $_.codec_name -eq 'mp3' }).Count) {
            throw 'Published file has no probed MP3 audio stream.'
        }
        $apkHash = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
        Write-Output "0C-06 youtube-mp3: device and media proof PASS; $model API $api $abi serial $serial."
        Write-Output "MediaStore URI: $($match.Groups[1].Value); name: $name; MIME: audio/mpeg."
        Write-Output "MP3 bytes: $($match.Groups[4].Value); SHA-256: $hash; duration: $($probe.format.duration)s."
        Write-Output "APK SHA-256: $apkHash; local feasibility only; Android distribution remains blocked."
        Get-Content $deviceLog | Where-Object { $_ -match 'ENGINE .*yt-dlp version|ENGINE .*JS runtimes:|ENGINE .*ExtractAudio|PUBLISHED uri=|TAURI_RESULT' } | Select-Object -Last 8
        exit 0
    } catch {
        Write-Error "0C-06 youtube-mp3: FAIL: $($_.Exception.Message)"
        exit 1
    }
}

if ($Case -eq 'quickjs-device') {
    try {
        $root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        if (-not $env:ANDROID_SERIAL) { throw 'Set ANDROID_SERIAL to the physical arm64 device serial.' }
        $sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
        $adb = Join-Path $sdk 'platform-tools/adb.exe'
        if (-not (Test-Path -LiteralPath $adb)) { throw "adb is missing: $adb" }
        $serial = $env:ANDROID_SERIAL
        $state = (& $adb -s $serial get-state 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $state -ne 'device') { throw "Device $serial is not authorized and connected: $state" }
        $abi = (& $adb -s $serial shell getprop ro.product.cpu.abi | Out-String).Trim()
        $api = (& $adb -s $serial shell getprop ro.build.version.sdk | Out-String).Trim()
        $model = (& $adb -s $serial shell getprop ro.product.model | Out-String).Trim()
        if ($abi -ne 'arm64-v8a') { throw "Device ABI is $abi, expected arm64-v8a." }

        foreach ($input in @('work/android/0c-05/jniLibs/arm64-v8a/libqjs.so',
                'work/android/0c-05/res/raw/ytdlp')) {
            if (-not (Test-Path -LiteralPath (Join-Path $root $input))) {
                throw "Run package-quickjs.ps1 before building Android; missing $input."
            }
        }
        $logs = Join-Path $root 'work/android/0c-05'
        New-Item -ItemType Directory -Force -Path $logs | Out-Null
        $buildLog = Join-Path $logs 'android-build.log'
        Push-Location $root
        try {
            $prior = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try { & npm.cmd run android:debug 2>&1 | Out-File $buildLog }
            finally { $ErrorActionPreference = $prior }
            if ($LASTEXITCODE -ne 0) {
                throw "Android build failed:`n$((Get-Content $buildLog | Select-Object -Last 50) -join "`n")"
            }
        } finally { Pop-Location }

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $apk = Join-Path $root 'src-tauri/gen/android/app/build/outputs/apk/universal/debug/app-universal-debug.apk'
        $archive = [IO.Compression.ZipFile]::OpenRead($apk)
        try {
            $expected = @{
                'lib/arm64-v8a/libqjs.so' = '4db3b8aeba709b4907da59a87f1ab3f94585bae3a95f7b02c946b7732cd20185'
                'res/raw/ytdlp' = '1fa6733c37ea6fb51c99ad8fe785e7b7e5f3246c9b980230329d4fb72ed8d4d6'
            }
            foreach ($name in $expected.Keys) {
                $entry = $archive.GetEntry($name)
                if (-not $entry) { throw "APK lacks $name" }
                $stream = $entry.Open()
                try { $actual = (Get-FileHash -InputStream $stream -Algorithm SHA256).Hash.ToLowerInvariant() }
                finally { $stream.Dispose() }
                if ($actual -ne $expected[$name]) { throw "APK $name SHA-256 mismatch: $actual" }
            }
            if (@($archive.Entries | Where-Object { $_.FullName -like 'lib/*' -and $_.FullName -notlike 'lib/arm64-v8a/*' }).Count) {
                throw 'APK includes a non-arm64 native library.'
            }
        } finally { $archive.Dispose() }

        & $adb -s $serial logcat -c | Out-Null
        $testLog = Join-Path $logs 'device-test.log'
        $android = Join-Path $root 'src-tauri/gen/android'
        Push-Location $android
        try {
            $prior = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try {
                & .\gradlew.bat :app:connectedUniversalDebugAndroidTest --no-configuration-cache `
                    -x :app:rustBuildUniversalDebug -x :app:rustBuildArm64Debug `
                    -x :app:rustBuildArmDebug -x :app:rustBuildX86Debug `
                    -x :app:rustBuildX86_64Debug 2>&1 | Out-File $testLog
            }
            finally { $ErrorActionPreference = $prior }
            if ($LASTEXITCODE -ne 0) {
                throw "Device test failed:`n$((Get-Content $testLog | Select-Object -Last 50) -join "`n")"
            }
        } finally { Pop-Location }
        $deviceLog = Join-Path $logs 'device-logcat.log'
        & $adb -s $serial logcat -d -s 'Zownload0C05:I' '*:S' | Out-File $deviceLog
        $report = Get-Content $deviceLog -Raw
        foreach ($term in @('ZOWNLOAD_QUICKJS_EXEC_OK', 'yt-dlp version stable@2026.08.19',
                'yt_dlp_ejs-0.8.0', 'JS runtimes: quickjs-2026-06-04', 'writable cache=')) {
            if (-not $report.Contains($term)) { throw "Device log lacks proof: $term" }
        }
        $apkHash = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
        Write-Output "0C-05 quickjs-device: PASS; $model; API $api; $abi; serial $serial."
        Write-Output "APK SHA-256: $apkHash; local feasibility only; Android distribution remains blocked."
        Get-Content $deviceLog | Where-Object { $_ -match 'QuickJS script=|yt-dlp version|Optional libraries:|JS runtimes:|writable cache=' } |
            Select-Object -Last 8
        exit 0
    } catch {
        Write-Error "0C-05 quickjs-device: FAIL: $($_.Exception.Message)"
        exit 1
    }
}

if ($Case -eq 'engine-reintegration') {
    try {
        $root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $gradleFile = Get-Content (Join-Path $root 'src-tauri/gen/android/app/build.gradle.kts') -Raw
        $evidence = Get-Content (Join-Path $root 'docs/gates/evidence/0c/engine-package.md') -Raw
        foreach ($term in @(
            'val androidEngineVersion = "0.18.1"',
            'implementation("io.github.junkfood02.youtubedl-android:library:$androidEngineVersion")',
            'implementation("io.github.junkfood02.youtubedl-android:ffmpeg:$androidEngineVersion")'
        )) {
            if (-not $gradleFile.Contains($term)) { throw "Missing pinned dependency: $term" }
        }
        $adapterSource = Get-Content (Join-Path $root 'src-tauri/gen/android/app/src/main/java/com/zownload/app/AndroidEngineAdapter.kt') -Raw
        if (-not $adapterSource.Contains('override val version = "0.18.1"')) {
            throw 'Bundled provider version differs from the Gradle pin.'
        }
        foreach ($term in @('FEASIBILITY ONLY', 'OPEN RELEASE BLOCKER',
                'no Android APK or build may be published')) {
            if (-not $evidence.Contains($term)) { throw "Missing release constraint: $term" }
        }

        $logs = Join-Path $root 'work/android'
        New-Item -ItemType Directory -Path $logs -Force | Out-Null
        $buildLog = Join-Path $logs '0c-04b-build.log'
        Push-Location $root
        try {
            $previousErrorAction = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try { & npm.cmd run android:debug 2>&1 | Out-File $buildLog }
            finally { $ErrorActionPreference = $previousErrorAction }
            if ($LASTEXITCODE -ne 0) {
                $errors = Get-Content $buildLog | Where-Object { $_ -match 'e: |error:|FAILURE:|What went wrong:|FAILED|Caused by:' } | Select-Object -Last 20
                throw "npm run android:debug failed ($LASTEXITCODE):`n$($errors -join "`n")"
            }
        } finally { Pop-Location }

        $android = Join-Path $root 'src-tauri/gen/android'
        $dependencyLog = Join-Path $logs '0c-04b-dependencies.log'
        Push-Location $android
        try {
            $previousErrorAction = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try { & .\gradlew.bat :app:dependencies --configuration universalDebugRuntimeClasspath --offline 2>&1 | Out-File $dependencyLog }
            finally { $ErrorActionPreference = $previousErrorAction }
            if ($LASTEXITCODE -ne 0) {
                throw "Gradle dependency resolution failed ($LASTEXITCODE):`n$((Get-Content $dependencyLog | Select-Object -Last 50) -join "`n")"
            }
        } finally { Pop-Location }
        $resolved = Get-Content $dependencyLog -Raw
        foreach ($module in @('library', 'ffmpeg', 'common')) {
            $pattern = "io\.github\.junkfood02\.youtubedl-android:${module}:0\.18\.1(?:\s|\(|$)"
            if ($resolved -notmatch $pattern) { throw "Resolved $module:0.18.1 is missing." }
            $moduleLines = @($resolved -split "`n" | Where-Object { $_ -match "io\.github\.junkfood02\.youtubedl-android:${module}:" })
            if (@($moduleLines | Where-Object { $_ -match ' -> ' }).Count) {
                throw "Gradle substituted a different $module version."
            }
            $versions = [regex]::Matches($resolved, "io\.github\.junkfood02\.youtubedl-android:${module}:([0-9][^\s()]*)")
            if (@($versions | Where-Object { $_.Groups[1].Value -ne '0.18.1' }).Count) {
                throw "Resolved $module has another version."
            }
        }

        $cache = Join-Path $env:USERPROFILE '.gradle/caches/modules-2/files-2.1/io.github.junkfood02.youtubedl-android'
        $hashes = @{
            library = '579b5fb480892b1abc2b218c2089699d52759cc8d7ba256bf876453f0365faef'
            ffmpeg = '0a87ffa6cf912b0fe76c1a99b9107f543ee2f247935fae2c71f0822eb7bc5f49'
            common = 'e0c0530bdbdf203e1598e900085d3582e27360731872872f3a67f23a9b24c0b5'
        }
        foreach ($module in $hashes.Keys) {
            $aar = Get-ChildItem (Join-Path $cache $module) -Recurse -File -Filter "$module-0.18.1.aar" |
                Select-Object -First 1
            if (-not $aar) { throw "Resolved $module AAR is missing." }
            $actual = (Get-FileHash $aar.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actual -ne $hashes[$module] -or -not $evidence.Contains($actual)) {
                throw "Resolved $module AAR differs from 0C-04."
            }
        }

        $classes = Join-Path $root 'src-tauri/gen/android/app/build/tmp/kotlin-classes'
        if (-not (Get-ChildItem $classes -Recurse -File -Filter 'AndroidEngineAdapter.class' |
                Select-Object -First 1)) { throw 'Kotlin adapter class was not compiled.' }

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $apk = Join-Path $root 'src-tauri/gen/android/app/build/outputs/apk/universal/debug/app-universal-debug.apk'
        if (-not (Test-Path $apk)) { throw 'Debug APK is missing.' }
        $rows = @(Import-Csv (Join-Path $root 'docs/gates/evidence/0c/engine-package-native.tsv') -Delimiter "`t" |
            Where-Object { $_.container -in @('library-0.18.1.aar', 'ffmpeg-0.18.1.aar') -and
                $_.entry -like 'jni/arm64-v8a/*' })
        if ($rows.Count -ne 6) { throw "Expected six top-level native inventory rows, got $($rows.Count)." }
        $archive = [System.IO.Compression.ZipFile]::OpenRead($apk)
        try {
            $native = @($archive.Entries | Where-Object FullName -Like 'lib/*')
            if (@($native | Where-Object FullName -NotLike 'lib/arm64-v8a/*').Count) {
                throw 'APK includes another native ABI.'
            }
            if (-not $archive.GetEntry('lib/arm64-v8a/libzownload_lib.so')) {
                throw 'APK lacks the Rust library.'
            }
            foreach ($row in $rows) {
                $entry = $archive.GetEntry($row.entry.Replace('jni/', 'lib/'))
                if (-not $entry -or $entry.Length -ne [long]$row.bytes) {
                    throw "APK lacks inventoried native entry $($row.entry)."
                }
                $stream = $entry.Open()
                try { $actual = (Get-FileHash -InputStream $stream -Algorithm SHA256).Hash.ToLowerInvariant() }
                finally { $stream.Dispose() }
                if ($actual -ne $row.sha256) { throw "APK native hash differs: $($row.entry)" }
            }
        } finally { $archive.Dispose() }
        $apkHash = (Get-FileHash $apk -Algorithm SHA256).Hash.ToLowerInvariant()
        $apkBytes = (Get-Item $apk).Length
        Write-Output "0C-04B engine-reintegration: PASS; APK $apkBytes bytes, SHA-256 $apkHash; feasibility only; Android distribution remains blocked."
        exit 0
    } catch {
        Write-Error "0C-04B engine-reintegration: FAIL: $($_.Exception.Message)"
        exit 1
    }
}

if ($Case -eq 'engine-package') {
    try {
        $root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $evidence = Get-Content (Join-Path $root 'docs/gates/evidence/0c/engine-package.md') -Raw
        $rows = @(Import-Csv (Join-Path $root 'docs/gates/evidence/0c/engine-package-native.tsv') -Delimiter "`t")
        if ($rows.Count -ne 361) { throw "Expected 361 native inventory rows, got $($rows.Count)" }
        if (@($rows | Where-Object { $_.sha256 -notmatch '^[a-f0-9]{64}$' -or $_.bytes -notmatch '^[0-9]+$' }).Count) {
            throw 'Native manifest has an invalid hash or size.'
        }
        if (@($rows | Group-Object container, entry | Where-Object Count -gt 1).Count) {
            throw 'Native manifest contains duplicate paths.'
        }

        $cache = Join-Path $env:USERPROFILE '.gradle/caches/modules-2/files-2.1/io.github.junkfood02.youtubedl-android'
        $hashes = @{
            library = '579b5fb480892b1abc2b218c2089699d52759cc8d7ba256bf876453f0365faef'
            ffmpeg = '0a87ffa6cf912b0fe76c1a99b9107f543ee2f247935fae2c71f0822eb7bc5f49'
            common = 'e0c0530bdbdf203e1598e900085d3582e27360731872872f3a67f23a9b24c0b5'
        }
        $artifacts = @{}
        foreach ($module in $hashes.Keys) {
            $file = Get-ChildItem (Join-Path $cache $module) -Filter "$module-0.18.1.aar" -Recurse -File |
                Select-Object -First 1
            if (-not $file) { throw "Resolved $module AAR is missing from Gradle cache." }
            $actual = (Get-FileHash $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actual -ne $hashes[$module] -or -not $evidence.Contains($actual)) {
                throw "Resolved $module AAR does not match the evidence."
            }
            $artifacts[$module] = $file.FullName
        }

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        foreach ($module in @('library', 'ffmpeg')) {
            $outer = [System.IO.Compression.ZipFile]::OpenRead($artifacts[$module])
            try {
                $nestedName = if ($module -eq 'library') {
                    'jni/arm64-v8a/libpython.zip.so'
                } else {
                    'jni/arm64-v8a/libffmpeg.zip.so'
                }
                $memory = [System.IO.MemoryStream]::new()
                $source = $outer.GetEntry($nestedName).Open()
                try { $source.CopyTo($memory) } finally { $source.Dispose() }
                $memory.Position = 0
                $nested = [System.IO.Compression.ZipArchive]::new($memory)
                try {
                    foreach ($row in $rows | Where-Object { $_.container -like "$module-0.18.1.aar*" }) {
                        $entry = if ($row.container -eq "$module-0.18.1.aar") {
                            $outer.GetEntry($row.entry)
                        } elseif ($row.container -eq "$module-0.18.1.aar/$nestedName") {
                            $nested.GetEntry($row.entry)
                        } else {
                            throw "Unexpected inventory container: $($row.container)"
                        }
                        if (-not $entry -or $entry.Length -ne [long]$row.bytes) {
                            throw "Missing or wrong-sized native entry: $($row.entry)"
                        }
                        $stream = $entry.Open()
                        try {
                            $actual = (Get-FileHash -InputStream $stream -Algorithm SHA256).Hash.ToLowerInvariant()
                        } finally { $stream.Dispose() }
                        if ($actual -ne $row.sha256) {
                            throw "Native entry hash differs: $($row.entry)"
                        }
                    }
                } finally {
                    $nested.Dispose()
                    $memory.Dispose()
                }
            } finally {
                $outer.Dispose()
            }
        }

        $apk = Join-Path $root 'src-tauri/gen/android/app/build/outputs/apk/universal/debug/app-universal-debug.apk'
        if (-not (Test-Path $apk)) { throw 'The inspected debug APK is missing.' }
        # The original probe APK was replaced by the 0C-04B build. Keep its
        # recorded hash as historical evidence and inspect the current package.
        if (-not $evidence.Contains('956cd82c6de20907fd61e55b37bf4d1611602696af13e3a04af0c54846199176')) {
            throw 'The historical 0C-04 APK hash is missing from the evidence.'
        }
        $archive = [System.IO.Compression.ZipFile]::OpenRead($apk)
        try {
            $native = @($archive.Entries | Where-Object FullName -Like 'lib/*')
            if (@($native | Where-Object FullName -NotLike 'lib/arm64-v8a/*').Count) {
                throw 'APK contains another native ABI.'
            }
            foreach ($name in @('libpython.so', 'libpython.zip.so', 'libqjs.so',
                    'libffmpeg.so', 'libffmpeg.zip.so', 'libffprobe.so', 'libzownload_lib.so')) {
                if (-not $archive.GetEntry("lib/arm64-v8a/$name")) {
                    throw "APK lacks $name."
                }
            }
        } finally {
            $archive.Dispose()
        }

        foreach ($term in @('1,007 entries', '184 entries', 'corresponding-source',
                '**Gate 0C stop rule invoked.**', 'not a completed 0C-04 integration')) {
            if (-not $evidence.Contains($term)) { throw "Missing stop evidence: $term" }
        }
        Write-Output '0C-04 engine-package: historical probe evidence verified; current Gate 0C status is feasibility only with an open Android release blocker.'
        exit 0
    } catch {
        Write-Error "0C-04 engine-package: FAIL: $($_.Exception.Message)"
        exit 1
    }
}

try {
    $root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $audit = Get-Content (Join-Path $root 'docs/gates/evidence/0c/library-audit.md') -Raw
    $sources = Get-Content (Join-Path $root 'docs/engine-sources.md') -Raw
    $commit = 'd725d5c9a18c3a99a13ee0308bf78275dc310760'

    foreach ($heading in @(
        '## JS runtime and yt-dlp/ejs pair',
        '## Update and rollback',
        '## FFmpeg package, native dependencies, and license',
        '## Artifact provenance and further proof',
        '## Foreground-service type for owner decision',
        '## Stop result and documentation consulted'
    )) {
        if (-not $audit.Contains($heading)) { throw "Missing audit section: $heading" }
    }

    foreach ($term in @(
        $commit, '2025.11.12', 'ejs 0.3.1', '2026.08.19',
        '0.8.0', '--js-runtimes', 'TMPDIR', 'GPL-3.0',
        '--enable-gpl', 'libmp3lame.so', 'libx264.so',
        'dataSync', 'onTimeout', '0C-01A'
    )) {
        if (-not $audit.Contains($term)) { throw "Missing audited fact: $term" }
    }

    foreach ($url in @(
        "https://github.com/yausername/youtubedl-android/tree/$commit",
        'https://ffmpeg.org/legal.html',
        'https://developer.android.com/develop/background-work/services/fgs/service-types',
        'https://developer.android.com/develop/background-work/services/fgs/timeout'
    )) {
        if (-not $audit.Contains($url)) { throw "Missing primary source: $url" }
    }

    foreach ($hash in @(
        '579b5fb480892b1abc2b218c2089699d52759cc8d7ba256bf876453f0365faef',
        '0a87ffa6cf912b0fe76c1a99b9107f543ee2f247935fae2c71f0822eb7bc5f49'
    )) {
        if (-not $audit.Contains($hash) -or -not $sources.Contains($hash)) {
            throw "Candidate AAR hash does not match source record: $hash"
        }
    }

    if (-not $audit.Contains('**Stop rule invoked.**') -or
        -not $sources.Contains('integration stops for owner architecture/licensing decision 0C-01A')) {
        throw 'The required Android integration stop is not recorded in both documents.'
    }

    Write-Output '0C-01 library-audit: PASS (versioned sources, candidate hashes, hard stop, and owner decision recorded)'
} catch {
    Write-Error "0C-01 library-audit: FAIL: $($_.Exception.Message)"
    exit 1
}
