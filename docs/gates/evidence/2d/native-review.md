<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 2D-07 — Native Windows update review

**Observed:** 2026-10-29. **Status:** verification complete; the owner accepted the Gate 2D checkpoint on 2026-10-29.

## Verification setup and result

The exact Gate 2D V3 sequence passed in a clean detached checkout at commit `0e87890`, using the pinned Node `24.22.0` and npm `11.19.1`. `npm ci` installed 120 packages with zero reported vulnerabilities. The three ignored Windows engine resources (`yt-dlp.exe`, `ffmpeg.exe`, `qjs.exe`) were copied into the checkout so the fallback scenarios exercised the real pinned baseline. Cargo used the main checkout's target directory.

- `npm run test:ui`: 60 passed across 13 files.
- `node --test --test-concurrency=1`: 18 passed, zero failed.
- `cargo fmt --manifest-path src-tauri/Cargo.toml --check`: passed.
- `powershell -NoProfile -File scripts/verify-foundation.ps1`: frontend build, contract fixture check, all Rust tests, and nine-image design inventory passed. Rust had 75 passing unit tests; all non-ignored integrations passed, including the updater fixture and Windows engine/queue scenarios.
- Focused reruns passed: `app_update` (1), `probation_queue` (1), `process_tree` (1 plus its helper), and `queue_lifecycle` (1). Focused updater tests passed (13) and app-update state tests passed (4).

The first V3 attempt in the task checkout found 36 Node tests and failed seven stale tests under the ignored nested checkout `work/engine/2b-09/clean`. That recursive discovery is why final V3 was run from a clean detached checkout outside the repository tree. The clean run found the expected 18 tests and passed without source changes. Rust emitted the existing non-fatal `restore_baseline` dead-code warning.

## Official stable release observation

On 2026-10-29, the [official latest-release API](https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest) still returned stable tag `2026.10.26` (`draft = false`, `prerelease = false`) with one `yt-dlp.exe` and one `SHA2-256SUMS` asset. The [official checksum file](https://github.com/yt-dlp/yt-dlp/releases/download/2026.10.26/SHA2-256SUMS) again returned this exact entry:

```text
f5389d3698ecde4ef06f4e6b1ce0294fe9ac1396228c8990b8d3416d6d177a7d  yt-dlp.exe
```

The complete asset download, matching local SHA-256, and successful `--version` probe for `2026.10.26` were performed on 2026-10-28 and are recorded in [engine-update.md](engine-update.md). This session reconfirmed the release metadata and checksum line, but did not complete a second 23.5 MB asset download; a slow partial transfer was stopped before the candidate was run. No new health probe is claimed for 2026-10-29.

## Native scenario evidence

| Acceptance | Fixture or test | Observed result |
|---|---|---|
| AC-21 — manual and daily engine outcomes | Local release-server unit coverage: `same_and_older_releases_do_not_download`, `local_release_is_staged_only_after_exact_checksum`, `automatic_engine_check_is_throttled_for_24_hours`, `automatic_checks_skip_failed_versions_and_persist_the_clock`, and `a_failed_release_gets_one_persisted_manual_retry`. Settings interaction coverage is in `tests/interactive/settings.test.tsx`. | Same/older release, available candidate, durable pending state, 24-hour automatic throttle, failed-version automatic skip, one persisted manual retry, and visible available/completed statuses passed. The check/update buttons remain separate from the app updater. Settings text tests use the deterministic browser simulator; the Rust updater tests exercise the native engine logic. |
| AC-24 — reject failed verification | `checksum_mismatch_never_executes_and_preserves_active_manifest`, `malformed_release_and_non_executable_candidate_are_rejected`, and `verified_candidate_activates_from_app_data_and_fallback_restores_baseline`. | Checksum, malformed metadata, non-executable and wrong-version candidates were rejected before activation; the active copy stayed intact. |
| AC-25 — probation crash and baseline retry | Windows `probation_queue_scenarios` with a locally compiled crashing yt-dlp stub and pinned bundled resources. | The updated copy was reverted; the bundled baseline was copied into app data and used for exactly one retry. The broken version was persisted in `failedVersions`, and the item settled once. Malformed analysis JSON also triggered one retry. |
| AC-26 — ordinary site error | `reported_site_error_keeps_updated_copy_and_completes_probation` in `probation_queue_scenarios`. | A reported `ERROR:` site failure kept the updated copy, marked probation good, and did not revert. |
| AC-27 — busy deferral, restart, and accepted update | `local_release_is_staged_only_after_exact_checksum`, `healthy_updated_copy_and_manifest_survive_restart_and_app_refresh`, and `verified_candidate_activates_from_app_data_and_fallback_restores_baseline`. | The verified pending candidate and manifest survived restart. An active engine-slot lease held activation; releasing it allowed the verified candidate to activate into app data in probation. The candidate was never probed before checksum verification. |
| AC-28 — bundled tool refresh after app update | `app_refresh_replaces_changed_tools_without_downgrading_updated_ytdlp`. | FFmpeg and QuickJS refreshed from the app bundle while a newer updated yt-dlp remained active. |
| AC-22 detection/action portion — separate app update | Native `app_update.rs::updater_verifies_local_signed_assets_for_both_installer_targets`; Rust app-update tests and `tests/interactive/settings.test.tsx`. The local fixture serves signed `latest.json` and installer bytes for NSIS and MSI. | Stable update detection and signed download passed for both targets; altered artifact bytes were rejected. The UI retains the persistent **Update Zownload** action and invokes it only after a click. Engine and app-update status/clocks remain separate. This verifies detection and action wiring only; it does not install either fixture. |

Windows process-tree cleanup and queue lifecycle integrations also passed. These cover timeout, cancellation, close, parent exit, sequential settlement, and durable queue ownership alongside the update scenarios.

## Limits

- The app-update fixture verifies signed metadata selection and artifact download/signature validation through Tauri's native test builder. It does not install a packaged NSIS or MSI update. Installed upgrade proof, release metadata, and production signing remain in 3C.
- No packaged-app or physical-window visual capture was produced. Settings status wording and click behavior are exercised by interactive tests; owner review of the visible outcomes remains part of checkpoint acceptance.
- The temporary fresh official binary download was stopped before completion because of transfer speed. The full checksum and health observation remains the 2026-10-28 result linked above; the official release metadata and checksum line were reconfirmed on 2026-10-29.
