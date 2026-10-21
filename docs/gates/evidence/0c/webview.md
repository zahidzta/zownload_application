# 0C-12 — WebView/Activity recreation (AC-34)

## Device and command

The approved rights-cleared long YouTube single was `https://www.youtube.com/watch?v=eRsGyueVLvQ` (Sintel). The instrumentation set a debug-only 32K yt-dlp rate limit so progress could be observed across recreation. The physical OnePlus BE2011 (`b1c28e0d`) ran Android API 29, `arm64-v8a`, and `com.google.android.webview` 155.0.8059.43.

```powershell
$env:JAVA_HOME = 'C:\Users\zahid\AppData\Local\Temp\zownload-0a-10-corretto\jdk21.0.11_10'
$env:ANDROID_SERIAL = 'b1c28e0d'
$env:ZOWNLOAD_ANDROID_LONG_URL = 'https://www.youtube.com/watch?v=eRsGyueVLvQ'
powershell -NoProfile -File scripts/gate-0c/verify.ps1 -Case webview-recreate
```

The exact verifier exited 0 on 2026-10-21. The debug APK SHA-256 was `39cd8336d929cdbc25896346419fd1a3ab4f24d6820bc4589d114c80e8aef222`. Android instrumentation reported `OK (1 test)` in 37.686 seconds. Full build, test, and logcat output is ignored under `work/android/0c-12/`.

## Recreation and live queue proof

The test invoked `enqueue_download` once in the original WebView, waited for its rendered queue card to show `downloading`, then called `MainActivity.recreate()`. Android created a distinct Activity and WebView in the same process. The new UI rendered the same queue ID, `downloading` status, and nondecreasing progress from its normal mount path, which subscribes to queue events and calls Rust `get_queue`. The test did not call Refresh or `get_queue` in the new WebView. A later Rust progress checkpoint appeared in that UI, proving its new event subscription was active. The same engine child PID remained before, immediately after, and after the progress event; no duplicate worker was observed.

```text
BEFORE pid=16398 item=08b0f46f-c69e-4928-960d-d81d79e0c45a status=downloading percent=0.0 children=17471
RECREATED pid=16398 item=08b0f46f-c69e-4928-960d-d81d79e0c45a status=downloading percent=0.0 children=17471
Zownload0C09 RUST_PROGRESS item=08b0f46f-c69e-4928-960d-d81d79e0c45a percent=1
LIVE_EVENT item=08b0f46f-c69e-4928-960d-d81d79e0c45a status=downloading percent=1.0 children=17471
```

This validates deliberate Activity recreation on the tested API 29 phone. It does not test rotation, lock/unlock, a process kill, or later MP3 publication. The Android native corresponding-source/build-input/notice gap remains an **OPEN RELEASE BLOCKER**. No Android APK or build may be distributed until it is resolved.
