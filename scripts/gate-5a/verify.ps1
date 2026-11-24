# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('python-source-lock', 'python-runtime', 'ffmpeg', 'quickjs', 'package-provenance')]
    [string]$Case
)

$ErrorActionPreference = 'Stop'
$HostIsWindows = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
    [System.Runtime.InteropServices.OSPlatform]::Windows
)
$HostIsLinux = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
    [System.Runtime.InteropServices.OSPlatform]::Linux
)

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param([object]$Actual, [object]$Expected, [string]$Label)
    if ([string]$Actual -cne [string]$Expected) {
        throw "$Label expected '$Expected', found '$Actual'."
    }
}

function Read-JsonFence {
    param([string]$Text, [string]$FenceName)
    $pattern = '(?ms)^```json ' + [regex]::Escape($FenceName) + '\s*(.*?)\r?\n```'
    $match = [regex]::Match($Text, $pattern)
    Assert-True $match.Success "Missing JSON block '$FenceName'."
    return (ConvertFrom-Json -InputObject $match.Groups[1].Value)
}

function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-ZipEntrySha256 {
    param([System.IO.Compression.ZipArchiveEntry]$Entry)
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    $stream = $Entry.Open()
    try {
        return ([System.BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $stream.Dispose()
        $algorithm.Dispose()
    }
}

function Get-ConnectedAndroidDevice {
    param([string]$AdbPath)
    $rows = & $AdbPath devices
    if ($LASTEXITCODE -ne 0) { throw 'adb devices failed.' }
    foreach ($row in $rows) {
        if ($row -match '^(\S+)\s+device$') { return $Matches[1] }
    }
    return $null
}

function Invoke-AndroidFfmpegSmoke {
    param([string]$RootPath, [string]$ManifestPath)

    if ($HostIsWindows) {
        $sdkRoot = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
        $adbPath = Join-Path $sdkRoot 'platform-tools\adb.exe'
        $emulatorPath = Join-Path $sdkRoot 'emulator\emulator.exe'
    }
    else {
        $sdkRoot = $env:ANDROID_HOME
        $adbPath = Join-Path $sdkRoot 'platform-tools/adb'
        $emulatorPath = $null
    }
    Assert-True (Test-Path -LiteralPath $adbPath -PathType Leaf) 'Android platform-tools adb is required for the FFmpeg runtime probes.'

    $serial = Get-ConnectedAndroidDevice -AdbPath $adbPath
    $startedEmulator = $false
    $emulatorProcess = $null
    if (-not $serial -and $HostIsWindows -and (Test-Path -LiteralPath $emulatorPath -PathType Leaf)) {
        $emulatorProcess = Start-Process -FilePath $emulatorPath -ArgumentList @(
            '-avd', 'Pixel_10_Pro', '-no-window', '-no-audio', '-no-boot-anim'
        ) -WindowStyle Hidden -PassThru
        $startedEmulator = $true
    }
    if (-not $serial -and -not $startedEmulator) {
        throw 'No Android device or Pixel_10_Pro emulator is available for the FFmpeg runtime probes.'
    }
    try {
        for ($attempt = 0; $attempt -lt 120 -and -not $serial; $attempt++) {
            Start-Sleep -Seconds 2
            $serial = Get-ConnectedAndroidDevice -AdbPath $adbPath
        }
        Assert-True (-not [string]::IsNullOrWhiteSpace($serial)) 'No Android device or bootable Pixel_10_Pro emulator is available for the FFmpeg runtime probes.'

        $booted = $false
        for ($attempt = 0; $attempt -lt 120 -and -not $booted; $attempt++) {
            $bootState = (& $adbPath -s $serial shell getprop sys.boot_completed | Out-String).Trim()
            if ($LASTEXITCODE -eq 0 -and $bootState -eq '1') { $booted = $true }
            else { Start-Sleep -Seconds 2 }
        }
        Assert-True $booted "Android device '$serial' did not finish booting."

        $deviceAbi = (& $adbPath -s $serial shell getprop ro.product.cpu.abi | Out-String).Trim()
        $deviceModel = (& $adbPath -s $serial shell getprop ro.product.model | Out-String).Trim()
        $deviceApi = (& $adbPath -s $serial shell getprop ro.build.version.sdk | Out-String).Trim()
        $deviceDir = '/data/local/tmp/5a-04-ffmpeg'
        $outputDir = Join-Path $RootPath 'work/android/gate-5a/5a-04-ffmpeg'
        & $adbPath -s $serial shell mkdir -p $deviceDir
        if ($LASTEXITCODE -ne 0) { throw 'Could not create the FFmpeg device test directory.' }
        & $adbPath -s $serial push (Join-Path $outputDir 'ffmpeg') "$deviceDir/ffmpeg"
        if ($LASTEXITCODE -ne 0) { throw 'Could not push ffmpeg to the Android test device.' }
        & $adbPath -s $serial push (Join-Path $outputDir 'ffprobe') "$deviceDir/ffprobe"
        if ($LASTEXITCODE -ne 0) { throw 'Could not push ffprobe to the Android test device.' }
        & $adbPath -s $serial push (Join-Path $RootPath 'scripts/gate-5a/ffmpeg-device-smoke.sh') "$deviceDir/ffmpeg-device-smoke.sh"
        if ($LASTEXITCODE -ne 0) { throw 'Could not push the FFmpeg smoke script to the Android test device.' }
        & $adbPath -s $serial shell chmod 755 "$deviceDir/ffmpeg" "$deviceDir/ffprobe" "$deviceDir/ffmpeg-device-smoke.sh"
        if ($LASTEXITCODE -ne 0) { throw 'Could not make the Android FFmpeg test files executable.' }
        & $adbPath -s $serial shell sh "$deviceDir/ffmpeg-device-smoke.sh"
        if ($LASTEXITCODE -ne 0) { throw 'Android FFmpeg MP3/MP4 runtime probes failed.' }

        $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
        $manifest | Add-Member -NotePropertyName runtimeSmoke -NotePropertyValue ([ordered]@{
            status = 'passed'
            deviceSerial = $serial
            deviceModel = $deviceModel
            deviceAbi = $deviceAbi
            apiLevel = $deviceApi
            tests = @('MP3 encode/probe', 'MP4 encode/remux/probe', 'x264/x265 absent')
        }) -Force
        $manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
    }
    finally {
        if ($startedEmulator) {
            if ($serial) { & $adbPath -s $serial emu kill *> $null }
            elseif ($emulatorProcess -and -not $emulatorProcess.HasExited) {
                Stop-Process -Id $emulatorProcess.Id -Force
            }
        }
    }
}

try {
    $root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $sourcesPath = Join-Path $root 'docs\engine-sources.md'
    $buildsPath = Join-Path $root 'docs\engine-builds.md'
    $toolchainPath = Join-Path $root 'docs\toolchain.md'
    $decisionPath = Join-Path $root 'docs\gates\evidence\5a\python-runtime-decision.md'
    $noticesPath = Join-Path $root 'docs\THIRD-PARTY-NOTICES.md'

    foreach ($path in @($sourcesPath, $buildsPath, $toolchainPath, $decisionPath, $noticesPath)) {
        Assert-True (Test-Path -LiteralPath $path -PathType Leaf) "Required task file is missing: $path"
    }

    $sourcesText = Get-Content -LiteralPath $sourcesPath -Raw
    $buildsText = Get-Content -LiteralPath $buildsPath -Raw
    $toolchainText = Get-Content -LiteralPath $toolchainPath -Raw
    $decisionText = Get-Content -LiteralPath $decisionPath -Raw
    $noticesText = Get-Content -LiteralPath $noticesPath -Raw
    $lock = Read-JsonFence $sourcesText 'android-python-runtime-lock'
    $sourceLock = Read-JsonFence $sourcesText 'source-lock'

    Assert-Equal $lock.schema 1 'Runtime lock schema'
    Assert-Equal $lock.status 'owner-approved' 'Runtime lock status'
    Assert-Equal $lock.approvedOn '2026-11-22' 'Owner approval date'
    Assert-Equal $lock.approach 'cpython-source-embedded-jni' 'Approved approach'
    Assert-Equal $lock.python.version '3.14.10' 'CPython version'
    Assert-Equal $lock.python.license 'PSF-2.0' 'CPython license'
    Assert-Equal $lock.python.sourceUrl 'https://www.python.org/ftp/python/3.14.10/Python-3.14.10.tar.xz' 'CPython source URL'
    Assert-Equal $lock.python.sha256 'de414a57119abef52784d8993e341d53aed635fc2b05c2607d9f98a2c5b72032' 'CPython source SHA-256'
    Assert-Equal $lock.python.androidHost 'aarch64-linux-android' 'Android target'
    Assert-Equal $lock.python.apiLevel 24 'Runtime API level'
    Assert-Equal $lock.python.ndkPatch.file 'Android/android-env.sh' 'CPython NDK patch target'
    Assert-Equal $lock.python.ndkPatch.from '27.3.13750724' 'CPython original NDK pin'
    Assert-Equal $lock.python.ndkPatch.to '30.0.16248370' 'CPython patched NDK pin'
    Assert-Equal $lock.sourceDependenciesRepository.url 'https://github.com/beeware/cpython-android-source-deps' 'Native recipe repository'
    Assert-Equal $lock.sourceDependenciesRepository.license 'MIT' 'Native recipe repository license'
    Assert-Equal $lock.sourceDependenciesRepository.ndkPatch.file 'android-env.sh' 'Recipe repository NDK patch target'
    Assert-Equal $lock.sourceDependenciesRepository.ndkPatch.to '30.0.16248370' 'Recipe repository patched NDK pin'

    $expectedNative = @(
        @{ name = 'bzip2'; version = '1.0.8'; build = '3'; sha256 = 'ab5a03176ee106d3f0fa90e381da478ddae405918153cca248e682cd0c4a2269'; recipeTag = 'bzip2-1.0.8-3'; recipeCommit = 'dcea166d40d573e963a35435e48b047afe243c2d'; recipeNdkFrom = '27.2.12479018'; patches = 'symlink.patch' },
        @{ name = 'libffi'; version = '3.4.4'; build = '3'; sha256 = 'd66c56ad259a82cf2a9dfc408b32bf5da52371500b84745f7fb8b645712df676'; recipeTag = 'libffi-3.4.4-3'; recipeCommit = '65d87e392d69198f3dd1ed2feb3b5fcea1b029a6'; recipeNdkFrom = '27.1.12297006'; patches = 'long_double.patch,open_temp_exec_file.patch' },
        @{ name = 'openssl'; version = '3.5.9'; build = '0'; sha256 = '603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a'; recipeTag = 'openssl-3.5.9-0'; recipeCommit = '5521f2c16ee87dd7f9d081421351f675fac2ee45'; recipeNdkFrom = '27.2.12479018'; patches = 'at_secure.patch,configuration.patch,soname-3.patch' },
        @{ name = 'sqlite'; version = '3.53.4'; build = '0'; sha256 = '0e9483900e92cd5de8fd48d16bf9200145a61f7fd5be542a5ac81d8a9516eb9c'; recipeTag = 'sqlite-3.53.4-0'; recipeCommit = '5521f2c16ee87dd7f9d081421351f675fac2ee45'; recipeNdkFrom = '27.2.12479018'; patches = 'soname.patch' },
        @{ name = 'xz'; version = '5.4.6'; build = '1'; sha256 = 'aeba3e03bf8140ddedf62a0a367158340520f6b384f75ca6045ccc6c0d43fd5c'; recipeTag = 'xz-5.4.6-1'; recipeCommit = '65d87e392d69198f3dd1ed2feb3b5fcea1b029a6'; recipeNdkFrom = '27.1.12297006'; patches = '' },
        @{ name = 'zstd'; version = '1.5.7'; build = '2'; sha256 = 'eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3'; recipeTag = 'zstd-1.5.7-2'; recipeCommit = 'f4c94a0fbc359d17993547b66f0627d436f8897b'; recipeNdkFrom = '27.2.12479018'; patches = '' }
    )
    $nativeDependencyCount = @($lock.nativeDependencies).Count
    Assert-Equal $nativeDependencyCount $expectedNative.Count 'Native dependency count'
    foreach ($expected in $expectedNative) {
        $entries = @($lock.nativeDependencies | Where-Object { $_.name -ceq $expected.name })
        Assert-Equal $entries.Count 1 "Native dependency '$($expected.name)' count"
        $entry = $entries[0]
        foreach ($field in @('version', 'build', 'sha256', 'recipeTag', 'recipeCommit', 'recipeNdkFrom')) {
            Assert-Equal $entry.$field $expected[$field] "$($expected.name) $field"
        }
        Assert-Equal (@($entry.patches) -join ',') $expected.patches "$($expected.name) patches"
        Assert-True ($entry.sourceUrl -cmatch '^https://') "$($expected.name) source URL is not pinned."
        Assert-True (-not [string]::IsNullOrWhiteSpace([string]$entry.license)) "$($expected.name) license is missing."
    }

    $expectedPackages = @(
        @{ name = 'Brotli'; version = '1.2.0'; sha256 = 'e310f77e41941c13340a95976fe66a8a95b01e783d430eeaf7a2f87e0a57dd0a' },
        @{ name = 'certifi'; version = '2026.7.22'; sha256 = '741e2c3b351ddf169a738da9f2c048608ff7f2c5cc02f1ebc6b118bb090d5d55' },
        @{ name = 'charset-normalizer'; version = '3.5.0'; sha256 = '49bd5feb59b0bf3cbf6ebcf4352e371c95b9da9bacd4449f8b64d0ad2c10a26e' },
        @{ name = 'idna'; version = '3.18'; sha256 = 'ffb385a7e039654cef1ab9ef32c6fafe283c0c0467bba1d9029738ce4a14a848' },
        @{ name = 'mutagen'; version = '1.48.1'; sha256 = '8f95637ab9f6f305cec6bd1294e197debe207998e3e068596563c74f86b0a173' },
        @{ name = 'pycryptodomex'; version = '3.23.0'; sha256 = '71909758f010c82bc99b0abf4ea12012c98962fbf0583c2164f8b84533c2e4da' },
        @{ name = 'requests'; version = '2.34.2'; sha256 = 'f288924cae4e29463698d6d60bc6a4da69c89185ad1e0bcc4104f584e960b9ed' },
        @{ name = 'urllib3'; version = '2.7.0'; sha256 = '231e0ec3b63ceb14667c67be60f2f2c40a518cb38b03af60abc813da26505f4c' },
        @{ name = 'websockets'; version = '17.0.1'; sha256 = '5baa9bc0dfbae8c507e51c8cf1b6d4628086f7a87bbd3a9952bd5f035451f1cc' }
    )
    $pythonPackageCount = @($lock.pythonPackages).Count
    Assert-Equal $pythonPackageCount $expectedPackages.Count 'Python package count'
    foreach ($expected in $expectedPackages) {
        $entries = @($lock.pythonPackages | Where-Object { $_.name -ceq $expected.name })
        Assert-Equal $entries.Count 1 "Python package '$($expected.name)' count"
        $entry = $entries[0]
        Assert-Equal $entry.version $expected.version "$($expected.name) version"
        Assert-Equal $entry.sha256 $expected.sha256 "$($expected.name) source SHA-256"
        Assert-True ($entry.sourceUrl -cmatch '^https://files\.pythonhosted\.org/') "$($expected.name) source URL is not a PyPI source archive."
        Assert-True (-not [string]::IsNullOrWhiteSpace([string]$entry.license)) "$($expected.name) license is missing."
    }

    foreach ($name in @('ytDlp', 'ejs', 'quickjs')) {
        Assert-True ($null -ne $lock.$name) "Missing $name pointer in runtime lock."
    }
    Assert-Equal $lock.ytDlp.sourceLockKey 'ytDlp' 'yt-dlp source-lock key'
    Assert-Equal $lock.ytDlp.sha256 $sourceLock.ytDlp.source.sha256 'yt-dlp source-lock SHA-256'
    Assert-Equal $lock.ytDlp.sourceUrl $sourceLock.ytDlp.source.url 'yt-dlp source-lock URL'
    Assert-Equal $lock.ytDlp.version $sourceLock.ytDlp.version 'yt-dlp source-lock version'
    Assert-Equal $lock.ytDlp.version '2026.08.19' 'yt-dlp version'
    Assert-Equal $lock.ejs.sourceLockKey 'ejs' 'EJS source-lock key'
    Assert-Equal $lock.ejs.sha256 $sourceLock.ejs.source.sha256 'EJS source-lock SHA-256'
    Assert-Equal $lock.ejs.sourceUrl $sourceLock.ejs.source.url 'EJS source-lock URL'
    Assert-Equal $lock.ejs.version $sourceLock.ejs.version 'EJS source-lock version'
    Assert-Equal $lock.ejs.version '0.8.0' 'EJS version'
    Assert-Equal $lock.quickjs.sourceLockKey 'quickjs' 'QuickJS source-lock key'
    Assert-Equal $lock.quickjs.sha256 $sourceLock.quickjs.source.sha256 'QuickJS source-lock SHA-256'
    Assert-Equal $lock.quickjs.sourceUrl $sourceLock.quickjs.source.url 'QuickJS source-lock URL'
    Assert-Equal $lock.quickjs.version $sourceLock.quickjs.version 'QuickJS source-lock version'
    Assert-Equal $lock.quickjs.version '2026-06-04' 'QuickJS version'

    $expectedTools = @{
        host = 'ubuntu-24.04-x86_64'; jdk = '21.0.11.10.1'; androidApi = '36'
        buildTools = '36.0.0'; platformTools = '37.0.3'; commandLineTools = '22.0'
        ndk = '30.0.16248370'; abi = 'arm64-v8a'
    }
    foreach ($name in $expectedTools.Keys) {
        Assert-Equal $lock.buildTools.$name $expectedTools[$name] "Build tool '$name'"
    }

    $expectedBuildTools = @(
        @{ name = 'setuptools'; version = '84.1.0'; sha256 = '23657205b63d4d31395ab917815247f694aafad28cd21316bf5fd45a51048ea0'; wheelSha256 = '5231689c6ac8156cd155cfb98c3fd6fb252c3e7e9bd3d78b64d3c55f132624c9' },
        @{ name = 'flit-core'; version = '3.12.0'; sha256 = '18f63100d6f94385c6ed57a72073443e1a71a4acb4339491615d0f16d6ff01b2'; wheelSha256 = 'e7a0304069ea895172e3c7bb703292e992c5d1555dd1233ab7b5621b5b69e62c' },
        @{ name = 'hatchling'; version = '1.33.0'; sha256 = '4c422bd4d554fcff5de5b73e9596f85e41e9f97f7e553d8f7595ecb31a627bef'; wheelSha256 = '415290b84f464d2884303fca8974d38e7b85579069fab02a15db0828fbb1446d' },
        @{ name = 'hatch-vcs'; version = '0.5.0'; sha256 = '0395fa126940340215090c344a2bf4e2a77bcbe7daab16f41b37b98c95809ff9'; wheelSha256 = 'b49677dbdc597460cc22d01b27ab3696f5e16a21ecf2700fb01bc28e1f2a04a7' },
        @{ name = 'setuptools-scm'; version = '10.3.4'; sha256 = 'a69f28bfc245608781205e912faae437c2b2165773afa4e7b979d77447a69dd2'; wheelSha256 = '82f34c3e3084fc2b57d397200637cc13f2338004052d2fee47baa5f0e902464e' },
        @{ name = 'packaging'; version = '26.3'; sha256 = '94edc256424af38762eb31306eed28beb9f0efc50a8837492c9d6fd6004aed79'; wheelSha256 = 'd7193f7c8e4e93f444fde0262bf90af30e16fa0ad0ad44cb553c87339b23cd1c' },
        @{ name = 'pathspec'; version = '1.1.1'; sha256 = '17db5ecd524104a120e173814c90367a96a98d07c45b2e10c2f3919fff91bf5a'; wheelSha256 = 'a00ce642f577bf7f473932318056212bc4f8bfdf53128c78bbd5af0b9b20b189' },
        @{ name = 'pluggy'; version = '1.7.0'; sha256 = 'd1eaa46ebb595891b860ab086b4d09c8588af65ebd4361b8e8f4bb8920b90ba8'; wheelSha256 = '7dd7b0d8832ba3cb632c306926ded123429211b83641b35dc5c41ad2d34f9bec' },
        @{ name = 'tomlkit'; version = '0.14.0'; sha256 = 'cf00efca415dbd57575befb1f6634c4f42d2d87dbba376128adb42c121b87064'; wheelSha256 = '592064ed85b40fa213469f81ac584f67a4f2992509a7c3ea2d632208623a3680' },
        @{ name = 'trove-classifiers'; version = '2026.9.21.13'; sha256 = '0a9ebc8d4e2f3e8a22848c5258033035bec17a3012ac3fea16dbaa764489eb71'; wheelSha256 = '8b1ff4f9c191b1040b71c37f1e445ab99732911e3cd91de52838453a854d7a17' },
        @{ name = 'vcs-versioning'; version = '2.6.0'; sha256 = '22e9159288e2d8bca2fa6f6c31c34c9c66aec157f60e9e526f5d160d2516d60f'; wheelSha256 = 'f8bebd1302ebc12e67ceb30fc7dd698ec969414b6fa43b30c3f14ac9b1e72c41' }
    )
    $buildToolCount = @($lock.pythonBuildTools).Count
    Assert-Equal $buildToolCount $expectedBuildTools.Count 'Pinned Python build tool count'
    foreach ($expected in $expectedBuildTools) {
        $entries = @($lock.pythonBuildTools | Where-Object { $_.name -ceq $expected.name })
        Assert-Equal $entries.Count 1 "Python build tool '$($expected.name)' count"
        foreach ($field in @('version', 'sha256', 'wheelSha256')) {
            Assert-Equal $entries[0].$field $expected[$field] "Python build tool '$($expected.name)' $field"
        }
    }

    Assert-True ($decisionText.Contains('Owner decision: CPython approved on 2026-11-22')) 'Decision memo does not record owner approval.'
    Assert-True ($decisionText.Contains('AndroidEnginePackage')) 'Decision memo omits the package boundary.'
    Assert-True ($decisionText.Contains('22–35 MB')) 'Decision memo omits the unmeasured package-size estimate.'
    Assert-True ($decisionText -match 'desktop-only\s+first-release\s+fallback') 'Decision memo omits the fallback.'
    Assert-True ($buildsText.Contains('./android.py configure-build')) 'CPython build-Python configure command is missing.'
    Assert-True ($buildsText.Contains('./android.py make-build')) 'CPython build-Python compile command is missing.'
    Assert-True ($buildsText.Contains('./android.py configure-host aarch64-linux-android')) 'CPython Android host configure command is missing.'
    Assert-True ($buildsText.Contains('./android.py make-host aarch64-linux-android')) 'CPython Android host compile command is missing.'
    Assert-True ($buildsText.Contains('./android.py package aarch64-linux-android')) 'CPython package command is missing.'
    Assert-True ($buildsText.Contains('cross-build/downloads/')) 'Source-built native dependency cache is undocumented.'
    Assert-True ($buildsText.Contains('prebuilt GitHub release archives are not allowed')) 'Build recipe permits opaque native archives.'
    Assert-True ($buildsText.Contains('without allowing `pip` to resolve')) 'Build recipe does not block unpinned pip resolution.'
    Assert-True ($toolchainText.Contains('cmdline-tools/latest')) 'Pinned SDK alias requirement is missing.'
    Assert-True ($toolchainText.Contains('ANDROID_API_LEVEL=24')) 'Runtime API level setup is missing.'
    Assert-True ($toolchainText.Contains('30.0.16248370')) 'Pinned NDK setup is missing.'

    if ($Case -eq 'python-runtime') {
        Assert-True $HostIsLinux 'The CPython runtime build must run on the pinned Ubuntu Linux host.'
        $buildScript = Join-Path $PSScriptRoot 'build-python-runtime.sh'
        Assert-True (Test-Path -LiteralPath $buildScript -PathType Leaf) 'The CPython runtime build script is missing.'
        $linuxBuildScript = Join-Path $PSScriptRoot ".build-python-runtime-$PID.sh"
        $buildScriptText = Get-Content -LiteralPath $buildScript -Raw
        [System.IO.File]::WriteAllText(
            $linuxBuildScript,
            ($buildScriptText -replace "`r`n?", "`n"),
            [System.Text.UTF8Encoding]::new($false)
        )
        try {
            & bash $linuxBuildScript
            $buildExitCode = $LASTEXITCODE
        }
        finally {
            Remove-Item -LiteralPath $linuxBuildScript -Force -ErrorAction SilentlyContinue
        }
        if ($buildExitCode -ne 0) {
            $buildLog = Join-Path $root 'work/android/gate-5a/5a-03-cpython/python-runtime-build.log'
            if (Test-Path -LiteralPath $buildLog -PathType Leaf) {
                Get-Content -LiteralPath $buildLog -Tail 50 | Write-Output
            }
            throw "CPython runtime builder failed with exit code $buildExitCode."
        }

        $manifestPath = Join-Path $root 'work/android/gate-5a/5a-03-cpython/runtime-manifest.json'
        Assert-True (Test-Path -LiteralPath $manifestPath -PathType Leaf) 'The CPython runtime manifest was not produced.'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        Assert-Equal $manifest.pythonVersion '3.14.10' 'Built CPython version'
        Assert-Equal $manifest.target 'aarch64-linux-android' 'Built CPython target'
        Assert-Equal $manifest.abi 'arm64-v8a' 'Built CPython ABI'
        Assert-Equal $manifest.ndk '30.0.16248370' 'Built CPython NDK'
        Assert-Equal $manifest.packages.Count ($lock.pythonPackages.Count + 2) 'Built Python package count'
        Assert-True ($manifest.nativeLibraries.Count -gt 0) 'The runtime manifest contains no native libraries.'
        Write-Output "PASS: CPython $($manifest.pythonVersion) runtime and locked yt-dlp/EJS packages built for $($manifest.abi)."
        Write-Output "Runtime archive SHA-256: $($manifest.runtimeArchive.sha256)"
    }
    elseif ($Case -eq 'python-source-lock') {
        Write-Output 'PASS: CPython Android source lock, owner decision, and build-tool pins are consistent.'
    }
    elseif ($Case -eq 'quickjs') {
        $quickJsLock = $sourceLock.quickjs
        $ytDlpLock = $sourceLock.ytDlp
        $ejsLock = $sourceLock.ejs
        Assert-Equal $quickJsLock.version '2026-06-04' 'Android QuickJS source version'
        Assert-Equal $quickJsLock.source.url 'https://bellard.org/quickjs/quickjs-2026-06-04.tar.xz' 'Android QuickJS source URL'
        Assert-Equal $quickJsLock.source.sha256 'b376e839b322978313d929fd20663b11ba58b75df5a46c126dd19ea2fa70ad2a' 'Android QuickJS source SHA-256'
        Assert-True ($quickJsLock.targets -contains 'android-arm64') 'QuickJS source lock omits Android arm64.'
        Assert-Equal $lock.quickjs.version $quickJsLock.version 'Runtime QuickJS version'
        Assert-Equal $lock.quickjs.sourceUrl $quickJsLock.source.url 'Runtime QuickJS source URL'
        Assert-Equal $lock.quickjs.sha256 $quickJsLock.source.sha256 'Runtime QuickJS source SHA-256'

        Assert-Equal $ytDlpLock.version '2026.08.19' 'yt-dlp runtime version'
        Assert-Equal $ytDlpLock.source.url 'https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.19/yt-dlp.tar.gz' 'yt-dlp source URL'
        Assert-Equal $ytDlpLock.source.sha256 '072aad4f2a7604e92155f61a275a4752dc64046c8f6d90df3710525d94cd37c1' 'yt-dlp source SHA-256'
        Assert-Equal $ejsLock.version '0.8.0' 'yt-dlp-ejs runtime version'
        Assert-Equal $ejsLock.source.url 'https://files.pythonhosted.org/packages/d3/e6/cceb9530e8f4e5940f6f7822d90e9d94f1b85343329a16baaf47bbbb3de1/yt_dlp_ejs-0.8.0.tar.gz' 'yt-dlp-ejs source URL'
        Assert-Equal $ejsLock.source.sha256 'd5fa1639f63b5c4af8d932495f60689d5370f1a095782c944f7f62a303eb104e' 'yt-dlp-ejs source SHA-256'

        Assert-True ($buildsText.Contains('5A-05 Android arm64-v8a QuickJS 2026-06-04')) 'Android QuickJS build recipe is missing.'
        Assert-True ($buildsText.Contains('LIBS=-lm -ldl')) 'Android QuickJS link inputs are not recorded.'
        Assert-True ($buildsText.Contains('absolute build path')) 'Android QuickJS debug-path hash behavior is not documented.'
        Assert-True ($noticesText.Contains('Android arm64/API 24') -and $noticesText.Contains('QuickJS 2026-06-04')) 'Android QuickJS notice entry is missing.'
        Assert-True ($toolchainText.Contains('5A-05 Android QuickJS build')) 'Android QuickJS build toolchain is undocumented.'

        $buildScript = Join-Path $root 'scripts/gate-0b/build-quickjs.sh'
        Assert-True (Test-Path -LiteralPath $buildScript -PathType Leaf) 'The pinned QuickJS source builder is missing.'
        if ($HostIsLinux) {
            & bash $buildScript android-arm64 --verify
            $buildExitCode = $LASTEXITCODE
        }
        elseif ($HostIsWindows) {
            $windowsScriptPath = (Resolve-Path -LiteralPath $buildScript).Path.Replace('\', '/')
            $linuxScript = (& wsl.exe -d Ubuntu-24.04 -- wslpath -u $windowsScriptPath | Out-String).Trim()
            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($linuxScript)) {
                throw 'Could not map the QuickJS build script into Ubuntu-24.04 WSL.'
            }
            $linuxTempScript = $linuxScript + '.wsl'
            $linuxCommand = 'export ANDROID_HOME="$HOME/Android/Sdk" ANDROID_SDK_ROOT="$HOME/Android/Sdk" ANDROID_NDK_HOME="$HOME/Android/Sdk/ndk/30.0.16248370" NDK_HOME="$HOME/Android/Sdk/ndk/30.0.16248370"; tr -d ''\015'' < "' + $linuxScript + '" > "' + $linuxTempScript + '" || exit 1; bash "' + $linuxTempScript + '" android-arm64 --verify; build_status=$?; rm -f "' + $linuxTempScript + '"; exit "$build_status"'
            & wsl.exe -d Ubuntu-24.04 -- bash -lc $linuxCommand
            $buildExitCode = $LASTEXITCODE
        }
        else {
            throw 'The Android QuickJS build requires Ubuntu 24.04 or Windows with Ubuntu-24.04 WSL.'
        }
        if ($buildExitCode -ne 0) { throw "Android QuickJS builder failed with exit code $buildExitCode." }

        $artifactPath = Join-Path $root 'work/engine/build/quickjs/android-arm64/qjs'
        Assert-True (Test-Path -LiteralPath $artifactPath -PathType Leaf) 'The Android QuickJS ELF was not produced.'
        $artifactHash = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
        Assert-True ($artifactHash -cmatch '^[0-9a-f]{64}$') 'Android QuickJS artifact SHA-256 is malformed.'
        Write-Output "PASS: Android QuickJS $($quickJsLock.version) ELF and locked yt-dlp $($ytDlpLock.version)/EJS $($ejsLock.version) inputs are consistent."
        Write-Output "Android QuickJS SHA-256: $artifactHash"
        Write-Output 'YouTube JavaScript challenge execution on Android remains a device check after the Gate 5A adapter is wired.'
    }
    elseif ($Case -eq 'package-provenance') {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $manifestPath = Join-Path $root 'work/android/gate-5a/5a-06-package/android-engine-manifest.json'
        $apkPath = Join-Path $root 'src-tauri/gen/android/app/build/outputs/apk/universal/debug/app-universal-debug.apk'
        $gradlePath = Join-Path $root 'src-tauri/gen/android/app/build.gradle.kts'
        Assert-True (Test-Path -LiteralPath $manifestPath -PathType Leaf) 'The staged Android engine manifest is missing; run stage-android-package.ps1 first.'
        Assert-True (Test-Path -LiteralPath $apkPath -PathType Leaf) 'The local Android debug APK is missing; run npm run android:debug first.'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        Assert-Equal $manifest.schema 1 'Android package manifest schema'
        Assert-Equal $manifest.package.abi 'arm64-v8a' 'Android package ABI'
        Assert-Equal $manifest.package.apiLevel 24 'Android engine API level'
        Assert-Equal $manifest.packageStatus 'staged; APK hash verification pending' 'Android package staging status'
        Assert-Equal $manifest.stagedFileCount $manifest.stagedFiles.Count 'Staged engine file count'
        Assert-True ($manifest.components.Count -ge 20) 'The transitive Android engine component inventory is incomplete.'
        Assert-True ($manifest.sourceMaterials.Count -ge $manifest.components.Count) 'Corresponding source archive coverage is incomplete.'

        $gradleText = Get-Content -LiteralPath $gradlePath -Raw
        Assert-True ($gradleText -notmatch 'io\.github\.junkfood02\.youtubedl-android|implementation\s*\([^\r\n]*0\.18\.1') 'The Android app still declares the opaque 0.18.1 engine AARs.'
        foreach ($source in $manifest.sourceMaterials) {
            $sourcePath = Join-Path $root ($source.localPath -replace '/', '\')
            Assert-True (Test-Path -LiteralPath $sourcePath -PathType Leaf) "Locked source archive is missing: $($source.name)"
            Assert-Equal (Get-Sha256 $sourcePath) $source.sha256 "$($source.name) source archive SHA-256"
        }
        foreach ($record in $manifest.auditRecords) {
            $recordPath = Join-Path $root ($record.path -replace '/', '\')
            Assert-True (Test-Path -LiteralPath $recordPath -PathType Leaf) "Audited build record is missing: $($record.path)"
            Assert-Equal (Get-Sha256 $recordPath) $record.sha256 "$($record.path) audit record SHA-256"
        }
        foreach ($component in $manifest.components) {
            Assert-True ($noticesText.IndexOf([string]$component.name, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) "The third-party notice inventory omits '$($component.name)'."
            Assert-True (@($manifest.sourceMaterials | Where-Object sha256 -CEQ $component.sourceSha256).Count -gt 0) "The source archive inventory omits '$($component.name)'."
        }
        foreach ($buildManifest in $manifest.buildManifests) {
            $buildManifestPath = Join-Path $root ($buildManifest.path -replace '/', '\')
            Assert-True (Test-Path -LiteralPath $buildManifestPath -PathType Leaf) "Source-build evidence is missing: $($buildManifest.path)"
            if ($buildManifest.sha256) { Assert-Equal (Get-Sha256 $buildManifestPath) $buildManifest.sha256 "$($buildManifest.path) SHA-256" }
        }
        $quickJsPath = Join-Path $root 'work/engine/build/quickjs/android-arm64/qjs'
        Assert-Equal (Get-Sha256 $quickJsPath) $manifest.buildManifests[2].artifactSha256 'QuickJS staged source-build artifact SHA-256'
        $zip = [System.IO.Compression.ZipFile]::OpenRead($apkPath)
        try {
            $entries = [System.Collections.Generic.Dictionary[string, System.IO.Compression.ZipArchiveEntry]]::new([System.StringComparer]::Ordinal)
            foreach ($entry in $zip.Entries) {
                if (-not $entry.FullName.EndsWith('/')) { $entries[$entry.FullName] = $entry }
            }

            Assert-True $entries.ContainsKey($manifest.assetArchive.apkPath) 'The APK is missing the Python runtime asset archive.'
            $archiveEntry = $entries[$manifest.assetArchive.apkPath]
            Assert-Equal $archiveEntry.Length $manifest.assetArchive.bytes 'Python runtime archive byte length'
            Assert-Equal (Get-ZipEntrySha256 $archiveEntry) $manifest.assetArchive.sha256 'Python runtime archive SHA-256'
            $archiveStream = $archiveEntry.Open()
            $archiveMemory = [System.IO.MemoryStream]::new()
            try {
                $archiveStream.CopyTo($archiveMemory)
                $archiveMemory.Position = 0
                $runtimeZip = [System.IO.Compression.ZipArchive]::new($archiveMemory, [System.IO.Compression.ZipArchiveMode]::Read, $true)
            }
            finally {
                $archiveStream.Dispose()
            }
            try {
                $runtimeEntries = [System.Collections.Generic.Dictionary[string, System.IO.Compression.ZipArchiveEntry]]::new([System.StringComparer]::Ordinal)
                foreach ($entry in $runtimeZip.Entries) {
                    if (-not $entry.FullName.EndsWith('/')) { $runtimeEntries[$entry.FullName] = $entry }
                }
                Assert-Equal $runtimeEntries.Count $manifest.assetArchive.entryCount 'Python runtime archive entry count'

                $expectedPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
                foreach ($file in $manifest.stagedFiles) {
                    if ($file.archivePath) {
                        Assert-True ($expectedPaths.Add("$($file.apkPath)!$($file.archivePath)")) "Duplicate staged asset archive entry: $($file.archivePath)"
                        Assert-True $runtimeEntries.ContainsKey($file.archivePath) "Python runtime archive is missing: $($file.archivePath)"
                        $apkPayloadEntry = $runtimeEntries[$file.archivePath]
                    }
                    else {
                        Assert-True ($expectedPaths.Add([string]$file.apkPath)) "Duplicate staged APK entry: $($file.apkPath)"
                        Assert-True $entries.ContainsKey($file.apkPath) "APK engine payload is missing: $($file.apkPath)"
                        $apkPayloadEntry = $entries[$file.apkPath]
                    }
                    Assert-Equal $apkPayloadEntry.Length $file.bytes "$($file.apkPath) byte length"
                    Assert-Equal (Get-ZipEntrySha256 $apkPayloadEntry) $file.sha256 "$($file.apkPath) SHA-256"
                }
            }
            finally {
                $runtimeZip.Dispose()
                $archiveMemory.Dispose()
            }

            $nativeEntries = @($entries.Keys | Where-Object { $_ -match '^lib/[^/]+/' })
            $nativeAbis = @($nativeEntries | ForEach-Object { ($_ -split '/')[1] } | Sort-Object -Unique)
            Assert-Equal ($nativeAbis -join ',') 'arm64-v8a' 'APK native ABI set'
            foreach ($nativeEntry in $nativeEntries) {
                Assert-True ($expectedPaths.Contains($nativeEntry) -or $manifest.appBuild.allowedGeneratedNativePaths -contains $nativeEntry) "Unexpected APK native library: $nativeEntry"
            }
            $stagedNativeEntries = @($manifest.stagedFiles | Where-Object { $_.apkPath -like 'lib/arm64-v8a/*' })
            Assert-True ($nativeEntries.Count -eq ($stagedNativeEntries.Count + $manifest.appBuild.allowedGeneratedNativePaths.Count)) 'APK native library count differs from the manifest.'
            Assert-True (-not ($entries.Keys | Where-Object { $_ -match '\.aar$|libpython\.so$|libpython\.zip\.so$' })) 'The APK contains an obsolete Android engine AAR payload.'
            Assert-True (-not ($entries.Keys | Where-Object { $_ -match 'youtubedl-android|0\.18\.1' })) 'The APK contains an obsolete Android engine package marker.'
            foreach ($dexEntry in @($entries.Values | Where-Object { $_.FullName -match '^classes(\d+)?\.dex$' })) {
                $dexStream = $dexEntry.Open()
                $memory = [System.IO.MemoryStream]::new()
                try {
                    $dexStream.CopyTo($memory)
                    $dexText = [System.Text.Encoding]::ASCII.GetString($memory.ToArray())
                    Assert-True ($dexText -notmatch 'com/yausername/youtubedl_android|com/yausername/ffmpeg|0\.18\.1') 'The APK still contains classes compiled from the 0.18.1 engine AARs.'
                }
                finally {
                    $dexStream.Dispose()
                    $memory.Dispose()
                }
            }

            $apkHash = Get-Sha256 $apkPath
            $manifest | Add-Member -NotePropertyName apkVerification -NotePropertyValue ([ordered]@{
                path = 'src-tauri/gen/android/app/build/outputs/apk/universal/debug/app-universal-debug.apk'
                sha256 = $apkHash
                bytes = (Get-Item -LiteralPath $apkPath).Length
                abi = 'arm64-v8a'
                verifiedEngineEntries = $manifest.stagedFileCount
                verifiedNativeEntries = $nativeEntries.Count
                verifiedRuntimeArchiveEntries = $manifest.assetArchive.entryCount
                status = 'passed'
            }) -Force
            $manifest.packageStatus = 'APK provenance verified'
        }
        finally {
            $zip.Dispose()
        }

        $evidenceManifest = Join-Path $root 'docs/gates/evidence/5a/5a-06-apk-engine-manifest.json'
        $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding utf8
        Copy-Item -LiteralPath $manifestPath -Destination $evidenceManifest -Force
        $nativePayloadCount = @($manifest.stagedFiles | Where-Object { $_.component -like 'CPython native*' -or $_.apkPath -like 'lib/arm64-v8a/*' }).Count
        Write-Output "PASS: APK engine provenance verified ($($manifest.stagedFileCount) engine files; $nativePayloadCount native runtime files; $($manifest.apkVerification.verifiedRuntimeArchiveEntries) ZIP entries)."
        Write-Output "APK SHA-256: $apkHash"
        Write-Output "Manifest: docs/gates/evidence/5a/5a-06-apk-engine-manifest.json"
    }
    else {
        $ffmpegLock = $sourceLock.ffmpeg
        $lameLock = $sourceLock.lame
        $zlibLock = $sourceLock.zlib
        Assert-Equal $ffmpegLock.version '8.1.3' 'Android FFmpeg source version'
        Assert-Equal $ffmpegLock.source.sha256 '7138d28c96d9d3e3af4ee3d8cad72741f8ffb40da90c1112235dea3ecd3178a3' 'Android FFmpeg source SHA-256'
        Assert-Equal $ffmpegLock.source.signatureSha256 '5f2880c7fea01f8694d30cb9d06362f77241ee67ce5926b157a226b18f08a538' 'Android FFmpeg signature SHA-256'
        Assert-Equal $ffmpegLock.signingKey.fingerprint 'FCF986EA15E6E293A5644F10B4322F04D67658D8' 'Android FFmpeg signing key'
        Assert-True ($ffmpegLock.targets -contains 'android-arm64') 'FFmpeg source lock omits Android arm64.'
        Assert-Equal $lameLock.version '3.100' 'Android LAME source version'
        Assert-Equal $lameLock.source.sha256 'ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e' 'Android LAME source SHA-256'
        Assert-True ($lameLock.targets -contains 'android-arm64') 'LAME source lock omits Android arm64.'
        Assert-Equal $zlibLock.version '1.3.2' 'Android zlib source version'
        Assert-Equal $zlibLock.source.sha256 'bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16' 'Android zlib source SHA-256'
        Assert-True ($zlibLock.targets -contains 'android-arm64') 'zlib source lock omits Android arm64.'

        Assert-True ($buildsText.Contains('Android arm64-v8a GPL FFmpeg 8.1.3')) 'Android FFmpeg build recipe is missing.'
        Assert-True ($buildsText.Contains('--enable-gpl')) 'Android build recipe does not record its GPL configuration.'
        Assert-True ($buildsText.Contains('--disable-everything')) 'Android FFmpeg feature allowlist is not recorded.'
        Assert-True ($buildsText.Contains('--enable-filter=aresample')) 'Android MP3 resampling filter is not recorded.'
        Assert-True ($buildsText.Contains('--enable-muxer=mp4')) 'Android MP4 muxer is not recorded.'
        Assert-True ($buildsText.Contains('--enable-decoder=wrapped_avframe')) 'Android lavfi smoke decoder is not recorded.'
        Assert-True ($buildsText.Contains('x264 and x265 are absent')) 'Android build recipe does not record the x264/x265 exclusion.'
        Assert-True ($noticesText.Contains('Android arm64-v8a FFmpeg 8.1.3')) 'Android FFmpeg notice entry is missing.'
        Assert-True ($toolchainText.Contains('5A-04 Android FFmpeg build')) 'Android FFmpeg build toolchain is undocumented.'

        $buildScript = Join-Path $PSScriptRoot 'build-ffmpeg.sh'
        Assert-True (Test-Path -LiteralPath $buildScript -PathType Leaf) 'The Android FFmpeg build script is missing.'
        if ($HostIsLinux) {
            & bash $buildScript
            $buildExitCode = $LASTEXITCODE
        }
        elseif ($HostIsWindows) {
            $windowsScriptPath = (Resolve-Path -LiteralPath $buildScript).Path.Replace('\', '/')
            $linuxScript = (& wsl.exe -d Ubuntu-24.04 -- wslpath -u $windowsScriptPath | Out-String).Trim()
            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($linuxScript)) {
                throw 'Could not map the repository build script into Ubuntu-24.04 WSL.'
            }
            $linuxCommand = 'export ANDROID_HOME="$HOME/Android/Sdk" ANDROID_SDK_ROOT="$HOME/Android/Sdk" ANDROID_NDK_HOME="$HOME/Android/Sdk/ndk/30.0.16248370" NDK_HOME="$HOME/Android/Sdk/ndk/30.0.16248370" ANDROID_API_LEVEL=24; exec bash "' + $linuxScript + '"'
            & wsl.exe -d Ubuntu-24.04 -- bash -lc $linuxCommand
            $buildExitCode = $LASTEXITCODE
        }
        else {
            throw 'The Android FFmpeg build requires Ubuntu 24.04 or Windows with Ubuntu-24.04 WSL.'
        }
        if ($buildExitCode -ne 0) {
            $buildDir = Join-Path $root 'work/android/gate-5a/5a-04-ffmpeg'
            $lastLog = Get-ChildItem -LiteralPath $buildDir -Filter '*.log' -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($lastLog) { Get-Content -LiteralPath $lastLog.FullName -Tail 50 | Write-Output }
            throw "Android FFmpeg builder failed with exit code $buildExitCode."
        }

        $buildDir = Join-Path $root 'work/android/gate-5a/5a-04-ffmpeg'
        $manifestPath = Join-Path $buildDir 'android-ffmpeg-manifest.json'
        Assert-True (Test-Path -LiteralPath $manifestPath -PathType Leaf) 'The Android FFmpeg manifest was not produced.'
        foreach ($name in @('ffmpeg', 'ffprobe')) {
            $binary = Join-Path $buildDir $name
            Assert-True (Test-Path -LiteralPath $binary -PathType Leaf) "The Android $name executable is missing."
            $actualHash = (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash.ToLowerInvariant()
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            Assert-Equal $manifest.artifacts.$name.sha256 $actualHash "$name artifact SHA-256"
        }
        $relinkPaths = @{
            'libmp3lame.a' = 'relink-materials/lib/libmp3lame.a'
            'libz.a' = 'relink-materials/lib/libz.a'
            'lame.h' = 'relink-materials/include/lame/lame.h'
            'zlib.h' = 'relink-materials/include/zlib.h'
            'zconf.h' = 'relink-materials/include/zconf.h'
        }
        foreach ($name in $relinkPaths.Keys) {
            $relinkFile = Join-Path $buildDir $relinkPaths[$name]
            Assert-True (Test-Path -LiteralPath $relinkFile -PathType Leaf) "Relinking input '$name' is missing."
            $actualHash = (Get-FileHash -LiteralPath $relinkFile -Algorithm SHA256).Hash.ToLowerInvariant()
            Assert-Equal $manifest.relinkMaterials.$name.sha256 $actualHash "$name relinking material SHA-256"
        }
        Assert-Equal $manifest.version '8.1.3' 'Built Android FFmpeg version'
        Assert-Equal $manifest.target 'aarch64-linux-android' 'Built Android FFmpeg target'
        Assert-Equal $manifest.abi 'arm64-v8a' 'Built Android FFmpeg ABI'
        Assert-Equal $manifest.apiLevel 24 'Built Android FFmpeg API level'
        Assert-Equal $manifest.license 'GPL-2.0-or-later' 'Built Android FFmpeg license'
        Assert-True $manifest.configuration.gpl 'Android FFmpeg GPL configuration is not enabled.'
        Assert-True (-not $manifest.configuration.nonfree) 'Android FFmpeg nonfree configuration is enabled.'
        Assert-True (-not $manifest.configuration.x264 -and -not $manifest.configuration.x265) 'Android FFmpeg includes x264 or x265.'
        Invoke-AndroidFfmpegSmoke -RootPath $root -ManifestPath $manifestPath
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        Assert-Equal $manifest.runtimeSmoke.status 'passed' 'Android FFmpeg runtime probe status'
        Write-Output "PASS: Android FFmpeg $($manifest.version) runtime probes passed on $($manifest.runtimeSmoke.deviceModel) ($($manifest.runtimeSmoke.deviceAbi), API $($manifest.runtimeSmoke.apiLevel))."
        Write-Output "FFmpeg SHA-256: $($manifest.artifacts.ffmpeg.sha256)"
        Write-Output "ffprobe SHA-256: $($manifest.artifacts.ffprobe.sha256)"
    }
    exit 0
}
catch {
    [Console]::Error.WriteLine("FAIL: $($_.Exception.Message)")
    exit 1
}
