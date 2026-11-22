<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 5A — Android production engine

## Scope and checkpoint

Gate 5A delivers the production Android engine provider, Kotlin engine adapter, and Rust `AndroidEngine`, then proves contract-compatible single and playlist downloads on a physical `arm64-v8a` device. Rust remains the queue owner and source of truth. Kotlin provides the engine bridge and callbacks; it does not add queue or business rules.

Gate 4B was accepted on 2026-11-22; see [its checkpoint](evidence/4b/checkpoint.md). Gate 5A is authorized by that checkpoint. **The owner accepted this plan and its budget checkpoint on 2026-11-22.** The owner also approved the CPython source-build and JNI packaging path under 5A-02; runtime integration begins in 5A-03.

Read only these `PROJECT.md` ranges for this gate: `180-195,341-358,368-393,394-461,555-597,618-645,646-693,787-793`. These define Android engine/lifecycle behavior, platform constraints, the selected Android ownership model, the engine boundary, API contract, security/licensing, tests, Android acceptance criteria, and the Phase 5A deliverable.

### Android binary release blocker

The current `youtubedl-android` `0.18.1` `library`, `ffmpeg`, and transitive `common` artifacts do not have established corresponding source, exact build inputs, and notices. The 0C-04A waiver covers local feasibility only. See the [package audit](evidence/0c/engine-package.md) and [owner architecture decision](evidence/0c/architecture-decision.md).

Before production-engine integration, replace those opaque native binaries with a pinned, traceable `arm64-v8a` Python runtime carrying pinned yt-dlp/ejs, the pinned Android QuickJS build, and minimal pinned FFmpeg/ffprobe without x264 or x265. Preserve the existing Kotlin package-provider boundary so binary versions, paths, and FFmpeg configuration stay out of the engine adapter. Keep the selected Android/GPL licensing posture from `PROJECT.md`; inventory every native and packaged dependency, its licence, notice, source, patches, and reproducible build inputs. Any change to the approved licensing or engine architecture requires an owner decision.

**Hard stop:** no Android APK/build may be published, uploaded, attached to a release, or shared with anyone until corresponding source, build inputs, and notices are established and the transitive dependency audit is complete. Local-only APKs may be used for owner-device tests. This gate does not authorize an Android release; Gate 5C owns release packaging.

The previous Gate 0C architecture estimate for an owned Android engine was about 20–35 work sessions. Gate 5A may use the existing adapter around newly traceable binaries, but the Python packaging path is not yet selected. The owner must review the expected effort and approve the Python runtime/package strategy before that strategy is implemented. If the source/build work exceeds the owner's budget, stop and ask whether to review the desktop-only first-release fallback recorded in `docs/STATE.md`.

### Scope boundaries

- Use the already validated Gate 0C Android bridge and output path for Gate 5A engine tests. Gate 5B owns production MediaStore/ZIP behavior, foreground-service changes, Home/recents/process-death handling, and timeout/recovery release tests.
- Keep `shared/contract.ts`, `src-tauri/src/contract.rs`, public command/event payloads, queue semantics, UI behavior, and desktop engines unchanged.
- Run Android builds and device tests locally only while the distribution blocker remains open. Do not attach APKs or build outputs to commits or PRs.

## Verification

All `scripts/gate-5a/verify.ps1` cases below are planned entrypoints to add with their owning task. They must print concise results (or a failure tail of at most 50 lines); keep full build logs and APKs under ignored `work/android/`.

- **V0 (5A-01 plan):** resolve changed relative Markdown links; run `git diff --check` and, after staging, `git diff --cached --check`.
- **V1 (5A-02..05 runtime inputs):** verify locked source URLs/commits and SHA-256 values, Python/yt-dlp/ejs compatibility, QuickJS version, FFmpeg configure flags, `arm64-v8a` ELF dependencies, and required MP3/MP4/YouTube-JS smoke behavior. Commands: `powershell -NoProfile -File scripts/gate-5a/verify.ps1 -Case python-runtime`, `-Case ffmpeg`, and `-Case quickjs`.
- **V2 (5A-06 package/provenance):** run `npm run android:debug`; verify the APK contains only the intended `arm64-v8a` native engine files, each packaged hash matches the source-build manifest, no `0.18.1` AAR/native payload remains, and corresponding sources/build materials/notices cover every shipped dependency. Command: `powershell -NoProfile -File scripts/gate-5a/verify.ps1 -Case package-provenance`.
- **V3 (5A-07..08 adapter/contract):** run `npm run check:contracts`, `cargo test --manifest-path src-tauri/Cargo.toml`, and the focused Android bridge verifier. Cover analysis, one-entry download, progress, cancellation, typed errors, update methods, and unchanged contract parity.
- **V4 (5A-09 device/checkpoint):** on a physical `arm64-v8a` device, prove a YouTube single MP3 with QuickJS/ejs, a single MP4, and a playlist through the existing Gate 0C path; verify queue/history/settings integration, progress, cancellation, and no Kotlin-owned queue. Record device/API/ABI, fixture provenance, hashes, output inspection, and limits in `docs/gates/evidence/5a/`. Command: `powershell -NoProfile -File scripts/gate-5a/verify.ps1 -Case device-engine`.

## Tasks

Each task is one roughly 30-minute session, on its own `task-<id>` branch, with a work commit, a separate `docs/STATE.md` commit, and a PR. Long builds and device waits may extend elapsed time. Do not start a dependent task before its prerequisite and owner decisions pass.

### 5A-01 — Plan and owner checkpoint — ACCEPTED 2026-11-22

- Goal: agree on the gate boundary, binary-provenance hard stop, Python packaging decision, and effort checkpoint before implementation.
- Files to touch: `docs/gates/gate-5a.md`, `docs/STATE.md`.
- Read: `PROJECT.md:180-195,341-358,368-393,394-461,555-597,618-645,646-693,787-793`; `docs/STATE.md`; Gate 4B checkpoint; Gate 0C package audit and architecture decision.
- Dependencies: Gate 4B acceptance (received 2026-11-22). No implementation may begin until the owner accepts this plan.
- Acceptance: owner accepted the plan and budget checkpoint on 2026-11-22. Changed relative links resolve; V0 passes. No source, workflow, dependency, binary, or public contract files change.
- Exact verification command: `git diff --check`.

### 5A-02 — Select and pin the Android Python packaging path — ACCEPTED 2026-11-22

- Goal: compare feasible traceable Python runtime/package approaches against the current `AndroidEnginePackage` boundary; lock one owner-approved approach, exact Python source/version, patches, build tools, dependencies, yt-dlp `2026.08.19`, and ejs `0.8.0`. Do not add a runtime framework or major dependency before owner approval.
- Files to touch: `docs/engine-sources.md`, `docs/engine-builds.md`, `docs/toolchain.md`, `docs/gates/evidence/5a/python-runtime-decision.md`, `scripts/gate-5a/verify.ps1`, `docs/STATE.md`, and this gate's task status.
- Read: `PROJECT.md:370-374,388,394-461,618-629,630-645,787-793`; `docs/engine-sources.md`; `docs/engine-builds.md`; Gate 0C package audit and architecture decision.
- Dependencies: 5A-01 accepted; owner approved CPython on 2026-11-22. Runtime build integration remains in 5A-03. Independent of 5A-04 and 5A-05 after the shared source lock format is agreed.
- Acceptance: CPython `3.14.10`, all six native source dependencies and recipes, the Python package sources, yt-dlp, EJS, QuickJS, licenses, patches, and build tools are pinned; the owner decision records the package boundary, size estimate, prerequisites, and fallback. The exact verifier passed; no opaque binary is treated as source evidence.
- Exact verification command: `powershell -NoProfile -File scripts/gate-5a/verify.ps1 -Case python-source-lock`.

### 5A-03 — Build the traceable Python and yt-dlp runtime

- Goal: reproducibly package the approved arm64 Python runtime with pinned yt-dlp/ejs and notices; keep the Kotlin provider interface independent of paths and versions.
- Files to touch: focused `scripts/gate-5a/` build scripts, Android packaging configuration, `docs/engine-sources.md`, `docs/engine-builds.md`, `docs/toolchain.md`, `docs/THIRD-PARTY-NOTICES.md`, and `docs/gates/evidence/5a/`.
- Read: `PROJECT.md:348-349,370-374,388,394-461,618-629,630-645,787-793`; the accepted 5A-02 decision.
- Dependencies: 5A-02 owner-approved source/package lock.
- Acceptance: clean build from pinned sources emits only required arm64 runtime files; yt-dlp/ejs versions and hashes match the lock; source archives, patches, build inputs, and notices are captured. No adapter or Rust behavior changes.
- Exact verification command: `powershell -NoProfile -File scripts/gate-5a/verify.ps1 -Case python-runtime`.

### 5A-04 — Build minimal Android FFmpeg and ffprobe

- Goal: build pinned arm64 FFmpeg/ffprobe from corresponding source with only the features needed for MP3/MP4 download processing; exclude x264/x265 and record the selected GPL configuration and every transitive native dependency.
- Files to touch: focused `scripts/gate-5a/` build scripts, `docs/engine-sources.md`, `docs/engine-builds.md`, `docs/toolchain.md`, `docs/THIRD-PARTY-NOTICES.md`, and `docs/gates/evidence/5a/`.
- Read: `PROJECT.md:368-370,388,618-629,630-645,664-684,787-793`; relevant Gate 0B and 4A/4B engine build records.
- Dependencies: 5A-01 accepted; may run independently of 5A-02/03. Any change from the confirmed Android GPL posture stops for owner review.
- Acceptance: source and all dependency versions/hashes are pinned; exact configure/link commands are reproducible; neither configure output nor dependency inventory includes x264/x265; `ffmpeg` and `ffprobe` pass required MP3/MP4 probes; notices and corresponding sources are recorded.
- Exact verification command: `powershell -NoProfile -File scripts/gate-5a/verify.ps1 -Case ffmpeg`.

### 5A-05 — Build and pin Android QuickJS

- Goal: package the upstream QuickJS `2026-06-04` arm64 build with its source, checksum, build inputs, and notices; confirm it pairs with the locked yt-dlp/ejs runtime.
- Files to touch: focused `scripts/gate-5a/` integration or reuse of `scripts/gate-0c/package-quickjs.ps1`, `docs/engine-sources.md`, `docs/engine-builds.md`, `docs/toolchain.md`, `docs/THIRD-PARTY-NOTICES.md`, and `docs/gates/evidence/5a/`.
- Read: `PROJECT.md:370-374,618-629,630-645,687-693,787-793`; Gate 0B QuickJS source/build evidence; accepted 5A-02 source lock.
- Dependencies: 5A-01 accepted; may run independently of 5A-03/04.
- Acceptance: the APK-bound runtime has the pinned version and expected arm64 ELF dependencies; a YouTube JS challenge fixture succeeds on device once the adapter is wired; source/build/notices are included.
- Exact verification command: `powershell -NoProfile -File scripts/gate-5a/verify.ps1 -Case quickjs`.

### 5A-06 — Replace opaque Android payloads and close provenance audit

- Goal: stage the approved runtime outputs, remove the `0.18.1` Maven AAR payloads, produce a machine-checked APK engine manifest, and complete the transitive licence/source/notice audit before production adapter integration.
- Files to touch: `src-tauri/gen/android/app/build.gradle.kts`, focused Android package configuration, focused `scripts/gate-5a/`, `docs/engine-sources.md`, `docs/engine-builds.md`, `docs/toolchain.md`, `docs/THIRD-PARTY-NOTICES.md`, and `docs/gates/evidence/5a/`.
- Read: `PROJECT.md:348-349,370-374,388,618-629,630-645,684,787-793`; Gate 0C package audit; 5A-02..05 evidence.
- Dependencies: 5A-03, 5A-04, and 5A-05. This task is the release-blocker exit check; failure stops the gate before engine integration.
- Acceptance: `npm run android:debug` packages only the approved traceable arm64 payload; APK hashes match the source-build manifest; there are no `0.18.1` engine AARs/native payloads; exact corresponding sources/build materials/notices and full transitive inventory are reviewable. Android APK/build sharing remains prohibited until owner review records blocker closure.
- Exact verification command: `powershell -NoProfile -File scripts/gate-5a/verify.ps1 -Case package-provenance`.

### 5A-07 — Wire the Kotlin engine provider and Tauri plugin

- Goal: implement production `analyze`, one-entry download, progress, cancel, and engine-update methods over the approved package provider; map callback/error data through the existing typed Rust bridge without Kotlin queue state.
- Files to touch: `src-tauri/gen/android/app/src/main/java/com/zownload/app/AndroidEngineAdapter.kt`, the focused Kotlin package provider/plugin files, focused Android bridge tests, and `docs/gates/evidence/5a/`.
- Read: `PROJECT.md:370-374,394-461,555-597,618-645,687-693,787-793`; the approved 5A-06 package manifest; current Tauri mobile-plugin documentation through Context7 before code changes.
- Dependencies: 5A-06; no new library or framework without owner approval.
- Acceptance: provider uses manifest-verified package inputs without embedding their versions, paths, or FFmpeg flags in adapter logic; cancellation and progress cross the bridge once; failures remain typed; Kotlin owns no queue/history/settings behavior.
- Exact verification command: `powershell -NoProfile -File scripts/gate-5a/verify.ps1 -Case kotlin-engine`.

### 5A-08 — Implement Rust `AndroidEngine` and contract integration

- Goal: implement the Android side of the existing Rust `Engine` boundary and wire it into the shared queue, history, settings, and commands while preserving the public contract and desktop implementations.
- Files to touch: focused `src-tauri/src/engine/`, `src-tauri/src/lib.rs`, Android bridge tests, and `docs/gates/evidence/5a/`.
- Read: `PROJECT.md:180-195,394-461,555-597,618-645,646-693,787-793`; accepted Kotlin bridge evidence; consult current Rust/Tauri API documentation through Context7 before code changes.
- Dependencies: 5A-07; no edits to `shared/contract.ts` or `src-tauri/src/contract.rs` unless an owner-approved requirement change is made.
- Acceptance: Rust owns all queue state and persistence; existing command/event names and payloads remain identical; tests cover bridge results, progress, cancellation, typed failures, engine update calls, and desktop regression.
- Exact verification command: `powershell -NoProfile -File scripts/gate-5a/verify.ps1 -Case rust-engine`.

### 5A-09 — Device proof and Gate 5A checkpoint

- Goal: prove production-engine behavior on a physical arm64 device through the existing Gate 0C path, record evidence and limitations, and request the owner's Gate 5A checkpoint acceptance.
- Files to touch: focused fixes from the device run, `docs/gates/evidence/5a/`, `docs/STATE.md`.
- Read: `PROJECT.md:180-195,394-461,555-597,630-645,646-693,787-793`; accepted 5A-02..08 evidence and the Gate 0C checkpoint limits.
- Dependencies: 5A-08; owner-provided physical `arm64-v8a` test device and rights-cleared YouTube/playlist fixtures. Keep Android 5B lifecycle/storage acceptance out of this task.
- Acceptance: V4 passes for single MP3, single MP4, and playlist downloads; UI recreation uses the shared queue state; queue/history/settings behavior is correct; no new contract fields are needed; evidence states exact device, fixture, binary hashes, test outcomes, and limits. Owner explicitly accepts the checkpoint before 5B begins.
- Exact verification command: `powershell -NoProfile -File scripts/gate-5a/verify.ps1 -Case device-engine`.

## Delivery

Commit each verified task, update and commit `docs/STATE.md`, and open a PR on its `task-<id>` branch. Do not publish Android artifacts. After V4, request explicit owner acceptance of the Gate 5A checkpoint. Stop before Gate 5B until that acceptance is recorded.
