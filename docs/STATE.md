# Zownload state

## Current checkpoint and next task

- **Checkpoint (2026-10-29):** The owner accepted Gate 2D and authorized Gate 3A planning. See the [Gate 2D checkpoint](gates/evidence/2d/checkpoint.md).
- **Next task:** 3A-04 — connect the stored playlist snapshot and entry worker to queue lifecycle, counters, partial-failure continuation, pause/resume, and one History row. Start it in a fresh session after reviewing the combined 3A-02/03 PR.

## Current gate 3A completions

- Completed 3A-01: Planned sequential playlist work and recorded the resume-state and ZIP boundary decisions; commit `4d6c2c5`; [plan evidence](gates/gate-3a.md). Verification is identified as V0 there.
- Completed 3A-02: Added private playlist snapshots, ZIP preference capture, and durable index/counter transactions; commit `2549665`; [evidence](gates/evidence/3a/3a-02.md). V1 passed.
- Completed 3A-03: Added per-entry Max/Min worker, playlist album metadata, and collision-safe outputs; commit `414c068`; [evidence](gates/evidence/3a/3a-03.md). V1 and focused CLI test passed.

## Accepted gates

- 0A — accepted 2026-10-18; [checkpoint record](gates/gate-0a.md).
- 0B — accepted 2026-10-20; [checkpoint](gates/evidence/0b/checkpoint.md).
- 0C — accepted 2026-10-21 for local technical feasibility only; [checkpoint](gates/evidence/0c/checkpoint.md).
- 1A — accepted 2026-10-22; [checkpoint](gates/evidence/1a/checkpoint.md).
- 1B — accepted 2026-10-23; [checkpoint](gates/evidence/1b/checkpoint.md).
- 1C — accepted 2026-10-24; [checkpoint](gates/evidence/1c/checkpoint.md).
- 2A — accepted 2026-10-25; [checkpoint](gates/evidence/2a/checkpoint.md).
- 2B — accepted 2026-10-26; [checkpoint](gates/evidence/2b/checkpoint.md).
- 2C — accepted 2026-10-28; [checkpoint](gates/evidence/2c/checkpoint.md).
- 2D — accepted 2026-10-29; [checkpoint](gates/evidence/2d/checkpoint.md).

## Standing decisions

- **Authority and licensing:** `shared/contract.ts` and `src-tauri/src/contract.rs` govern exchanged fields/types; `PROJECT.md` governs behavior; confirmed images indexed by `docs/design/README.md` govern visuals. The owner chose Android Option A (youtubedl-android) and GPL-3.0-or-later for the repository; Option A acceptance is local feasibility only. See the [0C decision memo](gates/evidence/0c/architecture-decision.md).
- **Owner-approved layout:** Header order is logo, name, language, Settings; Settings is right of language. Desktop Queue and History are on the right, following the owner's direction over the contrary left-side text in `PROJECT.md`. The owner approved centered Settings, its accessible icon-only Back, omitting speed/ETA, Cancel for queue removal, a native desktop folder picker, and the 2C bottom error toast/Paused treatment. See the [1A](gates/evidence/1a/checkpoint.md), [1C](gates/evidence/1c/checkpoint.md), and [2C](gates/evidence/2c/checkpoint.md) checkpoints.
- **Approved preview and tests:** Mobile analyzing adapts the mobile Input layout with the desktop loading treatment. Single preview uses the approved fixture still; mobile Download fills the card. Playlist preview uses its own cover, falling back to the first entry only when absent; downloaded entries use their own thumbnails. Vitest, Testing Library, and jsdom are approved. The optional single-quality estimate is format-specific and size appears only for a matching estimate. See [1B](gates/evidence/1b/checkpoint.md).
- **Quality and metadata:** MP3 presets are requested maxima: copy an MP3 source at or below the selection, reencode a higher-bitrate MP3, and encode non-MP3 audio to the selection. Single MP3 offers 320/256/192/128; playlist MP3 Max/Min request 320/128 kbps; MP4 Max is best video plus best audio; Min is minimum video plus best audio. On MP4 redownload, use the closest lower available height. History stores the request fields/title, replaces an identical request at the top, permits duplicate titles, and uses one row per playlist. Entry metadata uses its own title/thumbnail and the playlist title as album. See [0B](gates/evidence/0b/checkpoint.md) and [1B](gates/evidence/1b/checkpoint.md).
- **Queue and storage:** Run one eligible item at a time. Pause is explicit and only during downloading; interrupted work restores paused and never auto-resumes. Gate 2C desktop singles capture the output folder at enqueue; preserve owned `.part` files for explicit resume; never overwrite outputs (number collisions). Android stores through MediaStore in public Downloads, without SAF or a folder selector. Confirmed ZIP behavior is sequential individual files when off; when on, write a partial archive with at most the current temporary media file, add entries uncompressed, and delete each temporary file. ZIP packaging and filesystem stress are Gate 3B. See [2C](gates/evidence/2c/checkpoint.md) and the [Gate 3A plan](gates/gate-3a.md).
- **Engine and app updates:** Windows executes verified engine copies from app data. yt-dlp updates use stable official releases, checksum verification, probation, and baseline fallback; automatic checks skip a failed version while manual retry is available. App-update discovery is separate, stable-channel, and user-triggered; startup never installs it. Real signing and installed NSIS/MSI upgrade proof remain in Gate 3C. See the [2B](gates/evidence/2b/checkpoint.md) and [2D](gates/evidence/2d/checkpoint.md) checkpoints.

## RELEASE BLOCKER — Android distribution

- Corresponding source, exact build inputs, and third-party notices for youtubedl-android 0.18.1 `library`, `ffmpeg`, and `common` binaries are **not established**. The 0C-04A waiver is for local feasibility only. **Do not publish, upload, attach to a release, or share any Android APK/build until this gap is resolved.**
- Before the production Android engine (first Phase 5 task block), replace those binaries with traceable minimal pinned arm64 FFmpeg/ffprobe without x264/x265, pinned QuickJS, and a traceable Python runtime with yt-dlp; provide corresponding source, build inputs, and notices. If this exceeds budget, a desktop-only first release is a fallback for owner review; it does not clear the blocker.
- Other open release items: legal review before public release; full transitive dependency licence audit; release APK size measurement after binary replacement; per-release source bundle and Microsoft runtime entitlement checks. Gate 3C must prove NSIS/MSI installed upgrades; if an installer cannot update reliably, evaluate the FR-75 direct-link fallback.
- Deferred Android follow-ups: recheck classified CI/deprecation warnings on Tauri or AGP upgrades and replace the deprecated production foreground-service notification builder; test WebView Back/predictive Back on a physical device at `targetSdk 36`; keep the Kotlin adapter independent of bundled binary paths, versions, and FFmpeg configuration.

## Open owner questions

- Physical-device touch and assistive-technology review remains open for the accepted 1B/1C UI; see their checkpoints.
- Gate 0B records automated VLC playback, not a human listening/viewing claim. If human playback remains required, the owner's review is not recorded; see the [checkpoint](gates/evidence/0b/checkpoint.md).
- If Android binary replacement exceeds budget, the owner must review whether to choose the desktop-only first-release fallback. The distribution blocker remains until the source/build/notice gap is resolved.
- The Gate 2C native review left the test-created `C:/Users/zahid/Downloads/effect-alarm-siren.mp3` after deletion was rejected. Preserve it unless the owner directs otherwise; path and hash are in the [native review](gates/evidence/2c/native-downloads.md).
