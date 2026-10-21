# Zownload — Technical Specification

Repository state: Gate 0A accepted by the owner on 2026-10-18. Work is limited to Gate 0B — Real CLI and licensing proof; its builds and real CLI capabilities are not yet verified.

## 0. How to read this document

**Status tags** (used on every decision, requirement and rule):

| Tag | Meaning |
|---|---|
| `[CONFIRMED]` | Stated or explicitly accepted by the owner. Do not change without asking. |
| `[PROPOSAL]` | Suggested by the assistant and not rejected, but not explicitly approved. Treat as the default; the owner may change it. Includes everything in the contract files unless noted. |
| `[PENDING]` | Undecided or unknown. Needs an owner decision or a technical spike. Do not silently pick an answer; ask or document the assumption. |

**Current repository state:** Gate 0A is accepted by the owner (2026-10-18). Work is now limited to **Gate 0B — Real CLI and licensing proof**; its builds and real CLI capabilities are not yet verified. The repository contains:

- `shared/contract.ts` — TypeScript side of the UI ↔ engine contract.
- `src-tauri/src/contract.rs` — Rust mirror of the same contract.
- `docs/gates/gate-0a.md` — focused scope, checklist and evidence log for the first implementation gate.
- `docs/design/README.md` and `docs/design/{desktop,mobile}/` — indexed visual references for Phase 1.

**Authority rule:** for field names and types, the contract files win. For behaviour and intent, this document wins. For visual appearance and layout, the confirmed images indexed by `docs/design/README.md` win. A gate brief narrows execution scope but never overrides this document. If any authority conflicts with another, report it to the owner instead of silently choosing.

**Owner profile (affects how you should work):**
- Knows React/TypeScript well. Knows **little about Rust and Tauri**: explain Rust code, keep it simple and commented, prefer well-known crates, avoid clever abstractions.
- Uses the OpenCode AI coding tool. Required repo guidance (`[CONFIRMED]`): short root `AGENTS.md`, `opencode.json` loading `PROJECT.md`, focused execution briefs under `docs/gates/`, and supporting evidence docs such as `docs/toolchain.md` / `docs/ytdlp-commands.md` when their gates create them.
- English is the owner's second language; UI languages are English and Spanish.

---

## 1. Project overview and objective

**Name:** Zownload (the header shows the lowercase text "zownload" next to a logo). `[CONFIRMED]`

**Objective:** a cross-platform app to download **mp3 (audio)** and **mp4 (video)** files from as many websites as possible, using **yt-dlp** and **ffmpeg**. A user pastes a URL, and for playlists the **URL alone** is enough to download the entire playlist. `[CONFIRMED]`

**Targets:** Windows, macOS, Linux (desktop) and Android (mobile). iOS is excluded. `[CONFIRMED]`

**Key constraints at a glance:**
- Built with **Tauri**, **React** frontend. `[CONFIRMED]`
- **One monorepo** containing all targets, with a folder for shared code. `[CONFIRMED]`
- Android uses a **local engine** (no external server). `[CONFIRMED]`
- Distributed **only through GitHub** (Releases). `[CONFIRMED]`
- Development order: **Windows → Linux/macOS → Android**, with an early time-boxed Android feasibility spike. `[CONFIRMED]`

## 2. Problem it solves

yt-dlp is powerful but is a command-line tool that needs extra binaries (ffmpeg, a JavaScript runtime for YouTube) and manual updates. Ordinary users want: paste a link, pick mp3 or mp4, get a tagged file, and download whole playlists with one URL, on desktop and phone, with **one download and one install** and no terminal. `[PROPOSAL]` (synthesized from the owner's stated goals; the owner did not write a problem statement.)

## 3. Scope

### In scope `[CONFIRMED]`
- Download single items and entire playlists as mp3 or mp4 from any site yt-dlp supports.
- Playlist output either as one `.zip` or as individual files downloaded sequentially.
- Download queue with pause/resume/delete; download history with redownload.
- Metadata embedding (artist/author, thumbnail, album, etc.).
- English/Spanish UI; settings screen.
- Bundled yt-dlp, ffmpeg and JS runtime; self-updating yt-dlp; app self-update (see section 8).
- Installers/packages for Windows, macOS, Linux, Android via GitHub Releases and GitHub Actions CI. The exact v1 artifact list is in section 8.6 (single source of truth; other sections must match it).

### Out of scope `[CONFIRMED]`
- iOS. A backend/server for downloading. App store distribution (Google Play, App Store, Microsoft Store).

### Out of scope for v1 `[PROPOSAL]`
- Selecting/deselecting individual playlist items (the spec only shows a read-only list of names).
- Login/cookies for private or age-restricted content (these produce an error instead).
- Running more than one download at the same time.
- Video editing, format options other than mp3/mp4, subtitles.

## 4. Features

| ID | Feature | Status |
|---|---|---|
| F1 | Always-visible header with logo, name, language switch and settings button | `[CONFIRMED]` |
| F2 | Main screen with Input state and Download state | `[CONFIRMED]` |
| F3 | URL analysis (single or playlist) with metadata preview | `[CONFIRMED]` |
| F4 | mp3/mp4 download with quality selection (single) or max/min (playlist) | `[CONFIRMED]` |
| F5 | Playlist download as `.zip` or one-by-one | `[CONFIRMED]` |
| F6 | Queue card: progress, pause/continue, delete, playlist counters, failure summary | `[CONFIRMED]` |
| F7 | History card: redownload, delete one, delete all | `[CONFIRMED]` |
| F8 | Settings: language, zip option, download folder, update button, developer info | `[CONFIRMED]` |
| F9 | Metadata embedding in downloaded files | `[CONFIRMED]` |
| F10 | Bundled engine + self-updating yt-dlp with fallback | `[CONFIRMED]` |
| F11 | App self-update (desktop updater; Android release check) | `[CONFIRMED]` |
| F12 | Android background downloads (foreground service + notification) | `[CONFIRMED]` |

### Design references `[CONFIRMED]`

- The visual reference index is `docs/design/README.md`; source images live in `docs/design/desktop/` and `docs/design/mobile/`.
- Existing images are the confirmed target for colors, shapes, spacing, visual hierarchy and overall style of the states/components they show.
- Image filenames identify the represented screen or component. The index records device class and dimensions; do not rename, replace or reinterpret a confirmed reference silently.
- Screens, states, responsive breakpoints and components without an image may be designed by the implementing AI, provided they remain visually consistent with the confirmed references and satisfy this specification, accessibility requirements and both languages.
- Images define appearance, not hidden behaviour. Interactions, state transitions, data and error rules always come from this document and the contracts.
- Gate 0A only inventories and preserves these references. UI implementation begins in Phase 1.

## 5. Functional requirements

### Header
| ID | Requirement | Status |
|---|---|---|
| FR-01 | Header is at the top of the page and always visible. Left: logo + the text "zownload". | `[CONFIRMED]` |
| FR-02 | Right side: a button/icon to change language (English/Spanish only), and to its right a settings button. | `[CONFIRMED]` |

### Main screen layout
| ID | Requirement | Status |
|---|---|---|
| FR-03 | The Queue card and History card are always shown, on the **left side** of the main screen. | `[CONFIRMED]` |
| FR-04 | Desktop layouts and represented states follow the confirmed desktop images. Missing desktop screens/components may be completed consistently with that visual system; the main structure remains left Queue/History and right Input/Download. | `[CONFIRMED]` |
| FR-05 | Mobile layouts and represented states follow the confirmed mobile images. Missing mobile screens/components may be completed consistently using a single column, large touch targets and no hover-only interaction. | `[CONFIRMED]` |
| FR-06 | The main screen has two states: **Input state** and **Download state**. | `[CONFIRMED]` |

### Input state
| ID | Requirement | Status |
|---|---|---|
| FR-10 | A card with a URL input, below it the format options **mp3** and **mp4**, below them a **Convert** button. | `[CONFIRMED]` |
| FR-11 | When Convert is pressed, the button shows the text "analyzing" with a circular loading animation while the URL is analyzed. | `[CONFIRMED]` |
| FR-12 | If analysis fails, show a **red message below the input field** with the error type; stay in Input state. | `[CONFIRMED]` |
| FR-13 | Playlist detection is automatic from the URL (no separate toggle). A watch URL that also contains a playlist parameter is treated as a single item; only a pure playlist URL is treated as a playlist. | `[CONFIRMED]` |
| FR-14 | Disable the button while analyzing to prevent double submission. | `[PROPOSAL]` |

### Download state
| ID | Requirement | Status |
|---|---|---|
| FR-20 | When analysis succeeds, the input card is replaced by the **download card**: thumbnail on the left; on the right the title, author, duration (single) or number of elements (playlist), and the site name. | `[CONFIRMED]` |
| FR-21 | Card footer, **single element**: a combo box with the available qualities on the left, a Download button on the right. | `[CONFIRMED]` |
| FR-22 | Card footer, **playlist**: a combo box with only **Max quality** and **Min quality** on the left, a Download button on the right. | `[CONFIRMED]` |
| FR-23 | For a playlist, a second card **below** the download card lists the names of the elements. | `[CONFIRMED]` |
| FR-24 | An arrow above the download card returns to the Input state. | `[CONFIRMED]` |
| FR-25 | Single-element qualities depend on the chosen format: mp4 → available video heights (e.g. 1080p); mp3 → fixed **output** bitrate presets (320, 256, 192, 128 kbps). MP3 always downloads the best source audio before encoding to the selected output bitrate. | `[CONFIRMED]` |
| FR-26 | After pressing Download, the item appears in the Queue card and the main area returns to a cleared Input state. | `[CONFIRMED]` |

### Queue card
| ID | Requirement | Status |
|---|---|---|
| FR-30 | Lists the downloads in the queue, each with a progress bar and the options **stop/continue** and **delete**. | `[CONFIRMED]` |
| FR-31 | Single element: show only the download percentage. | `[CONFIRMED]` |
| FR-32 | Playlist: show elements downloaded / total, e.g. `5/10`, `9/10`. | `[CONFIRMED]` |
| FR-33 | If some playlist elements fail, continue with the rest and show a message on the item's progress bar, e.g. "10 correct, 5 failed". | `[CONFIRMED]` |
| FR-34 | Empty queue shows the message **"No active downloads"**. | `[CONFIRMED]` |
| FR-35 | A stopped item shows **"Paused"**, not a frozen progress bar. | `[CONFIRMED]` |
| FR-36 | Stop = kill the yt-dlp process; Continue = start it again and resume from the partial file (`.part`). | `[CONFIRMED]` |
| FR-37 | Delete cancels the download if running, deletes partial files, removes the item. | removal `[CONFIRMED]`; partial-file cleanup `[PROPOSAL]` |
| FR-38 | Pause is available only while an item is `downloading`. It is disabled during `analyzing`, ffmpeg `postProcessing`, and ZIP `packaging`. | `[CONFIRMED]` |
| FR-39 | `done` and `failed` are transient states: finished items are removed automatically from the queue. Before removing a failed item, persist an error notification that remains visible until the user dismisses it. | `[CONFIRMED]` |

### History card
| ID | Requirement | Status |
|---|---|---|
| FR-40 | Lists previously completed download requests; each has two options: **delete** from history and **redownload**. A playlist creates one history entry for the entire playlist request, never one per element. | `[CONFIRMED]` |
| FR-41 | Redownload enqueues the stored request (url, format, is-playlist, quality) and the process is shown in the Queue card. It does not open the Input/Download screens. | `[CONFIRMED]` |
| FR-42 | An option deletes the entire history. | `[CONFIRMED]` |
| FR-43 | Empty history shows **"No history yet"**. | `[CONFIRMED]` |
| FR-44 | Each history record stores: `url`, `format`, `is_playlist`, `quality`, plus `title` (display only). Nothing else (no timestamp). Duplicate titles are allowed; rows are identified by id. | `[CONFIRMED]` |
| FR-45 | On redownload, if the exact stored single-item **video height** no longer exists, use the closest lower quality. MP3 output bitrate presets are stable and do not require fallback. | `[CONFIRMED]` |

### Download behaviour
| ID | Requirement | Status |
|---|---|---|
| FR-50 | Playlist quality matrix is exactly as in business rule BR-01. | `[CONFIRMED]` |
| FR-51 | Downloaded files include title, artist/creator/uploader, album and cover art using the exact mapping in FR-58. | `[CONFIRMED]` |
| FR-52 | Setting "Download a playlist as a .zip file": yes → one `.zip`; no → elements downloaded **one by one**, starting the next when the previous ends, each saved **with the element's own name** (not the playlist's). | `[CONFIRMED]` |
| FR-53 | Desktop: download folder defaults to the system **Downloads** folder and the user may choose another folder. Android v1: always save through MediaStore to the public Downloads collection; hide/ignore the folder selector and do not use SAF. | `[CONFIRMED]` |
| FR-54 | Zip mode writes directly to a pending final archive (`playlist.zip.part` on desktop; a pending MediaStore entry on Android if the spike validates it). Each completed media file is added uncompressed, verified, and deleted immediately. On success, finalize/rename the archive. At most the partial ZIP plus the current temporary media file coexist; a full second copy of the playlist is never required. | `[CONFIRMED]` (direct MediaStore writing must be validated in the Android spike) |
| FR-55 | Progress events are throttled (≈5 per second per item max). | `[PROPOSAL]` |
| FR-56 | Duplicate display titles are allowed. Physical filename collisions are resolved without overwriting by appending ` (1)`, ` (2)`, etc., both in download folders and inside ZIP archives. | `[CONFIRMED]` |
| FR-57 | On disk-full or output-permission failure, cancel the whole job, terminate every active child process, clean incomplete output where safe, persist a translated error notification, and remove the item from the queue. | `[CONFIRMED]` |
| FR-58 | Metadata mapping: `title` = media title; `artist` = source artist/creator, falling back to uploader/author; `album` = playlist title for playlist entries and empty for single items; cover art = best available thumbnail converted to JPEG when the target container requires it. | `[CONFIRMED]` (exact yt-dlp/ffmpeg flags validated in Gate 0B) |

### Settings screen
| ID | Requirement | Status |
|---|---|---|
| FR-60 | Language: English / Spanish. | `[CONFIRMED]` |
| FR-61 | "Download a playlist as a .zip file": yes/no. | `[CONFIRMED]` |
| FR-62 | Developer information section. | section `[CONFIRMED]`, content `[PENDING]` |
| FR-63 | Download folder selector. | `[CONFIRMED]` |
| FR-64 | Settings has an **Update engine** button that updates yt-dlp only. App updates are checked separately at startup at most once per day; when one exists, show a distinct persistent **Update Zownload** action (desktop updater) or **Download new APK** action (Android). | `[CONFIRMED]` |
| FR-65 | Settings persist across restarts in the same SQLite database used by history and the durable queue. | `[CONFIRMED]` |
| FR-66 | All UI text, including error messages, exists in English and Spanish (i18n files in the shared folder). | `[CONFIRMED]` (mechanism `[PROPOSAL]`) |

### Engine and updates
| ID | Requirement | Status |
|---|---|---|
| FR-70 | The installer bundles baseline yt-dlp, ffmpeg and the JS runtime. | `[CONFIRMED]` |
| FR-71 | On first launch (desktop) the app copies the baseline engine (yt-dlp, ffmpeg, QuickJS) from the installation folder to the writable per-user **app data directory** (`<app_data>/engine/`) and **always executes the copies there**, never the files in the installation folder (BR-12). | `[CONFIRMED]` |
| FR-72 | Engine update (yt-dlp only): download the latest stable yt-dlp release from yt-dlp's GitHub into a staging folder, verify it against the published checksum file, run a health check on it, and only then swap it into `<app_data>/engine/` (only when no yt-dlp process is running). If verification fails, nothing changes. If an accepted update later proves broken (BR-17), the fallback **restores the bundled baseline by copying it again into app data and executing it from there**. Full procedure in section 8.5. | update + fallback to baseline `[CONFIRMED]`; mechanics (re-copy, health check, probation) `[PROPOSAL]` |
| FR-73 | Automatic update check at startup at most once per day, in addition to the Settings button. | `[CONFIRMED]` |
| FR-74 | ffmpeg and the JS runtime are refreshed only when a new app version ships: on the first launch after an app update they are re-copied from the baseline into app data. yt-dlp is re-copied only if the bundled baseline version is newer than the active one. | refresh rule `[CONFIRMED]` (ffmpeg stated; runtime `[PROPOSAL]`); mechanism `[PROPOSAL]` |
| FR-75 | Desktop app self-update via the Tauri updater plugin reading a bundle-type-aware `latest.json` from GitHub Releases, so an NSIS installation receives NSIS, MSI receives MSI, AppImage receives AppImage and `.deb` receives `.deb`. Pin `tauri-plugin-updater` to exact version `2.13.0` in v1 and use a compatible Tauri bundler that embeds the installed bundle type. Updating MSI/`.deb` may request administrator privileges. If updating a package proves unreliable, show "New version available" with a direct download link instead. | `[CONFIRMED]` |
| FR-76 | Android app update: on startup call the GitHub Releases API, show "New version available", open the APK link. No silent updates in v1. | `[CONFIRMED]` |
| FR-77 | Android: background downloads continue after the user presses Home, using a foreground service and notification; save to the user's Downloads via MediaStore/Storage Access Framework. The service only keeps the process alive and shows the notification; it holds no queue or business logic (D-23). Removing the app from recents cancels all active work and stops the service (FR-81). | `[CONFIRMED]` |
| FR-78 | The queue is saved to SQLite on structural/status changes and periodic durable progress checkpoints, then restored at app start. Items interrupted in `analyzing`, `downloading`, `postProcessing` or `packaging` are restored as `paused` and are **never resumed automatically** (avoids surprise mobile data use). | `[CONFIRMED]` for shared desktop/Android Rust code |
| FR-79 | The UI is disposable: whenever it starts (or is recreated after the WebView/Activity died) it calls `get_queue` and subscribes to events, and shows the correct state without losing anything. | `[CONFIRMED]` (D-23) |
| FR-80 | Android 15+ foreground-service time limit: when the system signals the timeout (`onTimeout`), Rust pauses the queue in an orderly way and the notification says the downloads are paused and the user must open the app to continue. No crash, no lost progress. | behaviour `[PROPOSAL]`; `dataSync` foreground service type `[CONFIRMED]` by owner on 2026-10-21 (see section 20) |
| FR-81 | Lifecycle shutdown: closing the desktop window with X cancels all active jobs and kills their complete process trees before exit. On Android, Home keeps downloads running; removing the app from recents cancels all jobs and stops the foreground service; real process death leaves no child work running. Interrupted queue items are restored as `paused` on the next launch. | `[CONFIRMED]` |

## 6. Non-functional requirements

| ID | Requirement | Status |
|---|---|---|
| NFR-01 | **Easy installation:** installing one concrete OS/architecture combination requires one appropriate artifact, no terminal and no extra dependency downloads. A release may contain alternatives for different architectures or package formats. | `[CONFIRMED]` |
| NFR-02 | **Resilience to site changes:** yt-dlp updatable without a new app release. | `[CONFIRMED]` |
| NFR-03 | **Fault tolerance:** one failing playlist element never stops the rest. | `[CONFIRMED]` |
| NFR-04 | **Storage efficiency:** ZIP mode never retains the complete set of individual files alongside the archive. Storage overhead is bounded to the partial ZIP plus the current temporary media file. Large playlists can be many GB; mobile storage is limited. | `[CONFIRMED]` |
| NFR-05 | **UI performance:** light UI, throttled progress events, no heavy animation libraries (Android uses the system WebView). | `[PROPOSAL]` |
| NFR-06 | **Responsive/mobile-first** React UI shared by desktop and Android. | `[PROPOSAL]` |
| NFR-07 | **Maintainability:** download logic behind one engine interface; contract files kept in sync; single repo. | `[CONFIRMED]` (interface idea) / `[PROPOSAL]` (details) |
| NFR-08 | **Localization:** English and Spanish. | `[CONFIRMED]` |
| NFR-09 | **Minimum OS versions** must be recorded with the pinned toolchain and validated by CI/device availability before feature work. | `[PENDING]` until Gate 0A; proposed baseline: Windows 10 1803+, macOS 10.15+, Android 7/API 24; Linux support defined by the Stage 4A test matrix |
| NFR-10 | **Accessibility** (keyboard navigation, screen readers, contrast). | `[PENDING]` |
| NFR-11 | **Logging/diagnostics:** local-only logs, no telemetry. | `[PROPOSAL]` |

## 7. Use cases

| ID | Use case | Actor goal |
|---|---|---|
| UC-01 | Download a single item as mp3 | Paste URL, choose mp3, Convert, pick bitrate, Download |
| UC-02 | Download a single item as mp4 | Same, choose mp4 and a video height |
| UC-03 | Download a playlist as mp4 (max or min) | Paste playlist URL, mp4, choose Max/Min, Download |
| UC-04 | Download a playlist as mp3 (max or min) | Same with mp3 |
| UC-05 | Playlist as one `.zip` | Settings → zip on, then UC-03/04 |
| UC-06 | Playlist file by file | Settings → zip off, then UC-03/04 |
| UC-07 | Pause and resume a download | Stop, see "Paused", Continue |
| UC-08 | Remove a download from the queue | Delete |
| UC-09 | Redownload from history | Press redownload; item appears in queue |
| UC-10 | Delete one history entry / clear history | Delete / delete all |
| UC-11 | Change language | Header button or Settings |
| UC-12 | Change download folder / zip option | Settings |
| UC-13 | Update the engine | Settings **Update engine** button, or automatic daily engine check |
| UC-14 | Update the app | Separate stable-release check; desktop shows **Update Zownload**, Android shows **Download new APK** only when available |
| UC-15 | Analyze a bad URL | See red error under the input |
| UC-16 | Playlist with some failing items | See "N correct, M failed" in the queue |
| UC-17 | Install the app | See flows in section 8 |

## 8. Main flows

### 8.1 Analyze → download (single)
1. User pastes URL, selects mp3 or mp4, presses Convert; button shows "analyzing" + spinner.
2. UI calls `analyze_url(url)`. On error → red message under the input (FR-12).
3. On success (`kind: "single"`) → Download state: thumbnail, title, author, duration, site.
4. Combo box lists available video heights for mp4, or fixed MP3 output bitrates (320/256/192/128 kbps) for mp3; user picks one and presses Download. MP3 always uses the best source audio.
5. UI calls `enqueue_download({ url, format, quality, isPlaylist: false })` and receives the queue item id.
6. The main area immediately returns to a cleared Input state. Rust runs the engine; `queue:item-updated` events drive the percentage in the Queue card.
7. On completion the file is saved to the download folder with embedded metadata; a history record is written; `history:changed` is emitted; the transient `done` item is removed from the queue.

### 8.2 Analyze → download (playlist)
1. Same as 8.1 up to analysis; result is `kind: "playlist"` with `itemCount` and `itemTitles`.
2. Download state shows playlist info, the Max/Min combo box, and a second card listing the element names.
3. `enqueue_download({ ..., quality: {type:"max"|"min"}, isPlaylist: true })`.
4. Rust queue manager (proposal, section 12): analyze the playlist (flat) to get entries; for each entry call the engine; update `done`/`failed` counters; a failed entry increments `failed` and continues.
5. Zip off: each file is saved straight into the download folder, named after the element, then the next entry starts.
6. Zip on: write directly to `playlist.zip.part` (or a pending MediaStore destination on Android); each finished file is added uncompressed, verified and deleted immediately. Finalize/rename the archive at the end (`packaging`).
7. A playlist writes one history row for the whole request when at least one element succeeds. Final status is transient `done` (even if some failed) or `failed` if all failed; then the queue item is removed. Any failure summary is persisted as an error notification until dismissed.

### 8.3 Pause / resume / delete
- Pause is enabled only during `downloading`: kill the yt-dlp process; status `paused`; UI shows "Paused".
- Pause is disabled during `analyzing`, ffmpeg `postProcessing`, and ZIP `packaging`.
- Resume: restart yt-dlp for the current entry; yt-dlp continues from the `.part` file; for playlists, continue from the current entry index.
- Delete: cancel if running, remove partial files, emit `queue:item-removed`.

### 8.4 Redownload
`enqueue_download(historyEntry.request)`. Status starts at `analyzing` (to fetch title/thumbnail/entries), then `queued`/`downloading`. Playlists re-analyze and use the stored Max/Min mode. If a single-item quality no longer exists, use the closest lower one (FR-45).

### 8.5 Engine bootstrap, update and fallback (desktop) `[PROPOSAL]` mechanics (principles are `[CONFIRMED]`)

**Locations**
```
<install folder>/binaries/      yt-dlp, ffmpeg, qjs    # baseline; read-only; NEVER executed directly
<app_data>/engine/
    yt-dlp[.exe]  ffmpeg[.exe]  qjs[.exe]               # the only copies that are executed
    engine.json                                          # manifest (section 14)
    staging/                                             # candidate files, before verification/swap
```

**A. Install baseline** (one routine, used in three cases): 1) copy the file(s) from the install folder to `staging/`; 2) set the execute permission on Unix; 3) run the health check (BR-17a); 4) atomically replace the active copy in `engine/`; 5) write `engine.json`. Used for: **first launch** (all three components); **first launch after an app update** (ffmpeg and QuickJS always; yt-dlp only if the bundled version is newer than the active one, comparing yt-dlp's date-based versions numerically); and **fallback** (step D).

**B. Update yt-dlp** (Settings button, or automatic check at startup at most once per day):
1. Ask GitHub for the latest stable release: tag, asset for this platform, checksum file. Same version as active, or tag in `failedVersions` (automatic check only) → stop.
2. Download the asset into `staging/`.
3. Verify the SHA-256 against the published checksum file. Mismatch → delete, show "update failed", keep the current copy.
4. Run the health check on the staged file (BR-17a). Failure → delete, add the tag to `failedVersions`, keep the current copy.
5. Swap into place only when no yt-dlp process is running (BR-16). Write `engine.json` with `source: "updated"` and `state: "probation"`.

**C. Probation:** from the swap until the first invocation that completes normally. Process-level failures (BR-17b) during probation trigger step D. The first normal completion sets `state: "good"`. Site/network errors never count (BR-17c).

**D. Fallback to baseline:** 1) stop running yt-dlp processes (the interrupted queue item stays recoverable from its `.part` file); 2) run **A (Install baseline)** for yt-dlp: copy the bundled baseline into `engine/` and run it **from there**; 3) write `engine.json` with `source: "bundled"` and add the broken version to `failedVersions`; 4) re-run once the invocation that exposed the breakage; 5) show in Settings "Update X was reverted; using the bundled version Y". If the baseline itself fails its health check, report `engine_missing` and ask the user to reinstall the app.

**E. Android:** youtubedl-android manages its own copy and updates it with `updateYoutubeDL()`. How to revert to the bundled yt-dlp on Android is `[PENDING]` (see section 20, #31).

### 8.6 Release artifacts and installation per platform

**v1 release artifacts (single source of truth).** Anything not in this table is **not** part of v1. Roadmap stage = when it is first built and tested (order Windows → Linux/macOS → Android).

| Platform | v1 artifact(s) | Auto-update | Roadmap stage | Status |
|---|---|---|---|---|
| Windows x64 | NSIS `*-setup.exe` (recommended for most users) **and** WiX `.msi` (managed/enterprise installation) | Tauri updater for both | 3C | `[CONFIRMED]` |
| macOS | Two `.dmg`: Apple Silicon (aarch64) and Intel (x86_64) | Tauri updater (`.app.tar.gz` updater bundle) | 4B | `[CONFIRMED]` |
| Linux x64 | **`.AppImage`** (portable, primary) **and `.deb`** (Debian/Ubuntu) | Tauri updater for both (see FR-75) | 4A | `[CONFIRMED]` |
| Android arm64 | One signed `.apk` for `arm64-v8a`; no other ABI in v1 | Release check via GitHub API, opens APK link (FR-76) | 5C | `[CONFIRMED]` |
| Updater metadata | Bundle-type-aware `latest.json`, per-installer `.sig` files and macOS `.app.tar.gz` updater bundles, generated by CI and attached to the same release; these are technical artifacts, not user-selected installers | — | 3C/4A/4B | `[CONFIRMED]` |

Explicitly **out of v1** `[CONFIRMED]`: `.rpm`, Flatpak, Snap, Microsoft Store/MSIX, Windows ARM, Linux ARM, macOS universal binary, Android AAB, `armeabi-v7a`, `x86_64` Android, and any store distribution. They can be added later without changing the architecture. In CI, restrict bundle targets explicitly so no extra format is published by accident.

**Install steps to document in the README** `[CONFIRMED]`:
- **Windows:** most users download `*-setup.exe`; managed environments may use `.msi`. Run the chosen installer; SmartScreen warns (unsigned) → More info → Run anyway. Building MSI requires Windows VBSCRIPT support in CI.
- **macOS:** download the `.dmg` (Apple Silicon or Intel), drag to Applications; Gatekeeper blocks first launch → System Settings → Privacy & Security → Open Anyway (right-click → Open no longer works on recent macOS). Document with screenshots. Paid Apple Developer account + notarization is a possible later improvement `[PENDING]`.
- **Linux:** both are shipped. **AppImage:** works on most distros; make it executable and run it; some distros (e.g. Ubuntu 22.04+) need `libfuse2`. **`.deb`:** for Debian/Ubuntu and derivatives; double-click to install through the software center (needs administrator rights).
- **Android:** download the `arm64-v8a` `.apk` in the browser; allow "Install unknown apps" once; Play Protect may warn → Install anyway. Devices that are not ARM64 are unsupported in v1. **All release APKs must be signed with the same keystore**, otherwise updates fail; back the keystore up.

### 8.7 Application shutdown
- **Desktop X:** persist active queue items as `paused`, cancel every active job, terminate the complete yt-dlp/ffmpeg/QuickJS process tree, then exit. Nothing remains running in the background.
- **Android Home:** keep the process alive through the foreground service; downloads continue.
- **Android removed from recents:** persist active items as `paused`, cancel all jobs, terminate engine work and stop the foreground service.
- **Real process death/crash:** child work must die with the process. On the next launch, interrupted items are restored as `paused`; never resume automatically.

## 9. Business rules

| ID | Rule | Status |
|---|---|---|
| BR-01 | **Playlist quality matrix.** mp4+Max: best video + best audio. mp4+Min: **min video + max audio**. mp3+Max: best source audio encoded at 320 kbps. mp3+Min: best source audio encoded at 128 kbps (smallest MP3 preset). Playlists only offer Max/Min. | `[CONFIRMED]` |
| BR-02 | Single mp4: user chooses an available video height. Single mp3: user chooses an output bitrate from 320/256/192/128 kbps; the engine always downloads the best source audio before encoding. | `[CONFIRMED]` |
| BR-03 | Zip off → sequential download; next element starts when the previous one ends; file named after the element. | `[CONFIRMED]` |
| BR-04 | A failed playlist element never aborts the playlist; failures are counted and summarized. | `[CONFIRMED]` |
| BR-05 | Pause is implemented by killing the yt-dlp process during `downloading`; resume continues from the partial file. Pause is unavailable during ffmpeg `postProcessing` and ZIP `packaging`. | `[CONFIRMED]` |
| BR-06 | History stores only url, format, is_playlist, quality, title. A playlist produces one row for the whole request. Duplicate titles are valid and rows are identified by id. | `[CONFIRMED]` |
| BR-07 | Redownload goes straight to the queue, no Input/Download screens. | `[CONFIRMED]` |
| BR-08 | History is unique per (url, format, is_playlist, quality); repeating the exact request deletes the old row and inserts a new one (moves it to the top). Different requests may have the same title. Newest first = highest id first. | `[CONFIRMED]` |
| BR-09 | The queue runs one item at a time, in order. | `[PROPOSAL]` |
| BR-10 | A history row is written when an item finishes with at least one successful file. | `[PROPOSAL]` |
| BR-11 | Finished items never remain in the queue. `done` and `failed` are transient internal/event states. Successful requests write history before removal; failures persist an error notification before removal. | `[CONFIRMED]` |
| BR-12 | The engine binaries that are executed are always the copies in `<app_data>/engine/`. The bundled files in the installation folder are **never executed directly**; they are only the source for copying (first launch, app update, fallback). The fallback is therefore "copy the baseline into app data again, then run it from there". (Another reason: an AppImage's internal paths are temporary and change on every run.) | principle `[CONFIRMED]`; fallback mechanics `[PROPOSAL]` |
| BR-13 | mp4 output where the source audio codec is not mp4-compatible (e.g. Opus) is re-encoded to AAC by ffmpeg. | `[PROPOSAL]` |
| BR-14 | UI never knows which engine implementation runs (desktop sidecar vs Android Kotlin). | `[CONFIRMED]` |
| BR-15 | On start, interrupted items are restored as `paused` and wait for the user to press Continue; the app never resumes downloads on its own after a process death or an OS restart of the service. | `[CONFIRMED]` (D-23) |
| BR-16 | A downloaded yt-dlp is **never executed before its checksum is verified**. It is swapped into place only when no yt-dlp process is running (a running `.exe` cannot be replaced on Windows); if the queue is busy, the swap waits until the queue is idle or the next app start. The swap is an atomic rename inside the same folder. | `[PROPOSAL]` |
| BR-17 | **When is the engine "broken"?** (a) *Pre-swap health check* fails: checksum mismatch; file not executable; `yt-dlp --version` does not exit 0 within 10 s; or the version it prints differs from the release tag. The candidate is discarded and the current copy stays. (b) *Probation breakage*: from the swap until the first invocation that completes normally, any **process-level** failure counts: cannot spawn; killed by a signal/crash; exit code ≠ 0 with **no** yt-dlp-formatted `ERROR:`/`WARNING:` line; no output within the timeout; or `analyze` exits 0 but its output is not valid JSON. One such failure triggers the fallback (it is cheap and reversible). (c) Ordinary **site/network errors reported by yt-dlp** (`ERROR: ...` lines such as unavailable video, unsupported URL, HTTP 403, no internet) are **never** engine breakage: a version failing on a site is the normal reason to update, the app cannot tell it apart from a site-specific problem, and the next release fixes it. Values (10 s, probation length) and the `ERROR:` pattern must be validated in Stage 2D. | `[PROPOSAL]` |
| BR-18 | A version that fails (a) or (b) is recorded in `failedVersions` and is not retried by the automatic check; a newer release is tried normally. The manual Settings button may retry once and explains the result. | `[PROPOSAL]` |
| BR-19 | Physical filename collisions never overwrite existing content. Sanitize the name and append ` (1)`, ` (2)`, etc. before the extension, including ZIP entries. Database identity remains id-based. | `[CONFIRMED]` |
| BR-20 | On `disk_full` or `permission_denied`, cancel the whole job, terminate every active child process, remove incomplete output where safe, persist the error notification, and remove the queue item. | `[CONFIRMED]` |
| BR-21 | Closing the desktop window or removing Android from recents stops all active engine work. Android Home is the only close-like user action that intentionally keeps downloads running in the background. Real process death must not leave orphan child processes. | `[CONFIRMED]` |

## 10. Constraints

- **Tauri 2 is required** for Android support. The Tauri updater plugin does **not** support mobile. `[CONFIRMED]` (Tauri; v2 implied by Android)
- **No iOS**, no backend server, **GitHub-only distribution**. `[CONFIRMED]`
- **Unsigned binaries:** SmartScreen (Windows), Gatekeeper (macOS), Play Protect/unknown-sources (Android) will warn; accepted and documented in the README. `[CONFIRMED]`
- **Sidecar naming:** Tauri sidecars must be named with the target triple, e.g. `yt-dlp-x86_64-pc-windows-msvc.exe`. `[CONFIRMED]`
- **Writable location:** the install folder (e.g. `Program Files`) is read-only; engines run from the app data directory. Binaries copied there need the execute bit on Unix. `[CONFIRMED]`
- **Android cannot execute binaries copied into app data** (modern Android restrictions); native executables must ship as libraries (e.g. `jniLibs`). The youtubedl-android library handles this for Python/yt-dlp/ffmpeg; a QuickJS binary may need the same treatment. `[PROPOSAL]` (verify in spike)
- **Android storage/distribution:** scoped storage through MediaStore Downloads only in v1; no SAF. Ship one `arm64-v8a` APK, not a universal or multi-ABI package. `[CONFIRMED]`
- **Android WebView:** performance depends on the device's system WebView. `[PROPOSAL]`
- **Android process lifetime:** the WebView/Activity can die at any time; the process can be killed by the system or aggressively by some manufacturers, even with a foreground service. Home keeps work running, but removing the app from recents intentionally cancels it. Nothing important may live only in memory; interrupted items restore as `paused` (see D-23, FR-78, FR-81). `[CONFIRMED]`
- **Android 15 foreground-service limit:** for apps targeting API 35+, a `dataSync` foreground service may run for a total of 6 hours per 24 hours. After that the system calls `onTimeout`, and no new `dataSync` service can start until the user brings the app to the foreground (which resets the timer). A very long playlist can hit this limit; see FR-80. A foreground service type must also be declared on recent Android versions. `[CONFIRMED]` (from Android documentation; re-verify when choosing the target API level)
- **Linux packaging:** AppImage may need `libfuse2` on newer distros; the `.deb` only installs on Debian-family distros and needs administrator rights, also when updating. Pin `tauri-plugin-updater` to `2.13.0`; it supports bundle-type-aware AppImage/`.deb` updates. `[CONFIRMED]`
- **YouTube JS runtime:** since yt-dlp 2025.11.12, full YouTube support requires an external JavaScript runtime plus the yt-dlp-ejs component. Deno has **no official Android build** (only old community builds, ≤ 1.36, while ejs needs Deno ≥ 2.3). See Appendix C. `[CONFIRMED]` (research result)
- **Legal/ToS:** downloading from some sites may violate their terms of service; app-store policies often ban such apps (reason for GitHub-only). The owner is responsible; README should include a disclaimer. `[PROPOSAL]`
- **yt-dlp breaks regularly** as sites change; the updater is a core requirement, not a nicety. `[CONFIRMED]`
- **Developer experience:** limited Rust/Tauri knowledge (see section 0). `[CONFIRMED]`

## 11. Technical decisions made

| ID | Decision | Status | Rationale / notes |
|---|---|---|---|
| D-01 | Framework: **Tauri** (v2) for desktop and Android | `[CONFIRMED]` | Single codebase for all targets; v2 needed for mobile |
| D-02 | Frontend: **React** | `[CONFIRMED]` | Owner's preference; any framework would work (webview) |
| D-03 | React + **TypeScript + Vite** (Tauri `create-tauri-app` template). Do **not** use Next.js | `[CONFIRMED]` | No SSR in Tauri; plain Vite is simpler |
| D-04a | Styling: **Tailwind CSS only**, without shadcn/ui or any other component library | `[CONFIRMED]` | Owner's explicit choice; keeps dependencies minimal |
| D-04b | State: Zustand; TanStack Query not needed | `[CONFIRMED]` | Data comes from Rust events, not a REST API |
| D-05 | Download tools: **yt-dlp + ffmpeg** | `[CONFIRMED]` | Owner requirement |
| D-06 | **Monorepo**, one repo for all ports, shared folder | `[CONFIRMED]` | Tauri 2 supports desktop+Android from one project |
| D-07 | JS runtime for yt-dlp: upstream **QuickJS 2026-06-04** on all platforms initially. Build reproducibly from the official source in CI for every desktop target and Android `arm64-v8a`; record source checksum and build commands. Do not depend on opaque third-party binaries. | `[CONFIRMED]` | MIT-licensed, meets yt-dlp's performance floor, one runtime/code path; Deno is unavailable on Android |
| D-08 | Switch desktop to Deno only if testing shows QuickJS is too slow for YouTube | `[CONFIRMED]` (as fallback) | Engine interface isolates the choice |
| D-09 | Android engine: local, via **youtubedl-android** wrapped in a **Kotlin Tauri mobile plugin** exposing the same commands | `[CONFIRMED]` (subject to the spike) | Library bundles Python, yt-dlp and FFmpeg; this project implements verified yt-dlp/ejs updates and rollback in Gate 0C task 0C-14; Android runtime behavior remains unverified on device |
| D-10 | Do an early **1–2 day Android spike** (Tauri Android build → Kotlin plugin → yt-dlp → one URL → MP3, **including a YouTube URL and the JS runtime**) | `[CONFIRMED]` | De-risks the hardest part |
| D-11 | Download logic behind one interface; desktop = sidecars, Android = Kotlin plugin; queue/progress/playlist/zip logic and whole frontend shared | `[CONFIRMED]` | |
| D-12 | Distribution only via GitHub Releases; CI with GitHub Actions + `tauri-action` for all four targets | `[CONFIRMED]` | |
| D-13 | yt-dlp kept in app data dir with bundled baseline fallback, checksum-verified updates | `[CONFIRMED]` | See FR-70..74 |
| D-14 | App updates: Tauri updater (desktop, signed with updater keypair; free, separate from OS signing); GitHub API check on Android | `[CONFIRMED]` | |
| D-15 | Development order: Windows → Linux/macOS → Android | `[CONFIRMED]` | |
| D-16 | Playlist: sequential download is the core; zip is a packaging step on top | `[CONFIRMED]` | |
| D-17 | Pause = kill process + resume from `.part` | `[CONFIRMED]` | yt-dlp has no native pause |
| D-18 | Use one local **SQLite** database owned by Rust for history, durable queue, persistent error notifications and settings. Access it with `rusqlite`; React never accesses the database directly. | `[CONFIRMED]` | One transactional persistence mechanism; preserves the UI ↔ Rust boundary |
| D-19 | Playlist handled per entry: the queue manager lists entries, then invokes the engine once per entry | `[PROPOSAL]` | Makes pause/resume, counters and per-entry failures simple |
| D-20 | UI ↔ engine contract in `shared/contract.ts` + `src-tauri/src/contract.rs` (camelCase JSON, commands + events) | `[CONFIRMED]` (v1 baseline) | See section 15 |
| D-21 | Incremental roadmap with mandatory owner-approved checkpoints: Gate 0A reproducible scaffold/toolchains → Gate 0B CLI/licensing proof → Gate 0C Android spike → mock UI → Windows vertical slices → Windows release → Linux/macOS → production Android → hardening. No stage begins before the previous checkpoint passes. | `[CONFIRMED]` | See Appendix A |
| D-22 | v1 user installers are exactly those in section 8.6: Windows NSIS `.exe` + WiX `.msi`; macOS `.dmg` for arm64 and x64; Linux `.AppImage` + `.deb`; Android one `arm64-v8a` `.apk`. CI also publishes updater metadata/signatures and macOS `.app.tar.gz`. No other formats. Pin updater `2.13.0`. | `[CONFIRMED]` | NSIS is the default Windows path; MSI supports managed installs; other formats add unsupported test/release surface |
| D-23 | **Android work ownership: option A.** Rust owns the queue and is the single source of truth (same code as desktop). Kotlin does only two things: (a) the `AndroidEngine` adapter around youtubedl-android (analyze, download one entry with progress callbacks, cancel) and (b) a foreground service that keeps the process alive and shows the notification, with **no business logic**. Three rules: **1)** Rust owns the queue and the truth; **2)** the queue is persisted to SQLite at durable checkpoints and restored at start, with interrupted items restored as `paused`; **3)** the UI is disposable and always rebuilds its state from `get_queue` + events. Home keeps the service running; removing the app from recents cancels work and stops it. Rejected: option B (queue owned by a Kotlin service with its own database) | `[CONFIRMED]` | One implementation of the business rules, no second queue in Kotlin, and a small Kotlin surface. The Android spike validates Home/background behavior and orderly cancellation on removal from recents |
| D-24 | MP3 quality means **output bitrate**, not source-stream bitrate. Singles expose 320/256/192/128 kbps and always use the best source. Playlist Max uses 320 kbps; Min uses 128 kbps for the smallest output. | `[CONFIRMED]` | Predictable cross-site behaviour and honest UI terminology |
| D-25 | Zownload source code uses **GPL-3.0-or-later**. Desktop FFmpeg remains LGPL-compatible as decided in Gate 0B: build without `--enable-gpl` and `--enable-nonfree`, pin exact source, preserve licence/notices, publish corresponding source and build configuration with each release, and validate required codecs. Android Option A uses GPL-3.0 youtubedl-android and its GPL-configured FFmpeg, subject to full package/source and transitive-licence audit. | `[CONFIRMED]` | The desktop LGPL build rule remains in force, although the GPL repository licence no longer requires it; any change to that rule is an open owner decision. Legal review before the first public release is open |
| D-26 | Toolchains are selected and frozen in Gate 0A, not guessed in advance: start from then-current stable Tauri/Rust/Node/JDK/NDK/SDK, record exact versions, commit lockfiles/wrappers, and make CI use the same versions before feature work begins. | `[CONFIRMED]` | Reproducible builds without baking stale versions into planning before the scaffold exists |
| D-27 | Metadata mapping is fixed by FR-58 and validated against real MP3/MP4 outputs in Gate 0B. | `[CONFIRMED]` | Avoids platform/player-specific surprises after UI development |
| D-28 | URLs containing both a video and playlist parameter are single-item requests; only pure playlist URLs expand the playlist. | `[CONFIRMED]` | Prevents accidental bulk downloads |
| D-29 | Android v1 writes only to MediaStore Downloads and hides the custom-folder setting; SAF is deferred beyond v1. | `[CONFIRMED]` | Lower permission and lifecycle complexity for the first Android release |

## 12. Proposed architecture `[PROPOSAL]`

```
┌─────────────────────── React UI (src/) ───────────────────────┐
│ Header · Main (Input/Download states) · Queue · History · Settings │
│ talks ONLY through call()/on() from shared/contract.ts         │
└───────────────┬───────────────────────────────▲────────────────┘
        Tauri commands                   Tauri events
┌───────────────▼───────────────────────────────┴────────────────┐
│ Rust core (src-tauri/)                                          │
│  commands · queue manager · history DB · settings · zip writer  │
│  progress throttling · error mapping                            │
│                    │ trait Engine                               │
│   ┌────────────────┴───────────────┐                            │
│   │ DesktopEngine                  │ AndroidEngine              │
│   │ spawns sidecars from app data  │ calls Kotlin plugin        │
│   │ yt-dlp + ffmpeg + qjs          │ (youtubedl-android)        │
└───┴────────────────────────────────┴────────────────────────────┘
```

**Responsibilities**
- **UI:** presentation and state (Zustand). It never knows which engine is active.
- **Queue manager (Rust, shared):** owns the queue, runs one item at a time, expands playlists into entries, pause/resume/cancel, counters, zip packaging, history writes, event emission (throttled).
- **Engine (platform-specific):** `analyze(url)`, `download_entry(request, on_percent, cancel)`, engine info/update. Sketch (not yet in code):

```rust
#[async_trait]
trait Engine: Send + Sync {
    async fn analyze(&self, url: &str) -> Result<AnalyzeResult, AppError>;
    async fn download_entry(&self, req: EntryRequest,
        on_percent: &(dyn Fn(f32) + Send + Sync),
        cancel: CancellationToken) -> Result<SavedFile, AppError>;
    async fn update_info(&self) -> Result<EngineUpdateInfo, AppError>;
    async fn update(&self) -> Result<EngineUpdateInfo, AppError>;
}
// EntryRequest: url, format, quality, output target (directory on desktop, MediaStore on Android)
```

**Proposed repository layout**
```
zownload/
├─ AGENTS.md, PROJECT.md, opencode.json
├─ src/                      # React app (desktop + Android)
├─ shared/                   # contract.ts, i18n (en.json, es.json), constants
├─ src-tauri/
│  ├─ src/                   # contract.rs, commands, queue, history, zip, engine/{mod,desktop,android}.rs
│  ├─ binaries/              # sidecars named with target triple: yt-dlp, ffmpeg, qjs
│  └─ gen/android            # generated Android project
├─ plugins/ytdlp-android/    # Kotlin Tauri plugin wrapping youtubedl-android
├─ docs/                     # roadmap.md, ytdlp-commands.md
└─ .github/workflows/        # tauri-action build/release
```

**Android specifics (D-23, `[CONFIRMED]`):** Rust and the Kotlin plugin run in the **same process**. The foreground service does not run the work; it tells Android the process is important and shows the notification.

| Layer | Who owns it | Lifetime |
|---|---|---|
| WebView / Activity (React UI) | Disposable; rebuilds state from `get_queue` + events | Dies easily (screen closed, rotation, recycled) |
| Process (Rust core: queue, SQLite, zip) | **Rust is the source of truth** | Alive after Home while the foreground service runs; cancelled when removed from recents; can still be killed by the system |
| Foreground service (Kotlin) | Keepalive + notification only | Started when the queue has active work; stopped when idle or removed from recents |

- **Kotlin plugin (`plugins/ytdlp-android/`) contains only:** `AndroidEngine` (implements the Engine trait over youtubedl-android: `analyze`, `download_entry` with progress callbacks, cancel, engine update) and `KeepAliveService` (start/stop, update notification text and progress when Rust asks).
- **Progress path:** youtubedl-android callback → Kotlin plugin → Rust → throttle (≈5/s) → UI event and notification update.
- **Recovery:** queue state is written to SQLite on structural/status changes and periodic durable progress checkpoints; after process death, the app restores interrupted items as `paused` (FR-78, BR-15). Resuming continues from the `.part` file.
- **User lifecycle:** Home leaves the service and downloads running. Removing the app from recents first persists active items as `paused`, cancels engine work and stops the service (FR-81).
- **Time limit (Android 15+):** on `onTimeout`, Rust pauses the queue cleanly and the notification asks the user to open the app (FR-80).
- **Other Android items:** MediaStore Downloads output, one `arm64-v8a` APK, runtime yt-dlp update through the library.

## 13. Selected technologies and justification

| Technology | Status | Why |
|---|---|---|
| Tauri 2 | `[CONFIRMED]` | One codebase for Windows/macOS/Linux/Android; small installers; Rust core |
| Rust (core logic) | `[CONFIRMED]` (implied by Tauri) | Required by Tauri backend |
| React | `[CONFIRMED]` | Owner's skill |
| TypeScript, Vite | `[CONFIRMED]` | Type-safe contract; Tauri template; no SSR needed |
| Tailwind CSS (utility classes only; **no shadcn/ui**, no other component library) | `[CONFIRMED]` | Fast, responsive, one UI for desktop and phone. Components (cards, combo box, buttons, progress bar) are written by hand |
| Zustand | `[CONFIRMED]` | Simple store for queue/progress |
| yt-dlp | `[CONFIRMED]` | Broadest site support |
| LGPL-compatible ffmpeg build (no GPL/nonfree flags) | `[CONFIRMED]` | Audio extraction (mp3), merging, re-encoding, metadata/cover embedding; reproducible redistribution evidence required |
| Upstream QuickJS 2026-06-04, reproducibly built from official source | `[CONFIRMED]` | MIT-licensed JS runtime for YouTube; light; meets the performance floor and compiles for Android |
| Deno | `[CONFIRMED]` as fallback for desktop only | yt-dlp's recommended runtime but unavailable on Android |
| youtubedl-android + Kotlin Tauri plugin | `[CONFIRMED]` (pending spike) | Only realistic local engine on Android |
| SQLite via `rusqlite` (bundled SQLite, versioned migrations) | `[CONFIRMED]` | One Rust-owned store for history, queue, settings and persistent errors; no database capability exposed to the UI |
| Zip crate (store mode, streaming) | `[PROPOSAL]` | Avoid memory/double-storage |
| Tauri plugins: shell (desktop sidecars), dialog (desktop folder picker), updater (desktop), fs as needed | `[PROPOSAL]` | Standard Tauri 2 ecosystem; no store/SQL plugin because Rust owns SQLite directly |
| GitHub Actions + `tauri-action` | `[CONFIRMED]` | Builds and attaches all platform artifacts to a release |

## 14. Data model

### History (persisted) `[CONFIRMED]`
```sql
CREATE TABLE history (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  url         TEXT    NOT NULL,
  format      TEXT    NOT NULL,   -- 'mp3' | 'mp4'
  is_playlist INTEGER NOT NULL,   -- 0 | 1
  quality     TEXT    NOT NULL,   -- Quality as JSON, e.g. {"type":"video","height":720}
  title       TEXT,               -- display only
  UNIQUE (url, format, is_playlist, quality)
);
-- Newest first: ORDER BY id DESC. On repeat download: DELETE old row, INSERT new.
```
One playlist request creates one row. Duplicate `title` values are valid; only an identical `(url, format, is_playlist, quality)` request is deduplicated and moved to the top.

### Settings (persisted in SQLite) `[CONFIRMED]`
`{ language: "en"|"es", zipPlaylists: boolean, downloadDir: string|null }` (`null` = system Downloads; ignored on Android for now).
```sql
CREATE TABLE settings (
  id            INTEGER PRIMARY KEY CHECK (id = 1),
  language      TEXT    NOT NULL, -- 'en' | 'es'
  zip_playlists INTEGER NOT NULL, -- 0 | 1
  download_dir  TEXT              -- null = system Downloads
);
```
Rust owns this table through `rusqlite`; React reads and writes it only through `get_settings` / `set_settings`.

### Engine manifest `<app_data>/engine/engine.json` `[PROPOSAL]`
```json
{
  "ytDlp": { "version": "2026.09.10", "source": "updated", "state": "probation", "installedAt": "2026-10-06T10:00:00Z" },
  "baselineAppVersion": "1.0.0",
  "failedVersions": ["2026.08.01"],
  "lastUpdateCheck": "2026-10-06T10:00:00Z"
}
```
`source`: `"bundled"` | `"updated"`. `state`: `"probation"` | `"good"`. `baselineAppVersion` is the app version whose baseline was last installed; if it differs from the running app version, step A runs again (FR-74).

### Queue (persisted) `[CONFIRMED]` that it persists (D-23); schema `[PROPOSAL]`
`QueueItem { id (uuid), request, title|null, thumbnail|null, status, progress, error|null }`, written on structural/status changes and periodic durable progress checkpoints (less often than UI events). On start, items in `analyzing`/`downloading`/`postProcessing`/`packaging` are restored as `paused`. Terminal items are removed after history/error-notification persistence.
```sql
CREATE TABLE queue_items (
  id         TEXT    PRIMARY KEY,   -- uuid
  position   INTEGER NOT NULL,      -- order in the queue
  request    TEXT    NOT NULL,      -- DownloadRequest as JSON
  title      TEXT,
  thumbnail  TEXT,
  status     TEXT    NOT NULL,      -- ItemStatus
  progress   TEXT    NOT NULL,      -- Progress as JSON (done/failed/total, current entry index)
  error      TEXT                   -- AppError as JSON, nullable
);
```
For playlists, also persist the list of entries and the index of the current one so that resume continues from the right entry `[PROPOSAL]`.

### Error notifications (persisted) `[CONFIRMED]`
```sql
CREATE TABLE error_notifications (
  id     TEXT PRIMARY KEY, -- queue item id
  title  TEXT,
  error  TEXT NOT NULL     -- AppError as JSON
);
```
Failed queue items are removed only after this row is committed. The UI loads notifications at startup and keeps each one visible until `dismiss_error_notification` succeeds.

### Core types (from the contract)
- `Format`: `"mp3" | "mp4"`.
- `Quality`: `{type:"max"} | {type:"min"} | {type:"video", height} | {type:"audio", bitrate}`. Playlist uses only max/min; single uses video (mp4) or audio (mp3).
- `DownloadRequest { url, format, quality, isPlaylist }`.
- `ItemStatus`: `analyzing | queued | downloading | postProcessing | paused | packaging | done | failed`. `done`/`failed` are transient.
- `Progress`: single `{percent}` or playlist `{done, failed, total, currentTitle, currentPercent}`.

## 15. Interfaces / API `[CONFIRMED]` (contract v1 baseline)

Authoritative definitions: `shared/contract.ts` and `src-tauri/src/contract.rs`. JSON is camelCase. Tauri maps camelCase JS args to snake_case Rust params. Every command may reject with `AppError`.

### Commands (UI → Rust)
| Command | Args | Returns | Notes |
|---|---|---|---|
| `analyze_url` | `{ url }` | `AnalyzeResult` | Returns `videoHeights` and fixed `audioOutputBitrates` for singles; the UI picks by format |
| `enqueue_download` | `{ request: DownloadRequest }` | queue item id (string) | Also used for redownload |
| `pause_download` | `{ id }` | void | |
| `resume_download` | `{ id }` | void | |
| `remove_download` | `{ id }` | void | Cancel + remove from queue |
| `get_queue` | `{}` | `QueueItem[]` | |
| `get_history` | `{}` | `HistoryEntry[]` | Newest first |
| `delete_history_entry` | `{ id: number }` | void | |
| `clear_history` | `{}` | void | |
| `get_error_notifications` | `{}` | `ErrorNotification[]` | Persisted until dismissed |
| `dismiss_error_notification` | `{ id: string }` | void | Deletes one notification |
| `get_settings` / `set_settings` | `{}` / `{ settings }` | `Settings` / void | |
| `engine_check_update` | `{}` | `EngineUpdateInfo` | `{ current, latest, updateAvailable }` |
| `engine_update` | `{}` | `EngineUpdateInfo` | |

### Events (Rust → UI)
| Event | Payload | Notes |
|---|---|---|
| `queue:item-updated` | `QueueItem` | Full snapshot, throttled ≈5/s per item; insert if id is new |
| `queue:item-removed` | `string` (id) | |
| `history:changed` | `null` | UI refetches `get_history` |
| `error-notifications:changed` | `null` | UI refetches `get_error_notifications` |

### `AnalyzeResult`
- `single`: `url, title, author, thumbnail|null, durationSec, site, videoHeights[], audioOutputBitrates[]`; MP3 presets are `[320,256,192,128]` and mean output bitrate.
- `playlist`: `url, title, author, thumbnail|null, site, itemCount, itemTitles[]`

### Typed helpers
`shared/contract.ts` exports `call(cmd, args)` and `on(event, handler)` wrapping Tauri `invoke`/`listen`. For the mock-engine phase, make these swappable (the contract file imports `@tauri-apps/api`, so it is not Tauri-free).

### Gaps in the contract `[PENDING]`
- Geo-blocked and age-restricted are currently grouped as `private_or_restricted`; whether to split them is pending.
- No way to expose per-entry failure reasons for a playlist (only counters).
- Restored queue items reuse the `paused` status (D-23); no new status or command is needed. Persistence is internal to Rust.
- No command to pick a download folder (use the Tauri dialog plugin from the UI) or to get app-update info (Tauri updater plugin on desktop; GitHub API on Android).

## 16. Error handling

**Analysis errors (Input state):** red message below the input, text from i18n key `errors.<code>`, shown in the current language. `[CONFIRMED]`

| `ErrorCode` | When (yt-dlp stderr patterns to be validated) | Status |
|---|---|---|
| `invalid_url` | Not a valid URL | `[PROPOSAL]` |
| `unsupported_site` | "Unsupported URL" | `[PROPOSAL]` |
| `private_or_restricted` | Private, members-only, age-restricted, geo-blocked | `[PROPOSAL]` |
| `not_found` | Removed/unavailable video | `[PROPOSAL]` |
| `no_internet` | Network failure | `[PROPOSAL]` |
| `disk_full` | Destination or temporary storage has insufficient free space | `[CONFIRMED]` |
| `permission_denied` | The app cannot create, write, finalize or remove required output | `[CONFIRMED]` |
| `engine_missing` | yt-dlp/ffmpeg/QuickJS missing or broken | `[PROPOSAL]` |
| `unknown` | Anything else; keep raw text in `detail` for logs | `[PROPOSAL]` |

**Download errors:** a failed single item gets transient status `failed` and `error` set. A playlist continues past failed entries and ends transient `done` (some failed) or `failed` (all failed). Before queue removal, Rust commits a persistent `ErrorNotification`; the UI keeps it visible until dismissed. Disk-full and permission errors cancel the complete job and terminate all active child processes. `[CONFIRMED]`

**Engine problems:** a failed or invalid yt-dlp update leaves the current copy untouched (FR-72, BR-17a). An update that proves broken is rolled back by copying the bundled baseline into app data again (BR-17b, section 8.5-D); the baseline itself failing its health check reports `engine_missing`. Site and network errors reported by yt-dlp never trigger a rollback (BR-17c). `[CONFIRMED]` fallback to baseline / `[PROPOSAL]` details. Disk full, output permissions, filename collisions and interrupted-app behaviour are defined by FR-56, FR-57 and FR-81.

## 17. Security `[PROPOSAL]` (none of this was discussed in detail with the owner)

- **No shell injection:** spawn processes with an argument array, never a shell string; allow only the bundled sidecars in Tauri's shell/capability scope.
- **Option injection:** validate that the URL is `http`/`https`; pass it after `--` so it cannot be read as a yt-dlp option; never enable `--exec` or similar.
- **Filesystem:** sanitize filenames (e.g. Windows-safe), prevent path traversal in zip entry names, write only inside the chosen download directory.
- **Engine updates:** download only from yt-dlp's official GitHub releases over HTTPS and verify the checksum (use a release signature too if available). Downloading and running an executable is the main trust boundary; keep it narrow. Never execute a downloaded binary before its checksum is verified (BR-16).
- **App updates:** Tauri updater requires its own signing keypair; keep the private key out of the repo (GitHub Actions secret). Android: sign every APK with the same keystore, keep it backed up and out of the repo.
- **Tauri hardening:** minimal capabilities/permissions, strict CSP, no remote content in the webview.
- **Privacy:** no telemetry; history and settings stay on the device; logs local only.
- **Licensing/compliance:** Zownload is GPL-3.0-or-later. Keep desktop FFmpeg LGPL-compatible (`--enable-gpl` and `--enable-nonfree` forbidden) under the Gate 0B build rule; Android Option A may use the tagged GPL-configured FFmpeg bundled by youtubedl-android, subject to package/source audit. Preserve third-party notices, publish exact corresponding FFmpeg/QuickJS and Android package sources, checksums and build configuration with releases, and audit all transitive dependency licences before the first release. Legal review before the first public release remains open. `[CONFIRMED]`
- **Legal notice:** README disclaimer about respecting site terms and copyright.

## 18. Testing `[PROPOSAL]`

1. **yt-dlp CLI validation (first):** run by hand the four playlist combinations, single mp3/mp4 with chosen quality, metadata + thumbnail embedding for mp3 and mp4, and `--js-runtimes quickjs:<path>` on a real YouTube playlist. Save working commands to `docs/ytdlp-commands.md`.
2. **Mock engine:** a fake implementation of the contract so the full UI (all states, errors, pause, "10 correct, 5 failed") can be built and tested without Rust.
3. **Unit tests (Rust):** queue state machine (pause/resume/remove, post-processing pause guard, terminal auto-removal, counters, partial failures), history uniqueness/ordering, persistent error notifications, video-quality fallback, error mapping from yt-dlp stderr, bounded-storage ZIP streaming, shutdown/process-tree cleanup.
4. **Frontend tests (Vitest + Testing Library):** components against the mock engine; persistent error notification and dismissal; immediate return to Input after enqueue; i18n key completeness for en/es.
5. **Smoke test in CI:** one short public YouTube video and a tiny playlist (YouTube breaks often); marked non-blocking if flaky.
6. **Manual per-artifact install and update tests** (exactly the artifacts of section 8.6, nothing else):
   - Windows: NSIS `.exe` and WiX `.msi`; clean install, upgrade and updater flow from the previous version for both.
   - macOS: both `.dmg` (Apple Silicon and Intel hardware or VM); update from the previous version.
   - Linux **AppImage**: Ubuntu 24.04 (with and without `libfuse2`) and one non-Debian distro (e.g. Fedora or Arch); update from the previous version.
   - Linux **`.deb`**: Ubuntu LTS and Debian stable; install, then update from the previous version (check the administrator prompt). If the `.deb` updater is unreliable, switch to the download-link fallback of FR-75.
   - Android: real device; update over an older APK signed with the same key.
7. **Android spike acceptance and lifecycle tests (real device):** AC-30 to AC-35. Validate both Home/background continuation and cancellation when removed from recents.
8. **Engine manager tests (desktop, automated):** use a tiny stub executable that imitates yt-dlp to simulate: good new version; checksum mismatch; non-executable file; wrong `--version` output; crash on startup; exit code ≠ 0 without an `ERROR:` line; invalid JSON on `analyze`; normal `ERROR:` lines (unavailable video, unsupported URL, HTTP 403); a swap requested while a process is running (including replacing a running `.exe` on Windows); baseline re-copy after fallback; refresh of ffmpeg/QuickJS after an app update; first launch with an empty app data folder.

## 19. Acceptance criteria

Derived from the confirmed requirements; refine with the owner.

**UI**
- AC-01: Header is always visible; shows logo, "zownload", language button, settings button, in that order.
- AC-02: Invalid/unsupported URL shows a red, translated error under the input and stays in Input state.
- AC-03: A valid single URL shows the download card with thumbnail, title, author, duration, site, a quality combo box and a Download button.
- AC-04: A valid playlist URL shows item count, a Max/Min combo box, and a list card of element names.
- AC-05: The back arrow returns to Input state.
- AC-06: Empty queue shows "No active downloads"; empty history shows "No history yet".
- AC-07: A paused item shows "Paused"; resuming continues from the partial file.
- AC-08: Playlist items show `done/total`; with failures they show "N correct, M failed".
- AC-09: Redownload from history puts the item in the queue without opening the download card.
- AC-10: All strings, including errors, exist in English and Spanish and switch immediately.
- AC-18: Pressing Download immediately restores a cleared Input card. Successful and failed terminal items leave the queue automatically.
- AC-19: A failed item creates an error notification that survives UI recreation/app restart and remains visible until dismissed.

**Downloads**
- AC-11: mp3/mp4 files open in common players and contain the FR-58 mapping: title; artist/creator/uploader fallback; playlist title as album only for playlist entries; JPEG-compatible cover art.
- AC-12: Playlist mp4 Max = best video + best audio; mp4 Min = lowest video + best audio; mp3 Max = best source encoded at 320 kbps; mp3 Min = best source encoded at 128 kbps. Single MP3 exposes 320/256/192/128 kbps output presets.
- AC-13: Zip on → one `.zip` with the playlist's files, built using at most the partial ZIP plus one temporary media file; zip off → individual files named after each element, downloaded sequentially.
- AC-14: One failing element does not stop the playlist.
- AC-15: Desktop files use Downloads by default or the folder chosen in Settings. Android files always appear in public Downloads through MediaStore and no folder selector is shown.
- AC-16: Existing output names are never overwritten; collisions produce `name (1).ext`, `name (2).ext`, etc., including ZIP entries.
- AC-17: Disk-full or permission-denied cancels the job and all active child processes, cleans incomplete output where safe, removes the queue item and leaves a persistent translated error notification.

**Distribution and updates**
- AC-20: A user installs one OS/architecture combination with one appropriate downloaded artifact (plus the documented unsigned-app warning steps), with no terminal or dependency downloads.
- AC-21: The Settings update button updates yt-dlp when a newer release exists and shows the outcome (updated, already current, failed).
- AC-22: Desktop app detects a new GitHub release and installs it via the updater; Android shows "New version available" with the APK link.
- AC-23: CI builds exactly the artifacts of section 8.6: Windows NSIS `.exe` + WiX `.msi`; two macOS `.dmg`; Linux `.AppImage` + `.deb`; one Android `arm64-v8a` `.apk`; updater `latest.json`, signatures and macOS `.app.tar.gz`. No additional installer format is published.
- AC-24: A downloaded yt-dlp whose checksum does not match, or that is not executable, or whose `--version` is wrong, is rejected; the working copy is untouched and the failure is shown.
- AC-25: If the engine breaks after a swap (simulated by a crashing stub), the app copies the bundled baseline into app data again, executes it **from app data**, downloads work again, the broken version is recorded in `failedVersions` and is not retried automatically, and Settings explains what happened.
- AC-26: Ordinary site/network errors reported by yt-dlp (unavailable video, unsupported URL, HTTP errors, no internet) never trigger a fallback.
- AC-27: The swap never happens while a yt-dlp process is running; it waits until the queue is idle or the next app start.
- AC-28: After an app update, ffmpeg and QuickJS in app data match the new bundle; yt-dlp is replaced only if the bundled version is newer.
- AC-29: Closing the desktop window during active work kills the complete process tree, leaves no background process and restores interrupted queue items as `paused` on the next launch.
- AC-36: Release compliance evidence contains the GPL-3.0-or-later licence, all third-party notices, exact desktop FFmpeg/QuickJS and Android package versions and checksums, reproducible build commands, and corresponding source archives; the desktop FFmpeg configuration contains neither `--enable-gpl` nor `--enable-nonfree`, while Android GPL FFmpeg and all transitive dependencies receive a full licence/source audit before the first release.

**Android**
- AC-30 (spike): a Tauri Android build calls a Kotlin plugin that downloads one YouTube URL as MP3 (with the JS runtime working) and saves it to Downloads on a real device.
- AC-31 (Home button): start a download and press Home; it keeps going for several minutes, with the foreground service notification visible and progress updating.
- AC-32 (remove from recents): remove the app from recents during a download; active work is cancelled, the foreground-service notification disappears, no child process remains, and reopening restores the item as `paused`.
- AC-33 (process death): kill the process with adb during a download; reopen the app; the queue is restored, the interrupted item shows "Paused", and Continue resumes from the `.part` file.
- AC-34 (WebView recreation): rotate, lock/unlock, or recreate the Activity during a download; the UI reconnects through `get_queue` + events and shows the correct state.
- AC-35 (Android 15 timeout): with the foreground-service timeout enabled for testing on an Android 15 device, the queue pauses cleanly, the notification explains it, and nothing crashes or is lost.

## 20. Open questions and pending decisions

| # | Question | Needed from | Default assumption until decided |
|---|---|---|---|
| 1 | Does youtubedl-android ship or support a JS runtime (QuickJS) for YouTube? If not, bundle QuickJS as an `.so` in `jniLibs`. | Android spike | Assume it must be bundled |
| 2 | Is pinned QuickJS fast enough for YouTube on desktop? Fallback: Deno (desktop only). | Gate 0B real-playlist benchmark | QuickJS everywhere |
| 3 | ~~QuickJS source and variant.~~ **Resolved:** upstream QuickJS 2026-06-04, built reproducibly from official source for each target with checksums/build commands recorded (D-07). | Gate 0A/0C verification | — |
| 4 | ~~Android download folder.~~ **Resolved:** MediaStore public Downloads only in v1; hide/ignore the folder selector; SAF is out of scope (D-29). | — | — |
| 5 | ~~ZIP strategy and pause during packaging.~~ **Resolved:** stream to a pending MediaStore destination when supported, retain only one temporary media file, and disable pause during `packaging`. The Android spike must validate direct writing; if the API/library cannot support it, document and test the cache-copy fallback. | Android spike | Direct MediaStore writing |
| 6 | ~~Main area after pressing Download.~~ **Resolved:** return immediately to a cleared Input state (FR-26). | — | — |
| 7 | ~~Finished queue items.~~ **Resolved:** remove automatically after history or persistent error notification is committed (BR-11). | — | — |
| 8 | ~~Settings update-button scope.~~ **Resolved:** the Settings button updates yt-dlp only; app updates use an automatic daily check and a separate action shown only when available (FR-64). | — | — |
| 9 | ~~Should the queue persist across app restarts?~~ **Resolved:** yes, see D-23, FR-78, BR-15. | — | Persisted; interrupted items restored as `paused` |
| 10 | Developer information content (name, links, license/contact). | Owner | Placeholder |
| 11 | ~~Project/ffmpeg licensing.~~ **Resolved:** Zownload GPL-3.0-or-later; retain the Gate 0B LGPL-compatible desktop FFmpeg build without GPL/nonfree flags and publish notices, exact source and build configuration (D-25). **Open:** review whether to retain that desktop build rule despite the GPL repository licence; complete Android GPL package/source and transitive-licence audit and legal review before first release. | Gate 0B desktop evidence; Gate 0C Android evidence and release review | — |
| 12 | ~~Metadata mapping.~~ **Resolved:** title, artist/creator/uploader fallback, playlist title as album, best thumbnail converted to JPEG as needed (FR-58). | Gate 0B verification | — |
| 13 | ~~Meaning of MP3 quality.~~ **Resolved:** MP3 always uses the best source; single presets are 320/256/192/128 kbps, playlist Max = 320 and Min = 128 (D-24). Commands still require CLI validation. | CLI test | As defined in D-24 |
| 14 | ~~Video URL containing a playlist parameter.~~ **Resolved:** treat as single; only pure playlist URLs expand playlists (D-28). | — | — |
| 15 | Mp4 audio compatibility: re-encode non-AAC audio to AAC (BR-13). | Gate 0B CLI test | Yes, when needed |
| 16 | ~~Disk-full and permission-denied errors.~~ **Resolved:** typed codes and persistent notifications (FR-57, BR-20). Still pending: whether to split geo/age restrictions and expose per-entry playlist failure details. | Owner/later design | Keep grouped restrictions and counters only for v1 |
| 17 | ~~Filename collisions.~~ **Resolved:** sanitize and append a counter (BR-19). Still pending: explicit limits/behaviour for very large playlists and live streams. | Owner | No artificial playlist limit; live streams out of v1 |
| 18 | Confirm the proposed minimum OS matrix in NFR-09 against the pinned scaffold and available test environments. | Gate 0A | Windows 10 1803+, macOS 10.15+, Android API 24 |
| 19 | Apple Developer account and notarization (removes the Gatekeeper step). | Owner | Not now |
| 20 | Layout of cards on mobile; exact UI copy for Spanish. | Stage 1A owner checkpoint | Single column; Spanish translations drafted with the UI |
| 21 | Accessibility baseline and final app logo/icon assets. Telemetry is already none. | Stage 1A baseline / Stage 6A final | Keyboard, screen reader and contrast baseline; placeholder icon until final polish |
| 22 | ~~Which toolchain versions to pin.~~ **Resolved process:** Gate 0A selects current stable compatible versions, records them, commits lockfiles/wrappers and proves local/CI reproducibility before feature work (D-26). Exact resulting numbers are Gate 0A evidence. | Gate 0A | — |
| 23 | ~~Linux artifacts for v1.~~ **Resolved:** AppImage + `.deb` (D-22). | — | — |
| 24 | Does the `.deb` auto-update (supported by updater 2.13.0, needs admin rights) work reliably enough? | Stage 4A test | If not, use the download-link fallback (FR-75) |
| 25 | ~~Android ABI list.~~ **Resolved:** `arm64-v8a` only in v1 (D-22). | Gate 0C validates device compatibility | — |
| 26 | ~~Windows installer formats.~~ **Resolved:** NSIS `.exe` and WiX `.msi`; `.exe` is recommended to ordinary users (D-22). | — | — |
| 27 | ~~Behaviour when removed from Android recents.~~ **Resolved:** cancel active work, stop the foreground service and restore interrupted items as `paused` on next launch (FR-81, AC-32). | — | — |
| 28 | When the OS restarts the foreground service in a fresh process with no UI, does Tauri start the Rust core and the queue restoration, or only when the user opens the app? | Android spike | Restore only when the app is opened; never auto-resume (BR-15) |
| 29 | Foreground service type to declare on Android (`dataSync` is the usual choice, with the 6 h / 24 h limit) and whether the notification has Pause/Stop buttons. | Gate 0C | `dataSync`; notification with progress only, no buttons in v1 |
| 30 | Keep a "previous known-good" yt-dlp copy in addition to the baseline, so a rollback does not jump back to an old baseline? | Stage 2D owner checkpoint | No: baseline only (simpler; matches the confirmed spec) |
| 31 | Android: can youtubedl-android revert to its bundled yt-dlp (e.g. clear its downloaded copy and re-initialize)? | Android spike | Assume yes; if not, no rollback on Android in v1 |
| 32 | Validate the breakage heuristics (BR-17) against real yt-dlp behaviour (exit codes, `ERROR:` line format, startup failures of the standalone builds); tune the 10 s timeout and probation length. Also check whether yt-dlp publishes a signature for its checksum file and verify it. | Gate 0B evidence, finalized in Stage 2D | As written in BR-17; checksum only |
| 33 | ~~Update channel.~~ **Resolved:** stable releases only for both the app and yt-dlp; no nightly channel in v1. | — | — |

---

## Appendix A — Confirmed roadmap `[CONFIRMED]`

### Delivery rule

This is **not** a big-bang implementation. Every stage is one reviewable work unit and ends with recorded evidence. Do not begin the next stage until:

1. its implementation and focused tests pass;
2. the documented manual scenario passes where applicable;
3. the result is reviewed against the listed acceptance criteria;
4. the owner explicitly accepts the checkpoint.

A failed Gate 0 result stops the roadmap: document the evidence and revise the affected decision before continuing. Later-stage failures remain inside that stage; do not hide them by starting subsequent work.

### Phase 0 — Feasibility gates

| Gate | Deliverable (strict scope) | Required verification / evidence | Exit criterion |
|---|---|---|---|
| **0A — Reproducible foundation** | Follow `docs/gates/gate-0a.md`. Scaffold Tauri 2 + React/TypeScript/Vite; integrate both contract files; configure Tailwind and Zustand only; initialize Android project; select and pin exact Tauri/Rust/Node/package-manager/JDK/NDK/SDK versions; commit lockfiles/wrappers; add initial licence (updated to GPL-3.0-or-later in 0C-01B), third-party notice template, `AGENTS.md`, `opencode.json`, and a CI skeleton. Preserve and validate the `docs/design/README.md` inventory, but implement no production UI. | Record all tool versions and setup commands in `docs/toolchain.md`; clean checkout builds/type-checks on Windows; Rust contract compiles; frontend type-checks; Android skeleton compiles; CI repeats the checks. Verify TypeScript/Rust contract JSON fixtures match and every indexed design path exists. | Reproducible empty application and contracts are accepted. Toolchain/version uncertainty is closed before feature work; design references are intact and remain unimplemented. |
| **0B — Real CLI and licensing proof** | Obtain pinned yt-dlp; reproducibly build upstream QuickJS 2026-06-04 and LGPL-compatible ffmpeg under the retained desktop build rule; write the exact command matrix in `docs/ytdlp-commands.md`. Test singles/playlists, mp3 presets, mp4 Max/Min, metadata/cover conversion, AAC compatibility, partial resume, progress output and representative errors. No Tauri engine integration. | Save command output and produced-file inspection results; play MP3/MP4 in common players; inspect metadata; verify ffmpeg configuration excludes GPL/nonfree flags and required MP3/AAC features work; record source URLs, versions and SHA-256 checksums. | Every required CLI capability works with redistributable binaries. If not, stop and revise formats/licensing/engine assumptions. |
| **0C — Android feasibility spike** | Time-box 1–2 days: Tauri Android app → minimal Kotlin plugin → youtubedl-android with pinned QuickJS 2026-06-04 and matched yt-dlp/ejs → download one real YouTube URL as MP3 to MediaStore Downloads on an `arm64-v8a` device. Prototype foreground service, Home continuation, removal-from-recents cancellation, process-death recovery, direct pending MediaStore ZIP output, and this project's verified update/rollback path (0C-14). No full UI. | AC-30..35 and JS runtime/version and update/rollback behavior must be proved on a real device; capture logs and resulting media; prove no orphan process after recents removal; verify restored queue state and direct ZIP writing; inventory GPL packages, corresponding source, build inputs and notices. None of these Android runtime claims is device-verified yet. | Local Android engine feasibility is pending device proof and GPL release evidence. Any failed hard requirement stops Android implementation and requires an explicit architecture decision. |

### Phase 1 — Complete UI against a mock engine

| Stage | Deliverable | Verification / checkpoint |
|---|---|---|
| **1A — App shell** | Derive reusable visual tokens from `docs/design/`; implement header, responsive desktop/mobile layout, navigation/settings shell, handcrafted Tailwind primitives and English/Spanish infrastructure. Missing components may be designed consistently with the confirmed references. | Component tests for layout/accessibility basics and complete en/es keys; visual comparison at the reference dimensions and intermediate responsive widths. |
| **1B — Analyze and enqueue flow** | Implement the indexed input/analyzing/single/playlist references, quality controls, playlist title list and return to cleared Input after enqueue. Create missing states consistently. Mock only. | AC-01..05, AC-10 and AC-18 against deterministic mock scenarios plus visual comparison with the indexed images. |
| **1C — Queue, history and notifications** | Implement indexed progress components and create the missing Queue states including `postProcessing`; pause rules; history/redownload; settings; persistent error-notification UI in the same visual language. Mock only. | AC-06..09 and AC-19; UI recreation/refetch tests; visual consistency review; no Rust engine required. |

### Phase 2 — Windows core, one vertical slice at a time

| Stage | Deliverable | Verification / checkpoint |
|---|---|---|
| **2A — Persistence and command boundary** | `rusqlite` migrations/repositories for settings, history, queue and error notifications; implement contract commands/events without real downloads. | Migration, uniqueness, ordering, recovery and contract serialization tests; UI works against Rust persistence. |
| **2B — Desktop engine bootstrap and analysis** | App-data engine copies, health checks, sidecar process supervision, URL analysis and typed error mapping. | Stub-engine tests plus real single/playlist analysis; process-tree cleanup test on window close. |
| **2C — Single downloads and queue lifecycle** | Single MP3/MP4, progress throttling, sequential queue, pause/resume/remove, ffmpeg `postProcessing`, metadata, durable recovery. | AC-07, AC-11, AC-12, AC-15..19 and AC-29 for single-item scenarios. |
| **2D — Engine updater** | Daily/manual yt-dlp checks, staging/checksum/probation/fallback and stable-channel app-update detection. | AC-21 and AC-24..28 using the stub engine before any release packaging. |

### Phase 3 — Windows playlists and distributable release

| Stage | Deliverable | Verification / checkpoint |
|---|---|---|
| **3A — Sequential playlists** | Per-entry execution, Max/Min matrix, counters, partial failures, one history row and durable resume index. | AC-04, AC-08, AC-12 and AC-14 with tiny and mixed-failure playlists. |
| **3B — ZIP and filesystem resilience** | Bounded-storage ZIP pipeline, numbered collisions, disk/permission failures and cleanup. | AC-13, AC-16 and AC-17; measure that only the partial ZIP plus current item coexist. |
| **3C — Windows release** | Signed updater artifacts plus unsigned OS installers: NSIS `.exe` and WiX `.msi`; GitHub release workflow and install/update documentation. | Clean install, upgrade, uninstall and updater tests for both formats; AC-20, AC-22, AC-23 and AC-36. |

### Phase 4 — Linux and macOS ports

| Stage | Deliverable | Verification / checkpoint |
|---|---|---|
| **4A — Linux runtime** | Linux sidecars, execute permissions and platform paths; AppImage and `.deb`. | Full download smoke tests; clean install/update on the distributions in section 18; `.deb` fallback link if updater is unreliable. |
| **4B — macOS runtime** | arm64 and x86_64 sidecars; two `.dmg`; updater `.app.tar.gz`; unsigned Gatekeeper documentation. | Real/virtual hardware smoke tests for both architectures, install/update flow and process cleanup. |

### Phase 5 — Production Android

| Stage | Deliverable | Verification / checkpoint |
|---|---|---|
| **5A — Engine adapter** | Production Kotlin plugin and Rust `AndroidEngine`; queue/history/settings integration using the already validated spike path. | Contract tests plus single and playlist downloads on a real ARM64 device. |
| **5B — Storage and lifecycle** | MediaStore individual/ZIP output, foreground service/notification, Home continuation, recents cancellation, timeout and recovery. | Repeat AC-31..35 as release tests; large-playlist storage test. |
| **5C — Android release** | Signed `arm64-v8a` APK, stable GitHub release check and upgrade over an older APK signed with the same keystore. | Clean install and update test; keystore backup procedure verified; no AAB or extra ABI generated. |

### Phase 6 — Release hardening

| Stage | Deliverable | Verification / checkpoint |
|---|---|---|
| **6A — Quality** | Accessibility baseline, local diagnostics/log rotation, performance checks, final translations and visual assets. | Keyboard/screen-reader/contrast pass; long queue/playlist test; no telemetry. |
| **6B — Release rehearsal** | README install warnings/screenshots, legal notices/source links, support/troubleshooting docs and one full GitHub prerelease across all targets. | Artifact allowlist exactly matches section 8.6; install/update checklist passes per artifact; owner approves v1 release. |

## Appendix B — yt-dlp starting-point commands `[PROPOSAL]` (UNVERIFIED; must be tested in Gate 0B)

- Analyze single: `yt-dlp --dump-single-json --no-playlist --skip-download <url>`
- Analyze playlist: `yt-dlp --dump-single-json --flat-playlist <url>` (a playlist has `_type == "playlist"`)
- mp4 Max: `-f "bv*+ba/b" --merge-output-format mp4`
- mp4 Min (min video + max audio): `-f "wv*+ba/w" --merge-output-format mp4`
- mp4 single at height H: `-f "bv*[height<=H]+ba/b[height<=H]"`
- mp3 playlist Max: `-f "ba/b" -x --audio-format mp3 --audio-quality 320K`
- mp3 playlist Min: `-f "ba/b" -x --audio-format mp3 --audio-quality 128K`
- mp3 single at output bitrate B: `-f "ba/b" -x --audio-format mp3 --audio-quality <B>K` where B is 320/256/192/128
- Always: `--embed-metadata --embed-thumbnail` (may need `--convert-thumbnails jpg`), `-o "<dir>/%(title)s.%(ext)s"`, `--ffmpeg-location <path>`, `--js-runtimes quickjs:<path>`, `--newline` plus a progress template for parsing, `--` before the URL, `--no-playlist` for single items.

## Appendix C — JS runtime research notes (verified during planning, re-verify before relying)

- Since yt-dlp **2025.11.12**, full YouTube support needs an **external JavaScript runtime** and the **yt-dlp-ejs** component. It only affects YouTube. Each yt-dlp release is pinned to a specific ejs version; the official standalone binaries already include it.
- Supported runtimes: Deno (recommended; the only one enabled by default), Node, Bun, QuickJS, QuickJS-NG. Others are enabled with `--js-runtimes RUNTIME[:PATH]`.
- Minimum versions for ejs: Deno ≥ 2.3, Node ≥ 22, QuickJS ≥ 2023-12-9, any QuickJS-NG. For acceptable speed use QuickJS ≥ 2025-4-26 or QuickJS-NG ≥ 0.12.0 (older builds can take minutes). Upstream QuickJS is the one recommended over QuickJS-NG for performance. QuickJS runs scripts from temporary files rather than stdin, so the cache/temp directory must be writable.
- **Deno on Android:** no official build; only community cross-compiles of Deno ≤ 1.36, some crashing at runtime. Not viable (ejs needs Deno ≥ 2.3).
- youtubedl-android 0.18.1 source audit: tagged Kotlin passes `--js-runtimes quickjs:<nativeLibraryDir>/libqjs.so` and sets a writable `TMPDIR`, but execution of the pinned QuickJS 2026-06-04 and matched yt-dlp/ejs on a device is UNVERIFIED. Its tagged updater has no checksum check, active-work exclusion or post-acceptance rollback; this project must implement and device-verify that path in 0C-14.

## Appendix D — Glossary

- **Sidecar:** external binary bundled with a Tauri app and launched from Rust.
- **ejs / yt-dlp-ejs:** JavaScript solver scripts yt-dlp runs inside a JS runtime to solve YouTube's challenges.
- **MediaStore / SAF:** Android APIs for saving to shared storage under scoped storage.
- **Baseline engine:** the yt-dlp copy shipped inside the installer, used on first launch and as a fallback.
