<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 5A-07 — Kotlin Android engine bridge

## Result

The production Kotlin provider and Tauri plugin now expose metadata analysis,
one-entry downloads, progress callbacks, cancellation, and engine update
methods over the owner-approved Gate 5A-06 package. The adapter forwards one
operation at a time and contains no queue, history, or settings state. Python
is entered through a small JNI shim that initializes the staged CPython runtime
once and serializes calls with its GIL.

The provider extracts the manifest-staged runtime into app-private storage,
rejects unsafe archive paths, uses the packaged FFmpeg/QuickJS paths, and
writes transient request/result/progress/cancel files under the app cache.
Updates are staged from a checksum-pinned official release and become active at
the next startup. If the staged release cannot import, startup removes it and
retries the bundled baseline. Updates cannot overlap analysis or download work.

The updater candidate is yt-dlp `2026.11.23`, with SHA-256
`e8665ed64d6b9172773e812f891fb707a0cb1ee8d9ef4fc1acb00cabee4c5256` from the
[official release asset](https://github.com/yt-dlp/yt-dlp/releases/tag/2026.11.23).
That release pins EJS `0.8.0` in its
[Python project metadata](https://github.com/yt-dlp/yt-dlp/blob/2026.11.23/pyproject.toml),
matching the staged runtime.

## Verification

- Focused `kotlin-engine` verifier passed: Kotlin provider/plugin compiled,
  JNI bridge built for Android, and focused adapter unit tests passed.
- `npm run check:contracts` passed; TypeScript fixtures match the shared JSON.
- `cargo test --manifest-path src-tauri/Cargo.toml` passed: 91 unit tests and
  all enabled integration tests passed; existing ignored tests remain ignored.
- Python runner syntax parsed successfully and `git diff --check` passed.
- The Android build used local JDK 26 because the documented Corretto 21
  installation was unavailable. The focused build passed with that JDK; CI or
  device verification on the pinned toolchain remains useful follow-up.
- No physical-device download test was run; single/playlist behavior and
  lifecycle proof are reserved for task 5A-09. No APK was shared.

## Authority note

The accepted Gate 5A plan records the owner's 2026-11-22 approval of CPython
and JNI. `PROJECT.md` D-09 and the older standing-decision text in `STATE.md`
still refer to the earlier `youtubedl-android` Option A. This task follows the
later explicit Gate 5A approval; `PROJECT.md` remains unchanged pending owner
requirements cleanup.
