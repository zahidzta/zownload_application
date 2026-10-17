# PROJECT.md line map

Ranges are inclusive and refer to the current 827-line `PROJECT.md`. Read the ranges for the active task only. Recheck this map if that file changes.

## Essentials (15 lines)

1. Objective: paste a URL to download MP3 or MP4 from yt-dlp-supported sites; a playlist URL downloads the whole playlist (`35`).
2. Targets: Windows, macOS, Linux, Android; iOS excluded (`37`).
3. Stack: Tauri 2, React, TypeScript, Vite, Rust (`363-369`).
4. UI stack: Tailwind CSS only, handcrafted components, Zustand; no Next.js or shadcn/ui (`365-367,470-471`).
5. Engine: yt-dlp, LGPL-compatible ffmpeg, upstream QuickJS 2026-06-04 (`368,370,388`).
6. Android engine is local through a Kotlin Tauri plugin; no server (`42,372-374`).
7. One monorepo with shared code and contract files (`41,383`).
8. Distribution is through GitHub Releases only; no app stores (`43,61-62`).
9. Development order is Windows, Linux/macOS, Android, with an early Android feasibility spike (`44,384`).
10. One user install artifact must need no terminal or extra dependency download (`200`).
11. v1 is MP3/MP4, sequential playlists, optional ZIP, queue, history, metadata, two UI languages (`52-59`).
12. Desktop executes engine copies in app data; Android saves to MediaStore Downloads (`184,349`).
13. Gate 0A is a reproducible empty foundation; do not implement production UI there (`751`).
14. Each stage needs tests, manual evidence where applicable, review, and explicit owner acceptance (`736-745`).
15. Authority: contract files for fields/types; `PROJECT.md` for behavior; indexed design images for visuals. Report conflicts (`22`).

## Sections

| Section | Lines | Contents |
|---|---:|---|
| Preface | 1-4 | Title and an old repository-status summary; compare with section 0 and `docs/STATE.md`. |
| 0. How to read | 5-30 | Status tags, claimed gate state, authority, owner profile and old OpenCode guidance. |
| 1. Overview | 31-45 | Product objective, target platforms, key constraints and development order. |
| 2. Problem | 46-49 | Why a bundled, simple downloader is needed. |
| 3. Scope | 50-69 | In-scope features, exclusions and proposed v1 limits. |
| 4. Features | 70-86 | F1-F12 feature list. |
| 4. Design references | 87-95 | Confirmed image authority, missing-screen freedom and Gate 0A inventory limit. |
| 5. Functional requirements | 96-195 | FR requirements; use the narrower rows below. |
| 5. Header/layout/input | 98-120 | Header, desktop/mobile layout, URL entry and analysis errors. |
| 5. Download state | 121-131 | Single/playlist preview, quality selection and cleared Input after enqueue. |
| 5. Queue/history | 132-155 | Progress, pause/delete, transient terminal states, history/redownload. |
| 5. Download behavior | 156-168 | Sequential/ZIP output, storage, collision, metadata and disk error rules. |
| 5. Settings | 169-179 | Language, ZIP, folder, updates, SQLite persistence and i18n. |
| 5. Engine and updates | 180-195 | Bundled engine, updater, Android lifecycle and durable queue. |
| 6. Non-functional | 196-211 | Installation, resilience, storage, performance, OS baseline, accessibility. |
| 7. Use cases | 212-233 | UC-01..17 user goals. |
| 8. Main flows | 234-314 | Analyze/download, pause, redownload, engine update and install flows. |
| 8.1 Single | 236-244 | Analyze, quality pick, enqueue and completion. |
| 8.2 Playlist | 245-253 | Playlist analysis, per-entry processing and ZIP/history behavior. |
| 8.3-8.4 Pause/redownload | 254-262 | Process stop/resume/delete and history replay. |
| 8.5 Engine lifecycle | 263-288 | Desktop app-data bootstrap, verified update, probation and fallback. |
| 8.6 Release artifacts | 289-308 | Exact v1 artifact allowlist and per-platform install instructions. |
| 8.7 Shutdown | 309-314 | Desktop close and Android Home/recents/process-death behavior. |
| 9. Business rules | 315-340 | BR-01..21 quality, queue, persistence, engine and failure rules. |
| 10. Constraints | 341-358 | Tauri/platform, Android storage/runtime, licensing and install limits. |
| 11. Decisions | 359-393 | D-01..29 selected stack, architecture, delivery and licensing decisions. |
| 12. Architecture | 394-461 | UI/Rust/engine boundaries, proposed layout and Android ownership. |
| 13. Technologies | 462-481 | Technology choices and reasons. |
| 14. Data model | 482-554 | SQLite/manifest sketches and contract core types. |
| 14. History/settings | 484-510 | Persisted history uniqueness and settings schema. |
| 14. Manifest/queue/errors/types | 511-554 | Engine manifest, durable queue, error notifications, core types. |
| 15. Interfaces/API | 555-597 | Contract authority, commands/events, results and gaps. |
| 15. Commands/events | 559-584 | UI-to-Rust commands and Rust-to-UI events. |
| 15. Results/helpers/gaps | 585-597 | Analyze result fields, typed wrappers, pending API gaps. |
| 16. Error handling | 598-617 | Typed errors, persistent notifications and update fallback. |
| 17. Security | 618-629 | Process/URL/file controls, update trust, privacy and license. |
| 18. Testing | 630-645 | CLI, mock, Rust/UI, CI, install and Android test strategy. |
| 19. Acceptance criteria | 646-693 | AC-01..36 UI, download, release and Android checks. |
| 20. Open questions | 694-733 | Resolved and pending decisions; check ownership before choosing. |

## Appendices

| Part or stage | Lines | Contents |
|---|---:|---|
| A. Roadmap and delivery rule | 734-745 | Checkpoint evidence and explicit owner acceptance required before next stage. |
| A. Phase 0 overview | 747-753 | Feasibility gates and exit criteria. |
| A. Gate 0A | 751 | Reproducible scaffold, contracts, Android skeleton, pins, license, CI, design inventory. |
| A. Gate 0B | 752 | Real yt-dlp/QuickJS/ffmpeg commands and licensing proof. |
| A. Gate 0C | 753 | Real-device Android engine, lifecycle and MediaStore feasibility spike. |
| A. Phase 1 overview | 755-761 | Complete mock-engine UI. |
| A. Stage 1A | 759 | Shell, visual tokens, navigation and i18n. |
| A. Stage 1B | 760 | Input, analysis, single/playlist download flows. |
| A. Stage 1C | 761 | Queue, history, settings and notification UI. |
| A. Phase 2 overview | 763-770 | Windows core in vertical slices. |
| A. Stage 2A | 767 | SQLite persistence and command boundary. |
| A. Stage 2B | 768 | Desktop engine bootstrap and analysis. |
| A. Stage 2C | 769 | Single downloads and queue lifecycle. |
| A. Stage 2D | 770 | Engine updater and fallback. |
| A. Phase 3 overview | 772-778 | Windows playlists and release. |
| A. Stage 3A | 776 | Sequential playlist processing. |
| A. Stage 3B | 777 | ZIP and filesystem resilience. |
| A. Stage 3C | 778 | Windows installer/update release. |
| A. Phase 4 overview | 780-785 | Linux and macOS ports. |
| A. Stage 4A | 784 | Linux runtime, AppImage and deb. |
| A. Stage 4B | 785 | macOS architectures, DMGs and updater. |
| A. Phase 5 overview | 787-793 | Production Android. |
| A. Stage 5A | 791 | Kotlin/Rust engine adapter. |
| A. Stage 5B | 792 | MediaStore output and lifecycle. |
| A. Stage 5C | 793 | Signed Android APK release. |
| A. Phase 6 overview | 795-800 | Release hardening. |
| A. Stage 6A | 799 | Accessibility, diagnostics, performance, translations. |
| A. Stage 6B | 800 | Full release rehearsal and owner approval. |
| B. CLI starting points | 802-813 | Unverified yt-dlp commands for Gate 0B. |
| C. JS runtime notes | 814-821 | QuickJS/yt-dlp-ejs requirements to reverify. |
| D. Glossary | 822-827 | Sidecar, ejs, MediaStore and baseline engine terms. |
