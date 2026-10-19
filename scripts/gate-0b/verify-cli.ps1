# Gate 0B CLI probes. Later tasks add cases to this entrypoint.
param(
    [ValidateSet('analyze', 'mp3-singles')]
    [string]$Case
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$downloadDir = Join-Path $root 'work\engine\downloads'
$runDir = if ($Case -eq 'mp3-singles') {
    Join-Path $root ('work\engine\cli\mp3-singles\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
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
        if (-not $finished) { $process.Kill(); $process.WaitForExit() }
        $clock.Stop()
        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result
        [IO.File]::WriteAllText((Join-Path $runDir "$name.stdout.txt"), $stdout, (New-Object System.Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText((Join-Path $runDir "$name.stderr.txt"), $stderr, (New-Object System.Text.UTF8Encoding($false)))
        $status = if ($finished) { $process.ExitCode } else { 'timeout' }
        Write-Host "$name`: exit=$status elapsed=$([math]::Round($clock.Elapsed.TotalSeconds, 2))s"
        if (-not $finished) { throw "$name timed out after $timeoutSeconds seconds; see $runDir" }
        if ($process.ExitCode -ne 0) { throw "$name exited $($process.ExitCode); see $runDir" }
        return [pscustomobject]@{ Stdout = $stdout; Stderr = $stderr; Seconds = $clock.Elapsed.TotalSeconds }
    }
    finally { $process.Dispose() }
}

if (-not $Case) { throw 'Specify -Case analyze or -Case mp3-singles' }

$source = Read-Lock (Join-Path $root 'docs\engine-sources.md') 'source-lock'
$fixtures = Read-Lock (Join-Path $root 'docs\gates\evidence\0b\fixtures.md') 'fixture-lock'
Assert-Hash $ytDlp $source.ytDlp.binaries.windowsX64.sha256
Assert-Hash $quickJs 'bec67f8f87fa22958d3ab8be5508088116b8bff90032323d82c94545e1698b83'
if ($source.ytDlp.ejsVersion -ne $source.ejs.version) { throw 'yt-dlp/EJS source lock mismatch' }

# Recheck fixture availability immediately before interpreting a CLI failure.
& (Join-Path $PSScriptRoot 'verify-fixtures.ps1')
if (-not $?) { throw 'Fixture preflight failed' }
New-Item -ItemType Directory -Path $runDir -Force | Out-Null

if ($Case -eq 'mp3-singles') {
    Assert-Hash $ffprobe 'bf44a50347aaba3e433c34c8c881d67eeaca41001577482ce3ba69b780824ec7'
    Assert-Hash (Join-Path $ffmpegDir 'ffmpeg.exe') 'fa050630ddf5b7c3303d8dab5e5a42e7023547fb78ec9b90b5be0a4f788a7e66'
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
