# Gate 0B CLI probes. Later tasks add cases to this entrypoint.
param(
    [ValidateSet('analyze', 'mp3-singles', 'mp3-playlist', 'mp4', 'aac')]
    [string]$Case
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$downloadDir = Join-Path $root 'work\engine\downloads'
$runDir = if ($Case -in @('mp3-singles', 'mp3-playlist', 'mp4', 'aac')) {
    Join-Path $root ('work\engine\cli\' + $Case + '\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
} else {
    Join-Path $root 'work\engine\cli\analyze'
}
$ytDlp = Join-Path $downloadDir 'yt-dlp.exe'
$quickJs = Join-Path $root 'work\engine\build\quickjs\windows-x64\qjs.exe'
$ffmpegDir = Join-Path $root 'work\engine\build\ffmpeg\windows-x64\recipe\ffmpeg-8.1.3'
$ffprobe = Join-Path $ffmpegDir 'ffprobe.exe'

function Read-Lock([string]$path, [string]$label) {
    $markdown = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $match = [regex]::Match($markdown, "(?s)``````json $label\r?\n(.*?)\r?\n``````")
    if (-not $match.Success) { throw "Missing $label block in $path" }
    return ($match.Groups[1].Value | ConvertFrom-Json)
}

function Assert-Hash([string]$path, [string]$expected) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing pinned executable: $path" }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected.ToLowerInvariant()) { throw "SHA-256 mismatch for $path`: $actual" }
    Write-Output "SHA-256 $([IO.Path]::GetFileName($path)): $actual"
}

function Assert-Shape([bool]$condition, [string]$message) {
    if (-not $condition) { throw "CLI verification failed: $message" }
}

function Assert-Runtime($result, [string]$name) {
    Assert-Shape ($result.Stderr -match 'yt-dlp version stable@2026\.08\.19') "$name ran an unexpected yt-dlp version"
    Assert-Shape ($result.Stderr -match '(?m)^\[debug\] JS runtimes: quickjs-2026-06-04\r?$') "$name did not enable only pinned QuickJS"
    Assert-Shape ($result.Stderr -match 'yt_dlp_ejs-0\.8\.0') "$name did not detect bundled EJS 0.8.0"
}

function Stop-EngineChildren([int]$parentId) {
    # The signed yt-dlp one-file executable can leave a child alive after its
    # launcher exits; that child keeps redirected stdout/stderr pipes open.
    foreach ($child in @(Get-CimInstance Win32_Process -Filter "ParentProcessId = $parentId")) {
        Stop-EngineChildren ([int]$child.ProcessId)
        Stop-Process -Id ([int]$child.ProcessId) -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-Engine([string]$name, [string[]]$arguments, [int]$timeoutSeconds) {
    # Windows PowerShell 5.1 has no ProcessStartInfo.ArgumentList. Every argument
    # here is a controlled option, local path or locked URL; quote each one so
    # the mixed URL's ampersand and paths with spaces survive Windows parsing.
    foreach ($argument in $arguments) {
        if ($argument.Contains('"')) { throw "Unexpected quote in argument for $name" }
    }
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $ytDlp
    $start.Arguments = (($arguments | ForEach-Object { '"' + $_ + '"' }) -join ' ')
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $start.StandardErrorEncoding = New-Object System.Text.UTF8Encoding($false)
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $start
    $clock = [Diagnostics.Stopwatch]::StartNew()
    try {
        if (-not $process.Start()) { throw "Could not start $ytDlp" }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $finished = $process.WaitForExit($timeoutSeconds * 1000)
        $remainingMs = [int][math]::Max(0, $timeoutSeconds * 1000 - $clock.ElapsedMilliseconds)
        $readsFinished = [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdoutTask, $stderrTask), $remainingMs)
        if (-not $finished -or -not $readsFinished) {
            Stop-EngineChildren $process.Id
            if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit(5000) | Out-Null }
            $readsFinished = [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdoutTask, $stderrTask), 5000)
        }
        $clock.Stop()
        if (-not $readsFinished) { throw "$name timed out and its output pipe remained open; see $runDir" }
        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result
        [IO.File]::WriteAllText((Join-Path $runDir "$name.stdout.txt"), $stdout, (New-Object System.Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText((Join-Path $runDir "$name.stderr.txt"), $stderr, (New-Object System.Text.UTF8Encoding($false)))
        $status = if ($finished -and $clock.Elapsed.TotalSeconds -lt $timeoutSeconds) { $process.ExitCode } else { 'timeout' }
        Write-Host "$name`: exit=$status elapsed=$([math]::Round($clock.Elapsed.TotalSeconds, 2))s"
        if ($status -eq 'timeout') { throw "$name timed out after $timeoutSeconds seconds; see $runDir" }
        if ($process.ExitCode -ne 0) { throw "$name exited $($process.ExitCode); see $runDir" }
        return [pscustomobject]@{ Stdout = $stdout; Stderr = $stderr; Seconds = $clock.Elapsed.TotalSeconds }
    }
    finally { $process.Dispose() }
}

function Assert-Mp4([string]$path, [string]$name, [int]$width, [int]$height, [double]$duration, [double]$durationTolerance = 2) {
    Assert-Shape (Test-Path -LiteralPath $path -PathType Leaf) "$name output is missing"
    $probeText = (& $ffprobe -v error -show_entries 'stream=codec_name,codec_type,width,height:format=format_name,duration,size' -of json -- $path | Out-String)
    Assert-Shape ($LASTEXITCODE -eq 0) "ffprobe failed for $name"
    [IO.File]::WriteAllText((Join-Path $runDir "$name.ffprobe.json"), $probeText, (New-Object System.Text.UTF8Encoding($false)))
    $probe = $probeText | ConvertFrom-Json
    $video = @($probe.streams | Where-Object { $_.codec_type -eq 'video' })
    $audio = @($probe.streams | Where-Object { $_.codec_type -eq 'audio' })
    Assert-Shape ($probe.format.format_name -match '(^|,)mp4(,|$)') "$name is not an MP4 container"
    Assert-Shape ($video.Count -eq 1 -and $audio.Count -eq 1 -and $probe.streams.Count -eq 2) "$name needs one video and one audio stream"
    Assert-Shape ($video[0].width -eq $width -and $video[0].height -eq $height) "$name video dimensions differ from selection"
    Assert-Shape ($video[0].codec_name -ne 'none' -and $audio[0].codec_name -ne 'none') "$name has an unknown codec"
    Assert-Shape ([math]::Abs([double]$probe.format.duration - $duration) -lt $durationTolerance) "$name duration differs from requested sample"
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Output "$name`: video=$($video[0].codec_name) $($video[0].width)x$($video[0].height) audio=$($audio[0].codec_name) duration=$($probe.format.duration)s bytes=$($probe.format.size) sha256=$hash"
}

if (-not $Case) { throw 'Specify -Case analyze, mp3-singles, mp3-playlist, mp4 or aac' }

$source = Read-Lock (Join-Path $root 'docs\engine-sources.md') 'source-lock'
$fixtures = Read-Lock (Join-Path $root 'docs\gates\evidence\0b\fixtures.md') 'fixture-lock'
Assert-Hash $ytDlp $source.ytDlp.binaries.windowsX64.sha256
Assert-Hash $quickJs 'bec67f8f87fa22958d3ab8be5508088116b8bff90032323d82c94545e1698b83'
if ($source.ytDlp.ejsVersion -ne $source.ejs.version) { throw 'yt-dlp/EJS source lock mismatch' }

# Recheck fixture availability immediately before interpreting a CLI failure.
& (Join-Path $PSScriptRoot 'verify-fixtures.ps1')
if (-not $?) { throw 'Fixture preflight failed' }
New-Item -ItemType Directory -Path $runDir -Force | Out-Null

if ($Case -in @('mp3-singles', 'mp3-playlist', 'mp4', 'aac')) {
    Assert-Hash $ffprobe 'bf44a50347aaba3e433c34c8c881d67eeaca41001577482ce3ba69b780824ec7'
    Assert-Hash (Join-Path $ffmpegDir 'ffmpeg.exe') 'fa050630ddf5b7c3303d8dab5e5a42e7023547fb78ec9b90b5be0a4f788a7e66'
}

if ($Case -eq 'aac') {
    $common = @('--ignore-config', '--verbose', '--no-js-runtimes', '--js-runtimes', "quickjs:$quickJs")
    $entry = @($fixtures.natureclipVideoPlaylist.entries | Where-Object { $_.playlistIndex -eq 7 })
    Assert-Shape ($entry.Count -eq 1 -and $entry[0].id -eq 'YC0kTqKbeFs') 'AAC fixture identity changed'
    $id = $entry[0].id
    $url = "https://www.youtube.com/watch?v=$id"
    $selector = 'bv*+ba/b'
    $selection = Invoke-Engine 'source-selection' ($common + @('--no-playlist', '--skip-download',
        '-f', $selector, '--dump-single-json', '--', $url)) 180
    Assert-Runtime $selection 'source-selection'
    $info = $selection.Stdout | ConvertFrom-Json
    $formats = @($info.requested_formats)
    Assert-Shape ($info.id -eq $id -and $formats.Count -eq 2) 'AAC source did not select separate video and audio'
    $videoFormat = @($formats | Where-Object { $_.vcodec -ne 'none' -and $_.acodec -eq 'none' })
    $audioFormat = @($formats | Where-Object { $_.acodec -ne 'none' -and $_.vcodec -eq 'none' })
    Assert-Shape ($videoFormat.Count -eq 1 -and $audioFormat.Count -eq 1) 'AAC source stream layout changed'
    Assert-Shape ($videoFormat[0].vcodec -match '^avc1\.' -and $audioFormat[0].acodec -eq 'opus') 'AAC source no longer has H.264 video and non-AAC Opus audio'
    Assert-Shape ([int]$videoFormat[0].width -gt 0 -and [int]$videoFormat[0].height -gt 0 -and [double]$info.duration -gt 0) 'AAC source dimensions or duration are missing'
    Write-Output "source selection: id=$id video=$($videoFormat[0].format_id)/$($videoFormat[0].vcodec) $($videoFormat[0].width)x$($videoFormat[0].height) audio=$($audioFormat[0].format_id)/$($audioFormat[0].acodec) duration=$($info.duration)s"

    $outputDir = Join-Path $runDir 'converted'
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    $download = Invoke-Engine 'aac-download' ($common + @('--no-playlist', '-f', $selector,
        '--merge-output-format', 'mp4', '--postprocessor-args', 'Merger+ffmpeg_o:-c:a aac',
        '--keep-video', '--ffmpeg-location', $ffmpegDir,
        '-o', (Join-Path $outputDir '%(id)s.%(ext)s'), '--', $url)) 300
    Assert-Runtime $download 'aac-download'
    Assert-Shape ($download.Stdout.Contains("[info] ${id}: Downloading 1 format(s): $($videoFormat[0].format_id)+$($audioFormat[0].format_id)")) 'AAC download selected different formats'
    $ffmpegLines = @($download.Stderr -split '\r?\n' | Where-Object { $_ -match '^\[debug\] ffmpeg command line:' })
    Assert-Shape ($ffmpegLines.Count -eq 1 -and $ffmpegLines[0] -match '-c copy' -and $ffmpegLines[0] -match '-c:a aac' -and $ffmpegLines[0] -match '-i file:.*-i file:' -and $ffmpegLines[0] -notmatch '-i https?:') 'AAC merge did not use local inputs and audio-only encoding'

    $videoPath = Join-Path $outputDir "$id.f$($videoFormat[0].format_id).$($videoFormat[0].ext)"
    $audioPath = Join-Path $outputDir "$id.f$($audioFormat[0].format_id).$($audioFormat[0].ext)"
    $outputPath = Join-Path $outputDir "$id.mp4"
    foreach ($item in @(@{ Name = 'source-video'; Path = $videoPath },
            @{ Name = 'source-audio'; Path = $audioPath },
            @{ Name = 'aac-output'; Path = $outputPath })) {
        Assert-Shape (Test-Path -LiteralPath $item.Path -PathType Leaf) "$($item.Name) file is missing"
        $probeText = (& $ffprobe -v error -show_entries 'stream=codec_name,codec_type,width,height,bit_rate:format=format_name,duration,size' -of json -- $item.Path | Out-String)
        Assert-Shape ($LASTEXITCODE -eq 0) "ffprobe failed for $($item.Name)"
        [IO.File]::WriteAllText((Join-Path $runDir "$($item.Name).ffprobe.json"), $probeText, (New-Object System.Text.UTF8Encoding($false)))
        $probe = $probeText | ConvertFrom-Json
        $video = @($probe.streams | Where-Object { $_.codec_type -eq 'video' })
        $audio = @($probe.streams | Where-Object { $_.codec_type -eq 'audio' })
        if ($item.Name -eq 'source-video') {
            Assert-Shape ($video.Count -eq 1 -and $audio.Count -eq 0 -and $video[0].codec_name -eq 'h264') 'source video is not H.264-only'
            Assert-Shape ($video[0].width -eq $videoFormat[0].width -and $video[0].height -eq $videoFormat[0].height) 'source video dimensions changed'
        } elseif ($item.Name -eq 'source-audio') {
            Assert-Shape ($video.Count -eq 0 -and $audio.Count -eq 1 -and $audio[0].codec_name -eq 'opus') 'source audio is not Opus-only'
        } else {
            Assert-Shape ($probe.format.format_name -match '(^|,)mp4(,|$)' -and $video.Count -eq 1 -and $audio.Count -eq 1 -and $probe.streams.Count -eq 2) 'AAC output is not a two-stream MP4'
            Assert-Shape ($video[0].codec_name -eq 'h264' -and $audio[0].codec_name -eq 'aac') 'AAC output codecs are wrong'
            Assert-Shape ($video[0].width -eq $videoFormat[0].width -and $video[0].height -eq $videoFormat[0].height) 'AAC output video dimensions changed'
            Assert-Shape ([math]::Abs([double]$probe.format.duration - [double]$info.duration) -lt 2) 'AAC output duration changed'
        }
        $hash = (Get-FileHash -LiteralPath $item.Path -Algorithm SHA256).Hash.ToLowerInvariant()
        Write-Output "$($item.Name): video=$(($video | ForEach-Object { $_.codec_name }) -join ',') audio=$(($audio | ForEach-Object { $_.codec_name }) -join ',') duration=$($probe.format.duration)s bytes=$($probe.format.size) sha256=$hash"
    }
    Assert-Shape (@(Get-ChildItem -LiteralPath $outputDir -File).Count -eq 3) 'AAC conversion produced unexpected media files'
    Write-Output "Full stdout/stderr, ffprobe JSON and media: $runDir (ignored)"
    return
}

if ($Case -eq 'mp4') {
    $common = @('--ignore-config', '--verbose', '--no-js-runtimes', '--js-runtimes', "quickjs:$quickJs")
    $playlist = $fixtures.natureclipVideoPlaylist
    $playlistUrl = $playlist.url
    $entries = @($playlist.entries)
    Assert-Shape ($entries.Count -eq 3) 'NatureClip fixture must lock exactly three MP4 entries'
    $playlistIndices = (@($entries | ForEach-Object { [int]$_.playlistIndex }) -join ',')
    $expectedIds = @($entries | ForEach-Object { $_.id })
    $selections = @{}
    foreach ($quality in @(@{ Name = 'max'; Selector = 'bv*+ba/b' },
            @{ Name = 'min'; Selector = 'wv*+ba/w' })) {
        $name = $quality.Name
        $selection = Invoke-Engine "$name-selection" ($common + @('--playlist-items', $playlistIndices,
            '--skip-download', '-f', $quality.Selector,
            '--print', '%(playlist_index)s|%(id)s|%(format_id)s|%(height)s|%(width)s|%(duration)s',
            '--', $playlistUrl)) 180
        Assert-Runtime $selection "$name-selection"
        $lines = @($selection.Stdout -split '\r?\n' | Where-Object { $_ -ne '' })
        Assert-Shape ($lines.Count -eq $entries.Count) "$name selection did not yield exactly $($entries.Count) playlist entries"
        for ($i = 0; $i -lt $entries.Count; $i++) {
            $fields = $lines[$i] -split '\|'
            Assert-Shape ($fields.Count -eq 6 -and $fields[0] -eq [string]$entries[$i].playlistIndex -and $fields[1] -eq $expectedIds[$i]) "$name playlist order or identity changed"
            Assert-Shape ($fields[2] -match '^([^+]+)\+([^+]+)$' -and [int]$fields[3] -gt 0 -and [int]$fields[4] -gt 0) "$name entry $($fields[1]) lacks separate video/audio formats or dimensions"
            $selections["$name-$($fields[1])"] = [pscustomobject]@{
                FormatId = $fields[2]; VideoId = $Matches[1]; AudioId = $Matches[2]
                Height = [int]$fields[3]; Width = [int]$fields[4]; Duration = [double]$fields[5]
            }
            Write-Output "$name selection entry $($entries[$i].playlistIndex): id=$($fields[1]) format=$($fields[2]) $($fields[4])x$($fields[3]) duration=$($fields[5])s"
        }
    }
    foreach ($id in $expectedIds) {
        $max = $selections["max-$id"]
        $min = $selections["min-$id"]
        Assert-Shape ($max.Height -gt $min.Height) "Max video is not taller than Min for $id"
        Assert-Shape ($max.AudioId -eq $min.AudioId) "Min did not retain Max audio format for $id"
    }
    foreach ($quality in @(@{ Name = 'max'; Selector = 'bv*+ba/b' },
            @{ Name = 'min'; Selector = 'wv*+ba/w' })) {
        $name = $quality.Name
        $outputDir = Join-Path $runDir $name
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        $download = Invoke-Engine "$name-download" ($common + @('--playlist-items', $playlistIndices,
            '-f', $quality.Selector, '--merge-output-format', 'mp4', '--ffmpeg-location', $ffmpegDir,
            '-o', (Join-Path $outputDir '%(id)s.%(ext)s'), '--', $playlistUrl)) 600
        Assert-Runtime $download "$name-download"
        foreach ($id in $expectedIds) {
            $selected = $selections["$name-$id"]
            Assert-Shape ($download.Stdout.Contains("[info] ${id}: Downloading 1 format(s): $($selected.FormatId)")) "$name download format changed for $id"
            $output = Join-Path $outputDir "$id.mp4"
            Assert-Shape (Test-Path -LiteralPath $output -PathType Leaf) "$name MP4 is missing for $id"
            Assert-Mp4 $output "$name-$id" $selected.Width $selected.Height $selected.Duration
        }
        Assert-Shape (@(Get-ChildItem -LiteralPath $outputDir -Filter '*.mp4' -File).Count -eq $entries.Count) "$name did not produce exactly $($entries.Count) MP4 files"
    }

    $singleUrl = $fixtures.archiveVideo.url
    $heightLimit = 240
    $boundedSelector = "bv*[height<=$heightLimit]+ba/b[height<=$heightLimit]"
    $singleSelection = Invoke-Engine 'single-selection' ($common + @('--no-playlist', '--skip-download',
        '-f', $boundedSelector, '--print', '%(id)s|%(format_id)s|%(height)s|%(width)s|%(duration)s', '--', $singleUrl)) 180
    Assert-Runtime $singleSelection 'single-selection'
    $singleFields = $singleSelection.Stdout.Trim() -split '\|'
    Assert-Shape ($singleFields.Count -eq 5 -and $singleFields[0] -eq $fixtures.archiveVideo.id -and [int]$singleFields[2] -gt 0 -and [int]$singleFields[2] -le $heightLimit) 'bounded single selection changed'
    $unbounded = Invoke-Engine 'single-unbounded-selection' ($common + @('--no-playlist', '--skip-download',
        '-f', 'bv*+ba/b', '--print', '%(height)s', '--', $singleUrl)) 180
    Assert-Runtime $unbounded 'single-unbounded-selection'
    Assert-Shape ([int]$unbounded.Stdout.Trim() -gt [int]$singleFields[2]) 'single fixture no longer demonstrates a height cap'
    Write-Output "single selection: format=$($singleFields[1]) $($singleFields[3])x$($singleFields[2]) limit=$heightLimit; unbounded=$($unbounded.Stdout.Trim())"
    $singleDir = Join-Path $runDir 'single-240'
    New-Item -ItemType Directory -Path $singleDir -Force | Out-Null
    $singleDownload = Invoke-Engine 'single-download' ($common + @('--no-playlist', '-f', $boundedSelector,
        '--merge-output-format', 'mp4', '--ffmpeg-location', $ffmpegDir,
        '-o', (Join-Path $singleDir '%(id)s.%(ext)s'), '--', $singleUrl)) 300
    Assert-Runtime $singleDownload 'single-download'
    Assert-Shape ($singleDownload.Stdout.Contains("[info] $($fixtures.archiveVideo.id): Downloading 1 format(s): $($singleFields[1])")) 'single download format changed'
    Assert-Mp4 (Join-Path $singleDir "$($fixtures.archiveVideo.id).mp4") 'single-240' ([int]$singleFields[3]) ([int]$singleFields[2]) ([double]$singleFields[4])
    Write-Output "Full stdout/stderr, ffprobe JSON and MP4 outputs: $runDir (ignored)"
    return
}

if ($Case -eq 'mp3-playlist') {
    $fixture = $fixtures.archivePcmPlaylist
    $indices = @($fixture.entries | ForEach-Object { [int]$_.playlistIndex })
    $common = @('--ignore-config', '--verbose', '--no-js-runtimes', '--js-runtimes', "quickjs:$quickJs")
    $playlist = Invoke-Engine 'playlist-flat' ($common + @('--flat-playlist', '--dump-single-json', '--', $fixture.url)) 180
    Assert-Runtime $playlist 'playlist-flat'
    $playlistJson = $playlist.Stdout | ConvertFrom-Json
    Assert-Shape ($playlistJson._type -eq 'playlist' -and $playlistJson.id -eq $fixture.id) 'PCM playlist identity changed'
    Assert-Shape ($fixture.entries.Count -eq 3 -and $playlistJson.entries.Count -ge ($indices | Measure-Object -Maximum).Maximum) 'PCM bounded playlist shape changed'
    foreach ($entry in $fixture.entries) {
        $expectedId = "$($fixture.id)/$($entry.name)"
        Assert-Shape ($playlistJson.entries[[int]$entry.playlistIndex - 1].id -eq $expectedId) "PCM entry $($entry.playlistIndex) changed"
    }
    $mismatches = @()
    $playlistHashes = @{}
    foreach ($preset in @(@{ Name = 'max'; Bitrate = 320 }, @{ Name = 'min'; Bitrate = 128 })) {
        $outputDir = Join-Path $runDir $preset.Name
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        $arguments = $common + @('--playlist-items', ($indices -join ','), '-f', 'ba/b', '-x', '--audio-format', 'mp3',
            '--audio-quality', "$($preset.Bitrate)K", '--ffmpeg-location', $ffmpegDir,
            '-o', (Join-Path $outputDir '%(playlist_index)s.%(ext)s'), '--', $fixture.url)
        $result = Invoke-Engine $preset.Name $arguments 180
        Assert-Runtime $result $preset.Name
        foreach ($entry in $fixture.entries) {
            $index = [int]$entry.playlistIndex
            $output = Join-Path $outputDir "$index.mp3"
            Assert-Shape (Test-Path -LiteralPath $output -PathType Leaf) "$($preset.Name) entry $index output is missing"
            Assert-Shape ($result.Stdout -match "(?m)^\[ExtractAudio\] Destination: .*[/\\]$index\.mp3\r?$") "$($preset.Name) entry $index did not convert its WAV source"
            $probeText = (& $ffprobe -v error -show_entries 'stream=codec_name,codec_type,bit_rate:format=duration,bit_rate' -of json -- $output | Out-String)
            Assert-Shape ($LASTEXITCODE -eq 0) "ffprobe failed for $($preset.Name) entry $index"
            [IO.File]::WriteAllText((Join-Path $runDir "$($preset.Name)-$index.ffprobe.json"), $probeText, (New-Object System.Text.UTF8Encoding($false)))
            $probe = $probeText | ConvertFrom-Json
            $audio = @($probe.streams | Where-Object { $_.codec_type -eq 'audio' })
            Assert-Shape ($audio.Count -eq 1 -and $probe.streams.Count -eq 1 -and $audio[0].codec_name -eq 'mp3') "$($preset.Name) entry $index is not audio-only MP3"
            Assert-Shape ([double]$probe.format.duration -gt 0 -and [double]$probe.format.duration -lt 30) "$($preset.Name) entry $index duration is unexpected"
            $actual = [int]$audio[0].bit_rate
            $target = $preset.Bitrate * 1000
            if ([math]::Abs($actual - $target) -gt ($target * 0.01)) {
                $mismatches += "$($preset.Name) entry $index ($($entry.name)): $actual bps, expected $target bps"
            }
            $hash = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant()
            $playlistHashes["$($preset.Name)-$index"] = $hash
            Write-Output "$($preset.Name) entry $index`: stream=$actual bps format=$($probe.format.bit_rate) bps duration=$($probe.format.duration)s sha256=$hash"
        }
        Assert-Shape (@(Get-ChildItem -LiteralPath $outputDir -Filter '*.mp3' -File).Count -eq 3) "$($preset.Name) did not produce exactly three MP3 files"
    }
    foreach ($entry in $fixture.entries) {
        $index = [int]$entry.playlistIndex
        Assert-Shape ($playlistHashes["max-$index"] -ne $playlistHashes["min-$index"]) "entry $index Max/Min outputs are identical"
    }
    # A direct original URL stands in for an individual queue item's invocation.
    # Exercise each entry independently at Max to confirm this option is viable.
    $singleDir = Join-Path $runDir 'per-entry-max'
    New-Item -ItemType Directory -Path $singleDir -Force | Out-Null
    foreach ($entry in $fixture.entries) {
        $index = [int]$entry.playlistIndex
        $entryUrl = "https://archive.org/download/$($fixture.id)/$($entry.name)"
        $single = Invoke-Engine "per-entry-$index" ($common + @('--no-playlist', '-f', 'ba/b', '-x', '--audio-format', 'mp3',
            '--audio-quality', '320K', '--ffmpeg-location', $ffmpegDir, '-o', (Join-Path $singleDir "$index.%(ext)s"), '--', $entryUrl)) 180
        Assert-Runtime $single "per-entry-$index"
        $output = Join-Path $singleDir "$index.mp3"
        Assert-Shape (Test-Path -LiteralPath $output -PathType Leaf) "per-entry $index output is missing"
        Assert-Shape ($single.Stdout -match "(?m)^\[ExtractAudio\] Destination: .*[/\\]$index\.mp3\r?$") "per-entry $index did not convert its WAV source"
        $probeText = (& $ffprobe -v error -show_entries 'stream=codec_name,codec_type,bit_rate:format=duration,bit_rate' -of json -- $output | Out-String)
        Assert-Shape ($LASTEXITCODE -eq 0) "ffprobe failed for per-entry $index"
        [IO.File]::WriteAllText((Join-Path $runDir "per-entry-$index.ffprobe.json"), $probeText, (New-Object System.Text.UTF8Encoding($false)))
        $probe = $probeText | ConvertFrom-Json
        $audio = @($probe.streams | Where-Object { $_.codec_type -eq 'audio' })
        Assert-Shape ($audio.Count -eq 1 -and $probe.streams.Count -eq 1 -and $audio[0].codec_name -eq 'mp3') "per-entry $index is not audio-only MP3"
        Assert-Shape ([math]::Abs([int]$audio[0].bit_rate - 320000) -le 3200) "per-entry $index missed 320K"
        Assert-Shape ([math]::Abs([double]$probe.format.duration - [double]$entry.duration) -lt 0.2) "per-entry $index duration changed"
        $hash = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant()
        Write-Output "per-entry $index`: stream=$($audio[0].bit_rate) bps duration=$($probe.format.duration)s sha256=$hash"
    }
    Assert-Shape (@(Get-ChildItem -LiteralPath $singleDir -Filter '*.mp3' -File).Count -eq 3) 'per-entry invocations did not produce three MP3 files'
    Write-Output "Full stdout/stderr, ffprobe JSON and MP3 outputs: $runDir (ignored)"
    Assert-Shape ($mismatches.Count -eq 0) ("playlist presets missed intended bitrates: " + ($mismatches -join '; '))
    return
}

if ($Case -eq 'mp3-singles') {
    $hashes = @{}
    foreach ($bitrate in @(320, 256, 192, 128)) {
        $outputDir = Join-Path $runDir "$bitrate"
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        $arguments = @('--ignore-config', '--verbose', '--no-js-runtimes', '--js-runtimes', "quickjs:$quickJs",
            '--no-playlist', '-f', 'ba/b', '-x', '--audio-format', 'mp3', '--audio-quality', "${bitrate}K", '--keep-video',
            '--ffmpeg-location', $ffmpegDir, '-o', (Join-Path $outputDir 'source.%(ext)s'),
            '--', $fixtures.commonsVorbisSingle.mediaUrl)
        $result = Invoke-Engine "mp3-$bitrate" $arguments 180
        Assert-Runtime $result "mp3-$bitrate"
        Assert-Hash (Join-Path $outputDir 'source.webm') $fixtures.commonsVorbisSingle.sha256
        $output = Join-Path $outputDir 'source.mp3'
        Assert-Shape (Test-Path -LiteralPath $output -PathType Leaf) "${bitrate}K output is missing"
        Assert-Shape ($result.Stdout -match '(?m)^\[ExtractAudio\] Destination:') "${bitrate}K did not convert the Vorbis source"
        $probeText = (& $ffprobe -v error -show_entries 'stream=codec_name,codec_type,bit_rate:format=duration,bit_rate' -of json -- $output | Out-String)
        Assert-Shape ($LASTEXITCODE -eq 0) "ffprobe failed for ${bitrate}K"
        [IO.File]::WriteAllText((Join-Path $runDir "mp3-$bitrate.ffprobe.json"), $probeText, (New-Object System.Text.UTF8Encoding($false)))
        $probe = $probeText | ConvertFrom-Json
        $audio = @($probe.streams | Where-Object { $_.codec_type -eq 'audio' })
        Assert-Shape ($audio.Count -eq 1 -and $probe.streams.Count -eq 1) "${bitrate}K must contain one audio stream and no video"
        Assert-Shape ($audio[0].codec_name -eq 'mp3') "${bitrate}K output codec is not MP3"
        $actual = [int]$audio[0].bit_rate
        $target = $bitrate * 1000
        # LAME is expected to emit CBR here; allow 1% for encoder/container reporting.
        Assert-Shape ([math]::Abs($actual - $target) -le ($target * 0.01)) "${bitrate}K stream bitrate is $actual bps"
        Assert-Shape ([double]$probe.format.duration -ge 14 -and [double]$probe.format.duration -le 16) "${bitrate}K duration is unexpected"
        $hash = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant()
        $hashes[$bitrate] = $hash
        Write-Output "${bitrate}K: stream=$actual bps format=$($probe.format.bit_rate) bps duration=$($probe.format.duration)s sha256=$hash"
    }
    Assert-Shape (@($hashes.Values | Select-Object -Unique).Count -eq 4) 'MP3 outputs are not distinct'
    Write-Output "Full stdout/stderr, ffprobe JSON and MP3 outputs: $runDir (ignored)"
    return
}

$common = @('--ignore-config', '--verbose', '--no-js-runtimes', '--js-runtimes', "quickjs:$quickJs", '--skip-download')
$single = Invoke-Engine 'single' ($common + @('--dump-single-json', '--no-playlist', '--', $fixtures.youtubeShort.url)) 180
Assert-Runtime $single 'single'
$singleJson = $single.Stdout | ConvertFrom-Json
Assert-Shape ($singleJson.id -eq $fixtures.youtubeShort.id) 'single video ID'
Assert-Shape ($singleJson._type -eq 'video') 'single URL did not return a video'
Assert-Shape ($singleJson.formats.Count -gt 0) 'single video has no formats'
Assert-Shape ($single.Stderr -match 'JS Challenge Providers: .*quickjs') 'single video did not register QuickJS challenge provider'

$playlist = Invoke-Engine 'playlist' ($common + @('--dump-single-json', '--flat-playlist', '--', $fixtures.blenderPlaylist.url)) 180
Assert-Runtime $playlist 'playlist'
$playlistJson = $playlist.Stdout | ConvertFrom-Json
Assert-Shape ($playlistJson._type -eq 'playlist') 'pure playlist JSON type'
Assert-Shape ($playlistJson.id -eq $fixtures.blenderPlaylist.id) 'pure playlist ID'
Assert-Shape ($playlistJson.entries.Count -ge 2) 'pure playlist has fewer than two entries'
foreach ($id in $fixtures.blenderPlaylist.videoIds) {
    Assert-Shape (@($playlistJson.entries | Where-Object { $_.id -eq $id }).Count -gt 0) "pure playlist missing locked entry $id"
}

$mixed = Invoke-Engine 'mixed' ($common + @('--dump-single-json', '--no-playlist', '--', $fixtures.blenderPlaylist.mixedUrl)) 180
Assert-Runtime $mixed 'mixed'
$mixedJson = $mixed.Stdout | ConvertFrom-Json
Assert-Shape ($mixedJson.id -eq $fixtures.blenderPlaylist.videoIds[0]) 'mixed URL video ID'
Assert-Shape ($mixedJson._type -eq 'video') 'mixed URL did not return a video'
Assert-Shape ($mixedJson.formats.Count -gt 0) 'mixed video has no formats'
Assert-Shape ($mixed.Stderr -match 'JS Challenge Providers: .*quickjs') 'mixed video did not register QuickJS challenge provider'

Write-Output "single: id=$($singleJson.id) formats=$($singleJson.formats.Count)"
Write-Output "playlist: id=$($playlistJson.id) entries=$($playlistJson.entries.Count)"
Write-Output "mixed: id=$($mixedJson.id) formats=$($mixedJson.formats.Count)"
Write-Output "playlist analysis elapsed: $([math]::Round($playlist.Seconds, 2))s"
Write-Output "Full stdout/stderr: $runDir (ignored)"
