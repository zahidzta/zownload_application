<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 2A — SQLite persistence and the Rust command boundary

## Scope and authority

The owner explicitly accepted the [Gate 1C checkpoint](evidence/1c/checkpoint.md) on 2026-10-24 and requested this plan. [Appendix A](../../PROJECT.md) requires focused tests, applicable manual evidence, review, and explicit owner acceptance of the **2A checkpoint** before Stage 2B. This plan records the handoff; it does not implement persistence or accept 2A results.

Stage 2A replaces the running mock's browser-backed data with one Rust-owned SQLite database for Settings, History, Queue, and error notifications. It registers the contract command/event boundary and proves that the existing UI can read and mutate that durable state in a Windows Tauri app. `shared/contract.ts` and `src-tauri/src/contract.rs` govern exchanged fields and types; [PROJECT-INDEX](../PROJECT-INDEX.md) locates the narrow `PROJECT.md` ranges below. Stage 2A does not run yt-dlp, create media or `.part` files, or claim real pause/resume. Real desktop analysis belongs to 2B, single download execution to 2C, engine updates to 2D, and playlist execution to 3A.

The pinned `rusqlite` crate is already in `src-tauri/Cargo.toml`; no new dependency is planned. Keep the Gate 0C Android spike and its separate `android-spike-queue.sqlite3` intact. Use one versioned production database under Tauri's app-local data directory. The confirmed History and Settings shapes in `PROJECT.md:484-509` are the baseline. The Queue table in `PROJECT.md:522-536` is a proposal: 2A stores the contract snapshot and queue position; later additive migrations can add engine-only playlist cursor data when 3A needs it. Do not treat mock browser storage as production data.

Each task is one session on its own `task-<id>` branch. After its exact verification, commit the task, update `docs/STATE.md` in a separate commit, open a PR with `& 'C:\Program Files\GitHub CLI\gh.exe' pr create`, and stop. Never merge, force-push, release, or start 2B without owner acceptance. New hand-written source files begin with the GPL-3.0-or-later/zahidzta/2026 SPDX header. Before writing code with Tauri, `rusqlite`, React, or another library/framework, consult its current documentation through context7. Keep terminal output to failures or the last 50 lines.

## Owner decisions and 2A boundaries

1. **Development preview — decided 2026-10-24.** In a development Tauri run, the existing UI may use the offline mock for `analyze_url` only, then send enqueue, reads, writes, and event subscriptions to Rust. Browser-only mock tests remain available. Production native `analyze_url` returns a typed deferred-engine error until 2B. This adapter must be visibly limited to development and must not create a second persistence store.
2. **Queue without an engine — decided 2026-10-24.** Native `enqueue_download` commits a `queued` item and emits its full snapshot; it never starts work in 2A. `remove_download` deletes a queued item. With no running engine job, `pause_download` and `resume_download` reject with typed `AppError`; they do not simulate `.part` continuation. Seeded interrupted states still recover as `paused` on startup, without auto-resume. The comment in `shared/contract.ts` that describes redownload entering `analyzing` first conflicts with this temporary 2A behavior; reconcile the comment during native integration without changing wire fields or types. Real analysis/lifecycle takes over in 2B/2C.
3. **Deferred commands.** Register every contract command name so an unavailable engine feature rejects as typed `AppError`, rather than as an unregistered Tauri command. `engine_check_update` and `engine_update` do not report invented versions or perform network work; 2D replaces their deferred behavior.
4. **Durability and events.** A command reports success and emits its contract event only after its SQLite change commits. Queue order is persisted, History is unique by the exact request and ordered by descending id, and notifications survive restart until successful dismissal. A terminal helper atomically writes History or an error notification before deleting the queue item, even though 2A has no real terminal download path. No new contract fields or events are planned.
5. **Verification boundary.** Repository tests may seed queued, active, and terminal snapshots to prove migration/recovery/transaction rules. A native manual scenario must use the development preview to enqueue, change Settings, close/reopen the app, inspect the same queue/settings, and remove the item. Prepared local database fixtures can expose History and notifications to the UI without adding a public seeding command. The 1C mock evidence remains separate from Rust persistence evidence.

## Verification commands

Run from the repository root. Documentation-only task 2A-01 uses **V0**: check every changed relative Markdown link target, then `git diff --check` and, after staging, `git diff --cached --check`.

- **V1 (Rust repository tasks 2A-02 through 2A-06):** `powershell -NoProfile -Command 'cargo fmt --manifest-path src-tauri/Cargo.toml --check; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo test --manifest-path src-tauri/Cargo.toml --lib; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo check --manifest-path src-tauri/Cargo.toml; exit $LASTEXITCODE'`
- **V2 (command and UI tasks 2A-07/08):** `powershell -NoProfile -Command 'npm run build; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; npm run test:ui; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; npm run check:contracts; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; node --test --test-concurrency=1; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo fmt --manifest-path src-tauri/Cargo.toml --check; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo test --manifest-path src-tauri/Cargo.toml; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo check --manifest-path src-tauri/Cargo.toml; exit $LASTEXITCODE'`
- **V3 (2A checkpoint):** `powershell -NoProfile -Command 'npm run test:ui; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; node --test --test-concurrency=1; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo fmt --manifest-path src-tauri/Cargo.toml --check; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; powershell -NoProfile -File scripts/verify-foundation.ps1; exit $LASTEXITCODE'`

Native restart observations and contract event/serialization tests are required evidence in addition to these commands. Record concise results in `docs/STATE.md` and the final checkpoint.

## Tasks

### 2A-01 — Accepted 1C handoff and task plan — OWNER-REVIEW

- Goal: record the owner's full 1C acceptance, map 2A into narrow tasks, and document the two owner decisions above and the stage boundary.
- Files: `docs/gates/gate-2a.md`, `docs/gates/evidence/1c/checkpoint.md`, `docs/STATE.md`.
- Read: `PROJECT.md:484-509,522-546,559-584,650-662,694-718,734-745,763-770`.
- Acceptance: acceptance is recorded without claiming real persistence from 1C; every 2A deliverable and checkpoint criterion has a task; Markdown links and diff checks pass. Exact verification: **V0**. Stop for owner review before 2A-02.

### 2A-02 — Production database and versioned migrations — AUTOMATABLE

- Goal: open one production SQLite file from Tauri's app-local data directory, apply numbered migrations transactionally, and seed the singleton default Settings row. Keep the Android spike database separate. Reject an unsupported newer schema or failed migration without silently resetting user data.
- Files: `src-tauri/src/lib.rs`, new `src-tauri/src/persistence/` migration module and focused Rust tests, `docs/STATE.md`.
- Read: `PROJECT.md:484-509,522-546,734-745,763-767`.
- Dependencies: 2A-01 owner review. Acceptance: fresh open, reopen without data loss, idempotent migration, upgrade from an earlier schema fixture, and failure cases pass using temporary databases. Exact verification: **V1**.

### 2A-03 — Settings repository — AUTOMATABLE

- Goal: read and atomically replace the one Settings row with typed language, ZIP, and optional desktop folder values. Keep Android's folder value ignored by the UI/output layer as specified; this task does not write downloads.
- Files: `src-tauri/src/persistence/settings.rs`, focused Rust tests, `docs/STATE.md`.
- Read: `PROJECT.md:169-179,499-509,559-584`.
- Dependencies: 2A-02. Acceptance: defaults, all fields, null folder, reopen, and invalid stored values are covered; no second Settings store is introduced. Exact verification: **V1**.

### 2A-04 — History repository — AUTOMATABLE

- Goal: store completed request fields and display title only, expose newest-first reads and delete/clear operations, and replace an identical request by deleting its old row and inserting a new one.
- Files: `src-tauri/src/persistence/history.rs`, focused Rust tests, `docs/STATE.md`.
- Read: `PROJECT.md:146-155,254-262,324-329,484-497,559-584`.
- Dependencies: 2A-02. Acceptance: exact-request uniqueness across reopen, descending id order after replacement, distinct rows with duplicate titles, JSON quality round trip, and delete/clear pass. Exact verification: **V1**.

### 2A-05 — Durable queue and restart recovery — AUTOMATABLE

- Goal: persist contract-shaped queue snapshots with stable positions and UUID ids, list them in order, and normalize interrupted `analyzing`/`downloading`/`postProcessing`/`packaging` items to `paused` during startup. Preserve queued and paused items and recorded progress; never auto-resume.
- Files: `src-tauri/src/persistence/queue.rs`, migration adjustments if needed, focused Rust tests, `docs/STATE.md`.
- Read: `PROJECT.md:132-145,309-314,522-536,559-584`.
- Dependencies: 2A-02. Acceptance: insertion/removal order, JSON round trip, reopen recovery for each active state, idempotent recovery, and no automatic execution pass. Exact verification: **V1**.

### 2A-06 — Notifications and atomic terminal settlement — AUTOMATABLE

- Goal: persist/dismiss error notifications and add an internal transaction that writes one History row for a wholly or partly successful request, or one persistent error notification for an all-failed request, before deleting its queue row. No engine calls this helper in 2A.
- Files: `src-tauri/src/persistence/notifications.rs`, queue/history repository integration, focused Rust tests, `docs/STATE.md`.
- Read: `PROJECT.md:144-155,322-329,484-497,522-546,598-615`.
- Dependencies: 2A-04 and 2A-05. Acceptance: commit and rollback cases, duplicate-request History replacement, notification survival and dismissal across reopen, and queue removal only with durable outcome pass. Exact verification: **V1**.

### 2A-07 — Tauri commands and events — AUTOMATABLE

- Goal: register the contract command names, use the repositories through shared Rust state, serialize typed results/errors, and emit full queue snapshots/removal ids and null change events after commits. Native enqueue remains queued; queued removal works; unsupported lifecycle/engine commands reject with typed errors. Do not replace the Android spike's handlers in this Windows stage.
- Files: `src-tauri/src/commands/`, `src-tauri/src/lib.rs`, focused Rust command/serialization tests, `docs/STATE.md`.
- Read: `PROJECT.md:559-584,598-615,734-745,763-770`.
- Dependencies: 2A-03 through 2A-06. Acceptance: every command name is registered, argument/result/error JSON matches both contracts, events follow commits, failed writes emit nothing, and direct redownload enqueue uses the stored request. Exact verification: **V2**.

### 2A-08 — Native UI against Rust persistence — OWNER-REVIEW

- Goal: select the production Tauri transport in the running native app and use only development-time mock `analyze_url` for preview. Keep browser mock tests isolated. Reconcile the redownload-status comment with the owner's temporary queued-only decision without changing fields/types. Verify Settings, Queue, History, and notifications against Rust data; keep existing focus and i18n behavior.
- Files: `src/App.tsx`, a small development transport adapter if needed, `shared/contract.ts` comment if needed, focused UI tests, `docs/STATE.md`.
- Read: `PROJECT.md:169-179,484-509,522-546,559-584,650-662,763-770`.
- Dependencies: 2A-07. Acceptance: native development enqueue writes Rust queue; relaunch restores Settings and queue, Cancel persists removal; prepared Rust fixture data shows History/notifications and dismissal; no media/network/update work occurs. Owner reviews the running native result. Exact verification: **V2** plus manual restart evidence.

### 2A-09 — Stage evidence and owner checkpoint — OWNER-REVIEW

- Goal: record V3, migration/uniqueness/ordering/recovery/serialization tests, native relaunch observations, accepted interim behavior, and remaining 2B/2C/2D limits in `docs/gates/evidence/2a/checkpoint.md`.
- Files: `docs/gates/evidence/2a/checkpoint.md`, `docs/STATE.md`.
- Read: `PROJECT.md:630-635,650-662,734-745,763-770`.
- Dependencies: 2A-02 through 2A-08 and owner review of the native UI. Acceptance: SQLite and contract evidence is linked, mock preview is clearly distinguished from production analysis, **V3** passes, and the owner receives a reviewable checkpoint. Stop for explicit owner acceptance before 2B.

## Stage exit and carried limits

Stage 2A establishes durable data and the command boundary, not downloads. AC-07's `.part` continuation, actual terminal output for AC-18/19, and engine-driven progress remain for 2C/3A; real analysis is 2B and updater behavior is 2D. A failed 2A criterion stays in 2A until resolved. The Android distribution blocker and other release conditions in [STATE](../STATE.md) remain open.
