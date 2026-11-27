<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 5B Task 5B-05 Evidence: Recents Removal Cancellation & Process-Death Recovery

## Implementation Summary
- `src-tauri/gen/android/app/src/main/java/com/zownload/app/DownloadForegroundService.kt`: Added `onTaskRemoved` forwarding to `AndroidEnginePlugin.onTaskRemoved()` with a 2.5-second fallback to detach/remove notification `1001` and call `stopSelf()`.
- `src-tauri/gen/android/app/src/main/java/com/zownload/app/AndroidEnginePlugin.kt`: Registered `registerLifecycleChannel` and added `dispatchLifecycleSignal("task_removed")` calling `cancelAllActive()` and posting the channel signal on a worker thread so `onTaskRemoved` never deadlocks the Android main Looper.
- `src-tauri/gen/android/app/src/main/java/com/zownload/app/BundledEnginePackage.kt`, `AndroidEngineAdapter.kt`, and `assets/engine_runner.py`: Added `cancelAllActive()`, `hasActiveOperations()`, `postprocessor_hooks` cancellation checks, and `watch_cancel` child-process termination (`SIGTERM` then `SIGKILL` for `/proc` descendants) while preserving `.part` files.
- `src-tauri/src/engine/android.rs` & `src-tauri/src/engine/android_queue.rs`: Registered the lifecycle channel in `init_queue`, paused active/queued work on `task_removed` without auto-resuming, stopped the foreground service, and preserved `.part` + pending MediaStore ZIP state across both recents removal and process death.

## Verification Results
- **Device under test:** Physical OnePlus `BE2011` (`serial=b1c28e0d`, Android 10 / API `29`, `arm64-v8a`)
- **Final Debug APK SHA-256:** `6e6e4d43efeaf1c2f8110a500d40103a390bae589f042c9b6dd527a345214720` (not committed or attached)
- `powershell -NoProfile -File scripts/gate-5b/verify.ps1 -Case lifecycle-recovery`: **PASS**
  - `cargo test --manifest-path src-tauri/Cargo.toml --locked --lib android_`: 11 passed, 0 failed (`android_queue::tests::recents_removal_pauses_queue_stops_service_and_preserves_part`, `android_spike::tests::android_spike_queue_restores_every_interrupted_state_as_paused`).
  - `:app:testArmDebugUnitTest`: passed.
  - `LifecycleRecoveryDeviceTest#recentsRemovalPausesQueueAndStopsService`: `OK (1 test)` (30.07s) — active notification list check passed (`pkg=com.zownload.app ... id=1001` absent from active `Notification List:` after `finishAndRemoveTask()`).
  - `LifecycleRecoveryDeviceTest#verifyPausedAfterRecentsAndCleanUp`: `OK (1 test)` (6.5s).
  - `LifecycleRecoveryDeviceTest#startDownloadForProcessDeath` (killed via `am force-stop com.zownload.app`) + `LifecycleRecoveryDeviceTest#verifyProcessDeathRestoreAndContinue`: `OK (1 test)` (31.904s) — confirmed interrupted `.part` stayed idle in `paused` state until explicit `resume_download`, then completed cleanly.
- Host foundation checks (`cargo fmt --check`, `cargo test --manifest-path src-tauri/Cargo.toml --locked`, `npm run check:contracts`, `npm run build`, `git diff --check`): **PASS**.
