# Gate 0B CLI probes. Later tasks add cases to this entrypoint.
param(
    [ValidateSet('analyze', 'mp3-singles', 'mp3-playlist', 'mp4', 'aac', 'metadata', 'resume-progress', 'errors')]
    [string]$Case
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$downloadDir = Join-Path $root 'work\engine\downloads'
$runDir = if ($Case -in @('mp3-singles', 'mp3-playlist', 'mp4', 'aac', 'metadata', 'resume-progress', 'errors')) {
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

function New-EngineStartInfo([string]$name, [string[]]$arguments) {
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
    return $start
}

function Invoke-Engine([string]$name, [string[]]$arguments, [int]$timeoutSeconds, [bool]$allowFailure = $false) {
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = New-EngineStartInfo $name $arguments
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
        if ($process.ExitCode -ne 0 -and -not $allowFailure) { throw "$name exited $($process.ExitCode); see $runDir" }
        return [pscustomobject]@{ Stdout = $stdout; Stderr = $stderr; Seconds = $clock.Elapsed.TotalSeconds; ExitCode = $process.ExitCode }
    }
    finally { $process.Dispose() }
}

function Invoke-StartupProbe([string]$name, [string]$fileName, [string[]]$arguments, [string]$workingDirectory = '', [int]$timeoutSeconds = 10) {
    $start = New-EngineStartInfo $name $arguments
    $start.FileName = $fileName
    if ($workingDirectory) { $start.WorkingDirectory = $workingDirectory }
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $start
    $clock = [Diagnostics.Stopwatch]::StartNew()
    try {
        try {
            if (-not $process.Start()) { throw "Could not start $fileName" }
        } catch [System.ComponentModel.Win32Exception] {
            $clock.Stop()
            $message = $_.Exception.Message
            $code = $_.Exception.NativeErrorCode
            [IO.File]::WriteAllText((Join-Path $runDir "$name.start-error.txt"), "Win32 error ${code}: $message")
            Write-Host "$name`: start-error=$code elapsed=$([math]::Round($clock.Elapsed.TotalSeconds, 2))s"
            return [pscustomobject]@{ ExitCode = $null; StartError = $message; NativeErrorCode = $code; Stdout = ''; Stderr = ''; Seconds = $clock.Elapsed.TotalSeconds }
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $finished = $process.WaitForExit($timeoutSeconds * 1000)
        if (-not $finished) {
            Stop-EngineChildren $process.Id
            if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit(5000) | Out-Null }
        }
        $readsFinished = [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdoutTask, $stderrTask), 5000)
        $clock.Stop()
        Assert-Shape $readsFinished "$name output pipe remained open"
        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result
        [IO.File]::WriteAllText((Join-Path $runDir "$name.stdout.txt"), $stdout, (New-Object System.Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText((Join-Path $runDir "$name.stderr.txt"), $stderr, (New-Object System.Text.UTF8Encoding($false)))
        $status = if ($finished) { $process.ExitCode } else { 'timeout' }
        Write-Host "$name`: exit=$status elapsed=$([math]::Round($clock.Elapsed.TotalSeconds, 2))s"
        return [pscustomobject]@{ ExitCode = $status; StartError = $null; NativeErrorCode = $null; Stdout = $stdout; Stderr = $stderr; Seconds = $clock.Elapsed.TotalSeconds }
    } finally { $process.Dispose() }
}

function Assert-CliError($result, [string]$name, [string]$pattern) {
    Assert-Runtime $result $name
    Assert-Shape ($result.ExitCode -eq 1) "$name did not exit 1"
    Assert-Shape ($result.Stdout.Trim() -eq 'null') "$name did not write the expected null JSON sentinel"
    $lines = [regex]::Matches($result.Stderr, '(?m)^ERROR: .+\r?$')
    Assert-Shape ($lines.Count -eq 1 -and $lines[0].Value -match $pattern) "$name has an unexpected ERROR line"
    Write-Output "$name`: exit=$($result.ExitCode) stderr=$($lines[0].Value.Trim())"
}

function Invoke-InterruptedEngine([string]$name, [string[]]$arguments, [string]$partPath, [int]$minimumBytes, [int]$timeoutSeconds) {
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = New-EngineStartInfo $name $arguments
    $clock = [Diagnostics.Stopwatch]::StartNew()
    try {
        if (-not $process.Start()) { throw "Could not start $ytDlp" }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        while ($clock.Elapsed.TotalSeconds -lt $timeoutSeconds) {
            if ($process.HasExited) { throw "$name finished before a partial file could be interrupted; see $runDir" }
            if ((Test-Path -LiteralPath $partPath -PathType Leaf) -and
                (Get-Item -LiteralPath $partPath).Length -ge $minimumBytes) { break }
            Start-Sleep -Milliseconds 200
        }
        if ($clock.Elapsed.TotalSeconds -ge $timeoutSeconds) { throw "$name did not produce $minimumBytes partial bytes within $timeoutSeconds seconds" }
        Stop-EngineChildren $process.Id
        if (-not $process.HasExited) { $process.Kill() }
        $process.WaitForExit(5000) | Out-Null
        Assert-Shape ([Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdoutTask, $stderrTask), 5000)) "$name output pipes remained open"
        [IO.File]::WriteAllText((Join-Path $runDir "$name.stdout.txt"), $stdoutTask.Result, (New-Object System.Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText((Join-Path $runDir "$name.stderr.txt"), $stderrTask.Result, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "$name`: interrupted after $([math]::Round($clock.Elapsed.TotalSeconds, 2))s, exit=$($process.ExitCode)"
        return [pscustomobject]@{ Stdout = $stdoutTask.Result; Stderr = $stderrTask.Result; ExitCode = $process.ExitCode }
    }
    finally {
        if (-not $process.HasExited) {
            Stop-EngineChildren $process.Id
            $process.Kill()
            $process.WaitForExit(5000) | Out-Null
        }
        $process.Dispose()
    }
}

function Read-ProgressLines([string]$stdout, [string]$name, [string]$expectedId) {
    $lines = @($stdout -split '\r?\n' | Where-Object { $_ -like 'ZP1|*' })
    Assert-Shape ($lines.Count -gt 0) "$name has no templated progress lines"
    $parsed = @()
    foreach ($line in $lines) {
        Assert-Shape ($line -match '^ZP1\|(?<id>[A-Za-z0-9_-]+)\|(?<status>downloading|finished)\|(?<downloaded>\d+)\|(?<total>\d+)\r?$') "$name has an unparseable progress line: $line"
        Assert-Shape ($Matches.id -eq $expectedId) "$name progress names the wrong item"
        $parsed += [pscustomobject]@{ Status = $Matches.status; Downloaded = [int64]$Matches.downloaded; Total = [int64]$Matches.total }
    }
    return $parsed
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

if (-not $Case) { throw 'Specify -Case analyze, mp3-singles, mp3-playlist, mp4, aac, metadata, resume-progress or errors' }

$source = Read-Lock (Join-Path $root 'docs\engine-sources.md') 'source-lock'
$fixtures = Read-Lock (Join-Path $root 'docs\gates\evidence\0b\fixtures.md') 'fixture-lock'
Assert-Hash $ytDlp $source.ytDlp.binaries.windowsX64.sha256
Assert-Hash $quickJs 'bec67f8f87fa22958d3ab8be5508088116b8bff90032323d82c94545e1698b83'
if ($source.ytDlp.ejsVersion -ne $source.ejs.version) { throw 'yt-dlp/EJS source lock mismatch' }

# Recheck fixture availability immediately before interpreting a CLI failure.
& (Join-Path $PSScriptRoot 'verify-fixtures.ps1')
if (-not $?) { throw 'Fixture preflight failed' }
New-Item -ItemType Directory -Path $runDir -Force | Out-Null

if ($Case -in @('mp3-singles', 'mp3-playlist', 'mp4', 'aac', 'metadata', 'resume-progress')) {
    Assert-Hash $ffprobe 'bf44a50347aaba3e433c34c8c881d67eeaca41001577482ce3ba69b780824ec7'
    Assert-Hash (Join-Path $ffmpegDir 'ffmpeg.exe') 'fa050630ddf5b7c3303d8dab5e5a42e7023547fb78ec9b90b5be0a4f788a7e66'
}

if ($Case -eq 'errors') {
    $common = @('--ignore-config', '--verbose', '--no-js-runtimes', '--js-runtimes', "quickjs:$quickJs",
        '--skip-download', '--dump-single-json', '--no-playlist', '--socket-timeout', '15',
        '--retries', '0', '--extractor-retries', '0')
    $invalid = Invoke-Engine 'invalid-url' ($common + @('--', $fixtures.invalidInput)) 60 $true
    Assert-CliError $invalid 'invalid-url' ([regex]::Escape("'$($fixtures.invalidInput)' is not a valid URL"))

    $missingUrl = "https://archive.org/details/$($fixtures.missingArchiveId)"
    $missing = Invoke-Engine 'unavailable-item' ($common + @('--', $missingUrl)) 60 $true
    Assert-CliError $missing 'unavailable-item' 'HTTP Error 404: Not Found'

    $privatePath = (($fixtures.restrictedArchive.privateFile -split '/') |
        ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
    $privateUrl = "https://archive.org/download/$($fixtures.restrictedArchive.id)/$privatePath"
    $restricted = Invoke-Engine 'private-file' ($common + @('--', $privateUrl)) 60 $true
    Assert-CliError $restricted 'private-file' 'HTTP Error (401: Unauthorized|403: Forbidden)'

    $ytStartup = Invoke-StartupProbe 'yt-dlp-startup' $ytDlp @('--version')
    Assert-Shape ($ytStartup.ExitCode -eq 0 -and $ytStartup.Stdout.Trim() -eq '2026.08.19' -and
        $ytStartup.Seconds -lt 10) 'pinned yt-dlp did not start within 10 seconds'
    $qjsStartup = Invoke-StartupProbe 'quickjs-startup' $quickJs @('-e', "print('quickjs-ready')")
    Assert-Shape ($qjsStartup.ExitCode -eq 0 -and $qjsStartup.Stdout.Trim() -eq 'quickjs-ready' -and
        $qjsStartup.Seconds -lt 10) 'pinned QuickJS did not start within 10 seconds'

    # An absent working directory forces Windows to reject Process.Start before
    # either verified executable can emit stderr or return a process exit code.
    $badDirectory = Join-Path $runDir 'intentionally-absent-working-directory'
    Assert-Shape (-not (Test-Path -LiteralPath $badDirectory)) 'startup-failure directory unexpectedly exists'
    foreach ($probe in @(@('yt-dlp', $ytDlp, @('--version')), @('quickjs', $quickJs, @('-e', '1')))) {
        $failed = Invoke-StartupProbe "$($probe[0])-start-failure" $probe[1] $probe[2] $badDirectory
        Assert-Shape ($null -eq $failed.ExitCode -and $failed.NativeErrorCode -eq 267 -and
            -not $failed.Stderr -and -not $failed.Stdout) "$($probe[0]) startup failure did not report Win32 error 267 without CLI output"
        Write-Output "$($probe[0]) simulated startup failure: Win32=$($failed.NativeErrorCode), no exit code or stderr"
    }
    $stalled = Invoke-StartupProbe 'quickjs-watchdog' $quickJs @('-e', 'for (;;) {}') '' 2
    Assert-Shape ($stalled.ExitCode -eq 'timeout' -and -not $stalled.Stdout -and -not $stalled.Stderr) 'nonresponsive QuickJS was not stopped at the probe deadline'
    Write-Output "QuickJS simulated no-response timeout: status=$($stalled.ExitCode), stopped after $([math]::Round($stalled.Seconds, 2))s"
    Write-Output "Startup success: yt-dlp=$([math]::Round($ytStartup.Seconds, 2))s QuickJS=$([math]::Round($qjsStartup.Seconds, 2))s (10s bound)"
    Write-Output "Full stdout/stderr and startup error details: $runDir (ignored)"
    return
}

if ($Case -eq 'resume-progress') {
    $fixture = $fixtures.archiveVideo
    $common = @('--ignore-config', '--verbose', '--no-js-runtimes', '--js-runtimes', "quickjs:$quickJs", '--no-playlist')
    $selector = 'best[height<=240]'
    $selected = Invoke-Engine 'selection' ($common + @('--skip-download', '-f', $selector,
        '--print', '%(id)s|%(format_id)s|%(ext)s|%(protocol)s|%(duration)s', '--', $fixture.url)) 180
    Assert-Runtime $selected 'selection'
    $fields = $selected.Stdout.Trim() -split '\|'
    Assert-Shape ($fields.Count -eq 5 -and $fields[0] -eq $fixture.id -and $fields[2] -eq 'mp4' -and
        $fields[3] -eq 'https' -and [double]$fields[4] -ge 110) 'resume fixture no longer selects a direct MP4'
    $output = Join-Path $runDir 'resume.mp4'
    $part = "$output.part"
    $template = 'download:ZP1|%(info.id)s|%(progress.status)s|%(progress.downloaded_bytes|0)d|%(progress.total_bytes,progress.total_bytes_estimate|0)d'
    $options = @('-f', $selector, '--continue', '--part', '--newline', '--progress-template', $template,
        '-o', (Join-Path $runDir 'resume.%(ext)s'))
    $interrupted = Invoke-InterruptedEngine 'interrupted' ($common + $options + @('--limit-rate', '64K', '--', $fixture.url)) $part 131072 180
    Assert-Runtime $interrupted 'interrupted'
    Assert-Shape ((Test-Path -LiteralPath $part -PathType Leaf) -and -not (Test-Path -LiteralPath $output)) 'interruption did not leave only a .part file'
    $partial = [IO.File]::ReadAllBytes($part)
    Assert-Shape ($partial.Length -ge 131072) 'interrupted partial file is too small'
    $initialProgress = @(Read-ProgressLines $interrupted.Stdout 'interrupted' $fixture.id)
    Assert-Shape (@($initialProgress | Where-Object Status -eq 'downloading').Count -gt 0) 'interrupted download did not report progress'
    Assert-Shape ($interrupted.Stderr -notmatch '(?m)^ERROR:|^ZP1\|') 'interrupted download stderr contains an error or progress line'

    $resumed = Invoke-Engine 'resumed' ($common + $options + @('--', $fixture.url)) 300
    Assert-Runtime $resumed 'resumed'
    Assert-Shape ($resumed.Stdout -match 'Resuming download at byte ([0-9]+)') 'yt-dlp did not report reusing partial bytes'
    $resumeOffset = [int64]$Matches[1]
    Assert-Shape ($resumeOffset -ge 131072 -and $resumeOffset -le $partial.Length) 'reported resume offset disagrees with saved partial file'
    $resumeProgress = @(Read-ProgressLines $resumed.Stdout 'resumed' $fixture.id)
    Assert-Shape (@($resumeProgress | Where-Object Status -eq 'downloading').Count -gt 0 -and
        @($resumeProgress | Where-Object Status -eq 'finished').Count -gt 0) 'resumed download lacks download/finish progress events'
    Assert-Shape (@($resumeProgress | Where-Object { $_.Downloaded -ge $resumeOffset }).Count -gt 0) 'progress bytes never reached the resume offset'
    Assert-Shape ($resumed.Stdout -match '(?m)^\[download\] Destination: ' -and $resumed.Stderr -match '(?m)^\[debug\] ') 'normal output or diagnostics were lost'
    Assert-Shape ($resumed.Stderr -notmatch '(?m)^ZP1\||^ERROR:') 'resumed stderr contains progress or an error'
    Assert-Shape ((Test-Path -LiteralPath $output -PathType Leaf) -and -not (Test-Path -LiteralPath $part)) 'resume did not finalize the MP4'
    $complete = [IO.File]::OpenRead($output)
    try {
        Assert-Shape ($complete.Length -gt $partial.Length) 'completed file did not grow beyond the partial file'
        $finalLength = $complete.Length
        $prefix = New-Object byte[] $partial.Length
        $readCount = 0
        while ($readCount -lt $prefix.Length) {
            $count = $complete.Read($prefix, $readCount, $prefix.Length - $readCount)
            Assert-Shape ($count -gt 0) 'could not read completed prefix'
            $readCount += $count
        }
        $sha = [Security.Cryptography.SHA256]::Create()
        try {
            $partialHash = [BitConverter]::ToString($sha.ComputeHash($partial)).Replace('-', '').ToLowerInvariant()
            $prefixHash = [BitConverter]::ToString($sha.ComputeHash($prefix)).Replace('-', '').ToLowerInvariant()
        } finally { $sha.Dispose() }
        Assert-Shape ($partialHash -eq $prefixHash) 'completed file does not retain the saved partial bytes'
    } finally { $complete.Dispose() }
    Assert-Mp4 $output 'resume' 360 240 120
    $errorProbe = Invoke-Engine 'invalid-with-template' ($common + @('--newline', '--progress-template', $template,
        '--', $fixtures.invalidInput)) 60 $true
    Assert-Shape ($errorProbe.ExitCode -ne 0 -and $errorProbe.Stderr -match '(?m)^ERROR: ' -and
        $errorProbe.Stdout -notmatch '(?m)^ZP1\|') 'progress options masked or corrupted a CLI error'
    Write-Output "resume: format=$($fields[1]) interrupted=$($partial.Length) bytes offset=$resumeOffset bytes progress=$($initialProgress.Count)+$($resumeProgress.Count) lines"
    Write-Output "partial-prefix sha256=$partialHash final bytes=$finalLength sha256=$((Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant())"
    Write-Output "invalid input with progress options: exit=$($errorProbe.ExitCode), ERROR line retained on stderr"
    Write-Output "Full stdout/stderr, ffprobe JSON and MP4 output: $runDir (ignored)"
    return
}

if ($Case -eq 'metadata') {
    $ffmpeg = Join-Path $ffmpegDir 'ffmpeg.exe'
    $common = @('--ignore-config', '--verbose', '--no-js-runtimes', '--js-runtimes', "quickjs:$quickJs")
    $albumRule = '%(playlist_title|)s:%(meta_album)s'
    $artistRule = '%(artist,creator,uploader|)s:%(meta_artist)s'

    # Archive's playlist exposes a PNG per track, but its yt-dlp entry has no
    # thumbnail field. Verify the field is absent before using the locked image.
    $archive = $fixtures.archiveAudio
    $archiveInfoResult = Invoke-Engine 'archive-info' ($common + @('--playlist-items', '2', '--skip-download',
        '--dump-json', '--', $archive.url)) 180
    Assert-Runtime $archiveInfoResult 'archive-info'
    $archiveInfo = $archiveInfoResult.Stdout | ConvertFrom-Json
    Assert-Shape ($archiveInfo.id -eq "$($archive.id)/$($archive.entries[0])" -and
        $archiveInfo.creator -eq $archive.creator -and -not $archiveInfo.artist -and
        $archiveInfo.playlist_title -eq 'Pure Data sound effects by Andy Farnell' -and
        -not $archiveInfo.thumbnail) 'Archive metadata/thumbnail fixture changed'
    $archiveDir = Join-Path $runDir 'archive'
    New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null
    $archiveDownload = Invoke-Engine 'archive-download' ($common + @('--playlist-items', '2', '-f', 'ba/b',
        '-x', '--audio-format', 'mp3', '--embed-metadata', '--parse-metadata', $artistRule,
        '--parse-metadata', $albumRule, '--ffmpeg-location', $ffmpegDir,
        '-o', (Join-Path $archiveDir 'source.%(ext)s'), '--', $archive.url)) 180
    Assert-Runtime $archiveDownload 'archive-download'
    Assert-Shape ($archiveDownload.Stderr -match 'Invoking http downloader on "https://archive.org/download/') 'Archive media was not fetched by yt-dlp HTTP'
    Assert-Shape ($archiveDownload.Stderr -match 'ffmpeg command line:.*-i file:' -and
        $archiveDownload.Stderr -notmatch 'ffmpeg command line:.*-i https?:') 'Archive metadata postprocessor used a network input'
    $archiveSource = Join-Path $archiveDir 'source.mp3'
    Assert-Shape (Test-Path -LiteralPath $archiveSource -PathType Leaf) 'Archive MP3 is missing'

    $pngUrl = "https://archive.org/download/$($archive.id)/$($archive.entries[0] -replace '\.mp3$', '.png')"
    $pngPath = Join-Path $archiveDir 'cover.png'
    Invoke-WebRequest -Uri $pngUrl -OutFile $pngPath -UseBasicParsing -TimeoutSec 90 | Out-Null
    $pngProbe = (& $ffprobe -v error -show_entries 'stream=codec_name,codec_type' -of json -- $pngPath | Out-String) | ConvertFrom-Json
    Assert-Shape ($LASTEXITCODE -eq 0 -and @($pngProbe.streams | Where-Object { $_.codec_name -eq 'png' }).Count -eq 1) 'Archive artwork is not PNG'
    $archiveOutput = Join-Path $archiveDir 'archive-cover.mp3'
    $coverLog = Join-Path $runDir 'archive-cover.ffmpeg.txt'
    $previousErrorAction = $ErrorActionPreference
    try {
        # PowerShell 5.1 promotes a native process's informational stderr to
        # an exception when ErrorActionPreference is Stop.
        $ErrorActionPreference = 'Continue'
        & $ffmpeg -hide_banner -loglevel info -y -i $archiveSource -i $pngPath -map '0:a:0' -map '1:v:0' -c:a copy -c:v mjpeg -q:v 2 -id3v2_version 3 -metadata:s:v title='Album cover' -metadata:s:v comment='Cover (front)' $archiveOutput 2>&1 | Out-File -LiteralPath $coverLog -Encoding utf8
        $coverStatus = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousErrorAction }
    Assert-Shape ($coverStatus -eq 0) 'FFmpeg PNG-to-JPEG cover embedding failed'

    $clip = @($fixtures.natureclipVideoPlaylist.entries | Where-Object { $_.playlistIndex -eq 7 })
    Assert-Shape ($clip.Count -eq 1 -and $clip[0].id -eq 'YC0kTqKbeFs') 'NatureClip metadata fixture changed'
    $videoUrl = "https://www.youtube.com/watch?v=$($clip[0].id)"
    $videoInfoResult = Invoke-Engine 'video-info' ($common + @('--no-playlist', '--skip-download',
        '--dump-single-json', '--', $videoUrl)) 180
    Assert-Runtime $videoInfoResult 'video-info'
    $videoInfo = $videoInfoResult.Stdout | ConvertFrom-Json
    Assert-Shape ($videoInfo.id -eq $clip[0].id -and $videoInfo.title -eq $clip[0].title -and
        -not $videoInfo.artist -and -not $videoInfo.creator -and
        $videoInfo.uploader -eq $fixtures.natureclipVideoPlaylist.uploader -and
        -not $videoInfo.playlist_title -and $videoInfo.thumbnail) 'NatureClip metadata fixture changed'
    $videoDir = Join-Path $runDir 'video'
    New-Item -ItemType Directory -Path $videoDir -Force | Out-Null
    $videoDownload = Invoke-Engine 'video-download' ($common + @('--no-playlist', '-f', 'bv*+ba/b',
        '--merge-output-format', 'mp4', '--postprocessor-args', 'Merger+ffmpeg_o:-c:a aac',
        '--embed-metadata', '--embed-thumbnail', '--convert-thumbnails', 'jpg',
        '--parse-metadata', $artistRule, '--parse-metadata', $albumRule,
        '--ffmpeg-location', $ffmpegDir, '-o', (Join-Path $videoDir 'single.%(ext)s'), '--', $videoUrl)) 300
    Assert-Runtime $videoDownload 'video-download'
    Assert-Shape (@([regex]::Matches($videoDownload.Stderr, 'Invoking http downloader on "https://')).Count -eq 2) 'NatureClip streams were not fetched by yt-dlp HTTP'
    $videoFfmpegLines = @($videoDownload.Stderr -split '\r?\n' | Where-Object { $_ -match '^\[debug\] ffmpeg command line:.*[/\\]ffmpeg(?:\.exe)? ' })
    Assert-Shape ($videoFfmpegLines.Count -ge 2 -and
        @($videoFfmpegLines | Where-Object { $_ -notmatch '-i file:' -or $_ -match '-i https?:' }).Count -eq 0) 'NatureClip FFmpeg used a network input'
    $videoOutput = Join-Path $videoDir 'single.mp4'
    Assert-Shape (Test-Path -LiteralPath $videoOutput -PathType Leaf) 'NatureClip MP4 is missing'

    foreach ($file in @(@{ Name = 'archive'; Path = $archiveOutput; Title = $archiveInfo.title; Artist = $archive.creator; Album = $archiveInfo.playlist_title; Audio = 'mp3' },
            @{ Name = 'video'; Path = $videoOutput; Title = $videoInfo.title; Artist = $videoInfo.uploader; Album = ''; Audio = 'aac' })) {
        $probeText = (& $ffprobe -v error -show_streams -show_format -of json -- $file.Path | Out-String)
        Assert-Shape ($LASTEXITCODE -eq 0) "ffprobe failed for $($file.Name)"
        [IO.File]::WriteAllText((Join-Path $runDir "$($file.Name).ffprobe.json"), $probeText, (New-Object System.Text.UTF8Encoding($false)))
        $probe = $probeText | ConvertFrom-Json
        $audio = @($probe.streams | Where-Object { $_.codec_type -eq 'audio' })
        $covers = @($probe.streams | Where-Object { $_.disposition.attached_pic -eq 1 })
        Assert-Shape ($audio.Count -eq 1 -and $audio[0].codec_name -eq $file.Audio) "$($file.Name) audio changed"
        Assert-Shape ($covers.Count -eq 1 -and $covers[0].codec_name -eq 'mjpeg') "$($file.Name) has no embedded JPEG cover"
        Assert-Shape ($probe.format.tags.title -eq $file.Title -and $probe.format.tags.artist -eq $file.Artist) "$($file.Name) title/artist mapping failed"
        # MP4 omits an empty album tag; that is the intended single-item value.
        $actualAlbum = if ($probe.format.tags.album) { [string]$probe.format.tags.album } else { '' }
        Assert-Shape ($actualAlbum -eq $file.Album) "$($file.Name) album mapping failed"
        $hash = (Get-FileHash -LiteralPath $file.Path -Algorithm SHA256).Hash.ToLowerInvariant()
        Write-Output "$($file.Name): title=$($probe.format.tags.title) artist=$($probe.format.tags.artist) album=$($probe.format.tags.album) cover=$($covers[0].codec_name) bytes=$($probe.format.size) sha256=$hash"
    }
    Write-Output "Archive PNG sha256=$((Get-FileHash -LiteralPath $pngPath -Algorithm SHA256).Hash.ToLowerInvariant())"
    Write-Output "Full stdout/stderr, ffprobe JSON and media: $runDir (ignored)"
    return
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
