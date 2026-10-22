# Zownload state

- **Current checkpoint (2026-10-21):** The owner accepted Gate 0C for **LOCAL TECHNICAL FEASIBILITY ONLY**. AC-30..35 evidence on two physical arm64 devices, probe limits, and custom update/rollback are in the [Gate 0C checkpoint](gates/evidence/0c/checkpoint.md). Gate 0A was accepted on 2026-10-18 and Gate 0B on 2026-10-20.
- **Current work:** Phase 1 setup plan is in the [Gate 1A task plan](gates/gate-1a.md) and [1B/1C outline](gates/phase-1-outline.md). The owner authorized 1A-02 execution on 2026-10-22; 1A-03 is complete on its task branch.
- **Completed 1A-02:** Added typed English/Spanish shell catalogs, translations for all nine contract `ErrorCode` values, and a lookup with English fallback. The exact Gate 1A verification command passed (`npm run build` and four `node:test` cases); no dependencies or contracts changed. Implementation commit: `f3c30b9`.
- **Completed 1A-03:** Added the app-owned `Commands`/`Events` transport interface, one Tauri adapter, and a Tauri-free injection entry for the later in-memory simulator. The Gate 0C spike remains intact. The exact Gate 1A verification command passed (`npm run build`, `npm run check:contracts`, and three `node:test` cases); no dependencies or contracts changed. Implementation commit: `13c8eac`.
- **Next task: 1A-04 — Semantic shell primitives.** Start it in a fresh session on `task-1a-04`, after integrating the 1A-03 PR. Follow the 1A-04 scope and verification command in [Gate 1A](gates/gate-1a.md).
- **1A decisions before dependent UI work:** `PROJECT.md` requires Queue/History on the desktop left and a settings button after language; indexed desktop images place Queue/History on the right and indexed main images omit settings. Settings, populated History, error notifications, mobile analysis, and several state variants lack an indexed design. See Gate 1A's decision register. No layout/design choice has been made.
- **1B/1C planning question:** interactive component tests would add Vitest, Testing Library, and a DOM test environment to `package.json`; owner approval is required before adding those dependencies. Gate 1A uses existing Node/Vite/React tools for focused checks.
- **Open MP3 product behavior:** Gate 0B showed yt-dlp leaves an already-MP3 128 kbps source at 128 kbps even when 320 kbps is requested ([single evidence](gates/evidence/0b/mp3-singles.txt), [playlist evidence](gates/evidence/0b/mp3-playlist.txt)). Whether requested bitrate less than or equal to an MP3 source should also force re-encoding remains an owner decision; Phase 1 must not silently choose a rule.

## RELEASE BLOCKER — Android distribution

- Native corresponding-source, exact build inputs, and third-party notices for the youtubedl-android `0.18.1` `library`, `ffmpeg`, and `common` binaries are **not established**. The 0C-04A waiver covers local feasibility only. **No Android APK or Android build is published, uploaded, attached to a release, or shared with anyone until this gap is resolved.**
- **FIRST task block of Phase 5, before the production Android engine:** replace the third-party native binaries with traceable minimal pinned arm64 FFmpeg and ffprobe without x264/x265, pinned QuickJS, and a Python runtime with yt-dlp from a traceable source; supply corresponding source, build inputs, and notices. If this exceeds the owner's budget, the fallback for owner review is a **desktop-only first release**. That fallback does not clear the Android blocker.
- **Other release items OPEN:** legal review before the first public release; full transitive dependency licence audit; release APK size measurement after binary replacement.

## Deferred Android follow-ups

- Recheck the [classified CI and deprecation warnings](gates/evidence/0c/ci-warnings.md) when Tauri or the Android Gradle Plugin is updated; replace the deprecated notification builder fallback in the production foreground service.
- Check WebView Back-button and predictive-back behavior on a physical device with `targetSdk 36`; the current `WryActivity.kt` is Tauri/wry-generated.
- Keep the Kotlin adapter independent of bundled binary paths, versions, and FFmpeg configuration so the Phase 5 replacement does not require an adapter rewrite.

## Evidence and standing decisions

- Gate evidence: [0A](gates/gate-0a.md), [0B](gates/evidence/0b/checkpoint.md), [0C](gates/evidence/0c/checkpoint.md); exact toolchain setup and checks: [toolchain](toolchain.md). Per-task probe details and limits live under `docs/gates/evidence/`.
- Owner-selected Option A is youtubedl-android with repository licence GPL-3.0-or-later; see the [decision memo](gates/evidence/0c/architecture-decision.md). Legal review remains open.
- Contract files govern exchanged fields and types; `PROJECT.md` governs behavior; confirmed images indexed by `docs/design/README.md` govern visuals. One task per session, with its own branch, verification, commits, and PR.
