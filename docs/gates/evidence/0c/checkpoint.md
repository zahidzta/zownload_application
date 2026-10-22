<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 0C checkpoint evidence — task 0C-16

Prepared 2026-10-21 for **owner review** against [Gate 0C](../../gate-0c.md) and
[`PROJECT.md:687-692,734-753,814-821`](../../../../PROJECT.md). All six Android
acceptance criteria have passing physical-device evidence at the scope stated
below. The result is **technical feasibility on the owner's devices only**.
Owner acceptance is **PENDING**; Phase 1 remains closed. The 0C-04A waiver
applies only to the native corresponding-source/build-input/notice gap and does
not authorize Android distribution.

## Devices, engine and media

The physical **OnePlus BE2011**, `ANDROID_SERIAL=b1c28e0d`, Android API 29,
`arm64-v8a`, WebView `155.0.8059.43`, supplied the engine, media, queue and
lifecycle runs. The physical **P90**, `ANDROID_SERIAL=P90260624026832`, Android
API 35, `arm64-v8a`, WebView `153.0.8010.39`, supplied the system timeout run.
Each linked record gives its exact verifier command, result, device observations,
and debug APK SHA-256. Full logs and media are ignored locally under
`work/android/`; this checkpoint reviews the committed excerpts and hashes.

- [0C-01 source audit](library-audit.md) and the [Option A decision](architecture-decision.md)
  established the versioned library APIs, GPL implications and need for custom
  update/rollback. [0C-01B licence audit](licence-compat.md) and the 0C-01C
  revision record in [state](../../../STATE.md) document the owner-selected
  `GPL-3.0-or-later` requirement. The same state records successful pinned
  arm64 debug APK builds for 0C-02's disposable screen and 0C-03's typed
  Rust/Kotlin smoke bridge. Those two build checks were compile/packaging
  evidence; 0C-06 later exercised the complete command path on device.
- [0C-04/04B package inventory](engine-package.md) records pinned
  youtubedl-android `0.18.1` `library`, `ffmpeg` and transitive `common` AARs,
  arm64-only APK packaging, and the feasibility-only reintegration. [0C-05
  runtime proof](quickjs.md) records the pinned upstream QuickJS `2026-06-04`
  arm64 hash `4db3b8aeba709b4907da59a87f1ab3f94585bae3a95f7b02c946b7732cd20185`,
  yt-dlp `2026.08.19` zipapp hash
  `1fa6733c37ea6fb51c99ad8fe785e7b7e5f3246c9b980230329d4fb72ed8d4d6`,
  EJS `0.8.0`, executable QuickJS, writable cache and matching device runtime
  selection. The 0C-05 simulate probe alone did not exercise YouTube media.
- [0C-06 real YouTube MP3](youtube-mp3.md) ran the locked rights-cleared
  `uW13KuRrg1g` single through the Tauri WebView, Rust and Kotlin adapter.
  Device logs report yt-dlp `2026.08.19`, EJS `0.8.0`, QuickJS `2026-06-04`,
  FFmpeg `libmp3lame`, and a successful MediaStore publish at
  `content://media/external/downloads/9623`. The row was `IS_PENDING=0`, MIME
  `audio/mpeg`, 236,588 bytes, with no pending Downloads row left. Pulled bytes
  and content URI matched SHA-256
  `3a8e6ff5c2d2ae91216dfd4747ea4b9223d0545b25146683ff99a3c814ec1cda`.
  Pinned FFprobe identified a 14.721458-second stereo MP3 at 128,000 bps;
  the owner heard it play from start to end on the OnePlus. The record does
  not isolate whether this specific YouTube extraction needed a JS challenge.

## AC-30..35 review

| Criterion | Recorded result and exact evidence | Scope limit |
|---|---|---|
| **AC-30 — real YouTube MP3** | **Pass:** the published MP3, URI, hash, FFprobe result and audible playback are above in [0C-06](youtube-mp3.md). | One API 29 device and one rights-cleared single; API 24–28 Downloads output is unresolved. |
| **AC-31 — Home continuation** | **Pass:** [0C-09](home.md) records `HOME_TEST_OK`, 180.372 seconds after Home, 12 durable SQLite samples rising monotonically from 0% to 34%, notification ID 108 visible, and continued engine work. Screenshot SHA-256 `ed474769061ee67e8cb92af02c9f72cc7046c3a38eb1b872be9b16144754cf46`; the screenshot remains local because the Home screen is personal. | Debug-only 32K limit kept the transfer observable; completion after Home was not tested. |
| **AC-32 — recents removal** | **Pass:** [0C-10](recents.md) records `TASK_REMOVED`, Rust's paused SQLite checkpoint, `killed=true workerExited=true`, no observed child PID, no active notification or growing/private media files, and the same paused item from reopened `get_queue`. | `finishAndRemoveTask()` exercised Android's task-removal callback; a launcher swipe gesture was not separately tested. |
| **AC-33 — process death and `.part`** | **Pass:** [0C-11](process-death.md) records `adb shell am force-stop`, absent app/child PIDs, the same paused item after reopening, and a `.part` fixed at 129,626 bytes for five idle seconds. Only Continue grew it to 259,674 bytes; the first 8,192 bytes retained SHA-256 `6fdea32e8a8858239355e4355f00b87675fa003f19cb93da082608b49b21e579`. | The device denied direct shell/`run-as` signals, so the test cannot isolate whether Android or parent death killed the child. It did not wait for resumed MP3 publication. |
| **AC-34 — WebView recreation** | **Pass:** [0C-12](webview.md) records a new Activity/WebView restoring item `08b0f46f-c69e-4928-960d-d81d79e0c45a` from `get_queue`, receiving a later 1% event, and retaining child PID 17471 without a second worker. | Deliberate `MainActivity.recreate()`; rotation and lock/unlock were not run. |
| **AC-35 — Android 15 timeout** | **Pass:** [0C-15](timeout.md) records P90 API 35 `dataSync` `onTimeout(startId=1, fgsType=1)`, a paused SQLite and reopened queue item at 3%, explanatory notification, exited engine child, and 554,983 retained `.part` bytes with stable prefix hash. The `15000` ms test override was restored to its original `null`. | One rate-limited download; no six-hour playlist or later Continue after timeout. |

## Other Gate 0C hard requirements

- [0C-07 queue proof](queue.md) tests Rust's one-item SQLite snapshots,
  interrupted-state restoration, contract field names, and one-item limit.
  [0C-08 service proof](service.md) observes `dataSync` service startup,
  notification ID 108 and stop around a real job. Rust owns status and
  progress; Kotlin owns the adapter, service and storage stream without a
  second queue. Later device runs above exercise restoration and live events.
- [0C-13 direct ZIP](zip.md) writes 16 KiB chunks to one pending MediaStore
  URI, hidden from a separate APK UID until close. The published 262,449-byte
  ZIP SHA-256 is
  `009c0141328d975b3a696bf3135f16d07966bbc56dd558815415e653909ca2d6`;
  it opens with `manifest.txt` then `payload.bin`. The latter's 262,144
  uncompressed bytes match SHA-256
  `2312394bd99545d9de131c24efb781e765ac1aec243f2ed9347597a793a415e9`.
  Fault injection deleted a second pending URI; no full private ZIP copy was
  found. The fixture contains synthetic entries, not a real playlist.
- [0C-14 custom update/rollback](update-rollback.md) rejects an active-job
  reservation and bad candidate without changing the baseline hash. A pinned
  HTTPS yt-dlp `2026.10.21`/EJS `0.8.0` zipapp with SHA-256
  `b7af77f686e95f7845ce8d09d21957718febb8b48b30555adb9dd2292ad7bf14`
  passed hash, identity and runtime checks before the private atomic swap.
  After an injected post-acceptance failure, the adapter restored and ran
  baseline `2026.08.19` with SHA-256
  `1fa6733c37ea6fb51c99ad8fe785e7b7e5f3246c9b980230329d4fb72ed8d4d6`.
  The tagged library updater was not used. The test reserved a job rather
  than running a simultaneous transfer and did not download media with the
  candidate or kill the app during a rename.

## GPL package/source inventory and release blocker

The repository now declares `GPL-3.0-or-later`; [0C-01B](licence-compat.md)
checked 17 direct npm/Cargo dependencies, while the [0C-04 AAR audit](engine-package.md)
records Maven Central SHA-256 values for `library`, `ffmpeg`, and `common`, their
GPL-3.0 POM declarations, FFmpeg 7.1.1 with `--enable-gpl`, x264 and x265,
and a [361-row native file manifest](engine-package-native.tsv). The library
contains Python 3.12 and nested native modules; the FFmpeg archive contains
`libffmpeg.so`, `libffprobe.so` and nested codecs. This is an artifact
inventory, **not** corresponding source or a complete licence audit.

The tagged build notes omit exact arm64 Termux commits, source tarballs,
patches and build recipes/configuration, and the nested archives have no
licence/notice paths. The owner's [0C-04A decision](engine-package.md#corresponding-source-and-notice-gap--release-blocker)
waived the **Gate 0C stop rule for this gap alone**. The exact native
corresponding-source/build-input/notice gap remains an **OPEN RELEASE BLOCKER**.
No Android APK or build may be published, uploaded, attached to a GitHub
release, or shared with anyone until it is resolved. Local technical
feasibility does not establish Android redistribution readiness.

### Open pre-release evidence checklist

- [ ] **Replace third-party native binaries with traceable ones:** build
  minimal pinned arm64 FFmpeg **and ffprobe** without x264/x265, pinned
  QuickJS, and a traceable Python runtime with yt-dlp. Preserve the adapter's
  package interface. An owner-reviewed alternative is required if replacement
  overruns the budget; the current provenance gap cannot close silently.
- [ ] Provide corresponding source, exact build inputs/configuration,
  patches and third-party notices for every Android native binary and
  packaged dependency.
- [ ] Complete legal review before the first public release.
- [ ] Complete the full transitive dependency licence and notice audit before
  the first release; the 17 direct-package check is insufficient.
- [ ] Measure the **release** Android APK size after replacement. The roughly
  265 MB engine-bearing debug package is a baseline, not a release APK result.
- [ ] Resolve the API 24–28 Downloads output path before claiming the stated
  Android minimum, and verify Phase 5 foreground-service/UI follow-ups before
  a production Android release.

**Checkpoint recommendation:** accept Gate 0C for *local technical
feasibility* if the owner agrees with the stated probe limits and the single
0C-04A waiver. Record the owner's explicit decision before starting Phase 1.
This recommendation does not close any checklist item or authorize Android
distribution.
