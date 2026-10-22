<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 1A — app shell, visual system, navigation, and languages

## Scope and checkpoint

- Source: `PROJECT.md:87-110,169-178,196-211,363-367,394-417,548-597,630-635,650-662,694-733,734-745,755-761`; current status: `docs/STATE.md`. The exact per-task ranges below supersede this reading map during execution.
- Strict deliverable: Phase 1A's React/TypeScript/Vite shell using the pinned Tailwind and Zustand stack, with shared tokens, handcrafted primitives, header, responsive layout, a Settings navigation shell, and English/Spanish infrastructure. No component library, new framework, real download engine, media output, or network-backed simulator.
- Authority: `shared/contract.ts` and `src-tauri/src/contract.rs` are **read-only for all of Phase 1**. They define every field, command, event, error code, and serialized type. `PROJECT.md` governs behavior; `docs/design/README.md` and its indexed images govern covered visuals. A needed contract change is an owner decision and stops the affected task.
- Setup session `1A-01` produced this plan and `phase-1-outline.md`. **Execution starts with `1A-02` only after owner approval.** Each numbered task below is about one 30-minute session, one `task-<id>` branch, verification, separate work/state commits, and a PR. Do not start 1B until the owner explicitly accepts the 1A checkpoint.
- Every new hand-written source file begins with `SPDX-License-Identifier: GPL-3.0-or-later` and `SPDX-FileCopyrightText: 2026 zahidzta` in valid file comments.
- Before coding with React, Tailwind, Zustand, Vite, or a test API, consult that library's current documentation through context7 as required by `AGENTS.md`.
- Stop rule: if any acceptance criterion fails or an authority conflicts, record the exact result in the task evidence and `docs/STATE.md`, stop that task, and ask the owner. Do not change requirements, contracts, images, test criteria, or architecture to make a check pass.

### Decisions required before dependent UI work

1. **Desktop placement conflict:** FR-03/04 (`PROJECT.md:107-108`) say Queue and History are on the **left**; [`desktop/main-input.png`](../design/desktop/main-input.png) places them on the **right**. The same placement appears in the indexed desktop reference set. Owner must choose or provide a revised authority before `1A-07`.
2. **Header conflict:** FR-02 and AC-01 (`PROJECT.md:102,651`) require a settings button to the right of language; [`desktop/main-input.png`](../design/desktop/main-input.png) and [`mobile/main-input.png`](../design/mobile/main-input.png) show language but no settings button. Owner must resolve before `1A-06`.
3. **No indexed image** covers the Settings screen, its navigation transition, a populated History card, persistent error notifications, disabled/focus/hover states, or intermediate widths. This plan does not select a new visual design for them. The owner must supply/approve direction before any affected visual task; `1A-09` is explicitly held for that decision. `docs/design/README.md` permits consistent completion, but the setup request requires these gaps to be flagged first.

### Existing tools and UI test approach

`package.json` already pins React, TypeScript, Vite, Tailwind, and Zustand. It has `npm run build` and `npm run check:contracts`, but no UI test runner or DOM implementation. Use Node's built-in `node:test` for translation-key, state/transport, and pure behavior tests; use installed Vite's SSR loader with installed `react-dom/server` for component markup tests (semantic landmarks, labels, button order, accessible names, language output). Test actual state transitions in a pure Zustand model, not by asserting source text. These checks do **not** prove click/focus behavior or responsive pixels; the 1A owner review covers those in the running app. `PROJECT.md:635` proposes Vitest + Testing Library for later interactive UI tests; adding them plus a DOM test environment would change `package.json`/`package-lock.json` and needs owner approval before 1B/1C planning. Do not install them in 1A by assumption.

Each task's verification command below is one exact PowerShell command from the repository root. The UI test files named in a command are created by that task or a dependency. Build/contract checks do not replace the listed human review. No task edits `package.json`, `package-lock.json`, either contract file, or `PROJECT.md`; any dependency approval that changes this is a new owner decision. `docs/STATE.md` is touched after **every** completed task and serialized even where implementation files are independent.

## Tasks

### 1A-02 — English/Spanish catalog and key parity — AUTOMATABLE

- Goal: add shared en/es catalogs and a typed lookup/fallback boundary for shell copy, with a test that rejects missing or extra keys and checks every contract `ErrorCode` has both translations.
- Files to touch: `shared/i18n/en.ts`, `shared/i18n/es.ts`, `src/i18n.ts`, `tests/ui/i18n.test.mjs`, `docs/STATE.md`.
- Read: `PROJECT.md:169-178,650-662,755-759`.
- Dependencies: approved 1A plan; independent of `1A-03` implementation. Parallel only in separate worktrees/branches; serialize `docs/STATE.md` and PR integration.
- Acceptance: matching nested keys, en/es shell strings and error names; immediate language selection is possible through the lookup function; no new dependency; source headers on new `.ts` and `.mjs` files.
- Exact verification command: `powershell -NoProfile -Command 'npm run build; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; node --test tests/ui/i18n.test.mjs'`.

### 1A-03 — Typed app transport seam — AUTOMATABLE

- Goal: define an app-owned transport interface from the existing contract's `Commands`/`Events`, keep the Tauri implementation in one module, and expose an injected transport for the later simulator. Preserve the current spike until `1A-07` replaces its screen.
- Files to touch: `src/transport/types.ts`, `src/transport/tauri.ts`, `src/transport/index.ts`, `tests/ui/transport.test.mjs`, `docs/STATE.md`.
- Read: `PROJECT.md:394-417,548-597,630-635,755-759`.
- Dependencies: approved 1A plan; independent of `1A-02` implementation. Parallel only in separate worktrees/branches; serialize `docs/STATE.md` and PR integration.
- Acceptance: consumers can swap a type-compatible in-memory command/event implementation without importing Tauri; event unsubscribe shape is preserved; both contracts remain unchanged; there is no simulator network or media-file behavior.
- Exact verification command: `powershell -NoProfile -Command 'npm run build; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; npm run check:contracts; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; node --test tests/ui/transport.test.mjs'`.

### 1A-04 — Semantic shell primitives — AUTOMATABLE

- Goal: implement only reusable Card, Button/IconButton, and page landmark primitives with accessible names, disabled state, keyboard semantics, and token-ready class hooks. No visual-screen composition yet.
- Files to touch: `src/components/ui/Card.tsx`, `src/components/ui/Button.tsx`, `src/components/ui/Page.tsx`, `tests/ui/primitives.test.mjs`, `docs/STATE.md`.
- Read: `PROJECT.md:87-95,98-110,196-211,755-759`.
- Dependencies: `1A-02` for translated labels; independent of `1A-03` implementation. Separate worktree only, with serialized state/PR integration.
- Acceptance: SSR component tests cover landmark hierarchy, button accessible names, disabled attributes, and no clickable non-button substitutes. Tailwind only; no component library. Visual styling waits for `1A-05`.
- Exact verification command: `powershell -NoProfile -Command 'npm run build; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; node --test tests/ui/primitives.test.mjs'`.

### 1A-05 — Tokens from indexed designs — OWNER-REVIEW

- Goal: derive and document reusable color, spacing, radius, border, shadow, type, and focus tokens from the confirmed images; apply them through Tailwind/CSS variables rather than scattering sampled values.
- Files to touch: `src/styles.css`, `docs/design/tokens.md`, `docs/STATE.md`.
- Read: `PROJECT.md:87-95,196-211,755-759`.
- Dependencies: `1A-04`; no parallel work on `src/styles.css` or `docs/STATE.md`.
- Acceptance: documented tokens cover backgrounds, card/input borders, primary action, text hierarchy, and focus visibility; owner checks the visual values against [`desktop/main-input.png`](../design/desktop/main-input.png) and [`mobile/main-input.png`](../design/mobile/main-input.png). Browser/status bars in the mobile image are not app UI. Any visual mismatch stops the task.
- Exact verification command: `npm run build`.
- Review gate: owner visual judgement required; do not chain unattended.

### 1A-06 — Header and language/settings actions — OWNER-REVIEW

- Goal: implement the always-visible header and language switch with a settings navigation action, keeping English/Spanish text current without restarting.
- Files to touch: `src/components/Header.tsx`, `src/state/shell.ts`, `tests/ui/header.test.mjs`, `docs/STATE.md`.
- Read: `PROJECT.md:87-110,169-178,650-662,755-759`.
- Dependencies: `1A-02`, `1A-04`, `1A-05`, and the owner decision on the settings-button image conflict. `src/state/shell.ts` is shared with later navigation tasks; no parallel edits there.
- Acceptance: logo/name/language/settings order follows the resolved authority; language switch changes all rendered shell copy immediately; header remains visible; accessible names and native keyboard semantics are verified; compare against both main-input images.
- Exact verification command: `powershell -NoProfile -Command 'npm run build; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; node --test tests/ui/header.test.mjs'`.
- Review gate: owner visual judgement required; do not chain unattended.

### 1A-07 — Desktop main shell — OWNER-REVIEW

- Goal: replace the Gate 0C spike presentation with the desktop shell: header, main-content slot, and empty Queue/History slots; keep functional Input/Download work for 1B and queue/history behavior for 1C.
- Files to touch: `src/App.tsx`, `src/components/AppShell.tsx`, `src/styles.css`, `tests/ui/shell.test.mjs`, `docs/STATE.md`.
- Read: `PROJECT.md:87-110,132-155,394-417,650-662,755-759`.
- Dependencies: `1A-03`, `1A-06`, and the owner decision on the desktop placement conflict. Shared `src/App.tsx`/`src/styles.css` make this sequential with `1A-08` and `1A-09`.
- Acceptance: at 1920 × 1200, shell proportions, card positions, header, negative space, and empty placeholders match the **resolved** desktop authority; Queue/History remain visible; component tests assert landmark/card order and empty copy. This is likely over 30 minutes if the spike-to-shell replacement also wires functional queue data: split into `1A-07A` static composition and `1A-07B` transport wiring before coding, with each separately verified.
- Exact verification command: `powershell -NoProfile -Command 'npm run build; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; node --test tests/ui/shell.test.mjs'`.
- Review gate: owner visual judgement required; do not chain unattended.

### 1A-08 — Mobile and intermediate-width shell — OWNER-REVIEW

- Goal: make the same shell a single-column mobile layout with large touch targets and sensible intermediate widths, without embedding screenshots.
- Files to touch: `src/components/AppShell.tsx`, `src/styles.css`, `tests/ui/shell.test.mjs`, `docs/STATE.md`.
- Read: `PROJECT.md:87-110,196-211,755-759`.
- Dependencies: `1A-07`; sequential because it edits the same shell/style files.
- Acceptance: at 738 × 1600 the app areas follow [`mobile/main-input.png`](../design/mobile/main-input.png) under the resolved header decision; no horizontal clipping at 360, 738, 1024, and 1920 CSS-pixel widths; touch targets, safe areas, and en/es text expansion work. At intermediate widths, ask owner to judge the consistent interpolation because no image exists.
- Exact verification command: `powershell -NoProfile -Command 'npm run build; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; node --test tests/ui/shell.test.mjs'`.
- Review gate: owner visual judgement required; do not chain unattended.

### 1A-09 — Settings navigation shell — OWNER-REVIEW

- Goal: add only navigation into/out of a Settings container and establish the layout shell. Setting controls and persistence belong to 1C.
- Files to touch: `src/App.tsx`, `src/components/SettingsShell.tsx`, `src/state/shell.ts`, `tests/ui/navigation.test.mjs`, `docs/STATE.md`.
- Read: `PROJECT.md:98-110,169-178,650-662,755-759`.
- Dependencies: `1A-08` and owner direction for the unillustrated Settings screen/transition. Shared App/state files make this sequential.
- Acceptance: navigation returns to the prior main state, has a clear page title/back action and accessible focus path, and does not imply a working engine update or folder picker. Owner reviews the proposed visual treatment before acceptance; no unapproved design is invented.
- Exact verification command: `powershell -NoProfile -Command 'npm run build; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; node --test tests/ui/navigation.test.mjs'`.
- Review gate: owner visual judgement required; do not chain unattended.

### 1A-10 — Stage 1A evidence and owner checkpoint — OWNER-REVIEW

- Goal: record focused test results, manual visual evidence, unresolved decisions, and stage exit status for explicit owner acceptance.
- Files to touch: `docs/gates/evidence/1a/checkpoint.md`, `docs/STATE.md`.
- Read: `PROJECT.md:87-110,169-178,196-211,630-635,650-662,734-745,755-759`.
- Dependencies: `1A-02` through `1A-09`; final and not parallel. If a prior task stopped, this checkpoint records that failure instead of declaring a pass.
- Acceptance: tests pass; visual observations at reference and intermediate widths are linked; design conflicts and open questions show owner decisions or remain blocking; owner explicitly accepts before 1B planning/execution.
- Exact verification command: `powershell -NoProfile -Command 'node --test; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; powershell -NoProfile -File scripts/verify-foundation.ps1'`.
- Review gate: owner visual judgement required; do not chain unattended.

## Phase 1 simulated-engine contract for later 1B/1C planning

The simulator lives behind `src/transport/types.ts` and implements the existing contract command/event shapes. The UI and Zustand stores call only that transport. It uses in-memory fixtures and a controllable clock, plus an injected state store (browser localStorage in the mock app, in-memory storage in tests) so notifications and settings survive a simulated app restart. **It makes no network request and writes no real media, `.part`, ZIP, or Downloads file.** It can model UI recreation by discarding/recreating the view and refetching mock queue/history/notifications. The later production transport replaces the injected implementation with `call`/`on` from `shared/contract.ts`; the UI components and store selectors do not change. Real persistence, platform engines, and process control stay in later stages.

| Scenario to simulate | Evidence and limits |
|---|---|
| Analyze success: single YouTube metadata, pure playlist, and mixed watch+list URL treated as single. Use a 17-item playlist for long-list scrolling. | [`0b/analyze.txt`](evidence/0b/analyze.txt) records 14 single formats, 17 flat Blender entries, and mixed URL as a single with 48 formats; its 6.80/7.90/9.23 s timings are observed network runs, not required mock delays. |
| Single MP4 heights and playlist Max/Min format choices; fixed MP3 output presets 320/256/192/128. | [`0b/fixtures.md`](evidence/0b/fixtures.md) records actual NatureClip height arrays (144–1080, varying by entry); [`0b/mp4.txt`](evidence/0b/mp4.txt) records selected 1080/720/144 and bounded 240 outputs; [`0b/mp3-singles.txt`](evidence/0b/mp3-singles.txt) records four achieved presets with a Vorbis source. Already-MP3 bitrate behavior is unresolved and stays an owner question. |
| Queue ordering and timed progress: `queued` then `downloading`, nondecreasing 0–100 progress, `postProcessing`, optional ZIP `packaging`, terminal snapshot, history/notification update, then removal. Virtual time can accelerate tests; emitted progress stays at or below about five events/second/item. | [`0c/queue.md`](evidence/0c/queue.md) records queued→downloading and terminal→removed; [`0b/resume-progress.txt`](evidence/0b/resume-progress.txt) records seven pre-interruption and 18 resumed parseable progress lines, then `finished`; [`0c/home.md`](evidence/0c/home.md) records 0→34% over 180 s and monotonic samples; [`0c/youtube-mp3.md`](evidence/0c/youtube-mp3.md) records extraction before publication. `postProcessing`/`packaging` placement and history/notification persistence are contract/PROJECT behavior; the Gate 0C one-item spike did not prove all of those event phases. |
| Playlist with many sequential entries, counters, one item failure continuing to later entries, and success/failure summary. | [`0b/analyze.txt`](evidence/0b/analyze.txt) shows 17 flat entries; [`0b/mp3-playlist.txt`](evidence/0b/mp3-playlist.txt) verifies three sequential source entries and per-entry invocations. Partial-failure continuation is specified by `PROJECT.md:137-138,321-322`, not observed in Gate 0B/0C; mark it synthetic. No per-entry error-detail field may be added. |
| Pause/cancel/resume and explicit retry: pause only during `downloading`; `resume_download` continues simulated percent; `remove_download` cancels/removes; re-enter or enqueue the same request to retry (there is no retry command). UI recreation refetches a paused item without auto-resume. | [`0b/resume-progress.txt`](evidence/0b/resume-progress.txt) proves `.part` reuse at byte 195136; [`0c/process-death.md`](evidence/0c/process-death.md) proves paused restoration and explicit Continue; [`0c/webview.md`](evidence/0c/webview.md) proves refetch then later event. The simulator never creates an actual `.part` file. |
| Typed analysis failures and error notification: invalid URL, HTTP 404/not-found, HTTP 401/restricted; separate process-launch and no-output timeout stimuli, with raw detail kept for diagnostics. | [`0b/errors.txt`](evidence/0b/errors.txt) preserves the actual `ERROR:` lines and distinguishes an OS launch exception and QuickJS watchdog timeout from site errors. The exact mapping of process failures and geo/age split remains pending; use only existing `ErrorCode` values and stop if a new one is needed. `disk_full`, `permission_denied`, and `no_internet` UI cases are contract/spec-driven synthetic cases, with no claimed Gate 0B/0C observation. |

## Stage exit checklist for the owner

- [ ] Resolve the desktop Queue/History side and settings-button conflicts above; confirm no approved image was replaced.
- [ ] At desktop 1920 × 1200, compare header, shell/card geometry, tokens, hierarchy, borders, shadows, and negative space to [`desktop/main-input.png`](../design/desktop/main-input.png). The Input details themselves are a 1B deliverable.
- [ ] At mobile 738 × 1600, compare the app content to [`mobile/main-input.png`](../design/mobile/main-input.png); ignore its captured phone/browser chrome. Check 360, 1024, and intermediate widths for clipping and touch usability.
- [ ] Exercise keyboard navigation, visible focus, screen-reader names/landmarks, disabled controls, and immediate en/es switching; check Spanish expansion and translated error-key coverage.
- [ ] Review the unillustrated Settings shell treatment explicitly; defer its controls, populated History card, notifications, and progress designs to 1C planning/review.
- [ ] Confirm `node --test`, `npm run build`, `npm run check:contracts`, and the foundation verifier pass, with no contract edits or new dependencies.
- [ ] Accept the documented 1A checkpoint explicitly before any 1B work. On any failed acceptance criterion, record evidence and stop; do not work around it.

## Carried-over limits and owner questions

- Android distribution is blocked by the native corresponding-source/build-input/notice gap in `docs/STATE.md`; legal review, full transitive licence audit, and release APK size remain release work outside Phase 1. The Phase 1 Settings shell may reserve an app-update action, but it must not publish/link an APK or imply distribution approval. Android folder selection stays hidden/ignored because v1 uses MediaStore Downloads (`PROJECT.md:162,701`).
- Owner decisions still open: already-MP3 requested bitrate at or above the source rate (`docs/STATE.md`; [`0b/mp3-singles.txt`](evidence/0b/mp3-singles.txt)); developer-info content (`PROJECT.md:707`); exact Spanish copy and mobile layout (`PROJECT.md:717`); accessibility baseline and final logo/icon (`PROJECT.md:718`); geo vs age error split and per-entry failure reasons (`PROJECT.md:713`); large-playlist/live-stream limits (`PROJECT.md:714`); Settings and error-state designs missing from the inventory; process-failure error mapping; and whether to approve Vitest + Testing Library + a DOM environment for interactive 1B/1C component tests. None is decided by this gate.

## Delivery

For each approved task: commit verified work, update and separately commit `docs/STATE.md`, open a PR using the verified absolute GitHub CLI path, and end the session. `1A-10` records the checkpoint; explicit owner acceptance is required before 1B planning or execution.
