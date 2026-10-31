<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# 3B-04 Windows synthetic review — 2026-10-31

This is a native Windows **Rust queue fixture**, not a completed Tauri WebView walkthrough. It runs the real Windows queue, SQLite, process supervisor, ZIP writer, and filesystem using a locally compiled deterministic engine stand-in. All generated media and archives stayed under unique `%TEMP%/zownload-zip-queue-*` roots; no request touched the owner's Downloads folder. Rust 1.99.1 compiled the stand-in, whose yt-dlp and FFmpeg executable SHA-256 was `7C0E9A9BD81F2C10C475DFD15168EFFA274A7A18B68A9BC6D87BCAAEE5486C51` for each copy. The [toolchain record](../../../toolchain.md#gate-3b-windows-zip-verification) lists setup and pinned production hashes.

The fixture requested five playlists in FIFO order with ZIP enabled, then changed Settings to ZIP off. Every request retained its captured choice and output folder. It used 2 MiB synthetic MP4 entries with an ordinary failed entry, duplicate titles, an all-failed playlist, and a simulated disk-full stderr. The completed output directory contained only:

| Archive | Stored entries (2,097,152 bytes each, method 0) |
|---|---|
| `Playlist.zip` | `first.mp4`, `second.mp4` |
| `Playlist (1).zip` | `first.mp4`, `second.mp4` (mixed playlist; failed entry omitted) |
| `Playlist (2).zip` | `first.mp4`, `first (1).mp4` |

There was no published ZIP for the all-failed or disk-full job and no `.zip.part` at settlement. SQLite had zero queue rows, three History rows, and three persistent notifications: `playlist_summary:2:1`, `playlist_summary:0:2`, and `disk_full` with the synthetic engine stderr. The fatal job's owned work directory was absent. `packaging` events were observed for the successful and mixed jobs. The writer tests separately cover an existing archive collision, interrupted append recovery, idempotent recovery after final rename, and removal of only the recovered owned archive. A restart test committed entry 0 to the ZIP before advancing SQLite, reopened a paused queue, and continued at entry 1 without duplicating entry 0; it also exercised an older persisted entry-directory path.

The 5 ms sampler reported **5 peak staging files and 8,389,117 peak staging bytes**, including ZIP journal/manifest files. It saw **2 current media files** during FFmpeg tagging, when the source and tagged output coexist. The numbers are sampled peaks from the 2 MiB fixture, not a proof of a byte-for-byte upper bound for arbitrarily large media. The strict reading of NFR-04 and Gate 3B's one-current-media-file rule is therefore **not met** by the existing FFmpeg pipeline; an owner decision on that rule was requested. The ZIP writer itself deletes each completed media file after its archive commit.

**V3 passed** in the documented clean detached checkout: UI tests, sequential Node tests, Rust format, and `scripts/verify-foundation.ps1`. The full V2 and focused Windows queue, playlist, and process-tree tests also passed; see [3B-03 verification](3b-03.md). A local attempt to set an isolated temporary directory ACL for a real permission-denied output fault was rejected by automatic command approval policy. The existing Rust I/O classifier has focused disk-full and permission-code tests, but no end-to-end Windows output-permission observation was recorded.

Direct Tauri WebView interaction, a restart *during* packaging in the app process, and the isolated permission fault remain unobserved. Those gaps, plus the storage-rule decision, prevent this record from claiming the Gate 3B native-app acceptance criterion.
