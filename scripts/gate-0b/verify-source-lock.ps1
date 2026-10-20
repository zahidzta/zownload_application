# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta
# Checks the offline structure of the 0B-01 research lock. Source-page review
# and downloaded-byte verification are separate manual/0B-03 steps.
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$sourcePath = Join-Path $root 'docs\engine-sources.md'
$noticePath = Join-Path $root 'docs\THIRD-PARTY-NOTICES.md'

function Assert-Lock([bool]$condition, [string]$message) {
    if (-not $condition) { throw "Source lock invalid: $message" }
}

function Assert-Url([string]$url, [string]$version, [string]$label) {
    Assert-Lock ($url -match '^https://') "$label must use HTTPS"
    Assert-Lock ($url.Contains($version)) "$label must contain the pinned version $version"
    Assert-Lock ($url -notmatch '(?i)/latest/|/master/|/main/|/nightly/') "$label must not use a moving URL"
}

function Assert-Digest([string]$digest, [string]$label) {
    Assert-Lock ($digest -match '^[a-f0-9]{64}$') "$label needs a 64-character lowercase SHA-256"
}

$markdown = Get-Content -LiteralPath $sourcePath -Raw
$matches = [regex]::Matches($markdown, '(?s)```json source-lock\r?\n(.*?)\r?\n```')
Assert-Lock ($matches.Count -eq 1) 'expected exactly one json source-lock block'
$lock = $matches[0].Groups[1].Value | ConvertFrom-Json
Assert-Lock ($lock.schema -eq 1) 'unexpected schema version'

$components = @('ytDlp', 'ejs', 'quickjs', 'ffmpeg', 'lame', 'zlib')
foreach ($name in $components) {
    $item = $lock.$name
    Assert-Lock ($null -ne $item) "missing $name"
    Assert-Lock (-not [string]::IsNullOrWhiteSpace($item.version)) "missing $name version"
    Assert-Lock (-not [string]::IsNullOrWhiteSpace($item.license)) "missing $name license"
    Assert-Url $item.source.url $item.version "$name source URL"
    if ($item.source.sha256) {
        Assert-Digest $item.source.sha256 "$name source"
    } else {
        Assert-Lock ($item.source.hashPlan -match '0B-03') "$name needs an explicit 0B-03 hash plan"
    }
}

Assert-Lock ($lock.ytDlp.ejsVersion -eq $lock.ejs.version) 'yt-dlp and ejs versions disagree'
Assert-Lock ($lock.ytDlp.commit -match '^[a-f0-9]{40}$') 'yt-dlp commit is not full length'
Assert-Lock ($lock.ejs.commit -match '^[a-f0-9]{40}$') 'ejs commit is not full length'
Assert-Url $lock.ytDlp.checksumManifest.url $lock.ytDlp.version 'yt-dlp checksum manifest'
Assert-Url $lock.ytDlp.checksumManifest.signatureUrl $lock.ytDlp.version 'yt-dlp checksum signature'
Assert-Digest $lock.ytDlp.checksumManifest.sha256 'yt-dlp checksum manifest'
Assert-Digest $lock.ytDlp.checksumManifest.signatureSha256 'yt-dlp checksum signature'
Assert-Lock ($lock.ytDlp.signingKey.url -eq "https://raw.githubusercontent.com/yt-dlp/yt-dlp/$($lock.ytDlp.commit)/public.key") 'yt-dlp key must come from the pinned commit'
Assert-Digest $lock.ytDlp.signingKey.sha256 'yt-dlp signing key'
Assert-Lock ($lock.ytDlp.signingKey.fingerprint -match '^[A-F0-9]{40}$') 'yt-dlp signer fingerprint is missing'

foreach ($target in @('windowsX64', 'linuxX64', 'macosUniversal')) {
    $artifact = $lock.ytDlp.binaries.$target
    Assert-Lock ($null -ne $artifact) "missing yt-dlp $target artifact"
    Assert-Url $artifact.url $lock.ytDlp.version "yt-dlp $target URL"
    if ($artifact.sha256) {
        Assert-Digest $artifact.sha256 "yt-dlp $target"
    } else {
        Assert-Lock ($artifact.hashPlan -match 'pinned-checksum-manifest-in-0B-03') "yt-dlp $target needs the pinned manifest hash plan"
    }
}

Assert-Url $lock.ejs.wheel.url $lock.ejs.version 'ejs wheel URL'
Assert-Digest $lock.ejs.wheel.sha256 'ejs wheel'
Assert-Url $lock.ffmpeg.source.signatureUrl $lock.ffmpeg.version 'FFmpeg signature URL'
Assert-Digest $lock.ffmpeg.source.sha256 'FFmpeg source'
Assert-Digest $lock.ffmpeg.source.signatureSha256 'FFmpeg signature'
Assert-Lock ($lock.ffmpeg.signingKey.url -eq 'https://ffmpeg.org/ffmpeg-devel.asc') 'FFmpeg key URL must be official'
Assert-Digest $lock.ffmpeg.signingKey.sha256 'FFmpeg signing key'
Assert-Lock ($lock.ffmpeg.signingKey.fingerprint -eq 'FCF986EA15E6E293A5644F10B4322F04D67658D8') 'FFmpeg signer fingerprint disagrees with upstream'
Assert-Lock ($lock.zlib.source.url -eq "https://zlib.net/fossils/zlib-$($lock.zlib.version).tar.gz") 'zlib must use the official versioned fossil archive'
Assert-Lock ($lock.zlib.license -match '^Zlib') 'zlib license must be recorded'
Assert-Lock ($lock.zlib.targets -contains 'windows-x64') 'zlib Windows target is missing'

$requiredQuickJsTargets = @('windows-x64', 'linux-x64', 'macos-x64', 'macos-arm64', 'android-arm64')
foreach ($target in $requiredQuickJsTargets) {
    Assert-Lock ($lock.quickjs.targets -contains $target) "missing QuickJS target $target"
}

$notice = Get-Content -LiteralPath $noticePath -Raw
Assert-Lock ($notice -match 'GPLv3\+') 'notices must describe official yt-dlp binary license'
Assert-Lock ($notice -match 'mpglib.*GPL') 'notices must flag the LAME GPL decoder'
Assert-Lock ($notice -match 'yt-dlp-ejs' -and $notice -match 'LAME MP3') 'notices need ejs and LAME sections'
Assert-Lock ($notice -match 'zlib compression library') 'notices need the zlib section'

Write-Output 'Source lock: 6 components, matching yt-dlp/ejs versions, 3 desktop yt-dlp artifacts, 5 QuickJS targets, URLs, SHA-256 values, signing keys and license notices passed.'
