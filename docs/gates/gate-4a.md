<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 4A — Linux runtime and packages

## Scope and checkpoint

Gate 4A ports the desktop engine to Linux x86_64, adds executable Linux sidecars and Linux-specific paths, and prepares the two confirmed v1 packages: AppImage and Debian `.deb`. It proves Linux download, installation, and update behavior without publishing a release. Linux ARM, RPM, Flatpak, Snap, and other formats remain out of scope.

Gate 3C was accepted by the owner on 2026-11-02; see the [Gate 3C checkpoint](evidence/3c/checkpoint.md) and [task evidence](evidence/3c/tasks.md). The owner-created `app-v0.0.1` draft remains unpublished and already contains the verified Windows assets. Gate 4A must preserve those assets while adding and validating Linux outputs.

Read only these `PROJECT.md` ranges for this gate: `180-195,196-211,263-308,618-629,630-645,664-684,734-745,780-785`. These define the desktop engine and updater behavior, defer the Linux support baseline to this gate, identify exact release formats and distro tests, and require an accepted checkpoint before Gate 4B.

Keep the shared contract and Windows behavior unchanged. Use the already locked Linux x64 yt-dlp release and QuickJS source/build; build Linux FFmpeg/ffprobe from the pinned corresponding sources with the approved LGPL-compatible configuration. Verify all engine files before copying them to writable app data, set executable permissions, and execute only those app-data copies. Do not add package formats, change public behavior, or publish a release.

## Owner-approved decisions and risks to verify

1. **Linux support baseline (owner-approved 2026-11-02; Fedora target updated 2026-11-06):** declare Ubuntu 24.04 LTS as the minimum; test AppImage on Ubuntu 24.04 with and without `libfuse2` and on Fedora Workstation 45 x86_64. The owner approved replacing the planned Fedora 44 target with Fedora 45. Test `.deb` on Debian stable and Ubuntu LTS. Pin exact distro releases and required WebKitGTK/runtime packages in `docs/toolchain.md` and the checkpoint.
2. **`.deb` application updates (owner-approved 2026-11-02):** use the FR-75 direct-download fallback for `.deb`; show “New version available” with a link to the matching `.deb` release asset and verify the user can install it with the expected administrator prompt. Keep the Tauri updater for AppImage. The current Tauri v2 documentation retrieved through Context7 documents the AppImage updater artifact and signature, while its manifest describes a generic `linux-x86_64` key; it does not establish package-specific `.deb` updater selection. See the [Tauri updater documentation](https://v2.tauri.app/plugin/updater/) and [Debian bundling documentation](https://v2.tauri.app/distribute/debian/). Confirm runtime package detection and link selection are reliable; if not, return for owner review rather than sending a `.deb` installation an AppImage.
3. **Release assembly:** the existing Windows workflow requires an empty draft and checks a Windows-only allowlist. Gate 4A must adapt the owner-triggered workflow so the existing Windows assets and new Linux assets are validated together, and `latest.json` is updated without losing the Windows entries. Keep platform signing secrets in Actions secrets and preserve the unpublished draft boundary.

## Verification

Run from the repository root. Use disposable Linux VMs or CI runners for package tests; record exact distro versions, WebKitGTK/runtime packages, FUSE presence, package hashes, engine hashes, and observed updater behavior. Do not install over an owner's system or publish the draft.

- **V0 (4A-01 plan):** resolve changed relative Markdown links; run `git diff --check` and, after staging, `git diff --cached --check`.
- **V1 (Linux runtime):** run the existing contract, frontend, Rust, and formatting checks on Ubuntu 24.04; verify Linux x86_64 engine hashes, executable bits, app-data bootstrap, health checks, update verification, fallback, process cleanup, and that no engine process runs from the installation resources.
- **V2 (packages and release metadata):** build only Linux x86_64 AppImage and `.deb` plus the AppImage updater artifacts. Verify the combined Windows/Linux allowlist in the owner-created draft, preserve Windows metadata, ensure the AppImage target/signature is correct, and ensure the `.deb` direct link resolves to the `.deb` asset rather than AppImage. Also verify tamper rejection, package dependencies, and unchanged Windows entries. The draft remains unpublished.
- **V3 (native smoke tests and checkpoint):** run a short single MP3 and MP4 plus a tiny playlist on Ubuntu 24.04 and Fedora Workstation 45 using AppImage; include Ubuntu with and without `libfuse2`. Clean-install and update the AppImage on the supported matrix. Clean-install `.deb` on Debian stable and Ubuntu LTS; verify update discovery opens the matching `.deb` release asset and complete the update with the expected administrator prompt. Recheck download behavior, shutdown/process cleanup, install documentation, provenance/notices, and the final artifact allowlist. Map AC-20, AC-22, the Linux portion of AC-23, AC-24/25/27/28/29, and the Linux desktop portion of AC-36.

## Tasks

### 4A-01 — Linux runtime and release plan — OWNER-REVIEW

- Goal: approve the Linux distribution baseline, runtime boundaries, exact package set, updater behavior, release assembly, native test matrix, and evidence before implementation.
- Files: `docs/gates/gate-4a.md`, `docs/gates/evidence/3c/checkpoint.md`, `docs/gates/evidence/3c/tasks.md`, `docs/STATE.md`.
- Read: `PROJECT.md:180-195,196-211,263-308,618-629,630-645,664-684,734-745,780-785`; Gate 3C checkpoint and release evidence.
- Dependencies: explicit Gate 3C checkpoint acceptance (received 2026-11-02).
- Acceptance: owner-approved support baseline and `.deb` fallback are recorded; relative links resolve; V0 passes; Gate 3C acceptance is recorded; no source, workflow, dependency, or public contract files change. Stop for explicit owner acceptance of the complete plan before implementation.

### 4A-02 — Linux engine paths, sidecars, and process handling — AUTOMATABLE

- Goal: compile the existing desktop engine on Linux x86_64; use platform-correct filenames and paths; bundle pinned yt-dlp, QuickJS, FFmpeg, and ffprobe; set execute permissions during bootstrap; keep only verified app-data copies executable; support Linux child cancellation and orderly app shutdown without regressing Windows.
- Files: focused `src-tauri/src/engine/`, `src-tauri/src/lib.rs`, target-specific Cargo configuration, Linux resource configuration, focused tests, and Linux engine build/provenance scripts.
- Read: `PROJECT.md:180-195,263-288,315-340,341-358,618-629,630-645,664-671`.
- Dependencies: owner acceptance of 4A-01; approved distro baseline; consult current Tauri and Rust/platform documentation through Context7 before platform API or bundler code; no public contract changes.
- Acceptance: Linux tests cover clean bootstrap, checksums, execute bits, health probes, app-data-only execution, verified yt-dlp replacement and rollback, interrupted/cancelled child cleanup, and process shutdown. The same focused Windows engine checks continue to pass. Exact verification: V1.

### 4A-03 — Linux yt-dlp and app-update behavior — AUTOMATABLE

- Goal: select the official Linux x64 yt-dlp asset and checksum, preserve the existing verified update/probation/fallback flow, enable the Tauri updater on Linux, and implement automatic AppImage updates plus the owner-approved direct `.deb` download link.
- Files: focused `src-tauri/src/engine/updater.rs`, desktop setup/plugin configuration, focused Rust tests and update fixtures.
- Read: `PROJECT.md:180-195,263-288,618-629,664-671`.
- Dependencies: 4A-01 and 4A-02; `.deb` selection feasibility and owner decision recorded before implementation; use the existing signing key/public key pairing.
- Acceptance: automatic yt-dlp checks use only the official Linux asset and matching checksum; invalid assets never replace the active copy; baseline fallback runs from app data; AppImage receives the matching signed update; `.deb` update discovery opens the matching `.deb` asset and never an AppImage. Exact verification: V1 and V3.

### 4A-04 — Linux packages, release workflow, and provenance — AUTOMATABLE

- Goal: build only the x86_64 AppImage and `.deb`, generate supported signatures/metadata, merge Linux metadata with the existing Windows entries, and validate the complete unpublished desktop draft allowlist. Record reproducible Linux engine inputs, hashes, LGPL-compatible FFmpeg configuration, source links, and notices.
- Files: focused Tauri bundler configuration, `.github/workflows/` release workflow, Linux engine preparation/build/verification scripts, `docs/engine-builds.md`, `docs/engine-sources.md`, `docs/toolchain.md`, and `docs/gates/evidence/4a/`.
- Read: `PROJECT.md:200-211,289-308,618-629,646-684,780-784`; Gate 3C release workflow and provenance records.
- Dependencies: 4A-02 and 4A-03; owner-controlled unpublished draft; production signing secret already provisioned securely.
- Acceptance: CI emits only the two Linux packages and supported updater files; the complete allowlist contains the verified Windows and Linux outputs; metadata maps each supported installer correctly; tampering fails verification; no signing secret is logged or committed; source and notices map every Linux engine binary to exact inputs and build commands. Exact verification: V2.

### 4A-05 — Native install/update review, documentation, and checkpoint — OWNER-REVIEW

- Goal: prove Linux single/playlist downloads and clean install/update behavior on the approved matrix; document AppImage FUSE guidance and `.deb` install/update steps; record release provenance and remaining cross-platform obligations.
- Files: `README.md`, focused Linux verification fixes, `docs/gates/evidence/4a/`, and `docs/STATE.md`.
- Read: `PROJECT.md:196-211,289-308,630-645,664-684,734-745,780-785`.
- Dependencies: 4A-02 through 4A-04.
- Acceptance: V3 passes; checkpoint maps Linux portions of AC-20, AC-22, AC-23, and AC-36 and the engine/runtime criteria listed in V3; remaining global AC-23/AC-36 and Android release blocker remain explicit; no public release is created. Stop for explicit owner acceptance before Gate 4B.

## Stage exit

Gate 4A exits when Linux x86_64 engine files run from verified app-data copies with correct execute permissions, AppImage and `.deb` install and download smoke tests pass on the owner-approved distro matrix, supported update behavior is proven, Linux provenance/notices are recorded, and the unpublished desktop draft contains exactly the allowed Windows and Linux assets. A failed criterion stays in 4A. Do not start Gate 4B until the owner explicitly accepts the Gate 4A checkpoint.
