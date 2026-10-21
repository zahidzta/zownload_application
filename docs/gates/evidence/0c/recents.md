# 0C-10 — Removal from recents (AC-32)

## Device and command

The test used the owner-approved, rights-cleared Sintel YouTube single `https://www.youtube.com/watch?v=eRsGyueVLvQ`. The debug instrumentation alone used yt-dlp `--limit-rate 32K` to keep a real partial transfer observable. The physical device was OnePlus BE2011 (`b1c28e0d`), Android API 29, `arm64-v8a`, with WebView `com.google.android.webview` 155.0.8059.43.

```powershell
$env:JAVA_HOME = 'C:\Users\zahid\AppData\Local\Temp\zownload-0a-10-corretto\jdk21.0.11_10'
$env:ANDROID_SERIAL = 'b1c28e0d'
$env:ZOWNLOAD_ANDROID_LONG_URL = 'https://www.youtube.com/watch?v=eRsGyueVLvQ'
powershell -NoProfile -File scripts/gate-0c/verify.ps1 -Case recents
```

The exact verifier exited 0 on 2026-10-21. The arm64 debug APK SHA-256 was `4a7b8b76cab99f038c60c2c3939328743ae3f5af07c8b0f05a7db92666f3f7db`. Both instrumentation phases reported `OK (1 test)`.

## Observed lifecycle

The first phase confirmed a Rust queue item in `downloading`, foreground notification 108, a native child process, and 15,360 private partial-file bytes. Android's `ActivityManager.AppTask.finishAndRemoveTask()` removed the app task from recents. The foreground service received `onTaskRemoved` and returned a transient interruption to Rust. Rust saved the same item as `paused` in SQLite before requesting engine cancellation, then requested service stop. Kotlin reported `killed=true workerExited=true`; the service logged `SERVICE_STOPPED`.

```text
RECENTS_REMOVING item=04a85665-38f5-4338-aca1-491b9b183830 percent=0.0 children=[25746] bytes=15360
TASK_REMOVED
RUST_PAUSED_ON_TASK_REMOVAL item=04a85665-38f5-4338-aca1-491b9b183830
ENGINE_CANCEL id=26f4ed19-62e8-4026-8d7d-079fa479bd63 killed=true workerExited=true
SERVICE_STOPPED timedOut=false
REOPENED_PAUSED item=04a85665-38f5-4338-aca1-491b9b183830 percent=0.0
```

The host verifier found the observed child PID absent, notification 108 absent from active notifications, and no files left in the private spike output directory on two samples separated by two seconds. It then started a fresh instrumentation process: the reopened WebView called `get_queue`, which returned the same one-item queue at `paused`. No Continue command was issued and no work restarted.

`finishAndRemoveTask()` is Android's task removal API; this probe exercises the same service `onTaskRemoved` callback as a recents swipe but does not validate a particular launcher gesture. Tauri may exit its process when the only Activity is destroyed, so the verifier performs the no-orphan and reopen checks from the host and a second instrumentation phase. Full build, test, and logcat output are ignored under `work/android/0c-10/`.

AC-32 passed for this physical API 29 device. Android 15 timeout and real process-death recovery remain separate Gate 0C tasks. The native corresponding-source/build-input/notice gap is still an **OPEN RELEASE BLOCKER**; no Android APK or build may be distributed until it is resolved.
