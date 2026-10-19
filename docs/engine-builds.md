# Engine build recipes

## 0B-04 — Windows x64 QuickJS environment

Use the upstream QuickJS `2026-06-04` source archive locked in
[`engine-sources.md`](engine-sources.md). Its SHA-256 is
`b376e839b322978313d929fd20663b11ba58b75df5a46c126dd19ea2fa70ad2a`.
The [upstream Makefile](https://github.com/bellard/quickjs/blob/master/Makefile)
has a Windows MinGW path. The attested release archive, rather than that
moving GitHub view, is what the script actually builds.

The Windows toolchain is [w64devkit v2.10.1 x64](https://github.com/skeeto/w64devkit/releases/tag/v2.10.1),
using its immutable `w64devkit-x64-2.10.1.7z.exe` asset. Its GitHub release
asset reports SHA-256
`add1edf984ce4d473cfeb7c52e0ab38db73a855bba6c7f564d5e16648eb2896a`;
the downloaded bytes matched. This bundle supplies GCC `16.2.0` targeting
`x86_64-w64-mingw32`, GNU Make `4.4.1`, `ar`, and BusyBox shell utilities.
The extracted `gcc.exe` and `make.exe` SHA-256 values are respectively
`e47ff11a48f1dd4546a0e5ae14913ea582f0c77a4c9a48ceb35ad8d2880fe27d`
and `d852bcfc0c1903aad10b3f7dfb04dce21d1165666d7301ad9f308a1f8900dc3f`;
the checker rejects either mismatch.
It uses the MSVCRT runtime and statically links its own runtime components.
Its [license notes](https://github.com/skeeto/w64devkit/blob/master/README.md#licenses)
require the applicable MinGW-w64 runtime notices with redistributed binaries;
0B-12 must inspect the actual QuickJS binary and include those notices.
The older local `C:\MinGW` GCC targets 32-bit `mingw32` and is not used.

From a Windows PowerShell at the repository root, first obtain and verify
the source using the existing 0B-03 task, then set up the isolated toolchain:

```powershell
powershell -NoProfile -File scripts/gate-0b/fetch-sources.ps1
$toolDir = Join-Path (Get-Location) 'work\engine\toolchains'
New-Item -ItemType Directory -Path $toolDir -Force | Out-Null
$archive = Join-Path $toolDir 'w64devkit-x64-2.10.1.7z.exe'
curl.exe --fail --location --retry 3 --proto '=https' --proto-redir '=https' --output $archive 'https://github.com/skeeto/w64devkit/releases/download/v2.10.1/w64devkit-x64-2.10.1.7z.exe'
if ($LASTEXITCODE -ne 0) { throw 'w64devkit download failed' }
$expected = 'add1edf984ce4d473cfeb7c52e0ab38db73a855bba6c7f564d5e16648eb2896a'
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) { throw 'w64devkit SHA-256 mismatch' }
& $archive -y "-o$toolDir"
if ($LASTEXITCODE -ne 0) { throw 'w64devkit extraction failed' }
powershell -NoProfile -File scripts/gate-0b/build-quickjs.ps1 -Target windows-x64 -CheckEnvironment
```

The self-extracting archive places the toolchain at
`work/engine/toolchains/w64devkit/`. No system PATH or installed compiler
needs to change. The script checks both archive hashes, the QuickJS version,
GCC version and x64 target, Make version, and required tool files. It fixes
these upstream Make variables before compilation:

```text
CONFIG_WIN32=y CROSS_PREFIX= CONFIG_LTO= CONFIG_TEMPORAL_INTL=y qjs.exe
```

`CONFIG_WIN32=y` selects the Windows link path; the empty `CROSS_PREFIX`
selects this host's x64 GCC rather than a Linux cross-compiler. LTO is
disabled because the pinned toolchain was configured without it. Temporal
and Intl stay enabled as in the upstream x64 default. The Makefile supplies
`-O2`, `-fwrapv`, `-D_GNU_SOURCE`, the release's `CONFIG_VERSION`, and the
Windows `__USE_MINGW_ANSI_STDIO` define; it links with `-lm -lpthread`.
The script prepends only the pinned toolchain's `bin` while Make runs and
builds solely the `qjs.exe` target from a fresh source extraction.

The deterministic output path is
`work/engine/build/quickjs/windows-x64/qjs.exe`; source extraction and the
full build log stay under the same ignored directory. 0B-05 will run
`powershell -NoProfile -File scripts/gate-0b/build-quickjs.ps1 -Target windows-x64 -Verify`
to compile and execute the trivial JavaScript check, then record the binary
hash and evidence. 0B-04 verifies the environment only.
