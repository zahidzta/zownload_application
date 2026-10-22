# Zownload state

- **Current checkpoint (2026-10-21):** The owner accepted Gate 0C for **LOCAL TECHNICAL FEASIBILITY ONLY**. AC-30..35 evidence on two physical arm64 devices, probe limits, and custom update/rollback are in the [Gate 0C checkpoint](gates/evidence/0c/checkpoint.md). Gate 0A was accepted on 2026-10-18 and Gate 0B on 2026-10-20.
- **Current work:** Phase 1 planning only. **Next task: 1A-01 — Stage 1A app-shell task plan**, in a fresh session on `task-1a-01`. Phase 1 execution is not authorized by this checkpoint.

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
