<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# 2A-08 Windows native UI check

On 2026-10-24/25, `npm run tauri dev` opened the Windows WebView with Tauri available. The development UI used the saved offline single-video analysis, then submitted `enqueue_download` to Rust. The Queue card showed the URL, `Queued`, and 0%; `%LOCALAPPDATA%\com.zownload.app\zownload.sqlite3` contained the same queued UUID and MP3 request. Stop was disabled because no engine runs in 2A.

In Settings, the language was changed to Spanish and ZIP was enabled. The SQLite settings row became `es, 1, NULL`. After stopping and relaunching the native process, the UI loaded Spanish, the queued item, and the checked ZIP control. Settings Back restored focus to the header Settings button. Cancel removed the item from the UI and the SQLite queue table.

A prepared local SQLite fixture then added one History row and one `no_internet` error notification. After launching the native app again, both appeared in Spanish. Dismiss removed the notification from SQLite and moved focus to its card. Redownload from History enqueued the stored MP3 request directly as `queued`; the Input stayed empty. Cancel and History delete removed their SQLite rows. No engine, media, network, or update action was invoked.

Before the check, the local database had default Settings and empty Queue, History, and notifications. A SQLite backup was taken and restored after the check. The final database again has default Settings and zero rows in those three tables. Browser simulator tests remain separate from this native observation.
