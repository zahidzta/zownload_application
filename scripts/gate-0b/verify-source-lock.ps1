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

$components = @('ytDlp', 'ejs', 'quickjs', 'ffmpeg', 'lame')
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
Assert-Lock ($lock.ffmpeg.source.hashPlan -match 'verify-upstream-pgp-signature') 'FFmpeg needs signature verification'

$requiredQuickJsTargets = @('windows-x64', 'linux-x64', 'macos-x64', 'macos-arm64', 'android-arm64')
foreach ($target in $requiredQuickJsTargets) {
    Assert-Lock ($lock.quickjs.targets -contains $target) "missing QuickJS target $target"
}

$notice = Get-Content -LiteralPath $noticePath -Raw
Assert-Lock ($notice -match 'GPLv3\+') 'notices must describe official yt-dlp binary license'
Assert-Lock ($notice -match 'mpglib.*GPL') 'notices must flag the LAME GPL decoder'
Assert-Lock ($notice -match 'yt-dlp-ejs' -and $notice -match 'LAME MP3') 'notices need ejs and LAME sections'

Write-Output 'Source lock: 5 components, matching yt-dlp/ejs versions, 3 desktop yt-dlp artifacts, 5 QuickJS targets, URLs, digest plans and license notices passed.'
