# Gate 0A — reproducible foundation

Scope: the empty Tauri 2/React foundation, contract parity, Android skeleton, pinned toolchain, legal templates, CI skeleton and preserved design inventory (`PROJECT.md:751`). No production UI or real download engine. On 2026-10-17 the owner approved running Gate 0A from scratch in this checkout and ruled out restoring a prior checkpoint. Follow the delivery rule at `PROJECT.md:736-745`. The owner's Codex instruction replaces the old `opencode.json` item; do not create that file.

Each item is one roughly 30-minute session on `task-<id>`. Every task also updates `docs/STATE.md` and records command results there. Independent tasks may be delegated only when supported; dependent tasks need their predecessors integrated. Do not start Gate 0B until the owner accepts the Gate 0A checkpoint.

### 0A-01 — Toolchain and OS matrix

- Goal: choose current compatible exact versions and record installation, setup and minimum-OS evidence.
- Files to touch: `docs/toolchain.md`, `docs/STATE.md`.
- Read: `PROJECT.md:196-210,359-390,694-719,747-751`.
- Dependencies: none; independent of 0A-06 and 0A-07.
- Acceptance: exact Tauri/Rust/Node/package-manager/JDK/NDK/SDK versions, source links, setup commands and OS matrix are recorded; no unresolved version placeholders.
- Exact verification command: `rg -n 'Tauri|Rust|Node|package manager|JDK|NDK|SDK|Windows|macOS|Android' docs/toolchain.md` (review each match and version manually).

### 0A-02 — Empty React/Vite frontend

- Goal: create the minimal React/TypeScript/Vite shell and pin the JavaScript dependency tree.
- Files to touch: `package.json`, `package-lock.json`, `index.html`, `tsconfig*.json`, `vite.config.*`, `src/**`, `docs/STATE.md`.
- Read: `PROJECT.md:31-44,363-367,462-471,747-751`.
- Dependencies: 0A-01; independent of 0A-06 and 0A-07.
- Acceptance: `npm run build` runs TypeScript checking and Vite; the blank app passes, with no production UI, Next.js or extra component library.
- Exact verification command: `npm run build`.

### 0A-03 — Tauri/Rust desktop shell

- Goal: add a minimal Tauri 2 shell using the pinned Rust/Tauri versions.
- Files to touch: `src-tauri/Cargo.toml`, `src-tauri/Cargo.lock`, `src-tauri/build.rs`, `src-tauri/tauri.conf.json`, `src-tauri/capabilities/**`, `src-tauri/src/**` except `contract.rs`, `package.json`, `docs/STATE.md`.
- Read: `PROJECT.md:341-347,359-366,383-384,394-416,747-751`.
- Dependencies: 0A-01 and 0A-02; independent of 0A-04, 0A-06 and 0A-07.
- Acceptance: Rust compiles with the existing contract module included; no download engine or production UI.
- Exact verification command: `cargo check --manifest-path src-tauri/Cargo.toml`.

### 0A-04 — Tailwind and Zustand only

- Goal: configure the agreed styling and state libraries in the empty frontend.
- Files to touch: `package.json`, `package-lock.json`, `src/**`, Tailwind/PostCSS config if required, `docs/STATE.md`.
- Read: `PROJECT.md:64-68,363-367,462-471,747-751`.
- Dependencies: 0A-02; independent of 0A-03, 0A-06 and 0A-07. Coordinate `package.json` with 0A-03.
- Acceptance: Tailwind and Zustand resolve, frontend still builds; no third-party component library or production screen.
- Exact verification command: `npm run build` and `npm ls tailwindcss zustand --depth=0`.

### 0A-05 — Contract compile and JSON parity

- Goal: wire the existing TypeScript/Rust contracts into their builds and compare representative serialized fixtures; do not edit contract files, and report conflicts to the owner.
- Files to touch: `shared/fixtures/**`, `src-tauri/tests/**`, contract-check script, `package.json`, `docs/STATE.md`. Read but do not edit `shared/contract.ts` or `src-tauri/src/contract.rs`.
- Read: `PROJECT.md:5-22,383,548-590,747-751`.
- Dependencies: 0A-02 and 0A-03; independent of 0A-06 and 0A-07.
- Acceptance: frontend types and Rust compile; equivalent values serialize to identical camelCase JSON; both contract files remain unchanged, and any conflict is reported to the owner.
- Exact verification command: `npm run check:contracts` and `cargo test --manifest-path src-tauri/Cargo.toml`.

### 0A-06 — Design inventory check

- Goal: preserve the confirmed images and verify every indexed path and stated dimension.
- Files to touch: `docs/design/README.md` only if inventory is wrong, `docs/design/{desktop,mobile}/*.png` for version control only, `scripts/check-design.ps1`, `docs/STATE.md`; do not alter images without owner approval.
- Read: `PROJECT.md:87-95,734-751`.
- Dependencies: none; independent of 0A-01 through 0A-05 and 0A-07.
- Acceptance: all nine indexed images are tracked and exist at their listed dimensions; inventory is preserved and no UI is built.
- Exact verification command: `powershell -NoProfile -File scripts/check-design.ps1`.

### 0A-07 — MIT and third-party notice template

- Goal: add the MIT license and a place to record redistributed engine/source notices later.
- Files to touch: `LICENSE`, `docs/THIRD-PARTY-NOTICES.md`, `docs/STATE.md`.
- Read: `PROJECT.md:359-390,618-629,747-751`.
- Dependencies: none; independent of 0A-01 through 0A-06.
- Acceptance: MIT text is complete; notice template has ffmpeg/QuickJS/yt-dlp source, version, checksum, license and build-configuration fields, without inventing releases.
- Exact verification command: `rg -q 'MIT License' LICENSE` and `rg -q 'ffmpeg' docs/THIRD-PARTY-NOTICES.md`.

### 0A-08 — Android project initialization

- Goal: initialize the Android project with pinned Gradle/JDK/SDK/NDK settings and a debug-build script.
- Files to touch: `src-tauri/gen/android/**`, `src-tauri/tauri.conf.json`, `package.json`, `docs/toolchain.md`, `docs/STATE.md`.
- Read: `PROJECT.md:196-210,341-352,370-373,747-753`.
- Dependencies: 0A-01 and 0A-03; independent of 0A-06 and 0A-07.
- Acceptance: generated project and Gradle wrapper are present, pinned settings match `docs/toolchain.md`, and no Kotlin engine plugin exists yet.
- Time limit: if this task would exceed roughly 30 minutes, stop and propose a split instead of continuing.
- Exact verification command: `rg -n 'distributionUrl|compileSdk|ndkVersion' src-tauri/gen/android` (review values against `docs/toolchain.md`).

### 0A-09 — Android debug-build proof

- Goal: compile the initialized Android skeleton and record the debug APK path and tool versions.
- Files to touch: `src-tauri/gen/android/**` only for build fixes, `package.json`, `docs/toolchain.md`, `docs/STATE.md`.
- Read: `PROJECT.md:196-210,341-352,747-753`.
- Dependencies: 0A-08; independent of 0A-06 and 0A-07.
- Acceptance: debug APK is produced without download-engine or production UI code; fix only foundation issues.
- Time limit: if this task would exceed roughly 30 minutes, stop and propose a split instead of continuing.
- Exact verification command: `npm run android:debug`.

### 0A-10 — CI skeleton and local verification entrypoint

- Goal: make CI repeat frontend build/type-check, Rust/contract tests, design check and Android debug build.
- Files to touch: `.github/workflows/ci.yml`, `package.json`, `scripts/verify-foundation.ps1`, `docs/toolchain.md`, `docs/STATE.md`.
- Read: `PROJECT.md:196-210,359-390,630-645,747-751`.
- Dependencies: 0A-02 through 0A-09; independent tasks may have been done in any order.
- Acceptance: CI pins the recorded versions and runs the same checks as local scripts, with no release/publish step.
- Exact verification command: `powershell -NoProfile -File scripts/verify-foundation.ps1` and `npm run android:debug`.

### 0A-11 — Clean-checkout Windows proof

- Goal: prove a fresh checkout installs locked dependencies and passes the foundation checks on Windows.
- Files to touch: `scripts/verify-clean.ps1`, `docs/toolchain.md`, `docs/STATE.md`.
- Read: `PROJECT.md:196-210,630-645,734-751`.
- Dependencies: 0A-10; independent of 0A-12's hosted-CI evidence once CI is running.
- Acceptance: from a clean clone, `npm ci`, frontend build/type-check, Rust tests and contract/design checks pass; record versions and results.
- Exact verification command: `powershell -NoProfile -File scripts/verify-clean.ps1`.

### 0A-12 — Hosted CI and checkpoint evidence

- Goal: collect CI and Android debug APK evidence and prepare the owner review of Gate 0A.
- Files to touch: `docs/toolchain.md`, `docs/STATE.md`, `docs/gates/gate-0a.md` evidence section only.
- Read: `PROJECT.md:5-22,196-210,630-645,734-753`.
- Dependencies: 0A-10 and 0A-11; no later stage may start before owner acceptance.
- Acceptance: green CI repeats the agreed checks, Android debug APK exists, contract fixtures and design paths pass, all tool versions are recorded; otherwise document the failure and stop.
- Exact verification command: `gh run list --limit 5` (inspect the latest Gate 0A run and record its ID/status; on failure use `gh run view <id> --log-failed | tail -50`).

## Gate exit

Owner reviews the empty app, clean-checkout and CI evidence, Android debug APK, version/OS matrix, contract parity, legal templates and preserved design references. Record explicit acceptance in `docs/STATE.md` before preparing Gate 0B.

## 0A-12 checkpoint evidence (2026-10-18)

| Review item | Evidence |
|---|---|
| Hosted CI | Exact `gh run list --limit 5` reported [main push run 39177425523](https://github.com/zahidzta/zownload_application/actions/runs/39177425523) at merge commit `f51aeb63538da39e6161d26953b33fbff402e7d8` as `completed/success`; `gh run view` showed both `foundation` (Windows 2025) and `android` (Ubuntu 24.04) jobs `completed/success`. |
| Foundation and contracts | The hosted Windows job ran `npm ci` and `scripts/verify-foundation.ps1`, which runs the frontend build/type-check, TypeScript JSON fixture comparison, Rust contract unit and parity tests, and design check. The 0A-11 clean Windows clone independently passed those checks with pinned Node/npm and Rust/Cargo. |
| Android skeleton | The hosted Ubuntu job ran `npm run android:debug` successfully with the recorded JDK/SDK/NDK pins. The local debug APK exists at `src-tauri/gen/android/app/build/outputs/apk/universal/debug/app-universal-debug.apk` (136,162,644 bytes; SHA-256 `11B696468F8B586E5C3EBE48BBB38887210EE619B826879DF5475B8494D7D25A`). Hosted CI does not upload its APK; this file and hash are local build evidence. |
| Versions and OS matrix | Exact Tauri, Rust, Node, npm, Corretto, Android SDK/NDK, Gradle and plugin versions, source links, setup commands, and the selected OS matrix are in `docs/toolchain.md`. |
| Legal and design inventory | `LICENSE` contains MIT text; `docs/THIRD-PARTY-NOTICES.md` provides the engine notice template. The hosted design check passed for all nine indexed, tracked PNG paths and dimensions. No production UI or download engine was added in Gate 0A. |

The evidence meets the Gate 0A technical checks. Owner review and explicit checkpoint acceptance remain pending; do not begin Gate 0B until acceptance is recorded in `docs/STATE.md`.
