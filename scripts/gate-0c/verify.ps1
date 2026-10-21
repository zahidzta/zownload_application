# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('library-audit', 'engine-package', 'engine-reintegration')]
    [string]$Case
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

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
