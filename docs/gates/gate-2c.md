<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 2C — Windows single downloads and queue lifecycle

## Scope and authority

The owner explicitly accepted the [Gate 2B checkpoint](evidence/2b/checkpoint.md) on 2026-10-26 and requested this plan. [Appendix A](../../PROJECT.md) requires focused tests, applicable native evidence, review, and explicit acceptance of the **2C checkpoint** before Stage 2D. This task plans 2C; it does not execute a download or accept its future results.

Stage 2C turns a native single request into a real MP3 or MP4 in the configured Windows folder. Rust owns a one-at-a-time queue, bounded progress events, pause/resume/remove, `postProcessing`, metadata, durable recovery, and terminal History or notification settlement. It extends the verified 2B app-data engine and Windows process-tree supervisor. The [Gate 0B commands](../ytdlp-commands.md) and evidence are starting points for exact yt-dlp/FFmpeg behavior; they are not a substitute for 2C production tests. `shared/contract.ts` and `src-tauri/src/contract.rs` govern wire fields and types; [PROJECT-INDEX](../PROJECT-INDEX.md) locates the narrow requirements below. The [indexed single progress image](../design/README.md) governs the visible queue treatment. Queue and History stay on the right at desktop widths, per the accepted 1A decision.

Playlist requests remain previewable but do not start media extraction in 2C; Stage 3A owns per-entry execution and counters, and Stage 3B owns ZIP and playlist-wide filesystem resilience. Stage 2C **does** prove single-file collision safety and single-job disk/permission handling under AC-15..17. Stage 2D owns network engine updates, probation/fallback, and app-update checks. The Android spike keeps its separate adapter and database; its [distribution blocker](../STATE.md#release-blocker--android-distribution) remains open. No new public contract field, error code, major dependency, or product requirement is assumed by this plan.

Each task is one session on its own `task-<id>` branch. After exact verification, commit the implementation, update `docs/STATE.md` in a separate commit, open a PR with `& 'C:\Program Files\GitHub CLI\gh.exe' pr create`, and stop. Never merge, force-push, release, or start 2D before owner acceptance. New hand-written source files begin with the GPL-3.0-or-later/zahidzta/2026 SPDX header. Before writing code with Tauri, Rust crates, React, or another library/framework, consult its current documentation through context7. Keep terminal output to failures or the last 50 lines.

## Decisions and implementation boundaries for owner review

1. **Single queue only.** Accept and persist playlist requests as before, but do not let the 2C worker take one. They remain `queued` for 3A; single jobs behind one must still run in stored order among eligible singles. Do not report a playlist as done, failed, or partially downloaded. This is the proposed 2C/3A handoff; confirm it with this plan before implementation.
2. **Resume ownership and database hold.** The current persisted `QueueItem` has no output/partial path. 2C proposes a small additive internal SQLite migration keyed by queue id to remember the output folder selected at enqueue, private partial-file location/name, and cleanup ownership. This preserves the existing wire contract and lets restart/resume use the same `.part` even if Settings changes. The owner must approve this database design with the 2C plan before its migration is implemented. If a simpler design proves sufficient, document its equal safety and request review before replacing this one.
3. **Output and quality rules.** Resolve `downloadDir: null` to the Windows Downloads folder; a chosen directory is used for new jobs. Never overwrite an existing file; reserve a final name safely and append ` (1)`, ` (2)`, etc. Preserve a paused job's partial file and output choice. Single MP3 uses the best source, with the selected preset as a **maximum**: copy an MP3 source at or below it, encode a higher-rate MP3 down, and encode non-MP3 sources to it. Single MP4 uses the selected available height; on redownload, fall back to the closest lower available height if the exact one vanished. A missing lower height fails with a typed error. Execute only the verified app-data yt-dlp, FFmpeg, and QuickJS copies. The pinned Gate 0B ffprobe is a verification tool, not a 2B app-data resource.
4. **Phases and process ownership.** A job may be paused only while actually `downloading`; `analyzing` and `postProcessing` reject or disable Pause. Transition to `postProcessing` when extraction, merge, metadata, or cover work starts, not merely at process exit. Extend the 2B supervisor to stream bounded progress/phase observations while retaining its whole-tree cancellation, timeout, and close guarantees. No shell command string, user yt-dlp config, unvalidated URL, or unbounded output capture.
5. **Durable lifecycle.** One eligible single runs at a time. Queue mutations, periodic progress checkpoints, and final History/error settlement commit before their matching events. Throttle live `queue:item-updated` progress to about five per second per item; always emit structural, phase, and terminal changes. After successful output, write History before removing the transient `done` item; on failure, persist an `ErrorNotification` before removing `failed`. Restart maps interrupted active items to `paused`, leaves `.part` for explicit Continue, and never auto-resumes. Remove cancels the complete process tree, deletes only files owned by that queue id, then removes its row. Desktop X does the same process cancellation but retains resumable partials and paused rows.
6. **Evidence boundary.** Deterministic local stubs cover scheduling, state guards, event order, progress bounds, collision naming, failure cleanup, and crash/restart paths without network. Native Windows review must show real MP3 and MP4 playback with mapped tags/cover, selected quality, progress, two queued singles in order, a stopped `.part` resuming from its byte offset, Settings folder behavior, redownload fallback, failure notification persistence, and full process-tree cleanup on close. Use public Gate 0B fixtures and a temporary output folder; record hashes, probes, screenshots, and limits. Site changes stay in 2C for diagnosis, not a claim of success from stubs alone.

## Verification commands

Run from the repository root. `tests/interactive` stays under Vitest/jsdom; the Node suite stays separate. Record any setup and exact native command/engine hashes in [toolchain](../toolchain.md) or focused gate evidence.

- **V0 (2C-01 documentation):** check every changed relative Markdown link target, then `git diff --check` and, after staging, `git diff --cached --check`.
- **V1 (Rust engine/repository tasks 2C-02 through 2C-06):** `powershell -NoProfile -Command 'cargo fmt --manifest-path src-tauri/Cargo.toml --check; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo test --manifest-path src-tauri/Cargo.toml; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo check --manifest-path src-tauri/Cargo.toml; exit $LASTEXITCODE'`. Run the focused Windows process-tree test whenever the supervisor or cancellation path changes.
- **V2 (native command/UI task 2C-07):** `powershell -NoProfile -Command 'npm run build; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; npm run test:ui; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; npm run check:contracts; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; node --test --test-concurrency=1; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo fmt --manifest-path src-tauri/Cargo.toml --check; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo test --manifest-path src-tauri/Cargo.toml; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo check --manifest-path src-tauri/Cargo.toml; exit $LASTEXITCODE'`.
- **V3 (2C-08/09 native review and checkpoint):** `powershell -NoProfile -Command 'npm run test:ui; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; node --test --test-concurrency=1; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo fmt --manifest-path src-tauri/Cargo.toml --check; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; powershell -NoProfile -File scripts/verify-foundation.ps1; exit $LASTEXITCODE'`, plus focused Windows child-tree/queue tests and the recorded native output, pause/resume, restart, and close scenarios. A passing V3 command does not replace media playback and lifecycle observations.

## Tasks

### 2C-01 — Accepted 2B handoff and task plan — OWNER-REVIEW

- Goal: record explicit 2B checkpoint acceptance, define the 2C sequence, decisions, verification, and 2D/3A/3B boundaries.
- Files: `docs/gates/gate-2c.md`, `docs/gates/evidence/2b/checkpoint.md`, `docs/STATE.md`.
- Read: `PROJECT.md:121-168,180-195,236-262,309-340,484-509,522-554,555-629,630-693,694-714,734-745,763-778`.
- Acceptance: relative Markdown links resolve, **V0** passes, and no source, dependency, or contract file changes. Stop for owner review of the plan and its two decisions above before implementation.

### 2C-02 — Single media command profiles and fixture proof — AUTOMATABLE

- Goal: turn the pinned Gate 0B MP3/MP4, metadata, thumbnail, AAC-compatibility, progress, and resume observations into exact safe argument-array profiles and deterministic selection tests. Prove MP3 copy/down-encode behavior for all preset boundaries, rather than assuming `--audio-quality` enforces it. Record any site-specific cover fallback without hardcoding one site's URL into production.
- Files: focused modules/tests under `src-tauri/src/engine/`, deterministic fixtures under `src-tauri/tests/`, focused evidence in `docs/gates/evidence/2c/`, `docs/STATE.md`.
- Read: `PROJECT.md:129-130,156-167,236-244,319-320,331,555-588,618-629,630-645,664-671,769`; Gate 0B CLI evidence.
- Dependencies: owner acceptance of 2C-01. Acceptance: request validation and profile tests cover MP3 copy/reencode, MP4 chosen height/AAC, metadata mapping, JPEG cover, redownload lower-height fallback, no-playlist mode, app-data paths, and option injection. Exact verification: **V1** plus focused CLI proof with pinned artifacts where a behavior cannot be established from stubs.

### 2C-03 — Bounded streaming progress and phase supervision — AUTOMATABLE

- Goal: extend the Windows supervisor so yt-dlp progress and postprocessing signals reach a Rust worker while stdout/stderr stay bounded and cancellation still kills the full child tree. Parse the Gate 0B progress format and coalesce live updates without dropping status changes.
- Files: `src-tauri/src/engine/process.rs` and focused engine progress module/tests, `docs/STATE.md`.
- Read: `PROJECT.md:135-144,164,191-194,254-258,309-314,323,522-536,577-584,630-645,656-662,683,769`.
- Dependencies: 2C-02. Acceptance: malformed lines, unknown totals, stderr errors, output bounds, repeated updates, phase transitions, timeout, cancel, window close, and parent exit are tested with stubs. Exact verification: **V1** plus the focused Windows child-tree test.

### 2C-04 — Single output paths and resumable partial ownership — AUTOMATABLE

- Goal: implement the approved internal path record and versioned migration, resolve Downloads or chosen Settings folder, sanitize names, safely reserve collision suffixes, and keep each queue id's resumable `.part` and owned temporary files distinct. Preserve the existing public `QueueItem` shape.
- Files: `src-tauri/src/persistence/`, focused filesystem module under `src-tauri/src/engine/`, migration and filesystem tests, `docs/STATE.md`.
- Read: `PROJECT.md:141-143,162-167,254-258,309-314,337-339,499-509,522-536,618-629,665-671,683,769,776-777`.
- Dependencies: 2C-01 database-design approval and 2C-02. Acceptance: migration/reopen, folder changes after enqueue, duplicate and unsafe titles, case-insensitive Windows collisions, simultaneous reservation, no overwrite, pause/restart retention, remove-owned-only cleanup, and typed disk/permission failures pass. Exact verification: **V1**.

### 2C-05 — Real single MP3/MP4 worker — AUTOMATABLE

- Goal: join the proven command profiles, pinned app-data paths, streaming supervisor, and owned output into one single-file worker. It sets `analyzing`, `downloading`, and `postProcessing` from real work; validates final media and metadata before success; classifies process and filesystem errors into existing `AppError` values.
- Files: `src-tauri/src/engine/` single worker and focused tests/fixtures, `docs/STATE.md`.
- Read: `PROJECT.md:129-130,156-167,180-184,236-244,254-258,320,330-339,555-588,598-629,664-671,769`.
- Dependencies: 2C-02 through 2C-04. Acceptance: MP3/MP4 stub and local-fixture paths finish with the selected quality and FR-58 tags; failed, cancelled, or invalid output never enters History; all child processes stop on fatal errors. Exact verification: **V1**.

### 2C-06 — Sequential queue, commands, and durable lifecycle — AUTOMATABLE

- Goal: start one eligible single at a time in stored order, wire enqueue/pause/resume/remove to real worker control, checkpoint progress, and use existing transactional History/notification settlement before removal and events. Restore interrupted jobs as paused with resumable files, without automatic restart. Keep playlist jobs queued for 3A.
- Files: `src-tauri/src/commands/`, `src-tauri/src/persistence/`, queue coordinator under `src-tauri/src/engine/`, `src-tauri/src/lib.rs`, focused Rust tests, `docs/STATE.md`.
- Read: `PROJECT.md:135-154,180-194,236-244,254-262,309-314,323-329,522-554,559-584,598-617,630-645,656-662,683,769`.
- Dependencies: 2C-03 through 2C-05. Acceptance: FIFO among eligible singles, no parallel work, pause guard/races, byte-offset `.part` continuation, remove/cancel cleanup, transient terminal states, event-after-commit order, notification durability, restart and window-close behavior pass deterministic tests. Exact verification: **V1** plus focused Windows child-tree test.

### 2C-07 — Native Queue and Settings integration — AUTOMATABLE

- Goal: connect the existing Queue, History, notification, and Settings UI to real 2C commands/events, including chosen download folder, progress, Pause/Continue/Cancel, terminal removal, and native redownload. Keep browser simulator tests deterministic and Android's spike boundary intact.
- Files: focused `src/` transport/UI changes only if needed, native command wiring, `tests/interactive/`, `docs/STATE.md`.
- Read: `PROJECT.md:121-168,169-179,236-244,254-262,559-584,600-616,650-671,769`; indexed single progress reference.
- Dependencies: 2C-06. Acceptance: mounted native transport tests exercise real queue snapshots/events and command errors; Input clears on enqueue, status and controls match Rust, translated persistent errors survive reload, and no browser mock starts native files. Exact verification: **V2**.

### 2C-08 — Real Windows media and lifecycle review — OWNER-REVIEW

- Goal: run the native app against the pinned app-data engine with public Gate 0B fixtures. Inspect MP3/MP4 outputs in a player and ffprobe, selected bitrate/height, tags and cover, Downloads/chosen folder, collision names, two-item order, progress, pause/`.part`/resume byte offset, restart, redownload fallback, errors, and active window-close process cleanup. Capture the single progress UI for owner review.
- Files: `docs/gates/evidence/2c/native-downloads.md`, focused fixes/tests if evidence exposes a defect, `docs/STATE.md`.
- Read: `PROJECT.md:129-130,135-167,180-194,236-244,254-262,309-314,319-339,630-645,656-671,683,769`.
- Dependencies: 2C-07. Acceptance: recorded outputs are playable and match FR-58 and MP3/MP4 rules; no overwrite, orphan child, automatic resume, or lost notification; owner reviews visible Queue behavior; **V3** passes. A failed native observation is fixed in 2C.

### 2C-09 — Stage evidence and owner checkpoint — OWNER-REVIEW

- Goal: link 2C command/profile tests, queue/recovery/collision/error tests, real MP3/MP4 and `.part` observations, UI review, and exact **V3** result in `docs/gates/evidence/2c/checkpoint.md`.
- Files: `docs/gates/evidence/2c/checkpoint.md`, `docs/STATE.md`.
- Read: `PROJECT.md:630-645,646-693,734-745,763-778`.
- Dependencies: 2C-02 through 2C-08 and owner review of the native result. Acceptance: evidence maps AC-07, AC-11, AC-12, AC-15..19, and AC-29 for **single-item Windows scenarios**, states site/test limits and remaining playlist/ZIP/updater work, then stops for explicit owner acceptance before 2D.

## Stage exit

Gate 2C exits with real playable single MP3/MP4 output, correct requested quality and metadata, sequential native single queue behavior, durable explicit resume from `.part`, single-file output/error safety, and complete active-close cleanup. A failed criterion stays in 2C. Playlist processing, ZIP, engine updating, release packaging, other desktop platforms, and Android distribution remain in their scheduled stages.
