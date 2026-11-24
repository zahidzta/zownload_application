<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 5A-08 — Rust Android engine integration

## Result

Rust now registers the accepted `AndroidEnginePlugin` through Tauri's mobile
plugin API. `AndroidEngine` maps analysis, one-entry downloads and progress,
cancellation, typed failures, and updater responses into the existing Rust
contract types. The Android command handler now uses the same command names,
queue/history/settings database, and event payloads as desktop. The Rust queue
serializes work and persists status/progress before emitting updates.

Playlist entry URLs travel in a private `itemUrls` field from the packaged
Python runner. Rust consumes those URLs for sequential entries, then serializes
only the existing `AnalyzeResult`; the bridge test verifies that private URLs
do not enter the public response. No shared TypeScript or Rust contract fields
changed.

Engine results are copied from the Kotlin operation cache to app-private
`android-engine-outputs/<queue-id>/` staging. Gate 5B owns public Downloads via
MediaStore and ZIP output. This task did not run a device download; task 5A-09
retains the physical-device proof through the validated Gate 0C output path.

## Verification

- V3 passed with `powershell -NoProfile -File scripts/gate-5a/verify.ps1 -Case rust-engine`.
- Contract parity passed; Rust ran 94 unit tests and all enabled integration
  tests passed. Existing ignored device/resource tests remained ignored.
- Cargo checked the Android `aarch64-linux-android` target using the pinned
  NDK r30 / API 24 Clang and LLVM archiver.
- The focused Android build passed Kotlin compilation, JNI native build, and
  `testArmDebugUnitTest` under the pinned Corretto 21 JDK.
- `git diff --check` passed. No APK or build output was shared.

## Limits

No physical device, YouTube fixture, playlist download, or MediaStore output
was tested here. Those checks remain in 5A-09 and Gate 5B respectively.
