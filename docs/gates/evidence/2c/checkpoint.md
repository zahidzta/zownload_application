<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 2C checkpoint — 2026-10-27

**Status:** Evidence prepared for explicit owner checkpoint acceptance. The owner reviewed the revised native Paused and bottom error-toast captures on 2026-10-27 and confirmed the visible result looks right. Stage 2D remains unopened until the owner accepts this full checkpoint.

## Windows single-download acceptance map

| Criterion | Gate 2C evidence and boundary |
|---|---|
| [AC-07](../../../../PROJECT.md) — Paused and resume from partial | [Native Queue capture](queue-paused.png), [native byte-offset record](native-downloads.md#queue-filesystem-and-restart): Stop at 16.8% left a 1,029,269-byte `.part`; relaunch stayed Paused without automatic transfer; Continue requested `Range: bytes=1029269-`, received HTTP 206, and completed. The deterministic [queue lifecycle test](../../../../src-tauri/tests/queue_lifecycle.rs) checks the same transition and durable ordering. |
| AC-11 — playable MP3/MP4 and FR-58 metadata | [Pinned `ffprobe`, full decode, and Windows Media Player observations](native-downloads.md#real-files-metadata-and-playback) cover direct MP3 copy, Vorbis-to-MP3 encode, MP4 H.264/AAC and MPEG-4/AAC, title, source artist, empty single-item album, and an attached JPEG cover. The Gate [2C-02 worker proof](single-worker.md#pinned-windows-cli-proof) covers an MP3 with available JPEG cover. Playlist album mapping remains for 3A. |
| AC-12 — quality behavior | Native 320-maximum MP3 copied a 128 kb/s source; 256 MP3 encoded Vorbis at 256 kb/s; MP4 240 produced 240-pixel video, and a stale 360 request selected the next lower 304-pixel derivative and output 304-pixel video. The [worker proof](single-worker.md#pinned-windows-cli-proof) covers higher-bitrate MP3 down-encode. Playlist Max/Min combinations remain for 3A. |
| AC-15 — desktop download folder | [Native folder record](native-downloads.md#queue-filesystem-and-restart) shows the chosen folder, captured folder retained across a Settings change and resume, and `downloadDir: null` producing a file in system Downloads. Android storage is outside this Windows gate. |
| AC-16 — no overwrite | [Native collision observations](native-downloads.md#queue-filesystem-and-restart) show numbered MP3 and MP4 names and preservation of the first MP4 hash. ZIP entry collisions remain for 3B. |
| AC-17 — disk/permission failure | [Worker classifier tests](../../../../src-tauri/src/engine/single.rs) and the [deterministic queue failure test](../../../../src-tauri/tests/queue_lifecycle.rs) cover typed error settlement and owned incomplete-output cleanup. The native missing-item failure confirms durable translated notification and Queue removal, but does **not** simulate physical disk-full or permission denial. Full filesystem-resilience proof remains in 3B. |
| AC-18 — cleared Input and transient terminal removal | [Native Queue and History observations](native-downloads.md#queue-filesystem-and-restart) show Input visible during the transfer, successful rows leaving Queue after History, and a failed row leaving after notification persistence. [Native transport UI tests](../../../../tests/interactive/nativeRuntime.test.tsx) cover the mounted flow. |
| AC-19 — persistent translated errors | [Bottom toast captures](error-notification.png) and [desktop toast](error-toast-desktop.png), [native restart observation](native-downloads.md#queue-filesystem-and-restart), and [interactive notification tests](../../../../tests/interactive/notificationCard.test.tsx) cover en/es text, persistence, Settings visibility, explicit dismissal, failed-dismiss retry, and focus restoration. |
| AC-29 — active desktop close | [Native process record](native-downloads.md#queue-filesystem-and-restart) found the app, app-data yt-dlp, and its child gone within three seconds of X, kept the `.part`, and reopened Paused without auto-resume. The [Windows process-tree test](../../../../src-tauri/tests/process_tree.rs) also covers timeout, cancel, close, and abrupt parent death. |

The real native review used the pinned app-data engine copies and the locked public Gate 0B media, with final outputs, hashes, and site limits in [native-downloads.md](native-downloads.md). It exposed and fixed early thumbnail processing misclassified as post-processing, a raw URL shown after analysis, and an MP4 derivative's incorrect title/height. The owner-requested persistent bottom toast keeps an error visible without scrolling. No contract field, crate, npm dependency, or approved reference image changed.

## Verification

The exact [Gate 2C V3 command](../../gate-2c.md#verification-commands) exited **0** on 2026-10-27 in a clean detached checkout containing the reviewed task files. The setup is in [toolchain](../../../toolchain.md#gate-2c-04-clean-verification): pinned Node `24.22.0`, `npm ci` (120 packages, zero reported vulnerabilities), three verified Windows engine resources, and the existing Cargo target directory. The command was:

```powershell
powershell -NoProfile -Command 'npm run test:ui; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; node --test --test-concurrency=1; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo fmt --manifest-path src-tauri/Cargo.toml --check; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; powershell -NoProfile -File scripts/verify-foundation.ps1; exit $LASTEXITCODE'
```

Results: **13 interactive files, 58/58 tests; 18/18 sequential Node tests; Rust formatting; frontend build and TypeScript/shared-JSON contract check; 48/48 Rust library tests; analysis CLI and contract parity; Windows child-tree and queue lifecycle integrations; and all nine indexed design images.** The script ended with `Foundation verification passed.` Separate focused Windows process-tree and queue commands also passed after this V3 run.

Two earlier attempts established setup issues. The first passed UI and Node but the open native review app locked the shared `zownload.exe` during Rust compilation; closing it resolved that. The second reached the queue integration, which timed out because its deterministic yt-dlp stand-in did not yet supply the new FFmpeg tag-copy output. The test stand-in now copies that stub media into the final stage; its focused lifecycle test and the final exact V3 passed. No production code was changed solely to make the test pass.

## Stage boundary

Gate 2C establishes the Windows single-item media pipeline and native queue lifecycle on one machine. Public site responses can change; the real playback review used Archive media and the checksum-locked Commons fixture served over a throttled local range server. Playlist extraction/Max-Min/counters remain in **3A**, playlist ZIP and full disk/permission stress in **3B**, and engine/app update checks in **2D**. Installer packaging, other desktop platforms, and Android distribution are outside this checkpoint. The [Android distribution blocker](../../../STATE.md#release-blocker--android-distribution) remains open. The owner has approved the revised visible native result; explicit acceptance of this complete checkpoint is still required before 2D.
