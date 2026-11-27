<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 5B Task 5B-07 Evidence: Android 15 Foreground-Service Timeout Handling

## Implementation Summary
- `src-tauri/gen/android/app/src/main/java/com/zownload/app/DownloadForegroundService.kt`: Added `onTimeout(startId, fgsType)` delegating to `handleForegroundTimeout`, notifying `AndroidEnginePlugin.onForegroundTimeout()`, updating notification `1001` to detached non-ongoing text `"Downloads paused. Open Zownload to continue."` via `ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_DETACH)`, and calling `stopSelf()`.
- `src-tauri/gen/android/app/src/main/java/com/zownload/app/AndroidEnginePlugin.kt` & `src-tauri/src/engine/android_queue.rs`: Dispatched `"foreground_timeout"` over the lifecycle channel on a background thread (`Intent::TimeoutPause`), cancelling active engine operations while preserving `.part` files and pending ZIP progress, setting active/queued SQLite items to `paused` without halting future explicit `Continue`/`resume_download` recovery.

## Verification Results
- **Device under test:** Physical OnePlus `BE2011` (`serial=b1c28e0d`, Android 10 / API `29`, `arm64-v8a`)
- **Final Debug APK SHA-256:** `6e6e4d43efeaf1c2f8110a500d40103a390bae589f042c9b6dd527a345214720` (not committed or attached)
- `powershell -NoProfile -File scripts/gate-5b/verify.ps1 -Case foreground-timeout`: **PASS (simulated timeout callback on API 29)**
  - `cargo test --manifest-path src-tauri/Cargo.toml --locked --lib android_`: 11 passed, 0 failed (`android_queue::tests::foreground_timeout_pauses_without_stopping_detached_notification_and_resumes_on_continue`).
  - `:app:testArmDebugUnitTest`: passed.
  - `ForegroundTimeoutProductionDeviceTest#simulatedTimeoutCallbackPausesQueueAndPreservesPart`: `OK (1 test)` (51.027s) — invoked `service.handleForegroundTimeout(1, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)` on the live `DownloadForegroundService` while downloading, verified SQLite `paused`, detached `"Downloads paused. Open Zownload to continue."` notification, engine operation termination, 3-second `.part` byte stability, `paused` reopen state, and completion after explicit `resume_download`.

## Scope Limitation (Open AC-35 Sign-Off)
- `BE2011` (`b1c28e0d`) runs Android 10 (API 29 < 35), and the available `emulator-5554` is an `x86_64` API 37 emulator incompatible with `arm64-v8a` APKs. Therefore, OS-triggered `Service.onTimeout` (`android15SystemTimeoutPausesQueueAndPreservesPart`) was **not** executed on this device; physical Android 15 (API 35) device sign-off remains open for **AC-35**.
