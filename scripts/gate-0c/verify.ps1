# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('library-audit', 'engine-package', 'engine-reintegration', 'quickjs-device', 'youtube-mp3', 'foreground-service', 'home', 'recents', 'process-death', 'webview-recreate', 'mediastore-zip', 'update-rollback')]
    [string]$Case
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($Case -eq 'update-rollback') {
    try {
        $root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        if (-not $env:ANDROID_SERIAL) { throw 'Set ANDROID_SERIAL to the physical arm64 device serial.' }
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
        $virtual = (& $adb -s $serial shell getprop ro.kernel.qemu | Out-String).Trim()
        if ($abi -ne 'arm64-v8a' -or [int]$api -lt 24 -or $virtual -eq '1') {
            throw "Requires physical arm64 API 24+; found $abi API $api qemu=$virtual"
        }

        $logs = Join-Path $root 'work/android/0c-14'
        New-Item -ItemType Directory -Force -Path $logs | Out-Null
        $candidate = Join-Path $logs 'yt-dlp-2026.10.21'
        $manifest = Join-Path $logs 'SHA2-256SUMS'
        if (-not (Test-Path -LiteralPath $candidate)) {
            Invoke-WebRequest -Uri 'https://github.com/yt-dlp/yt-dlp/releases/download/2026.10.21/yt-dlp' -OutFile $candidate
        }
        if (-not (Test-Path -LiteralPath $manifest)) {
            Invoke-WebRequest -Uri 'https://github.com/yt-dlp/yt-dlp/releases/download/2026.10.21/SHA2-256SUMS' -OutFile $manifest
        }
        $candidateHash = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($candidateHash -ne 'b7af77f686e95f7845ce8d09d21957718febb8b48b30555adb9dd2292ad7bf14' -or
            -not ((Get-Content -LiteralPath $manifest -Raw).Contains("$candidateHash  yt-dlp"))) {
            throw 'Candidate differs from its pinned SHA-256 or published checksum manifest.'
        }
        $baseline = Join-Path $root 'work/android/0c-05/res/raw/ytdlp'
        if (-not (Test-Path -LiteralPath $baseline) -or
            (Get-FileHash -LiteralPath $baseline -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '1fa6733c37ea6fb51c99ad8fe785e7b7e5f3246c9b980230329d4fb72ed8d4d6') {
            throw 'The packaged yt-dlp baseline is missing or differs from its pin.'
        }

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

        $testBuildLog = Join-Path $logs 'android-test-build.log'
        Push-Location (Join-Path $root 'src-tauri/gen/android')
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
        if ($LASTEXITCODE -ne 0) { throw 'Could not install the test APK.' }
        & $adb -s $serial logcat -c | Out-Null

        $testLog = Join-Path $logs 'device-test.log'
        $testErr = Join-Path $logs 'device-test-error.log'
        $args = @('-s', $serial, 'shell', 'am', 'instrument', '-w', '-r', '-e', 'class',
            'com.zownload.app.YtDlpUpdateDeviceTest#verifiedStableUpdateRejectsUnsafeSwapsAndRollsBack',
            'com.zownload.app.test/androidx.test.runner.AndroidJUnitRunner')
        $instrument = Start-Process -FilePath $adb -ArgumentList $args -PassThru `
            -RedirectStandardOutput $testLog -RedirectStandardError $testErr -WindowStyle Hidden
        $null = $instrument.WaitForExit(240000)
        if (-not $instrument.HasExited) {
            $instrument.Kill()
            throw 'Update/rollback instrumentation timed out.'
        }
        $testReport = Get-Content -LiteralPath $testLog -Raw
        if (-not $testReport.Contains('OK (1 test)') -or -not $testReport.Contains('INSTRUMENTATION_CODE: -1')) {
            throw "Update/rollback instrumentation failed:`n$((Get-Content $testLog | Select-Object -Last 50) -join "`n")"
        }
        $deviceLog = Join-Path $logs 'device-logcat.log'
        & $adb -s $serial logcat -d -s 'Zownload0C14:I' '*:S' | Out-File $deviceLog
        $report = Get-Content -LiteralPath $deviceLog -Raw
        foreach ($term in @('BASELINE version=2026.08.19', 'ACTIVE_JOB_REJECTED',
                'BAD_CANDIDATE_REJECTED', 'CANDIDATE_VERIFIED version=2026.10.21 ejs=0.8.0',
                'UPDATE_OK version=2026.10.21', 'RUNTIME [debug] yt-dlp version stable@2026.10.21',
                'POST_ACCEPT_FAILURE reason=injected post-acceptance failure',
                'ROLLBACK_OK version=2026.08.19', 'RECOVERY_OK version=2026.08.19')) {
            if (-not $report.Contains($term)) { throw "Device log lacks proof: $term" }
        }
        $apkHash = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
        Write-Output "0C-14 update-rollback: physical device PASS; $model API $api $abi serial $serial."
        Write-Output "Baseline 2026.08.19/$((Get-FileHash -LiteralPath $baseline -Algorithm SHA256).Hash.ToLowerInvariant()); candidate 2026.10.21/$candidateHash; EJS 0.8.0."
        Write-Output 'Active-job and bad-hash swaps rejected; accepted candidate executed; injected post-acceptance failure restored the executable baseline.'
        Write-Output "APK SHA-256: $apkHash; local feasibility only; Android distribution remains blocked."
        exit 0
    } catch {
        Write-Error "0C-14 update-rollback failed: $($_.Exception.Message)"
        exit 1
    }
}

if ($Case -eq 'mediastore-zip') {
    try {
        $root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        if (-not $env:ANDROID_SERIAL) { throw 'Set ANDROID_SERIAL to the physical arm64 device serial.' }
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

        $logs = Join-Path $root 'work/android/0c-13'
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

        $testBuildLog = Join-Path $logs 'android-test-build.log'
        Push-Location (Join-Path $root 'src-tauri/gen/android')
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
        & $adb -s $serial uninstall com.zownload.app.test | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not reset the separate test APK.' }
        & $adb -s $serial install -r $testApk | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not install the instrumentation APK.' }
        & $adb -s $serial shell pm grant com.zownload.app.test android.permission.READ_EXTERNAL_STORAGE | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not grant the separate test APK read access.' }
        & $adb -s $serial logcat -c | Out-Null

        $testLog = Join-Path $logs 'device-test.log'
        $testErr = Join-Path $logs 'device-test-error.log'
        $args = @('-s', $serial, 'shell', 'am', 'instrument', '-w', '-r', '-e', 'class',
            'com.zownload.app.MediaStoreZipDeviceTest#rustStreamsZipAndDeletesFailedPendingRow',
            'com.zownload.app.test/androidx.test.runner.AndroidJUnitRunner')
        $instrument = Start-Process -FilePath $adb -ArgumentList $args -PassThru `
            -RedirectStandardOutput $testLog -RedirectStandardError $testErr -WindowStyle Hidden
        $pending = $null
        $deadline = (Get-Date).AddSeconds(45)
        while (-not $pending -and (Get-Date) -lt $deadline -and -not $instrument.HasExited) {
            Start-Sleep -Milliseconds 250
            $live = (& $adb -s $serial logcat -d -s 'Zownload0C13:I' '*:S' 2>&1 | Out-String)
            $pending = [regex]::Match($live, 'ZIP_PENDING uri=(content://\S+) name=(Zownload-0C13-[a-f0-9-]+\.zip)')
            if (-not $pending.Success) { $pending = $null }
        }
        if (-not $pending) { throw 'No pending ZIP row appeared during instrumentation.' }
        $pendingUri = $pending.Groups[1].Value
        $pendingName = $pending.Groups[2].Value
        # adb's shell UID is privileged. The receiver queries as the separate
        # test APK UID with read permission, before Rust writes the ZIP.
        & $adb -s $serial shell am broadcast -n com.zownload.app.test/com.zownload.app.ZipVisibilityReceiver --es uri $pendingUri | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not query the pending row as the test app.' }
        $visibility = (& $adb -s $serial logcat -d -s 'Zownload0C13:I' '*:S' 2>&1 | Out-String)
        if ($visibility -notmatch "ZIP_VISIBILITY uid=\d+ uri=$([regex]::Escape($pendingUri)) visible=false") {
            throw 'The separate test app did not confirm that the pending row was hidden.'
        }
        $pendingRow = (& $adb -s $serial shell content query --uri $pendingUri 2>&1 | Out-String)
        if ($pendingRow -notmatch 'is_pending=1' -or
            $visibility -match "ZIP_PUBLISHED uri=$([regex]::Escape($pendingUri))") {
            throw 'The visibility query did not run before ZIP publication.'
        }
        $null = $instrument.WaitForExit(120000)
        if (-not $instrument.HasExited) { throw 'ZIP instrumentation timed out.' }
        $testReport = Get-Content $testLog -Raw
        if (-not $testReport.Contains('OK (1 test)') -or -not $testReport.Contains('INSTRUMENTATION_CODE: -1')) {
            throw "ZIP instrumentation failed:`n$((Get-Content $testLog | Select-Object -Last 50) -join "`n")"
        }
        $deviceLog = Join-Path $logs 'device-logcat.log'
        & $adb -s $serial logcat -d -s 'Zownload0C13:I' 'RustStdoutStderr:I' '*:S' | Out-File $deviceLog
        $report = Get-Content $deviceLog -Raw
        foreach ($term in @('ZIP_TEST_PUBLISHED OK:', 'ZIP_TEST_FAILED ERR:Injected ZIP failure', 'ZIP_DELETED uri=', 'deleted=1', 'ZIP_ABORT')) {
            if (-not $report.Contains($term)) { throw "Device log lacks proof: $term" }
        }
        $deleted = [regex]::Match($report, 'ZIP_DELETED uri=(content://\S+) deleted=1')
        if (-not $deleted.Success) { throw 'Could not parse the deleted failed ZIP row.' }
        $failedRow = (& $adb -s $serial shell content query --uri $deleted.Groups[1].Value 2>&1 | Out-String)
        if ($failedRow -match 'Row:|_display_name=') { throw 'The failed ZIP row still exists.' }
        $published = [regex]::Match($report, 'ZIP_PUBLISHED uri=(content://\S+) name=(Zownload-0C13-[a-f0-9-]+\.zip) bytes=(\d+)')
        if (-not $published.Success -or $published.Groups[1].Value -ne $pendingUri -or $published.Groups[2].Value -ne $pendingName) {
            throw 'The pending ZIP row was not published under the same URI and name.'
        }
        # Downloads rows remain owner-scoped to MediaStore callers on API 29.
        # The shell can inspect the published metadata and the actual file.
        $publishedRow = (& $adb -s $serial shell content query --uri $pendingUri 2>&1 | Out-String)
        if ($publishedRow -notmatch 'is_pending=0' -or $publishedRow -notmatch [regex]::Escape($pendingName)) {
            throw 'Published MediaStore metadata is missing or still pending.'
        }
        $media = Join-Path $logs $pendingName
        & $adb -s $serial pull "/sdcard/Download/$pendingName" $media | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Cannot pull Downloads/$pendingName." }
        if ((Get-Item -LiteralPath $media).Length -ne [long]$published.Groups[3].Value) { throw 'Published ZIP byte count differs from the pulled file.' }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [IO.Compression.ZipFile]::OpenRead($media)
        try {
            $names = @($archive.Entries | ForEach-Object { $_.FullName })
            if ($names.Count -ne 2 -or $names[0] -ne 'manifest.txt' -or $names[1] -ne 'payload.bin') {
                throw "ZIP entry order differs: $($names -join ', ')"
            }
            $textReader = New-Object IO.StreamReader($archive.Entries[0].Open())
            try { $manifest = $textReader.ReadToEnd() } finally { $textReader.Dispose() }
            if ($manifest -ne "Zownload Gate 0C-13`nRust owns ZIP entries and order.`n") { throw 'ZIP manifest differs.' }
            [byte[]]$expected = New-Object byte[] (256 * 1024)
            for ($i = 0; $i -lt $expected.Length; $i++) { $expected[$i] = [byte]($i % 256) }
            $sha = [Security.Cryptography.SHA256]::Create()
            try {
                $expectedHash = [BitConverter]::ToString($sha.ComputeHash($expected)).Replace('-', '').ToLowerInvariant()
                $payloadStream = $archive.Entries[1].Open()
                try { $actualHash = [BitConverter]::ToString($sha.ComputeHash($payloadStream)).Replace('-', '').ToLowerInvariant() }
                finally { $payloadStream.Dispose() }
            } finally { $sha.Dispose() }
            if ($archive.Entries[1].Length -ne $expected.Length -or $actualHash -ne $expectedHash) { throw 'ZIP payload length or SHA-256 differs.' }
        } finally { $archive.Dispose() }
        $privateZip = (& $adb -s $serial shell run-as com.zownload.app find cache -type f -name '*.zip' 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $privateZip) { throw "Private ZIP copy check failed: $privateZip" }
        $apkHash = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
        $zipHash = (Get-FileHash -LiteralPath $media -Algorithm SHA256).Hash.ToLowerInvariant()
        Write-Output "0C-13 mediastore-zip: device and ZIP proof PASS; $model API $api $abi serial $serial."
        Write-Output "Pending hidden from separate test app UID; published IS_PENDING=0; URI: $pendingUri; ZIP: $pendingName; bytes: $($published.Groups[3].Value); SHA-256: $zipHash."
        Write-Output "Entries: $($names -join ', '); payload SHA-256: $actualHash; injected failure deleted its pending row."
        Write-Output "APK SHA-256: $apkHash; local feasibility only; Android distribution remains blocked."
        exit 0
    } catch {
        Write-Error "0C-13 mediastore-zip: FAIL: $($_.Exception.Message)"
        exit 1
    }
}

if ($Case -eq 'webview-recreate') {
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
        $logs = Join-Path $root 'work/android/0c-12'
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
        $testLog = Join-Path $logs 'webview-recreate-test.log'
        & $adb -s $serial shell am instrument -w -r -e class `
            'com.zownload.app.WebViewRecreationDeviceTest#recreatedActivityRestoresQueueAndReceivesProgressEvents' `
            -e youtubeUrlB64 $encoded 'com.zownload.app.test/androidx.test.runner.AndroidJUnitRunner' 2>&1 | Out-File $testLog
        $testExit = $LASTEXITCODE
        $testResult = Get-Content $testLog -Raw
        if ($testExit -ne 0 -or -not $testResult.Contains('OK (1 test)')) {
            throw "WebView recreation instrumentation failed:`n$((Get-Content $testLog | Select-Object -Last 50) -join "`n")"
        }
        $deviceLog = Join-Path $logs 'device-logcat.log'
        & $adb -s $serial logcat -d -s 'Zownload0C12:I' 'Zownload0C09:I' 'RustStdoutStderr:I' '*:S' | Out-File $deviceLog
        $report = Get-Content $deviceLog -Raw
        $before = [regex]::Match($report, 'BEFORE pid=(\d+) item=([a-f0-9-]{36}) status=downloading percent=([\d.]+) children=([\d,]+)')
        $after = [regex]::Match($report, 'RECREATED pid=(\d+) item=([a-f0-9-]{36}) status=downloading percent=([\d.]+) children=([\d,]+)')
        $live = [regex]::Match($report, 'LIVE_EVENT item=([a-f0-9-]{36}) status=downloading percent=([\d.]+) children=([\d,]+)')
        if (-not $before.Success -or -not $after.Success -or -not $live.Success -or
                $before.Groups[1].Value -ne $after.Groups[1].Value -or
                $before.Groups[2].Value -ne $after.Groups[2].Value -or
                $before.Groups[2].Value -ne $live.Groups[1].Value -or
                $before.Groups[4].Value -ne $after.Groups[4].Value -or
                $before.Groups[4].Value -ne $live.Groups[3].Value -or
                [double]$after.Groups[3].Value -lt [double]$before.Groups[3].Value -or
                [double]$live.Groups[2].Value -le [double]$after.Groups[3].Value) {
            throw 'Activity recreation, same job, or new event subscription proof is missing.'
        }
        $apkHash = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
        Write-Output "0C-12 webview-recreate: PASS; $model API $api $abi serial $serial."
        Write-Output "WebView: $webView; APK SHA-256: $apkHash."
        Write-Output 'Local feasibility only; Android distribution remains blocked.'
        Get-Content $deviceLog | Where-Object { $_ -match 'BEFORE pid=|RECREATED pid=|LIVE_EVENT item=' } | Select-Object -Last 3
        exit 0
    } catch {
        Write-Error "0C-12 webview-recreate: FAIL: $($_.Exception.Message)"
        exit 1
    }
}

if ($Case -eq 'process-death') {
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
        $logs = Join-Path $root 'work/android/0c-11'
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
        $firstLog = Join-Path $logs 'before-kill-test.log'
        $firstError = Join-Path $logs 'before-kill-test-error.log'
        $firstProcess = Start-Process -FilePath $adb -ArgumentList @(
            '-s', $serial, 'shell', 'am', 'instrument', '-w', '-r', '-e', 'class',
            'com.zownload.app.ProcessDeathDeviceTest#startAndLeavePartForHostKill',
            '-e', 'youtubeUrlB64', $encoded,
            'com.zownload.app.test/androidx.test.runner.AndroidJUnitRunner'
        ) -RedirectStandardOutput $firstLog -RedirectStandardError $firstError -WindowStyle Hidden -PassThru
        $deviceLog = Join-Path $logs 'device-logcat.log'
        $proof = [regex]::Match('', 'PREKILL pid=(\d+) item=([a-f0-9-]{36}) part=(\S+\.part) bytes=(\d+) prefix=([a-f0-9]{64})')
        for ($attempt = 1; $attempt -le 90; $attempt++) {
            & $adb -s $serial logcat -d -s 'Zownload0C11:I' 'Zownload0C06:I' 'Zownload0C08:I' 'RustStdoutStderr:I' '*:S' | Out-File $deviceLog
            $report = Get-Content $deviceLog -Raw
            $proof = [regex]::Match($report, 'PREKILL pid=(\d+) item=([a-f0-9-]{36}) part=(\S+\.part) bytes=(\d+) prefix=([a-f0-9]{64})')
            if ($proof.Success) { break }
            if ($firstProcess.HasExited) {
                throw "Pre-kill instrumentation ended early:`n$((Get-Content $firstLog | Select-Object -Last 50) -join "`n")"
            }
            Start-Sleep -Seconds 2
        }
        if (-not $proof.Success -or [long]$proof.Groups[4].Value -lt 8192) { throw 'Pre-kill .part proof is missing.' }
        $pidToKill = $proof.Groups[1].Value
        $ps = (& $adb -s $serial shell ps -A -o PID,PPID,NAME | Out-String)
        $relations = @{}
        foreach ($line in ($ps -split "`n")) {
            if ($line -match '^\s*(\d+)\s+(\d+)\s+') { $relations[$Matches[1]] = $Matches[2] }
        }
        $children = @($relations.Keys | Where-Object { $relations[$_] -eq $pidToKill })
        if ($children.Count -eq 0) { throw 'No live engine child PID before kill.' }
        # Android denies shell/run-as signals to this foreground app on the
        # test device. Activity Manager's adb force-stop ends it abruptly.
        $killReport = (& $adb -s $serial shell am force-stop com.zownload.app 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) { throw "adb force-stop failed: $killReport" }
        $firstProcess.WaitForExit(20000) | Out-Null
        Start-Sleep -Seconds 3
        $afterPs = (& $adb -s $serial shell ps -A -o PID,PPID,NAME | Out-String)
        $live = @([regex]::Matches($afterPs, '(?m)^\s*(\d+)\s+') | ForEach-Object { $_.Groups[1].Value })
        foreach ($observed in (@($pidToKill) + $children)) {
            if ($observed -in $live) { throw "Process PID $observed survived SIGKILL." }
        }
        $saved = (& $adb -s $serial shell run-as com.zownload.app stat -c '%s' "cache/zownload-0c-06/$($proof.Groups[2].Value)/$($proof.Groups[3].Value)" 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or [long]$saved -lt [long]$proof.Groups[4].Value) {
            throw "Saved .part was lost or shrank after kill: $saved"
        }
        $secondLog = Join-Path $logs 'after-kill-test.log'
        & $adb -s $serial shell am instrument -w -r -e class 'com.zownload.app.ProcessDeathDeviceTest#reopenAndContinueSavedPart' `
            'com.zownload.app.test/androidx.test.runner.AndroidJUnitRunner' 2>&1 | Out-File $secondLog
        $second = Get-Content $secondLog -Raw
        if ($LASTEXITCODE -ne 0 -or -not $second.Contains('OK (1 test)')) {
            throw "Reopen/Continue phase failed:`n$((Get-Content $secondLog | Select-Object -Last 50) -join "`n")"
        }
        & $adb -s $serial logcat -d -s 'Zownload0C11:I' 'Zownload0C06:I' 'Zownload0C08:I' 'RustStdoutStderr:I' '*:S' | Out-File $deviceLog
        $report = Get-Content $deviceLog -Raw
        $id = $proof.Groups[2].Value
        $hash = $proof.Groups[5].Value
        if (-not $report.Contains("REOPENED_PAUSED item=$id") -or
                -not $report.Contains("CONTINUED_PART item=$id") -or
                -not $report.Contains("prefix=$hash") -or
                -not $report.Contains("RESUME_INPUT item=$id")) {
            throw 'Reopen, no-auto-resume, or saved-prefix Continue proof is missing.'
        }
        $apkHash = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
        Write-Output "0C-11 process-death: PASS; $model API $api $abi serial $serial."
        Write-Output "WebView: $webView; APK SHA-256: $apkHash; adb force-stopped PID $pidToKill; engine children $($children -join ',') absent."
        Write-Output 'Local feasibility only; Android distribution remains blocked.'
        Get-Content $deviceLog | Where-Object { $_ -match 'PREKILL|REOPENED_PAUSED|RESUME_INPUT|CONTINUED_PART' } | Select-Object -Last 10
        exit 0
    } catch {
        Write-Error "0C-11 process-death: FAIL: $($_.Exception.Message)"
        exit 1
    }
}

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
