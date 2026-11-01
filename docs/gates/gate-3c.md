<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 3C — Windows installer and updater release

## Scope and checkpoint

Gate 3C prepares the Windows x64 release path: unsigned NSIS and WiX MSI installers, production-signed Tauri updater artifacts, bundle-aware release metadata, a GitHub release workflow, install/update documentation, and installed upgrade evidence for both formats. The owner accepted the Gate 3B checkpoint on 2026-10-31; see the [Gate 3B checkpoint](evidence/3b/checkpoint.md).

Read only these `PROJECT.md` ranges for this gate: `180-204,263-308,618-627,630-644,646-684,734-745,778`. These rules require the exact Windows x64 installer formats, bundle-aware updater targets, signed updater payloads, unsigned installers with SmartScreen instructions, clean install/uninstall/upgrade tests for both formats, and release compliance evidence.

This gate does not publish a public release. It prepares the artifacts and workflow for owner-controlled release use. Windows installers remain unsigned as specified in PROJECT.md; the Tauri updater packages have production signatures. Keep the updater private key in GitHub Actions secrets and put only its matching public key in the app configuration. Do not change the confirmed Tauri updater version, install formats, public contract, or app behavior without separate owner approval. Before changing Tauri bundling or updater configuration, consult the current Tauri documentation through Context7.

The existing updater fixture uses a test public key. Replace it with the public key matching the production signing secret during implementation. The release workflow must emit only Windows x64 NSIS `.exe` and WiX `.msi` installers and their updater metadata/signatures; it must not publish other platform formats early. Run an explicit Windows CI build with VBSCRIPT support enabled, then validate the generated artifacts and signatures before they can be attached to an owner-created draft release. The owner remains responsible for creating or publishing releases.

## Owner review before implementation

The roadmap row for 3C names AC-20, AC-22, AC-23, and AC-36, while AC-23 and AC-36 describe the full multi-platform artifact set and Android release compliance. Linux, macOS, and Android artifacts are assigned to 4A, 4B, and 5C, and Android source/build provenance is still a release blocker. Recommended scope: prove the Windows portion of AC-23 and the desktop portion of AC-36 in 3C, record the remaining platform requirements as open, and do not claim either global criterion complete until its later gates and Android blocker are resolved. The owner must confirm this scope before implementation.

## Verification

Run from the repository root. Keep install tests in disposable Windows VMs or isolated test accounts; never upgrade or uninstall the owner's installed app. Do not expose signing secrets in workflow output, build artifacts, logs, or evidence. No public release is part of verification.

- **V0 (3C-01 plan):** check every changed relative Markdown link target and run `git diff --check`; after staging, run `git diff --cached --check`.
- **V1 (Windows packages and metadata):** run the production workflow in an owner-controlled draft-release test path. Verify the exact Windows artifact allowlist, NSIS/MSI-specific `latest.json` entries, matching `.sig` files, signature verification with the configured public key, package versions, and desktop release notices/provenance. Confirm no other platform formats are emitted.
- **V2 (installed behavior):** for NSIS and MSI independently, record clean install, launch/version, in-place upgrade from a prior version, updater download/verification/install, relaunch/version, and uninstall results. Confirm each installed format receives its matching update. If either package's updater proves unreliable, evaluate FR-75's direct-download fallback and return the finding for owner review.
- **V3 (release readiness):** rerun focused package/updater checks and the existing project verification commands; verify the Windows install instructions and desktop AC-36 provenance evidence; record the unresolved global AC-23/AC-36 items and the Android distribution blocker in the checkpoint.

## Tasks

### 3C-01 — Windows release plan — OWNER-REVIEW

- Goal: approve the Windows-only delivery boundary, production updater signing, exact package allowlist, workflow, native install scenarios, and evidence before implementation.
- Files: `docs/gates/gate-3c.md`, `docs/gates/evidence/3b/checkpoint.md`, `docs/gates/evidence/3b/tasks.md`, `docs/STATE.md`.
- Read: `PROJECT.md:180-204,263-308,618-627,630-644,646-684,734-745,778`; Gate 3B checkpoint and Gate 2D updater plan/evidence.
- Dependencies: explicit Gate 3B checkpoint acceptance (received 2026-10-31).
- Acceptance: relative links resolve, V0 passes, Gate 3B acceptance is recorded, the AC-23/AC-36 scope is resolved by the owner, and no source, workflow, dependency, or public contract files change. Stop for owner review before implementation.

### 3C-02 — Production updater signing and Windows release workflow — AUTOMATABLE

- Goal: replace the updater test public key with its production counterpart, build unsigned Windows x64 NSIS and MSI packages, generate bundle-aware `latest.json` and per-package signatures, and prepare the resulting assets for an owner-created draft release.
- Files: focused `src-tauri/tauri.conf.json` and release configuration, `.github/workflows/` release workflow, focused verification scripts and evidence.
- Dependencies: owner acceptance of 3C-01; production updater signing secret provisioned securely; current Tauri updater/bundler documentation consulted through Context7; Windows CI VBSCRIPT support.
- Acceptance: workflow emits only the two approved Windows installers and their updater assets; each target selects the matching package; signatures verify; tampered assets fail verification; signing secrets never enter the repository or logs. Exact verification: V1.

### 3C-03 — Native NSIS/MSI install, upgrade, and uninstall review — AUTOMATABLE

- Goal: prove clean installation and installed updater upgrades for both Windows formats using a prior-version package and the corresponding current-version package.
- Files: focused Windows packaging tests or scripts and `docs/gates/evidence/3c/` install records.
- Dependencies: 3C-02 and its verified packages/metadata.
- Acceptance: isolated native scenarios record clean install, launch, correct version, same-format update, post-update launch/version, and uninstall for both NSIS and MSI. Build the previous-version and candidate packages from controlled source revisions; do not depend on an already-published release. Admin prompts and limitations are recorded. If a format cannot update reliably, evaluate FR-75's direct-link fallback and return to owner review. Exact verification: V2.

### 3C-04 — Install documentation, compliance evidence, and checkpoint — OWNER-REVIEW

- Goal: document Windows downloads and unsigned SmartScreen steps; capture desktop release provenance and native install evidence; map the gate criteria and carry forward unresolved platform-wide release blockers.
- Files: `README.md`, focused `docs/gates/evidence/3c/` records and checkpoint, `docs/STATE.md`.
- Dependencies: 3C-02 and 3C-03.
- Acceptance: V3 passes; checkpoint maps AC-20, AC-22, the Windows portion of AC-23, and the desktop portion of AC-36; no public release is created; remaining global AC-23/AC-36 obligations and Android distribution blocker remain explicit. Stop for owner acceptance before the next stage.

## Stage exit

Gate 3C exits when both approved Windows installer formats have verified production-signed updater artifacts, bundle-correct release metadata, documented install instructions, and recorded clean install, upgrade, and uninstall results. The global multi-platform AC-23/AC-36 criteria and Android distribution blocker remain open until their assigned platform work and provenance requirements are complete. Do not publish a release or start Gate 4A before explicit owner acceptance of the 3C checkpoint.
