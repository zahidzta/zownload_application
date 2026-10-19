# Configure, build and inspect the locked LGPL FFmpeg recipe on Windows x64.
param([switch]$CheckConfiguration, [switch]$Verify)

$ErrorActionPreference = 'Stop'
if ($CheckConfiguration -eq $Verify) { throw 'Choose exactly one of -CheckConfiguration or -Verify.' }

function Assert-Recipe([bool]$condition, [string]$message) {
    if (-not $condition) { throw "FFmpeg recipe: $message" }
}

function Assert-Hash([string]$path, [string]$expected) {
    Assert-Recipe (Test-Path -LiteralPath $path -PathType Leaf) "missing input: $path"
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-Recipe ($actual -eq $expected) "SHA-256 mismatch: $path"
}

function To-ShellPath([string]$path) {
    # w64devkit's BusyBox shell accepts /Users/... on the current Windows drive.
    # Omitting the drive also avoids Autoconf splitting C: as a PATH delimiter.
    return ($path -replace '^[A-Za-z]:', '').Replace('\', '/')
}

function Run-Logged([string]$name, [string]$command, [string[]]$arguments) {
    $log = Join-Path $script:recipeRoot "$name.log"
    # Windows PowerShell 5.1 promotes native stderr to a terminating error
    # under Stop, including harmless Make warnings. Use the process exit code.
    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $script:shell -c $command sh @arguments *> $log
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldPreference
    }
    if ($code -ne 0) {
        Get-Content -LiteralPath $log -Tail 50
        throw "FFmpeg recipe: $name failed (exit $code); full log: $log"
    }
}

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$downloads = Join-Path $root 'work\engine\downloads'
$toolRoot = Join-Path $root 'work\engine\toolchains'
$toolBin = Join-Path $toolRoot 'w64devkit\bin'
$shell = Join-Path $toolBin 'sh.exe'
$gcc = Join-Path $toolBin 'gcc.exe'
$make = Join-Path $toolBin 'make.exe'
$buildRoot = Join-Path $root 'work\engine\build\ffmpeg\windows-x64'
$recipeRoot = Join-Path $buildRoot 'recipe'
$sources = @(
    @{ Name = 'ffmpeg-8.1.3.tar.xz'; Dir = 'ffmpeg-8.1.3'; Hash = '7138d28c96d9d3e3af4ee3d8cad72741f8ffb40da90c1112235dea3ecd3178a3' },
    @{ Name = 'lame-3.100.tar.gz'; Dir = 'lame-3.100'; Hash = 'ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e' },
    @{ Name = 'zlib-1.3.2.tar.gz'; Dir = 'zlib-1.3.2'; Hash = 'bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16' }
)

# The existing offline verifier also validates the release signatures and the
# other Gate 0B inputs before any source is extracted or compiled.
& powershell -NoProfile -File (Join-Path $PSScriptRoot 'verify-downloads.ps1')
Assert-Recipe ($LASTEXITCODE -eq 0) 'the source lock verifier failed'
foreach ($source in $sources) { Assert-Hash (Join-Path $downloads $source.Name) $source.Hash }
Assert-Hash (Join-Path $toolRoot 'w64devkit-x64-2.10.1.7z.exe') 'add1edf984ce4d473cfeb7c52e0ab38db73a855bba6c7f564d5e16648eb2896a'
Assert-Hash $gcc 'e47ff11a48f1dd4546a0e5ae14913ea582f0c77a4c9a48ceb35ad8d2880fe27d'
Assert-Hash $make 'd852bcfc0c1903aad10b3f7dfb04dce21d1165666d7301ad9f308a1f8900dc3f'
foreach ($name in @('sh.exe', 'ar.exe', 'ranlib.exe', 'nm.exe', 'strip.exe')) {
    Assert-Recipe (Test-Path -LiteralPath (Join-Path $toolBin $name) -PathType Leaf) "missing tool: $name"
}
$gccVersion = (& $gcc -dumpfullversion).Trim()
$gccTarget = (& $gcc -dumpmachine).Trim()
$makeVersion = (& $make --version | Select-Object -First 1).Trim()
Assert-Recipe ($gccVersion -eq '16.2.0' -and $gccTarget -eq 'x86_64-w64-mingw32') "wrong compiler: $gccVersion $gccTarget"
Assert-Recipe ($makeVersion -eq 'GNU Make 4.4.1') "wrong Make: $makeVersion"

New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
if (Test-Path -LiteralPath $recipeRoot) {
    # Only delete this fixed, ignored recipe directory after checking its
    # resolved parent. Never use a caller-supplied path for recursive cleanup.
    $resolved = (Resolve-Path -LiteralPath $recipeRoot).Path
    $parent = (Resolve-Path -LiteralPath (Split-Path -Parent $resolved)).Path
    Assert-Recipe ($resolved -eq $recipeRoot -and $parent -eq (Resolve-Path -LiteralPath $buildRoot).Path) 'refusing to clean outside the recipe directory'
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
New-Item -ItemType Directory -Path $recipeRoot -Force | Out-Null
foreach ($source in $sources) {
    & tar.exe -xf (Join-Path $downloads $source.Name) -C $recipeRoot
    Assert-Recipe ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath (Join-Path $recipeRoot $source.Dir) -PathType Container)) "cannot extract $($source.Name)"
}

$binPath = To-ShellPath $toolBin
$lameDir = To-ShellPath (Join-Path $recipeRoot 'lame-3.100')
$zlibDir = To-ShellPath (Join-Path $recipeRoot 'zlib-1.3.2')
$ffmpegDir = To-ShellPath (Join-Path $recipeRoot 'ffmpeg-8.1.3')
$depsDir = Join-Path $recipeRoot 'deps'
$depsPath = To-ShellPath $depsDir

$lameOptions = '--build=x86_64-w64-mingw32 --disable-decoder --disable-frontend --disable-shared --enable-static --disable-mp3x --disable-mp3rtp'
$lameTools = 'CC=gcc.exe CFLAGS=-O2 AR=ar.exe RANLIB=ranlib.exe AWK=awk.exe SED=sed.exe GREP=grep.exe EGREP=egrep.exe FGREP=fgrep.exe NM=nm.exe LD=ld.exe OBJDUMP=objdump.exe'
Run-Logged 'lame-configure' ('PATH="$2"; export PATH; cd "$1" && ./configure ' + $lameOptions + ' ' + $lameTools) @($lameDir, $binPath)
$lameConfig = Get-Content -LiteralPath (Join-Path $recipeRoot 'lame-3.100\config.h') -Raw
Assert-Recipe ($lameConfig -match '/\* #undef HAVE_MPGLIB \*/') 'LAME decoder was enabled'
$lameMake = Get-Content -LiteralPath (Join-Path $recipeRoot 'lame-3.100\libmp3lame\Makefile') -Raw
Assert-Recipe ($lameMake -match '(?m)^CFLAGS =\s+-O2\s*$' -and $lameMake -match '(?m)^decoder_ldadd =\s*$') 'LAME flags or decoder linkage changed'
Run-Logged 'lame-build' 'PATH="$2"; export PATH; cd "$1" && make.exe -C libmp3lame -j2' @($lameDir, $binPath)
$lameLib = Join-Path $recipeRoot 'lame-3.100\libmp3lame\.libs\libmp3lame.a'
Assert-Recipe (Test-Path -LiteralPath $lameLib -PathType Leaf) 'LAME static encoder library is missing'
$lameMembers = @(& (Join-Path $toolBin 'ar.exe') t $lameLib)
Assert-Recipe ($LASTEXITCODE -eq 0 -and $lameMembers.Count -gt 0) 'cannot inspect LAME archive'
Assert-Recipe (-not ($lameMembers -match '^(?:decode|dct64|layer[123]|tabinit|interface)\.o$')) 'GPL mpglib decoder object entered LAME archive'

Run-Logged 'zlib-build' 'PATH="$2"; export PATH; cd "$1" && make.exe -f win32/Makefile.gcc libz.a' @($zlibDir, $binPath)
$zlibLib = Join-Path $recipeRoot 'zlib-1.3.2\libz.a'
Assert-Recipe (Test-Path -LiteralPath $zlibLib -PathType Leaf) 'zlib static library is missing'

New-Item -ItemType Directory -Path (Join-Path $depsDir 'include\lame'),(Join-Path $depsDir 'lib') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $recipeRoot 'lame-3.100\include\lame.h') -Destination (Join-Path $depsDir 'include\lame\lame.h')
Copy-Item -LiteralPath $lameLib -Destination (Join-Path $depsDir 'lib\libmp3lame.a')
foreach ($name in @('zlib.h', 'zconf.h')) {
    Copy-Item -LiteralPath (Join-Path $recipeRoot "zlib-1.3.2\$name") -Destination (Join-Path $depsDir "include\$name")
}
Copy-Item -LiteralPath $zlibLib -Destination (Join-Path $depsDir 'lib\libz.a')

$ffmpegOptions = @(
    '--target-os=mingw32', '--arch=x86_64', '--cc=gcc.exe', '--cxx=g++.exe',
    '--ar=ar.exe', '--ranlib=ranlib.exe', '--nm=nm.exe', '--strip=strip.exe',
    '--pkg-config=false', '--disable-autodetect', '--disable-x86asm',
    '--disable-ffplay', '--disable-doc', '--disable-debug',
    '--enable-static', '--disable-shared', '--enable-libmp3lame', '--enable-zlib'
)
Assert-Recipe (-not ($ffmpegOptions -match '^--enable-(?:gpl|nonfree|version3)$')) 'forbidden license option'
$configure = 'PATH="$2"; export PATH; cd "$1" && ./configure ' + ($ffmpegOptions -join ' ') + ' --extra-cflags="-I$3/include" --extra-ldflags="-L$3/lib"'
Run-Logged 'ffmpeg-configure' $configure @($ffmpegDir, $binPath, $depsPath)

$ffmpegSource = Join-Path $recipeRoot 'ffmpeg-8.1.3\configure'
$configMak = Get-Content -LiteralPath (Join-Path $recipeRoot 'ffmpeg-8.1.3\ffbuild\config.mak') -Raw
$configHeader = Get-Content -LiteralPath (Join-Path $recipeRoot 'ffmpeg-8.1.3\config.h') -Raw
$configLog = Get-Content -LiteralPath (Join-Path $recipeRoot 'ffmpeg-configure.log') -Raw
Assert-Recipe ($configHeader -match '(?m)^#define CONFIG_GPL 0\r?$' -and
               $configHeader -match '(?m)^#define CONFIG_NONFREE 0\r?$' -and
               $configHeader -match '(?m)^#define CONFIG_VERSION3 0\r?$') 'FFmpeg license configuration changed'
Assert-Recipe ($configLog -match '(?m)^License: LGPL version 2\.1 or later\r?$') 'FFmpeg did not report LGPL-2.1-or-later'
foreach ($feature in @(
    'LIBMP3LAME', 'LIBMP3LAME_ENCODER', 'ZLIB', 'AAC_ENCODER',
    'PNG_DECODER', 'MJPEG_ENCODER', 'SCALE_FILTER', 'SWSCALE',
    'MP3_MUXER', 'MOV_MUXER', 'MP4_MUXER', 'FFMPEG', 'FFPROBE'
)) {
    Assert-Recipe ($configMak -match "(?m)^CONFIG_${feature}=yes\r?$") "required FFmpeg feature is disabled: $feature"
}

# Read FFmpeg's own external-library lists from the hash-verified configure
# source. Only LAME and zlib may be enabled; future configure defaults cannot
# silently pull another external library into this redistribution recipe.
$external = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$inList = $false
foreach ($line in Get-Content -LiteralPath $ffmpegSource) {
    if ($line -match '^EXTERNAL_[A-Z0-9_]*LIBRARY[A-Z0-9_]*_LIST="$') { $inList = $true; continue }
    if ($inList -and $line -eq '"') { $inList = $false; continue }
    if ($inList -and $line -match '^\s+([a-z0-9_]+)\s*$') { [void]$external.Add($Matches[1]) }
}
Assert-Recipe ($external.Contains('libmp3lame') -and $external.Contains('zlib')) 'cannot audit upstream external-library lists'
$enabledExternal = @()
foreach ($name in $external) {
    $key = $name.ToUpperInvariant()
    if ($configMak -match "(?m)^CONFIG_${key}=yes\r?$") { $enabledExternal += $name }
}
$unexpected = @($enabledExternal | Where-Object { $_ -notin @('libmp3lame', 'zlib') })
Assert-Recipe ($unexpected.Count -eq 0) "unapproved external libraries enabled: $($unexpected -join ', ')"

Write-Output "Compiler: GCC $gccVersion ($gccTarget); $makeVersion"
Write-Output "LAME: 3.100, decoder disabled, static libmp3lame.a SHA-256 $((Get-FileHash -LiteralPath $lameLib -Algorithm SHA256).Hash.ToLowerInvariant())"
Write-Output "zlib: 1.3.2, static libz.a SHA-256 $((Get-FileHash -LiteralPath $zlibLib -Algorithm SHA256).Hash.ToLowerInvariant())"
Write-Output "FFmpeg configure: ./configure $($ffmpegOptions -join ' ') --extra-cflags=-I$depsPath/include --extra-ldflags=-L$depsPath/lib"
Write-Output "Enabled external libraries: $(($enabledExternal | Sort-Object) -join ', ')"
Write-Output 'License: LGPL version 2.1 or later (configured)'
Write-Output "Configuration log: $(Join-Path $recipeRoot 'ffmpeg-configure.log')"

if ($CheckConfiguration) { return }

# Use the generated Makefile and the same pinned tools used by configure.
# Keep complete compiler output in the ignored recipe directory.
Run-Logged 'ffmpeg-build' 'PATH="$2"; export PATH; cd "$1" && make.exe -j2 V=1 ffmpeg.exe ffprobe.exe' @($ffmpegDir, $binPath)
$ffmpegExe = Join-Path $recipeRoot 'ffmpeg-8.1.3\ffmpeg.exe'
$ffprobeExe = Join-Path $recipeRoot 'ffmpeg-8.1.3\ffprobe.exe'
foreach ($exe in @($ffmpegExe, $ffprobeExe)) {
    Assert-Recipe (Test-Path -LiteralPath $exe -PathType Leaf) "built executable is missing: $exe"
}

$ffmpegVersion = @(& $ffmpegExe -version)
Assert-Recipe ($LASTEXITCODE -eq 0 -and $ffmpegVersion[0] -match '^ffmpeg version 8\.1\.3(?:\s|$)') 'built ffmpeg version is wrong'
$ffprobeVersion = @(& $ffprobeExe -version)
Assert-Recipe ($LASTEXITCODE -eq 0 -and $ffprobeVersion[0] -match '^ffprobe version 8\.1\.3(?:\s|$)') 'built ffprobe version is wrong'

foreach ($exe in @($ffmpegExe, $ffprobeExe)) {
    $license = @(& $exe -L) -join "`n"
    Assert-Recipe ($LASTEXITCODE -eq 0 -and $license -match 'GNU Lesser General Public\s+License' -and
                   $license -match 'version 2\.1') "built binary did not report LGPL-2.1-or-later: $exe"
    $buildconf = @(& $exe -buildconf) -join "`n"
    Assert-Recipe ($LASTEXITCODE -eq 0 -and $buildconf -match '--enable-libmp3lame' -and
                   $buildconf -match '--enable-zlib' -and
                   $buildconf -notmatch '--enable-(?:gpl|nonfree|version3)(?:\s|$)') "built binary has unexpected configuration: $exe"
}

$encoders = @(& $ffmpegExe -hide_banner -encoders) -join "`n"
$decoders = @(& $ffmpegExe -hide_banner -decoders) -join "`n"
$muxers = @(& $ffmpegExe -hide_banner -muxers) -join "`n"
$filters = @(& $ffmpegExe -hide_banner -filters) -join "`n"
Assert-Recipe ($encoders -match '(?m)^\s*A\S*\s+libmp3lame\s' -and
               $encoders -match '(?m)^\s*A\S*\s+aac\s' -and
               $encoders -match '(?m)^\s*V\S*\s+mjpeg\s') 'MP3, AAC or JPEG encoder is missing'
Assert-Recipe ($decoders -match '(?m)^\s*V\S*\s+png\s') 'PNG decoder is missing'
foreach ($muxer in @('mp3', 'mov', 'mp4')) {
    Assert-Recipe ($muxers -match "(?m)^\s*E\s+$muxer\s") "muxer is missing: $muxer"
}
Assert-Recipe ($filters -match '(?m)^\s*\.\.\S*\s+scale\s') 'scale filter is missing'

# A short encode proves that the configured codecs also work at runtime.
Run-Logged 'smoke-mp3' 'PATH="$2"; export PATH; cd "$1" && ./ffmpeg.exe -nostdin -hide_banner -loglevel error -f lavfi -i sine=frequency=440:duration=1 -c:a libmp3lame -b:a 128k -y smoke.mp3' @($ffmpegDir, $binPath)
Run-Logged 'smoke-mp4' 'PATH="$2"; export PATH; cd "$1" && ./ffmpeg.exe -nostdin -hide_banner -loglevel error -f lavfi -i testsrc2=size=160x90:rate=1:duration=1 -f lavfi -i sine=frequency=440:duration=1 -c:v mpeg4 -c:a aac -shortest -y smoke.mp4' @($ffmpegDir, $binPath)
$mp3Streams = @(& $ffprobeExe -v error -show_entries stream=codec_name -of csv=p=0 (Join-Path $recipeRoot 'ffmpeg-8.1.3\smoke.mp3'))
Assert-Recipe ($LASTEXITCODE -eq 0 -and $mp3Streams -contains 'mp3') 'MP3 smoke output did not probe as MP3'
$mp4Streams = @(& $ffprobeExe -v error -show_entries stream=codec_name -of csv=p=0 (Join-Path $recipeRoot 'ffmpeg-8.1.3\smoke.mp4'))
Assert-Recipe ($LASTEXITCODE -eq 0 -and $mp4Streams -contains 'aac' -and $mp4Streams -contains 'mpeg4') 'MP4 smoke output lacks MPEG-4 video or AAC audio'

# PE imports reveal runtime DLL dependencies. The static LAME/zlib libraries
# must not turn into untracked DLL requirements.
$objdump = Join-Path $toolBin 'objdump.exe'
Assert-Recipe (Test-Path -LiteralPath $objdump -PathType Leaf) 'objdump.exe is missing'
foreach ($exe in @($ffmpegExe, $ffprobeExe)) {
    $imports = @(& $objdump -p $exe | Select-String -Pattern '^\s*DLL Name:\s*(\S+)' | ForEach-Object { $_.Matches[0].Groups[1].Value } | Sort-Object -Unique)
    Assert-Recipe ($LASTEXITCODE -eq 0 -and $imports.Count -gt 0) "cannot inspect PE imports: $exe"
    Assert-Recipe (-not ($imports -match '(?i)^(?:libmp3lame|zlib|libz).*\.dll$')) "unexpected LAME/zlib DLL import: $exe"
    Write-Output "$(Split-Path -Leaf $exe) SHA-256 $((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()); bytes $((Get-Item -LiteralPath $exe).Length)"
    Write-Output "$(Split-Path -Leaf $exe) PE imports: $(($imports) -join ', ')"
}
Write-Output $ffmpegVersion[0]
Write-Output $ffprobeVersion[0]
Write-Output 'Binary license: LGPL version 2.1 or later; GPL/nonfree/version3 options absent'
Write-Output 'Capabilities: libmp3lame MP3, native AAC, MJPEG encode; PNG decode; MP3/MOV/MP4 mux; scale filter'
Write-Output "Smoke probes: MP3=$($mp3Streams -join ','); MP4=$($mp4Streams -join ',')"
Write-Output "Build log: $(Join-Path $recipeRoot 'ffmpeg-build.log')"
