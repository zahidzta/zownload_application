<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 3B checkpoint — pending review

Gate 3B is **open**. The [Windows synthetic review](native-review.md) and [V2 evidence](3b-03.md) support the ZIP queue implementation, and V3 passed. The required direct native-app and storage observations are still incomplete. No Gate 3C work may start before owner acceptance under [Gate 3B](../../gate-3b.md#stage-exit).

| Criterion | Current evidence | Status |
|---|---|---|
| AC-13 | ZIP-on synthetic playlists publish one uncompressed archive; ZIP-off playlist CLI remains covered. Source and tagged output briefly coexist during FFmpeg for the current entry. | Functional path passes under the owner-approved current-entry work-file rule; native-app review remains. |
| AC-16 | Duplicate entry titles and archive collisions produce numbered names without replacing existing files; recovery and cancellation tests pass. | Passes synthetic Windows tests. |
| AC-17 | Synthetic disk-full cancels the complete ZIP job, leaves no archive or queue row, and persists `disk_full`; process-tree tests pass. | Permission fault and native-app observation pending. |
| NFR-04 | The owner approved current-entry work files on 2026-10-31. The 2 MiB-entry fixture sampled 5 staging files, 8,389,117 bytes, and 2 current media files at 5 ms intervals. | Synthetic observation is consistent with the revised rule; native-app and real-engine peak remain to be reviewed. |

Next work in **3B-04**: observe the playlist, current-entry storage peak, and restart in the native Tauri WebView, and obtain a safe isolated permission-fault result. Then update this checkpoint and request explicit owner acceptance.
