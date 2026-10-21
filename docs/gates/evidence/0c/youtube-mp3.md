# 0C-06 — Real YouTube MP3 in MediaStore Downloads

Verified on 2026-10-21 with the exact gate entrypoint:

```powershell
$env:JAVA_HOME = 'C:\Users\zahid\AppData\Local\Temp\zownload-0a-10-corretto\jdk21.0.11_10'
$env:ANDROID_SERIAL = 'b1c28e0d'
$env:ZOWNLOAD_ANDROID_YOUTUBE_URL = 'https://www.youtube.com/watch?v=uW13KuRrg1g'
powershell -NoProfile -File scripts/gate-0c/verify.ps1 -Case youtube-mp3
```

The URL is the locked, rights-cleared `youtube-short` fixture in
[Gate 0B fixtures](../0b/fixtures.md). The verifier rejects a missing URL and
does not replace it. The device was a physical OnePlus BE2011, Android API 29,
`arm64-v8a`. Corretto reported `21.0.11.10.1`. The local Node/npm used by this
run were `24.14.0`/`11.21.0`; the project pins remain `24.22.0`/`11.19.1`.

## Result

The exact command exited **0**. Its instrumentation test completed **1/1**
tests. The test loaded the Tauri WebView and invoked the contract's
`enqueue_download` command with a single MP3 request at 128 kbps. Rust
validated the request and called the Kotlin mobile plugin. Kotlin ran the
pinned engine on a worker thread, converted the YouTube audio in private
cache, copied it into a pending MediaStore Downloads row, set `IS_PENDING=0`,
and verified the published content URI by reading it back. The Rust call
returned after publication. There is no Kotlin queue. The temporary Rust
one-item guard and `get_queue` stub are replaced by the durable queue in
**0C-07**.

Two earlier attempts were setup/test-harness failures: the shell's original
`JAVA_HOME` pointed to an incomplete Android Studio JBR, and the first
instrumentation harness timed out its WebView callback after 10 seconds while
the engine was still running. The final run used the pinned Corretto JDK and
waited for the complete native call.

Selected device log lines:

```text
ENGINE [debug] yt-dlp version stable@2026.08.19 from yt-dlp/yt-dlp [594bd50c2] (zip)
ENGINE [debug] Optional libraries: Cryptodome-3.23.0, mutagen-1.47.0, sqlite3-3.50.4, yt_dlp_ejs-0.8.0
ENGINE [debug] JS runtimes: quickjs-2026-06-04
ENGINE [debug] ffmpeg command line: .../libffmpeg.so ... -acodec libmp3lame -b:a 128.0k .../audio.mp3
ENGINE [ExtractAudio] Destination: .../audio.mp3
PUBLISHED uri=content://media/external/downloads/9623 name=Zownload-0C06-ae8504a6-32a6-40c7-9d40-029fdaa7d3e9.mp3 mime=audio/mpeg sha256=3a8e6ff5c2d2ae91216dfd4747ea4b9223d0545b25146683ff99a3c814ec1cda bytes=236588
TAURI_RESULT OK:ae8504a6-32a6-40c7-9d40-029fdaa7d3e9
```

The Android `content query` read the published row as `_id=9623`,
`mime_type=audio/mpeg`, `is_pending=0`, `_size=236588`, and
`relative_path=Download/`. A query for pending Downloads rows returned
`No result found`. The verifier pulled the user's Downloads file, matched
its SHA-256 and length against the bytes read through the content URI, and
probed it with the pinned Gate 0B FFprobe 8.1.3 binary:

| Property | Observed |
|---|---|
| SHA-256 | `3a8e6ff5c2d2ae91216dfd4747ea4b9223d0545b25146683ff99a3c814ec1cda` |
| Size | 236,588 bytes |
| Format / audio codec | MP3 / MP3 |
| Audio bitrate | 128,000 bps |
| Sample rate / channels | 48,000 Hz / stereo |
| Duration | 14.721458 seconds |

The owner confirmed that the file opened on the connected OnePlus and played
audibly from start to end. The debug APK SHA-256 was
`525bdb0046c2ea3c965d74ba1468620e6ff0f03602f9623b10b0db99a7509ab9`.
Full build, instrumentation, logcat output and the pulled MP3 stay ignored
under `work/android/0c-06/`.

## Pending-row handling and limits

The plugin creates a pending row only after a nonempty private MP3 exists.
The publisher deletes the row if copying, publishing, metadata inspection or
content-URI hash verification fails; it logs whether deletion succeeded.
This failure path was reviewed but not fault-injected on the device. The
successful row was published and no pending Downloads row remained.

This probe runs on API 29. `MediaStore.Downloads` pending rows are an API 29+
feature; the project's API 24–28 support path remains to be resolved in later
Android work. The 0C-04A native corresponding-source/build-input/notice
**OPEN RELEASE BLOCKER** remains in force. The APK is for feasibility on the
owner's device only and may not be published, uploaded, attached to a release,
or shared.

Implementation references: [Android MediaStore pending media guidance](https://developer.android.com/training/data-storage/shared/media),
[MediaStore `IS_PENDING` API](https://developer.android.com/reference/android/provider/MediaStore.MediaColumns#IS_PENDING),
[Tauri mobile plugin commands](https://v2.tauri.app/develop/plugins/develop-mobile/), and
[youtubedl-android 0.18.1 usage](https://github.com/yausername/youtubedl-android/tree/0.18.1).
