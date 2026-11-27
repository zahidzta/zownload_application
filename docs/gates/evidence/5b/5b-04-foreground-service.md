<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 5B Task 5B-04 Evidence: Production `dataSync` Foreground Service & Notification

## Implementation Summary
- `src-tauri/gen/android/app/src/main/java/com/zownload/app/DownloadForegroundService.kt`: Implemented the stateless `dataSync` foreground service using `NotificationCompat` + `ServiceCompat`, posting progress-only notifications (`NOTIFICATION_ID = 1001`, channel `zownload-downloads`, zero action buttons), without owning queue or retry state.
- `src-tauri/gen/android/app/src/main/AndroidManifest.xml`: Replaced `.SpikeDownloadService` with `.DownloadForegroundService` (`android:exported="false"`, `android:foregroundServiceType="dataSync"`).
- `src-tauri/gen/android/app/src/main/java/com/zownload/app/AndroidEnginePlugin.kt` & `src-tauri/src/engine/android_queue.rs`: Added `startForegroundService`, `updateForegroundProgress`, and `stopForegroundService` bridge commands driven by `AndroidQueueCore` transitions so the service runs only while active queue work runs and stops cleanly on pause or queue idle.
- `src-tauri/gen/android/app/src/test/java/com/zownload/app/DownloadForegroundServiceTest.kt`: Added 3 JVM unit tests for notification formatting behavior.

## Verification Results
- **Device under test:** Physical OnePlus `BE2011` (`serial=b1c28e0d`, Android 10 / API `29`, `arm64-v8a`)
- **Final Debug APK SHA-256:** `6e6e4d43efeaf1c2f8110a500d40103a390bae589f042c9b6dd527a345214720` (not committed or attached)
- `powershell -NoProfile -File scripts/gate-5b/verify.ps1 -Case foreground-service`: **PASS**
  - `cargo test --manifest-path src-tauri/Cargo.toml --locked --lib android_`: 11 passed, 0 failed.
  - `:app:testArmDebugUnitTest`: passed (including `DownloadForegroundServiceTest`, 3 unit tests).
  - `ForegroundServiceProductionDeviceTest#dataSyncServiceStartsShowsProgressStopsOnPauseAndIdleWithZeroActions`: `OK (1 test)` (47.44s). Verified active `dataSync` service + notification ID `1001` with zero notification actions while downloading, cleared notification when paused, and stopped service when idle.
- Host foundation checks (`cargo fmt --check`, `cargo test --manifest-path src-tauri/Cargo.toml --locked`, `npm run check:contracts`, `npm run build`, `git diff --check`): **PASS**.
