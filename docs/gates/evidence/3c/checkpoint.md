<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 3C checkpoint — owner review pending

Gate 3C's Windows x64 V1 and V2 workflows passed again on 2026-11-02 after PR #130 merged the console-window fix at `c586c90c7b4311dd6e3d105052e271ab12dc86d1`. The owner-created `app-v0.0.1` draft now contains the post-fix signed V1 assets and remains unpublished. This checkpoint covers only Gate 3C's Windows and desktop evidence; the global cross-platform criteria remain open. Owner acceptance is still pending.

| Criterion | Gate 3C evidence | Gate result |
|---|---|---|
| AC-20 — one Windows x64 install artifact with documented warning steps | [README installation instructions](../../../../README.md) identify GitHub Releases, recommend NSIS, document MSI use, explain SmartScreen, and describe the WebView2 bootstrapper's Internet condition. V1 verified the signed-updater Windows packages. | Passes for Windows x64. |
| AC-22 — desktop app updates | [Post-fix V1](3c-02.md#signed-production-v1-rerun-after-console-window-fix--passed) verified production signatures and bundle-aware NSIS/MSI metadata. [Post-fix V2](3c-03.md#post-merge-downloadbootstrapper-v2-rerun-after-console-window-fix--passed) installed and updated both formats to version `0.0.1`, relaunched, and uninstalled them. | Passes for NSIS and MSI. |
| AC-23 — exact release artifact set | V1 verified exactly `latest.json`, NSIS `.exe` and `.sig`, and WiX MSI and `.sig` in the owner draft. No other platform or bundle format was attached. | Passes for Windows x64; Linux, macOS, and Android deliverables remain open. |
| AC-36 — desktop provenance | [Desktop provenance record](release-provenance.md) maps Windows FFmpeg and QuickJS versions, output and source hashes, reproducible commands, notices, and the LGPL-compatible FFmpeg configuration. | Recorded for the desktop inputs; the per-release source/compliance bundle still must accompany a public release. Android provenance and audit remain open. |

## V3 verification

- The post-fix signed V1 workflow passed asset allowlisting, bundle-aware metadata, production-key signature checks, and tamper rejection in [run 41515896085](https://github.com/zahidzta/zownload_application/actions/runs/41515896085).
- Post-fix installed NSIS/MSI review passed clean install, matching-format update, post-update launch/version, and uninstall in [run 41519891153](https://github.com/zahidzta/zownload_application/actions/runs/41519891153); see the [uploaded scenario record](3c-03.md#post-merge-downloadbootstrapper-v2-rerun-after-console-window-fix--passed).
- The focused verifier regression passed in Windows PowerShell 5.1 and PowerShell 7 using the pinned Minisign 0.9 installer: valid signed fixtures and rejected tampering returned success, while invalid metadata and signatures returned failure. Bundle asset-ID URL resolution passed in both shells.
- `powershell -NoProfile -File scripts/verify-foundation.ps1` passed the frontend, contract, Rust unit/integration, and nine-image design checks. `cargo fmt --manifest-path src-tauri/Cargo.toml -- --check` passed.
- Relative Markdown targets resolved in all seven changed documents; the README installation steps and desktop provenance links were reviewed against the approved spec and source records; `git diff --check` passed.
- After the console issue was reported, `cargo test --manifest-path src-tauri/Cargo.toml --test process_tree` passed, including the new no-console regression, and foundation verification passed again on the fix.

## Carry-forward items

- Global AC-23 still requires the assigned Linux, macOS, and Android artifacts and verification.
- Android distribution remains blocked until the youtubedl-android binary sources, exact build inputs, notices, and transitive license audit are established. Do not distribute an Android build while this blocker remains; see [STATE.md](../../../STATE.md#release-blocker--android-distribution).
- The public-release source/compliance bundle, legal review, and remaining release checks listed in [STATE.md](../../../STATE.md#release-blocker--android-distribution) remain required. Gate 3C did not create or publish a release.

**Owner decision:** Gate 3C checkpoint acceptance is pending. Do not start Gate 4A until the owner accepts this checkpoint.
