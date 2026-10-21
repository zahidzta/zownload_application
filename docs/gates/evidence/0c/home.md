# 0C-09 — Home continuation (AC-31)

## Fixture and command

The owner supplied and approved `https://www.youtube.com/watch?v=eRsGyueVLvQ` for the long Home probe. Pinned yt-dlp metadata identified `Sintel - Open Movie by Blender Foundation`, ID `eRsGyueVLvQ`, duration 888 seconds. The Android instrumentation applied yt-dlp `--limit-rate 32K` **only in the debug test** to keep a real transfer observable for three minutes; normal spike jobs have no rate limit.

```powershell
$env:JAVA_HOME = 'C:\Users\zahid\AppData\Local\Temp\zownload-0a-10-corretto\jdk21.0.11_10'
$env:ANDROID_SERIAL = 'b1c28e0d'
$env:ZOWNLOAD_ANDROID_LONG_URL = 'https://www.youtube.com/watch?v=eRsGyueVLvQ'
powershell -NoProfile -File scripts/gate-0c/verify.ps1 -Case home
```

The exact command exited 0. Android instrumentation reported `OK (1 test)` in 184.27 seconds. Device: physical OnePlus BE2011, Android API 29, `arm64-v8a`, WebView `com.google.android.webview` 155.0.8059.43. APK SHA-256: `8380751ec6db4aa7e4c654030da74dfae5a957ba918718da8a8330516e5eae42`.

## Observed result

Rust started the foreground service before invoking the Kotlin engine. Kotlin forwarded whole-percentage yt-dlp callbacks through a Tauri channel; Rust alone validated monotonic values, saved SQLite snapshots, and emitted queue events. The test pressed Home and checked that the Activity stayed out of focus at every sample. A host `dumpsys activity activities` observation also showed the OnePlus launcher resumed during the transfer.

The device's final record was:

```text
HOME_TEST_OK start=2026-10-21T19:02:32.299Z end=2026-10-21T19:05:33.562Z elapsedMs=180372 item=59b7f733-cb15-409e-8af4-884fe0aa2f10 startPercent=0.0 endPercent=34.0 changes=10 samples=12 notification=true home=true
```

Every 15-second sample read the Rust SQLite snapshot, required status `downloading`, rejected falling progress, required notification ID 108 from Android's `NotificationManager`, and required the Activity to remain unfocused. The 12 durable samples rose from 0% through 3%, 6%, 10%, 13%, 17%, 20%, 24%, 27%, 30%, and 34%. The engine and Rust progress logs continued during Home. At the end of the timed window, local engine work was still running; this test did not wait for completion or publish another MP3.

The Home screenshot shows the download notification icon at 2026-10-21 13:04 device time. It remains ignored at `work/android/0c-09/home-notification.png`, SHA-256 `ed474769061ee67e8cb92af02c9f72cc7046c3a38eb1b872be9b16144754cf46`. Full build, instrumentation, logcat, and fixture logs are ignored under `work/android/0c-09/`; the verifier prints only a concise result. The screenshot is not committed because the phone's Home screen is personal.

AC-31 is proved for this physical API 29 device and the controlled 32K test transfer. This does not prove unconstrained throughput, completion after Home, recents cancellation, or Android 15 timeout. The native corresponding-source/build-input/notice gap remains an **OPEN RELEASE BLOCKER**. No Android APK or build may be distributed until that gap is resolved.
