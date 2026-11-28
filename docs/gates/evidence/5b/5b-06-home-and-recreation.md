<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 5B Task 5B-06 Evidence: Home Continuation & Disposable UI Recovery

## Implementation Summary
- `src-tauri/gen/android/app/src/main/java/com/zownload/app/AndroidEnginePlugin.kt`: Replaced the per-plugin `lazy` adapter with a synchronized process-level `activeAdapter` singleton (`getOrCreateAdapter`) and replaced `activity` references in `@Command` handlers with `appContext`, ensuring Activity recreation never orphans active engine operations or dereferences a destroyed Activity.
- `src-tauri/gen/android/app/src/main/java/com/zownload/app/DownloadForegroundService.kt`: Added `shouldPostNotificationUpdate` deduplication so unchanged progress snapshots are not re-posted unnecessarily while the service runs in the background.
- `src-tauri/gen/android/app/src/main/java/com/zownload/app/MediaStoreOutput.kt`: Added `insertWithNumberedFallback` and `isExpectedPublishedDisplayName` so Android 10+ Scoped Storage collisions against pre-existing unowned Downloads entries retry safely with numbered filenames (`name (1).ext`, `name (2).ext`) without overwriting or rejecting valid pending rows.
- `src/state/downloadFlow.ts`: Added a `document` `visibilitychange` listener inside `connectActivity` (detached cleanly on unmount) so returning from Home reconciles queue, history, notifications, and settings without duplicating event subscriptions.
- Tests & verifier:
  - `src-tauri/gen/android/app/src/test/java/com/zownload/app/DownloadForegroundServiceTest.kt`: Added unit tests for `shouldPostNotificationUpdate`, `isExpectedPublishedDisplayName`, and `insertWithNumberedFallback`.
  - `src-tauri/src/engine/android_queue.rs`: Added `monotonic_progress_updates_foreground_notification_without_regression`.
  - `tests/interactive/activity.test.tsx`: Added multi-item `get_queue` restoration + live event tracking and `visibilitychange` foreground reconciliation tests.
  - `src-tauri/gen/android/app/src/androidTest/java/com/zownload/app/HomeAndRecreationProductionDeviceTest.kt`, `DeviceTestHelpers.kt`, `scripts/gate-5b/fixture-server.py`, and `scripts/gate-5b/verify.ps1`: Added the `home-and-recreation` device verification case covering AC-31 and AC-34.

## Verification Results
- **Device under test:** Physical OnePlus `BE2011` (`serial=b1c28e0d`, Android 10 / API `29`, `arm64-v8a`)
- **Final Debug APK SHA-256:** `470978bc5c509dc15e2835cbffd14bd7ab197ac0c63de5f04c52575645e60a31` (not committed or attached)
- `powershell -NoProfile -File scripts/gate-5b/verify.ps1 -Case home-and-recreation`: **PASS**
  - `cargo test --manifest-path src-tauri/Cargo.toml --locked --lib android_`: 12 passed, 0 failed.
  - `:app:testArmDebugUnitTest`: passed (including `DownloadForegroundServiceTest`, 6 unit tests).
  - `HomeAndRecreationProductionDeviceTest#homeContinuationAdvancesNotificationAndCompletesAfterReturning`: `OK (1 test)` (252.251s) — 12 Home samples over 180s advanced SQLite `2.7392547% -> 75.808174%` and foreground notification progress `2 -> 76` with zero action buttons while `MainActivity` stayed out of focus, then completed cleanly to History and MediaStore Downloads after returning to foreground.
  - `HomeAndRecreationProductionDeviceTest#recreatedActivityRestoresQueueAndReceivesLiveEventsWithoutDuplicates`: `OK (1 test)` (117.897s) — `BEFORE_RECREATE pid=11510 domCount=2 domPercent=1 activeOps=true`, `AFTER_RECREATE pid=11510 domCount=2 domPercent=1 activeOps=true`, `LIVE_EVENT_AFTER_RECREATE domCount=2 domPercent=2` on the new WebView DOM without duplicate items or engine restarts, followed by clean completion.
- Host checks (`cargo fmt --check --manifest-path src-tauri/Cargo.toml`, `cargo test --manifest-path src-tauri/Cargo.toml --locked` [101 lib + integration tests], `npm run check:contracts`, `npm run build`, `npm run test:ui` [13 files, 64 passed], `git diff --check`): **PASS**.

## Scope Limitations
- Verified on physical API 29 (`BE2011`) using deliberate `input keyevent 3` (Home) and `MainActivity.recreate()`. Physical Android 15 (API 35) device sign-off (`AC-35`) and rights-cleared large-playlist device verification remain for Gate `5B-08`, and the Android distribution blocker remains open.
