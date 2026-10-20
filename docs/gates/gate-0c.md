# Gate 0C — Android feasibility spike

## Scope, time box, and checkpoint

- **Time box: 1–2 days total.** Sixteen roughly 30-minute task sessions are the target (about eight hours of hands-on work, plus device/build waits). If the two-day limit is reached without the exit evidence, record the result and ask the owner whether to extend the spike; do not call the gate passed.
- Source: `PROJECT.md:31-45,180-195,309-314,341-393,687-692,734-753,814-821`; current status and accepted Gate 0B evidence: `docs/STATE.md`. Gate 0B was accepted on 2026-10-20.
- Strict deliverable: a minimal Tauri Android app and Kotlin plugin use local youtubedl-android with pinned upstream QuickJS 2026-06-04 and a matching yt-dlp/ejs pair to download a real YouTube MP3 into MediaStore Downloads on a physical `arm64-v8a` device. Prototype the foreground service, Home continuation, recents cancellation, interrupted queue recovery, WebView recreation, Android 15 timeout, and direct pending MediaStore ZIP output. No production UI, server, or production Android release.
- Exit evidence: AC-30..35 on real hardware, command/log excerpts and media inspection, notification and process observations, SQLite-restored `paused` state, direct ZIP inspection, and a documented youtubedl-android update/rollback result. Preserve Gate 0B's already-MP3 bitrate, unmeasured YouTube JS challenge, and FFmpeg HTTPS-input limits as limits; do not turn them into Android success claims.
- Ownership: Rust owns the one-item spike queue and its SQLite state; Kotlin contains the engine adapter, MediaStore bridge, and foreground service without a second queue or business rules (`PROJECT.md:381,383,386,392`). `shared/contract.ts` and `src-tauri/src/contract.rs` govern exchanged fields and types. The UI is disposable and reconstructs from `get_queue` plus events. Keep Rust small and comment Android-specific transitions.
- The foreground-service type is still marked **pending** in `PROJECT.md:193`. Task 0C-01 must document current Android requirements and a proposed type; obtain the owner's explicit decision before 0C-08 rather than silently choosing one.
- Each task uses `task-<id>`, one session, its own verification, work commit, `docs/STATE.md` commit, and PR. Before writing library/framework code, consult its current documentation through context7. The named verification commands below are entrypoints **to implement in those tasks**, not commands run by this setup plan. `scripts/gate-0c/verify.ps1` must print at most a concise 50-line result or failure tail; keep full logs and media ignored under `work/android/`, and commit concise evidence under `docs/gates/evidence/0c/`.

## Stop rule

**Any failed hard requirement stops Android implementation and requires an explicit architecture decision from the owner.** Record the exact command, pinned inputs, device/API/ABI, exit status, relevant log lines, and output inspection in `docs/STATE.md` and `docs/gates/evidence/0c/`; then stop. Do not switch runtime, engine, storage API, service ownership, ffmpeg license posture, or acceptance criteria as a workaround. A missing/broken test URL is recorded as fixture evidence and replaced only in a separate fixture task after establishing that it is a fixture failure. The two-day time box is also a stop point for owner review.

## Device and test preparation for the owner

- One **physical arm64-v8a Android device**, ideally **Android 15/API 35 or newer** so the same device can run AC-35. If that is unavailable, a second physical Android 15+ arm64 device is needed; an emulator cannot close AC-30..35. Keep it charged, unlocked for tests, with a reliable USB cable, USB debugging/ADB authorization, network access, and permission to install the debug APK and show notifications. Record device model, ABI, Android/API level, WebView version, and `ANDROID_SERIAL` in local evidence.
- Provide or approve a rights-cleared, publicly playable **real YouTube single URL** for AC-30 and a **long enough rights-cleared URL** to observe several minutes of Home/background work and to interrupt during recents/process-death tests. The locked Gate 0B YouTube fixture can be the first candidate, but its availability and duration must be rechecked. Provide a small rights-cleared multi-entry input (or approved local entry bytes) for the ZIP probe. No credentials, private videos, or tracked media.
- Before device runs, set `ANDROID_SERIAL`, `ZOWNLOAD_ANDROID_YOUTUBE_URL`, `ZOWNLOAD_ANDROID_LONG_URL`, and `ZOWNLOAD_ANDROID_ZIP_URL` as needed. The verifier must reject missing inputs and never silently substitute a different URL. Android 15 timeout testing must use a documented temporary device override and restore its original value afterward.

## Unverified youtubedl-android assumptions to check first

Task 0C-01 checks the **current primary documentation and versioned source**; Appendix C (`PROJECT.md:814-821`) is a research note, not proof of present Android behavior. Record upstream page/commit, selected library version, date, and exact cited API or absence of one. Runtime claims still require the later device tasks.

1. **JS runtime:** whether youtubedl-android can pass yt-dlp's `--js-runtimes quickjs:<path>` and matching yt-dlp-ejs through its API, provide a writable script/cache directory, and execute the pinned QuickJS binary from an Android-allowed packaged location. Do not infer this from desktop yt-dlp support.
2. **yt-dlp update and rollback:** whether its documented updater can select and verify a pinned yt-dlp/ejs version, preserve the bundled baseline, prevent swaps during active work, and restore that baseline after a bad update. A documented update method alone does not prove rollback.
3. **Bundled ffmpeg:** exact bundled artifact/version/architectures, native dependencies, build configuration, redistribution license and source obligations, and whether required MP3 encoding works on arm64. A bundled ffmpeg claim alone does not prove the LGPL-compatible requirement in `PROJECT.md:388`.

If documentation/source cannot support a hard prerequisite, record the gap and invoke the stop rule before integrating an unverified replacement.

## Tasks

### 0C-01 — Versioned Android engine documentation audit

- Goal: check the three assumptions above against current youtubedl-android documentation and versioned source; pin the selected library version and map its API, native artifacts, licenses, yt-dlp/ejs relationship, and open runtime checks. Document current Android foreground-service types and propose one for owner decision. Consult current Tauri/Android/library documentation through context7 before later implementation.
- Files: `docs/gates/evidence/0c/library-audit.md`, `docs/engine-sources.md`, `scripts/gate-0c/verify.ps1`, `docs/STATE.md`.
- Read: `PROJECT.md:348-354,368-373,376,388,753,814-821`.
- Device: **no**.
- Dependencies/parallelism: none; independent of 0C-02. This audit gates 0C-04, 0C-05, and 0C-14.
- Acceptance: versioned primary links and source evidence answer each assumption or name the missing proof; selected artifacts have a hash/provenance plan; no unsupported claim of update, rollback, JS, or LGPL ffmpeg.
- Exact verification command: `powershell -NoProfile -File scripts/gate-0c/verify.ps1 -Case library-audit`.

### 0C-02 — Minimal Tauri Android spike app

- Goal: reduce the existing Gate 0A Android scaffold to a tiny start/status screen and debug hooks for one spike item; keep production UI out of scope.
- Files: `src/App.tsx`, `src/styles.css`, `src-tauri/tauri.conf.json`, `scripts/gate-0c/verify.ps1`, `docs/STATE.md`.
- Read: `PROJECT.md:363-365,373,383,753`.
- Device: **no** (APK build only).
- Dependencies/parallelism: Gate 0B accepted; independent of 0C-01. 0C-03 follows this app shape.
- Acceptance: the pinned single-ABI Android debug APK compiles and exposes the minimal spike screen without production queue/UI features.
- Exact verification command: `npm run android:debug`.

### 0C-03 — Minimal Kotlin Tauri plugin bridge

- Goal: register a Kotlin mobile plugin with one typed smoke command/callback and Rust entrypoint; prove the bridge compiles before adding the engine.
- Files: `src-tauri/src/lib.rs`, `src-tauri/src/android_spike.rs`, `src-tauri/gen/android/app/src/main/java/**`, `src-tauri/gen/android/app/build.gradle.kts`, `docs/STATE.md`.
- Read: `PROJECT.md:372-374,383,386,753`.
- Device: **no** (compile-only bridge proof).
- Dependencies/parallelism: 0C-02; independent of 0C-01. It must land before 0C-04.
- Acceptance: a typed Rust-to-Kotlin call and callback compile for the arm64 APK; Kotlin has no queue or service logic yet.
- Exact verification command: `npm run android:debug`.

### 0C-04 — Pinned youtubedl-android adapter

- Goal: add the 0C-01 pinned youtubedl-android dependency and a minimal Kotlin analyze/download-one/cancel adapter with progress/error callbacks. Inspect the resolved native package and ffmpeg configuration/license before claiming suitability.
- Files: `src-tauri/gen/android/app/build.gradle.kts`, `src-tauri/gen/android/app/src/main/java/**`, `src-tauri/src/android_spike.rs`, `docs/gates/evidence/0c/engine-package.md`, `scripts/gate-0c/verify.ps1`, `docs/STATE.md`.
- Read: `PROJECT.md:348-349,368,372-374,386,388,753`.
- Device: **no** for compile/package audit; runtime is 0C-05/06.
- Dependencies/parallelism: 0C-01 and 0C-03; independent of the later queue prototype.
- Acceptance: pinned dependency resolves, arm64 packaging and adapter compile, actual packaged yt-dlp/ffmpeg inventory is recorded, and the LGPL-compatible ffmpeg obligation is supported or the stop rule fires. No successful download is claimed here.
- Exact verification command: `powershell -NoProfile -File scripts/gate-0c/verify.ps1 -Case engine-package`.

### 0C-05 — Pinned QuickJS and matching ejs on device

- Goal: package the Gate 0B attested upstream QuickJS 2026-06-04 arm64 build as an Android-executable native artifact, pair it with the selected yt-dlp/ejs versions, pass the explicit runtime option, and run a device smoke probe with writable temporary files.
- Files: `scripts/gate-0c/package-quickjs.ps1`, `src-tauri/gen/android/app/build.gradle.kts`, `src-tauri/gen/android/app/src/main/java/**`, `.gitignore`, `docs/gates/evidence/0c/quickjs.md`, `scripts/gate-0c/verify.ps1`, `docs/STATE.md`; generated native output under ignored `work/android/` or the Android build tree.
- Read: `PROJECT.md:348,354,370,373,753,814-821`.
- Device: **physical arm64 required**.
- Dependencies/parallelism: 0C-01 and 0C-04; independent of 0C-07 after adapter API stabilizes.
- Acceptance: packaged QuickJS hash/version matches the pinned build, device process can execute it, yt-dlp reports the selected runtime and matching ejs, and writable temp/cache use is demonstrated. A normal YouTube result alone is insufficient proof of JS execution.
- Exact verification command: `powershell -NoProfile -File scripts/gate-0c/verify.ps1 -Case quickjs-device`.

### 0C-06 — Real YouTube MP3 in MediaStore Downloads (AC-30)

- Goal: use the plugin and pinned engine/runtime to download a real approved YouTube single, convert to MP3, write through a pending MediaStore Downloads row, publish it, and inspect the user's Downloads result.
- Files: `src-tauri/gen/android/app/src/main/java/**`, `src-tauri/src/android_spike.rs`, `src/App.tsx`, `docs/gates/evidence/0c/youtube-mp3.md`, `scripts/gate-0c/verify.ps1`, `docs/STATE.md`.
- Read: `PROJECT.md:35,349,368,372-374,392,687,753`.
- Device: **physical arm64 required**.
- Dependencies/parallelism: 0C-05; 0C-14 can be investigated independently after 0C-04.
- Acceptance: AC-30 passes on the real device; capture yt-dlp/runtime/ffmpeg logs, MediaStore URI/display name/MIME, SHA-256 and probed MP3 stream, plus manual playback observation. Clean or explicitly account for pending rows on failure.
- Exact verification command: `powershell -NoProfile -File scripts/gate-0c/verify.ps1 -Case youtube-mp3`.

### 0C-07 — Durable one-item Rust queue and disposable UI

- Goal: add a minimal SQLite-backed Rust queue with durable progress/status checkpoints, `get_queue` and events; interrupted active states restore as `paused` and never auto-resume. Keep this a one-item spike, not the full production queue.
- Files: `src-tauri/src/android_spike.rs`, `src-tauri/src/lib.rs`, `src-tauri/Cargo.toml`, `src/App.tsx`, `docs/gates/evidence/0c/queue.md`, `docs/STATE.md`.
- Read: `PROJECT.md:190-194,309-313,381,383,386,689-691,753`.
- Device: **no** for focused Rust persistence test; device lifecycle validation follows.
- Dependencies/parallelism: 0C-03 and 0C-06; 0C-14 is independent after 0C-04.
- Acceptance: a killed/recreated queue owner restores active states as `paused`; contract JSON field names and types match both authority files; no second queue exists in Kotlin.
- Exact verification command: `cargo test --manifest-path src-tauri/Cargo.toml android_spike_queue`.

### 0C-08 — Foreground service and notification

- Goal: after the owner selects the service type from 0C-01 evidence, add a minimal foreground service and notification, started/stopped by Rust-owned work; Kotlin keeps no queue, and the service handles the documented Android 15 timeout callback.
- Files: `src-tauri/gen/android/app/src/main/AndroidManifest.xml`, `src-tauri/gen/android/app/src/main/java/**`, `src-tauri/src/android_spike.rs`, `docs/gates/evidence/0c/service.md`, `scripts/gate-0c/verify.ps1`, `docs/STATE.md`.
- Read: `PROJECT.md:190,193,351-352,386,688,692,753`.
- Device: **physical arm64 required**.
- Dependencies/parallelism: 0C-01, 0C-07, and the owner's foreground-service-type decision; 0C-14 remains independent.
- Acceptance: notification and active service are observable on device during a controlled job; service startup/stop and Rust callback path are logged; no Kotlin queue logic is introduced.
- Exact verification command: `powershell -NoProfile -File scripts/gate-0c/verify.ps1 -Case foreground-service`.

### 0C-09 — Home continuation (AC-31)

- Goal: press Home during a long download and observe continuing work for several minutes with visible foreground notification and changing progress.
- Files: `scripts/gate-0c/verify.ps1`, `docs/gates/evidence/0c/home.md`, `docs/STATE.md` (implementation fix files only if the probe exposes a defect).
- Read: `PROJECT.md:190,309-311,351,386,688,753`.
- Device: **physical arm64 required**.
- Dependencies/parallelism: 0C-08; independent of 0C-14 and 0C-13 after shared files are integrated.
- Acceptance: AC-31 evidence includes start/end timestamps separated by several minutes, monotonic durable progress, notification screenshots/logs, and completed or still-running local engine work after Home.
- Exact verification command: `powershell -NoProfile -File scripts/gate-0c/verify.ps1 -Case home`.

### 0C-10 — Removal from recents cancels work (AC-32)

- Goal: remove the app from recents during an active download; Rust persists `paused`, cancels engine work, and stops the service.
- Files: `src-tauri/gen/android/app/src/main/java/**`, `src-tauri/src/android_spike.rs`, `scripts/gate-0c/verify.ps1`, `docs/gates/evidence/0c/recents.md`, `docs/STATE.md`.
- Read: `PROJECT.md:190-194,309-313,351,386,689,753`.
- Device: **physical arm64 required**.
- Dependencies/parallelism: 0C-08; independent of 0C-13/14 after shared files are integrated.
- Acceptance: AC-32 passes: notification disappears, active engine and child PIDs are absent, no media keeps growing, and reopening shows the durable item as `paused`.
- Exact verification command: `powershell -NoProfile -File scripts/gate-0c/verify.ps1 -Case recents`.

### 0C-11 — Process death and `.part` recovery (AC-33)

- Goal: abruptly kill the process with adb during a download, reopen, prove no automatic restart, then explicitly Continue from the existing `.part` file.
- Files: `src-tauri/src/android_spike.rs`, `src-tauri/gen/android/app/src/main/java/**`, `scripts/gate-0c/verify.ps1`, `docs/gates/evidence/0c/process-death.md`, `docs/STATE.md`.
- Read: `PROJECT.md:191-194,309-313,351,386,690,753`.
- Device: **physical arm64 required**.
- Dependencies/parallelism: 0C-07 and 0C-08; independent of 0C-13/14 after shared files are integrated.
- Acceptance: AC-33 passes: process/engine work dies, reopened `get_queue` shows `paused`, no bytes resume until Continue, and logs plus prefix/hash evidence show resumption from the saved `.part`.
- Exact verification command: `powershell -NoProfile -File scripts/gate-0c/verify.ps1 -Case process-death`.

### 0C-12 — WebView/Activity recreation (AC-34)

- Goal: rotate, lock/unlock, or deliberately recreate the Activity during an active job; the tiny UI resubscribes and reloads `get_queue` without changing Rust-owned work.
- Files: `src/App.tsx`, `src-tauri/src/android_spike.rs`, `scripts/gate-0c/verify.ps1`, `docs/gates/evidence/0c/webview.md`, `docs/STATE.md`.
- Read: `PROJECT.md:192,351,386,691,753`.
- Device: **physical arm64 required**.
- Dependencies/parallelism: 0C-07 and 0C-08; independent of 0C-13/14 after shared files are integrated.
- Acceptance: AC-34 passes with before/after queue ID, status/progress, event subscription and no duplicate job.
- Exact verification command: `powershell -NoProfile -File scripts/gate-0c/verify.ps1 -Case webview-recreate`.

### 0C-13 — Direct pending MediaStore ZIP output

- Goal: prototype a ZIP streamed into a pending MediaStore Downloads row, with no completed ZIP first written to private storage. Rust decides entries/order; Kotlin only brokers the Android storage handle.
- Files: `src-tauri/src/android_spike.rs`, `src-tauri/gen/android/app/src/main/java/**`, `src-tauri/Cargo.toml`, `scripts/gate-0c/verify.ps1`, `docs/gates/evidence/0c/zip.md`, `docs/STATE.md`.
- Read: `PROJECT.md:349,374,379,386,392,753`.
- Device: **physical arm64 required**.
- Dependencies/parallelism: 0C-06 and 0C-07; independent of 0C-09..12 and 0C-14 after shared adapter edits are integrated.
- Acceptance: pending row is hidden until closed/published; the resulting Downloads ZIP opens with expected entries/hashes; failed writes remove or retain a clearly recorded pending row; no second full ZIP copy or Kotlin queue is created.
- Exact verification command: `powershell -NoProfile -File scripts/gate-0c/verify.ps1 -Case mediastore-zip`.

### 0C-14 — yt-dlp update and rollback proof

- Goal: test the 0C-01 documented youtubedl-android updater on a device, including pinned/checksummed candidate, no swap during a job, failed-candidate preservation, and restoration of the bundled baseline after a safely injected post-acceptance failure. Preserve exact version/ejs identity.
- Files: `src-tauri/gen/android/app/src/main/java/**`, `docs/gates/evidence/0c/update-rollback.md`, `scripts/gate-0c/verify.ps1`, `docs/STATE.md`.
- Read: `PROJECT.md:185,187,356,376,386,753,820`.
- Device: **physical arm64 required** for runtime proof.
- Dependencies/parallelism: 0C-01 and 0C-04; independent of 0C-07..13 after shared adapter edits are integrated.
- Acceptance: document whether update **and** rollback work, with baseline/candidate hashes, observed version, active-job exclusion and recovery logs. If a required safe rollback is unsupported, invoke the stop rule instead of claiming the updater works.
- Exact verification command: `powershell -NoProfile -File scripts/gate-0c/verify.ps1 -Case update-rollback`.

### 0C-15 — Android 15 foreground-service timeout (AC-35)

- Goal: on a physical Android 15+ device, trigger the documented test timeout for the chosen service type; Rust pauses work, notification explains the pause, and state survives reopen.
- Files: `src-tauri/gen/android/app/src/main/java/**`, `src-tauri/src/android_spike.rs`, `scripts/gate-0c/verify.ps1`, `docs/gates/evidence/0c/timeout.md`, `docs/STATE.md`.
- Read: `PROJECT.md:193,352,386,692,753`.
- Device: **physical Android 15+ arm64 required**.
- Dependencies/parallelism: 0C-07 and 0C-08; independent of 0C-13/14 after shared files are integrated.
- Acceptance: AC-35 passes with timeout callback, paused SQLite state, explanatory notification, no crash/lost progress, and restoration of the device's original test setting.
- Exact verification command: `powershell -NoProfile -File scripts/gate-0c/verify.ps1 -Case android15-timeout`.

### 0C-16 — Gate evidence and owner checkpoint

- Goal: review AC-30..35 and all Gate 0C hard requirements against exact logs, device details, media hashes/playback, ZIP contents, orphan-process check and updater/rollback findings; list any limit without claiming a pass.
- Files: `docs/gates/gate-0c.md`, `docs/gates/evidence/0c/checkpoint.md`, `scripts/gate-0c/verify.ps1`, `docs/STATE.md`.
- Read: `PROJECT.md:687-692,734-753,814-821`.
- Device: **no new device run**; requires the recorded physical-device evidence.
- Dependencies/parallelism: 0C-01..15; final and not parallel.
- Acceptance: every hard requirement has linked passing evidence, or the gate is stopped with the owner's required architecture decision pending. Passing local evidence prepares the checkpoint; only explicit owner acceptance opens Phase 1.
- Exact verification command: `powershell -NoProfile -File scripts/gate-0c/verify.ps1 -Case gate`.

## Thirty-minute risks and planned splits

- **0C-04/05:** dependency resolution, native library audit or QuickJS packaging may exceed one session. Split 0C-04 into dependency/package audit and adapter compile; split 0C-05 into packaged hash/build and device runtime proof. Do not claim a runtime pass from compilation.
- **0C-06:** real YouTube extraction/conversion and MediaStore publish may exceed one session. Split into private-output engine proof and pending-row publish (`0C-06A/B`); AC-30 requires the combined result.
- **0C-11:** interruption and actual `.part` resume may require two stable network runs. Split kill/restore and explicit resume (`0C-11A/B`) while keeping AC-33 open.
- **0C-13:** split MediaStore write-handle/`IS_PENDING` proof from ZIP streaming/inspection (`0C-13A/B`) if the Rust-to-Kotlin handle needs extra work.
- **0C-14/15:** split updater API/negative cases from device rollback (`0C-14A/B`), or timeout configuration from callback recovery (`0C-15A/B`), if either takes longer than 30 minutes.
- Any split is recorded in this gate file and `docs/STATE.md` before further implementation. A split does not extend the **1–2 day** spike by itself. CI/device/network waits can be recorded with an ID and reviewed in a new session; never mark a pending run passed.

## Delivery

After 0C-16 passes, commit the evidence and state, open the task PR, and request explicit owner acceptance. Do not begin Phase 1 or production Android work until that checkpoint is accepted. A failed hard requirement follows the stop rule above.
