# Third-party notices and Gate 0B redistribution plan

Zownload's own source from task 0C-01B onward uses
[GPL-3.0-or-later](../LICENSE). Copies of the earlier MIT-licensed history
remain under MIT for people who received them; this change does not revoke
those grants. The component licences below remain those components' own terms.
This audits the locked Gate 0B engine artifacts and the Gate 4A Linux
extension. Unpublished Windows and Linux draft packages now exist; no public
release has been made. Exact source
URLs and signatures are in [`engine-sources.md`](engine-sources.md), build
commands in [`engine-builds.md`](engine-builds.md), and observations in
[`license-audit.txt`](gates/evidence/0b/license-audit.txt). No engine binary
or source archive is tracked by Git.

The Gate 0B LGPL FFmpeg evidence below describes that exact desktop build.
It is not a repo-wide LGPL-only requirement. The selected Android library
has GPL components; its resolved package and corresponding-source inventory
remain Gate 0C work before any distribution.

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
and check them before deleting it. Each platform build needs its own
binary hashes, library inventories and relinking materials.

Gate 4A's Linux `ffmpeg` and `ffprobe` use the same locked FFmpeg 8.1.3,
encoder-only LAME 3.100, and zlib 1.3.2 sources. Their
[Linux build record](engine-builds.md#4a-04--linux-x64-package-engine-recipe)
gives the exact configuration and checks, and the
[Gate 4A evidence](gates/evidence/4a/4a-04.md) identifies the shipped Linux
binary hashes. Preserve the same FFmpeg, LAME, and zlib license texts and
Linux-specific link commands and relinking objects in the eventual versioned
source bundle. The unpublished draft is not a public compliance release.

## Android arm64-v8a FFmpeg 8.1.3, LAME and zlib

Gate 5A-04 builds FFmpeg 8.1.3 for arm64-v8a with --enable-gpl,
--disable-nonfree and --disable-version3. FFmpeg reports GPL version 2 or
later. The build links only the pinned LAME 3.100 encoder library and zlib
1.3.2 as external libraries; it excludes LAME's GPL-only mpglib decoder.
Neither x264 nor x265 is built. The source hashes, FFmpeg signature
verification, complete configure arguments, toolchain and local output hashes
are recorded in the [5A-04 build evidence](gates/evidence/5a/5a-04-ffmpeg.md).

| Component | Effective license in the Android build | Corresponding source and notice |
|---|---|---|
| FFmpeg 8.1.3 | GPL-2.0-or-later | ffmpeg-8.1.3.tar.xz, SHA-256 7138d28c96d9d3e3af4ee3d8cad72741f8ffb40da90c1112235dea3ecd3178a3; include upstream LICENSE.md and COPYING.GPLv2. |
| LAME 3.100 encoder library | LGPL-2.0-or-later, linked into the GPL FFmpeg executable | lame-3.100.tar.gz, SHA-256 ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e; include upstream COPYING and LICENSE; mpglib decoder is excluded. |
| zlib 1.3.2 | Zlib license | zlib-1.3.2.tar.gz, SHA-256 bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16; include the upstream root LICENSE. |

These locally built executables are not APK payloads and must not be shared.
Before an Android package is assembled, Gate 5A-06 must record the final
APK-bound hashes and complete source, build-input, notice and transitive
dependency inventory.

## Android CPython runtime

The local Android CPython package is built from CPython `3.14.10` under
PSF-2.0. Its source archive, source-built native dependencies, and package
sources are pinned in [`engine-sources.md`](engine-sources.md#gate-5a-android-python-runtime-lock--owner-approved-2026-11-22).
The runtime package retains upstream package metadata and license files under
`site-packages/*.dist-info/licenses/` where supplied by each source archive.

| Component | License | Runtime or build use |
|---|---|---|
| CPython `3.14.10` | PSF-2.0 | Embedded interpreter and standard library. |
| bzip2 `1.0.8` | bzip2 license | Source-built CPython compression dependency. |
| libffi `3.4.4` | MIT | Source-built CPython foreign-function dependency. |
| OpenSSL `3.5.9` | Apache-2.0 | Source-built TLS and cryptography dependency. |
| SQLite `3.53.4` | Public domain | Source-built CPython database dependency. |
| xz/liblzma `5.4.6` | LGPL-2.1-or-later | Source-built CPython compression dependency. |
| zstd `1.5.7` | BSD-3-Clause | Source-built CPython compression dependency. |
| Brotli `1.2.0` | MIT | yt-dlp HTTP compression support. |
| certifi `2026.7.22` | MPL-2.0 | CA certificate bundle. |
| charset-normalizer `3.5.0` | MIT | Requests response decoding. |
| idna `3.18` | BSD-3-Clause | Internationalized URL handling. |
| Mutagen `1.48.1` | GPL-2.0-or-later | Media metadata support. |
| pycryptodomex `3.23.0` | BSD-2-Clause and public domain | Optional yt-dlp decryption support. |
| requests `2.34.2` | Apache-2.0 | HTTP support. |
| urllib3 `2.7.0` | MIT | HTTP transport. |
| websockets `17.0.1` | BSD-3-Clause | WebSocket support. |
| yt-dlp `2026.08.19` | Unlicense | Download engine Python source. |
| yt-dlp-ejs `0.8.0` | Unlicense; solver scripts include Meriyah ISC and Astring MIT | JavaScript challenge solver source. |
| setuptools `84.1.0` | MIT | Host build-only tool; not shipped in Android runtime. |
| flit-core `3.12.0` | BSD-3-Clause | Host-only PEP 517 backend for idna. |
| hatchling `1.33.0` | MIT | Host-only PEP 517 backend for yt-dlp-ejs and urllib3. |
| hatch-vcs `0.5.0` | MIT | Host-only Hatch version plugin for yt-dlp-ejs and urllib3. |
| setuptools-scm `10.3.4` | MIT | Host-only VCS version plugin dependency. |
| packaging `26.3` | Apache-2.0 or BSD-2-Clause | Host-only build backend dependency. |
| pathspec `1.1.1` | MPL-2.0 | Host-only Hatchling dependency. |
| pluggy `1.7.0` | MIT | Host-only Hatchling dependency. |
| tomlkit `0.14.0` | MIT | Host-only Hatchling dependency. |
| trove-classifiers `2026.9.21.13` | Apache-2.0 | Host-only Hatchling dependency. |
| vcs-versioning `2.6.0` | MIT | Host-only setuptools-scm dependency. |

The [5A-06 package provenance evidence](gates/evidence/5a/5a-06-package-provenance.md)
and [machine-readable APK manifest](gates/evidence/5a/5a-06-apk-engine-manifest.json)
record the complete arm64 engine payload, all 22 transitive engine components,
the 24 pinned corresponding source materials, source-build hashes, and notice
coverage. The local package verifier passed. Owner review is still required
before any Android APK/build is shared or the distribution blocker is closed.

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
| Android arm64/API 24 | Gate 0B CI: `4db3b8aeba709b4907da59a87f1ab3f94585bae3a95f7b02c946b7732cd20185`; Gate 5A-05 checkout: `65ebedfeaa87856788ae8ee508f9ed7836dbec5f7c616b88490a5edee3881ffd` | Both use the locked NDK r30 recipe; QuickJS debug info includes the absolute build path, so artifact hashes vary by checkout root. See [5A-05 build evidence](gates/evidence/5a/5a-05-quickjs.md) and [Gate 0B ELF record](gates/evidence/0b/quickjs-android.txt). APK staging and final provenance audit are Gate 5A-06. |

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
