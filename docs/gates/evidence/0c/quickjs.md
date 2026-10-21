# 0C-05 — Android QuickJS and yt-dlp/ejs device probe

## Pinned inputs and package construction

| Input | Version and SHA-256 | Source |
|---|---|---|
| QuickJS Android arm64 ELF | upstream 2026-06-04; `4db3b8aeba709b4907da59a87f1ab3f94585bae3a95f7b02c946b7732cd20185` | [Gate 0B attested source build](../0b/quickjs-android.txt) from the [official source archive](https://bellard.org/quickjs/) and NDK r30 |
| yt-dlp Unix zipapp | 2026.08.19; `1fa6733c37ea6fb51c99ad8fe785e7b7e5f3246c9b980230329d4fb72ed8d4d6` | [release asset](https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.19/yt-dlp); hash is in the Gate 0B verified signed `SHA2-256SUMS` |
| EJS inside that zipapp | 0.8.0 | `yt_dlp_ejs/_version.py` in the hash-checked zipapp; this matches [yt-dlp's release dependency](https://github.com/yt-dlp/yt-dlp/blob/2026.08.19/pyproject.toml) |
| Original library AAR | youtubedl-android 0.18.1; `579b5fb480892b1abc2b218c2089699d52759cc8d7ba256bf876453f0365faef` | [Maven Central artifact](https://repo.maven.apache.org/maven2/io/github/junkfood02/youtubedl-android/library/0.18.1/library-0.18.1.aar) and [0C-04 inventory](engine-package.md) |

`scripts/gate-0c/package-quickjs.ps1` checks the QuickJS and yt-dlp input
hashes and both Python package version files. It copies them to ignored
`work/android/0c-05/jniLibs/arm64-v8a/libqjs.so` and
`work/android/0c-05/res/raw/ytdlp`. The app Gradle source set includes those
inputs and selects the pinned QuickJS when it encounters the library's older
`libqjs.so`. Gradle still resolves the original `library`, `common`, and
`ffmpeg` 0.18.1 Maven modules. The APK verifier checks which bytes actually
landed in the APK; no AAR is modified and no active-job binary swap occurs.

The [tagged library implementation](https://github.com/yausername/youtubedl-android/blob/0.18.1/library/src/main/java/com/yausername/youtubedl_android/YoutubeDL.kt)
sets `--js-runtimes quickjs:<nativeLibraryDir>/libqjs.so` and an app cache
`TMPDIR`. Its `init_ytdlp` copies the raw resource only when no private zipapp
exists. `BundledEnginePackage.initialize` now checks that private zipapp hash
and atomically replaces an older copy from the pinned raw resource before
`YoutubeDL.init`; this happens before spike work starts. The engine package
interface carries selected versions and paths; FFmpeg build flags remain
unassumed. The application requests extracted native libraries so the
executable has a real filesystem path.

## Physical device verification

The exact entrypoint is
`powershell -NoProfile -File scripts/gate-0c/verify.ps1 -Case quickjs-device`
with `ANDROID_SERIAL` set. It builds the arm64 debug APK, checks the packaged
QuickJS and zipapp hashes, runs the Android instrumentation probe, and requires
five device log markers: QuickJS script execution from writable cache, yt-dlp
2026.08.19, EJS 0.8.0, QuickJS 2026-06-04 selected by yt-dlp, and a writable
yt-dlp cache. The instrumentation probe first plants an old private zipapp
placeholder so its replacement path is exercised. Its URL is the generic
`https://example.com/` with `--simulate`: no media is downloaded and a
successful extraction is not part of this check.

Full build, instrumentation, and logcat output stays ignored in
`work/android/0c-05/`.

## Result

The exact verifier exited **0** on 2026-10-20. The physical OnePlus BE2011
(`b1c28e0d`) reported Android API 29, `arm64-v8a`, and WebView
`155.0.8059.43`. Gradle's connected instrumentation run completed **1/1**
tests with zero failures. The local debug APK is 243,330,501 bytes, SHA-256
`3f3f6700d36bdbb5e9e4529741960506834afffb6cf739a60310585f14a67b62`.
Its inspected `lib/arm64-v8a/libqjs.so` and `res/raw/ytdlp` hashes match the
pinned inputs above, and it contains no other native ABI.

The test planted an old private zipapp, then confirmed its replacement by the
pinned archive hash. It executed the packaged QuickJS binary with a script in
`/data/user/0/com.zownload.app/cache/`, which printed
`ZOWNLOAD_QUICKJS_EXEC_OK`. yt-dlp's device log reported
`stable@2026.08.19 (zip)`, `yt_dlp_ejs-0.8.0`, and
`JS runtimes: quickjs-2026-06-04`. The test wrote and read a file in
`/data/user/0/com.zownload.app/cache/yt-dlp-device-probe` and passed that path
as `--cache-dir`. This proves startup and runtime selection; it does not yet
prove a YouTube extraction requiring JavaScript or an MP3 download. AC-30 is
the next task.

This task does not clear the Android native corresponding-source/build-input/
notice **OPEN RELEASE BLOCKER**. No Android APK or build may be published,
uploaded, attached to a release, or shared.
