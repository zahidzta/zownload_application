<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 5B Task 5B-03 Evidence: MediaStore ZIP Output & Storage Recovery

## Implementation Summary
- `src-tauri/gen/android/app/src/main/java/com/zownload/app/MediaStoreOutput.kt`: Added pending MediaStore ZIP lifecycle (`PendingMediaStoreZip`, `createPendingMediaStoreZip`, `openPendingMediaStoreZipFd`, `publishPendingMediaStoreZip`, `deletePendingMediaStoreZip`), `queryDisplayNameExists` with `QUERY_ARG_MATCH_PENDING` on API 30+ and `@Suppress("DEPRECATION") MediaStore.setIncludePending` on API 29, and cache cleanup (`deleteOperationWorkDir`, `deleteQueueCacheDirs`).
- `src-tauri/gen/android/app/src/main/java/com/zownload/app/AndroidEnginePlugin.kt`: Exposed `createPendingZip`, `openPendingZipFd`, `publishPendingZip`, `deletePendingZip`, `cleanupOperation`, and `cleanupQueueCache` commands on the private Android engine bridge.
- `src-tauri/src/engine/android_zip.rs` & `src-tauri/src/engine/android_queue.rs`: Implemented `PendingArchiveStore` and `AndroidZipOutput` writing uncompressed `Stored` ZIP entries directly to the MediaStore `"rw"` descriptor, verifying entry CRC on readback, maintaining a central-directory recovery backup and journal for resume recovery, resolving numbered filename collisions, and deleting source cache files and empty/unrecoverable pending rows on failure or removal.
- `src-tauri/src/engine/android.rs` & `src-tauri/src/lib.rs`: Wired `AndroidEngine<R>` to implement `PendingArchiveStore` and `AndroidEngineBackend`.

## Verification Results
- **Device under test:** Physical OnePlus `BE2011` (`serial=b1c28e0d`, Android 10 / API `29`, `arm64-v8a`)
- **Final Debug APK SHA-256:** `6e6e4d43efeaf1c2f8110a500d40103a390bae589f042c9b6dd527a345214720` (not committed or attached)
- `powershell -NoProfile -File scripts/gate-5b/verify.ps1 -Case mediastore-zip`: **PASS**
  - `cargo test --manifest-path src-tauri/Cargo.toml --locked --lib android_`: 11 passed, 0 failed (`android_zip::tests::*`, `android_queue::tests::zip_playlist_publishes_stored_entries_cleans_work_and_stops_service`).
  - `:app:testArmDebugUnitTest`: passed.
  - `MediaStoreZipOutputDeviceTest#pendingMediaStoreZipSupportsSeekableRwCollisionsAndCleanup`: `OK (1 test)` (0.592s).
  - `MediaStoreZipOutputDeviceTest#playlistZipDownloadsEndToEndThroughMediaStoreWithZeroLeftoverWorkFiles`: `OK (1 test)` (72.136s).
- `powershell -NoProfile -File scripts/gate-5b/verify.ps1 -Case mediastore-single`: **PASS** (`MediaStoreOutputDeviceTest#mp3AndMp4ArePublishedWithNumberedCollisionsAndNoPartialRows`, `OK (1 test)` in 1.476s).
- Host foundation checks (`cargo fmt --check`, `cargo test --manifest-path src-tauri/Cargo.toml --locked` — 100 lib unit tests + integration suites, `npm run check:contracts`, `npm run build`, `git diff --check`): **PASS**.
