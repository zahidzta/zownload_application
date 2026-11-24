<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 5A-06 — Android package provenance evidence

## Result

The local `arm64-v8a` debug APK build and package provenance verification passed
on 2026-11-23. The [machine manifest](5a-06-apk-engine-manifest.json) records
the exact APK and staged payload hashes, source materials, build manifests,
component inventory, and audit record hashes.

- APK SHA-256: `03aca66c894c0f76fb08d79e24b1c980149448ffa1752503d7091b962bc77b91`
- APK size: 145,666,028 bytes; ABI: `arm64-v8a`.
- Verified engine payload: 4,230 files (116,192,664 staged bytes), including
  `assets/python-runtime.zip` with 4,219 entries.
- The manifest records 24 source materials and 22 transitive components.
- The verifier confirmed the staged payload hashes against the locked build
  outputs, checked each runtime archive entry, and found no `0.18.1` engine AAR
  or its payload/classes in the APK.

Commands run:

```powershell
powershell -NoProfile -File scripts/gate-5a/stage-android-package.ps1
npm run android:debug
powershell -NoProfile -File scripts/gate-5a/verify.ps1 -Case package-provenance
```

The Android build used the task-pinned Corretto 21 JDK described in
[`docs/toolchain.md`](../../../toolchain.md#5a-06-android-package-build).

## Limits and handoff

This verifies package contents and provenance only. It does not prove Android
engine behavior on a device. The APK debug variant excludes the four legacy
0C Kotlin classes that depended on the removed AAR API; task 5A-07 must wire a
provider that extracts the Python runtime archive and implements the production
engine interface. Physical-device behavior remains for 5A-09.

The APK and build output remain local under ignored `src-tauri/gen/android/`
build output and are not included in commits or PRs. APK/build sharing remains
prohibited until the owner reviews this evidence and explicitly records blocker
closure.
