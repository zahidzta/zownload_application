<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# 5A-03 — Python and yt-dlp Android package

## Result

The exact gate command passed on 2026-11-22:

```powershell
powershell -NoProfile -File scripts/gate-5a/verify.ps1 -Case python-runtime
```

It reported Chaquopy 17.2.0, CPython 3.13.16, yt-dlp 2026.08.19, yt-dlp-ejs
0.8.0, and only the `arm64-v8a` native ABI. The verifier checked the locked
source archives and wheels, inspected the packaged Python metadata and EJS
solver scripts inside the APK, and rejected other native ABIs.

## APK and dependency hashes

- Local debug APK:
  `src-tauri/gen/android/app/build/outputs/apk/universal/debug/app-universal-debug.apk`
- Size: **122,161,575 bytes**; SHA-256:
  `e2bbeb3c75114de69c1679212e9901050de76879ce658d8ecc44882cdad0b39f`.
- Source archives, wheels, versions, URLs, licenses, and hashes:
  [`runtime-lock.psd1`](../../../../scripts/gate-5a/runtime-lock.psd1).
- Gradle dependency verification, including Chaquopy Maven plugin/runtime
  artifacts:
  [`verification-metadata.xml`](../../../../src-tauri/gen/android/gradle/verification-metadata.xml).
- The resolved Chaquopy Python target is `com.chaquo.python:target:3.13.16-0`
  for `arm64-v8a`; its artifact SHA-256 is
  `fae8cfd4d3910b6f978b22279fe820c0c6ba49d0ea20f7b106aa6130f1c8f355`. The
  Chaquopy bootstrap image SHA-256 is
  `7f9baf492f6f55ffaf92de492e239b7d4e8e5ca7a0ab3a07698a35f413495276`.

## Reproduction and package boundary

Provision the owner-pinned build hosts, then run the gate:

```powershell
powershell -NoProfile -File scripts/gate-5a/setup-jdk-host.ps1
powershell -NoProfile -File scripts/gate-5a/setup-python-host.ps1
powershell -NoProfile -File scripts/gate-5a/verify.ps1 -Case python-runtime
```

The build uses Corretto 21.0.11.10.1, Python 3.13.17 x64 as Chaquopy's host
interpreter, Gradle 9.6.1, and AGP 9.3.1. `gradle.properties` restricts the
Tauri universal variant and Rust build task to `arm64-v8a`; AGP disables the
other ABI variants, which Chaquopy Python 3.13 does not supply. The Android
configuration cache is disabled because this project's AGP resource task could
not serialize its cache state.

Chaquopy supplies prebuilt, upstream Python/Android artifacts. This task pins
their corresponding source archives and the resolved Maven artifacts; it does
not claim to rebuild CPython or Chaquopy from source on Windows. The approved
package decision and the current Python micro-version limitation are recorded
in the [5A-02 decision](python-runtime-decision.md).

## Limits

This is a local debug APK measurement, not a release-size estimate. The APK
still includes the existing Android engine dependencies pending the 5A-06
provenance/removal audit; the Android distribution blocker remains open. The
Chaquopy target is Python 3.13.16 while [Python 3.13.18](https://www.python.org/downloads/release/python-31318/)
is a later security-only source release, so do not distribute this APK before
updating or reviewing the runtime target.

The package includes EJS solver scripts but does not prove a YouTube JavaScript
challenge. QuickJS packaging and the approved Android `ProcessBuilder` bridge
with yt-dlp provider adaptation are later Gate 5A tasks. The Python subprocess
runner is unavailable on Android; 5A-07 must prove the Java bridge path on a
device.
