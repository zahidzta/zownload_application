# 0C-01 — Android engine documentation audit

Audited 2026-10-20. This is a source and artifact inspection, not a device run or
an Android integration. The selected **candidate**, not an approved dependency,
is `io.github.junkfood02.youtubedl-android:{library,ffmpeg}:0.18.1`, tag
[`0.18.1`](https://github.com/yausername/youtubedl-android/releases/tag/0.18.1),
commit [`d725d5c9a18c3a99a13ee0308bf78275dc310760`](https://github.com/yausername/youtubedl-android/tree/d725d5c9a18c3a99a13ee0308bf78275dc310760).
The release was published 2025-11-16. The tag's README gives the Maven Central
coordinates and calls `aria2c` optional. The checked Maven POMs declare both
`library` and `ffmpeg` as **GPL-3.0**. No Gradle dependency was added.

## JS runtime and yt-dlp/ejs pair

- Tagged [`YoutubeDL.kt:31-53`](https://github.com/yausername/youtubedl-android/blob/d725d5c9a18c3a99a13ee0308bf78275dc310760/library/src/main/java/com/yausername/youtubedl_android/YoutubeDL.kt#L31-L53) takes `libqjs.so` from Android's `nativeLibraryDir`, uses app `cacheDir` for `TMPDIR`, and places the Python/FFmpeg package dirs in `LD_LIBRARY_PATH`. [`executeImpl:183-226`](https://github.com/yausername/youtubedl-android/blob/d725d5c9a18c3a99a13ee0308bf78275dc310760/library/src/main/java/com/yausername/youtubedl_android/YoutubeDL.kt#L183-L226) adds `--js-runtimes quickjs:<absolute native path>` and executes Python plus yt-dlp. [`YoutubeDLRequest`](https://github.com/yausername/youtubedl-android/blob/d725d5c9a18c3a99a13ee0308bf78275dc310760/library/src/main/java/com/yausername/youtubedl_android/YoutubeDLRequest.kt) supports arbitrary command options. This supports the argument and writable-temp call path **in source**, but device execution remains unproved. yt-dlp's [EJS guide](https://github.com/yt-dlp/yt-dlp/wiki/EJS) says QuickJS needs temporary script files.
- The tagged `library/src/main/res/raw/ytdlp` is a Python zipapp. Inspection of its internal `yt_dlp/version.py` and `yt_dlp_ejs/_version.py` found **yt-dlp 2025.11.12 + ejs 0.3.1**, not Gate 0B's locked **2026.08.19 + 0.8.0**. The tagged arm64 `libqjs.so` contains the string `2025-04-26`, not the required upstream `2026-06-04`; an embedded string alone does not prove executable behavior. `PROJECT.md:370` and the [0B-09 build evidence](../0b/quickjs-android.txt) require the locally built 2026-06-04 runtime (SHA-256 `4db3b8aeba709b4907da59a87f1ab3f94585bae3a95f7b02c946b7732cd20185`). Whether the library's hard-coded native path can be packaged with that build, and whether the newer matched yt-dlp/ejs zipapp runs in its Python environment, remain device/package checks.

## Update and rollback

- [`updateYoutubeDL`](https://github.com/yausername/youtubedl-android/blob/d725d5c9a18c3a99a13ee0308bf78275dc310760/library/src/main/java/com/yausername/youtubedl_android/YoutubeDL.kt#L263-L295) is synchronized and accepts a channel URL; [`YoutubeDLUpdater`](https://github.com/yausername/youtubedl-android/blob/d725d5c9a18c3a99a13ee0308bf78275dc310760/library/src/main/java/com/yausername/youtubedl_android/YoutubeDLUpdater.kt#L16-L108) fetches GitHub `releases/latest` by default, selects an asset named `yt-dlp`, deletes the existing update directory, copies the download, and stores its release tag. Its catch block restores the bundled baseline only when deletion/copy throws. No SHA-256, signature, exact version pin, ejs-pair check, active-process exclusion, post-install health check, or rollback of an installed bad update appears in this tagged updater API/code.
- The initial bundled zipapp is preserved as an app raw resource and copied to `noBackupFilesDir` when absent. This is a **baseline source**, not proof of a usable rollback path after a bad update. A custom `UpdateChannel` URL might point to a fixed release endpoint, but source review found no digest verification; using it as a pinned updater would still fail `PROJECT.md:376`. No replacement updater architecture is selected in this task.

## FFmpeg package, native dependencies, and license

- Tag `0.18.1` has `ffmpeg/src/main/jniLibs/{arm64-v8a,armeabi-v7a,x86,x86_64}/libffmpeg.so`, `libffprobe.so`, and `libffmpeg.zip.so` in the [versioned tree](https://github.com/yausername/youtubedl-android/tree/d725d5c9a18c3a99a13ee0308bf78275dc310760/ffmpeg/src/main/jniLibs). The arm64 `libffmpeg.so` contains `version 7.1.1` and an `aarch64` configure line. Its dynamic `NEEDED` entries include `libavdevice.so.61`, `libavfilter.so.10`, `libavformat.so.61`, `libavcodec.so.61`, `libpostproc.so.58`, `libswresample.so.5`, `libswscale.so.8`, `libavutil.so.59`, `libm.so`, and `libc.so`; its `RUNPATH` is `/data/data/com.termux/files/usr/lib`. The 35,624,931-byte arm64 `libffmpeg.zip.so` has 184 entries, including `libmp3lame.so`, `libx264.so.164`, and `libx265.so`; `libavcodec.so.61.19.101` is present. Packaging and run-time resolution are still untested.
- The inspected tagged arm64 executable embeds **`--enable-gpl`**, `--enable-version3`, `--enable-libmp3lame`, `--enable-libx264`, and `--enable-libx265`. That is direct evidence of a GPL FFmpeg configuration, despite the MP3 encoder's presence. The tagged [`BUILD_FFMPEG.md`](https://github.com/yausername/youtubedl-android/blob/d725d5c9a18c3a99a13ee0308bf78275dc310760/BUILD_FFMPEG.md) describes a Termux build without a Termux commit, FFmpeg source digest, complete dependency/source inventory, or the exact flags used for this binary. [FFmpeg's own license checklist](https://ffmpeg.org/legal.html) requires an LGPL build to omit `--enable-gpl` and `--enable-nonfree`, and calls out libx264. Thus the candidate's tagged FFmpeg **fails** the confirmed LGPL-compatible constraint in `PROJECT.md:388`. MP3 encoding has not been run on a device.
- The full embedded configure argument list, extracted from the tagged arm64 `libffmpeg.so`, is below. The `android-r28c-api-24-v1` build path is also different from Zownload's NDK r30 pin. This binary string records upstream build inputs; it is not a reproducible source recipe by itself.

  ```text
  --arch=aarch64 --as=aarch64-linux-android-clang --cc=aarch64-linux-android-clang
  --cxx=aarch64-linux-android-clang++ --nm=llvm-nm --ar=llvm-ar --ranlib=llvm-ranlib
  --pkg-config=/home/builder/.termux-build/_cache/android-r28c-api-24-v1/bin/pkg-config
  --strip=llvm-strip --cross-prefix=aarch64-linux-android- --disable-indevs
  --disable-outdevs --enable-indev=lavfi --disable-static --disable-symver
  --enable-cross-compile --enable-gnutls --enable-gpl --enable-version3 --enable-jni
  --enable-lcms2 --enable-libaom --enable-libass --enable-libbluray --enable-libdav1d
  --enable-libfontconfig --enable-libfreetype --enable-libfribidi --enable-libgme
  --enable-libharfbuzz --enable-libmp3lame --enable-libopencore-amrnb
  --enable-libopencore-amrwb --enable-libopenmpt --enable-libopus --enable-librav1e
  --enable-librubberband --enable-libsoxr --enable-libsrt --enable-libssh
  --enable-libsvtav1 --enable-libtheora --enable-libv4l2 --enable-libvidstab
  --enable-libvmaf --enable-libvo-amrwbenc --enable-libvorbis --enable-libvpx
  --enable-libwebp --enable-libx264 --enable-libx265 --enable-libxml2
  --enable-libxvid --enable-libzimg --enable-libzmq --enable-mediacodec
  --enable-opencl --enable-shared --prefix=/data/data/com.termux/files/usr
  --target-os=android --extra-libs=-landroid-glob --disable-vulkan --enable-neon
  --disable-libfdk-aac
  ```
- The [tagged repository license](https://github.com/yausername/youtubedl-android/blob/d725d5c9a18c3a99a13ee0308bf78275dc310760/LICENSE) and the versioned Maven [library POM](https://repo.maven.apache.org/maven2/io/github/junkfood02/youtubedl-android/library/0.18.1/library-0.18.1.pom) / [ffmpeg POM](https://repo.maven.apache.org/maven2/io/github/junkfood02/youtubedl-android/ffmpeg/0.18.1/ffmpeg-0.18.1.pom) identify GPL-3.0. This conflicts with the confirmed MIT/LGPL distribution plan (`PROJECT.md:388`). A release using these modules would require an owner-approved licensing/architecture change and a corresponding-source, build-configuration, and dependency-notices plan; this audit is not a legal opinion.

## Artifact provenance and further proof

The upstream raw tagged files inspected here had these locally computed SHA-256
values; Maven Central's separate `.aar.sha256` files supply the candidate AAR
digests. No AAR was resolved into the app, so equivalence between the tagged
files and the published AAR contents has **not** been claimed.

| Artifact | SHA-256 | Provenance / next check |
|---|---|---|
| `library-0.18.1.aar` | `579b5fb480892b1abc2b218c2089699d52759cc8d7ba256bf876453f0365faef` | [Maven Central checksum](https://repo.maven.apache.org/maven2/io/github/junkfood02/youtubedl-android/library/0.18.1/library-0.18.1.aar.sha256); resolve and inspect only after owner decision |
| `ffmpeg-0.18.1.aar` | `0a87ffa6cf912b0fe76c1a99b9107f543ee2f247935fae2c71f0822eb7bc5f49` | [Maven Central checksum](https://repo.maven.apache.org/maven2/io/github/junkfood02/youtubedl-android/ffmpeg/0.18.1/ffmpeg-0.18.1.aar.sha256); compare embedded native files if integration is authorized |
| tagged arm64 `ytdlp` | `89a0d9058ea9018e380b7771898ff46e393a1986dcd13fef331693c87ce1fca4` | [raw resource](https://github.com/yausername/youtubedl-android/blob/d725d5c9a18c3a99a13ee0308bf78275dc310760/library/src/main/res/raw/ytdlp); inspect zipapp versions |
| tagged arm64 `libqjs.so` | `a0fe160a8cd76eec34132f945664856e96687d701e3b1ff28dff44ea1fad13bc` | [native file](https://github.com/yausername/youtubedl-android/blob/d725d5c9a18c3a99a13ee0308bf78275dc310760/library/src/main/jniLibs/arm64-v8a/libqjs.so); replace only with approved pinned build |
| tagged arm64 `libffmpeg.so` | `1b8d5c371ea79e6e7a1930b31f2ad6a2731e48d75ceddc9c36dffda6e0092401` | [native file](https://github.com/yausername/youtubedl-android/blob/d725d5c9a18c3a99a13ee0308bf78275dc310760/ffmpeg/src/main/jniLibs/arm64-v8a/libffmpeg.so); inspected with NDK r30 `llvm-readelf` and binary strings |
| tagged arm64 `libffmpeg.zip.so` | `4664a895283f9f31786be39b0c484c1f96631f02c7c7f9c70a4a4a2da324a092` | [native dependency archive](https://github.com/yausername/youtubedl-android/blob/d725d5c9a18c3a99a13ee0308bf78275dc310760/ffmpeg/src/main/jniLibs/arm64-v8a/libffmpeg.zip.so); inspect complete transitives before any distribution |

Inspection used direct downloads from the commit-pinned `raw.githubusercontent.com`
paths above, then `Get-FileHash -Algorithm SHA256`. The following local
read-only probes exited 0 on Windows; device/API: **none**; target ABI:
**arm64-v8a**:

```powershell
python -c "import zipfile; z=zipfile.ZipFile('work/android/library-audit/binaries/ytdlp'); print(z.read('yt_dlp/version.py').decode()); print(z.read('yt_dlp_ejs/_version.py').decode())"
python -c "import re; b=open('work/android/library-audit/binaries/libffmpeg.so','rb').read(); print([x.decode() for x in re.findall(rb'[ -~]{20,}',b) if b'configuration: --arch' in x][0])"
python -c "import zipfile; z=zipfile.ZipFile('work/android/library-audit/binaries/libffmpeg.zip.so'); print(len(z.infolist())); print([n for n in z.namelist() if 'mp3lame' in n or 'x264' in n or 'x265' in n])"
& 'C:\Users\zahid\AppData\Local\Android\Sdk\ndk\30.0.16248370\toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-readelf.exe' -d work/android/library-audit/binaries/libffmpeg.so
```

The second command exposed `--enable-gpl`, `--enable-libx264`, and
`--enable-libx265`; the third exposed `libmp3lame.so` and GPL codec libraries;
`llvm-readelf` gave the `NEEDED` and `RUNPATH` entries above. These observations
trigger the hard stop, rather than an Android execution failure.

## Foreground-service type for owner decision

Android's [current service-type table](https://developer.android.com/develop/background-work/services/fgs/service-types) explicitly lists download and local file processing under `dataSync`. **Proposal:** choose `dataSync` for the user-started download/convert spike, with `FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_DATA_SYNC` manifest permissions, `android:foregroundServiceType="dataSync"`, and matching `startForeground` type. `mediaProcessing` fits conversion but not the main transfer; `mediaPlayback` fits playback, which this app does not perform. This is a proposal, not owner approval. Android 15's [timeout rules](https://developer.android.com/develop/background-work/services/fgs/timeout) give `dataSync` six hours per 24 hours while backgrounded, shared across the app; `Service.onTimeout(int,int)` must stop the service within seconds. Foreground interaction resets the budget. The later service task must test timeout and cancellation on physical API 35+ hardware.

## Stop result and documentation consulted

**Stop rule invoked.** GPL-3.0 modules and a GPL-configured FFmpeg conflict with
the confirmed distribution requirement; the updater also lacks verified pinning
and bad-update rollback. Android integration tasks remain closed until the owner
chooses an architecture and, if desired, explicitly changes the affected
requirement. Task **0C-01A — owner Android engine/licensing decision** is next.

Context7 was consulted on 2026-10-20 for current youtubedl-android API, Android
foreground-service requirements, and Tauri 2 mobile-plugin development. Its
youtubedl examples were checked against the tagged code above; runtime claims
come from the tagged code and binaries. The [Tauri mobile-plugin guide](https://v2.tauri.app/develop/plugins/develop-mobile/)
identifies the Rust/Kotlin bridge for a later task. No plugin code was written.
