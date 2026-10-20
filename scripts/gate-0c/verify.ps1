param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('library-audit')]
    [string]$Case
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

try {
    $root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $audit = Get-Content (Join-Path $root 'docs/gates/evidence/0c/library-audit.md') -Raw
    $sources = Get-Content (Join-Path $root 'docs/engine-sources.md') -Raw
    $commit = 'd725d5c9a18c3a99a13ee0308bf78275dc310760'

    foreach ($heading in @(
        '## JS runtime and yt-dlp/ejs pair',
        '## Update and rollback',
        '## FFmpeg package, native dependencies, and license',
        '## Artifact provenance and further proof',
        '## Foreground-service type for owner decision',
        '## Stop result and documentation consulted'
    )) {
        if (-not $audit.Contains($heading)) { throw "Missing audit section: $heading" }
    }

    foreach ($term in @(
        $commit, '2025.11.12', 'ejs 0.3.1', '2026.08.19',
        '0.8.0', '--js-runtimes', 'TMPDIR', 'GPL-3.0',
        '--enable-gpl', 'libmp3lame.so', 'libx264.so',
        'dataSync', 'onTimeout', '0C-01A'
    )) {
        if (-not $audit.Contains($term)) { throw "Missing audited fact: $term" }
    }

    foreach ($url in @(
        "https://github.com/yausername/youtubedl-android/tree/$commit",
        'https://ffmpeg.org/legal.html',
        'https://developer.android.com/develop/background-work/services/fgs/service-types',
        'https://developer.android.com/develop/background-work/services/fgs/timeout'
    )) {
        if (-not $audit.Contains($url)) { throw "Missing primary source: $url" }
    }

    foreach ($hash in @(
        '579b5fb480892b1abc2b218c2089699d52759cc8d7ba256bf876453f0365faef',
        '0a87ffa6cf912b0fe76c1a99b9107f543ee2f247935fae2c71f0822eb7bc5f49'
    )) {
        if (-not $audit.Contains($hash) -or -not $sources.Contains($hash)) {
            throw "Candidate AAR hash does not match source record: $hash"
        }
    }

    if (-not $audit.Contains('**Stop rule invoked.**') -or
        -not $sources.Contains('integration stops for owner architecture/licensing decision 0C-01A')) {
        throw 'The required Android integration stop is not recorded in both documents.'
    }

    Write-Output '0C-01 library-audit: PASS (versioned sources, candidate hashes, hard stop, and owner decision recorded)'
} catch {
    Write-Error "0C-01 library-audit: FAIL: $($_.Exception.Message)"
    exit 1
}
