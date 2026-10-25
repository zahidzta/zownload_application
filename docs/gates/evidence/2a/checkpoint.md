<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 2A checkpoint — 2026-10-25

**Status:** Accepted by the owner on 2026-10-25. The owner approved this checkpoint, including its linked 2A-08 native UI evidence, and requested the [Gate 2B plan](../../gate-2b.md). This acceptance allows planning Stage 2B; implementation follows review of that plan.

## SQLite and command evidence

| Gate 2A requirement | Evidence |
|---|---|
| One production database and numbered migrations | [Migration tests](../../../../src-tauri/src/persistence/migrations.rs) cover fresh open and singleton Settings seed, reopen, upgrade from an earlier version without data loss, rejection of a newer schema, and rollback of a failed migration. The [database initializer](../../../../src-tauri/src/persistence/mod.rs) applies migrations and recovery on open. The Android spike database remains separate. |
| Settings durability | [Settings tests](../../../../src-tauri/src/persistence/settings.rs) cover default and replacement values, null folder, reopen, invalid stored values, and the singleton row. |
| History uniqueness and order | [History tests](../../../../src-tauri/src/persistence/history.rs) cover replacement of an identical request, newest-first order after reopen, distinct rows with duplicate titles, quality JSON round trips, delete, and clear. |
| Queue snapshots, order, and recovery | [Queue tests](../../../../src-tauri/src/persistence/queue.rs) cover stable positions and UUID ids, JSON round trips, removal and reopen, invalid ids, and idempotent conversion of interrupted analyzing/downloading/postProcessing/packaging snapshots to paused while preserving progress. Queued and paused snapshots stay unchanged; no engine starts on reopen. |
| Durable outcomes before queue removal | [Notification and settlement tests](../../../../src-tauri/src/persistence/notifications.rs) cover persistent error notification and dismissal, success and partial success History replacement, and transaction rollback that keeps the queue row on an invalid terminal state or failed write. No engine invokes terminal settlement in 2A. |
| Registered contract boundary | [Command tests](../../../../src-tauri/src/commands/mod.rs) check all 15 registered names, contract-shaped event payloads emitted after commits, no event on rejected writes, typed errors, null change events, and direct enqueue from a stored History request. [Rust contract tests](../../../../src-tauri/src/contract.rs), the [shared JSON fixture](../../../../tests/contract-fixtures.json), the [parity test](../../../../src-tauri/tests/contract_parity.rs), and the TypeScript contract check cover serialization across the boundary. |
| UI uses Rust persistence | [Native transport tests](../../../../tests/interactive/nativeRuntime.test.tsx) distinguish the development offline `analyze_url` preview from native Queue, History, notification, Settings, and event calls. The [Windows native relaunch observation](native-ui.md) confirms a queued item and Settings persisted in SQLite, restored in the UI after relaunch, and removed by Cancel; prepared History and notification rows appeared, dismissal persisted, and Redownload used the stored request directly. The local database was restored afterward. |

## Interim behavior and acceptance limits

The owner's [2A decisions](../../gate-2a.md) allow the offline mock only for `analyze_url` in a development Tauri run. Production native analysis returns a typed deferred-engine error. Native enqueue commits a `queued` snapshot and emits its event without starting a download. Queued Cancel removes that row; pause/resume and other unavailable engine actions return typed errors. The updater performs no version check or network work in 2A. Browser simulator tests remain separate from the Rust-owned desktop data, and the Android spike keeps its own handler and database.

This checkpoint supports the Stage 2A deliverable in [PROJECT.md:767](../../../../PROJECT.md). It does not establish real analysis, `.part` continuation, process supervision, actual terminal output, engine-driven progress, or updater behavior. [Stage 2B](../../../../PROJECT.md) owns desktop engine bootstrap and analysis; 2C owns single-download execution and real queue lifecycle; 2D owns updater behavior. Playlist execution remains later Stage 3A work. AC-09's direct Redownload queue insertion is observed natively, while AC-07's partial-file continuation and AC-18/19's real terminal outcomes remain open. The [Android distribution blocker and release conditions](../../../STATE.md) remain open.

## Checkpoint verification

Gate 2A **V3** was run from `task-2a-09` on 2026-10-25 with the exact command below and exited **0**.

```powershell
powershell -NoProfile -Command 'npm run test:ui; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; node --test --test-concurrency=1; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo fmt --manifest-path src-tauri/Cargo.toml --check; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; powershell -NoProfile -File scripts/verify-foundation.ps1; exit $LASTEXITCODE'
```

- The interactive suite passed **13 files, 57/57 tests**.
- The sequential Node suite passed **18/18 tests**. Repeated Vite optimizer scans extended it to about **435 seconds** without a failure.
- `cargo fmt --check` passed. The foundation verifier passed the frontend build, TypeScript/shared JSON contract check, **25 Rust library tests**, **1 Rust contract-parity test**, and all **9 indexed design images**.

This checkpoint task changes documentation only. The owner's pre-existing uncommitted `src-tauri/Cargo.toml` edit is outside this task's commits.
