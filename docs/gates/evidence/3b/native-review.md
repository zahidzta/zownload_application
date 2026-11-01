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

On 2026-10-31, the owner approved revising FR-54 and NFR-04 to allow the partial ZIP plus temporary work files for only the current entry, with cleanup after archive verification and before the next entry. The observed source and tagged output are consistent with that rule. This synthetic sampler does not establish the real-engine peak or complete the native-app review.

**V3 passed** in the documented clean detached checkout: UI tests, sequential Node tests, Rust format, and `scripts/verify-foundation.ps1`. The full V2 and focused Windows queue, playlist, and process-tree tests also passed; see [3B-03 verification](3b-03.md). A local attempt to set an isolated temporary directory ACL for a real permission-denied output fault was rejected by automatic command approval policy. The existing Rust I/O classifier has focused disk-full and permission-code tests, but no end-to-end Windows output-permission observation was recorded.

## Tauri WebView startup smoke check

PR #124 passed CI but a local `npm run tauri dev` opened a white window. Before the fix, Vite accepted port 5173 without returning `/` within five seconds; another launch moved to port 5174 while Tauri still expected 5173. Isolated Vite probes showed that excluding generated `src-tauri/target`, `src-tauri/gen`, and `work` from file watching restored immediate HTTP responses. Tailwind's repository-wide source scan also took 33.1 seconds in one build. Commit `cda7a85` pins Vite to port 5173, restricts the watcher and dependency entry, and scopes Tailwind to `src` and `index.html`.

On a clean native restart after the fix, Vite was ready in 701 ms, `http://localhost:5173/` returned HTTP 200 in 0.0044 seconds, and Windows UI Automation found Download, Queue, and Settings in the Zownload WebView. The production build, 61 interactive UI tests, 18 root Node UI tests, Rust format check, and foundation verification passed. The exact local V3 `node --test` invocation also discovered an ignored old checkout under `work/engine/2b-09/clean` and failed there because it loaded a second React copy; the intended root tests passed explicitly, and the earlier clean detached V3 pass remains recorded above. This smoke check verifies app startup only.

Direct Tauri playlist interaction, a restart *during* packaging in the app process, the real-engine storage peak, and the isolated permission fault remain unobserved. Those gaps prevent this record from claiming the Gate 3B native-app acceptance criterion.
