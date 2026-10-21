# 0C-04 — Published Android engine package probe

Inspected on 2026-10-20 on Windows, without an Android device. This probe
temporarily added the approved `0.18.1` `library` and `ffmpeg` Maven modules and
compiled a minimal Kotlin analyze/download-one/cancel adapter. The dependency
and adapter were removed from the branch after the hard redistribution gap
below was confirmed. This is **not a completed 0C-04 integration**.

## Resolved artifacts and package proof

Gradle `universalDebugRuntimeClasspath` resolved the following Maven Central
artifacts. The first two AAR hashes match the independent Maven Central SHA-256
values recorded in [0C-01](library-audit.md); `common` is an actual new transitive
module. All three versioned POMs declare GPL-3.0 and point to the
[`0.18.1` upstream tag](https://github.com/yausername/youtubedl-android/tree/d725d5c9a18c3a99a13ee0308bf78275dc310760).

| Maven AAR | Bytes | SHA-256 |
|---|---:|---|
| `library-0.18.1.aar` | 59,213,110 | `579b5fb480892b1abc2b218c2089699d52759cc8d7ba256bf876453f0365faef` |
| `ffmpeg-0.18.1.aar` | 139,371,444 | `0a87ffa6cf912b0fe76c1a99b9107f543ee2f247935fae2c71f0822eb7bc5f49` |
| `common-0.18.1.aar` | 5,186 | `e0c0530bdbdf203e1598e900085d3582e27360731872872f3a67f23a9b24c0b5` |

The exact `npm run android:debug` command exited 0 using pinned Node
24.22.0/npm 11.19.1, Corretto 21.0.11.10.1, Rust 1.99.1, and NDK r30. Gradle
compiled `AndroidEngineAdapter.class`. The resulting debug APK was 265,205,621
bytes, SHA-256
`956cd82c6de20907fd61e55b37bf4d1611602696af13e3a04af0c54846199176`.
Its only native ABI was `arm64-v8a`. It contained `libpython.so`,
`libpython.zip.so`, `libqjs.so`, `libffmpeg.so`, `libffmpeg.zip.so`,
`libffprobe.so`, and Zownload's Rust library. The six upstream APK entries
matched the same-named AAR entries byte for byte by SHA-256. This proves
compilation and packaging only; no adapter method or binary ran on a device.

## Actual bundled inputs

The published `library` AAR contains `res/raw/ytdlp` (SHA-256
`89a0d9058ea9018e380b7771898ff46e393a1986dcd13fef331693c87ce1fca4`),
`libpython.so`, `libpython.zip.so`, and `libqjs.so` for arm64. The Python
archive has **1,007 entries**, including a Python 3.12 tree and **189 `.so`
named entries**. The `ffmpeg` AAR contains `libffmpeg.so`, `libffprobe.so`, and
`libffmpeg.zip.so`; its archive has **184 entries**, including **165 `.so`
named entries** such as `libmp3lame.so`, `libx264.so`, and `libx265.so`.
[The 361-row native manifest](engine-package-native.tsv) gives the exact
path, byte count, and SHA-256 for the six top-level native libraries, the
bundled `ytdlp`, and every nonempty `.so` named entry inside the two archives.
Neither nested archive contains a path with `LICENSE`, `COPYING`, or
`copyright` in its name.

The bundled `ytdlp` is yt-dlp **2025.11.12** with ejs **0.3.1**, and the
bundled arm64 QuickJS has the `2025-04-26` version string. These differ from
the Gate 0B pins **2026.08.19**, ejs **0.8.0**, and QuickJS **2026-06-04**;
substitution and device proof remain assigned to 0C-05. The identical
`libffmpeg.so` hash from [0C-01](library-audit.md) identifies FFmpeg **7.1.1**
with `--enable-gpl`, `--enable-version3`, `--enable-libmp3lame`,
`--enable-libx264`, and `--enable-libx265`; that audit preserves the complete
embedded configure string and NDK dependency probe.

Gradle's resolved tree adds `common:0.18.1`, `commons-io:2.5`, and
`commons-compress:1.12` through the engine modules. It resolves the engine's
older requested Jackson modules to the app's existing `2.15.3` and its
AndroidX/Kotlin requests to the app's existing versions. A full transitive
licence and notice audit remains open; the module-level GPL POM declarations
do not describe every native package inside the Python and FFmpeg archives.

## Corresponding-source and notice gap — hard stop

The tagged [FFmpeg](https://github.com/yausername/youtubedl-android/blob/d725d5c9a18c3a99a13ee0308bf78275dc310760/BUILD_FFMPEG.md)
and [Python](https://github.com/yausername/youtubedl-android/blob/d725d5c9a18c3a99a13ee0308bf78275dc310760/BUILD_PYTHON.md)
build notes use an unpinned `git clone` of Termux packages and arm32 examples.
The Python note lists 3.7.2 packages while the published arm64 archive contains
a Python 3.12 tree. Neither note identifies the Termux commit, exact source
tarballs and patches, or build recipes/configuration for the arm64 binaries
and their packaged native dependencies. The AAR POMs
link the project repository but do not fill these binary-specific gaps. The
two nested archives have no licence/notice paths. Therefore the corresponding
source, build-configuration, and notices needed to distribute these exact
native binaries are **not established**. The complete native file inventory
records what must be traced; it is not a corresponding-source bundle.

**Gate 0C stop rule invoked.** A missing hard GPL redistribution input fails
0C-04 acceptance. Do not merge an engine dependency, proceed to 0C-05, or
claim a downloadable or distributable Android build on this evidence. The
owner must decide whether to obtain and verify complete corresponding source
and notices for these exact binaries or reopen the [architecture options](architecture-decision.md).
Legal review before a public release remains open.

## Verification scope

The local ignored logs are `work/android/0c-04-dependencies.log` and
`work/android/0c-04-build.log`. The AAR files were read from Gradle's resolved
cache, not a guessed source tree. Archive inspection counted entries and
SHA-256 values from those AAR bytes and checked APK entry hashes. The exact
`powershell -NoProfile -File scripts/gate-0c/verify.ps1 -Case engine-package`
command verifies the recorded hashes, native manifest, and explicit stop
result; it does not claim the blocked integration is complete.
