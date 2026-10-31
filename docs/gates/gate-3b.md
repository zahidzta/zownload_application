<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 3B — ZIP and filesystem resilience

## Scope and checkpoint

Gate 3B adds ZIP-enabled sequential playlist downloads to the Windows desktop queue. It covers bounded temporary storage, safe archive and entry naming, durable continuation after interruption, disk-full and permission failures, cleanup, and filesystem stress. It completes the remaining Windows playlist behavior in AC-13, AC-16, and AC-17. The owner accepted the Gate 3A checkpoint on 2026-10-30; see [Gate 3A checkpoint](evidence/3a/checkpoint.md).

Read only these `PROJECT.md` ranges for this gate: `156-168,200-204,245-253,315-329,337-339,511-554,598-617,630-645,664-671,683,777`. The relevant project rules require one final ZIP, uncompressed entries, no complete second copy of playlist media, sequential processing, numbered collisions, durable queue recovery, per-entry continuation for ordinary failures, and whole-job cancellation for disk-full or permission errors.

Gate 3B is Windows-only. Android production ZIP output remains outside this gate. Reuse the pinned `zip` dependency already in `src-tauri/Cargo.toml`; do not add a dependency or alter the public TypeScript/Rust contract without separate owner approval. Before implementation uses the ZIP API, consult its current documentation through Context7. The configured Context7 lookup returned a monthly-quota error during planning, so implementation must retry the required documentation lookup before coding.

The output protocol is a pending `<playlist>.zip.part` in the captured output directory, followed by a collision-safe final rename after successful archive completion. Store entries uncompressed. Package one completed media file at a time, verify its archive entry, then remove that temporary media file. Number duplicate sanitized entry names inside the archive and number a colliding final archive name using the existing ` (1)`, ` (2)` convention. A mixed playlist finalizes one ZIP containing successful entries and retains the existing failure summary; an all-failed playlist publishes no archive.

The archive must have a durable per-entry recovery boundary. Persist/advance the playlist index only after that entry is durably present and verified in the pending archive. On process restart, the queue restores paused; Continue preserves completed archive entries and retries the current entry from its owned partial media file where available. A crash during an archive write must recover to the last committed entry. A crash after final rename but before queue settlement must detect the completed archive and settle without producing a duplicate. Pause remains unavailable during packaging. Disk-full or permission failure while creating, writing, verifying, finalizing, renaming, or cleaning output cancels the whole job, terminates active children, cleans incomplete output where safe, persists the translated notification, and removes the queue row.

## Decisions for owner review before implementation

1. Approve the per-entry archive commit and restart behavior above, including preservation of already committed entries and retry of the interrupted entry.
2. Approve same-directory `.zip.part` staging, uncompressed entries, numbered archive/entry collisions, and the rule that mixed playlists finalize successful entries while all-failed playlists publish nothing.
3. Keep filesystem errors fatal to the complete playlist request; ordinary media-entry failures continue under the existing 3A behavior.
4. Keep the public contract and dependency set unchanged. Any implementation finding that requires either change returns for separate owner approval.

## Verification

Run from the repository root. Keep generated media, output archives, permission-denied fixtures, and disk-full simulations under a unique disposable temp root; never use the owner's Downloads folder or fill a shared volume. Record native Windows setup, exact engine hashes, and observed peak temporary storage in `docs/toolchain.md` or focused evidence under `docs/gates/evidence/3b/`.

- **V0 (3B-01 plan):** check every changed relative Markdown link target; run `git diff --check`; after staging, run `git diff --cached --check`.
- **V1 (ZIP writer and persistence tasks):** `powershell -NoProfile -Command 'cargo fmt --manifest-path src-tauri/Cargo.toml --check; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo test --manifest-path src-tauri/Cargo.toml; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo check --manifest-path src-tauri/Cargo.toml; exit $LASTEXITCODE'`, plus focused ZIP, path-collision, recovery, and filesystem-error tests.
- **V2 (integrated queue):** `powershell -NoProfile -Command 'npm run build; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; npm run test:ui; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; npm run check:contracts; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; node --test --test-concurrency=1; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo fmt --manifest-path src-tauri/Cargo.toml --check; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo test --manifest-path src-tauri/Cargo.toml; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo check --manifest-path src-tauri/Cargo.toml; exit $LASTEXITCODE'`.
- **V3 (Windows review/checkpoint):** `powershell -NoProfile -Command 'npm run test:ui; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; node --test --test-concurrency=1; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo fmt --manifest-path src-tauri/Cargo.toml --check; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; powershell -NoProfile -File scripts/verify-foundation.ps1; exit $LASTEXITCODE'`, plus the native scenarios below and focused playlist/queue/process-tree tests. Native observations are required in addition to V3 passing.

## Tasks

### 3B-01 — ZIP and filesystem resilience plan — OWNER-REVIEW

- Goal: define the ZIP output protocol, archive recovery boundary, failure policy, task sequence, and evidence before implementation.
- Files: `docs/gates/gate-3b.md`, `docs/gates/evidence/3a/checkpoint.md`, `docs/gates/evidence/3a/tasks.md`, `docs/STATE.md`.
- Read: `PROJECT.md:156-168,200-204,245-253,315-329,337-339,511-554,598-617,630-645,664-671,777`; Gate 3A checkpoint and plan.
- Dependencies: explicit Gate 3A checkpoint acceptance (received 2026-10-30).
- Acceptance: relative links resolve, V0 passes, 3A acceptance is recorded, and no source, dependency, or public contract files change. Stop for owner review of this plan and its decisions before implementation.

### 3B-02 — Bounded, collision-safe ZIP writer — AUTOMATABLE

- Goal: write uncompressed archive entries to the pending ZIP with a recoverable per-entry commit boundary; verify each entry before deleting its single temporary media file; reserve a collision-safe final archive path; finalize and rename only after playlist settlement. Recover incomplete writes to the last committed entry without retaining a second copy of playlist media.
- Files: focused `src-tauri/src/engine/` ZIP/output-path modules, `src-tauri/src/engine/single.rs` only as needed for the current media staging path, and Rust tests/fixtures.
- Read: `PROJECT.md:161-167,203,245-251,321,337,667,670`.
- Dependencies: owner acceptance of 3B-01. Consult current `zip` crate documentation through Context7 before writing ZIP API code. If the existing crate cannot provide the approved recovery behavior without a new dependency or public contract change, stop and return the finding for owner review.
- Acceptance: tests cover uncompressed content and metadata, archive integrity, duplicate entry names, existing archive collisions, final rename, write interruption recovery, idempotent recovery around final rename, and proof that only the partial ZIP plus the current media file coexist. Exact verification: V1.

### 3B-03 — ZIP queue lifecycle, resume, and fatal storage errors — AUTOMATABLE

- Goal: make captured ZIP-enabled playlist requests eligible; report the existing `packaging` state; advance durable progress only after archive commit; resume after restart from the current entry; continue ordinary entry failures; finalize a partial-success ZIP and one History row; and treat disk-full/permission failures as whole-job cancellation with child termination, safe cleanup, and persistent translated notification.
- Files: focused `src-tauri/src/engine/queue.rs`, `src-tauri/src/persistence/queue.rs` and migrations only if private durable state requires it, notification settlement, focused Rust/CLI fixtures and tests. Keep shared contract files unchanged.
- Read: `PROJECT.md:161-167,245-253,321-329,333,522-553,609-614,667-671`.
- Dependencies: 3B-02.
- Acceptance: deterministic tests cover ZIP preference snapshot, FIFO eligibility, ordinary and fatal failures, all-success/mixed/all-failed results, exact counters and History/notification behavior, pause guard during packaging, restart at every archive boundary including final rename/settlement, interrupted entry resume, remove/cancel cleanup, and process-tree termination. Exact verification: V2 plus focused Windows process-tree/playlist/queue tests.

### 3B-04 — Filesystem stress, native Windows review, and checkpoint — OWNER-REVIEW

- Goal: prove ZIP output and queue behavior in the native Windows app with deterministic synthetic media, duplicate titles, an ordinary failed entry, collisions, restart during packaging, and isolated disk-full/permission failures. Measure peak staging files/bytes and confirm the bounded-storage rule; verify no incomplete archive is published and no child process or unsafe partial remains after fatal failure.
- Files: focused tests/fixes if needed, `docs/gates/evidence/3b/` test/native records and checkpoint, `docs/STATE.md`.
- Read: `PROJECT.md:161-167,203,245-253,321-329,337-339,609-614,630-645,667-671,683,777`.
- Dependencies: 3B-02 and 3B-03.
- Acceptance: V3 and focused queue/ZIP/process-tree tests pass; native observations record the test fixture, engine hashes, archive contents and names, collision results, restart recovery point, measured peak storage, fatal error/notification outcomes, cleanup, and limitations. The checkpoint maps AC-13, AC-16, AC-17 and NFR-04, then stops for explicit owner acceptance before Gate 3C.

## Stage exit

Gate 3B exits with Windows ZIP-enabled playlists producing one collision-safe archive from sequential entries, bounded to the pending ZIP plus the current media file, recoverable at durable entry boundaries, and verified against disk-full/permission cancellation and cleanup. ZIP-entry and archive-name collisions never overwrite content. A failed criterion stays in 3B. Do not start Gate 3C until the owner explicitly accepts the 3B checkpoint.
