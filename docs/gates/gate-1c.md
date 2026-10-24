<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 1C — queue, history, settings, and notifications against the mock engine

## Scope and authority

The owner explicitly accepted the [Gate 1B checkpoint](evidence/1b/checkpoint.md) on 2026-10-23 and requested this plan. [Appendix A](../../PROJECT.md) requires focused tests, applicable manual evidence, review, and explicit owner acceptance of the **1C checkpoint** before Stage 2A. This plan does not accept the 1C checkpoint or authorize Stage 2A work.

Gate 1C completes the mock UI for queue progress and actions, history and redownload, settings, and persistent error notifications. It verifies AC-06..09 and AC-19, plus the terminal-removal clause of AC-18, against deterministic mock scenarios. The 1B Input and previews stay available. The two [indexed progress images](../design/README.md) govern represented visuals; missing Settings, notification, paused, `postProcessing`, `packaging`, and mobile states follow the accepted visual tokens and shell. Queue and History remain on the **right** at desktop widths, per the owner's 1A decision recorded in [STATE](../STATE.md).

`shared/contract.ts` and `src-tauri/src/contract.rs` govern exchanged fields and types; [PROJECT-INDEX](../PROJECT-INDEX.md) locates the narrow `PROJECT.md` ranges named below. Do not change either contract or product behavior without the owner's decision. Stage 1C uses the injected `AppTransport` and mock state for downloads. A small mock backing store may survive transport/UI recreation to prove restart behavior; Stage 2A replaces it with Rust-owned SQLite repositories and command implementations. The owner approved a real desktop folder picker for Settings in 1C, while the chosen path remains mock-stored. No 1C result proves a real `.part` resume, process kill, media output, or updater.

Each task is one session on its own `task-<id>` branch. After its exact verification, commit the task, update `docs/STATE.md` in a separate commit, open a PR using the installed GitHub CLI, and stop. Do not merge, force-push, release, or start Stage 2A without owner acceptance. New hand-written source files begin with the GPL-3.0-or-later/zahidzta/2026 SPDX header. Before writing code with a library or framework, consult its current documentation through context7. Keep terminal output to failures or the last 50 lines.

## Decisions and boundaries

1. **Reference data gap — decided.** [`progress-bar-playlist.png`](../design/desktop/progress-bar-playlist.png) shows speed and ETA, but `Progress` has neither field. On 2026-10-23 the owner chose to omit those values in 1C rather than invent values or amend the contract. Preserve the progress component's other visual relationships.
2. **Queue action label — decided.** The progress references say “Cancel”; `PROJECT.md:135-144` requires Stop/Continue and Delete behaviors. On 2026-10-23 the owner chose Cancel as the removal action, with a separate Stop/Continue control. The underlying removal command remains `remove_download`.
3. **Mock durability.** Use a replaceable, deterministic mock store behind the simulator so a new transport can reload queue, history, settings, and notifications. The running mock may use browser storage for this purpose, with isolated storage in tests. Restored active items become `paused` and never auto-resume. This demonstrates UI recovery and AC-19 without claiming production SQLite persistence; the latter belongs to Stage 2A.
4. **Settings boundary — folder picker decided.** The confirmed `Settings` fields are language, ZIP choice, and `downloadDir`; the engine-update button has a mock outcome only. On 2026-10-23 the owner chose a real desktop native folder picker in 1C, using the Tauri dialog plugin specified by `PROJECT.md:596`; save its returned path in mock Settings. Android hides the folder selector and ignores `downloadDir`. Real yt-dlp updates and app-update availability belong to Stage 2D. The developer-information *section* is required, while its content remains owner-pending (`PROJECT.md:174,707`); use a reviewable placeholder until the owner supplies it.
5. **Terminal and history rules.** A successful or partially successful job writes one history entry before leaving the queue; an all-failed job writes a persistent notification before leaving it. Identical history requests replace the old row and move to the top; duplicate titles remain allowed. Redownload sends the stored request straight to the queue; a missing single-video height falls back to the closest lower available height. Mock progress and pause demonstrate UI behavior, while the real engine rules remain for Stage 2C/3A.

## Verification commands

Run from the repository root. Keep `tests/interactive` under Vitest/jsdom and the existing Node suite separate. Use the manual simulator clock and isolated mock storage in tests; no network, process, or media writes.

- **V0 (plan/authority documentation):** check changed Markdown link targets, `git diff --check`, and `git diff --cached --check` after staging.
- **V1 (each implementation task):** `powershell -NoProfile -Command 'npm run build; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; npm run test:ui; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; npm run check:contracts; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; node --test --test-concurrency=1; exit $LASTEXITCODE'`
- **V1D (native folder picker task 1C-09):** V1, then `powershell -NoProfile -Command 'cargo fmt --manifest-path src-tauri/Cargo.toml --check; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo check --manifest-path src-tauri/Cargo.toml; exit $LASTEXITCODE'`, plus a manual picker/cancel check in the running desktop app.
- **V2 (1C checkpoint):** `powershell -NoProfile -Command 'npm run build; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; npm run test:ui; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; node --test --test-concurrency=1; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; powershell -NoProfile -File scripts/verify-foundation.ps1; exit $LASTEXITCODE'`

Browser visual review and UI recreation/restart scenarios are additional evidence, not substitutes for V1/V2. Record concise command outcomes in `docs/STATE.md` and the final checkpoint.

## Tasks

### 1C-01 — Plan and accepted 1B handoff — OWNER-REVIEW

- Goal: record the owner's 1B acceptance, map 1C to the confirmed requirements and images, isolate decisions, and define task order and verification.
- Files: `docs/gates/gate-1c.md`, `docs/gates/evidence/1b/checkpoint.md`, `docs/STATE.md`.
- Read: `PROJECT.md:132-155,169-179,315-329,484-509,522-553,559-596,598-615,650-662,694-718,734-745,755-767`.
- Acceptance: 1B acceptance is recorded without claiming real downloads; every 1C criterion and contract/UI boundary has an assigned task; links and diff checks pass. Exact verification: **V0**. Stop for owner review.

### 1C-02 — Deterministic queue lifecycle — AUTOMATABLE

- Goal: extend the injected simulator clock to drive single and playlist `queued`, `downloading`, `postProcessing`, `packaging`, and paused snapshots. Implement `pause_download`, `resume_download`, and `remove_download`, emitting full updated snapshots and removal IDs. Pause is accepted only while `downloading`; resume continues from the recorded mock progress. Keep 1B analysis/enqueue fixtures stable.
- Files: `src/transport/simulator.ts`, `tests/interactive/simulator.test.tsx`, `docs/STATE.md`.
- Read: `PROJECT.md:132-145,254-258,315-329,522-536,548-584,650-662,755-761`.
- Dependencies: 1C-01 and the queue-action decision for eventual UI wording. Acceptance: deterministic event ordering, all required status transitions, disabled pause states, removal, and unsubscribing pass without real process/files. Exact verification: **V1**.

### 1C-03 — Terminal outcomes, history, and notifications in the mock — AUTOMATABLE

- Goal: settle successful, partly successful, and all-failed mock jobs. Write one history row for any successful file or a persistent error notification for failure, then remove terminal queue items. Implement history and notification read/delete/dismiss commands and change events, with exact-request history uniqueness, newest-first order, duplicate-title support, and redownload quality fallback. Add replaceable mock storage so terminal data survives a new simulator instance.
- Files: `src/transport/simulator.ts`, a small mock-storage module if needed, `tests/interactive/simulator.test.tsx`, `docs/STATE.md`.
- Read: `PROJECT.md:144-155,245-262,322-329,484-497,522-546,559-584,650-662,755-761`.
- Dependencies: 1C-02. Acceptance: history or notification is stored before queue removal; failed-only jobs create no history; dismiss/delete persist across mock instances; commands/events and fallback preserve contract types. Exact verification: **V1**.

### 1C-04 — Mock settings and interrupted-queue recovery — AUTOMATABLE

- Goal: implement `get_settings` and `set_settings`, plus deterministic mock engine-update command outcomes for later Settings UI. Restore interrupted queue work as paused when a new simulator loads the same backing store. Wire the running mock to browser storage while keeping tests isolated.
- Files: `src/transport/simulator.ts`, the mock-storage module, `src/App.tsx` for the running mock's backing store, `tests/interactive/simulator.test.tsx`, `docs/STATE.md`.
- Read: `PROJECT.md:144,169-179,324-333,499-509,522-546,559-584,598-615,650-662,755-767`.
- Dependencies: 1C-03. Acceptance: restoration never auto-resumes; settings and terminal data reload correctly; mock update outcomes are typed; no Rust/database or actual updater claim is made. Exact verification: **V1**.

### 1C-05 — UI snapshots, events, and recovery — AUTOMATABLE

- Goal: connect the mounted UI to `get_queue`, `get_history`, `get_error_notifications`, and `get_settings`; subscribe to all contract events; reconcile startup snapshots with concurrent events, refetch history/notifications on change, and clean up subscriptions. Surface a translated recoverable error when a snapshot fails instead of silently treating an accepted enqueue as rejected.
- Files: `src/state/downloadFlow.ts`, a small activity-state module if needed, `src/App.tsx`, `tests/interactive/flow.test.ts`, new focused interactive tests, `docs/STATE.md`.
- Read: `PROJECT.md:132-155,169-179,559-584,598-615,650-662,755-761`.
- Dependencies: 1C-04. Acceptance: event/refetch races, UI recreation, duplicate subscriptions, and snapshot failure recovery pass with the injected transport; 1B Input flow stays intact. Exact verification: **V1**.

### 1C-06 — Queue progress and controls — OWNER-REVIEW

- Goal: replace the minimal queued row with single percentage and playlist item count/failure summary, accessible progress bars, translated state labels, and Stop/Continue plus Cancel removal controls. Show `Paused` explicitly; represent `postProcessing` and `packaging` without an enabled pause action. Omit uncontracted speed and ETA as directed.
- Files: `src/components/AppShell.tsx`, a queue item component, `src/styles.css`, `shared/i18n/en.ts`, `shared/i18n/es.ts`, focused interactive tests, `docs/STATE.md`.
- Read: `PROJECT.md:87-95,132-145,196-211,315-329,548-553,650-662,755-761`.
- Dependencies: 1C-05 and the recorded queue-reference decisions. Acceptance: AC-06/08 and mock pause/resume, remove, terminal-removal UI pass; keyboard, focus, en/es, and comparison with both indexed desktop progress images pass owner review. Real `.part` resume remains Stage 2C. Exact verification: **V1**.

### 1C-07 — History and direct redownload — OWNER-REVIEW

- Goal: populate the History card with one row per completed request, clear-all and per-row delete, and Redownload that calls `enqueue_download` with stored request data and updates Queue without navigating to a preview. Use IDs as row keys; allow identical titles. Empty state matches AC-06.
- Files: `src/components/AppShell.tsx`, a history component, `src/App.tsx`, `src/styles.css`, both i18n catalogs, focused interactive tests, `docs/STATE.md`.
- Read: `PROJECT.md:146-155,254-262,324-329,484-497,559-584,650-662,755-761`.
- Dependencies: 1C-03, 1C-05, and shared UI edits from 1C-06; work sequentially. Acceptance: AC-06/09, deletion/clear, direct queue insertion, en/es, and Settings navigation pass; owner reviews the History row against the indexed progress images. Exact verification: **V1**.

### 1C-08 — Persistent error-notification UI — OWNER-REVIEW

- Goal: display typed, translated download failures independently of transient queue rows; load them on UI creation and dismiss one only after `dismiss_error_notification` succeeds. Include accessible announcement and focus behavior. Test a new UI instance and a new mock transport over the same backing store.
- Files: notification component, `src/App.tsx`, `src/styles.css`, both i18n catalogs, focused interactive tests, `docs/STATE.md`.
- Read: `PROJECT.md:144,538-546,571-584,598-615,650-662,755-761`.
- Dependencies: 1C-04/05 and shared App edits from 1C-07; work sequentially. Acceptance: AC-19 and the failed terminal part of AC-18 pass; notification remains visible until successful dismissal; owner reviews the unillustrated visual state. Exact verification: **V1**.

### 1C-09 — Settings controls and desktop folder picker — OWNER-REVIEW

- Goal: extend the accepted Settings shell with persisted language and ZIP choices, a real desktop folder picker using Tauri's dialog plugin, developer-information section, and a distinct mock engine-update action/result. Keep app-update treatment separate and Android folder selection hidden. The selected desktop path is mock-stored; no 1C download writes there. Consult current plugin documentation through context7 before integration and pin compatible JS/Rust plugin versions.
- Files: `src/components/SettingsShell.tsx`, `src/App.tsx`, `src/state/shell.ts`, `src/styles.css`, both i18n catalogs, `package.json`, `package-lock.json`, `src-tauri/Cargo.toml`, `src-tauri/Cargo.lock`, `src-tauri/src/lib.rs`, `src-tauri/capabilities/default.json`, focused interactive tests, `docs/toolchain.md`, `docs/STATE.md`.
- Read: `PROJECT.md:169-179,263-288,499-509,559-596,650-662,694-718,755-767`.
- Dependencies: 1C-04/05, shared App edits from 1C-08, and the recorded folder-picker choice; work sequentially. Acceptance: settings reload through the mock store, language switches immediately, ZIP choice round-trips, picker selection/cancel and Android hiding work, focus/Back work, and the owner reviews missing-screen design and placeholder developer content. Actual updater behavior remains Stage 2D. Exact verification: **V1D**.

### 1C-10 — Responsive and accessibility review — OWNER-REVIEW

- Goal: compare running single/playlist queue cards with the two indexed desktop progress components; inspect empty/paused/failed, history, notifications, and Settings at 1920 × 1200, 738-pixel mobile, 360, 1024, and intermediate CSS widths in both languages. Fix 1C-specific overflow, focus, touch, and contrast issues; record limits.
- Files: affected 1C components/styles/tests, `docs/gates/evidence/1c/visual-review.md`, `docs/STATE.md`.
- Read: `PROJECT.md:87-95,132-155,169-179,196-211,650-662,755-761`.
- Dependencies: 1C-06 through 1C-09 and their owner reviews. Acceptance: no horizontal overflow, keyboard and touch actions remain usable, notifications are announced, and the owner judges visual consistency. Exact verification: **V1** plus browser evidence.

### 1C-11 — Stage evidence and owner checkpoint — OWNER-REVIEW

- Goal: record exact V2 results, scenario coverage, reference comparisons, accepted decisions, UI recreation/mock restart evidence, limitations, and remaining Stage 2A work in `docs/gates/evidence/1c/checkpoint.md`.
- Files: `docs/gates/evidence/1c/checkpoint.md`, `docs/STATE.md`.
- Read: `PROJECT.md:650-662,734-745,755-767`.
- Dependencies: all prior 1C tasks and reviews. Acceptance: AC-06..09, AC-19, and AC-18 terminal removal have linked deterministic evidence; no mock result is claimed as real engine/database verification; **V2** passes. Stop after the checkpoint PR for explicit owner acceptance before Stage 2A.

## Stage exit and carried limits

Stage 1C remains an offline download mock with a real desktop folder picker. Actual SQLite persistence and command handlers are Stage 2A; real pause/process and `.part` continuation, media output, and engine progress are later stages. The Android distribution blocker, legal review, and release conditions in [STATE](../STATE.md) remain open. A failed 1C criterion stays in 1C until resolved; it does not move into Stage 2A by default.
