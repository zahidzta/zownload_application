<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 5B-02 — MediaStore single-file output

## Verification

Command: `powershell -NoProfile -File scripts/gate-5b/verify.ps1 -Case mediastore-single`

Result: passed on 2026-11-25. Rust bridge tests passed (3/3), Kotlin filename tests
passed (2/2), the Android instrumentation test compiled, and the device test passed
(1/1, zero failures).

Device: OnePlus BE2011, Android API 29, `arm64-v8a`.

The device test published MP3 and MP4 byte fixtures to the public Downloads
collection. It checked the MIME type, relative path, published `IS_PENDING=0`
state, and read-back bytes. Publishing a second `song.mp3` produced `song (1).mp3`.
An injected partial-copy failure propagated the existing typed bridge error and
left no Downloads row behind.

The Android debug APK remains local under the generated Android build tree;
SHA-256: `ed7f2c5ea297249bfa11e721b3398af0c7a8897686f606aeae0ed7e7631d3c18`.
It was not attached or published.

## Scope notes

The device test exercises the MediaStore provider with synthetic bytes; it does not
claim that those fixtures are playable media or verify a live yt-dlp queue run.
The Rust bridge and Android app compile passed as part of the exact verification.
API 35 lifecycle and large-playlist proof remain assigned to Gate 5B-08.
