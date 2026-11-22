<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# 5A-02 — Android Python runtime decision

## Owner decision

The owner approved Chaquopy 17.2.0, Python 3.13, and `arm64-v8a` only, and
approved using an Android Java/Kotlin `ProcessBuilder` bridge for QuickJS with
a yt-dlp EJS provider adaptation. This records the runtime/package boundary;
the JavaScript bridge and actual YouTube challenge proof belong to later Gate
5A tasks.

## Pinned package boundary

- Chaquopy Gradle plugin/source: 17.2.0, upstream commit
  `1f63c93d8beaf7062fbe51888ab9235475df3bb8`.
- App Python target: 3.13, `arm64-v8a` only. Chaquopy 17.2 currently resolves
  this to CPython 3.13.16 (`3.13.16-0` Android target); the exact CPython source
  and package inputs are in [`runtime-lock.psd1`](../../../../scripts/gate-5a/runtime-lock.psd1).
- Python packages: yt-dlp 2026.08.19 and yt-dlp-ejs 0.8.0, installed only from
  their SHA-256-pinned pure-Python wheels. Their source archives are also
  pinned for provenance.
- Kotlin will call yt-dlp through Chaquopy's in-process Python API. Python's
  subprocess module is unavailable on Android, so the QuickJS provider must
  call the approved Java bridge rather than the upstream Python subprocess
  runner. 5A-03 does not implement that adapter.

## Build and fallback

The Windows build host uses Python 3.13.17 x64; Chaquopy requires matching
major/minor versions, and its documented buildPython micro version may differ.
The repeatable setup and APK verification commands are in
[`engine-builds.md`](../../../engine-builds.md#gate-5a-python-and-ytdlp-android-package).
The 5A-03 build produced a 122,161,575-byte local debug APK; see the
[build evidence](python-runtime-build.md) for its hash. This includes existing
app assets and legacy engine dependencies, so it is not a final release-size
estimate. If the approved runtime cannot be packaged or the QuickJS bridge
cannot be made to work, stop Android engine integration and return to the owner
for a runtime or release-scope decision; do not distribute an APK while the
Android release blocker is open.

## Security and runtime limits

Chaquopy 17.2's published Python 3.13 target is 3.13.16. Python 3.13.18 is a
later security-only source release with security fixes, but Chaquopy 17.2 does
not publish that target ([Chaquopy target docs](https://chaquo.com/chaquopy/doc/current/android.html),
[Python 3.13.18 release](https://www.python.org/downloads/release/python-31318/)).
Record the version gap as an Android distribution blocker: update Chaquopy's
target or build and review a patched runtime before release. The local package
task does not claim Python 3.13.18 security fixes.

The approved QuickJS bridge is an architectural decision only. EJS scripts
alone do not execute JavaScript; 5A-05 must package the pinned QuickJS runtime,
and 5A-07 must prove the adapted provider on Android before the YouTube JS
challenge acceptance can pass.
