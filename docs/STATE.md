# Zownload state

## Current checkpoint and next task

- **Checkpoint:** Gate 3C was accepted on 2026-11-02, Gate 4A on 2026-11-12, Gate 4B on 2026-11-22, and Gate 5A on 2026-11-25; see the [Gate 3C checkpoint](gates/evidence/3c/checkpoint.md), [Gate 4A checkpoint](gates/evidence/4a/checkpoint.md), [Gate 4B checkpoint](gates/evidence/4b/checkpoint.md), and [Gate 5A checkpoint](gates/evidence/5a/checkpoint.md). `app-v0.0.1` remains an unchanged draft; stable `app-v0.0.2` remains the Linux update-review candidate.
- **Gate 5A plan:** Accepted by the owner on 2026-11-22, including its budget checkpoint. The owner selected CPython `3.14.10` for Android; the traceable runtime build is complete.
- **Gate 5B plan:** Owner accepted the storage/lifecycle scope and eight-session budget on 2026-11-25; [plan](gates/gate-5b.md).
- **Next task:** 5B-06 — Home continuation and disposable UI recovery. The 5A-09 playlist's media rights were not independently verified.
- **Completed 5B-01:** Recorded Gate 5A acceptance and drafted/recorded Gate 5B plan approval; commits `f72b580`, `878079f`; [plan](gates/gate-5b.md) and [checkpoint](gates/evidence/5a/checkpoint.md).
- **Completed 5B-02:** Published single MP3/MP4 outputs to Downloads with numbered collisions and failed-row cleanup; commit `c3d4368`; [evidence](gates/evidence/5b/5b-02-mediastore-single.md).
- **Completed 5B-03:** Implemented MediaStore pending-ZIP output, Stored entry CRC/central-directory recovery, and cache cleanup (`mediastore-zip`, `mediastore-single` pass on `BE2011`); commit `b022fdd`; [evidence](gates/evidence/5b/5b-03-mediastore-zip.md).
- **Completed 5B-04:** Replaced spike service with stateless `dataSync` `DownloadForegroundService` (progress-only notification, zero actions; `foreground-service` passes on `BE2011`); commit `b022fdd`; [evidence](gates/evidence/5b/5b-04-foreground-service.md).
- **Completed 5B-05:** Paused queue on recents removal and restored interrupted downloads paused with `.part` preservation across process death (`lifecycle-recovery` passes on `BE2011`); commit `b022fdd`; [evidence](gates/evidence/5b/5b-05-lifecycle-recovery.md).
- **Completed 5B-07:** Handled `onTimeout` with detached pause notification and `.part` preservation (`foreground-timeout` callback test passes on API 29 `BE2011`; physical API 35 sign-off remains open for AC-35); commit `b022fdd`; [evidence](gates/evidence/5b/5b-07-foreground-timeout.md).
- **Completed 5A-01:** Documented the Android engine scope, source/build/notice hard gate, task sequence, and budget checkpoint; commit `d32d5cb`; [Gate 5A plan](gates/gate-5a.md).
- **Completed 5A-02:** Approved CPython source/JNI strategy and pinned its sources, dependencies, patches, and toolchain; commit `ed15956`; [decision and lock evidence](gates/evidence/5a/python-runtime-decision.md).
- **Completed 5A-03:** Built locked CPython 3.14.10 with yt-dlp/EJS for arm64; work commit `3b34df2`; [runtime build evidence](gates/evidence/5a/5a-03-cpython-runtime.md).
- **Completed 5A-04:** Built pinned Android arm64 FFmpeg/ffprobe and verified MP3/MP4 paths; commit `af2217e`; [build evidence](gates/evidence/5a/5a-04-ffmpeg.md).
- **Completed 5A-05:** Rebuilt locked QuickJS `2026-06-04` for Android arm64 and verified its ELF dependencies and yt-dlp/EJS pairing; commit `843e056`; [build evidence](gates/evidence/5a/5a-05-quickjs.md).
- **Completed 5A-06:** Replaced opaque Android payloads and verified the arm64 APK provenance; work commit `fdd69d4`; [package evidence](gates/evidence/5a/5a-06-package-provenance.md) and [manifest](gates/evidence/5a/5a-06-apk-engine-manifest.json).
- **Completed 5A-07:** Added the Kotlin provider/plugin, JNI runner, progress/cancel bridge, and verified updater; commit `4059152`; V3 passed; [evidence](gates/evidence/5a/5a-07-kotlin-engine.md).
- **Completed 5A-08:** Added Rust Android engine and queue/history/settings wiring; CI pause-fixture race fixed in `c2ec9e7` (implementation `cc06661`); V3 and Foundation pass; [evidence](gates/evidence/5a/5a-08-android-rust-engine.md).
- **Completed 5A-09:** V4 passed on OnePlus BE2011 for MP3/MP4, playlist, queue/history/settings, recreation, and cancellation; commits `886b872`, `a75323d` (CI rustfmt); [device evidence](gates/evidence/5a/5a-09-device-engine.md).
- Android CI maintenance: while the 5A-06 distribution blocker remains open, CI checks pinned Android toolchains without building APKs; Android checks passed in [Actions run 45317287226](https://github.com/zahidzta/zownload_application/actions/runs/45317287226) and [45317294613](https://github.com/zahidzta/zownload_application/actions/runs/45317294613), workflow fix `67a0012`.
- **Windows app fix:** The engine-hash correction is merged to `main`, but published Windows v0.0.2 still has the mismatched resources. A new signed Windows build and update/install review remain pending.
- **Owner direction:** The v0.0.2 desktop window is horizontal 1350×770; the stable release was authorized for update review.

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
- 3A — accepted 2026-10-30; [checkpoint](gates/evidence/3a/checkpoint.md) and [task evidence](gates/evidence/3a/tasks.md).
- 3B — accepted 2026-10-31; [checkpoint](gates/evidence/3b/checkpoint.md) and [task evidence](gates/evidence/3b/tasks.md).
- 3C — accepted 2026-11-02; commit `1c9c221`; [checkpoint](gates/evidence/3c/checkpoint.md) and [task evidence](gates/evidence/3c/tasks.md).
- 4A — accepted by owner 2026-11-12; [checkpoint](gates/evidence/4a/checkpoint.md) and [task evidence](gates/evidence/4a/tasks.md).
- 4B — accepted by owner 2026-11-22; [checkpoint](gates/evidence/4b/checkpoint.md) and [task evidence](gates/evidence/4b/tasks.md).
- 5A — accepted by owner 2026-11-25; [checkpoint](gates/evidence/5a/checkpoint.md).

## Standing decisions

- **Authority and licensing:** `shared/contract.ts` and `src-tauri/src/contract.rs` govern exchanged fields/types; `PROJECT.md` governs behavior; confirmed images indexed by `docs/design/README.md` govern visuals. The owner chose GPL-3.0-or-later and approved CPython 3.14.10/JNI for Gate 5A on 2026-11-22; this supersedes the earlier Gate 0C Option A feasibility choice. `PROJECT.md` D-09 still needs owner requirements cleanup. See the [0C memo](gates/evidence/0c/architecture-decision.md) and [5A decision](gates/evidence/5a/python-runtime-decision.md).
- **Owner-approved layout:** Header order is logo, name, language, Settings; Settings is right of language. Desktop Queue and History are on the right, following the owner's direction over the contrary left-side text in `PROJECT.md`. The owner approved centered Settings, its accessible icon-only Back, omitting speed/ETA, Cancel for queue removal, a native desktop folder picker, and the 2C bottom error toast/Paused treatment. See the [1A](gates/evidence/1a/checkpoint.md), [1C](gates/evidence/1c/checkpoint.md), and [2C](gates/evidence/2c/checkpoint.md) checkpoints.
- **Approved preview and tests:** Mobile analyzing adapts the mobile Input layout with the desktop loading treatment. Single preview uses the approved fixture still; mobile Download fills the card. Playlist preview uses its own cover, falling back to the first entry only when absent; downloaded entries use their own thumbnails. Vitest, Testing Library, and jsdom are approved. The optional single-quality estimate is format-specific and size appears only for a matching estimate. See [1B](gates/evidence/1b/checkpoint.md).
- **Quality and metadata:** MP3 presets are requested maxima: copy an MP3 source at or below the selection, reencode a higher-bitrate MP3, and encode non-MP3 audio to the selection. Single MP3 offers 320/256/192/128; playlist MP3 Max/Min request 320/128 kbps; MP4 Max is best video plus best audio; Min is minimum video plus best audio. On MP4 redownload, use the closest lower available height. History stores the request fields/title, replaces an identical request at the top, permits duplicate titles, and uses one row per playlist. Entry metadata uses its own title/thumbnail and the playlist title as album. See [0B](gates/evidence/0b/checkpoint.md) and [1B](gates/evidence/1b/checkpoint.md).
- **Queue and storage:** Run one eligible item at a time. Pause is explicit and only during downloading; interrupted work restores paused and never auto-resumes. Gate 2C desktop singles capture the output folder at enqueue; preserve owned `.part` files for explicit resume; never overwrite outputs (number collisions). Android stores through MediaStore in public Downloads, without SAF or a folder selector. Confirmed ZIP behavior is sequential individual files when off; when on, retain the partial archive and only the current entry's work files, add entries uncompressed, and remove verified entries' work files before starting the next. ZIP packaging and filesystem stress are Gate 3B. See [2C](gates/evidence/2c/checkpoint.md) and the [Gate 3B plan](gates/gate-3b.md).
- **Engine and app updates:** Windows executes verified engine copies from app data. yt-dlp updates use stable official releases, checksum verification, probation, and baseline fallback; automatic checks skip a failed version while manual retry is available. App-update discovery is separate, stable-channel, and user-triggered; startup never installs it. Real signing and installed NSIS/MSI upgrade proof remain in Gate 3C. See the [2B](gates/evidence/2b/checkpoint.md) and [2D](gates/evidence/2d/checkpoint.md) checkpoints.

## RELEASE BLOCKER — Android distribution

- The former opaque `0.18.1` AAR source/build/notice gap and package provenance audit were resolved locally in 5A-06; see its [evidence](gates/evidence/5a/5a-06-package-provenance.md). **Do not share any Android APK/build until the owner reviews this evidence and explicitly closes the distribution blocker.**
- Other open release items: legal review before public release; release APK size measurement; per-release source bundle and Microsoft runtime entitlement checks. Gate 3C must prove NSIS/MSI installed upgrades; if an installer cannot update reliably, evaluate the FR-75 direct-link fallback.
- Deferred Android follow-ups: recheck classified CI/deprecation warnings on Tauri or AGP upgrades and replace the deprecated production foreground-service notification builder; test WebView Back/predictive Back on a physical device at `targetSdk 36`; keep the Kotlin adapter independent of bundled binary paths, versions, and FFmpeg configuration.

## Open owner questions

- Physical-device touch and assistive-technology review remains open for the accepted 1B/1C UI; see their checkpoints.
- Gate 0B records automated VLC playback, not a human listening/viewing claim. If human playback remains required, the owner's review is not recorded; see the [checkpoint](gates/evidence/0b/checkpoint.md).
- Owner review of the 5A-06 package evidence and explicit distribution-blocker closure remain pending before APK/build sharing.
- The Gate 2C native review left the test-created `C:/Users/zahid/Downloads/effect-alarm-siren.mp3` after deletion was rejected. Preserve it unless the owner directs otherwise; path and hash are in the [native review](gates/evidence/2c/native-downloads.md).
