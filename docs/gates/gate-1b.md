<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 1B — analyze and enqueue against the in-memory simulator

## Scope and authority

The owner accepted the [Gate 1A checkpoint](evidence/1a/checkpoint.md) on 2026-10-22 and approved this Gate 1B plan on 2026-10-22. This plan does not accept the later 1B checkpoint. [Appendix A](../../PROJECT.md) requires a tested, reviewed, explicitly accepted checkpoint before 1C.

Read only the indexed `PROJECT.md` ranges named for each task below. The governing 1B ranges are `87-95,98-131,236-253,315-320,387,548-597,630-635,650-655,660-661,666,694-718,734-745,755-761`; locate them through [PROJECT-INDEX](../PROJECT-INDEX.md). `shared/contract.ts` and `src-tauri/src/contract.rs` govern fields and types; the indexed [design images](../design/README.md) govern represented visuals. Existing 1A tokens, shell, i18n, and `AppTransport` are the starting point. The desktop Queue/History placement and Settings header treatment remain as accepted in 1A.

Gate 1B delivers URL input, MP3/MP4 selection, analyzing and typed errors, single and playlist previews, quality controls, playlist titles, Back, enqueue, a visible minimal queued item, and a cleared Input state. Verify AC-01..05, AC-10, and the Input/enqueue portion of AC-18. Queue progress/actions, history, settings controls, notifications, restart persistence, and terminal removal are 1C work; AC-18's terminal clause is verified there. The simulator makes no network request and writes no media, `.part`, ZIP, or Downloads file. It stays behind `src/transport/types.ts`; the production transport retains the same command/event interface.

Each task uses its own `task-<id>` branch and session. After its exact check passes, commit the work, update `docs/STATE.md` in a separate commit, create a PR with `& 'C:\Program Files\GitHub CLI\gh.exe' pr create`, then stop. Never merge, force-push, release, or start the next stage without owner acceptance. New hand-written source files begin with the GPL-3.0-or-later/zahidzta/2026 SPDX header. Before writing code with React, Zustand, Vitest, Testing Library, jsdom, or any other library, consult its current documentation through context7. If an acceptance criterion or authority conflict fails, record evidence and stop the affected task.

## Owner decisions and holds

1. **Mobile analyzing — decided.** On 2026-10-22 the owner chose to adapt the confirmed [`mobile/main-input.png`](../design/mobile/main-input.png) layout and [`desktop/analysis-input.png`](../design/desktop/analysis-input.png) loading treatment. There is no separate mobile analyzing image. Review the composed state in the running app before accepting `1B-07`.
2. **Interactive tests — approved.** On 2026-10-22 the owner approved Vitest, Testing Library, and a DOM test environment for 1B/1C. `1B-03` may add pinned dev dependencies (`vitest`, `@testing-library/react`, `@testing-library/user-event`, `jsdom`) and a `test:ui` script. Record exact install commands and versions in `docs/toolchain.md`. Keep existing Node tests. Separate DOM tests from existing Vite SSR tests to avoid the concurrent optimizer warnings recorded at 1A.
3. **Already-MP3 source — decided and reconciled in 1B-02.** The owner chose this exact rule on 2026-10-22: when the best source is MP3 at or below the selected bitrate, copy it; when above, reencode down to the selected bitrate. Non-MP3 sources encode to the selected bitrate. The UI must describe 320/256/192/128 kbps as requested maxima rather than guaranteed output bitrates. `1B-02` reconciles the conflicting `PROJECT.md` lines and contract comments before quality UI; no mock file is used as evidence of real encoding behavior.
4. **Single quality size estimate — approved for 1B-02.** The confirmed desktop/mobile single images show an approximate file size (for example, `~8.8MB`) within the quality selector. The owner approved the following additive TypeScript shape on 2026-10-22:

   ```ts
   estimates?: Array<
     | { format: 'mp3'; quality: { type: 'audio'; bitrate: number }; estimatedBytes: number }
     | { format: 'mp4'; quality: { type: 'video'; height: number }; estimatedBytes: number }
   >
   ```

   `estimates` belongs only to `AnalyzeResult.single`; an absent matching entry means “unknown” and the UI hides the size. The owner authorized the mirrored amendment to both contracts and `PROJECT.md` in `1B-02`. Estimates must come from defensible engine metadata, not invented UI constants; source-MP3 copying makes a bitrate-only calculation unreliable.
5. **Other visual gaps.** The red error state has a behavior rule (`PROJECT.md:117`) but no indexed image. Create it consistently with the confirmed Input layout and tokens, then seek owner visual judgement. Single/playlist references contain populated History examples; those rows remain a 1C deliverable and do not authorize early History behavior.

## Verification commands

Run these exact PowerShell commands from the repository root. `1B-03` creates `test:ui`; Vitest discovers only `tests/interactive/**/*.test.tsx` and `tests/interactive/**/*.test.ts`, leaving `tests/ui/*.test.mjs` with Node. Use deterministic timers and fixtures in DOM tests.

- **V0 (authority task 1B-02):** `powershell -NoProfile -Command 'npm run check:contracts; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; npm run build; exit $LASTEXITCODE'`
- **V1 (each implementation task 1B-03..1B-11):** `powershell -NoProfile -Command 'npm run build; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; npm run test:ui; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; npm run check:contracts; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; node --test --test-concurrency=1; exit $LASTEXITCODE'`
- **V2 (checkpoint 1B-12):** `powershell -NoProfile -Command 'npm run build; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; npm run test:ui; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; node --test --test-concurrency=1; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; powershell -NoProfile -File scripts/verify-foundation.ps1; exit $LASTEXITCODE'`

The browser visual review is additional evidence, not a substitute for V1/V2. Keep command output to failures or the last 50 lines; record the commands and concise results in `docs/STATE.md` and checkpoint evidence.

## Tasks

### 1B-02 — Size contract decision and MP3 authority alignment — OWNER-REVIEW

- Goal: after the owner's 2026-10-22 approval of the exact estimate shape, reconcile the confirmed MP3 copy rule and selected size policy in the authorities. Mirror the MP3 wording and approved estimate field in both contracts. This task changes contract declarations and comments, not a Rust engine implementation.
- Files: `PROJECT.md`, `shared/contract.ts`, `src-tauri/src/contract.rs`, relevant contract-check fixtures, `docs/STATE.md`; the owner approved the estimate field above.
- Read: `PROJECT.md:121-130,315-320,359-393,548-597,650-666,694-714,755-761`.
- Dependencies: owner approval of this plan **and** explicit size-estimate decision, both recorded above. Acceptance: field names/types mirror, MP3 text consistently states the requested-maximum rule, the line index remains accurate, and no implementation code or engine behavior is claimed. Exact verification: **V0**. Stop after owner review.

### 1B-03 — Interactive test harness — AUTOMATABLE

- Goal: install only the approved pinned test dependencies and add `test:ui`/DOM setup. Prove real click and keyboard interaction with one existing header behavior; keep Node's prior tests isolated.
- Files: `package.json`, `package-lock.json`, `vitest.config.ts`, `tests/interactive/header.test.tsx`, `docs/toolchain.md`, `docs/STATE.md`.
- Read: `PROJECT.md:630-635,650-662,755-760`.
- Dependencies: `1B-02` and approved test dependencies. Acceptance: an interactive test mounts the header and exercises language switching; no app behavior changes. Exact verification: **V1**.

### 1B-04 — Offline analysis fixtures and command — AUTOMATABLE

- Goal: build a deterministic `analyze_url` simulator using the Gate 0B single, 17-entry pure playlist, and mixed watch/list observations; include typed invalid, unsupported, not-found, and restricted errors with raw diagnostic detail. Use local or inline mock thumbnails, never remote fixture fetches.
- Files: `src/transport/simulator.ts`, `src/transport/fixtures.ts`, `tests/interactive/simulator.test.ts`, `docs/STATE.md`.
- Read: `PROJECT.md:115-129,236-248,555-597,630-635,650-655,755-760`; [Gate 0B analyze evidence](evidence/0b/analyze.txt) and [error evidence](evidence/0b/errors.txt).
- Dependencies: `1B-03`. Acceptance: single/pure-playlist/mixed URL shapes match the contracts; invalid/unsupported failures stay distinguishable; fixtures need no network or file writes. Synthetic errors are labelled as such. Exact verification: **V1**.

### 1B-05 — Offline enqueue and queue snapshots — AUTOMATABLE

- Goal: add `enqueue_download`, `get_queue`, and `queue:item-updated` behavior to the injected simulator. Give each request an id, preserve enqueue order, and expose a controllable clock for later 1C progress. Keep lifecycle progression, persistence, and other commands for 1C.
- Files: `src/transport/simulator.ts`, `tests/interactive/simulator.test.ts`, `docs/STATE.md`.
- Read: `PROJECT.md:124-130,236-253,548-584,630-635,660-661,755-761`.
- Dependencies: `1B-04`. Acceptance: a contract-shaped request produces a visible queued snapshot and an event; repeated subscriptions can be removed; no real process, network, or media side effect. Exact verification: **V1**.

### 1B-06 — Analyze-flow state and translated copy — AUTOMATABLE

- Goal: add a small Zustand flow store/controller for URL, chosen format, analyzing, typed error, result, selected quality, Back, and accepted enqueue; add matching English/Spanish keys. Keep settings navigation behavior from 1A.
- Files: `src/state/downloadFlow.ts`, `shared/i18n/en.ts`, `shared/i18n/es.ts`, `tests/interactive/flow.test.ts`, `docs/STATE.md`.
- Read: `PROJECT.md:110-130,236-248,548-597,650-655,660-661,755-760`.
- Dependencies: `1B-04` and `1B-05`; `1B-02` settles MP3 labels. Acceptance: typed transitions are deterministic, stale analysis results cannot replace a newer request, Back returns to Input, and en/es keys remain complete. Exact verification: **V1**.

### 1B-07 — Input and analyzing/error states — OWNER-REVIEW

- Goal: replace the static 1A Input slot with semantic URL input, format choices, Convert button, disabled duplicate submission, spinner/analyzing label, and a translated red error directly under the field. Compare with [`desktop/main-input.png`](../design/desktop/main-input.png), [`desktop/analysis-input.png`](../design/desktop/analysis-input.png), and [`mobile/main-input.png`](../design/mobile/main-input.png).
- Files: `src/components/InputCard.tsx`, `src/App.tsx`, `src/styles.css`, `tests/interactive/input.test.tsx`, `docs/STATE.md`.
- Read: `PROJECT.md:87-95,112-120,236-238,650-655,660,755-760`.
- Dependencies: `1B-06` and the decided mobile analyzing treatment. Acceptance: AC-02, both format choices and loading behavior pass interaction tests; keyboard/focus and immediate language switching work; owner reviews desktop Input/analyzing and mobile adapted state. Exact verification: **V1**. Do not chain unattended past visual review.

### 1B-08 — Single preview and quality choice — OWNER-REVIEW

- Goal: show thumbnail/null fallback, title, author, duration, site, Back, available MP4 heights or four MP3 choices, a native quality selector, and Download action. Compare with [`desktop/single-download.png`](../design/desktop/single-download.png) and [`mobile/single-download.png`](../design/mobile/single-download.png). Render an approximate size only under an approved contract amendment and only when metadata supplies it.
- Files: `src/components/SinglePreview.tsx`, `src/App.tsx`, `src/styles.css`, `tests/interactive/single.test.tsx`, `docs/STATE.md`; authority files only under a separately approved amendment.
- Read: `PROJECT.md:87-95,121-130,236-244,315-320,387,585-597,650-655,666,755-760`.
- Dependencies: `1B-07` and accepted `1B-02` authority alignment. Acceptance: AC-03, quality/request types, Back, accessibility, en/es expansion, and desktop/mobile reference comparison pass; no fabricated estimate. Exact verification: **V1**. Do not chain unattended past visual review.

### 1B-09 — Playlist preview and long title list — OWNER-REVIEW

- Goal: render the playlist image/null fallback, title, author, site, item count, Max/Min only, Back, and a second card listing all item titles with bounded scrolling. Compare with [`desktop/playlist-download.png`](../design/desktop/playlist-download.png) and [`mobile/playlist-download.png`](../design/mobile/playlist-download.png).
- Files: `src/components/PlaylistPreview.tsx`, `src/App.tsx`, `src/styles.css`, `tests/interactive/playlist.test.tsx`, `docs/STATE.md`.
- Read: `PROJECT.md:87-95,121-130,245-253,315-320,650-655,755-760`.
- Dependencies: `1B-07` and shared App/style edits from `1B-08`; work sequentially. Acceptance: AC-04/05, 17-entry scrolling, long/duplicate titles, en/es, keyboard access, and reference comparison pass. Exact verification: **V1**. Do not chain unattended past visual review.

### 1B-10 — Enqueue, clear Input, and minimal Queue item — OWNER-REVIEW

- Goal: send only a valid `DownloadRequest` through the injected transport, show the queued snapshot in the existing Queue card, and restore a cleared Input immediately when enqueue is accepted. Report a typed enqueue rejection in Input without inventing a queue item.
- Files: `src/App.tsx`, `src/components/AppShell.tsx`, `src/state/downloadFlow.ts`, `tests/interactive/enqueue.test.tsx`, `docs/STATE.md`.
- Read: `PROJECT.md:124-130,132-145,236-253,559-584,650-661,755-761`.
- Dependencies: `1B-05`, `1B-08`, `1B-09`; shared files require sequential work. Acceptance: single/playlist request shapes and quality types are exact, the Queue card shows an item, Input clears, duplicate click cannot enqueue twice, and Settings navigation still restores the prior main view. Queue controls/progress wait for 1C. Exact verification: **V1**. Do not chain unattended past visual review.

### 1B-11 — Responsive and accessibility review — OWNER-REVIEW

- Goal: compare the running flows with all indexed 1B images and record browser measurements at 1920 × 1200 desktop, the indexed 738-pixel mobile captures, 360, 1024, and intermediate CSS widths in en/es. Fix 1B-specific clipping, focus, and touch issues.
- Files: affected 1B components/styles/tests, `docs/gates/evidence/1b/visual-review.md`, `docs/STATE.md`.
- Read: `PROJECT.md:87-95,98-131,196-211,650-661,755-760`.
- Dependencies: `1B-07` through `1B-10`. Acceptance: no horizontal overflow, quality and Back remain usable by keyboard/touch, errors are announced, long playlists remain readable, and owner judges reference fidelity including the new mobile analyzing state. Exact verification: **V1**. Do not chain unattended past visual review.

### 1B-12 — Stage evidence and owner checkpoint — OWNER-REVIEW

- Goal: record exact test/build/contract results, deterministic scenario coverage, image comparisons, accepted design/contract decisions, limitations, and remaining 1C questions in `docs/gates/evidence/1b/checkpoint.md`.
- Files: `docs/gates/evidence/1b/checkpoint.md`, `docs/STATE.md`.
- Read: `PROJECT.md:650-662,734-745,755-761`.
- Dependencies: all prior 1B tasks and reviews. Acceptance: **V2** passes, AC-01..05/10 and the enqueue portion of AC-18 have linked evidence, and the owner explicitly accepts the 1B checkpoint before 1C planning or implementation. Exact verification: **V2**. Stop after the checkpoint PR and owner review.

## Stage exit and carried limits

- The simulator stays offline and never produces a real download; browser interactions and contract shapes are proven, not engine output or source bitrate. Gate 0B/0C results remain the real-engine evidence.
- Queue progress, pause/resume/delete, playlist failure counters, history, settings controls, persistent notifications, restored queue, and terminal cleanup remain 1C or later. This plan does not silently mark the terminal clause of AC-18 complete.
- The Android distribution blocker, legal review, native source/build inputs, and release artifacts in `docs/STATE.md` remain outside 1B.
- The 1B checkpoint must record any incomplete owner decision or failed acceptance criterion as open and stop before 1C.
