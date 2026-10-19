# Third-party notices and Gate 0B redistribution plan

Zownload's own source uses the [MIT License](../LICENSE). This audits the
locked Gate 0B engine artifacts; no release package exists yet. Exact source
URLs and signatures are in [`engine-sources.md`](engine-sources.md), build
commands in [`engine-builds.md`](engine-builds.md), and observations in
[`license-audit.txt`](gates/evidence/0b/license-audit.txt). No engine binary
or source archive is tracked by Git.

For each release, ship a versioned bundle beside the installer/APK with the
**verbatim** license texts below, exact corresponding source and patches,
build configuration, relinking materials where required, and a SHA-256
manifest. The release URL and bundle hash must be recorded after packaging;
the hashes below identify only the audited Gate 0B inputs and outputs.

## FFmpeg, LAME, zlib and MinGW-w64 runtime

| Component and effective license | Gate 0B Windows x64 artifact SHA-256 | Source SHA-256 and notice text |
|---|---|---|
| FFmpeg 8.1.3, LGPL-2.1-or-later | `ffmpeg.exe` `fa050630ddf5b7c3303d8dab5e5a42e7023547fb78ec9b90b5be0a4f788a7e66`; `ffprobe.exe` `bf44a50347aaba3e433c34c8c881d67eeaca41001577482ce3ba69b780824ec7` | `ffmpeg-8.1.3.tar.xz` `7138d28c96d9d3e3af4ee3d8cad72741f8ffb40da90c1112235dea3ecd3178a3`; ship `LICENSE.md`, `COPYING.LGPLv2.1` and source notices. |
| LAME 3.100 encoder, GNU Library GPL-2.0-or-later | Statically linked into those executables; 0B-11 `libmp3lame.a` was `4f8170f664a4afc01a3f7bb60432543a0bb8a1238f380de415ec0fbfd735318c` | `lame-3.100.tar.gz` `ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e`; ship `COPYING`, `LICENSE`, and encoder source headers. |
| zlib 1.3.2, Zlib license | Statically linked; 0B-11 `libz.a` was `e480ab641a60b9d3b8e3e577290e15556572da6e08b67d255ba8a61ce4947957` | `zlib-1.3.2.tar.gz` `bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16`; ship root `LICENSE`. |
| Statically linked MinGW-w64 runtime, permissive terms with notice conditions | Included in the Windows QuickJS and FFmpeg outputs | w64devkit 2.10.1 archive `add1edf984ce4d473cfeb7c52e0ab38db73a855bba6c7f564d5e16648eb2896a`; ship `COPYING.MinGW-w64-runtime.txt`, SHA-256 `ecff91ddb5799c8b79a4bdb576921b9c3e2989783fd1944527e8eb9b41a5ff5f`. |

The executables report LGPL version 2.1 or later. Their configuration has
`CONFIG_GPL=0`, `CONFIG_NONFREE=0`, `CONFIG_VERSION3=0`, enables only external
`libmp3lame` and `zlib`, and omits `--enable-gpl`, `--enable-nonfree`, and
`--enable-version3`. LAME's GPL-only `mpglib` decoder was excluded. The
[0B-11 evidence](gates/evidence/0b/ffmpeg-windows.txt) records the exact
configuration and imported DLLs.

Because these libraries are statically linked, each Windows release must
provide the matching source, patches, full build/link commands, and relinkable
object files or another LGPL-compliant relinking method. The ignored recipe
directory currently contains intermediate objects; a release must package
and check them before deleting it. Later platform builds need separate
binary hashes, library inventories and relinking materials.

## QuickJS

QuickJS 2026-06-04 is MIT-licensed. Ship its unmodified source archive
`quickjs-2026-06-04.tar.xz` (SHA-256
`b376e839b322978313d929fd20663b11ba58b75df5a46c126dd19ea2fa70ad2a`)
and verbatim root `LICENSE`. No source patch was applied.

| Target | `qjs` SHA-256 | Build configuration and evidence |
|---|---|---|
| Windows x64 | `bec67f8f87fa22958d3ab8be5508088116b8bff90032323d82c94545e1698b83` | [`build-quickjs.ps1`](../scripts/gate-0b/build-quickjs.ps1), [evidence](gates/evidence/0b/quickjs-windows.txt); ship MinGW-w64 notice above. |
| Linux x64 | `50263177cb921024aabc0807a31d71be7fa3c22f0c5824c3c6a2d1cf920f300c` | [`build-quickjs.sh`](../scripts/gate-0b/build-quickjs.sh), [evidence](gates/evidence/0b/quickjs-linux.txt). |
| macOS x64 | `554102a8a9c0d0c5e24cd138ad7a790f330fd926310c01009265589a446ef90a` | Same script, [evidence](gates/evidence/0b/quickjs-macos-x64.txt). |
| macOS arm64 | `fba79a316a53ed58a17709a39c173218f8bc825831094b6033ce0510a713bb43` | Same script, [evidence](gates/evidence/0b/quickjs-macos-arm64.txt). |
| Android arm64/API 24 | `4db3b8aeba709b4907da59a87f1ab3f94585bae3a95f7b02c946b7732cd20185` | Same script with NDK r30, [evidence](gates/evidence/0b/quickjs-android.txt); APK packaging is still pending. |

## Official yt-dlp executables and yt-dlp-ejs

yt-dlp 2026.08.19's own code uses the Unlicense; its verbatim text is
`yt-dlp/LICENSE` in the locked source tarball. The official PyInstaller
executables are **GPL-3.0-or-later combined works**, per the tagged
[licensing section](https://github.com/yt-dlp/yt-dlp/blob/2026.08.19/README.md#licensing).
Each executable embeds `THIRD_PARTY_LICENSES.txt`, with full text for 45
open-source entries. Extract and ship that file verbatim, the Unlicense, and
GPL-3.0-or-later text. The Windows file uses CRLF and the Unix files LF;
their normalized contents match. The inventory must not be reduced to the
`pyproject.toml` dependency list.

| Artifact | SHA-256 | Embedded `THIRD_PARTY_LICENSES.txt` SHA-256 |
|---|---|---|
| `yt-dlp.exe`, Windows x64 | `66674953fe251b89f4d08c5f0e35e0728679bd67ab3d7d05c0562af101dd3e7a` | `5b7bc105c562b81b90d1a2cd5a8cc8b336ee107ae0ae81ce58450cd8b1bc2ad4` |
| `yt-dlp_linux`, Linux x64 | `58162f9bfdc27458ea47bfcb311cf47028f17d8154a8bf7d689861d46399230a` | `472aefe951c7db35e1657c1d13fd337140511ed6f2b329205105ad441c5a02b7` |
| `yt-dlp_macos`, macOS universal | `0f192b7ec147ab6288885d6351d9ab67367640029b4377576ef46dd79cf7b202` | `472aefe951c7db35e1657c1d13fd337140511ed6f2b329205105ad441c5a02b7` |

The locked `yt-dlp.tar.gz` source is SHA-256
`072aad4f2a7604e92155f61a275a4752dc64046c8f6d90df3710525d94cd37c1`.
EJS 0.8.0's source tarball is SHA-256
`d5fa1639f63b5c4af8d932495f60689d5370f1a095782c944f7f62a303eb104e`;
its wheel is `79300e5fca7f937a1eeede11f0456862c1b41107ce1d726871e0207424f4bdb4`.
All three executables embed the wheel's exact `core.min.js` and `lib.min.js`
bytes. EJS's own source is Unlicense; its solver scripts include Meriyah ISC
and Astring MIT. Ship the EJS source, wheel `licenses/LICENSE`, and the
Meriyah/Astring notices from the embedded inventory.

The [audit inventory](gates/evidence/0b/license-audit.txt) names all 45
entries and their declared licenses. Its digest identifies the complete
texts, which remain extractable from each pinned executable. The release
source bundle must cover the versions actually embedded, including Python
and native packages. Obtain and checksum their corresponding sources,
publish build configuration and patches, and map each embedded component to
its source in the release manifest. The yt-dlp tarball alone does not contain
the bundled dependencies or PyInstaller build scripts; use immutable commit
`3a08beaf031ab68f966401ead017ac81fe8486cf` for the upstream `bundle/`
recipe and requirements, then compare with the binary inventory.

The executables also include a PyInstaller bootloader. Its
[GPL-2.0-or-later bootloader exception](https://pyinstaller.org/en/stable/license.html)
allows distribution under the dependency-compatible effective license. Ship
its applicable `COPYING.txt`/exception text and exact source/build revision
in the release bundle, with a source checksum. The whole executable hashes
above cover the audited output.

**Windows proprietary runtime:** The official `yt-dlp.exe` includes
`VCRUNTIME140.dll`, `ucrtbase.dll`, and `api-ms-win-*` forwarder DLLs. These
follow [Microsoft's Visual C++ runtime terms](https://learn.microsoft.com/cpp/windows/redistributing-visual-cpp-files)
and [Universal CRT deployment terms](https://learn.microsoft.com/cpp/windows/universal-crt-deployment),
which are separate from the embedded open-source file. Include applicable
Microsoft terms and verify redistribution entitlement for the release
package. These proprietary components have no public corresponding-source
obligation; record their per-file hashes and versions at packaging. Stop a
release if permission or required terms cannot be established.

The Gate 0B audit proves the fixed binaries, source archives, embedded
notices and release plan. It does not claim that dependency sources,
relinkable objects, Microsoft entitlement or a release source bundle have
already been published.
