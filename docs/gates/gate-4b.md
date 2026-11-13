<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 4B — macOS runtime and packages

## Scope and checkpoint

Gate 4B ports the desktop engine to macOS on Intel x86_64 and Apple Silicon arm64, builds the two confirmed architecture-specific DMGs, enables the Tauri `.app.tar.gz` updater for both architectures, and proves macOS installation, updating, downloads, and process cleanup. A universal binary and other package formats remain out of scope. No public release is authorized by this gate.

Gate 4A was accepted by the owner on 2026-11-12; see the [Gate 4A checkpoint](evidence/4a/checkpoint.md) and [task evidence](evidence/4a/tasks.md). Preserve the validated Windows and Linux assets and updater metadata while adding macOS outputs. Use only an owner-designated unpublished candidate for release-assembly and updater review; do not modify an existing published release or publish a release.

The owner accepted the Gate 4B plan on 2026-11-12. Begin implementation with task 4B-02 in a fresh task session.

Read only these `PROJECT.md` ranges for this gate: `180-195,196-211,263-308,618-629,630-645,664-684,734-745,780-785`. These define the desktop engine/updater behavior, proposed macOS baseline, exact architecture-specific artifact set, Gatekeeper instructions, platform test matrix, release criteria, and owner checkpoint rule.

## Owner review decisions and constraints

1. **Minimum macOS by architecture:** `docs/toolchain.md` currently groups x86_64 and arm64 under macOS 10.15+, while it says arm64 testing starts on macOS 11 hardware. Confirm the supported minimum separately for each architecture before implementation. The plan proposes x86_64 10.15+ and arm64 11+; revise only after owner approval and record exact runner/OS versions and required packages in `docs/toolchain.md`.
2. **Unsigned app distribution:** `PROJECT.md` calls for unsigned Gatekeeper documentation and lists a paid Apple Developer account/notarization as a possible later improvement. Preserve that scope unless the owner explicitly approves the added signing/notarization cost. Record the exact first-launch warning and recovery steps on each approved macOS baseline. Tauri's updater signature is separate from Apple code signing and remains required for updater artifacts. See [Tauri updater artifacts](https://v2.tauri.app/plugin/updater/) and [Tauri macOS bundling](https://v2.tauri.app/distribute/macos/).
3. **Updater candidate:** identify an unpublished lower-version macOS app and a higher-version candidate, both built for each architecture with the existing updater key. Do not infer that the existing Windows/Linux-only draft is a suitable macOS update source. Record the owner-designated candidate and exact version transition before native update tests.
4. **Native test availability:** confirm access to Intel and Apple Silicon hardware or VMs meeting the approved OS baselines. Hosted build runners alone do not satisfy the manual install/update and Gatekeeper review.

Keep the shared contract, approved product behavior, Windows runtime, and Linux runtime unchanged. Use the pinned universal macOS yt-dlp binary, the separately built and pinned QuickJS binaries, and FFmpeg/ffprobe built for each architecture from the locked sources with the approved LGPL-compatible configuration. Verify all engine files before copying them to writable app data, set executable permissions there, and execute only those app-data copies. Do not add dependencies, change public behavior, or build a universal app.

## Verification

Run from the repository root. Build and test each architecture on a matching macOS host/runner. Record exact macOS/Xcode/SDK/runner versions, dependency versions, architecture, package and engine hashes, updater target keys/URLs, Gatekeeper behavior, and native test results. Keep signing secrets in Actions secrets and never log them. No public release is created.

- **V0 (4B-01 plan):** resolve changed relative Markdown links; run `git diff --check` and, after staging, `git diff --cached --check`.
- **V1 (macOS runtime):** run existing contract, frontend, Rust, and formatting checks; verify x86_64 and arm64 engine hashes, executable bits, app-data bootstrap, health checks, app-data-only execution, yt-dlp verification/fallback, child cancellation, and orderly shutdown. Confirm the focused Windows and Linux engine checks still pass.
- **V2 (packages and update metadata):** build only x86_64 and arm64 DMGs plus each matching `.app.tar.gz` updater bundle and `.sig`. Verify the release allowlist preserves all existing Windows/Linux assets and metadata, `latest.json` maps `darwin-x86_64` and `darwin-aarch64` to the matching architecture's updater bundle/signature, tampering is rejected, and no universal or extra package is produced. The candidate remains unpublished.
- **V3 (native review and checkpoint):** on each approved architecture/OS baseline, clean-install its DMG, record the unsigned Gatekeeper first-launch flow, run short MP3 and MP4 downloads plus a tiny playlist, close during active work and confirm all child processes exit and interrupted items restore paused, then update from the recorded lower-version app to the candidate through the signed Tauri updater artifact. Review README install/update instructions, provenance/notices, asset allowlist, and the final checkpoint. Map the macOS portions of AC-20, AC-22, AC-23 and AC-36, plus the desktop engine/runtime criteria in V1.

## Tasks

### 4B-01 — macOS runtime and release plan — ACCEPTED 2026-11-12

- Goal: approve per-architecture macOS minimums, unsigned distribution and Gatekeeper handling, updater candidate/version transition, exact package set, native test availability, and evidence before implementation.
- Files: `docs/gates/gate-4b.md` and `docs/STATE.md`.
- Read: `PROJECT.md:180-195,196-211,263-308,618-629,630-645,664-684,734-745,780-785`; Gate 4A checkpoint and release evidence; the pinned macOS engine source/build records.
- Dependencies: explicit Gate 4A checkpoint acceptance (received 2026-11-12).
- Acceptance: owner approves the complete plan and its four review decisions above; changed relative links resolve; V0 passes; no source, workflow, dependency, or public contract files change. Stop for explicit owner acceptance before implementation.

### 4B-02 — macOS engine paths, sidecars, and process handling — AUTOMATABLE

- Goal: support the pinned macOS engine on x86_64 and arm64; use platform-correct resource names, app-data paths, hashes, and executable permissions; preserve process cancellation and shutdown behavior on both architectures without regressing Windows or Linux.
- Files: focused `src-tauri/src/engine/`, `src-tauri/src/lib.rs`, target-specific Cargo/resource configuration, focused tests, macOS engine build/provenance scripts, and `docs/engine-builds.md`, `docs/engine-sources.md`, `docs/toolchain.md`.
- Read: `PROJECT.md:180-195,263-288,315-340,341-358,618-629,630-645,664-684`; Gate 0B macOS QuickJS evidence and Gate 4A engine records.
- Dependencies: owner acceptance of 4B-01; approved per-architecture OS baseline; consult current Tauri and Rust/platform documentation through Context7 before platform API or bundler code; no public contract changes.
- Acceptance: each architecture's tests cover clean bootstrap, checksums, executable permissions, health probes, app-data-only execution, verified yt-dlp replacement/fallback, cancellation, and process shutdown. Focused Windows/Linux checks continue to pass. Exact verification: V1.

### 4B-03 — macOS DMGs, updater, release workflow, and provenance — AUTOMATABLE

- Goal: build only the two architecture-specific DMGs and signed Tauri `.app.tar.gz` updater artifacts; add both macOS target entries without changing Windows/Linux metadata; record reproducible engine inputs, hashes, LGPL-compatible FFmpeg configuration, sources, and notices.
- Files: focused Tauri bundle configuration, `.github/workflows/` release workflow, macOS engine preparation/build/verification scripts, `docs/engine-builds.md`, `docs/engine-sources.md`, `docs/toolchain.md`, README install/update instructions, and `docs/gates/evidence/4b/`.
- Read: `PROJECT.md:200-211,289-308,618-629,630-645,664-684,780-785`; Gate 3C and Gate 4A release workflow/provenance records; current Tauri updater and macOS bundle documentation.
- Dependencies: 4B-02; owner-designated unpublished candidate and version transition; existing updater signing key available only through Actions secrets. Apple code signing/notarization remains out of scope unless the owner changes the approved plan.
- Acceptance: CI emits only the two DMGs and their supported updater bundles/signatures; the full allowlist retains verified Windows/Linux assets; `latest.json` maps both macOS architectures correctly; tampering fails verification; no secret is logged or committed; exact source/build inputs and notices cover each macOS engine binary. Exact verification: V2.

### 4B-04 — Native install/update review, documentation, and checkpoint — OWNER-REVIEW

- Goal: prove macOS single/playlist downloads, clean installation, Gatekeeper instructions, updater behavior on each architecture, and process cleanup; record evidence and open cross-platform obligations.
- Files: `README.md`, focused macOS verification fixes, `docs/gates/evidence/4b/`, and `docs/STATE.md`.
- Read: `PROJECT.md:196-211,289-308,630-645,664-684,734-745,780-785`; approved 4B plan and 4B-02/03 evidence.
- Dependencies: 4B-02 and 4B-03; owner-provided Intel and Apple Silicon native/virtual test environments; approved lower/higher version candidate pair.
- Acceptance: V3 passes on both architectures; checkpoint maps the macOS portions of AC-20, AC-22, AC-23 and AC-36 and records any attested evidence limits; Windows/Linux remain unchanged; no public release is created. Stop for explicit owner acceptance before Gate 5A.

## Stage exit

Gate 4B exits when x86_64 and arm64 engines run only from verified app-data copies, both architecture-specific DMGs install and pass download smoke tests on the approved OS matrix, both updater paths and Gatekeeper instructions are proven, macOS provenance/notices are recorded, and the unpublished candidate has exactly the allowed Windows/Linux/macOS assets. A failed criterion stays in 4B. Do not start Gate 5A until the owner explicitly accepts the Gate 4B checkpoint.
