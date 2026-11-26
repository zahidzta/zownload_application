<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 5B — Android storage and lifecycle

## Scope and checkpoint

This plan covers production Android Downloads output and lifecycle handling.
Gate 5A was accepted by the owner on 2026-11-25; see its [checkpoint](evidence/5a/checkpoint.md).
The owner accepted this plan and its eight-session budget checkpoint on
2026-11-25. Implementation may begin with task 5B-02.

Gate 5B delivers individual and ZIP output through MediaStore, a foreground
service with progress notification, Home/background continuation, cancellation
on removal from recents, safe process-death recovery, and Android 15 timeout
handling. Rust remains the owner of queue state and persistence. Kotlin service
code only keeps active work in the foreground and reports lifecycle signals.

Read the relevant requirements through `docs/PROJECT-INDEX.md` before each task:
`PROJECT.md:132-168,180-195,630-645,646-693,787-793`. These define queue and
storage behavior, Android lifecycle, device verification, AC-31..35, and the
Stage 5B deliverable.

### Accepted constraints

- Save through the public Downloads MediaStore collection. Hide the Android
  folder selector; do not use SAF.
- With ZIP disabled, save playlist entries sequentially as separate named
  files. With ZIP enabled, keep one pending partial archive and only the
  current entry's work files, add verified entries uncompressed, remove each
  entry's work files before continuing, and finalize the archive on success.
- Never overwrite a file. Resolve filename collisions with numbered names.
  On storage failure, stop child work, clean incomplete output where safe, and
  persist the existing typed error notification.
- Interrupted queue work restores as paused and never resumes automatically;
  Continue resumes from owned `.part` data. The Rust queue remains the source
  of truth after Activity/WebView recreation.
- Use the owner-approved `dataSync` foreground service with progress-only
  notification behavior. Add no notification actions, public contract fields,
  or dependencies without a separate owner decision.
- Keep Android APKs and build outputs local while the distribution blocker is
  open. Do not attach or publish them.

### Budget and dependencies

Approved budget: eight tasks, each planned as one roughly 30-minute session
(about four planned hours). Android builds, physical-device setup, and long
playlist runs can extend elapsed time. This estimate is not a time guarantee.

Before device acceptance, the owner must provide a physical `arm64-v8a`
Android 15 (API 35) device and a rights-cleared large-playlist fixture. The
existing OnePlus BE2011 / API 29 remains useful for regression but cannot prove
AC-35.

No contract or architecture change is planned. Task 5B-02 must confirm the
MediaStore output boundary against the existing Android engine bridge. Stop for
owner review if implementation would require new contract fields, a major
architecture change, a dependency, or a licensing change.

## Tasks

Each task uses its own `task-<id>` branch, work commit, separate `docs/STATE.md`
commit, and PR. Long builds and device waits may exceed one session. Do not
start a dependent task before its predecessor and required owner decisions pass.

### 5B-01 — Plan, budget, and Gate 5A checkpoint record

- Goal: record Gate 5A owner acceptance and prepare this scoped Gate 5B plan.
- Files: `docs/STATE.md`, `docs/gates/gate-5a.md`, `docs/gates/gate-5b.md`,
  `docs/gates/evidence/5a/`.
- Acceptance: Gate 5A acceptance is recorded; this plan identifies requirements,
  dependencies, tasks, verification, and a budget proposal for owner review.
- Exact verification: `git diff --check`.
- Result: Owner accepted the Gate 5B plan and budget checkpoint on 2026-11-25.

### 5B-02 — MediaStore single-file output

- Goal: publish completed MP3/MP4 outputs to public Downloads with safe naming,
  cleanup on failure, and no overwrite.
- Files: focused Android engine plugin/output provider, `src-tauri/src/engine/`
  Android integration, focused Kotlin/Rust tests, and Gate 5B evidence.
- Read: `PROJECT.md:156-168,180-195,394-461,618-629`; consult current Android
  and Tauri mobile-plugin documentation through Context7 before code changes.
- Dependencies: Gate 5B plan and budget accepted. No contract changes or new
  dependencies without owner approval.
- Acceptance: successful content is visible in Downloads; collisions are
  numbered; failed writes leave no incomplete visible item and map to the
  existing typed error path.
- Exact verification: `powershell -NoProfile -File scripts/gate-5b/verify.ps1 -Case mediastore-single`.

### 5B-03 — MediaStore ZIP output and storage recovery

- Goal: integrate the existing sequential ZIP rules with a pending MediaStore
  archive while avoiding a second complete playlist copy.
- Files: focused Android output provider, Rust ZIP/output integration and tests,
  plus Gate 5B evidence.
- Read: `PROJECT.md:156-168,630-645`; consult current Android storage and Rust
  API documentation through Context7 before code changes.
- Dependencies: 5B-02; no new contract fields.
- Acceptance: resume preserves the partial archive; verified entries are added
  uncompressed and their work files are removed before the next entry starts;
  collisions and disk-full failures follow the confirmed rules.
- Exact verification: `powershell -NoProfile -File scripts/gate-5b/verify.ps1 -Case mediastore-zip`.

### 5B-04 — Production foreground service and notification

- Goal: connect the existing service path to production Rust queue activity,
  progress, pause, idle, and terminal states.
- Files: focused Android service/plugin/manifest code, bridge tests, and Gate
  5B evidence.
- Read: `PROJECT.md:180-195,618-645,646-693`; consult current Android service
  and Tauri lifecycle documentation through Context7 before code changes.
- Dependencies: 5B-02; 5B-03 may proceed independently after 5B-02.
- Acceptance: the `dataSync` service starts before long work, shows progress,
  and stops after queue work ends; Kotlin owns no queue or business state.
- Exact verification: `powershell -NoProfile -File scripts/gate-5b/verify.ps1 -Case foreground-service`.

### 5B-05 — Recents removal and process-death recovery

- Goal: cancel active work on recents removal and restore interrupted work as
  paused after process death, retaining resumable owned `.part` data.
- Files: focused Android lifecycle bridge, Rust queue recovery, device tests,
  and Gate 5B evidence.
- Read: `PROJECT.md:180-195,630-645,646-693`; consult current Android lifecycle
  documentation through Context7 before code changes.
- Dependencies: 5B-04.
- Acceptance: AC-32 and AC-33 pass; child processes and service stop on recents
  removal; process death restores paused state without auto-resume; Continue
  resumes safely from owned partial data.
- Exact verification: `powershell -NoProfile -File scripts/gate-5b/verify.ps1 -Case lifecycle-recovery`.

### 5B-06 — Home continuation and disposable UI recovery

- Goal: keep active work alive after Home and restore the correct UI state after
  Activity/WebView recreation.
- Files: focused Android lifecycle glue, existing queue/event integration,
  device tests, and Gate 5B evidence.
- Read: `PROJECT.md:180-195,630-645,646-693`; consult current Tauri Android
  lifecycle documentation through Context7 before code changes.
- Dependencies: 5B-04; may proceed alongside 5B-05 if changes stay in separate
  test and lifecycle modules.
- Acceptance: AC-31 and AC-34 pass; foreground notification progress updates;
  recreated UI calls `get_queue` and subscribes to events without duplicate or
  lost queue state.
- Exact verification: `powershell -NoProfile -File scripts/gate-5b/verify.ps1 -Case home-and-recreation`.

### 5B-07 — Android 15 foreground-service timeout

- Goal: pause queue work safely when Android reports the `dataSync` service
  timeout and explain recovery in the notification.
- Files: focused service timeout handling, Rust pause/recovery integration,
  Android 15 device test, and Gate 5B evidence.
- Read: `PROJECT.md:180-195,630-645,646-693`; consult current Android timeout
  documentation through Context7 before code changes.
- Dependencies: 5B-04 and 5B-05.
- Acceptance: AC-35 passes on a physical Android 15 device; no crash or lost
  progress; work stays paused until the user opens the app and continues.
- Exact verification: `powershell -NoProfile -File scripts/gate-5b/verify.ps1 -Case foreground-timeout`.

### 5B-08 — Integrated device proof and checkpoint

- Goal: run the full Android 5B acceptance matrix and record output, lifecycle,
  and large-playlist storage evidence.
- Files: focused fixes, `docs/gates/evidence/5b/`, `docs/STATE.md`.
- Read: `PROJECT.md:156-168,180-195,630-645,646-693,787-793`; accepted 5B-02
  through 5B-07 evidence.
- Dependencies: 5B-02 through 5B-07; owner-provided API 35 device and
  rights-cleared large-playlist fixture.
- Acceptance: AC-31..35 and the large-playlist storage test pass; evidence
  states device/API/ABI, APK hash, fixture rights, outcomes, and limitations.
  Owner acceptance is required before Gate 5C.
- Exact verification: `powershell -NoProfile -File scripts/gate-5b/verify.ps1 -Case device-acceptance`.

## Verification

Gate 5B verification cases are added by their owning tasks. Keep full logs and
local APKs under ignored `work/android/`; do not commit or publish Android
build outputs. The first plan checkpoint uses `git diff --check` and relative
Markdown-link review.

## Delivery

Commit each verified task and the corresponding `docs/STATE.md` update on the
task branch, then open a PR. Do not merge or publish Android artifacts. Do not
start Gate 5C until the owner accepts the Gate 5B checkpoint.
