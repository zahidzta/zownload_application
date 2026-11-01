# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta
# Build and stage the hash-locked Windows desktop engine before packaging.
param(
    [string[]]$Destinations = @('src-tauri/resources/windows-engine')
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$toolRoot = Join-Path $root 'work/engine/toolchains'
$toolArchive = Join-Path $toolRoot 'w64devkit-x64-2.10.1.7z.exe'
$toolHash = 'add1edf984ce4d473cfeb7c52e0ab38db73a855bba6c7f564d5e16648eb2896a'
$toolUrl = 'https://github.com/skeeto/w64devkit/releases/download/v2.10.1/w64devkit-x64-2.10.1.7z.exe'

function Assert-Engine([bool]$condition, [string]$message) {
    if (-not $condition) { throw "Windows engine preparation: $message" }
}

function Invoke-CheckedScript([string]$path, [string[]]$arguments) {
    & $path @arguments
}

New-Item -ItemType Directory -Path $toolRoot -Force | Out-Null
if (Test-Path -LiteralPath $toolArchive -PathType Leaf) {
    $actual = (Get-FileHash -LiteralPath $toolArchive -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-Engine ($actual -eq $toolHash) 'the existing w64devkit archive has the wrong SHA-256'
} else {
    $downloadLog = Join-Path $toolRoot 'w64devkit-download.log'
    & curl.exe --fail --location --retry 3 --proto '=https' --proto-redir '=https' --output $toolArchive $toolUrl *> $downloadLog
    if ($LASTEXITCODE -ne 0) {
        Get-Content -LiteralPath $downloadLog -Tail 50
        throw 'Windows engine preparation: w64devkit download failed.'
    }
    $actual = (Get-FileHash -LiteralPath $toolArchive -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-Engine ($actual -eq $toolHash) 'downloaded w64devkit archive SHA-256 mismatch'
}

Invoke-CheckedScript (Join-Path $PSScriptRoot 'gate-0b/fetch-sources.ps1') @()

$gcc = Join-Path $toolRoot 'w64devkit/bin/gcc.exe'
if (-not (Test-Path -LiteralPath $gcc -PathType Leaf)) {
    & $toolArchive -y "-o$toolRoot"
    Assert-Engine ($LASTEXITCODE -eq 0) 'w64devkit extraction failed'
}

Invoke-CheckedScript (Join-Path $PSScriptRoot 'gate-0b/build-quickjs.ps1') @('-Target', 'windows-x64', '-Verify')
Invoke-CheckedScript (Join-Path $PSScriptRoot 'gate-0b/build-ffmpeg.ps1') @('-Verify')

$stageScript = Join-Path $PSScriptRoot 'gate-2b/stage-windows-engine.ps1'
foreach ($destination in $Destinations) {
    Invoke-CheckedScript $stageScript @('-Destination', $destination)
}

Write-Output "Verified Windows engine staged to $($Destinations.Count) destination(s)."
