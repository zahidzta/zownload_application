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
full build log stay under the same ignored directory. 0B-04 verified the
environment only.

## 0B-05 — Windows x64 QuickJS binary

Run the exact gate verification command from the repository root:

```powershell
powershell -NoProfile -File scripts/gate-0b/build-quickjs.ps1 -Target windows-x64 -Verify
```

This extracts the attested source afresh, builds `qjs.exe` with the pinned
toolchain and flags above, checks the executable's reported version, and
executes `print(1 + 1)`. The local Windows run exited `0`, reported
`QuickJS version 2026-06-04`, and printed `2`. Its 5,575,257-byte binary had
SHA-256 `bec67f8f87fa22958d3ab8be5508088116b8bff90032323d82c94545e1698b83`;
a second fresh extraction and build at the same path produced the same hash.
Pinned-toolchain `objdump -f` identified `pei-x86-64` and `i386:x86-64`.
The exact commands, build-log flags, and output are recorded in
[`gates/evidence/0b/quickjs-windows.txt`](gates/evidence/0b/quickjs-windows.txt).
The binary and full build log remain ignored local artifacts; run the command
above to regenerate them.

## 0B-06 — Linux x64 QuickJS binary

The Linux build uses the same attested upstream QuickJS `2026-06-04` archive
and SHA-256 listed above. The build host is the Gate 0A Ubuntu `24.04` x64 CI
baseline. Its system GCC 13, GNU Make, `curl`, `sha256sum`, `tar`, and `file`
are checked before compilation. On a clean Ubuntu 24.04 host, the setup is:

```bash
sudo apt-get update
sudo apt-get install -y gcc-13 make curl coreutils tar xz-utils file
bash scripts/gate-0b/build-quickjs.sh linux-x64 --verify
```

The script downloads the exact locked URL only when its local archive is
absent, rejects a different source hash, and builds from a new extraction at
a fixed path so GCC debug paths do not change between CI runs.
It invokes upstream Make with `CC=gcc-13 HOST_CC=gcc-13 CONFIG_LTO=
CONFIG_TEMPORAL_INTL=y qjs`. This selects GCC 13 and keeps the upstream x64
Temporal/Intl configuration while disabling LTO. The Makefile supplies the
release version define, `-O2`, `-fwrapv`, and its Linux libraries. The script
checks the ELF architecture, built-in QuickJS version, and `print(1 + 1)`.
Its output is `work/engine/build/quickjs/linux-x64/qjs`; the binary and full
build log remain ignored. The GitHub Actions job in
`.github/workflows/gate-0b-engines.yml` runs the exact command on
`ubuntu-24.04` after checkout. The run output and resulting hash are recorded
in [`gates/evidence/0b/quickjs-linux.txt`](gates/evidence/0b/quickjs-linux.txt).
GitHub Actions run `39194291600` passed twice from clean runners using GCC
`13.3.0` and GNU Make `4.3`. Both attempts produced a 5,079,320-byte ELF
x86-64 binary with SHA-256
`50263177cb921024aabc0807a31d71be7fa3c22f0c5824c3c6a2d1cf920f300c`.

## 0B-07 — macOS x64 QuickJS binary

The macOS build uses the same attested QuickJS source archive and hash as the
Linux build. GitHub Actions runs the exact gate command on its documented
[`macos-15-intel` runner](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
The script selects Xcode 16.4 build 16F6 from the
[macOS 15 image](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md),
checks the Intel host and Apple Clang target, and uses that Clang for both
`CC` and `HOST_CC`. It selects the macOS 15.5 SDK so Clang finds the system
headers. On a macOS x64 host with that Xcode installed, run:

```bash
bash scripts/gate-0b/build-quickjs.sh macos-x64 --verify
```

The script fetches the locked archive only if absent, checks its SHA-256,
extracts it afresh at a fixed path, and builds the upstream `qjs` target with
`CONFIG_LTO=` and `CONFIG_TEMPORAL_INTL=y`. The Makefile selects its Darwin
Clang settings and supplies the optimization flags. The macOS link keeps `-g`
and passes `-Wl,-reproducible`, as documented by
[Apple's linker](https://keith.github.io/xcode-man-pages/ld.1.html#reproducible).
Verification
checks the Mach-O x86_64 format, reported QuickJS version, and
`print(1 + 1)` result. The output and full log remain ignored at
`work/engine/build/quickjs/macos-x64/`; the observed commands, tool versions,
binary hash, and CI run are in
[`gates/evidence/0b/quickjs-macos-x64.txt`](gates/evidence/0b/quickjs-macos-x64.txt).
Two clean `macos-15-intel` CI attempts with Xcode 16.4 produced the same
1,241,256-byte Mach-O x86_64 binary with SHA-256
`554102a8a9c0d0c5e24cd138ad7a790f330fd926310c01009265589a446ef90a`.

## 0B-08 — macOS arm64 QuickJS binary

GitHub Actions runs the exact gate command on its documented
[`macos-15` arm64 runner](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
The script uses the same attested upstream source and build settings as the
macOS x64 recipe, selects Xcode 16.4 build 16F6 and its macOS 15.5 SDK, and
requires an arm64 host with Apple Clang targeting arm64. Run on that host:

```bash
bash scripts/gate-0b/build-quickjs.sh macos-arm64 --verify
```

The source is extracted afresh at a fixed path under the ignored
`work/engine/build/quickjs/macos-arm64/` directory. Verification checks the
source SHA-256, Mach-O arm64 format, reported QuickJS version and
`print(1 + 1)` result. The full log and binary stay ignored. The compiler,
flags, output hash and CI run are recorded in
[`gates/evidence/0b/quickjs-macos-arm64.txt`](gates/evidence/0b/quickjs-macos-arm64.txt).
Two clean `macos-15` CI attempts with Xcode 16.4 produced the same
1,158,656-byte Mach-O arm64 binary with SHA-256
`fba79a316a53ed58a17709a39c173218f8bc825831094b6033ce0510a713bb43`.

## 0B-09 — Android arm64 QuickJS binary

The Android build uses the same locked QuickJS `2026-06-04` archive and source
SHA-256 as the desktop builds. Run it on the Gate 0A Ubuntu 24.04 x64 baseline
with Android NDK r30 (`30.0.16248370`), GCC 13, GNU Make, `curl`, `tar`,
`sha256sum`, and `file`. With Android SDK Command-Line Tools 22.0 installed:

```bash
sdkmanager 'ndk;30.0.16248370'
export NDK_HOME="${ANDROID_SDK_ROOT:-$ANDROID_HOME}/ndk/30.0.16248370"
bash scripts/gate-0b/build-quickjs.sh android-arm64 --verify
```

The CI job installs that exact NDK package with `android-actions/setup-android`
and checks `source.properties` before compilation. The recipe follows
[Android's NDK guidance for non-CMake Make projects](https://developer.android.com/ndk/guides/other_build_systems):
NDK Clang targets `aarch64-linux-android24` for the app's minimum API 24.
Upstream Make uses host GCC 13 to generate `repl.c` with `host-qjsc`, then NDK
Clang builds `qjs`. `CONFIG_LTO=` and `CONFIG_TEMPORAL_INTL=y` match the
desktop recipe. Its target link uses `LIBS=-lm -ldl` because [Android includes
pthread functions in `libc`](https://developer.android.com/ndk/guides/stable_apis),
without a separate `libpthread`. The script extracts the source afresh at the stable ignored
path `work/engine/build/quickjs/android-arm64/`, checks ELF AArch64 and the
Android linker path, and lists every linked shared library with the NDK's
`llvm-readelf`. It does not execute the Android binary on the Linux host.
Device execution and Android packaging are Gate 0C work. The exact compiler,
flags, ELF inspection, artifact hash and CI run are recorded in
[`gates/evidence/0b/quickjs-android.txt`](gates/evidence/0b/quickjs-android.txt).

## 0B-10 — Windows x64 LGPL FFmpeg configuration

From the repository root, after the 0B-03/10A source acquisition and 0B-04
w64devkit setup, run:

```powershell
powershell -NoProfile -File scripts/gate-0b/build-ffmpeg.ps1 -CheckConfiguration
```

The script runs the offline source/signature verifier and checks the exact
FFmpeg 8.1.3, LAME 3.100, zlib 1.3.2 and w64devkit 2.10.1 archive hashes. It
checks pinned GCC 16.2.0 targeting `x86_64-w64-mingw32` and GNU Make 4.4.1.
It extracts all three sources afresh under the ignored
`work/engine/build/ffmpeg/windows-x64/recipe/` directory.
The attested source SHA-256 values are FFmpeg
`7138d28c96d9d3e3af4ee3d8cad72741f8ffb40da90c1112235dea3ecd3178a3`,
LAME `ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e`
and zlib `bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16`.

The LAME 3.100 encoder-only configuration is:

```text
./configure --build=x86_64-w64-mingw32 --disable-decoder --disable-frontend --disable-shared --enable-static --disable-mp3x --disable-mp3rtp CC=gcc.exe CFLAGS=-O2 AR=ar.exe RANLIB=ranlib.exe AWK=awk.exe SED=sed.exe GREP=grep.exe EGREP=egrep.exe FGREP=fgrep.exe NM=nm.exe LD=ld.exe OBJDUMP=objdump.exe
make.exe -C libmp3lame -j2
```

The explicit `.exe` names let LAME's older Autoconf script locate the pinned
Windows tools. LAME compiles with `-O2`. `--disable-decoder` leaves `HAVE_MPGLIB` undefined; the script
inspects the static archive and rejects GPL decoder objects. Only LAME's
`libmp3lame` target is built. zlib's root static library is built with
`make.exe -f win32/Makefile.gcc libz.a` (upstream `-O3 -Wall` flags);
`contrib/` programs and examples are
excluded. Their headers and static archives are copied to the recipe's
`deps/include` and `deps/lib` directories.

With `D` equal to the shell path of the recipe's `deps` directory, the FFmpeg
configuration is exactly:

```text
./configure --target-os=mingw32 --arch=x86_64 --cc=gcc.exe --cxx=g++.exe --ar=ar.exe --ranlib=ranlib.exe --nm=nm.exe --strip=strip.exe --pkg-config=false --disable-autodetect --disable-x86asm --disable-ffplay --disable-doc --disable-debug --enable-static --disable-shared --enable-libmp3lame --enable-zlib --extra-cflags="-I$D/include" --extra-ldflags="-L$D/lib"
```

The script sets `PATH` to the pinned w64devkit `bin` for each configure/build
step. `--disable-x86asm` removes an unpinned NASM requirement;
`--pkg-config=false` and `--disable-autodetect` prevent ambient package
detection. The explicit `--enable-libmp3lame` and `--enable-zlib` probes link
against the built static libraries. Generated `ffbuild/config.mak` records
fully expanded paths and flags. The script checks that only LAME and zlib
appear among FFmpeg's enabled external libraries, and that `config.h` has
`CONFIG_GPL=0`, `CONFIG_NONFREE=0` and `CONFIG_VERSION3=0`.
FFmpeg's generated C flags include `-std=c17`, `-O3`, `-fomit-frame-pointer`,
`-Wall` and the warnings/errors in `ffbuild/config.mak`; its MinGW linker
flags include `--nxcompat`, `--dynamicbase` and `--high-entropy-va`.
`--pkg-config=false` prints a warning that the named executable is absent;
the explicit LAME and zlib header/link probes still must pass.

The configure probe must report `License: LGPL version 2.1 or later` and enable
the LAME MP3 encoder, native AAC encoder, MP3/MOV/MP4 muxers, PNG decoder,
MJPEG encoder, image scale filter, `swscale`, `ffmpeg` and `ffprobe`. PNG plus
zlib decodes the locked fixture's artwork; MJPEG encodes its JPEG cover. Full
logs, static libraries and configured source stay ignored under the recipe
directory. 0B-12 completes the redistribution license inventory and relinking
plan.

## 0B-11 — Windows x64 FFmpeg and ffprobe build

From the repository root, with the locked archives and pinned w64devkit already
installed, run the complete fresh-extraction recipe:

```powershell
powershell -NoProfile -File scripts/gate-0b/build-ffmpeg.ps1 -Verify
```

`-Verify` repeats the 0B-10 source, signature, toolchain and configuration
checks, then uses `make.exe -j2 V=1 ffmpeg.exe ffprobe.exe` with the pinned w64devkit
tools. The complete compiler output stays in the ignored
`work/engine/build/ffmpeg/windows-x64/recipe/ffmpeg-build.log`. The two built
executables and short smoke outputs stay in the ignored extracted FFmpeg
directory; none is committed as a prebuilt binary.

The verification checks both binaries' version, build configuration and
reported LGPL license. It lists enabled MP3/AAC/JPEG encoders, PNG decoder,
MP3/MOV/MP4 muxers and image scaling, then actually encodes a short MP3 with
LAME and an MP4 with native AAC. `ffprobe` confirms the output codecs.
Pinned `objdump.exe -p` lists each executable's PE DLL imports, including any
runtime dependency introduced by the static LAME or zlib linkage. The binary
hashes, version lines, import lists and smoke results are recorded in
[`gates/evidence/0b/ffmpeg-windows.txt`](gates/evidence/0b/ffmpeg-windows.txt).
The pinned `ar.exe` writes build-time member timestamps into the LAME and zlib
archives, so their SHA-256 values can change between clean runs even with the
same source and commands. The evidence identifies hashes from its own run;
the recipe does not claim byte-identical archives across runs.
