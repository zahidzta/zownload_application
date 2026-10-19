# Builds the locked upstream QuickJS source with the pinned Windows toolchain.
# -CheckEnvironment checks inputs and tools only; compilation belongs to 0B-05.
param(
    [ValidateSet('windows-x64')][string]$Target = 'windows-x64',
    [switch]$CheckEnvironment,
    [switch]$Verify
)

$ErrorActionPreference = 'Stop'
if ($CheckEnvironment -and $Verify) { throw 'Choose either -CheckEnvironment or -Verify.' }

function Assert-QuickJS([bool]$condition, [string]$message) {
    if (-not $condition) { throw "QuickJS Windows build: $message" }
}

function Read-ToolLine([string]$path, [string[]]$arguments) {
    $lines = @(& $path @arguments 2>&1)
    Assert-QuickJS ($LASTEXITCODE -eq 0 -and $lines.Count -gt 0) "$path failed"
    return [string]$lines[0]
}

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$sourceArchive = Join-Path $root 'work\engine\downloads\quickjs-2026-06-04.tar.xz'
$toolArchive = Join-Path $root 'work\engine\toolchains\w64devkit-x64-2.10.1.7z.exe'
$toolHome = Join-Path $root 'work\engine\toolchains\w64devkit'
$toolBin = Join-Path $toolHome 'bin'
$gcc = Join-Path $toolBin 'gcc.exe'
$make = Join-Path $toolBin 'make.exe'
$buildRoot = Join-Path $root 'work\engine\build\quickjs\windows-x64'
$sourceDir = Join-Path $buildRoot 'quickjs-2026-06-04'
$output = Join-Path $buildRoot 'qjs.exe'
$log = Join-Path $buildRoot 'build.log'
$sourceSha256 = 'b376e839b322978313d929fd20663b11ba58b75df5a46c126dd19ea2fa70ad2a'
$toolSha256 = 'add1edf984ce4d473cfeb7c52e0ab38db73a855bba6c7f564d5e16648eb2896a'
$gccSha256 = 'e47ff11a48f1dd4546a0e5ae14913ea582f0c77a4c9a48ceb35ad8d2880fe27d'
$makeSha256 = 'd852bcfc0c1903aad10b3f7dfb04dce21d1165666d7301ad9f308a1f8900dc3f'
$makeFlags = @('CONFIG_WIN32=y', 'CROSS_PREFIX=', 'CONFIG_LTO=', 'CONFIG_TEMPORAL_INTL=y')

Assert-QuickJS (Test-Path -LiteralPath $sourceArchive -PathType Leaf) 'source archive is missing; run fetch-sources.ps1'
Assert-QuickJS ((Get-FileHash -LiteralPath $sourceArchive -Algorithm SHA256).Hash.ToLowerInvariant() -eq $sourceSha256) 'source archive SHA-256 mismatch'
Assert-QuickJS (Test-Path -LiteralPath $toolArchive -PathType Leaf) 'pinned w64devkit archive is missing; follow docs/engine-builds.md setup'
Assert-QuickJS ((Get-FileHash -LiteralPath $toolArchive -Algorithm SHA256).Hash.ToLowerInvariant() -eq $toolSha256) 'w64devkit archive SHA-256 mismatch'
Assert-QuickJS (Test-Path -LiteralPath $gcc -PathType Leaf) 'pinned GCC is missing; extract w64devkit to the documented path'
Assert-QuickJS (Test-Path -LiteralPath $make -PathType Leaf) 'pinned GNU Make is missing; extract w64devkit to the documented path'
Assert-QuickJS ((Get-FileHash -LiteralPath $gcc -Algorithm SHA256).Hash.ToLowerInvariant() -eq $gccSha256) 'extracted GCC SHA-256 mismatch'
Assert-QuickJS ((Get-FileHash -LiteralPath $make -Algorithm SHA256).Hash.ToLowerInvariant() -eq $makeSha256) 'extracted GNU Make SHA-256 mismatch'

$gccVersion = (Read-ToolLine $gcc @('-dumpfullversion')).Trim()
$gccTarget = (Read-ToolLine $gcc @('-dumpmachine')).Trim()
$makeVersion = (Read-ToolLine $make @('--version')).Trim()
Assert-QuickJS ($gccVersion -eq '16.2.0') "expected GCC 16.2.0, found $gccVersion"
Assert-QuickJS ($gccTarget -eq 'x86_64-w64-mingw32') "expected x86_64-w64-mingw32, found $gccTarget"
Assert-QuickJS ($makeVersion -eq 'GNU Make 4.4.1') "expected GNU Make 4.4.1, found $makeVersion"
foreach ($name in @('sh.exe', 'cat.exe', 'mkdir.exe', 'ar.exe')) {
    Assert-QuickJS (Test-Path -LiteralPath (Join-Path $toolBin $name) -PathType Leaf) "missing build tool $name"
}

# The archive hash pins the upstream Makefile and VERSION. Check that the
# extracted metadata still identifies the release before invoking Make.
$versionText = @(& tar.exe -xOf $sourceArchive 'quickjs-2026-06-04/VERSION' 2>&1)
Assert-QuickJS ($LASTEXITCODE -eq 0 -and $versionText.Count -eq 1 -and $versionText[0].Trim() -eq '2026-06-04') 'source VERSION is not 2026-06-04'
$makefileText = @(& tar.exe -xOf $sourceArchive 'quickjs-2026-06-04/Makefile' 2>&1) -join "`n"
Assert-QuickJS ($LASTEXITCODE -eq 0) 'could not read upstream Makefile'
foreach ($pattern in @('CFLAGS\+=-fwrapv', 'CFLAGS_OPT=\$\(CFLAGS\) -O2', 'DEFINES\+=-D__USE_MINGW_ANSI_STDIO', 'LIBS=-lm -lpthread', 'qjs\$\(EXE\):')) {
    Assert-QuickJS ($makefileText -match $pattern) "upstream Makefile no longer has expected build flag or target: $pattern"
}

Write-Output "Source SHA-256: $sourceSha256"
Write-Output "Toolchain archive SHA-256: $toolSha256"
Write-Output "Compiler: GCC $gccVersion ($gccTarget)"
Write-Output "Build tool: $makeVersion"
Write-Output "Make flags: $($makeFlags -join ' ') qjs.exe"
Write-Output "Output: $output"
if ($CheckEnvironment) { return }

New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
if (Test-Path -LiteralPath $sourceDir) {
    # Keep recursive cleanup confined to this task's fixed build directory.
    $resolvedSource = (Resolve-Path -LiteralPath $sourceDir).Path
    $resolvedBuild = (Resolve-Path -LiteralPath $buildRoot).Path
    Assert-QuickJS ($resolvedSource -eq (Join-Path $resolvedBuild 'quickjs-2026-06-04')) 'refusing to remove source outside build directory'
    Remove-Item -LiteralPath $resolvedSource -Recurse -Force
}
& tar.exe -xf $sourceArchive -C $buildRoot
Assert-QuickJS ($LASTEXITCODE -eq 0) 'source extraction failed'
Assert-QuickJS (Test-Path -LiteralPath (Join-Path $sourceDir 'Makefile') -PathType Leaf) 'upstream Makefile is missing after extraction'

$oldPath = $env:PATH
try {
    # Force Make to find the pinned GCC, ar and BusyBox utilities first.
    $env:PATH = "$toolBin;$oldPath"
    & $make -C $sourceDir @makeFlags qjs.exe *> $log
    if ($LASTEXITCODE -ne 0) {
        Get-Content -LiteralPath $log -Tail 50
        throw "QuickJS Windows build: make failed (exit $LASTEXITCODE); full log: $log"
    }
} finally {
    $env:PATH = $oldPath
}

$built = Join-Path $sourceDir 'qjs.exe'
Assert-QuickJS (Test-Path -LiteralPath $built -PathType Leaf) 'make did not produce qjs.exe'
Copy-Item -LiteralPath $built -Destination $output -Force
Write-Output "Built SHA-256: $((Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant())"
if ($Verify) {
    $smoke = @(& $output -e 'print(1 + 1)' 2>&1)
    Assert-QuickJS ($LASTEXITCODE -eq 0 -and $smoke.Count -eq 1 -and [string]$smoke[0] -eq '2') "qjs smoke test failed: $($smoke -join ' ')"
    Write-Output 'qjs smoke test: 2'
}
