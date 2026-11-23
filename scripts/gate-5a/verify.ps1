# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('python-source-lock', 'python-runtime')]
    [string]$Case
)

$ErrorActionPreference = 'Stop'

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

try {
    $root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $sourcesPath = Join-Path $root 'docs\engine-sources.md'
    $buildsPath = Join-Path $root 'docs\engine-builds.md'
    $toolchainPath = Join-Path $root 'docs\toolchain.md'
    $decisionPath = Join-Path $root 'docs\gates\evidence\5a\python-runtime-decision.md'

    foreach ($path in @($sourcesPath, $buildsPath, $toolchainPath, $decisionPath)) {
        Assert-True (Test-Path -LiteralPath $path -PathType Leaf) "Required task file is missing: $path"
    }

    $sourcesText = Get-Content -LiteralPath $sourcesPath -Raw
    $buildsText = Get-Content -LiteralPath $buildsPath -Raw
    $toolchainText = Get-Content -LiteralPath $toolchainPath -Raw
    $decisionText = Get-Content -LiteralPath $decisionPath -Raw
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

    $setuptools = @($lock.pythonBuildTools | Where-Object { $_.name -ceq 'setuptools' })
    Assert-Equal $setuptools.Count 1 'Pinned setuptools build tool count'
    Assert-Equal $setuptools[0].version '84.1.0' 'Setuptools version'
    Assert-Equal $setuptools[0].sha256 '23657205b63d4d31395ab917815247f694aafad28cd21316bf5fd45a51048ea0' 'Setuptools source SHA-256'
    Assert-Equal $setuptools[0].wheelSha256 '5231689c6ac8156cd155cfb98c3fd6fb252c3e7e9bd3d78b64d3c55f132624c9' 'Setuptools build wheel SHA-256'

    Assert-True ($decisionText.Contains('Owner decision: CPython approved on 2026-11-22')) 'Decision memo does not record owner approval.'
    Assert-True ($decisionText.Contains('AndroidEnginePackage')) 'Decision memo omits the package boundary.'
    Assert-True ($decisionText.Contains('22–35 MB')) 'Decision memo omits the unmeasured package-size estimate.'
    Assert-True ($decisionText -match 'desktop-only\s+first-release\s+fallback') 'Decision memo omits the fallback.'
    Assert-True ($buildsText.Contains('./android.py build aarch64-linux-android')) 'CPython build command is missing.'
    Assert-True ($buildsText.Contains('./android.py package aarch64-linux-android')) 'CPython package command is missing.'
    Assert-True ($buildsText.Contains('cross-build/downloads/')) 'Source-built native dependency cache is undocumented.'
    Assert-True ($buildsText.Contains('prebuilt GitHub release archives are not allowed')) 'Build recipe permits opaque native archives.'
    Assert-True ($buildsText.Contains('without allowing `pip` to resolve')) 'Build recipe does not block unpinned pip resolution.'
    Assert-True ($toolchainText.Contains('cmdline-tools/latest')) 'Pinned SDK alias requirement is missing.'
    Assert-True ($toolchainText.Contains('ANDROID_API_LEVEL=24')) 'Runtime API level setup is missing.'
    Assert-True ($toolchainText.Contains('30.0.16248370')) 'Pinned NDK setup is missing.'

    if ($Case -eq 'python-runtime') {
        Assert-True $IsLinux 'The CPython runtime build must run on the pinned Ubuntu Linux host.'
        $buildScript = Join-Path $PSScriptRoot 'build-python-runtime.sh'
        Assert-True (Test-Path -LiteralPath $buildScript -PathType Leaf) 'The CPython runtime build script is missing.'
        & bash $buildScript
        $buildExitCode = $LASTEXITCODE
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
    else {
        Write-Output 'PASS: CPython Android source lock, owner decision, and build-tool pins are consistent.'
    }
    exit 0
}
catch {
    [Console]::Error.WriteLine("FAIL: $($_.Exception.Message)")
    exit 1
}
