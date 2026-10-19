# Offline Gate 0B redistribution audit. The locked inputs and local Windows
# builds are checked again; no engine binary or source is added to Git.
$ErrorActionPreference = 'Stop'

function Assert-License([bool]$ok, [string]$message) {
    if (-not $ok) { throw "Gate 0B license audit: $message" }
}
function Read-ArchiveText([string]$archive, [string]$member) {
    $lines = @(& tar.exe -xOf $archive $member)
    Assert-License ($LASTEXITCODE -eq 0) "cannot read $member"
    Assert-License ($lines.Count -gt 0) "empty $member"
    return ($lines -join "`n")
}
function Assert-FileHash([string]$path, [string]$expected) {
    Assert-License (Test-Path -LiteralPath $path -PathType Leaf) "missing $path"
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-License ($actual -eq $expected) "SHA-256 mismatch: $path"
}

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$downloads = Join-Path $root 'work\engine\downloads'
$build = Join-Path $root 'work\engine\build'
$noticePath = Join-Path $root 'docs\THIRD-PARTY-NOTICES.md'
$evidencePath = Join-Path $root 'docs\gates\evidence\0b\license-audit.txt'
$sourcePath = Join-Path $root 'docs\engine-sources.md'
$buildPath = Join-Path $root 'docs\engine-builds.md'
$source = Get-Content -LiteralPath $sourcePath -Raw
$block = [regex]::Matches($source, '(?s)```json source-lock\r?\n(.*?)\r?\n```')
Assert-License ($block.Count -eq 1) 'source lock is missing'
$lock = $block[0].Groups[1].Value | ConvertFrom-Json

$downloadCheck = @(& powershell -NoProfile -File (Join-Path $PSScriptRoot 'verify-downloads.ps1') 2>&1)
if ($LASTEXITCODE -ne 0) {
    $downloadCheck | Select-Object -Last 50
    throw 'Gate 0B license audit: locked inputs failed verification'
}

$ytLicense = Read-ArchiveText (Join-Path $downloads 'yt-dlp.tar.gz') 'yt-dlp/LICENSE'
Assert-License ($ytLicense -match 'unencumbered software released into the public domain') 'yt-dlp Unlicense text is missing'
$ejsLicense = Read-ArchiveText (Join-Path $downloads 'yt_dlp_ejs-0.8.0.tar.gz') 'yt_dlp_ejs-0.8.0/LICENSE'
Assert-License ($ejsLicense -match 'unencumbered software released into the public domain') 'EJS Unlicense text is missing'
$quickLicense = Read-ArchiveText (Join-Path $downloads 'quickjs-2026-06-04.tar.xz') 'quickjs-2026-06-04/LICENSE'
Assert-License ($quickLicense -match 'Permission is hereby granted, free of charge') 'QuickJS MIT text is missing'
$ffLicense = Read-ArchiveText (Join-Path $downloads 'ffmpeg-8.1.3.tar.xz') 'ffmpeg-8.1.3/COPYING.LGPLv2.1'
Assert-License ($ffLicense -match 'GNU LESSER GENERAL PUBLIC LICENSE') 'FFmpeg LGPL 2.1 text is missing'
$lameLicense = Read-ArchiveText (Join-Path $downloads 'lame-3.100.tar.gz') 'lame-3.100/COPYING'
Assert-License ($lameLicense -match 'GNU LIBRARY GENERAL PUBLIC LICENSE') 'LAME Library GPL 2 text is missing'
$lameSource = Read-ArchiveText (Join-Path $downloads 'lame-3.100.tar.gz') 'lame-3.100/libmp3lame/lame.c'
Assert-License ($lameSource -match 'version 2 of the License, or \(at your option\) any later version') 'LAME encoder grant is missing'
$zlibLicense = Read-ArchiveText (Join-Path $downloads 'zlib-1.3.2.tar.gz') 'zlib-1.3.2/LICENSE'
Assert-License ($zlibLicense -match 'This notice may not be removed or altered') 'zlib license conditions are missing'

# Parse the appended PyInstaller CArchive with Python's standard library.
# The format is documented in PyInstaller's archive viewer documentation.
# The official binaries are first pinned by the signed source-lock verifier.
$archiveAudit = @'
import hashlib, json, re, struct, sys, zipfile, zlib
from pathlib import Path

MAGIC = b'MEI\x0c\x0b\x0a\x0b\x0e'
def members(path):
    data = path.read_bytes()
    cookie = data.rfind(MAGIC)
    if cookie < 0 or cookie + 88 > len(data):
        raise ValueError(f'{path.name}: no complete PyInstaller archive cookie')
    _, length, offset, size, _, library = struct.unpack_from('!8sIIII64s', data, cookie)
    start = cookie + 88 - length
    if start < 0 or not library.strip(b'\0'):
        raise ValueError(f'{path.name}: invalid archive cookie')
    toc = data[start + offset:start + offset + size]
    found = {}
    position = 0
    while position < len(toc):
        entry_length, entry_offset, packed, unpacked, compressed, kind = struct.unpack_from('!IIIIBc', toc, position)
        if entry_length < 18 or position + entry_length > len(toc):
            raise ValueError(f'{path.name}: invalid archive entry')
        name = toc[position + 18:position + entry_length].rstrip(b'\0').decode('utf-8')
        payload = data[start + entry_offset:start + entry_offset + packed]
        if len(payload) != packed:
            raise ValueError(f'{path.name}: truncated archive member {name}')
        if name == 'THIRD_PARTY_LICENSES.txt' or name.replace('\\', '/').endswith(('/core.min.js', '/lib.min.js')):
            content = zlib.decompress(payload) if compressed else payload
            if len(content) != unpacked:
                raise ValueError(f'{path.name}: wrong member size {name}')
            found[name.replace('\\', '/')] = content
        position += entry_length
    return found

folder = Path(sys.argv[1])
with zipfile.ZipFile(folder / 'yt_dlp_ejs-0.8.0-py3-none-any.whl') as wheel:
    wheel_license = wheel.read('yt_dlp_ejs-0.8.0.dist-info/licenses/LICENSE').decode('utf-8')
    if 'unencumbered software released into the public domain' not in wheel_license:
        raise ValueError('EJS wheel has no Unlicense text')
    wheel_hashes = {name: hashlib.sha256(wheel.read(name)).hexdigest()
                    for name in ('yt_dlp_ejs/yt/solver/core.min.js', 'yt_dlp_ejs/yt/solver/lib.min.js')}
normalized = None
for filename, expected in (('yt-dlp.exe', '5b7bc105c562b81b90d1a2cd5a8cc8b336ee107ae0ae81ce58450cd8b1bc2ad4'),
                           ('yt-dlp_linux', '472aefe951c7db35e1657c1d13fd337140511ed6f2b329205105ad441c5a02b7'),
                           ('yt-dlp_macos', '472aefe951c7db35e1657c1d13fd337140511ed6f2b329205105ad441c5a02b7')):
    found = members(folder / filename)
    notice = found.get('THIRD_PARTY_LICENSES.txt')
    if notice is None or hashlib.sha256(notice).hexdigest() != expected:
        raise ValueError(f'{filename}: missing or altered embedded license inventory')
    text = notice.decode('utf-8').replace('\r\n', '\n')
    headings = re.findall(r'^([^\n|]+) \| ([^\n]+)$', text, re.M)
    if len(headings) != 45 or len(set(headings)) != 45:
        raise ValueError(f'{filename}: unexpected license inventory')
    names = {name for name, _ in headings}
    if not {'Python', 'GNU Readline', 'mutagen', 'Meriyah', 'Astring'} <= names:
        raise ValueError(f'{filename}: required bundled component notice is missing')
    if not all(section.strip() for section in re.split(r'(?m)^-{80}$', text)[1:]):
        raise ValueError(f'{filename}: empty license section')
    if normalized is None:
        normalized = text
    elif text != normalized:
        raise ValueError(f'{filename}: platform license inventories differ')
    for name, digest in wheel_hashes.items():
        if name not in found or hashlib.sha256(found[name]).hexdigest() != digest:
            raise ValueError(f'{filename}: embedded EJS differs from locked wheel: {name}')
    print(json.dumps({'file': filename, 'notice_sha256': expected, 'components': len(headings),
                      'ejs_core_sha256': wheel_hashes['yt_dlp_ejs/yt/solver/core.min.js'],
                      'ejs_lib_sha256': wheel_hashes['yt_dlp_ejs/yt/solver/lib.min.js']}))
'@
$archiveResult = @(& python -c $archiveAudit $downloads 2>&1)
if ($LASTEXITCODE -ne 0) {
    $archiveResult | Select-Object -Last 50
    throw 'Gate 0B license audit: yt-dlp embedded inventory failed'
}
Assert-License ($archiveResult.Count -eq 3) 'expected three yt-dlp archive results'
foreach ($line in $archiveResult) {
    $item = $line | ConvertFrom-Json
    Assert-License ($item.components -eq 45) "incomplete $($item.file) third-party inventory"
}

$quick = Join-Path $build 'quickjs\windows-x64\qjs.exe'
Assert-FileHash $quick 'bec67f8f87fa22958d3ab8be5508088116b8bff90032323d82c94545e1698b83'
$recipe = Join-Path $build 'ffmpeg\windows-x64\recipe'
$ffmpeg = Join-Path $recipe 'ffmpeg-8.1.3\ffmpeg.exe'
$ffprobe = Join-Path $recipe 'ffmpeg-8.1.3\ffprobe.exe'
Assert-FileHash $ffmpeg 'fa050630ddf5b7c3303d8dab5e5a42e7023547fb78ec9b90b5be0a4f788a7e66'
Assert-FileHash $ffprobe 'bf44a50347aaba3e433c34c8c881d67eeaca41001577482ce3ba69b780824ec7'
foreach ($exe in @($ffmpeg, $ffprobe)) {
    # FFmpeg writes its version banner to stderr even on success. Windows
    # PowerShell 5.1 otherwise promotes that banner to a terminating error.
    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $license = (& $exe -L 2>&1) -join "`n"
        $licenseCode = $LASTEXITCODE
        $configuration = (& $exe -buildconf 2>&1) -join "`n"
        $configurationCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldPreference
    }
    $licenseFlat = $license -replace '\s+', ' '
    Assert-License ($licenseCode -eq 0 -and $licenseFlat -match 'Lesser General Public License' -and $licenseFlat -match 'version 2\.1 of the License, or .*any later version') "LGPL license output missing from $exe"
    Assert-License ($configurationCode -eq 0) "cannot inspect configuration of $exe"
    Assert-License ($configuration -match '--enable-libmp3lame' -and $configuration -match '--enable-zlib') "required libraries absent in $exe"
    Assert-License ($configuration -notmatch '--enable-(gpl|nonfree|version3)') "GPL/nonfree option in $exe"
}
$config = Get-Content -LiteralPath (Join-Path $recipe 'ffmpeg-8.1.3\config.h') -Raw
foreach ($option in @('GPL', 'NONFREE', 'VERSION3')) {
    Assert-License ($config -match "(?m)^#define CONFIG_${option} 0$") "CONFIG_$option is not disabled"
}
$ar = Join-Path $root 'work\engine\toolchains\w64devkit\bin\ar.exe'
Assert-License (Test-Path -LiteralPath $ar -PathType Leaf) 'pinned ar.exe is missing'
$objects = (& $ar t (Join-Path $recipe 'deps\lib\libmp3lame.a') 2>&1) -join "`n"
$lameConfig = Get-Content -LiteralPath (Join-Path $recipe 'lame-3.100\config.h') -Raw
# mpglib_interface.o belongs to the encoder archive even when the decoder
# is disabled. Check the actual GPL decoder objects, not that interface name.
Assert-License ($LASTEXITCODE -eq 0 -and $objects -notmatch '(?im)^(common|dct64_i386|decode_i386|interface|layer[123]|tabinit)\.o$' -and $lameConfig -match '(?m)^/\* #undef HAVE_MPGLIB \*/$') 'GPL LAME decoder objects present or archive unreadable'
$runtimeNotice = Join-Path $root 'work\engine\toolchains\w64devkit\COPYING.MinGW-w64-runtime.txt'
Assert-FileHash $runtimeNotice 'ecff91ddb5799c8b79a4bdb576921b9c3e2989783fd1944527e8eb9b41a5ff5f'
Assert-License ((Get-Content -LiteralPath $runtimeNotice -Raw) -match 'MinGW-w64 runtime licensing') 'MinGW-w64 notice text is incomplete'
$objdump = Join-Path $root 'work\engine\toolchains\w64devkit\bin\objdump.exe'
Assert-License (Test-Path -LiteralPath $objdump -PathType Leaf) 'pinned objdump.exe is missing'
foreach ($exe in @($quick, $ffmpeg, $ffprobe)) {
    $dlls = @(& $objdump -p $exe | Select-String 'DLL Name:' | ForEach-Object { $_.Line.Trim() })
    Assert-License ($LASTEXITCODE -eq 0 -and $dlls.Count -gt 0) "cannot inspect DLL imports of $exe"
    Assert-License (-not ($dlls -match '(?i)lib(mp3lame|z)|libwinpthread|libgcc|libstdc\+\+')) "unexpected runtime DLL import in $exe"
}

$notices = Get-Content -LiteralPath $noticePath -Raw
$evidence = Get-Content -LiteralPath $evidencePath -Raw
$builds = Get-Content -LiteralPath $buildPath -Raw
Assert-License ($notices -notmatch 'TODO') 'third-party notice template still contains TODO'
foreach ($component in @('FFmpeg', 'QuickJS', 'yt-dlp', 'yt-dlp-ejs', 'LAME', 'zlib', 'MinGW-w64', 'GPL-3.0-or-later', 'relink')) {
    Assert-License ($notices -match [regex]::Escape($component)) "notice or release plan missing $component"
}
foreach ($hash in @($lock.ytDlp.source.sha256, $lock.ejs.source.sha256, $lock.quickjs.source.sha256,
                   $lock.ffmpeg.source.sha256, $lock.lame.source.sha256, $lock.zlib.source.sha256,
                   'bec67f8f87fa22958d3ab8be5508088116b8bff90032323d82c94545e1698b83',
                   '50263177cb921024aabc0807a31d71be7fa3c22f0c5824c3c6a2d1cf920f300c',
                   '554102a8a9c0d0c5e24cd138ad7a790f330fd926310c01009265589a446ef90a',
                   'fba79a316a53ed58a17709a39c173218f8bc825831094b6033ce0510a713bb43',
                   '4db3b8aeba709b4907da59a87f1ab3f94585bae3a95f7b02c946b7732cd20185',
                   'fa050630ddf5b7c3303d8dab5e5a42e7023547fb78ec9b90b5be0a4f788a7e66',
                   'bf44a50347aaba3e433c34c8c881d67eeaca41001577482ce3ba69b780824ec7')) {
    Assert-License ($notices.Contains($hash)) "notice is missing SHA-256 $hash"
    Assert-License ($evidence.Contains($hash)) "audit evidence is missing SHA-256 $hash"
}
Assert-License ($builds -match '0B-11' -and $builds -match '0B-12') 'build configuration and audit setup are not recorded'
Assert-License ($evidence -match '45 embedded license entries' -and $evidence -match 'CONFIG_GPL=0') 'audit evidence is incomplete'

Write-Output 'Gate 0B license audit passed: 15 locked inputs, 3 yt-dlp inventories, EJS wheel match, source texts, QuickJS, LGPL FFmpeg/ffprobe, LAME decoder exclusion, notices and release plan.'
