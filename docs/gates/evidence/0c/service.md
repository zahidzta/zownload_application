# 0C-08 — `dataSync` foreground service and notification

The owner explicitly approved the 0C-01 `dataSync` proposal on 2026-10-21.
`PROJECT.md:193` now records the type. Android's [service-type table](https://developer.android.com/develop/background-work/services/fgs/service-types)
lists downloads and local file processing under `dataSync`; the manifest declares
`FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC`, and the service type. The
app requests notification permission on Android 13+ so the notice can appear in
the notification drawer.

Rust starts the service after its durable queued checkpoint and waits for the
service's foreground-start acknowledgement before invoking the Kotlin engine.
It stops the service when Kotlin returns and continues to own all queue state.
The service owns no queue. Its Android 15 `onTimeout(int,int)` sends a timeout
result through the plugin's waiting Rust call, cancels the transient engine
process, posts a paused notification, and stops itself promptly. Rust then
checkpoints the item as `paused`. The timeout code compiled, but the Android 15
system callback remains untested until 0C-15.

## Exact verification

```powershell
$env:JAVA_HOME = 'C:\Users\zahid\AppData\Local\Temp\zownload-0a-10-corretto\jdk21.0.11_10'
$env:ANDROID_SERIAL = 'b1c28e0d'
$env:ZOWNLOAD_ANDROID_YOUTUBE_URL = 'https://www.youtube.com/watch?v=uW13KuRrg1g'
powershell -NoProfile -File scripts/gate-0c/verify.ps1 -Case foreground-service
```

The final command exited 0 on the physical OnePlus BE2011, API 29,
`arm64-v8a`. It built the arm64 debug APK and a connected instrumentation APK,
then used the locked rights-cleared `youtube-short` fixture. The test observed
notification ID 108 during a Rust-owned job, an `OK` download callback, and no
active notification after the Rust stop call. The relevant device log times
were 11:44:43 `SERVICE_STARTED type=dataSync` and `NOTIFICATION_OBSERVED`,
11:45:02 `RUST_DOWNLOAD_CALLBACK result=ok`,
`RUST_SERVICE_STOP_REQUESTED`, `SERVICE_STOPPED timedOut=false`, and
`SERVICE_TEST_OK` for item `71224ab8-5790-42ec-834b-259faaa22a2c`.
The final APK SHA-256 is
`577d4fd58289276ac6850b1176a3d314930384adf07f30a7508f44f60178eb43`.
Full build/test/logcat files remain ignored under `work/android/0c-08/`.

This run proves service and notification startup/stop around a controlled
download on API 29. It does not prove Home continuation, recents cancellation,
or the Android 15 system timeout; those belong to 0C-09, 0C-10, and 0C-15.
The Android native corresponding-source/build-input/notice **OPEN RELEASE
BLOCKER** and no-distribution rule remain in force. No APK was published,
uploaded, attached to a release, or shared.
