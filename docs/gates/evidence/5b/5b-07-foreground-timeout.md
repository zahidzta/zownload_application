<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 5B Task 5B-07 Evidence: Android 15 Foreground-Service Timeout Handling

## Implementation Summary
- `src-tauri/gen/android/app/src/main/java/com/zownload/app/DownloadForegroundService.kt`: Added `onTimeout(startId, fgsType)` delegating to `handleForegroundTimeout`, notifying `AndroidEnginePlugin.onForegroundTimeout()`, updating notification `1001` to detached non-ongoing text `"Downloads paused. Open Zownload to continue."` via `ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_DETACH)`, and calling `stopSelf()`.
- `src-tauri/gen/android/app/src/main/java/com/zownload/app/AndroidEnginePlugin.kt` & `src-tauri/src/engine/android_queue.rs`: Dispatched `"foreground_timeout"` over the lifecycle channel on a background thread (`Intent::TimeoutPause`), cancelling active engine operations while preserving `.part` files and pending ZIP progress, setting active/queued SQLite items to `paused` without halting future explicit `Continue`/`resume_download` recovery.
- `scripts/gate-5b/fixture-server.py` & `scripts/gate-5b/verify.ps1`: Added `/long-timeout.mp3` (`2600` MP3 frames, `1,084,200` bytes ≈ `45.2s` at `24,000` B/s) for `foreground-timeout` so the transfer stays mid-`.part` past Android 15's 15s test `data_sync_fgs_timeout_duration` window before OS `Service.onTimeout` fires.

## Verification Results
### Physical Android 15 (API 35) — AC-35 Sign-Off
- **Device under test:** Physical `CUBOT P90` (`serial=P90260624026832`, Android 15 / API `35`, `arm64-v8a`, fingerprint `CUBOT/P90_EEA/P90:15/AP3A.240905.015.A2/2026352:user/release-keys`)
- **Final Debug APK SHA-256:** `470978bc5c509dc15e2835cbffd14bd7ab197ac0c63de5f04c52575645e60a31` (not committed or attached)
- `powershell -NoProfile -File scripts/gate-5b/verify.ps1 -Case foreground-timeout`: **PASS (OS-triggered `Service.onTimeout` on Android 15 / API 35)**
  - `cargo test --manifest-path src-tauri/Cargo.toml --locked --lib android_`: 12 passed, 0 failed (`android_queue::tests::foreground_timeout_pauses_without_stopping_detached_notification_and_resumes_on_continue`).
  - `:app:testArmDebugUnitTest`: passed.
  - `ForegroundTimeoutProductionDeviceTest#android15SystemTimeoutPausesQueueAndPreservesPart`: `OK (1 test)` (`59.599s`) with `device_config put activity_manager data_sync_fgs_timeout_duration 15000`:
    - `ZownloadFgs`: `SERVICE_STARTED type=dataSync startId=1` -> OS callback `SERVICE_TIMEOUT startId=1 type=1` -> `SERVICE_STOPPED timedOut=true` (clean stop, no `ForegroundServiceDidNotStopInTimeException`).
    - `Zownload5B07`: `TIMEOUT_ACTIVE item=a9a6937c-b9ab-4909-8e0a-b709e9f146c9 bytes=127802 prefix=9d2dfbdf6209954582ee00531bea6e0882d81f411600b537b270cf2d666839da system=true` -> `TIMEOUT_PAUSED bytes=535347 prefix=9d2dfbdf6209954582ee00531bea6e0882d81f411600b537b270cf2d666839da` (3s stability + detached `"Downloads paused. Open Zownload to continue."` notification + zero child processes) -> `TIMEOUT_REOPENED status=paused`.
    - Explicit `resume_download` restarted `DownloadForegroundService` (`SERVICE_STARTED type=dataSync startId=1`), requested HTTP `206` `range=bytes=535347-` on `/long-timeout.mp3`, and completed cleanly (`SERVICE_STOPPED timedOut=false`).
    - Post-run check confirmed `device_config get activity_manager data_sync_fgs_timeout_duration` restored to `null` (`dumpsys activity settings`: `data_sync_fgs_timeout_duration=21600000`).

### Physical Android 10 (API 29) — Regression Run
- **Device under test:** Physical OnePlus `BE2011` (`serial=b1c28e0d`, Android 10 / API `29`, `arm64-v8a`)
- **Debug APK SHA-256:** `6e6e4d43efeaf1c2f8110a500d40103a390bae589f042c9b6dd527a345214720` (not committed or attached)
- `powershell -NoProfile -File scripts/gate-5b/verify.ps1 -Case foreground-timeout`: **PASS (simulated timeout callback on API 29)**
  - `cargo test --manifest-path src-tauri/Cargo.toml --locked --lib android_`: 11 passed, 0 failed.
  - `:app:testArmDebugUnitTest`: passed.
  - `ForegroundTimeoutProductionDeviceTest#simulatedTimeoutCallbackPausesQueueAndPreservesPart`: `OK (1 test)` (`51.027s`) — invoked `service.handleForegroundTimeout(1, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)` on the live `DownloadForegroundService` while downloading, verified SQLite `paused`, detached `"Downloads paused. Open Zownload to continue."` notification, engine operation termination, 3-second `.part` byte stability, `paused` reopen state, and completion after explicit `resume_download`.

## AC-35 Status & Remaining Scope
- **AC-35** is **PASSED and closed** on physical Android 15 (API 35, `CUBOT P90`).
- Remaining Gate 5B work: `5B-08` integrated device acceptance (including the owner-provided rights-cleared large-playlist fixture) and owner review of the open Android distribution blocker.
