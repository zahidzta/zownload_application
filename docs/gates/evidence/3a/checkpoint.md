<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 3A — Sequential playlists checkpoint

**Status:** Accepted by the owner on 2026-10-30.

## Acceptance mapping

| Criterion | Evidence | Result |
|---|---|---|
| AC-04 — playlist preview lists entries | Native two-entry preview in [Windows review](native-review.md#native-observations), capture [playlist-preview.png](playlist-preview.png). | Pass |
| AC-08 — playlist counters and failure summary | Native mixed run displayed `2/3` and `2 correct, 1 failed`; interactive notification test verifies English and Spanish counts and translated fatal errors. | Pass |
| AC-12 — Max/Min quality behavior | Native MP3 Max decoded at 320 kb/s and Min at 128 kb/s; `playlist_cli` covers all four MP3/MP4 profiles, URL isolation, sequential calls, and output naming. Pinned selector observations are linked from [native review](native-review.md#limits). | Pass |
| AC-14 — continue after an entry fails | Native mixed playlist completed entries before and after the 404; deterministic queue test covers mixed, all-success, all-failed, and fatal disk-full outcomes. | Pass |
| Durable resume index | Native pause, close/reopen, and Continue resumed at entry 2 with `next_index = 1`; Rust queue test also covers restart recovery at index 1. | Pass |
| One History row and persistent failure summary | Native mixed request created one playlist History row and a stored `playlist_summary:2:1` notification that remained after restart. All-failed creates a notification without History; tests cover both. | Pass |
| Queue order, ZIP deferral, removal, and process cleanup | ZIP-enabled playlist stayed queued without blocking eligible ZIP-off jobs; FIFO and removal are tested in `queue_lifecycle`. Native window close terminated the captured yt-dlp process tree. | Pass |

V2 passed in a clean detached checkout: build, 61 UI tests, contract fixtures, 18 Node tests, Rust format, 79 Rust unit tests, all eligible CLI/queue/process-tree integrations, and Cargo check. V3 passed in a separate clean checkout: 61 UI tests, 18 Node tests, Rust format, frontend build, contract fixtures, 79 Rust unit tests, all eligible integrations, and the nine-image design inventory. V3 logs the expected existing `restore_baseline` dead-code warning. Two real-engine single CLI tests remained intentionally ignored because their test inputs are separately provisioned. See [3A-04 verification evidence](3a-04.md) and [native Windows review](native-review.md).

Gate 3A is limited to sequential ZIP-off playlist processing on Windows. ZIP packaging, bounded storage, filesystem stress, disk/permission integration stress, and ZIP-entry collisions remain in Gate 3B. The owner accepted this checkpoint on 2026-10-30, clearing the handoff to plan Gate 3B; implementation remains gated on owner review and acceptance of the [Gate 3B plan](../../gate-3b.md).
