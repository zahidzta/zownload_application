# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta

param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$work = Join-Path $root 'work/android/gate-5a/5a-06-package'
$package = Join-Path $work 'package'
$runtimeDir = Join-Path $root 'work/android/gate-5a/5a-03-cpython'
$ffmpegDir = Join-Path $root 'work/android/gate-5a/5a-04-ffmpeg'
$quickJsPath = Join-Path $root 'work/engine/build/quickjs/android-arm64/qjs'
$runtimeManifestPath = Join-Path $runtimeDir 'runtime-manifest.json'
$ffmpegManifestPath = Join-Path $ffmpegDir 'android-ffmpeg-manifest.json'
$sourcesPath = Join-Path $root 'docs/engine-sources.md'
$buildsPath = Join-Path $root 'docs/engine-builds.md'
$toolchainPath = Join-Path $root 'docs/toolchain.md'
$noticesPath = Join-Path $root 'docs/THIRD-PARTY-NOTICES.md'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Read-JsonFence {
    param([string]$Text, [string]$FenceName)
    $pattern = '(?ms)^```json ' + [regex]::Escape($FenceName) + '\s*(.*?)\r?\n```'
    $match = [regex]::Match($Text, $pattern)
    Assert-True $match.Success "Missing JSON block '$FenceName'."
    return (ConvertFrom-Json -InputObject $match.Groups[1].Value)
}

function Copy-Tree {
    param([string]$Source, [string]$Destination)
    Assert-True (Test-Path -LiteralPath $Source -PathType Container) "Missing package source tree: $Source"
    $sourceRoot = (Resolve-Path -LiteralPath $Source).Path.TrimEnd('\', '/')
    foreach ($file in Get-ChildItem -LiteralPath $sourceRoot -Recurse -File) {
        $relative = $file.FullName.Substring($sourceRoot.Length).TrimStart('\', '/')
        $target = Join-Path $Destination $relative
        $targetDirectory = Split-Path -Parent $target
        New-Item -ItemType Directory -Force -Path $targetDirectory | Out-Null
        if (-not (Test-Path -LiteralPath $target -PathType Leaf) -or (Get-Item -LiteralPath $target).Length -ne $file.Length) {
            Copy-Item -LiteralPath $file.FullName -Destination $target -Force
        }
    }
}

function Add-SourceMaterial {
    param(
        [System.Collections.Generic.List[object]]$Materials,
        [string]$Name,
        [string]$Version,
        [string]$License,
        [string]$Url,
        [string]$Sha256,
        [object[]]$FileIndex
    )

    Assert-True ($Sha256 -match '^[0-9a-f]{64}$') "$Name source hash is malformed."
    $sourceFile = $FileIndex | Where-Object { $_.sha256 -ceq $Sha256 } | Select-Object -First 1
    Assert-True ($null -ne $sourceFile) "$Name source archive with SHA-256 $Sha256 is missing from the local source bundle."

    $relativePath = $sourceFile.path.Substring($root.Length).TrimStart('\', '/')
    $Materials.Add([ordered]@{
        name = $Name
        version = $Version
        license = $License
        sourceUrl = $Url
        sha256 = $Sha256
        localPath = $relativePath.Replace('\', '/')
    }) | Out-Null
}

function Add-PackageFile {
    param([string]$Source, [string]$PackagePath, [string]$ApkPath, [string]$Component, [System.Collections.Generic.List[object]]$Files)
    Assert-True (Test-Path -LiteralPath $Source -PathType Leaf) "Missing staged payload input: $Source"
    $target = Join-Path $package ($PackagePath -replace '/', '\')
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    Copy-Item -LiteralPath $Source -Destination $target -Force
    $relativeSource = (Resolve-Path -LiteralPath $Source).Path.Substring($root.Length).TrimStart('\', '/')
    $Files.Add([ordered]@{
        apkPath = $ApkPath
        component = $Component
        sourcePath = $relativeSource.Replace('\', '/')
        bytes = (Get-Item -LiteralPath $target).Length
        sha256 = Get-Sha256 $target
    }) | Out-Null
}

foreach ($path in @($runtimeManifestPath, $ffmpegManifestPath, $quickJsPath, $sourcesPath, $buildsPath, $toolchainPath, $noticesPath)) {
    Assert-True (Test-Path -LiteralPath $path -PathType Leaf) "Required 5A build or provenance input is missing: $path"
}

$runtimeManifest = Get-Content -LiteralPath $runtimeManifestPath -Raw | ConvertFrom-Json
$ffmpegManifest = Get-Content -LiteralPath $ffmpegManifestPath -Raw | ConvertFrom-Json
$sourcesText = Get-Content -LiteralPath $sourcesPath -Raw
$buildsText = Get-Content -LiteralPath $buildsPath -Raw
$noticesText = Get-Content -LiteralPath $noticesPath -Raw
$sourceLock = Read-JsonFence $sourcesText 'source-lock'
$runtimeLock = Read-JsonFence $sourcesText 'android-python-runtime-lock'

Assert-True ($runtimeManifest.pythonVersion -ceq '3.14.10' -and $runtimeManifest.abi -ceq 'arm64-v8a') 'The CPython runtime manifest is not the approved Android build.'
Assert-True ($runtimeManifest.nativeLibraries.Count -gt 0) 'The CPython runtime manifest has no native libraries.'
Assert-True ($runtimeManifest.packages.Count -eq ($runtimeLock.pythonPackages.Count + 2)) 'The CPython package manifest differs from the locked runtime packages.'
Assert-True ($ffmpegManifest.version -ceq '8.1.3' -and $ffmpegManifest.abi -ceq 'arm64-v8a') 'The FFmpeg manifest is not the approved Android build.'
Assert-True ($ffmpegManifest.license -ceq 'GPL-2.0-or-later' -and $ffmpegManifest.configuration.gpl) 'The Android FFmpeg GPL posture is missing.'
Assert-True (-not $ffmpegManifest.configuration.nonfree -and -not $ffmpegManifest.configuration.x264 -and -not $ffmpegManifest.configuration.x265) 'The Android FFmpeg build enables an unapproved component.'
Assert-True ($buildsText.Contains('5A-03 — CPython and yt-dlp Android runtime') -and $buildsText.Contains('5A-04 — Android arm64-v8a GPL FFmpeg 8.1.3') -and $buildsText.Contains('5A-05 Android arm64-v8a QuickJS 2026-06-04')) 'Build recipes for all three Android runtime inputs must be documented.'

$quickJsHash = Get-Sha256 $quickJsPath
$quickJsEvidence = Get-Content -LiteralPath (Join-Path $root 'docs/gates/evidence/5a/5a-05-quickjs.md') -Raw
$quickJsOutputMatch = [regex]::Match($quickJsEvidence, '(?is)work/engine/build/quickjs/android-arm64/qjs.{0,100}?SHA-256\s*`([0-9a-f]{64})`')
Assert-True $quickJsOutputMatch.Success 'The 5A-05 evidence does not record the QuickJS output hash.'
Assert-True ($quickJsHash -ceq $quickJsOutputMatch.Groups[1].Value) 'The built QuickJS hash differs from the 5A-05 evidence.'

$sourceRoots = @(
    (Join-Path $runtimeDir 'source-inputs'),
    (Join-Path $ffmpegDir 'downloads'),
    (Join-Path $root 'work/engine/downloads')
)
$sourceFileIndex = [System.Collections.Generic.List[object]]::new()
foreach ($searchRoot in $sourceRoots) {
    Assert-True (Test-Path -LiteralPath $searchRoot -PathType Container) "A locked source directory is missing: $searchRoot"
    foreach ($file in Get-ChildItem -LiteralPath $searchRoot -Recurse -File) {
        $sourceFileIndex.Add([pscustomobject]@{ path = $file.FullName; sha256 = Get-Sha256 $file.FullName }) | Out-Null
    }
}
$sourceMaterials = [System.Collections.Generic.List[object]]::new()
$components = [System.Collections.Generic.List[object]]::new()

Add-SourceMaterial $sourceMaterials 'CPython' $runtimeLock.python.version $runtimeLock.python.license $runtimeLock.python.sourceUrl $runtimeLock.python.sha256 $sourceFileIndex
$components.Add([ordered]@{ name = 'CPython'; version = $runtimeLock.python.version; license = $runtimeLock.python.license; sourceUrl = $runtimeLock.python.sourceUrl; sourceSha256 = $runtimeLock.python.sha256 }) | Out-Null

foreach ($dependency in $runtimeLock.nativeDependencies) {
    Add-SourceMaterial $sourceMaterials $dependency.name $dependency.version $dependency.license $dependency.sourceUrl $dependency.sha256 $sourceFileIndex
    $components.Add([ordered]@{ name = $dependency.name; version = $dependency.version; license = $dependency.license; sourceUrl = $dependency.sourceUrl; sourceSha256 = $dependency.sha256 }) | Out-Null
}
foreach ($dependency in $runtimeLock.pythonPackages) {
    Add-SourceMaterial $sourceMaterials $dependency.name $dependency.version $dependency.license $dependency.sourceUrl $dependency.sha256 $sourceFileIndex
    $components.Add([ordered]@{ name = $dependency.name; version = $dependency.version; license = $dependency.license; sourceUrl = $dependency.sourceUrl; sourceSha256 = $dependency.sha256 }) | Out-Null
}

foreach ($key in @('ytDlp', 'ejs', 'quickjs')) {
    $component = $sourceLock.$key
    Add-SourceMaterial $sourceMaterials $key $component.version $component.license $component.source.url $component.source.sha256 $sourceFileIndex
    $displayName = switch ($key) { 'ytDlp' { 'yt-dlp' } 'ejs' { 'yt-dlp-ejs' } 'quickjs' { 'QuickJS' } }
    $components.Add([ordered]@{ name = $displayName; version = $component.version; license = $component.license; sourceUrl = $component.source.url; sourceSha256 = $component.source.sha256 }) | Out-Null
}
foreach ($key in @('ffmpeg', 'lame', 'zlib')) {
    $component = $sourceLock.$key
    Add-SourceMaterial $sourceMaterials $key $component.version $component.license $component.source.url $component.source.sha256 $sourceFileIndex
    $displayName = switch ($key) { 'ffmpeg' { 'FFmpeg' } 'lame' { 'LAME' } 'zlib' { 'zlib' } }
    $components.Add([ordered]@{ name = $displayName; version = $component.version; license = $component.license; sourceUrl = $component.source.url; sourceSha256 = $component.source.sha256 }) | Out-Null
}
Add-SourceMaterial $sourceMaterials 'FFmpeg signing key' $sourceLock.ffmpeg.version 'FFmpeg source signature verification key' $sourceLock.ffmpeg.signingKey.url $sourceLock.ffmpeg.signingKey.sha256 $sourceFileIndex
Add-SourceMaterial $sourceMaterials 'FFmpeg detached signature' $sourceLock.ffmpeg.version 'FFmpeg source signature' $sourceLock.ffmpeg.source.signatureUrl $sourceLock.ffmpeg.source.signatureSha256 $sourceFileIndex

foreach ($component in $components) {
    Assert-True ($noticesText.IndexOf([string]$component.name, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) "THIRD-PARTY-NOTICES.md does not inventory '$($component.name)'."
}
Assert-True ($noticesText.Contains('Meriyah ISC') -and $noticesText.Contains('Astring MIT')) 'The yt-dlp/EJS embedded solver notices are missing.'

$runtimePackage = Join-Path $runtimeDir 'android-package'
$runtimeJni = Join-Path $runtimePackage 'jniLibs/arm64-v8a'
$runtimeAssets = Join-Path $runtimePackage 'assets/python-runtime'
$stageJni = Join-Path $package 'jniLibs/arm64-v8a'
$stageAssets = Join-Path $package 'runtime-tree'
$apkAssets = Join-Path $package 'apk-assets'
$runtimeArchive = Join-Path $apkAssets 'python-runtime.zip'

# Recreate only the generated JNI staging folder. Verify its resolved path is
# inside this task's ignored work directory before removing stale staged files.
if (Test-Path -LiteralPath $stageJni -PathType Container) {
    $resolvedWork = (Resolve-Path -LiteralPath $work).Path.TrimEnd('\', '/')
    $resolvedStageJni = (Resolve-Path -LiteralPath $stageJni).Path
    Assert-True ($resolvedStageJni.StartsWith($resolvedWork + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) 'Refusing to replace a JNI staging folder outside this task work directory.'
    Remove-Item -LiteralPath $resolvedStageJni -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $stageJni | Out-Null
Copy-Tree $runtimeAssets $stageAssets

foreach ($native in $runtimeManifest.nativeLibraries) {
    $sourceRelative = $native.path -replace '/', '\'
    $builtPath = Join-Path $runtimeJni $sourceRelative
    Assert-True (Test-Path -LiteralPath $builtPath -PathType Leaf) "Runtime manifest native output is missing: $($native.path)"
    Assert-True ((Get-Sha256 $builtPath) -ceq $native.sha256) "Runtime manifest native hash mismatch: $($native.path)"
    if ($native.path.Contains('/')) {
        $destination = Join-Path $stageAssets ("lib/" + ($native.path -replace '/', '\'))
    }
    else {
        $destination = Join-Path $stageJni $sourceRelative
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $builtPath -Destination $destination -Force
    Assert-True ((Get-Sha256 $destination) -ceq $native.sha256) "Staged native output hash mismatch: $($native.path)"
}

# Package the Python tree as one asset. AGP's asset merge omits some
# underscore-prefixed Python package directories, including yt-dlp solvers.
# The 5A-07 provider extracts this archive into app-private storage.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
New-Item -ItemType Directory -Force -Path $apkAssets | Out-Null
if (Test-Path -LiteralPath $runtimeArchive -PathType Leaf) {
    Remove-Item -LiteralPath $runtimeArchive -Force
}
$archiveFile = [System.IO.File]::Open($runtimeArchive, [System.IO.FileMode]::Create, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
$runtimeZip = [System.IO.Compression.ZipArchive]::new($archiveFile, [System.IO.Compression.ZipArchiveMode]::Create, $false)
try {
    $resolvedStageAssets = (Resolve-Path -LiteralPath $stageAssets).Path.TrimEnd('\', '/')
    foreach ($file in Get-ChildItem -LiteralPath $resolvedStageAssets -Recurse -File) {
        $relative = $file.FullName.Substring($resolvedStageAssets.Length).TrimStart('\', '/')
        $entry = $runtimeZip.CreateEntry($relative.Replace('\', '/'), [System.IO.Compression.CompressionLevel]::Optimal)
        $inputStream = [System.IO.File]::OpenRead($file.FullName)
        $outputStream = $entry.Open()
        try { $inputStream.CopyTo($outputStream) }
        finally {
            $outputStream.Dispose()
            $inputStream.Dispose()
        }
    }
}
finally {
    $runtimeZip.Dispose()
}
$runtimeArchiveHash = Get-Sha256 $runtimeArchive
$runtimeArchiveBytes = (Get-Item -LiteralPath $runtimeArchive).Length
$runtimeArchiveEntryCount = (Get-ChildItem -LiteralPath $stageAssets -Recurse -File | Measure-Object).Count

$stagedFiles = [System.Collections.Generic.List[object]]::new()
$runtimeHashes = @{}
foreach ($hash in (Get-ChildItem -LiteralPath @($stageJni, $stageAssets) -Recurse -File | Get-FileHash -Algorithm SHA256)) {
    $runtimeHashes[$hash.Path] = $hash.Hash.ToLowerInvariant()
}
foreach ($native in $runtimeManifest.nativeLibraries) {
    $sourceRelative = $native.path -replace '/', '\'
    $builtPath = Join-Path $runtimeJni $sourceRelative
    if ($native.path.Contains('/')) {
        $destination = Join-Path $stageAssets ("lib/" + $sourceRelative)
        $apkPath = 'assets/python-runtime.zip'
        $archivePath = 'lib/' + $native.path
        $componentName = 'CPython native extension modules'
    }
    else {
        $destination = Join-Path $stageJni $sourceRelative
        $apkPath = 'lib/arm64-v8a/' + $native.path
        $archivePath = $null
        $componentName = 'CPython native runtime'
    }
    $sourceRelativePath = $builtPath.Substring($root.Length).TrimStart('\', '/')
    $record = [ordered]@{
        apkPath = $apkPath
        component = $componentName
        sourcePath = $sourceRelativePath.Replace('\', '/')
        bytes = (Get-Item -LiteralPath $destination).Length
        sha256 = $runtimeHashes[$destination]
    }
    if ($archivePath) { $record.archivePath = $archivePath }
    $stagedFiles.Add($record) | Out-Null
}
$resolvedAssets = (Resolve-Path -LiteralPath $runtimeAssets).Path.TrimEnd('\', '/')
foreach ($file in Get-ChildItem -LiteralPath $resolvedAssets -Recurse -File) {
    $relative = $file.FullName.Substring($resolvedAssets.Length).TrimStart('\', '/')
    $destination = Join-Path $stageAssets $relative
    $sourceRelativePath = $file.FullName.Substring($root.Length).TrimStart('\', '/')
    $stagedFiles.Add([ordered]@{
        apkPath = 'assets/python-runtime.zip'
        archivePath = $relative.Replace('\', '/')
        component = 'CPython and pinned Python packages'
        sourcePath = $sourceRelativePath.Replace('\', '/')
        bytes = $file.Length
        sha256 = $runtimeHashes[$destination]
    }) | Out-Null
}

Add-PackageFile $quickJsPath 'jniLibs/arm64-v8a/libqjs.so' 'lib/arm64-v8a/libqjs.so' 'QuickJS' $stagedFiles
Add-PackageFile (Join-Path $ffmpegDir 'ffmpeg') 'jniLibs/arm64-v8a/libffmpeg.so' 'lib/arm64-v8a/libffmpeg.so' 'FFmpeg 8.1.3' $stagedFiles
Add-PackageFile (Join-Path $ffmpegDir 'ffprobe') 'jniLibs/arm64-v8a/libffprobe.so' 'lib/arm64-v8a/libffprobe.so' 'FFmpeg 8.1.3' $stagedFiles

$seenApkPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($file in $stagedFiles) {
    $key = if ($file['archivePath']) { "$($file['apkPath'])!$($file['archivePath'])" } else { [string]$file['apkPath'] }
    Assert-True ($seenApkPaths.Add($key)) "Duplicate APK engine path '$key'."
}
$stagedBytes = [long]0
foreach ($file in $stagedFiles) { $stagedBytes += [long]$file['bytes'] }
$manifest = [ordered]@{
    schema = 1
    spdx = 'GPL-3.0-or-later'
    package = [ordered]@{ name = 'Zownload Android engine'; version = 'Gate 5A-06'; target = 'aarch64-linux-android'; abi = 'arm64-v8a'; apiLevel = 24 }
    appBuild = [ordered]@{ minSdk = 24; targetSdk = 36; allowedGeneratedNativePaths = @('lib/arm64-v8a/libzownload_lib.so') }
    assetArchive = [ordered]@{
        apkPath = 'assets/python-runtime.zip'
        packagePath = 'work/android/gate-5a/5a-06-package/package/apk-assets/python-runtime.zip'
        bytes = $runtimeArchiveBytes
        sha256 = $runtimeArchiveHash
        entryCount = $runtimeArchiveEntryCount
        extractionDirectory = 'python-runtime'
    }
    buildManifests = @(
        [ordered]@{ path = 'work/android/gate-5a/5a-03-cpython/runtime-manifest.json'; sha256 = Get-Sha256 $runtimeManifestPath },
        [ordered]@{ path = 'work/android/gate-5a/5a-04-ffmpeg/android-ffmpeg-manifest.json'; sha256 = Get-Sha256 $ffmpegManifestPath },
        [ordered]@{ path = 'docs/gates/evidence/5a/5a-05-quickjs.md'; sha256 = Get-Sha256 (Join-Path $root 'docs/gates/evidence/5a/5a-05-quickjs.md'); artifactSha256 = $quickJsHash }
    )
    auditRecords = @(
        [ordered]@{ path = 'docs/engine-sources.md'; sha256 = Get-Sha256 $sourcesPath },
        [ordered]@{ path = 'docs/engine-builds.md'; sha256 = Get-Sha256 $buildsPath },
        [ordered]@{ path = 'docs/toolchain.md'; sha256 = Get-Sha256 $toolchainPath },
        [ordered]@{ path = 'docs/THIRD-PARTY-NOTICES.md'; sha256 = Get-Sha256 $noticesPath }
    )
    sourceMaterials = @($sourceMaterials)
    components = @($components)
    stagedFiles = @($stagedFiles)
    stagedFileCount = $stagedFiles.Count
    stagedBytes = $stagedBytes
    packageStatus = 'staged; APK hash verification pending'
}

$manifestPath = Join-Path $work 'android-engine-manifest.json'
New-Item -ItemType Directory -Force -Path $work | Out-Null
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding utf8
Write-Output "PASS: staged $($stagedFiles.Count) traceable engine files for $($manifest.package.abi)."
Write-Output "Source archives and build inputs checked: $($sourceMaterials.Count); transitive engine components checked: $($components.Count)."
