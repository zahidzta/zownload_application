<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 2B — Windows engine bootstrap and analysis

## Scope and authority

The owner accepted the [Gate 2A checkpoint](evidence/2a/checkpoint.md) on 2026-10-25 and requested this plan. [Appendix A](../../PROJECT.md) requires focused tests, a real native scenario, review, and explicit acceptance of the **2B checkpoint** before Stage 2C. This task plans 2B; it does not implement the engine or accept its future results.

Stage 2B makes the Windows Tauri app copy the pinned baseline yt-dlp, FFmpeg, and QuickJS executables into `<app_data>/engine/`, check those copies, and run real URL analysis through supervised yt-dlp processes. The app returns the existing `AnalyzeResult` or a typed `AppError`; browser mock tests stay isolated. [Gate 0B's locked sources](../engine-sources.md), [artifact hashes](evidence/0b/checkpoint.md), and [working analysis commands](../ytdlp-commands.md) are the executable baseline. `shared/contract.ts` and `src-tauri/src/contract.rs` govern exchanged fields and types. [PROJECT-INDEX](../PROJECT-INDEX.md) locates the narrow specification ranges for each task.

There is no download execution, media output, queue progress, `.part` recovery, playlist processing, or engine update in 2B. Native enqueue remains queued as in 2A. Stage 2C owns single downloads and the real queue lifecycle; 2D owns network update, probation, fallback, and app-update refresh; 3A owns playlist execution. Android keeps its separate spike handler and database. The Android distribution blocker in [STATE](../STATE.md) remains open.

Each task is one session on its own `task-<id>` branch. After exact verification, commit the task, update `docs/STATE.md` in a separate commit, open a PR with `& 'C:\Program Files\GitHub CLI\gh.exe' pr create`, and stop. Never merge, force-push, release, or begin 2C before owner acceptance. New hand-written source files start with the GPL-3.0-or-later/zahidzta/2026 SPDX header. Before writing code using Tauri, Rust crates, React, or another library/framework, consult its current documentation through context7. Keep command output to failures or the last 50 lines.

## Boundaries and implementation decisions

1. **Baseline provenance.** Use only the Gate 0B pinned Windows x64 artifacts and checksums. A repeatable preparation command stages them for Tauri development/build from verified local artifacts or the existing locked acquisition/build scripts. Generated executables remain ignored by Git; the stage records exact inputs and output hashes. Do not silently substitute a newer release or a system-installed binary. Resource packaging is scoped to the Windows baseline in this stage; Linux/macOS ports remain Phase 4 work.
2. **Execution location.** Installation resources are copy sources only. Health probes and analysis run only the checked app-data copies, including QuickJS by absolute path. Use staging and replacement so a failed copy or health check cannot leave a partly active engine. Keep the manifest fields needed by later 2D work, without implementing update or probation behavior now. No desktop process may run directly from `work/engine/`, the installation resources, or `PATH`.
3. **Process ownership.** Rust owns spawning with an argument array, bounded output and a timeout; Windows supervision must terminate yt-dlp and its descendant process tree on cancellation, window close, and parent process death. Keep the platform-specific process-tree code small and documented. A stub executable that creates a child is required evidence; killing only yt-dlp's immediate PID is insufficient. Analyse calls must not block the UI thread.
4. **Analysis semantics.** Preserve watch-plus-list URLs as singles and analyze pure playlist URLs as playlists, using the verified `--no-playlist`/`--flat-playlist` modes. Pass only validated HTTP(S) URLs after `--`, disable user configuration and default JS runtimes, and select the app-data QuickJS copy. Parse yt-dlp JSON into the existing single/playlist variants. Single MP3 choices are `[320,256,192,128]` requested maxima; video heights come from available formats. Emit size estimates only when supported by trustworthy engine data. The playlist preview uses its own cover, or the first entry's cover when it has none; later per-entry downloads must retain each entry's own cover.
5. **Failure semantics.** Map known invalid, unsupported, restricted, unavailable, and offline cases to the existing error codes; retain raw diagnostic detail for `unknown`. Missing/broken engine uses `engine_missing`; spawn failure, malformed JSON, timeout, and cancelled analysis use an existing code with diagnostic detail and leave no child process. Do not invent a new wire code or use an analysis failure as an updater fallback trigger in 2B. A typed error reaches the existing translated Input alert.
6. **Acceptance boundary.** Stub tests cover bootstrap, supervision, JSON parsing, URL-mode choice, and error mapping without network. Native Windows evidence must show a real single, a pure playlist, and a mixed watch/list analysis with pinned copies, plus full process-tree cleanup when the app window closes. If live sites change, keep the failure in 2B with evidence; do not declare the checkpoint passed from stubs alone.

## Verification commands

Run from the repository root. Document setup and exact staged binary hashes in [toolchain](../toolchain.md) or focused gate evidence. Keep `tests/interactive` under Vitest/jsdom and the existing Node suite separate.

- **V0 (2B-01 documentation):** check every changed relative Markdown link target, `git diff --check`, then `git diff --cached --check` after staging.
- **V1 (Rust engine tasks 2B-02 through 2B-06):** `powershell -NoProfile -Command 'cargo fmt --manifest-path src-tauri/Cargo.toml --check; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo test --manifest-path src-tauri/Cargo.toml; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo check --manifest-path src-tauri/Cargo.toml; exit $LASTEXITCODE'`. For 2B-02, also run its preparation command against the locked artifacts and verify the staged hashes.
- **V2 (native integration task 2B-07):** `powershell -NoProfile -Command 'npm run build; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; npm run test:ui; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; npm run check:contracts; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; node --test --test-concurrency=1; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo fmt --manifest-path src-tauri/Cargo.toml --check; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo test --manifest-path src-tauri/Cargo.toml; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo check --manifest-path src-tauri/Cargo.toml; exit $LASTEXITCODE'`.
- **V3 (2B-08/09 native review and checkpoint):** `powershell -NoProfile -Command 'npm run test:ui; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; node --test --test-concurrency=1; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo fmt --manifest-path src-tauri/Cargo.toml --check; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; powershell -NoProfile -File scripts/verify-foundation.ps1; exit $LASTEXITCODE'`, plus the deterministic Windows child-tree test and the recorded real native analysis/close scenarios. A passing command does not replace those manual observations.

## Tasks

### 2B-01 — Accepted 2A handoff and task plan — OWNER-REVIEW

- Goal: record the owner's 2A acceptance, define the 2B task sequence, exact verification, and 2C/2D/3A boundaries.
- Files: `docs/gates/gate-2b.md`, `docs/gates/evidence/2a/checkpoint.md`, `docs/STATE.md`.
- Read: `PROJECT.md:180-195,263-288,309-340,511-521,555-617,618-645,646-693,734-745,763-770`.
- Acceptance: changed Markdown links resolve, **V0** passes, and no source, dependency, or contract file changes. Stop for owner review of the plan before implementation.

### 2B-02 — Verified Windows baseline staging — AUTOMATABLE

- Goal: prepare the locked yt-dlp, FFmpeg, and QuickJS Windows x64 artifacts for native development and bundling, with reproducible verification of all three output hashes. Keep generated binaries out of Git and source/build records traceable.
- Files: focused staging script/configuration under `scripts/` and `src-tauri/`, focused tests/evidence, `docs/toolchain.md`, `docs/STATE.md`.
- Read: `PROJECT.md:180-184,263-275,331-337,618-629,763-768`; Gate 0B source lock, hashes, and build commands.
- Dependencies: 2B-01 plan approval. Acceptance: clean staging rejects missing/mismatched inputs, passes with locked artifacts, and Tauri resolves all three Windows resources without relying on a system engine. Exact verification: **V1** plus staged hash check.

### 2B-03 — App-data bootstrap and health checks — AUTOMATABLE

- Goal: copy verified baseline resources through staging into `<app_data>/engine/`, run bounded yt-dlp/FFmpeg/QuickJS health probes on those copies, and record a minimal durable engine manifest for later 2D extension. Reopen uses healthy copies; failed preparation leaves the prior healthy set intact.
- Files: `src-tauri/src/engine/` bootstrap module, Tauri setup integration, focused Rust tests, `docs/STATE.md`.
- Read: `PROJECT.md:180-185,263-275,511-521,331-337,763-768`.
- Dependencies: 2B-02. Acceptance: first launch, repeat launch, missing/corrupt resource, failed probe, and replacement rollback tests pass; every executed path is under app data. No network update logic. Exact verification: **V1**.

### 2B-04 — Windows process-tree supervisor — AUTOMATABLE

- Goal: centralize child launch, bounded stdout/stderr capture, timeout, cancellation, and complete Windows descendant cleanup. Bind children to app lifetime, including an abrupt parent exit.
- Files: `src-tauri/src/engine/` process module and small Windows-specific helper, `src-tauri/src/lib.rs` close hook, deterministic child-spawning stub tests, `docs/STATE.md`.
- Read: `PROJECT.md:309-314,337-339,618-623,630-645,665-679,763-768`.
- Dependencies: 2B-03. Acceptance: argument-array execution, timeout, explicit cancel, window-close trigger, and parent-death scenarios leave no stub child; no orphan process survives. Exact verification: **V1** plus Windows child-tree test.

### 2B-05 — yt-dlp analysis and contract conversion — AUTOMATABLE

- Goal: run metadata-only yt-dlp analysis with the pinned QuickJS copy and convert bounded JSON into exact `AnalyzeResult` shapes for single, pure playlist, and watch/list mixed URLs.
- Files: `src-tauri/src/engine/` analysis/parser modules, JSON fixtures from Gate 0B observations, focused Rust tests, `docs/STATE.md`.
- Read: `PROJECT.md:107-131,234-253,555-588,618-623,646-659,763-768`; Gate 0B analysis matrix.
- Dependencies: 2B-04. Acceptance: URL mode, title/author/site/duration, unique descending video heights, fixed audio maxima, playlist count/titles, cover fallback, and absent estimates when unsupported pass. No media file is written. Exact verification: **V1**.

### 2B-06 — Typed analysis errors and limits — AUTOMATABLE

- Goal: validate URL/response bounds and map observed yt-dlp and process failures into the existing `AppError` codes with diagnostic detail; cancel timed-out work through the supervisor.
- Files: `src-tauri/src/engine/` error mapping, focused Rust tests/fixtures, `docs/STATE.md`.
- Read: `PROJECT.md:113-120,598-629,630-645,646-659,763-768`; Gate 0B error observations.
- Dependencies: 2B-05. Acceptance: invalid, unsupported, restricted, not found, offline, missing/broken engine, malformed output, timeout, and unknown cases have deterministic tests and no process leak. No contract field/type change. Exact verification: **V1**.

### 2B-07 — Native command and UI analysis integration — AUTOMATABLE

- Goal: replace the native `analyze_url` deferred response with the desktop engine, remove the development Tauri offline-preview exception, and keep browser simulator tests isolated. Preserve the existing preview and translated Input error behavior.
- Files: `src-tauri/src/commands/`, `src-tauri/src/lib.rs`, native transport selection in `src/`, focused Rust/UI tests, `docs/STATE.md`.
- Read: `PROJECT.md:107-131,234-253,555-617,646-659,763-768`.
- Dependencies: 2B-03 through 2B-06. Acceptance: native analysis returns contract JSON and typed errors, UI shows single/playlist previews from real results, browser tests remain deterministic, and enqueue still does not execute downloads. Exact verification: **V2**.

### 2B-08 — Real Windows analysis and shutdown review — OWNER-REVIEW

- Goal: run the native app with pinned app-data copies, analyze a real single, a pure playlist, and a mixed watch/list URL, then close the window during an active stub analysis and inspect the complete process tree. Record hashes, paths, result fields, timings, screenshots, and any site-specific limits without recording private user data.
- Files: `docs/gates/evidence/2b/native-analysis.md`, focused fixes/tests if evidence exposes a defect, `docs/STATE.md`.
- Read: `PROJECT.md:107-131,180-184,309-314,598-629,646-659,679,763-768`.
- Dependencies: 2B-07. Acceptance: native real results match the contract and URL-mode rule, an active close leaves no child processes, owner reviews the visible result, and **V3** passes. A failed observation is fixed in 2B.

### 2B-09 — Stage evidence and owner checkpoint — OWNER-REVIEW

- Goal: link the locked baseline, bootstrap, supervisor, parser/error tests, native real single/playlist/mixed analysis, shutdown evidence, and exact **V3** result in `docs/gates/evidence/2b/checkpoint.md`.
- Files: `docs/gates/evidence/2b/checkpoint.md`, `docs/STATE.md`.
- Read: `PROJECT.md:630-645,646-693,734-745,763-770`.
- Dependencies: 2B-02 through 2B-08 and owner review of the native result. Acceptance: reviewable evidence states what 2B proves and the remaining 2C/2D/3A limits. Stop for explicit owner acceptance before 2C.

## Stage exit

Gate 2B exits only with verified app-data execution, real single/playlist analysis, typed failures, and process-tree cleanup on close. A failed criterion stays in 2B. Queue execution, file output, updater checks/swaps, and playlist processing remain in their scheduled stages.
