<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 3B checkpoint — accepted 2026-10-31

Gate 3B is **accepted by the owner on 2026-10-31**. The [Windows synthetic and native review](native-review.md) and [V2 evidence](3b-03.md) support the ZIP queue implementation; V3 passed after the native restart fixes. Gate 3C planning may proceed under [Gate 3B](../../gate-3b.md#stage-exit).

| Criterion | Current evidence | Status |
|---|---|---|
| AC-13 | Native WebView submitted real-engine ZIP playlists; all-success and mixed archives had uncompressed, CRC-valid entries. ZIP-off playlist CLI remains covered. The interrupted second entry resumed from the committed archive boundary. | Passes Gate 3B review. |
| AC-16 | Native duplicate `dup.mp4` entries became `dup.mp4` and `dup (1).mp4`; redownload created `Gate 3B Mixed (1).zip` without replacing the original. Restart recovery preserved the first entry. | Passes Gate 3B review. |
| AC-17 | Synthetic disk-full canceled the whole job and persisted `disk_full`. Isolated native Windows write denial produced `permission_denied`, zero queue rows, no incomplete output or child process, and an empty owned work directory. | Passes Gate 3B review. |
| NFR-04 | Under the owner-approved current-entry rule, the real-engine 5 ms sampler observed at most 1 entry work directory, 2 current media files, 7 staging files and 11,805,745 staging bytes. Verified entries' work files were removed before the next entry. | Passes for the measured native fixture; the sampled peak is not a universal size bound. |

**Owner decision:** On 2026-10-31, the owner accepted the Gate 3B checkpoint and directed planning for Gate 3C. The native disk-full scenario used a deterministic simulation so no shared disk was filled; the Windows permission denial was exercised in the native app.
