# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta
param(
    [string]$YtDlpPath = 'work/engine/downloads/yt-dlp.exe',
    [string]$FfmpegPath = 'work/engine/build/ffmpeg/windows-x64/recipe/ffmpeg-8.1.3/ffmpeg.exe',
    [string]$QuickJsPath = 'work/engine/build/quickjs/windows-x64/qjs.exe',
    [string]$Destination = 'src-tauri/resources/windows-engine'
)
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
function Resolve-Input([string]$value) {
    if ([IO.Path]::IsPathRooted($value)) { return [IO.Path]::GetFullPath($value) }
    return [IO.Path]::GetFullPath((Join-Path $root $value))
}
function Assert-Hash([string]$path, [string]$expected) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing locked artifact: $path" }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { throw "SHA-256 mismatch for $path`: $actual" }
}

$artifacts = @(
    @{ Name='yt-dlp.exe'; Source=(Resolve-Input $YtDlpPath); Hash='66674953fe251b89f4d08c5f0e35e0728679bd67ab3d7d05c0562af101dd3e7a' },
    @{ Name='ffmpeg.exe'; Source=(Resolve-Input $FfmpegPath); Hash='fa050630ddf5b7c3303d8dab5e5a42e7023547fb78ec9b90b5be0a4f788a7e66' },
    @{ Name='qjs.exe'; Source=(Resolve-Input $QuickJsPath); Hash='bec67f8f87fa22958d3ab8be5508088116b8bff90032323d82c94545e1698b83' }
)
foreach ($artifact in $artifacts) { Assert-Hash $artifact.Source $artifact.Hash }

$target = Resolve-Input $Destination
$parent = Split-Path $target -Parent
if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}
$temp = Join-Path $parent ('.windows-engine-stage-' + [guid]::NewGuid().ToString('N'))
$backup = Join-Path $parent ('.windows-engine-backup-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    foreach ($artifact in $artifacts) {
        $output = Join-Path $temp $artifact.Name
        Copy-Item -LiteralPath $artifact.Source -Destination $output
        Assert-Hash $output $artifact.Hash
    }
    if (Test-Path -LiteralPath $target) { Move-Item -LiteralPath $target -Destination $backup }
    try { Move-Item -LiteralPath $temp -Destination $target }
    catch {
        if (Test-Path -LiteralPath $backup) { Move-Item -LiteralPath $backup -Destination $target }
        throw
    }
    Write-Output 'Verified Windows resources staged for Tauri:'
    foreach ($artifact in $artifacts) { Write-Output "$($artifact.Name) $($artifact.Hash)" }
}
finally {
    # These paths are newly generated siblings of the configured destination.
    foreach ($path in @($temp, $backup)) {
        if ((Split-Path ([IO.Path]::GetFullPath($path)) -Parent) -ne $parent) { throw 'Unsafe staging cleanup path' }
        if ((Test-Path -LiteralPath $path) -and ($path -ne $backup -or (Test-Path -LiteralPath $target))) {
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }
}
