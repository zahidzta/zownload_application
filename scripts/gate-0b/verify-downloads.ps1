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

$source = Get-Content -LiteralPath $sourcePath -Raw
$blocks = [regex]::Matches($source, '(?s)```json source-lock\r?\n(.*?)\r?\n```')
Assert-Download ($blocks.Count -eq 1) 'expected one source-lock block'
$lock = $blocks[0].Groups[1].Value | ConvertFrom-Json
Assert-Download ($lock.schema -eq 1) 'unexpected source-lock schema'

# All network destinations come from the reviewed source lock. Each name is
# fixed here so a changed URL cannot write to an arbitrary local path.
$items = @(
    [pscustomobject]@{ Name = 'yt-dlp.tar.gz'; Url = $lock.ytDlp.source.url; Hash = $lock.ytDlp.source.sha256 },
    [pscustomobject]@{ Name = 'SHA2-256SUMS'; Url = $lock.ytDlp.checksumManifest.url; Hash = $lock.ytDlp.checksumManifest.sha256 },
    [pscustomobject]@{ Name = 'SHA2-256SUMS.sig'; Url = $lock.ytDlp.checksumManifest.signatureUrl; Hash = $lock.ytDlp.checksumManifest.signatureSha256 },
    [pscustomobject]@{ Name = 'yt-dlp.exe'; Url = $lock.ytDlp.binaries.windowsX64.url; Hash = $lock.ytDlp.binaries.windowsX64.sha256 },
    [pscustomobject]@{ Name = 'yt-dlp_linux'; Url = $lock.ytDlp.binaries.linuxX64.url; Hash = $lock.ytDlp.binaries.linuxX64.sha256 },
    [pscustomobject]@{ Name = 'yt-dlp_macos'; Url = $lock.ytDlp.binaries.macosUniversal.url; Hash = $lock.ytDlp.binaries.macosUniversal.sha256 },
    [pscustomobject]@{ Name = 'yt_dlp_ejs-0.8.0.tar.gz'; Url = $lock.ejs.source.url; Hash = $lock.ejs.source.sha256 },
    [pscustomobject]@{ Name = 'yt_dlp_ejs-0.8.0-py3-none-any.whl'; Url = $lock.ejs.wheel.url; Hash = $lock.ejs.wheel.sha256 },
    [pscustomobject]@{ Name = 'quickjs-2026-06-04.tar.xz'; Url = $lock.quickjs.source.url; Hash = $lock.quickjs.source.sha256 },
    [pscustomobject]@{ Name = 'ffmpeg-8.1.3.tar.xz'; Url = $lock.ffmpeg.source.url; Hash = $lock.ffmpeg.source.sha256 },
    [pscustomobject]@{ Name = 'ffmpeg-8.1.3.tar.xz.asc'; Url = $lock.ffmpeg.source.signatureUrl; Hash = $lock.ffmpeg.source.signatureSha256 },
    [pscustomobject]@{ Name = 'lame-3.100.tar.gz'; Url = $lock.lame.source.url; Hash = $lock.lame.source.sha256 },
    [pscustomobject]@{ Name = 'zlib-1.3.2.tar.gz'; Url = $lock.zlib.source.url; Hash = $lock.zlib.source.sha256 },
    [pscustomobject]@{ Name = 'yt-dlp-public.key'; Url = $lock.ytDlp.signingKey.url; Hash = $lock.ytDlp.signingKey.sha256 },
    [pscustomobject]@{ Name = 'ffmpeg-devel.asc'; Url = $lock.ffmpeg.signingKey.url; Hash = $lock.ffmpeg.signingKey.sha256 }
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
    Assert-Download ($item.Url -match '^https://') "$($item.Name) URL is not HTTPS"
    Assert-Download ($item.Hash -match '^[a-f0-9]{64}$') "$($item.Name) is missing a locked SHA-256"
    Assert-Download ($attested.ContainsKey($item.Name)) "$($item.Name) is missing from evidence"
    Assert-Download ($attested[$item.Name] -eq $item.Hash) "$($item.Name) evidence disagrees with the source lock"
    $path = Join-Path $downloadDir $item.Name
    if (-not (Test-Path -LiteralPath $path) -and $FetchMissing) {
        $partial = "$path.partial"
        Write-Output "Fetching $($item.Name)"
        & curl.exe --silent --show-error --fail --location --retry 3 --proto '=https' --proto-redir '=https' --output $partial $item.Url
        Assert-Download ($LASTEXITCODE -eq 0) "curl failed for $($item.Name) (exit $LASTEXITCODE)"
        $partialHash = (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash.ToLowerInvariant()
        Assert-Download ($partialHash -eq $item.Hash) "$($item.Name) downloaded SHA-256 disagrees with lock"
        Move-Item -LiteralPath $partial -Destination $path
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
