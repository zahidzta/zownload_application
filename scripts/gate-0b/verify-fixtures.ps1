# Read-only availability check for the 0B-02 real-media fixtures.
# This checks catalog/oEmbed/playlist-page data, never media bytes or yt-dlp behavior.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$fixturePath = Join-Path $root 'docs\gates\evidence\0b\fixtures.md'
$markdown = Get-Content -LiteralPath $fixturePath -Raw -Encoding UTF8
$blocks = [regex]::Matches($markdown, '(?s)```json fixture-lock\r?\n(.*?)\r?\n```')
if ($blocks.Count -ne 1) { throw 'Fixture lock invalid: expected one json fixture-lock block' }
$lock = $blocks[0].Groups[1].Value | ConvertFrom-Json

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

Assert-Fixture ($lock.schema -eq 1) 'unexpected schema version'
Assert-Fixture ($lock.checkedOn -match '^\d{4}-\d{2}-\d{2}$') 'missing access date'
Assert-Fixture ($lock.youtubeShort.url -eq "https://www.youtube.com/watch?v=$($lock.youtubeShort.id)") 'YouTube single URL changed'
Assert-Fixture ($lock.blenderPlaylist.url -eq "https://www.youtube.com/playlist?list=$($lock.blenderPlaylist.id)") 'YouTube playlist URL changed'
Assert-Fixture ($lock.blenderPlaylist.mixedUrl -eq "https://www.youtube.com/watch?v=$($lock.blenderPlaylist.videoIds[0])&list=$($lock.blenderPlaylist.id)") 'mixed URL changed'
Assert-Fixture ($lock.blenderPlaylist.videoIds.Count -eq 2) 'expected two locked Blender entries'
Assert-Fixture ($lock.invalidInput -eq 'not-a-url') 'invalid-input fixture changed'

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
}
Write-Output "OK YouTube playlist and mixed URL: $($lock.blenderPlaylist.id), 2 locked entries"

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

$video = Read-Archive $lock.archiveVideo
Assert-License $video $lock.archiveVideo.license $lock.archiveVideo.id
Assert-Fixture ($video.metadata.creator -eq $lock.archiveVideo.creator) 'Archive video creator changed'
foreach ($name in $lock.archiveVideo.files) { Assert-PublicFile $video $name $lock.archiveVideo.id }
$videoEntries = @(Read-ArchivePlaylist $lock.archiveVideo.id)
Assert-Fixture ($videoEntries.Count -eq 1 -and [double]$videoEntries[0].duration -ge 110 -and $videoEntries[0].image -match '\.jpg') 'Archive video duration or thumbnail changed'
Write-Output 'OK Archive video: 120-second item, Ogg/MP4 choices and JPEG artwork'

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
Write-Output 'Fixture preflight passed; no media or engine command was run.'
