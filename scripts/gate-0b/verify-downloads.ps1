# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta
# Checks the locked bytes and detached release signatures without fetching data.
# -FetchMissing is used only by fetch-sources.ps1; the default is offline.
param([switch]$FetchMissing)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$downloadDir = Join-Path $root 'work\engine\downloads'
$evidencePath = Join-Path $root 'docs\gates\evidence\0b\source-hashes.txt'
$sourcePath = Join-Path $root 'docs\engine-sources.md'

function Assert-Download([bool]$condition, [string]$message) {
    if (-not $condition) { throw "Engine download verification failed: $message" }
}

function Get-DownloadUrls([string]$primary, [object[]]$fallbacks) {
    $urls = @($primary)
    foreach ($fallback in @($fallbacks)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$fallback)) { $urls += [string]$fallback }
    }
    return ,$urls
}

$source = Get-Content -LiteralPath $sourcePath -Raw
$blocks = [regex]::Matches($source, '(?s)```json source-lock\r?\n(.*?)\r?\n```')
Assert-Download ($blocks.Count -eq 1) 'expected one source-lock block'
$lock = $blocks[0].Groups[1].Value | ConvertFrom-Json
Assert-Download ($lock.schema -eq 1) 'unexpected source-lock schema'

# All network destinations come from the reviewed source lock. Each name is
# fixed here so a changed URL cannot write to an arbitrary local path.
$items = @(
    [pscustomobject]@{ Name = 'yt-dlp.tar.gz'; Urls = (Get-DownloadUrls $lock.ytDlp.source.url $lock.ytDlp.source.fallbackUrls); Hash = $lock.ytDlp.source.sha256 },
    [pscustomobject]@{ Name = 'SHA2-256SUMS'; Urls = (Get-DownloadUrls $lock.ytDlp.checksumManifest.url $lock.ytDlp.checksumManifest.fallbackUrls); Hash = $lock.ytDlp.checksumManifest.sha256 },
    [pscustomobject]@{ Name = 'SHA2-256SUMS.sig'; Urls = (Get-DownloadUrls $lock.ytDlp.checksumManifest.signatureUrl $lock.ytDlp.checksumManifest.signatureFallbackUrls); Hash = $lock.ytDlp.checksumManifest.signatureSha256 },
    [pscustomobject]@{ Name = 'yt-dlp.exe'; Urls = (Get-DownloadUrls $lock.ytDlp.binaries.windowsX64.url $lock.ytDlp.binaries.windowsX64.fallbackUrls); Hash = $lock.ytDlp.binaries.windowsX64.sha256 },
    [pscustomobject]@{ Name = 'yt-dlp_linux'; Urls = (Get-DownloadUrls $lock.ytDlp.binaries.linuxX64.url $lock.ytDlp.binaries.linuxX64.fallbackUrls); Hash = $lock.ytDlp.binaries.linuxX64.sha256 },
    [pscustomobject]@{ Name = 'yt-dlp_macos'; Urls = (Get-DownloadUrls $lock.ytDlp.binaries.macosUniversal.url $lock.ytDlp.binaries.macosUniversal.fallbackUrls); Hash = $lock.ytDlp.binaries.macosUniversal.sha256 },
    [pscustomobject]@{ Name = 'yt_dlp_ejs-0.8.0.tar.gz'; Urls = (Get-DownloadUrls $lock.ejs.source.url $lock.ejs.source.fallbackUrls); Hash = $lock.ejs.source.sha256 },
    [pscustomobject]@{ Name = 'yt_dlp_ejs-0.8.0-py3-none-any.whl'; Urls = (Get-DownloadUrls $lock.ejs.wheel.url $lock.ejs.wheel.fallbackUrls); Hash = $lock.ejs.wheel.sha256 },
    [pscustomobject]@{ Name = 'quickjs-2026-06-04.tar.xz'; Urls = (Get-DownloadUrls $lock.quickjs.source.url $lock.quickjs.source.fallbackUrls); Hash = $lock.quickjs.source.sha256 },
    [pscustomobject]@{ Name = 'ffmpeg-8.1.3.tar.xz'; Urls = (Get-DownloadUrls $lock.ffmpeg.source.url $lock.ffmpeg.source.fallbackUrls); Hash = $lock.ffmpeg.source.sha256 },
    [pscustomobject]@{ Name = 'ffmpeg-8.1.3.tar.xz.asc'; Urls = (Get-DownloadUrls $lock.ffmpeg.source.signatureUrl $lock.ffmpeg.source.signatureFallbackUrls); Hash = $lock.ffmpeg.source.signatureSha256 },
    [pscustomobject]@{ Name = 'lame-3.100.tar.gz'; Urls = (Get-DownloadUrls $lock.lame.source.url $lock.lame.source.fallbackUrls); Hash = $lock.lame.source.sha256 },
    [pscustomobject]@{ Name = 'zlib-1.3.2.tar.gz'; Urls = (Get-DownloadUrls $lock.zlib.source.url $lock.zlib.source.fallbackUrls); Hash = $lock.zlib.source.sha256 },
    [pscustomobject]@{ Name = 'yt-dlp-public.key'; Urls = (Get-DownloadUrls $lock.ytDlp.signingKey.url $lock.ytDlp.signingKey.fallbackUrls); Hash = $lock.ytDlp.signingKey.sha256 },
    [pscustomobject]@{ Name = 'ffmpeg-devel.asc'; Urls = (Get-DownloadUrls $lock.ffmpeg.signingKey.url $lock.ffmpeg.signingKey.fallbackUrls); Hash = $lock.ffmpeg.signingKey.sha256 }
)

Assert-Download (Test-Path -LiteralPath $evidencePath) 'missing source-hashes.txt'
$attested = @{}
foreach ($line in Get-Content -LiteralPath $evidencePath) {
    if ($line -match '^\s*(#|$)') { continue }
    Assert-Download ($line -match '^([a-f0-9]{64})  ([A-Za-z0-9._-]+)$') "invalid evidence line: $line"
    $digest = $Matches[1]
    $name = $Matches[2]
    Assert-Download (-not $attested.ContainsKey($name)) "duplicate evidence: $name"
    $attested[$name] = $digest
}
Assert-Download ($attested.Count -eq $items.Count) 'evidence file has missing or extra entries'

if ($FetchMissing) { New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null }
Assert-Download (Test-Path -LiteralPath $downloadDir) 'downloads directory is absent; run fetch-sources.ps1'

foreach ($item in $items) {
    Assert-Download ($item.Urls.Count -gt 0) "$($item.Name) has no download URLs"
    foreach ($url in $item.Urls) { Assert-Download ($url -match '^https://') "$($item.Name) URL is not HTTPS" }
    Assert-Download ($item.Hash -match '^[a-f0-9]{64}$') "$($item.Name) is missing a locked SHA-256"
    Assert-Download ($attested.ContainsKey($item.Name)) "$($item.Name) is missing from evidence"
    Assert-Download ($attested[$item.Name] -eq $item.Hash) "$($item.Name) evidence disagrees with the source lock"
    $path = Join-Path $downloadDir $item.Name
    if (-not (Test-Path -LiteralPath $path) -and $FetchMissing) {
        $partial = "$path.partial"
        $fetched = $false
        for ($urlIndex = 0; $urlIndex -lt $item.Urls.Count; $urlIndex++) {
            if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
            $url = $item.Urls[$urlIndex]
            Write-Output "Fetching $($item.Name) from source URL $($urlIndex + 1) of $($item.Urls.Count)"
            & curl.exe --silent --show-error --fail --location --retry 3 --proto '=https' --proto-redir '=https' --output $partial $url
            if ($LASTEXITCODE -ne 0) {
                if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
                if ($urlIndex -eq ($item.Urls.Count - 1)) {
                    Assert-Download $false "curl failed for $($item.Name) at every locked URL"
                }
                Write-Warning "Download failed for $($item.Name); trying its next locked URL."
                continue
            }
            $partialHash = (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash.ToLowerInvariant()
            Assert-Download ($partialHash -eq $item.Hash) "$($item.Name) downloaded SHA-256 disagrees with lock"
            Move-Item -LiteralPath $partial -Destination $path
            $fetched = $true
            break
        }
        Assert-Download $fetched "could not fetch $($item.Name) from its locked URLs"
    }
    Assert-Download (Test-Path -LiteralPath $path -PathType Leaf) "missing $($item.Name); run fetch-sources.ps1"
    $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-Download ($actualHash -eq $item.Hash) "$($item.Name) SHA-256 mismatch"
}

$extra = @(Get-ChildItem -LiteralPath $downloadDir -File | Where-Object { $attested.ContainsKey($_.Name) -eq $false })
Assert-Download ($extra.Count -eq 0) "unlisted files in downloads directory: $($extra.Name -join ', ')"

# Match the inspected upstream version and root license inside the hash-locked
# zlib archive. contrib/ programs are not inputs to the planned FFmpeg build.
$zlibPath = Join-Path $downloadDir 'zlib-1.3.2.tar.gz'
$zlibHeader = (& tar.exe -xOzf $zlibPath 'zlib-1.3.2/zlib.h') -join "`n"
Assert-Download ($LASTEXITCODE -eq 0) 'could not read zlib.h from zlib archive'
$zlibVersion = [regex]::Escape([string]$lock.zlib.version)
Assert-Download ($zlibHeader -match "(?m)^#define ZLIB_VERSION `"$zlibVersion`"\s*$") 'zlib.h version disagrees with lock'
$zlibLicense = (& tar.exe -xOzf $zlibPath 'zlib-1.3.2/LICENSE') -join "`n"
Assert-Download ($LASTEXITCODE -eq 0) 'could not read root LICENSE from zlib archive'
Assert-Download ($zlibLicense -match 'Copyright notice:' -and
    $zlibLicense -match 'Permission is granted to anyone to use this software for any purpose' -and
    $zlibLicense -match 'This notice may not be removed or altered from any source distribution') 'zlib root license text is missing'

# The signed, hash-locked yt-dlp manifest must agree with the selected binaries.
$manifest = Get-Content -LiteralPath (Join-Path $downloadDir 'SHA2-256SUMS') -Raw
foreach ($name in @('yt-dlp.tar.gz', 'yt-dlp.exe', 'yt-dlp_linux', 'yt-dlp_macos')) {
    $pattern = '(?m)^([a-fA-F0-9]{64})\s+\*?' + [regex]::Escape($name) + '\s*$'
    $entry = [regex]::Matches($manifest, $pattern)
    Assert-Download ($entry.Count -eq 1) "expected one published SHA-256 for $name"
    Assert-Download ($entry[0].Groups[1].Value.ToLowerInvariant() -eq $attested[$name]) "published SHA-256 disagrees for $name"
}

$gpgCommand = Get-Command gpg.exe -ErrorAction SilentlyContinue
if ($gpgCommand) { $gpg = $gpgCommand.Source }
elseif (Test-Path -LiteralPath 'C:\Program Files\Git\usr\bin\gpg.exe') { $gpg = 'C:\Program Files\Git\usr\bin\gpg.exe' }
else { throw 'GnuPG is required to verify the yt-dlp and FFmpeg signatures.' }
$gitCygpath = 'C:\Program Files\Git\usr\bin\cygpath.exe'
$useGitGpg = $gpg -like '*\Git\usr\bin\gpg.exe'
if ($useGitGpg) { Assert-Download (Test-Path -LiteralPath $gitCygpath) 'Git GPG requires cygpath.exe' }

function Convert-GpgPath([string]$path) {
    if (-not $useGitGpg) { return $path }
    $converted = & $gitCygpath -u $path
    Assert-Download ($LASTEXITCODE -eq 0) "cygpath failed for $path"
    return $converted
}

function Assert-Signature([string]$keyName, [string]$signatureName, [string]$dataName, [string]$fingerprint) {
    Assert-Download ($fingerprint -match '^[A-F0-9]{40}$') "$keyName has no pinned signer fingerprint"
    $gpgHome = Join-Path $root ('work\engine\gpg-' + $keyName)
    New-Item -ItemType Directory -Path $gpgHome -Force | Out-Null
    $keyPath = Join-Path $downloadDir $keyName
    $signaturePath = Join-Path $downloadDir $signatureName
    $dataPath = Join-Path $downloadDir $dataName
    $gpgHomeArg = Convert-GpgPath $gpgHome
    $keyArg = Convert-GpgPath $keyPath
    $signatureArg = Convert-GpgPath $signaturePath
    $dataArg = Convert-GpgPath $dataPath
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue' # GPG writes diagnostics to stderr on successful verification.
    try {
        & $gpg --homedir $gpgHomeArg --batch --no-tty --no-autostart --no-auto-key-retrieve --import $keyArg 2>$null | Out-Null
        $importCode = $LASTEXITCODE
        $status = & $gpg --homedir $gpgHomeArg --batch --no-tty --no-autostart --no-auto-key-retrieve --status-fd 1 --verify $signatureArg $dataArg 2>$null | Out-String
        $verifyCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    Assert-Download ($importCode -eq 0) "could not import $keyName"
    Assert-Download ($verifyCode -eq 0) "bad signature for $dataName"
    Assert-Download ($status -match ('(?m)^\[GNUPG:\] VALIDSIG ' + [regex]::Escape($fingerprint) + '\s')) "unexpected signer for $dataName"
}

Assert-Signature 'yt-dlp-public.key' 'SHA2-256SUMS.sig' 'SHA2-256SUMS' $lock.ytDlp.signingKey.fingerprint
Assert-Signature 'ffmpeg-devel.asc' 'ffmpeg-8.1.3.tar.xz.asc' 'ffmpeg-8.1.3.tar.xz' $lock.ffmpeg.signingKey.fingerprint

Write-Output "Verified $($items.Count) locked files, published yt-dlp checksums, yt-dlp manifest signature and FFmpeg source signature."
