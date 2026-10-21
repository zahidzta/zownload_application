# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta
param(
    [Parameter(Mandatory = $true)][string]$QuickJsPath,
    [string]$YtDlpPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$packageDir = Join-Path $root 'work/android/0c-05/package'
New-Item -ItemType Directory -Force -Path $packageDir | Out-Null
$quickJsHash = '4db3b8aeba709b4907da59a87f1ab3f94585bae3a95f7b02c946b7732cd20185'
$ytDlpHash = '1fa6733c37ea6fb51c99ad8fe785e7b7e5f3246c9b980230329d4fb72ed8d4d6'

function Assert-Hash([string]$Path, [string]$Expected) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing input: $Path" }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $Expected) { throw "SHA-256 mismatch for $Path (got $actual)" }
}

$quickJs = (Resolve-Path -LiteralPath $QuickJsPath).Path
Assert-Hash $quickJs $quickJsHash
if (-not $YtDlpPath) {
    $YtDlpPath = Join-Path $packageDir 'yt-dlp-2026.08.19'
    if (-not (Test-Path -LiteralPath $YtDlpPath)) {
        Invoke-WebRequest -Uri 'https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.19/yt-dlp' -OutFile $YtDlpPath
    }
}
$ytDlp = (Resolve-Path -LiteralPath $YtDlpPath).Path
Assert-Hash $ytDlp $ytDlpHash

# The official Unix zipapp has an executable prefix; Python's zipfile handles it.
$inspect = @'
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as archive:
    checks = {
        'yt_dlp/version.py': "__version__ = '2026.08.19'",
        'yt_dlp_ejs/_version.py': "__version__ = version = '0.8.0'",
    }
    for name, expected in checks.items():
        if expected not in archive.read(name).decode('utf-8'):
            raise SystemExit('Unexpected version in ' + name)
'@
$inspectScript = Join-Path $packageDir 'inspect_zipapp.py'
Set-Content -LiteralPath $inspectScript -Value $inspect -Encoding UTF8
& python $inspectScript $ytDlp
if ($LASTEXITCODE -ne 0) { throw 'yt-dlp/ejs zipapp version inspection failed.' }

$nativeOutput = Join-Path $root 'work/android/0c-05/jniLibs/arm64-v8a/libqjs.so'
$resourceOutput = Join-Path $root 'work/android/0c-05/res/raw/ytdlp'
New-Item -ItemType Directory -Force (Split-Path $nativeOutput),(Split-Path $resourceOutput) | Out-Null
Copy-Item -LiteralPath $quickJs -Destination $nativeOutput -Force
Copy-Item -LiteralPath $ytDlp -Destination $resourceOutput -Force
Assert-Hash $nativeOutput $quickJsHash
Assert-Hash $resourceOutput $ytDlpHash
Write-Output "QuickJS 2026-06-04 SHA-256: $quickJsHash"
Write-Output "yt-dlp 2026.08.19 / ejs 0.8.0 SHA-256: $ytDlpHash"
Write-Output 'Pinned Android native and raw-resource inputs are ready under work/android/0c-05.'
