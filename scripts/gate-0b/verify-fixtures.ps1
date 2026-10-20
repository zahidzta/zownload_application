# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta
# Read-only availability and format check for the Gate 0B real-media fixtures.
# HTTP catalog pages and simulated yt-dlp extraction are allowed; no media is downloaded.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$fixturePath = Join-Path $root 'docs\gates\evidence\0b\fixtures.md'
$markdown = Get-Content -LiteralPath $fixturePath -Raw -Encoding UTF8
$blocks = [regex]::Matches($markdown, '(?s)```json fixture-lock\r?\n(.*?)\r?\n```')
if ($blocks.Count -ne 1) { throw 'Fixture lock invalid: expected one json fixture-lock block' }
$lock = $blocks[0].Groups[1].Value | ConvertFrom-Json
$ytDlp = Join-Path $root 'work\engine\downloads\yt-dlp.exe'
$quickJs = Join-Path $root 'work\engine\build\quickjs\windows-x64\qjs.exe'

function Assert-Fixture([bool]$condition, [string]$message) {
    if (-not $condition) { throw "Fixture unavailable or lock invalid: $message" }
}

function Read-Json([string]$url) {
    try { return Invoke-RestMethod -Uri $url -TimeoutSec 20 }
    catch { throw "Fixture preflight could not read $url`: $($_.Exception.Message)" }
}

function Read-Page([string]$url) {
    try { return (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 20).Content }
    catch { throw "Fixture preflight could not read $url`: $($_.Exception.Message)" }
}

function Assert-ArchiveUrl($fixture) {
    Assert-Fixture ($fixture.url -eq "https://archive.org/details/$($fixture.id)") "unexpected Archive URL for $($fixture.id)"
}

function Read-Archive($fixture) {
    Assert-ArchiveUrl $fixture
    $metadata = Read-Json "https://archive.org/metadata/$($fixture.id)"
    Assert-Fixture ($metadata.metadata.identifier -eq $fixture.id) "Archive item $($fixture.id) disappeared"
    return $metadata
}

function Assert-License($metadata, [string]$expected, [string]$id) {
    $actual = [string]$metadata.metadata.licenseurl -replace '^https?://', ''
    Assert-Fixture ($actual -eq $expected) "$id license changed: $actual"
}

function Read-ArchivePlaylist([string]$id) {
    $page = Read-Page "https://archive.org/embed/$id"
    $attribute = [regex]::Match($page, "playlist='([^']+)'")
    Assert-Fixture $attribute.Success "$id has no public embed playlist"
    $json = [System.Net.WebUtility]::HtmlDecode($attribute.Groups[1].Value)
    foreach ($entry in ($json | ConvertFrom-Json)) { Write-Output $entry }
}

function Assert-PublicFile($metadata, [string]$name, [string]$id) {
    $files = @($metadata.files | Where-Object { $_.name -eq $name })
    Assert-Fixture ($files.Count -eq 1) "$id is missing file $name"
    Assert-Fixture (-not $files[0].private) "$id file $name became private"
    Assert-Fixture ([long]$files[0].size -gt 0) "$id file $name has no size"
}

function Invoke-YtDlpMetadata([string[]]$arguments, [string]$label) {
    # --skip-download (or --dump-single-json, which simulates) extracts page
    # metadata only. All arguments below are locked URLs and controlled options.
    $output = & $ytDlp @arguments 2>$null
    Assert-Fixture ($LASTEXITCODE -eq 0) "yt-dlp metadata extraction failed for $label"
    return $output
}

function Estimate-FormatBytes($format, [double]$duration, [string]$label) {
    if ([double]$format.filesize -gt 0) { return [long][math]::Ceiling([double]$format.filesize) }
    if ([double]$format.filesize_approx -gt 0) { return [long][math]::Ceiling([double]$format.filesize_approx) }
    Assert-Fixture ([double]$format.tbr -gt 0 -and $duration -gt 0) "$label has no size or bitrate estimate"
    # tbr is kilobits/s. Allow 50% for rate variation and HLS segment overhead.
    return [long][math]::Ceiling([double]$format.tbr * $duration * 1000 / 8 * 1.5)
}

Assert-Fixture ($lock.schema -eq 1) 'unexpected schema version'
Assert-Fixture ($lock.checkedOn -match '^\d{4}-\d{2}-\d{2}$') 'missing access date'
Assert-Fixture ($lock.youtubeShort.url -eq "https://www.youtube.com/watch?v=$($lock.youtubeShort.id)") 'YouTube single URL changed'
Assert-Fixture ($lock.blenderPlaylist.url -eq "https://www.youtube.com/playlist?list=$($lock.blenderPlaylist.id)") 'YouTube playlist URL changed'
Assert-Fixture ($lock.blenderPlaylist.mixedUrl -eq "https://www.youtube.com/watch?v=$($lock.blenderPlaylist.videoIds[0])&list=$($lock.blenderPlaylist.id)") 'mixed URL changed'
Assert-Fixture ($lock.blenderPlaylist.videoIds.Count -eq 2) 'expected two locked Blender entries'
Assert-Fixture ($lock.blenderPlaylist.minDistinctVideoHeights -eq 2) 'Blender resolution minimum changed'
Assert-Fixture ($lock.invalidInput -eq 'not-a-url') 'invalid-input fixture changed'
Assert-Fixture (Test-Path -LiteralPath $ytDlp -PathType Leaf) 'pinned yt-dlp is missing'
Assert-Fixture (Test-Path -LiteralPath $quickJs -PathType Leaf) 'pinned QuickJS is missing'
Assert-Fixture ((Get-FileHash -LiteralPath $ytDlp -Algorithm SHA256).Hash.ToLowerInvariant() -eq '66674953fe251b89f4d08c5f0e35e0728679bd67ab3d7d05c0562af101dd3e7a') 'yt-dlp hash changed'
Assert-Fixture ((Get-FileHash -LiteralPath $quickJs -Algorithm SHA256).Hash.ToLowerInvariant() -eq 'bec67f8f87fa22958d3ab8be5508088116b8bff90032323d82c94545e1698b83') 'QuickJS hash changed'

$videoUrl = [uri]::EscapeDataString($lock.youtubeShort.url)
$oembed = Read-Json "https://www.youtube.com/oembed?url=$videoUrl&format=json"
Assert-Fixture ($oembed.title -eq $lock.youtubeShort.title -and $oembed.author_name -eq $lock.youtubeShort.author) 'YouTube short title/author changed or video disappeared'
Write-Output "OK YouTube single: $($lock.youtubeShort.id)"

$commonsLock = $lock.commonsVorbisSingle
Assert-Fixture ($commonsLock.title -eq [uri]::UnescapeDataString('File:10%E8%99%9F%E9%A2%A8....webm')) 'Commons Vorbis file title changed'
Assert-Fixture ($commonsLock.pageUrl -eq 'https://commons.wikimedia.org/wiki/File:10%E8%99%9F%E9%A2%A8....webm') 'Commons file page URL changed'
Assert-Fixture ($commonsLock.mediaUrl -eq 'https://upload.wikimedia.org/wikipedia/commons/a/aa/10%E8%99%9F%E9%A2%A8....webm') 'Commons original media URL changed'
Assert-Fixture ($commonsLock.audioCodec -eq 'vorbis') 'Commons source audio codec lock changed'
$commonsTitle = [uri]::EscapeDataString($commonsLock.title)
$commonsApiUrl = "https://commons.wikimedia.org/w/api.php?action=query&format=json&prop=imageinfo&iiprop=url%7Csize%7Cmime%7Csha1%7Cextmetadata&titles=$commonsTitle"
$commonsApi = Read-Json $commonsApiUrl
$commonsPages = @($commonsApi.query.pages.PSObject.Properties)
Assert-Fixture ($commonsPages.Count -eq 1) 'Commons API did not return one file page'
$commonsPage = $commonsPages[0].Value
Assert-Fixture ($commonsPage.title -eq $commonsLock.title -and $commonsPage.imageinfo.Count -eq 1) 'Commons original file disappeared'
$commonsInfo = $commonsPage.imageinfo[0]
Assert-Fixture (($commonsInfo.url -split '\?', 2)[0] -eq $commonsLock.mediaUrl) 'Commons original media URL changed'
Assert-Fixture ([long]$commonsInfo.size -eq [long]$commonsLock.size -and $commonsInfo.mime -eq $commonsLock.mime) 'Commons original size or MIME changed'
Assert-Fixture ($commonsInfo.sha1 -eq $commonsLock.sha1) 'Commons original SHA-1 changed'
Assert-Fixture ($commonsInfo.extmetadata.LicenseShortName.value -eq $commonsLock.license) 'Commons license changed'
Assert-Fixture ($commonsInfo.extmetadata.Artist.value -match [regex]::Escape($commonsLock.author)) 'Commons author changed'
$commonsHtml = Read-Page $commonsLock.pageUrl
Assert-Fixture ($commonsHtml.Contains('VP8/Vorbis')) 'Commons page no longer documents Vorbis audio'
Write-Output 'OK Commons single: original WebM, Vorbis audio and reviewed CC BY 3.0; metadata only'

$playlistPage = Read-Page $lock.blenderPlaylist.url
Assert-Fixture ($playlistPage.Contains($lock.blenderPlaylist.title)) 'Blender playlist title changed or page disappeared'
foreach ($id in $lock.blenderPlaylist.videoIds) {
    $member = "videoId.{0,24}$id.{0,40}playlistId.{0,24}$($lock.blenderPlaylist.id)"
    Assert-Fixture ($playlistPage -match $member) "Blender playlist page no longer lists $id as a member"
    $videoOembed = Read-Json "https://www.youtube.com/oembed?url=$([uri]::EscapeDataString("https://www.youtube.com/watch?v=$id"))&format=json"
    Assert-Fixture (-not [string]::IsNullOrWhiteSpace($videoOembed.title)) "Blender video $id is unavailable"
    $videoJsonText = Invoke-YtDlpMetadata @('--ignore-config', '--quiet', '--no-warnings', '--no-js-runtimes', '--js-runtimes', "quickjs:$quickJs", '--no-playlist', '--skip-download', '--dump-single-json', '--', "https://www.youtube.com/watch?v=$id") "Blender video $id"
    $videoJson = ($videoJsonText | Out-String) | ConvertFrom-Json
    Assert-Fixture ($videoJson.id -eq $id) "Blender video $id metadata identity changed"
    $heights = @($videoJson.formats | Where-Object { $_.vcodec -ne 'none' -and [int]$_.height -gt 0 } | ForEach-Object { [int]$_.height } | Sort-Object -Unique)
    Assert-Fixture ($heights.Count -ge $lock.blenderPlaylist.minDistinctVideoHeights) "Blender video $id offers fewer than two distinct heights"
    Write-Output "OK Blender video $id`: available heights $($heights -join ',')"
}
Write-Output "OK YouTube playlist and mixed URL: $($lock.blenderPlaylist.id), 2 locked entries"

$clipLock = $lock.natureclipVideoPlaylist
Assert-Fixture ($clipLock.url -eq "https://www.youtube.com/playlist?list=$($clipLock.id)") 'NatureClip playlist URL changed'
Assert-Fixture ($clipLock.entries.Count -ge 3) 'NatureClip playlist must lock at least three entries'
Assert-Fixture ($clipLock.minDistinctVideoHeights -ge 2) 'NatureClip resolution requirement was weakened'
Assert-Fixture ($clipLock.maxDurationSeconds -eq 20) 'NatureClip duration cap changed'
Assert-Fixture ($clipLock.maxEstimatedBytesPerEntry -eq 524288) 'NatureClip size cap changed'
$clipIndices = @($clipLock.entries | ForEach-Object { [int]$_.playlistIndex })
Assert-Fixture (@($clipIndices | Select-Object -Unique).Count -eq $clipLock.entries.Count) 'NatureClip playlist positions are duplicated'
$clipCommon = @('--ignore-config', '--quiet', '--no-warnings', '--no-js-runtimes', '--js-runtimes', "quickjs:$quickJs")
$clipFlatText = Invoke-YtDlpMetadata ($clipCommon + @('--flat-playlist', '--dump-single-json', '--', $clipLock.url)) 'NatureClip flat playlist'
$clipFlat = ($clipFlatText | Out-String) | ConvertFrom-Json
Assert-Fixture ($clipFlat.id -eq $clipLock.id -and $clipFlat.title -eq $clipLock.title) 'NatureClip playlist identity changed'
foreach ($entry in $clipLock.entries) {
    $index = [int]$entry.playlistIndex
    Assert-Fixture ($index -ge 1 -and $index -le $clipFlat.entries.Count) "NatureClip entry $index is outside the playlist"
    Assert-Fixture ($clipFlat.entries[$index - 1].id -eq $entry.id) "NatureClip entry $index changed identity"
}
$clipSelections = @{}
foreach ($preset in @(@{ Name = 'Max'; Selector = 'bv*+ba/b' }, @{ Name = 'Min'; Selector = 'wv*+ba/w' })) {
    $clipJsonText = Invoke-YtDlpMetadata ($clipCommon + @('--playlist-items', ($clipIndices -join ','),
        '--skip-download', '-f', $preset.Selector, '--dump-single-json', '--', $clipLock.url)) "NatureClip $($preset.Name)"
    $clipJson = ($clipJsonText | Out-String) | ConvertFrom-Json
    Assert-Fixture ($clipJson.id -eq $clipLock.id -and $clipJson.entries.Count -eq $clipLock.entries.Count) "NatureClip $($preset.Name) selection changed playlist shape"
    for ($i = 0; $i -lt $clipLock.entries.Count; $i++) {
        $entry = $clipLock.entries[$i]
        $video = $clipJson.entries[$i]
        Assert-Fixture ($video.id -eq $entry.id -and [int]$video.playlist_index -eq [int]$entry.playlistIndex) "NatureClip $($preset.Name) entry order changed"
        Assert-Fixture ($video.title -eq $entry.title -and $video.uploader -eq $clipLock.uploader) "NatureClip $($entry.id) title or creator changed"
        Assert-Fixture ($video.license -eq $clipLock.license) "NatureClip $($entry.id) CC BY license changed"
        Assert-Fixture ([double]$video.duration -gt 0 -and [double]$video.duration -le [double]$clipLock.maxDurationSeconds) "NatureClip $($entry.id) exceeds the duration cap"
        $heights = @($video.formats | Where-Object { $_.vcodec -ne 'none' -and [int]$_.height -gt 0 } |
            ForEach-Object { [int]$_.height } | Sort-Object -Unique)
        Assert-Fixture ($heights.Count -ge [int]$clipLock.minDistinctVideoHeights) "NatureClip $($entry.id) offers only one video resolution"
        $parts = @($video.requested_formats)
        Assert-Fixture ($parts.Count -eq 2 -and $parts[0].vcodec -ne 'none' -and $parts[0].acodec -eq 'none' -and
            $parts[1].vcodec -eq 'none' -and $parts[1].acodec -ne 'none') "NatureClip $($entry.id) lacks separate selected video and audio"
        $estimatedBytes = [long]0
        foreach ($part in $parts) {
            Assert-Fixture (@('https', 'm3u8_native') -contains [string]$part.protocol) "NatureClip $($entry.id) selected a downloader protocol that may require FFmpeg network input"
            $estimatedBytes += Estimate-FormatBytes $part ([double]$video.duration) "NatureClip $($entry.id) $($part.format_id)"
        }
        Assert-Fixture ($estimatedBytes -le [long]$clipLock.maxEstimatedBytesPerEntry) "NatureClip $($entry.id) $($preset.Name) estimate $estimatedBytes exceeds $($clipLock.maxEstimatedBytesPerEntry) bytes"
        $clipSelections["$($preset.Name)-$($entry.id)"] = [pscustomobject]@{
            Height = [int]$parts[0].height; AudioId = [string]$parts[1].format_id
        }
        Write-Output "OK NatureClip $($entry.playlistIndex) $($entry.id) $($preset.Name): heights $($heights -join ','), selected $($video.format_id) at $($parts[0].height)p, estimated $estimatedBytes bytes (limit $($clipLock.maxEstimatedBytesPerEntry))"
    }
}
foreach ($entry in $clipLock.entries) {
    $max = $clipSelections["Max-$($entry.id)"]
    $min = $clipSelections["Min-$($entry.id)"]
    Assert-Fixture ($max.Height -gt $min.Height -and $max.AudioId -eq $min.AudioId) "NatureClip $($entry.id) Max/Min heights or common audio changed"
}
Write-Output "OK NatureClip real playlist: $($clipLock.entries.Count) short CC BY entries, metadata only; no media downloaded"

$audio = Read-Archive $lock.archiveAudio
Assert-License $audio $lock.archiveAudio.license $lock.archiveAudio.id
Assert-Fixture ($audio.metadata.creator -eq $lock.archiveAudio.creator) 'Archive audio creator changed'
Assert-Fixture ($lock.archiveAudio.thumbnailExt -eq 'png') 'Archive audio thumbnail expectation changed'
$audioEntries = @(Read-ArchivePlaylist $lock.archiveAudio.id)
Assert-Fixture ($audioEntries.Count -ge 4) "Archive audio playlist is too short (found $($audioEntries.Count) entries)"
for ($i = 0; $i -lt $lock.archiveAudio.entries.Count; $i++) {
    $name = $lock.archiveAudio.entries[$i]
    Assert-PublicFile $audio $name $lock.archiveAudio.id
    Assert-Fixture ($audioEntries[$i + 1].orig -eq $name) "Archive audio entry $name moved from position $($i + 2)"
    $image = $name -replace '\.mp3$', '.png'
    Assert-PublicFile $audio $image $lock.archiveAudio.id
    Assert-Fixture ($audioEntries[$i + 1].image -like "*/$image") "Archive audio entry $name lost its PNG artwork"
}
Write-Output 'OK Archive audio: 3 short, public, bounded playlist entries with PNG artwork'

$pcmLock = $lock.archivePcmPlaylist
$pcm = Read-Archive $pcmLock
Assert-License $pcm $pcmLock.license $pcmLock.id
Assert-Fixture ($pcm.metadata.title -eq $pcmLock.title) 'PCM playlist title changed'
Assert-Fixture ($pcmLock.entries.Count -eq 3) 'PCM playlist must lock exactly three entries'
$pcmEntries = @(Read-ArchivePlaylist $pcmLock.id)
$selectedIndices = @($pcmLock.entries | ForEach-Object { [int]$_.playlistIndex })
Assert-Fixture (@($selectedIndices | Select-Object -Unique).Count -eq 3) 'PCM playlist positions are duplicated'
foreach ($entry in $pcmLock.entries) {
    $index = [int]$entry.playlistIndex
    Assert-Fixture ($index -ge 1 -and $index -le $pcmEntries.Count) "PCM entry $($entry.name) is outside the embed playlist"
    Assert-Fixture ($pcmEntries[$index - 1].orig -eq $entry.name) "PCM entry $($entry.name) moved from position $index"
    Assert-Fixture ($entry.name -match '\.wav$' -and $entry.sourceCodec -eq 'pcm_s16le' -and $entry.format -eq 'WAVE') "PCM entry $($entry.name) is not locked as non-MP3 PCM/WAV"
    $files = @($pcm.files | Where-Object { $_.name -eq $entry.name })
    Assert-Fixture ($files.Count -eq 1 -and -not $files[0].private) "PCM entry $($entry.name) is missing or private"
    $file = $files[0]
    Assert-Fixture ($file.source -eq 'original' -and $file.format -eq $entry.format) "PCM entry $($entry.name) source format changed or became MP3"
    Assert-Fixture ([long]$file.size -eq [long]$entry.size -and $file.md5 -eq $entry.md5 -and $file.sha1 -eq $entry.sha1) "PCM entry $($entry.name) fingerprint changed; inspected codec cannot be trusted"
    Assert-Fixture ([math]::Abs([double]$file.length - [double]$entry.duration) -lt 0.1) "PCM entry $($entry.name) duration changed"
    Write-Output "OK PCM entry $index $($entry.name): source codec $($entry.sourceCodec), $($entry.duration)s; Archive size/MD5/SHA-1 match inspected bytes"
}
$selected = @(Invoke-YtDlpMetadata @('--ignore-config', '--quiet', '--no-warnings', '--playlist-items', ($selectedIndices -join ','), '-f', 'ba/b', '--skip-download', '--print', '%(playlist_index)s|%(id)s|%(ext)s|%(url)s', '--', $pcmLock.url) 'PCM playlist selection')
Assert-Fixture ($selected.Count -eq 3) 'yt-dlp did not select all three PCM entries'
for ($i = 0; $i -lt 3; $i++) {
    $entry = $pcmLock.entries[$i]
    $parts = $selected[$i] -split '\|', 4
    $expectedUrl = "https://archive.org/download/$($pcmLock.id)/$($entry.name)"
    Assert-Fixture ($parts.Count -eq 4 -and [int]$parts[0] -eq [int]$entry.playlistIndex -and $parts[1] -eq "$($pcmLock.id)/$($entry.name)" -and $parts[2] -eq 'wav' -and $parts[3] -eq $expectedUrl) "yt-dlp selected an unexpected or MP3 source for $($entry.name)"
}
Write-Output 'OK PCM playlist: all three selected sources are the locked WAV originals; no MP3 selected'

$video = Read-Archive $lock.archiveVideo
Assert-License $video $lock.archiveVideo.license $lock.archiveVideo.id
Assert-Fixture ($video.metadata.creator -eq $lock.archiveVideo.creator) 'Archive video creator changed'
foreach ($name in $lock.archiveVideo.files) { Assert-PublicFile $video $name $lock.archiveVideo.id }
$videoResolutions = @()
Assert-Fixture ($lock.archiveVideo.resolutions.Count -ge 2) 'Archive video lacks two locked resolutions'
foreach ($resolution in $lock.archiveVideo.resolutions) {
    Assert-Fixture ($lock.archiveVideo.files -contains $resolution.name) "Archive video resolution file $($resolution.name) is not locked"
    $variant = @($video.files | Where-Object { $_.name -eq $resolution.name })
    Assert-Fixture ($variant.Count -eq 1 -and [int]$variant[0].width -eq [int]$resolution.width -and [int]$variant[0].height -eq [int]$resolution.height) "Archive video resolution changed for $($resolution.name)"
    $videoResolutions += "$($resolution.width)x$($resolution.height)"
}
Assert-Fixture (@($videoResolutions | Select-Object -Unique).Count -ge 2) 'Archive video offers fewer than two distinct resolutions'
$videoEntries = @(Read-ArchivePlaylist $lock.archiveVideo.id)
Assert-Fixture ($videoEntries.Count -eq 1 -and [double]$videoEntries[0].duration -ge 110 -and $videoEntries[0].image -match '\.jpg') 'Archive video duration or thumbnail changed'
Write-Output "OK Archive video: 120-second item, two resolutions $($videoResolutions -join ', '), Ogg/MP4 choices and JPEG artwork"

$short = Read-Archive $lock.archiveShortVideo
Assert-License $short $lock.archiveShortVideo.license $lock.archiveShortVideo.id
foreach ($name in $lock.archiveShortVideo.files) { Assert-PublicFile $short $name $lock.archiveShortVideo.id }
$shortEntries = @(Read-ArchivePlaylist $lock.archiveShortVideo.id)
Assert-Fixture ($shortEntries.Count -eq 1 -and [double]$shortEntries[0].duration -le 12) 'Archive short video duration changed'
Write-Output 'OK Archive short video: public MP4 and JPEG thumbnail'

$missing = Read-Json "https://archive.org/metadata/$($lock.missingArchiveId)"
Assert-Fixture (-not $missing.metadata.identifier) 'the intentionally missing Archive item now exists'
$restricted = Read-Archive $lock.restrictedArchive
$private = @($restricted.files | Where-Object { $_.name -eq $lock.restrictedArchive.privateFile })
Assert-Fixture ($private.Count -eq 1 -and $private[0].private) 'restricted Archive file is no longer marked private'
Write-Output 'OK errors: absent Archive item, private Archive file and malformed local URL'
Write-Output 'Fixture preflight passed; yt-dlp simulated format selection, and no media was downloaded.'
