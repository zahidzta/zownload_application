<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# 0C-13 — Direct pending MediaStore ZIP output

The exact gate command `powershell -NoProfile -File scripts/gate-0c/verify.ps1 -Case mediastore-zip` exited `0` on 2026-10-21 with `ANDROID_SERIAL=b1c28e0d` and `JAVA_HOME=C:\Program Files\Java\jdk-26.0.2`. The device was a physical OnePlus BE2011, API 29, `arm64-v8a`. The local JDK differs from the pinned Corretto 21; the Android build and the one device instrumentation test passed. The debug APK SHA-256 was `f74e4360e9511138b911dc55efcc3e012f4f8cc1982a14ef058c2acaf6a4326d`.

Rust used `zip` 9.0.5's non-seeking stream writer. It selected `manifest.txt` followed by `payload.bin` and sent bounded 16 KiB ZIP chunks through the Tauri mobile plugin. Kotlin only held the pending MediaStore output stream, wrote those chunks, closed it, changed `IS_PENDING` from 1 to 0, or deleted the row on failure. Neither side created a completed ZIP in private storage; the verifier also found no private `*.zip` in the app cache. Kotlin gained no work queue.

## Device observations

- At 16:51:24.244, MediaStore created pending URI `content://media/external/downloads/9662` with display name `Zownload-0C13-992b91b5-0609-484e-8a50-c94cc0c2314a.zip`. The shell inspected the row as `is_pending=1` while the stream was open.
- At 16:51:31.286, a separate test APK UID (`10554`) queried that exact URI and got `visible=false`. The verifier required the row to remain pending before allowing this result. The shell UID itself is privileged and can inspect pending rows, so it was not used as the visibility observer.
- At 16:51:45.944, Kotlin closed the stream and published the **same URI**. The shell then read `is_pending=0`; `/sdcard/Download/` held the ZIP and it opened successfully. The file was 262,449 bytes, SHA-256 `009c0141328d975b3a696bf3135f16d07966bbc56dd558815415e653909ca2d6`.
- The archive had exactly two entries in Rust's order. `manifest.txt` matched the expected UTF-8 text. The uncompressed 262,144-byte `payload.bin` matched SHA-256 `2312394bd99545d9de131c24efb781e765ac1aec243f2ed9347597a793a415e9`.
- An injected failure after writing entry bytes and before ZIP close created pending URI `content://media/external/downloads/9663`. Rust requested abort; Kotlin logged `deleted=1` at 16:51:49.220; a later shell query found no row. Instrumentation reported `OK (1 test)`.

Build, instrumentation, logcat, and the pulled ZIP remain ignored under `work/android/0c-13/`. The fixture uses deterministic synthetic entries; actual playlist packaging belongs to later stages. MediaStore pending Downloads rows require API 29 here, so the project's API 24–28 path remains unresolved. This is local feasibility evidence only. The Android native corresponding-source/build-input/notice **OPEN RELEASE BLOCKER** and no-distribution rule remain in force.
