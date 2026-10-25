# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$work = [IO.Path]::GetFullPath((Join-Path $root 'work/engine'))
$case = Join-Path $work ('2b-stage-test-' + [guid]::NewGuid().ToString('N'))
if (-not $case.StartsWith($work + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Unsafe test directory'
}
$stage = Join-Path $PSScriptRoot 'stage-windows-engine.ps1'
function Assert-Rejected([scriptblock]$action) {
    try { & $action | Out-Null }
    catch { return }
    throw 'Invalid input was accepted'
}
New-Item -ItemType Directory -Path $case -Force | Out-Null
try {
    $target = Join-Path $case 'resources'
    $missing = Join-Path $case 'missing.exe'
    Assert-Rejected { & $stage -YtDlpPath $missing -Destination $target }
    if (Test-Path -LiteralPath $target) { throw 'Missing input created resources' }

    & $stage -Destination $target | Out-Null
    $original = (Get-FileHash -LiteralPath (Join-Path $target 'yt-dlp.exe') -Algorithm SHA256).Hash

    $bad = Join-Path $case 'bad-yt-dlp.exe'
    Copy-Item -LiteralPath (Join-Path $target 'yt-dlp.exe') -Destination $bad
    [IO.File]::AppendAllText($bad, 'corrupt')
    Assert-Rejected { & $stage -YtDlpPath $bad -Destination $target }
    if ((Get-FileHash -LiteralPath (Join-Path $target 'yt-dlp.exe') -Algorithm SHA256).Hash -ne $original) {
        throw 'Rejected input changed staged resources'
    }
    foreach ($name in @('yt-dlp.exe', 'ffmpeg.exe', 'qjs.exe')) {
        if (-not (Test-Path -LiteralPath (Join-Path $target $name) -PathType Leaf)) {
            throw "Missing staged resource: $name"
        }
    }
    Write-Output 'Windows staging tests passed: missing and mismatched inputs rejected; locked artifacts staged and retained.'
}
finally { Remove-Item -LiteralPath $case -Recurse -Force }
