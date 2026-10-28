<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 2D — Windows engine updater and app-update detection

## Scope and authority

The owner explicitly accepted the [Gate 2C checkpoint](evidence/2c/checkpoint.md) on 2026-10-28 and requested this plan. [Appendix A](../../PROJECT.md) makes Stage 2D a separate checkpoint before 3A. This task plans 2D; it does not download or execute an update. [PROJECT-INDEX](../PROJECT-INDEX.md) identifies the narrow requirements: `PROJECT.md:169-185,263-288,315-340,511-521,559-584,598-629,630-645,664-681,734-745,763-770`.

Stage 2D updates **desktop yt-dlp only** from the latest stable official release, using a staged, checksum-verified candidate, a bounded health check, queue-idle activation, probation, and a baseline fallback. It also checks for a stable Zownload app release at startup at most once per day and presents a separate persistent **Update Zownload** action when available. The existing [2B app-data engine](evidence/2b/checkpoint.md) and [2C single queue](evidence/2c/checkpoint.md) are the starting points. The current `engine/mod.rs` bootstrap accepts only `source: "bundled"` and the pinned version; it would overwrite an accepted updated yt-dlp on restart. Fixing that reconciliation is the first implementation task. Existing `engine_check_update` and `engine_update` commands are deferred native stubs; the Settings screen and browser simulator already exercise their contract.

Stage 3A owns playlist execution, 3B owns ZIP and full filesystem stress, and 3C owns Windows installer artifacts, production updater metadata/signatures, and installed NSIS/MSI upgrade proof. Stage 2D tests app-update discovery and the action against signed local stub metadata before those artifacts exist. Linux/macOS and Android update implementations remain in their scheduled stages. The [Android distribution blocker](../STATE.md#release-blocker--android-distribution) remains open. No production release, new public error code, or changed approved behavior is authorized by this plan.

Each task is one session on its own `task-<id>` branch. After exact verification, commit the task, update `docs/STATE.md` in a separate commit, open a PR with `& 'C:\Program Files\GitHub CLI\gh.exe' pr create`, and stop. Never merge, force-push, release, or start 3A before owner acceptance of the 2D checkpoint. New hand-written source files start with the GPL-3.0-or-later/zahidzta/2026 SPDX header. Before writing code using Tauri, Rust crates, React, or another library/framework, consult its current documentation through context7. Keep command output to failures or the last 50 lines.

## Decisions for owner review before implementation

1. **Minimal contract addition for durable update status.** The current [`EngineUpdateInfo`](../../shared/contract.ts) has only `current`, `latest`, and `updateAvailable`. It cannot tell Settings that activation is waiting for an active process or identify a version reverted after probation. Propose optional `pendingVersion?: string` and `revertedVersion?: string`, mirrored in [`contract.rs`](../../src-tauri/src/contract.rs). Existing fields keep their meaning; `current` always names the copy actually in use. The manifest persists pending and reverted status so Settings can explain it after restart. Approve this additive contract shape before 2D-02; no new error code is needed.
2. **One native HTTPS client.** Propose a pinned `reqwest` blocking client with Rustls and only the features needed for bounded GitHub release metadata, checksum text, and streamed executable downloads. Its exact compatible pin is selected in 2D-03 after consulting current documentation. No downloader endpoint beyond [official yt-dlp GitHub Releases](https://github.com/yt-dlp/yt-dlp/releases) is introduced. The current official release publishes a Windows executable and `SHA2-256SUMS`; candidate tag, asset, and checksum entry must still match exactly. Redirects, response sizes, timeouts, and temporary files are bounded. This is the only proposed new engine-network dependency.
3. **Queue-safe activation and replay.** A manual update requested during yt-dlp activity reports a pending version and activates only after the active process has exited and the queue coordinator has held the next start. Persist the pending candidate so a restart can finish activation when idle. A probation failure cancels or finishes the failing invocation, restores a verified bundled yt-dlp through app-data staging, and retries that invocation **once** against the baseline while retaining its owned partial file and queue identity. A second failure follows normal analysis/download error handling; it cannot loop. Ordinary yt-dlp `ERROR:` site/network output never triggers fallback. A failed release version gets **one explicit manual retry per recorded version**; automatic checks keep skipping it. Approval of this plan authorizes the coordinator/manifest changes, not a new public queue status.
4. **App-update boundary.** Use the confirmed Tauri updater plugin version `2.13.0` and [Tauri's static `latest.json` format](https://v2.tauri.app/plugin/updater/) with a custom target that preserves NSIS/MSI identity. The JSON contains each artifact's signature; it is the **downloaded artifact** that the plugin verifies, so do not describe the JSON itself as signed. Stage 2D tests daily throttling, stable-channel selection, persistence of an available action, and a stubbed updater action with local metadata and signed test artifacts. Stage 3C supplies real signing keys, release metadata, NSIS/MSI packages, and installed upgrade evidence; if an installer format cannot be updated reliably, apply FR-75's direct-link fallback during 3C review. The app updater and engine updater have separate clocks, statuses, and Settings actions. Do not silently install an app update at startup.

## Verification commands

Run from the repository root. Record exact setup, tested binary hashes, local fixture URL, and native results in focused evidence or [toolchain](../toolchain.md).

- **V0 (2D-01 documentation):** check every changed relative Markdown link target, then `git diff --check` and, after staging, `git diff --cached --check`.
- **V1 (2D-02 through 2D-04 Rust engine tasks):** `powershell -NoProfile -Command 'cargo fmt --manifest-path src-tauri/Cargo.toml --check; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo test --manifest-path src-tauri/Cargo.toml; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo check --manifest-path src-tauri/Cargo.toml; exit $LASTEXITCODE'`, plus the focused Windows process-tree and queue tests when lifecycle code changes.
- **V2 (2D-05/06 native UI and app discovery):** `powershell -NoProfile -Command 'npm run build; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; npm run test:ui; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; npm run check:contracts; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; node --test --test-concurrency=1; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo fmt --manifest-path src-tauri/Cargo.toml --check; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo test --manifest-path src-tauri/Cargo.toml; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo check --manifest-path src-tauri/Cargo.toml; exit $LASTEXITCODE'`.
- **V3 (2D-07 native review/checkpoint):** `powershell -NoProfile -Command 'npm run test:ui; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; node --test --test-concurrency=1; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo fmt --manifest-path src-tauri/Cargo.toml --check; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; powershell -NoProfile -File scripts/verify-foundation.ps1; exit $LASTEXITCODE'`, plus focused Windows process-tree/queue tests and the recorded native update/fallback scenarios. A passing V3 command does not replace the native observations.

## Tasks

### 2D-01 — Accepted 2C handoff and task plan — OWNER-REVIEW

- Goal: record explicit 2C checkpoint acceptance and define the 2D sequence, owner decisions, exact verification, and 3C boundary.
- Files: `docs/gates/gate-2d.md`, `docs/gates/evidence/2c/checkpoint.md`, `docs/STATE.md`.
- Read: `PROJECT.md:169-185,263-288,315-340,511-521,559-584,598-629,630-645,664-681,734-745,763-770`; 2B/2C checkpoints.
- Acceptance: changed relative Markdown links resolve, **V0** passes, and no source, dependency, or contract file changes. Stop for owner review of the four decisions above before implementation.

### 2D-02 — Manifest and app-version reconciliation — AUTOMATABLE

- Goal: preserve a healthy accepted updated yt-dlp across restart, migrate/recover the existing 2B manifest, and refresh bundled FFmpeg/QuickJS after an app-version change. Replace yt-dlp only when the new bundled date-version is newer than the active one. Keep all executions under app data and use staged replacement with a recoverable previous state.
- Files: focused `src-tauri/src/engine/` bootstrap/manifest code, both contract files for the approved optional fields, focused Rust/contract tests, `docs/STATE.md`.
- Read: `PROJECT.md:180-185,263-275,331-337,511-521,598-617,630-645,679-681,763-770`.
- Dependencies: owner acceptance of 2D-01 and contract decision. Acceptance: first launch, unchanged restart, updated/probation restart, legacy manifest, corrupt/missing copy, interrupted replacement, newer/same/older bundled version, FFmpeg/QuickJS refresh, and `failedVersions`/check-clock preservation pass. Exact verification: **V1** plus `npm run check:contracts`.

### 2D-03 — Official release candidate and safe activation — AUTOMATABLE

- Goal: check the latest stable yt-dlp release; fetch the Windows asset and published checksum; verify the exact SHA-256 **before any execution**; run bounded version/health probes; promote only while the coordinator holds an idle yt-dlp slot. Keep the old active copy if fetching, verification, probing, or promotion fails; record failed versions per BR-18. Make a busy-queue request durable and complete it when idle or on the next app start.
- Files: focused `src-tauri/src/engine/` updater/process code, queue integration, `src-tauri/Cargo.toml`/lockfile for the approved HTTPS client, local HTTP/release fixtures and Rust tests, `docs/toolchain.md`, `docs/STATE.md`.
- Read: `PROJECT.md:180-185,263-282,330-337,511-521,618-629,630-645,667-680,763-770`.
- Dependencies: 2D-02 and approved dependency. Acceptance: real stable release asset/checksum discovery recorded; deterministic local tests cover current/new/failed versions, checksum mismatch, wrong tag/version, non-executable candidate, timeouts, interrupted download, invalid metadata, queue-busy deferral, Windows running-executable guard, atomic activation, restart, and no unverified execution. Exact verification: **V1** and focused Windows process-tree/queue tests.

### 2D-04 — Probation, baseline fallback, and one retry — AUTOMATABLE

- Goal: classify the first post-swap invocation, mark normal completion `good`, and on process-level breakage restore the verified bundled yt-dlp into app data and retry that invocation once. Preserve queue ownership and `.part`; surface the failed version for Settings. The baseline failing health check produces `engine_missing` without a retry loop.
- Files: focused `src-tauri/src/engine/` analysis, process, queue, and updater code, focused Rust tests/fixtures, `docs/STATE.md`.
- Read: `PROJECT.md:180-185,263-288,323-337,598-629,630-645,667-680,763-770`.
- Dependencies: 2D-03. Acceptance: crashing/spawn-error/nonzero-without-`ERROR:`/silent-timeout/malformed-analysis-JSON stubs trigger fallback; normal success clears probation; `ERROR:` site/network cases do not; baseline executes from app data, broken version is recorded, one retry succeeds or settles normally, and no child survives cancellation/close. Exact verification: **V1** and focused Windows process-tree/queue tests.

### 2D-05 — Engine checks, outcomes, and Settings — AUTOMATABLE

- Goal: implement native manual `engine_check_update`/`engine_update`, one startup check per 24 hours, and translated Settings outcomes for current, available, pending, updated, failed, and reverted versions. Manual retry of a failed version is allowed once and explained; automatic checks skip it. Browser simulator remains deterministic.
- Files: `src-tauri/src/commands/`, engine scheduler, focused `src/state/`, `src/components/SettingsShell.tsx`, `shared/i18n/`, Rust and `tests/interactive/` tests, `docs/STATE.md`.
- Read: `PROJECT.md:169-185,263-288,331-337,559-584,598-617,630-645,664-680,763-770`.
- Dependencies: 2D-04. Acceptance: current/latest/outcome values reflect the copy in use, manual check is not blocked by the daily clock, update while busy is visibly pending, failed-version auto skip and manual retry work, locale switches immediately, update failures preserve the working copy, and no engine action starts an app update. Exact verification: **V2**.

### 2D-06 — Stable desktop app-update discovery — AUTOMATABLE

- Goal: add a separate daily startup check through the pinned Tauri updater, using bundle-type-aware stable `latest.json` with artifact signatures; show a persistent Update Zownload action only when a newer release exists. Keep its clock and errors separate from yt-dlp. Use local metadata and signed test artifacts until 3C supplies release artifacts and production keys.
- Files: focused Tauri updater configuration/setup and `src-tauri/Cargo.toml`/lockfile, `src/state/`, `src/components/SettingsShell.tsx`, `shared/i18n/`, focused native/UI tests, `docs/toolchain.md`, `docs/STATE.md`.
- Read: `PROJECT.md:169-185,288-308,511-521,559-597,618-629,630-645,668-681,763-778`.
- Dependencies: 2D-05 and current Tauri updater documentation through context7. Acceptance: signed good/bad metadata, stable-only selection, 24-hour throttle, persisted available action after UI recreation/restart, NSIS/MSI bundle identity, no automatic install, and isolated engine/app errors pass against local fixtures. Production installation and package fallback evidence remain for 3C. Exact verification: **V2**.

### 2D-07 — Native Windows update review and checkpoint — OWNER-REVIEW

- Goal: exercise the native app with a local release fixture and stub yt-dlp, plus an actual official stable release checksum/health observation. Show manual and daily outcomes, busy deferral, restart, accepted update, failed verification, probation crash/re-copy/retry, ordinary site error, and separate app-update action. Link tests and limits in the 2D checkpoint.
- Files: `docs/gates/evidence/2d/` native record and checkpoint, focused fixes/tests if evidence exposes a defect, `docs/STATE.md`.
- Read: `PROJECT.md:169-185,263-288,315-340,598-629,630-645,664-681,734-745,763-778`.
- Dependencies: 2D-02 through 2D-06 and owner review of visible update outcomes. Acceptance: **V3** and focused native scenarios pass; evidence maps AC-21 and AC-24..28 plus the **detection/action portion** of AC-22, explicitly leaving installed NSIS/MSI app upgrade proof for 3C. Stop for explicit owner acceptance before 3A.

## Stage exit

Gate 2D exits with a verified, restart-safe Windows yt-dlp updater and baseline fallback, separate stable app-update discovery, translated Settings outcomes, and documented native evidence. Installed app updates, release signing/packaging, playlists, ZIP, other desktop platforms, and Android updates remain in their scheduled stages. A failed criterion stays in 2D.
