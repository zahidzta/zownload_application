<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 3A — Sequential playlists

## Scope and checkpoint

The owner accepted the [Gate 2D checkpoint](evidence/2d/checkpoint.md) on 2026-10-29 and requested Gate 3A. Stage 3A implements Windows desktop playlist execution one entry at a time, including the confirmed Max/Min quality matrix, progress counters, continuation after entry failures, one History row per request, and a durable resume index. The [PROJECT-INDEX](../PROJECT-INDEX.md) points to the narrow requirements in `PROJECT.md:121-168,184-195,236-262,315-329,394-420,522-554,559-584,598-617,630-645,650-668,734-745,772-778`.

The implementation extends the existing 2C SQLite queue and Windows single worker. At present, the analysis result exposes playlist titles but not executable entry URLs; the scheduler skips playlist rows; and the single worker rejects playlist requests. `Progress::Playlist` already has `done`, `failed`, `total`, `currentTitle`, and `currentPercent`. Keep the shared TypeScript and Rust `QueueItem`/`Progress` contract unchanged unless the owner separately approves a public field change.

Gate 3A covers ZIP-off playlists. ZIP packaging, bounded-storage behavior, and full filesystem stress stay in 3B. Do not ignore the saved ZIP preference or write individual files for a ZIP request. Preserve the current queued behavior for ZIP-enabled playlists until 3B unless the owner chooses another temporary behavior. The existing single-item output collision protection remains in force. This gate does not change the supported platforms, public errors, or Android path.

Each task is one session on its own `task-<id>` branch. Commit verified task work, update `docs/STATE.md` in a separate commit, open a PR using `& 'C:\Program Files\GitHub CLI\gh.exe' pr create`, then stop. Never merge, force-push, or start 3B before explicit owner acceptance of the 3A checkpoint. New hand-written source files start with the GPL-3.0-or-later/zahidzta/2026 SPDX header. Before writing code that uses a library or framework, consult its current documentation through context7. Keep command output to failures or the last 50 lines.

## Decisions for owner review before implementation

1. **Private durable playlist state.** The project requires an entry list and current index to survive restart, while the public queue contract has no index field. Propose a private SQLite playlist-state record keyed by queue id, storing the resolved ordered entries and current index; keep public `QueueItem` and `Progress` unchanged. Update the playlist state and public counters transactionally at each settled entry. This avoids leaking implementation state through Tauri events.
2. **ZIP-enabled requests during 3A.** ZIP is assigned to 3B. Propose capturing the ZIP preference at enqueue and leaving ZIP-enabled playlist rows queued as they are today, without blocking eligible non-ZIP work, until 3B implements packaging. ZIP-off playlists are eligible for 3A execution. This keeps the confirmed preference from silently producing the wrong output.

Please review these two decisions with the plan before implementation. A plan approval authorizes the listed internal queue/schema changes, not a public contract change or ZIP behavior change.

## Verification commands

Run from the repository root. Record any setup and exact Windows engine hashes/native scenarios in `docs/toolchain.md` or focused evidence under `docs/gates/evidence/3a/`.

- **V0 (3A-01 plan):** check every changed relative Markdown link target; run `git diff --check`; after staging, run `git diff --cached --check`.
- **V1 (Rust queue/worker tasks):** `powershell -NoProfile -Command 'cargo fmt --manifest-path src-tauri/Cargo.toml --check; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo test --manifest-path src-tauri/Cargo.toml; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo check --manifest-path src-tauri/Cargo.toml; exit $LASTEXITCODE'`, plus the focused playlist, queue-lifecycle, and Windows process-tree tests affected by the task.
- **V2 (integrated queue/UI contract):** `powershell -NoProfile -Command 'npm run build; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; npm run test:ui; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; npm run check:contracts; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; node --test --test-concurrency=1; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo fmt --manifest-path src-tauri/Cargo.toml --check; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo test --manifest-path src-tauri/Cargo.toml; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo check --manifest-path src-tauri/Cargo.toml; exit $LASTEXITCODE'`.
- **V3 (3A-05 Windows review/checkpoint):** `powershell -NoProfile -Command 'npm run test:ui; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; node --test --test-concurrency=1; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo fmt --manifest-path src-tauri/Cargo.toml --check; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; powershell -NoProfile -File scripts/verify-foundation.ps1; exit $LASTEXITCODE'`, plus focused playlist/queue/process-tree tests and the native Windows scenarios. Passing V3 does not replace the native observations.

## Tasks

### 3A-01 — Accepted 2D handoff and playlist execution plan — OWNER-REVIEW

- Goal: record Gate 2D acceptance, define the 3A sequence and ZIP boundary, and surface the private-state and ZIP-enabled queue decisions before implementation.
- Files: `docs/gates/gate-3a.md`, `docs/gates/evidence/2d/checkpoint.md`, `docs/gates/evidence/2d/native-review.md`, `docs/STATE.md`.
- Read: `PROJECT.md:121-168,184-195,236-262,315-329,394-420,522-554,559-584,598-617,630-645,650-668,734-745,772-778`; Gate 2C and 2D checkpoints.
- Dependencies: explicit Gate 2D checkpoint acceptance (received 2026-10-29).
- Acceptance: changed relative Markdown links resolve, V0 passes, and no source, dependency, or contract files change. Stop for owner review of this plan and its two decisions before implementation.

### 3A-02 — Durable playlist expansion and resume snapshot — AUTOMATABLE

- Goal: resolve a flat playlist into ordered executable entry URLs and display titles, persist the snapshot and current index privately by queue id, and restore interrupted playlist work as paused. Resume from the current entry using its existing partial file; redownload resolves a fresh snapshot. Keep the public queue contract unchanged.
- Files: focused `src-tauri/src/engine/analysis.rs` and `queue.rs`, `src-tauri/src/persistence/queue.rs` and migrations, focused Rust fixtures/tests, `docs/STATE.md`.
- Read: `PROJECT.md:180-195,245-258,522-536,630-645,654-668,769-776`.
- Dependencies: owner acceptance of 3A-01 decisions.
- Acceptance: tests cover entry extraction, malformed/empty/oversized snapshots, transactional snapshot/index persistence, restart recovery, current-entry resume, and fresh expansion on History redownload. Exact verification: V1.

### 3A-03 — Sequential playlist entry worker and quality matrix — AUTOMATABLE

- Goal: run one playlist entry at a time through the verified app-data engine. Apply BR-01 exactly: mp4 Max selects best video plus best audio; mp4 Min selects minimum video plus best audio; mp3 Max and Min request 320 and 128 kbps respectively, using best source audio and BR-02's copy/reencode behavior. Use each entry's title and the playlist title for metadata, with no nested playlist expansion.
- Files: focused `src-tauri/src/engine/single.rs` and queue/analysis modules as needed, CLI fixtures/tests under `src-tauri/tests/`, `docs/STATE.md`.
- Read: `PROJECT.md:156-168,245-253,315-324,522-536,630-645,664-668,776` and Gate 0B command evidence.
- Dependencies: 3A-02.
- Acceptance: stub CLI tests prove each format/quality argument profile, entry URL isolation, sequential invocation, playlist metadata, collision-safe individual outputs, and no ZIP creation. Pinned-tool observations confirm all four quality combinations. Exact verification: V1.

### 3A-04 — Queue lifecycle, counters, partial failures, and History — AUTOMATABLE

- Goal: schedule eligible ZIP-off playlists with the existing one-at-a-time queue; persist each settled entry before advancing the resume index; report success/failure counters; continue after ordinary entry failures; allow explicit pause/resume during downloading; and settle one playlist request to one History row when at least one entry succeeds. Persist an error summary when entries fail, including partial success, before removing the transient queue row. All-failed playlists settle as failed with a durable notification. Emit events only after the related database commit.
- Files: focused `src-tauri/src/engine/queue.rs`, `src-tauri/src/persistence/queue.rs` and history/notification settlement, `src-tauri/src/commands/`, relevant UI state only if the existing playlist progress rendering needs correction, Rust and interactive tests, `docs/STATE.md`.
- Read: `PROJECT.md:132-155,180-195,254-262,319-329,522-554,559-584,598-617,654-668,734-745,776`.
- Dependencies: 3A-02 and 3A-03.
- Acceptance: deterministic tests cover mixed success/failure continuation, all-failed and all-success outcomes, exact counters, one History row, durable partial-failure notification, queue FIFO, ZIP-enabled deferral without blocking, progress event timing, pause/resume at the current entry, restart recovery, removal, and child cleanup. Exact verification: V2 plus focused Windows process-tree/playlist/queue tests.

### 3A-05 — Native Windows playlist review and checkpoint — OWNER-REVIEW

- Goal: review a tiny all-success playlist and a mixed-failure playlist in the native Windows app with ZIP off; verify Max/Min output, entry order, counters, failure continuation, one History row, pause/resume at the current index, restart recovery, persistent failure summary, and child cleanup. Link the exact tests, engine hashes, screenshots/observations, and limits in the 3A checkpoint.
- Files: `docs/gates/evidence/3a/` native record and checkpoint, focused fixes/tests if evidence exposes a defect, `docs/STATE.md`.
- Read: `PROJECT.md:236-262,315-329,522-554,630-693,734-745,772-778`.
- Dependencies: 3A-02 through 3A-04 and owner review of the decisions in 3A-01.
- Acceptance: V3 and focused Windows scenarios pass; checkpoint maps AC-04, AC-08, AC-12, AC-14 and the durable resume-index requirement, clearly leaves ZIP and filesystem stress to 3B, then stops for explicit owner acceptance before 3B.

## Stage exit

Gate 3A exits with sequential ZIP-off playlist processing on Windows, the exact Max/Min matrix, accurate counters, continuation after per-entry failures, one durable History row per successful playlist request, durable explicit resume from the current entry, and native evidence against tiny and mixed-failure playlists. ZIP packaging, bounded storage, disk/permission stress, and ZIP-entry collisions remain in 3B. A failed criterion stays in 3A.
