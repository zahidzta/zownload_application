# Gate 0B CLI probes. Later tasks add cases to this entrypoint.
param(
    [ValidateSet('analyze')]
    [string]$Case
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$downloadDir = Join-Path $root 'work\engine\downloads'
$runDir = Join-Path $root 'work\engine\cli\analyze'
$ytDlp = Join-Path $downloadDir 'yt-dlp.exe'
$quickJs = Join-Path $root 'work\engine\build\quickjs\windows-x64\qjs.exe'

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
    if (-not $condition) { throw "Analysis shape failed: $message" }
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

if ($Case -ne 'analyze') { throw 'Specify -Case analyze' }

$source = Read-Lock (Join-Path $root 'docs\engine-sources.md') 'source-lock'
$fixtures = Read-Lock (Join-Path $root 'docs\gates\evidence\0b\fixtures.md') 'fixture-lock'
Assert-Hash $ytDlp $source.ytDlp.binaries.windowsX64.sha256
Assert-Hash $quickJs 'bec67f8f87fa22958d3ab8be5508088116b8bff90032323d82c94545e1698b83'
if ($source.ytDlp.ejsVersion -ne $source.ejs.version) { throw 'yt-dlp/EJS source lock mismatch' }

# Recheck fixture availability immediately before interpreting a CLI failure.
& (Join-Path $PSScriptRoot 'verify-fixtures.ps1')
if (-not $?) { throw 'Fixture preflight failed' }
New-Item -ItemType Directory -Path $runDir -Force | Out-Null

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
