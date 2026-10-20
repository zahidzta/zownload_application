# Gate 0B — real CLI and licensing proof

## Scope and checkpoint

- Source: `PROJECT.md:346-356,368-373,388-390,618-629,698-700,708-712,729,734-752,802-821`; current status: `docs/STATE.md`. Gate 0A was accepted on 2026-10-18.
- Strict deliverable: pinned yt-dlp, reproducible upstream QuickJS 2026-06-04 builds for Windows x64, Linux x64, macOS x64 and arm64, and Android arm64; an LGPL-compatible ffmpeg build and license proof; real CLI evidence and an exact command matrix in `docs/ytdlp-commands.md`. The Windows CLI probe uses the pinned redistributable artifacts. Android execution belongs to Gate 0C. No Tauri engine integration, production UI, release, or Android spike is part of this gate.
- Exit evidence: official source/version URLs and SHA-256 values, build recipes and binary hashes, effective license inventory and corresponding-source plan, captured CLI output and produced-file inspection, common-player playback, and review against every capability in `PROJECT.md:752`. Owner acceptance is required before Gate 0C.
- Keep downloaded archives, binaries, temporary media and full logs under ignored `work/engine/`; commit only reproducible scripts and concise redacted evidence under `docs/gates/evidence/0b/`. The source lock defines exact artifact URLs and hashes. Build/test tasks consume it without choosing new versions. Hosted builds may fetch those exact locked artifacts after checksum verification.
- The commands below are the exact verification entrypoints to create in the named task. Record exit codes, tool versions, hashes, relevant output and any manual checks in `docs/STATE.md` and the evidence directory. Each task is one roughly 30-minute session on `task-<id>`, with its own verification, work commit, state commit and PR as described in `AGENTS.md`.

## Stop rule

If any required CLI capability, QuickJS runtime requirement, codec/metadata/playback check, source-integrity check, or licensing check fails, record the exact command, inputs, exit status and relevant output in `docs/STATE.md` and stop Gate 0B. Do not substitute an unpinned binary, relax the feature, change formats or licensing, or use another engine/runtime as a workaround. Ask the owner to revise the affected decision before resuming. A broken or unavailable test URL is fixture maintenance: record it and replace it only in a separate source/fixture task, without treating a failed engine test as a fixture problem without evidence.

## Tasks requiring web access: pins, source URLs, checksums and fixtures

### 0B-01 — Source and license lock

- Goal: identify official immutable yt-dlp release and matching yt-dlp-ejs, upstream QuickJS 2026-06-04, ffmpeg, and any required MP3 encoder source; pin versions/revisions, source and binary URLs, published checksums when available, license texts and build dependencies. Check actual licenses rather than assuming the template is complete.
- Files to touch: `docs/engine-sources.md`, `docs/THIRD-PARTY-NOTICES.md`, `scripts/gate-0b/verify-source-lock.ps1`, `docs/STATE.md`.
- Read: `PROJECT.md:354-356,368-371,388,627,699-700,708,729,752,814-821`.
- Dependencies/parallelism: none; independent of 0B-02. This is research only: no archive download or build.
- Acceptance: every selected component has an official source URL, immutable version/revision, stated license, target artifact plan and checksum source or an explicit plan to compute and attest the source hash; the exact yt-dlp/ejs relationship is recorded. No `latest` URL is used as a pin.
- Exact verification command: `powershell -NoProfile -File scripts/gate-0b/verify-source-lock.ps1` (also review the cited primary source pages manually).

### 0B-02 — Real test fixture lock

- Goal: select short, publicly accessible, permitted single, pure-playlist, video-plus-playlist, metadata/thumbnail and error-case URLs; record expected properties and a repeatable way to detect fixture disappearance. Include a real YouTube case for QuickJS/ejs.
- Files to touch: `docs/gates/evidence/0b/fixtures.md`, `scripts/gate-0b/verify-fixtures.ps1`, `docs/STATE.md`.
- Read: `PROJECT.md:370-371,390-391,699,709-712,752,802-821`.
- Dependencies/parallelism: none; independent of 0B-01. Fixture discovery is web work; no media download or engine test.
- Acceptance: each planned capability has a named fixture and expected observation; fixture licensing/permission and access dates are documented; unavailable fixtures are identified before interpreting CLI results.
- Exact verification command: `powershell -NoProfile -File scripts/gate-0b/verify-fixtures.ps1`.

### 0B-03 — Acquire and attest pinned artifacts

- Goal: download only the 0B-01 locked source archives and yt-dlp artifact, verify published hashes where provided, compute SHA-256 for every acquired file, and make later builds fail on hash mismatch. Keep artifacts outside Git.
- Files to touch: `scripts/gate-0b/fetch-sources.ps1`, `scripts/gate-0b/verify-downloads.ps1`, `docs/engine-sources.md`, `.gitignore`, `docs/gates/evidence/0b/source-hashes.txt`, `docs/STATE.md`.
- Read: `PROJECT.md:370,388,623,627,752,814-821`.
- Dependencies/parallelism: 0B-01; may proceed independently of 0B-02. This is the last source-acquisition task before builds/tests; no compilation or CLI capability test.
- Acceptance: downloaded archives and binary match locked hashes and official provenance; each source and artifact hash is recorded; a fresh fetch can repeat the check; no binary or media is tracked.
- Exact verification command: `powershell -NoProfile -File scripts/gate-0b/verify-downloads.ps1`.

## Tasks that build or inspect pinned engines

### 0B-04 — Windows QuickJS build environment

- Goal: pin and document the Windows compiler/build tools and a reproducible QuickJS recipe from the attested upstream source. Keep the toolchain setup separate from compilation.
- Files to touch: `scripts/gate-0b/build-quickjs.ps1`, `docs/engine-builds.md`, `docs/STATE.md`.
- Read: `PROJECT.md:370,388,752,818`.
- Dependencies/parallelism: 0B-03; independent of 0B-09 after sources are locked.
- Acceptance: the script checks source hash, compiler identity and flags before building and has a deterministic Windows x64 output path; exact setup commands are documented.
- Exact verification command: `powershell -NoProfile -File scripts/gate-0b/build-quickjs.ps1 -Target windows-x64 -CheckEnvironment`.

### 0B-05 — Windows QuickJS binary

- Goal: build upstream QuickJS 2026-06-04 for Windows x64 and prove its CLI starts from the resulting binary.
- Files to touch: `scripts/gate-0b/build-quickjs.ps1`, `docs/engine-builds.md`, `docs/gates/evidence/0b/quickjs-windows.txt`, `docs/STATE.md`.
- Read: `PROJECT.md:370-371,388,752,818`.
- Dependencies/parallelism: 0B-04; independent of 0B-06 through 0B-09 once common scripts are integrated.
- Acceptance: source hash and compiler/flags are captured; built binary hash and version are recorded; `qjs` executes a trivial script. No opaque third-party QuickJS binary is used.
- Exact verification command: `powershell -NoProfile -File scripts/gate-0b/build-quickjs.ps1 -Target windows-x64 -Verify`.

### 0B-06 — Linux x64 QuickJS binary

- Goal: build and run the same locked QuickJS source on the pinned Linux CI baseline.
- Files to touch: `scripts/gate-0b/build-quickjs.sh`, `.github/workflows/gate-0b-engines.yml`, `docs/engine-builds.md`, `docs/gates/evidence/0b/quickjs-linux.txt`, `docs/STATE.md`.
- Read: `PROJECT.md:370,388,752,818`.
- Dependencies/parallelism: 0B-03; independent of 0B-05, 0B-09 and the CLI tasks after the shared workflow/script is integrated. Coordinate edits to shared scripts/workflow.
- Acceptance: Linux x64 build and trivial JS execution pass on CI; source and output hashes, compiler, flags and run ID are recorded.
- Exact verification command: `bash scripts/gate-0b/build-quickjs.sh linux-x64 --verify` (run on the Linux x64 host/CI job).

### 0B-07 — macOS x64 QuickJS binary

- Goal: build and run the locked source on a macOS x64 host.
- Files to touch: `scripts/gate-0b/build-quickjs.sh`, `.github/workflows/gate-0b-engines.yml`, `docs/engine-builds.md`, `docs/gates/evidence/0b/quickjs-macos-x64.txt`, `docs/STATE.md`.
- Read: `PROJECT.md:370,388,752,818`.
- Dependencies/parallelism: 0B-03 and 0B-06's shared Unix build script; independent of 0B-08 after shared CI edits are integrated.
- Acceptance: macOS x64 build and trivial JS execution pass on the matching host; source and output hashes, compiler, flags and run ID are recorded.
- Exact verification command: `bash scripts/gate-0b/build-quickjs.sh macos-x64 --verify` (run on the macOS x64 host/CI job).

### 0B-08 — macOS arm64 QuickJS binary

- Goal: build and run the locked source on a macOS arm64 host.
- Files to touch: `scripts/gate-0b/build-quickjs.sh`, `.github/workflows/gate-0b-engines.yml`, `docs/engine-builds.md`, `docs/gates/evidence/0b/quickjs-macos-arm64.txt`, `docs/STATE.md`.
- Read: `PROJECT.md:370,388,752,818`.
- Dependencies/parallelism: 0B-03 and 0B-06's shared Unix build script; independent of 0B-07 after shared CI edits are integrated.
- Acceptance: macOS arm64 build and trivial JS execution pass on the matching host; source and output hashes, compiler, flags and run ID are recorded.
- Exact verification command: `bash scripts/gate-0b/build-quickjs.sh macos-arm64 --verify` (run on the macOS arm64 host/CI job).

### 0B-09 — Android arm64 QuickJS build

- Goal: cross-compile the locked QuickJS source with pinned Android NDK r30 for `arm64-v8a` and inspect the artifact format and dependencies. Device execution is deferred to Gate 0C.
- Files to touch: `scripts/gate-0b/build-quickjs.sh`, `.github/workflows/gate-0b-engines.yml`, `docs/engine-builds.md`, `docs/gates/evidence/0b/quickjs-android.txt`, `docs/STATE.md`.
- Read: `PROJECT.md:348-349,370,372-373,752,818-820`.
- Dependencies/parallelism: 0B-03 and 0B-06's shared Unix build script; independent of 0B-07/08 after shared CI edits are integrated.
- Acceptance: NDK r30 build yields an Android arm64 native artifact, with source/output hash, compiler, flags and ELF dependency inspection recorded; the artifact is not claimed to run on a device yet.
- Exact verification command: `bash scripts/gate-0b/build-quickjs.sh android-arm64 --verify` (run on the NDK-equipped Linux host/CI job).

### 0B-10A — zlib source lock and attestation

- Goal: pin and acquire upstream zlib source required by FFmpeg's PNG thumbnail decoder; verify its version, source hash and license before any FFmpeg configuration or build. This repair was approved by the owner after 0B-10 found the missing dependency.
- Files to touch: `docs/engine-sources.md`, `docs/THIRD-PARTY-NOTICES.md`, `docs/gates/evidence/0b/source-hashes.txt`, `scripts/gate-0b/fetch-sources.ps1`, `scripts/gate-0b/verify-downloads.ps1`, `scripts/gate-0b/verify-source-lock.ps1`, `docs/STATE.md`.
- Read: `PROJECT.md:388,627,708-712,752,812`.
- Dependencies/parallelism: 0B-03; finish before resuming 0B-10. Use an official immutable source artifact and published hash or document the same source-attestation method used for the other locked sources. No compilation in this task.
- Acceptance: the new source URL, exact version, SHA-256, license and Windows build dependency plan are documented; the acquisition and offline verifier reject missing or altered zlib source; the existing 14 source checks still pass.
- Exact verification command: `powershell -NoProfile -File scripts/gate-0b/verify-downloads.ps1`.

### 0B-10 — LGPL ffmpeg configuration

- Goal: freeze a reproducible ffmpeg recipe, compiler and required external codec sources; audit enabled libraries before compilation. Validate that MP3 encoding, AAC encoding/compatibility, MP4 muxing and thumbnail conversion are possible under the effective license.
- Files to touch: `scripts/gate-0b/build-ffmpeg.ps1`, `docs/engine-builds.md`, `docs/THIRD-PARTY-NOTICES.md`, `docs/STATE.md`.
- Read: `PROJECT.md:368,388,390,627,708-712,752,806-812`.
- Dependencies/parallelism: 0B-03 and 0B-10A; independent of QuickJS builds. Use only sources locked and attested before this task.
- Acceptance: exact configure command, dependency versions/licenses, compiler and flags are recorded; `--enable-gpl` and `--enable-nonfree` are absent; no required codec depends on an incompatible library.
- Exact verification command: `powershell -NoProfile -File scripts/gate-0b/build-ffmpeg.ps1 -CheckConfiguration`.

### 0B-11 — Windows LGPL ffmpeg build

- Goal: compile ffmpeg/ffprobe from the locked source and configuration for the Windows CLI probe.
- Files to touch: `scripts/gate-0b/build-ffmpeg.ps1`, `docs/engine-builds.md`, `docs/gates/evidence/0b/ffmpeg-windows.txt`, `docs/STATE.md`.
- Read: `PROJECT.md:388,627,708,712,752`.
- Dependencies/parallelism: 0B-10; independent of QuickJS builds.
- Acceptance: reproducible build command exits successfully; ffmpeg/ffprobe binary hashes, version, configuration, linked dependency inventory and required MP3/AAC/MP4 capabilities are recorded. License verification is repeated against the built binaries.
- Exact verification command: `powershell -NoProfile -File scripts/gate-0b/build-ffmpeg.ps1 -Verify`.

### 0B-12 — Redistribution license audit

- Goal: inspect the actual yt-dlp bundled dependency inventory, QuickJS source and ffmpeg plus enabled external libraries, then fill the notice template for Gate 0B artifacts and corresponding-source/build-configuration locations.
- Files to touch: `docs/THIRD-PARTY-NOTICES.md`, `docs/engine-sources.md`, `docs/engine-builds.md`, `scripts/gate-0b/verify-licenses.ps1`, `docs/gates/evidence/0b/license-audit.txt`, `docs/STATE.md`.
- Read: `PROJECT.md:388,618-629,708,752`.
- Dependencies/parallelism: 0B-03 and 0B-05 through 0B-11; may run while CLI tests proceed but must finish before checkpoint. The web license/source lookup was completed in 0B-01; this task checks the acquired sources and built artifacts.
- Acceptance: all actually bundled components have effective license and notice text, source checksum, build configuration, binary hash and corresponding-source plan; ffmpeg lacks GPL/nonfree options; missing license evidence fails the audit.
- Exact verification command: `powershell -NoProfile -File scripts/gate-0b/verify-licenses.ps1`.

## Tasks that test the real CLI

### 0B-13 — Analysis, YouTube JS runtime and speed

- Goal: run pinned yt-dlp with the built Windows QuickJS and matching ejs for one real single, pure playlist and mixed video/playlist URL; verify JSON shapes and `--no-playlist` behavior, and time a representative YouTube playlist analysis.
- Files to touch: `scripts/gate-0b/verify-cli.ps1`, `docs/ytdlp-commands.md`, `docs/gates/evidence/0b/analyze.txt`, `docs/STATE.md`.
- Read: `PROJECT.md:370-371,390-391,699,752,804-805,812,814-821`.
- Dependencies/parallelism: 0B-02, 0B-03 and 0B-05; independent of 0B-11 until media conversion tests. QuickJS performance is evidence for the D-08 fallback decision, not permission to switch runtimes automatically.
- Acceptance: required JSON shapes and single/playlist interpretation match the command matrix; YouTube succeeds with QuickJS/ejs; elapsed time and any timeout are recorded.
- Exact verification command: `powershell -NoProfile -File scripts/gate-0b/verify-cli.ps1 -Case analyze`.

### 0B-14A — Non-MP3 single fixture

- Goal: replace the already-MP3 input for 0B-14 with a rights-documented, short source whose audio is not MP3, without changing MP3 source behavior. This separate fixture task was approved by the owner after the 0B-14 stop.
- Files to touch: `docs/gates/evidence/0b/fixtures.md`, `scripts/gate-0b/verify-fixtures.ps1`, `docs/gates/evidence/0b/mp3-singles.txt`, `docs/ytdlp-commands.md`, `docs/STATE.md`, this gate file.
- Read: `PROJECT.md:388,390,710,752,809-812`.
- Dependencies/parallelism: 0B-02 and the recorded 0B-14 failure. Finish before resuming 0B-14; do not run the four preset encodes in this fixture task.
- Acceptance: the new source URL, author, license, file identity and non-MP3 audio codec are documented; a one-time ffprobe inspection confirms the codec; the read-only preflight checks current source metadata without downloading media and all prior fixture checks still pass.
- Exact verification command: `powershell -NoProfile -File scripts/gate-0b/verify-fixtures.ps1`.

### 0B-14 — MP3 single presets

- Goal: test 320/256/192/128 kbps output from the best available source, inspect actual output bitrate and play the four files.
- Files to touch: `scripts/gate-0b/verify-cli.ps1`, `docs/ytdlp-commands.md`, `docs/gates/evidence/0b/mp3-singles.txt`, `docs/STATE.md`.
- Read: `PROJECT.md:388,390,710,752,809-812`.
- Dependencies/parallelism: 0B-02, 0B-03, 0B-05, 0B-11 and 0B-14A; use the locked non-MP3 Commons original for this probe. Independent of 0B-15/16 once shared CLI script edits are integrated.
- Acceptance: all four commands succeed, ffprobe reports MP3 outputs at the intended presets within documented encoder tolerance, and common-player playback is recorded.
- Exact verification command: `powershell -NoProfile -File scripts/gate-0b/verify-cli.ps1 -Case mp3-singles`.

### 0B-15 — MP3 playlist Max/Min

- Goal: test a real playlist with Max 320/Min 128 kbps output; capture per-entry results and whether separate CLI invocations are viable, without implementing the application queue.
- Files to touch: `scripts/gate-0b/verify-cli.ps1`, `docs/ytdlp-commands.md`, `docs/gates/evidence/0b/mp3-playlist.txt`, `docs/STATE.md`.
- Read: `PROJECT.md:370,710,752,805,809-812`.
- Dependencies/parallelism: 0B-02, 0B-03, 0B-05, 0B-11 and 0B-15A for the resumed run. Use the locked non-MP3 playlist from 0B-15A; preserve the earlier Archive MP3-source failure as evidence. Independent of 0B-14/16 after shared script edits are integrated.
- Acceptance: every fixture entry is processed, Max/Min output bitrates are inspected, and produced MP3s play; the per-entry invocation option is documented as tested or untested, not assumed.
- Exact verification command: `powershell -NoProfile -File scripts/gate-0b/verify-cli.ps1 -Case mp3-playlist`.

### 0B-15A — Non-MP3 playlist fixture

- Goal: after the 0B-15 stop, confirm all three original Archive entries are 128 kbps MP3 sources, then lock a rights-documented real playlist with at least three non-MP3 sources for a later 0B-15 rerun. The owner approved this separate fixture task on 2026-10-19 and prohibited forced conversion of the original MP3s.
- Files to touch: `docs/gates/evidence/0b/fixtures.md`, `scripts/gate-0b/verify-fixtures.ps1`, `docs/gates/evidence/0b/mp3-playlist.txt`, `docs/STATE.md`, this gate file.
- Read: `PROJECT.md:370,388,710,752,805,809-812`.
- Dependencies/parallelism: the recorded 0B-15 failure. Finish before resuming 0B-15; do not run Max/Min encodes or alter the stopped result in this fixture task.
- Acceptance: all original entries are independently confirmed as 128 kbps MP3 sources; the replacement has at least three selected original non-MP3 entries with source hashes, codecs and rights recorded. The read-only preflight checks each current entry's metadata fingerprint, selected format and codec lock without downloading media, and rejects MP3. It also verifies at least two distinct video resolutions for the upcoming 0B-16 fixture.
- Exact verification command: `powershell -NoProfile -File scripts/gate-0b/verify-fixtures.ps1`.

### 0B-16A — Short video playlist fixture after the 0B-16 stop

- Goal: replace the timed-out Blender transfer fixture with a rights-documented real playlist of at least three short videos; retain the original stop finding in `mp4.txt`.
- Files to touch: `docs/gates/evidence/0b/fixtures.md`, `scripts/gate-0b/verify-fixtures.ps1`, this gate file, `docs/ytdlp-commands.md`, `docs/STATE.md`. Do not alter the FFmpeg build or run the 0B-16 MP4 verifier.
- Read: `PROJECT.md:388,752,806-808,812`.
- Dependencies/parallelism: the recorded 0B-16 stop and owner approval. Complete this fixture task before the 0B-16 rerun.
- Acceptance: lock at least three rights-documented playlist entries, including CC BY attribution where applicable. The read-only preflight prints each entry's available video heights and estimated Max/Min transfer bytes, and fails for fewer than two distinct heights, a changed license or membership, or an estimated size above the documented threshold. Both playlist invocations must fit comfortably inside the unchanged 600-second bound on the locked estimates. The old `mp4.txt` stop remains a finding, not a pass.
- Exact verification command: `powershell -NoProfile -File scripts/gate-0b/verify-fixtures.ps1`.

### 0B-16 — MP4 Max/Min and height selection

- Goal: validate MP4 Max/Min selection for a real playlist and a bounded-height single; inspect streams and play the files.
- Files to touch: `scripts/gate-0b/verify-cli.ps1`, `docs/ytdlp-commands.md`, `docs/gates/evidence/0b/mp4.txt`, `docs/STATE.md`.
- Read: `PROJECT.md:388,752,806-808,812`.
- Dependencies/parallelism: 0B-02, 0B-03, 0B-05, 0B-11 and 0B-16A for the rerun; independent of 0B-14/15 after shared script edits are integrated.
- Acceptance: playlist Max/Min and bounded-height single outputs match selected quality, are valid MP4 and play in common players; actual ffprobe output and player names/results are recorded.
- Exact verification command: `powershell -NoProfile -File scripts/gate-0b/verify-cli.ps1 -Case mp4`.

### 0B-17 — MP4 AAC compatibility

- Goal: test a real non-AAC source and determine the exact CLI options required to produce MP4 with AAC audio when conversion is needed.
- Files to touch: `scripts/gate-0b/verify-cli.ps1`, `docs/ytdlp-commands.md`, `docs/gates/evidence/0b/aac.txt`, `docs/STATE.md`.
- Read: `PROJECT.md:388,712,752,806-808,812`.
- Dependencies/parallelism: 0B-02, 0B-03, 0B-05, 0B-11 and 0B-16; independent of 0B-14/15 after shared script edits are integrated.
- Acceptance: ffprobe confirms AAC output where source audio is non-AAC; the resulting MP4 plays in common players, with source and output stream details recorded.
- Exact verification command: `powershell -NoProfile -File scripts/gate-0b/verify-cli.ps1 -Case aac`.

### 0B-18 — Metadata and JPEG cover

- Goal: test title, artist/creator/uploader fallback, playlist title as album, and best thumbnail converted to an embedded JPEG when required, on actual MP3/MP4 outputs.
- Files to touch: `scripts/gate-0b/verify-cli.ps1`, `docs/ytdlp-commands.md`, `docs/gates/evidence/0b/metadata.txt`, `docs/STATE.md`.
- Read: `PROJECT.md:390,709,752,812`.
- Dependencies/parallelism: 0B-14 through 0B-17; independent of 0B-19/20 after shared script edits are integrated.
- Acceptance: ffprobe/media inspection shows the required mapped fields and embedded JPEG cover where the fixture supplies artwork; common-player display is recorded. A missing fixture field is documented as such, not counted as a mapped-field pass.
- Exact verification command: `powershell -NoProfile -File scripts/gate-0b/verify-cli.ps1 -Case metadata`.

### 0B-19 — Partial resume and parseable progress

- Goal: interrupt a real download, resume from its `.part` file, and capture `--newline` plus a stable progress template for application parsing.
- Files to touch: `scripts/gate-0b/verify-cli.ps1`, `docs/ytdlp-commands.md`, `docs/gates/evidence/0b/resume-progress.txt`, `docs/STATE.md`.
- Read: `PROJECT.md:752,812`.
- Dependencies/parallelism: 0B-02, 0B-03, 0B-05 and 0B-11; independent of 0B-18/20 after shared script edits are integrated.
- Acceptance: resumed output passes media inspection, evidence shows whether bytes were reused, and progress lines are machine parseable without corrupting normal/error output.
- Exact verification command: `powershell -NoProfile -File scripts/gate-0b/verify-cli.ps1 -Case resume-progress`.

### 0B-20 — Representative error behavior

- Goal: probe unavailable, invalid and access-restricted URLs plus startup failures of pinned executables; capture exit codes, stderr and `ERROR:` formatting for later typed-error and updater heuristics.
- Files to touch: `scripts/gate-0b/verify-cli.ps1`, `docs/ytdlp-commands.md`, `docs/gates/evidence/0b/errors.txt`, `docs/STATE.md`.
- Read: `PROJECT.md:729,752,812`.
- Dependencies/parallelism: 0B-02, 0B-03 and 0B-05; independent of 0B-14 through 0B-19 after shared script edits are integrated.
- Acceptance: expected failures are reproducible and distinguishable from fixture/network outages; exit status, startup timeout and relevant stderr are recorded. The observations do not silently alter later-stage heuristics.
- Exact verification command: `powershell -NoProfile -File scripts/gate-0b/verify-cli.ps1 -Case errors`.

### 0B-21 — Command matrix and checkpoint evidence

- Goal: freeze exact tested commands and options, source/build/license evidence, output inspections and manual playback results; compare every `PROJECT.md:752` capability with a passing probe and prepare owner review.
- Files to touch: `docs/ytdlp-commands.md`, `docs/gates/gate-0b.md` evidence section, `docs/gates/evidence/0b/checkpoint.md`, `scripts/gate-0b/verify-gate.ps1`, `docs/STATE.md`.
- Read: `PROJECT.md:370-371,388-390,699,708-712,729,736-745,752,802-821`.
- Dependencies/parallelism: 0B-01 through 0B-20; no next gate begins before owner acceptance.
- Acceptance: all required capabilities, target QuickJS builds, SHA-256 values, licensing checks and manual player results have linked evidence; the command matrix contains exact verified commands, marks any Appendix B proposal corrected by testing, and has no unsupported success claim. For every required test, the matrix review records which component fetches media and verifies that FFmpeg never has to fetch an HTTPS input (including HLS/DASH paths); local FFmpeg post-processing is allowed. Any required test that depends on FFmpeg HTTPS input fails review until the owner resolves the licensing/build question. A failed requirement triggers the stop rule.
- Exact verification command: `powershell -NoProfile -File scripts/gate-0b/verify-gate.ps1`.

## 0B-21 checkpoint evidence for owner review

Gate 0B checkpoint accepted by the owner on 2026-10-20, after [PR #45](https://github.com/zahidzta/zownload_application/pull/45)
merged. The decision and next task are recorded in `docs/STATE.md`. The
documented playback and source-format limits remain visible in the record.

The [checkpoint record](evidence/0b/checkpoint.md) links the frozen
[command matrix](../ytdlp-commands.md), source and SHA-256 attestation, all
five QuickJS target builds, LGPL FFmpeg/license audit, each required CLI probe,
output inspections and automated VLC playback. It records the already-MP3
quality behavior, unmeasured YouTube JS challenge speed, failed FFmpeg HTTPS
diagnostic and absence of a human listening/viewing check without turning
those observations into passing claims. The tested HLS paths used yt-dlp's
native downloader and FFmpeg only read local files.

Run `powershell -NoProfile -File scripts/gate-0b/verify-gate.ps1` to verify the
local artifacts, locks, links and checkpoint coverage. This verification does
not accept the gate. The owner reviews the recorded limits and playback before
an explicit Gate 0B acceptance or rejection; Gate 0C remains closed.

## Time risks and planned splits

- Windows QuickJS toolchain discovery plus compilation could exceed 30 minutes; it is already split into 0B-04 and 0B-05. Unix/Android target builds are one target per session (0B-06 through 0B-09).
- ffmpeg toolchain/configuration plus compilation and codec inspection could exceed 30 minutes; it is already split into 0B-10 and 0B-11. If compilation alone runs beyond a session, stop after a reproducible CI/build invocation and split 0B-11 into build completion and binary inspection before claiming acceptance.
- Playlist/network probes and player inspection may exceed 30 minutes if the fixture is long or a site changes. Keep fixtures short; if 0B-15 or 0B-16 overruns, split Max and Min into separate task IDs in this gate file before continuing. Do not skip a required case to make the time box.
- CI runner wait time may exceed 30 minutes for a target. Record the run ID and stop that session; inspect the completed run in a new session before marking the task passed.

## Delivery

After 0B-21 passes, the owner reviews the recorded CLI, playback, licensing and build evidence and explicitly accepts or rejects Gate 0B. Only an accepted checkpoint recorded in `docs/STATE.md` permits Gate 0C.
