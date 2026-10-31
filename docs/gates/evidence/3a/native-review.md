<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 3A — Native Windows playlist review

**Observed:** 2026-10-30. **Environment:** Windows 11 x64, debug Tauri desktop window with its Vite WebView origin, local HTTP fixture at `127.0.0.1:8877`, ZIP disabled, and the existing app-data engine copies. WebView2 `156.0.4314.50` exposed its local debugging endpoint for control and screenshots, following Microsoft's [WebView2 debugging guide](https://learn.microsoft.com/en-us/microsoft-edge/webview2/how-to/debug-visual-studio-code). The UI was confirmed to use the native Tauri transport; queue, History, and notifications were also read back through the Rust commands.

The local media inputs were generated for this review with the pinned FFmpeg from two-second color and sine sources. A local HTML page exposed two direct MP4 entries. A second page exposed those entries plus a missing URL that returns HTTP 404. No public media was fetched. The source fixture and all output remained under the ignored `work/engine/3a-native-fixture/` directory.

## Engine identity

The three executable hashes in the app-data engine directory matched the pinned Gate 0B resources:

| Executable | SHA-256 |
|---|---|
| `yt-dlp.exe` 2026.08.19 | `66674953fe251b89f4d08c5f0e35e0728679bd67ab3d7d05c0562af101dd3e7a` |
| `ffmpeg.exe` 8.1.3 | `fa050630ddf5b7c3303d8dab5e5a42e7023547fb78ec9b90b5be0a4f788a7e66` |
| `qjs.exe` 2026-06-04 | `bec67f8f87fa22958d3ab8be5508088116b8bff90032323d82c94545e1698b83` |

## Native observations

| Scenario | Observation and committed capture |
|---|---|
| Tiny playlist preview | Two entry titles appeared in the native playlist card. [Preview](playlist-preview.png). |
| MP3 Max, pause and resume | The two-entry request used Max. While entry 2 was downloading, the UI showed Paused and `1/2`; the durable snapshot had `next_index = 1`, `currentTitle = Gate 3A Tiny Playlist (2)`, and 3.63% for that entry. After app close/reopen, it remained paused and did not auto-start. Continue resumed entry 2. Captures: [paused](playlist-paused.png), [paused after restart](playlist-restart-paused.png), [completed](playlist-completed.png). |
| Max output | `first.mp3` (83,785 bytes) and `second.mp3` (83,786 bytes) decoded through FFmpeg as 320 kb/s MP3. FFmpeg metadata showed titles `first` and `second` and album `Gate 3A Tiny Playlist`. SHA-256: `BE3FE5417F15B48FF238A563F413F9C054DD31E653E6708ED6EFB8A045169188` and `6B47124F7D3C6F60B178F99CA6CC0218311417A66F317DF379A0674E90AD3CCB`. |
| Mixed playlist, Min | The native run completed the first and third entries after the missing middle URL failed. Queue displayed `2/3` and `2 correct, 1 failed`; History gained exactly one row for the playlist request; its stored quality was Min; and the persistent notification stored `playlist_summary:2:1`. After app restart the notification still displayed `2 correct, 1 failed`. Capture: [mixed failure and notification](playlist-mixed.png). |
| Min output | `first (1).mp3` (33,630 bytes) and `second (1).mp3` (33,631 bytes) decoded as 128 kb/s MP3 and retained the playlist album/title mapping. SHA-256: `46B20C692786E52431F9EA141FE26FDC14E88C64BA5921415E8F4AC191AF6572` and `29430A41EE85290B1444025BA51B34D64D53C967CEA6FD07BFC49F77327557E3`. Existing Max outputs remained intact; Min collisions received numbered names. |
| Close and child cleanup | Closed the native window during a subsequent playlist run. Captured app-data `yt-dlp.exe` PIDs `30124` and `25100` (parent/child) both exited within two seconds. Reopening restored the request as Paused at `1/2`; no engine process auto-started. The paused row was then removed through the UI. |

The pre-review app database was copied aside before changing the ZIP setting and output folder. After the app closed, `zownload.sqlite3` was restored and its SHA-256 matched the original `96fae310f25712a1a6410e4dbedb04722f25f85726c8df0686bc2089df23d004`. The fixture output folder is separate from the user's Downloads folder.

## Limits

The native media fixture is synthetic, two entries long, and tests the MP3 Max/Min outputs. It does not claim human playback or cover public-site reliability. MP4 Max/Min selector profiles and URL isolation are covered by `playlist_cli`; the pinned selector and source-format observations remain in [Gate 0B MP4](../0b/mp4.txt), [Gate 0B MP3 playlist](../0b/mp3-playlist.txt), and [3A-03 evidence](3a-03.md). ZIP packaging, bounded storage, disk/permission stress, and ZIP collisions remain in Gate 3B.
