<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 5A-02 — Approved CPython runtime strategy

**Owner decision: CPython approved on 2026-11-22.** The owner selected an
upstream CPython source build embedded behind the existing Kotlin
`AndroidEnginePackage` boundary. This records the packaging strategy and
source lock; it does not build or integrate the runtime. Those steps belong to
5A-03 and later tasks.

## Selected approach

Build CPython `3.14.10` for `arm64-v8a` from its official source archive and
embed `libpython` plus the standard library in the Android app. A small JNI
bridge will let the Kotlin package provider call Python; Rust remains the queue
owner and the public command/event contract stays unchanged. yt-dlp
`2026.08.19`, EJS `0.8.0`, QuickJS `2026-06-04`, the pinned Python package
sources, and six native dependencies are recorded in the machine-readable lock
in [`engine-sources.md`](../../../engine-sources.md#gate-5a-android-python-runtime-lock--owner-approved-2026-11-22).
yt-dlp's pinned release supports CPython `3.10+` and tests through `3.14`, so
the selected runtime stays within its documented Python compatibility range
([tagged project metadata](https://github.com/yt-dlp/yt-dlp/blob/2026.08.19/pyproject.toml)).

The CPython Android guide describes this embedded `libpython` arrangement.
The official Android build helper supports Linux/macOS hosts; this project
selects Ubuntu 24.04 x86_64 with Corretto JDK `21.0.11.10.1`, Android SDK API
36, Build-Tools `36.0.0`, Command-Line Tools `22.0`, and NDK r30
`30.0.16248370`. The helper defaults to Android API 24 and target
`aarch64-linux-android`, matching the app's minimum API and `arm64-v8a` ABI.
See the [CPython Android guide](https://github.com/python/cpython/blob/v3.14.10/Doc/using/android.rst),
[build instructions](https://github.com/python/cpython/blob/v3.14.10/Android/README.md),
and the task's [build recipe](../../../engine-builds.md#5a-03--cpython-and-yt-dlp-android-runtime).

CPython's helper pins a different NDK than the repository, and its dependency
repository publishes prebuilt archives. The lock records one-line NDK patches
for both source trees. 5A-03 must build bzip2, libffi, OpenSSL, SQLite, xz,
and zstd from their exact locked source archives with the pinned recipe tags,
then place those outputs in CPython's local download cache. The helper reuses
same-named cache files, so this avoids treating upstream prebuilt archives as
source evidence. Do not build until the task captures the recipe patches,
commands, notices, and dependency hashes.

The official CPython Android package is listed as 22.0 MB. Planning estimates
a 22–35 MB compressed APK increase for the source-built runtime before the
other Android engines; this has not been measured. 5A-03 must report the actual
APK delta and runtime size.

## Alternatives considered

| Path | Fit with `AndroidEnginePackage` | Main cost or risk |
|---|---|---|
| **CPython source + JNI — selected** | Preserves the provider boundary with embedded Python calls behind a small JNI bridge. | Most custom native work; runtime size estimate is unmeasured. |
| Chaquopy 17.2.0 | Offers a documented Kotlin-to-Python call API that a provider could wrap. | Adds a major Gradle/runtime dependency and needs artifact-level Python/package provenance. |
| python-for-android AAR (`service_library`) | Produces a reusable AAR with Java service entrypoints. | Adds a packaging framework and needs a bridge design for callbacks and cancellation. |

If CPython cannot be built with the pinned sources and tools, or the measured
size exceeds the accepted budget, stop 5A-03 and return the evidence to the
owner for a new runtime decision or review of the desktop-only first-release
fallback recorded in [`STATE.md`](../../../STATE.md). Do not silently switch
frameworks or ship untraceable binaries.

## Verification

`powershell -NoProfile -File scripts/gate-5a/verify.ps1 -Case python-source-lock`
passed with: `PASS: CPython Android source lock, owner decision, and build-tool pins are consistent.`
