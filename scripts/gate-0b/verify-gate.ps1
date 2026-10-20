# Offline Gate 0B checkpoint review. Earlier case verifiers retain the full
# network/media probes; this command checks their committed evidence and the
# pinned local artifacts without redownloading media.
$ErrorActionPreference = 'Stop'

function Assert-Gate([bool]$ok, [string]$message) {
    if (-not $ok) { throw "Gate 0B checkpoint: $message" }
}

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$checkpointPath = Join-Path $root 'docs\gates\evidence\0b\checkpoint.md'
$matrixPath = Join-Path $root 'docs\ytdlp-commands.md'
$gatePath = Join-Path $root 'docs\gates\gate-0b.md'
$statePath = Join-Path $root 'docs\STATE.md'
$noticePath = Join-Path $root 'docs\THIRD-PARTY-NOTICES.md'
foreach ($path in @($checkpointPath, $matrixPath, $gatePath, $statePath, $noticePath)) {
    Assert-Gate (Test-Path -LiteralPath $path -PathType Leaf) "missing $path"
}
$checkpoint = Get-Content -LiteralPath $checkpointPath -Raw -Encoding UTF8
$matrix = Get-Content -LiteralPath $matrixPath -Raw -Encoding UTF8
$gate = Get-Content -LiteralPath $gatePath -Raw -Encoding UTF8
$state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8
$notices = Get-Content -LiteralPath $noticePath -Raw -Encoding UTF8

# Resolve every local checkpoint link, including links back into docs/.
$links = [regex]::Matches($checkpoint, '\[[^\]]+\]\(([^)]+)\)')
Assert-Gate ($links.Count -ge 20) 'checkpoint lacks linked evidence'
foreach ($link in $links) {
    $target = $link.Groups[1].Value.Split('#')[0]
    if ($target -match '^https?://') { continue }
    $path = [IO.Path]::GetFullPath((Join-Path (Split-Path $checkpointPath -Parent) $target))
    Assert-Gate (Test-Path -LiteralPath $path -PathType Leaf) "broken checkpoint link: $target"
}

$cases = @('analyze', 'mp3-singles', 'mp3-playlist', 'mp4', 'aac',
           'metadata', 'resume-progress', 'errors')
foreach ($case in $cases) {
    $evidenceName = "$case.txt"
    Assert-Gate ($checkpoint.Contains("($evidenceName)")) "checkpoint omits $evidenceName"
    Assert-Gate ($matrix.Contains("(gates/evidence/0b/$evidenceName)")) "matrix omits $evidenceName"
}
foreach ($option in @('--no-js-runtimes', '--audio-quality', '--merge-output-format',
                      'Merger+ffmpeg_o:-c:a aac', '--convert-thumbnails jpg',
                      '--continue --part', '--newline', '--progress-template')) {
    Assert-Gate ($matrix.Contains($option)) "matrix omits tested option $option"
}
foreach ($term in @('hlsnative', 'local `file:`', 'already-MP3',
                    'Human listening', 'JS challenge', '--download-sections')) {
    Assert-Gate ($matrix.Contains($term) -or $checkpoint.Contains($term)) "checkpoint omits limit $term"
}
Assert-Gate ($gate.Contains('(evidence/0b/checkpoint.md)')) 'gate file does not link checkpoint'
Assert-Gate ($state -match 'Next task explicitly:') 'STATE.md must name the next task explicitly'
$accepted = $state -match 'Gate 0B accepted by the owner'
if ($accepted) {
    Assert-Gate ($gate -match 'Gate 0B checkpoint accepted by the owner') 'gate file omits owner acceptance'
    Assert-Gate ($state -match 'Next task explicitly:.*0C-00') 'accepted checkpoint must name the Gate 0C planning task'
} else {
    Assert-Gate ($state -match 'Next task explicitly:.*Gate 0B') 'pending checkpoint must name owner review'
}

$targetEvidence = @{
    'quickjs-windows.txt' = 'bec67f8f87fa22958d3ab8be5508088116b8bff90032323d82c94545e1698b83'
    'quickjs-linux.txt' = '50263177cb921024aabc0807a31d71be7fa3c22f0c5824c3c6a2d1cf920f300c'
    'quickjs-macos-x64.txt' = '554102a8a9c0d0c5e24cd138ad7a790f330fd926310c01009265589a446ef90a'
    'quickjs-macos-arm64.txt' = 'fba79a316a53ed58a17709a39c173218f8bc825831094b6033ce0510a713bb43'
    'quickjs-android.txt' = '4db3b8aeba709b4907da59a87f1ab3f94585bae3a95f7b02c946b7732cd20185'
    'ffmpeg-windows.txt' = 'fa050630ddf5b7c3303d8dab5e5a42e7023547fb78ec9b90b5be0a4f788a7e66'
}
foreach ($name in $targetEvidence.Keys) {
    $hash = $targetEvidence[$name]
    $evidencePath = Join-Path (Split-Path $checkpointPath -Parent) $name
    $evidence = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8
    Assert-Gate ($evidence.Contains($hash)) "$name does not contain its output hash"
    Assert-Gate ($checkpoint.Contains($hash)) "checkpoint omits $name output hash"
    Assert-Gate ($notices.Contains($hash)) "notices omit $name output hash"
}

# The redistribution audit includes the signed source checks, Windows binary
# hashes, LGPL flags, codec inventory and notice/source obligations.
$audit = @(& powershell -NoProfile -File (Join-Path $PSScriptRoot 'verify-licenses.ps1') 2>&1)
if ($LASTEXITCODE -ne 0) {
    $audit | Select-Object -Last 50
    throw 'Gate 0B checkpoint: redistribution audit failed'
}
$audit | Select-Object -Last 3
$status = if ($accepted) { 'recorded' } else { 'pending' }
Write-Output "Gate 0B checkpoint evidence passed: $($links.Count) links, $($cases.Count) CLI cases, five QuickJS targets, locked Windows binaries and redistribution audit. Owner acceptance: $status."
