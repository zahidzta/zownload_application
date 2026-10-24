<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# 1C-10 responsive and accessibility review

Date: 2026-10-24. The built offline app was loaded through a temporary local Vite preview in headless Chrome. The seeded mock store contained a paused single, a paused playlist with one failed entry, a completed playlist in History, and a persistent disk-full notification. The browser then resumed each item to capture active progress. No media or network request was made. [Raw measurements](captures/measurements.json) and the captures below are retained for owner review.

| State | Built capture | Observation |
|---|---|---|
| [Indexed single progress](../../../design/desktop/progress-bar-single.png) | [Active single](captures/desktop-progress-es.png) | Rounded dark Queue card, blue-to-cyan progress bar, percentage, and red Cancel follow the reference. The separate Stop button follows the owner's recorded decision. |
| [Indexed playlist progress](../../../design/desktop/progress-bar-playlist.png) | [Active playlist](captures/desktop-playlist-progress-es.png) | Item count, current title, failed count, progress bar, and right-side History retain the reference hierarchy. Speed and ETA are omitted per the 1C decision because the contract has no such fields. |
| Paused, History, failed notification | [Desktop activity](captures/desktop-activity.png), [mobile activity](captures/mobile-activity-es.png) | Paused rows have no bar, History retains direct Redownload and delete, and the persistent error stays visible after queue removal. |
| Mobile progress | [Single](captures/mobile-progress-es.png), [playlist](captures/mobile-playlist-progress-es.png) | Cards stack under Input; action targets fit the narrow card. |
| Empty activity | [Mobile empty](captures/mobile-empty.png) | Queue and History use the confirmed empty copy. |
| Settings | [Desktop](captures/desktop-settings.png), [Spanish mobile](captures/mobile-settings-es.png) | The unindexed screen uses the established card, border, spacing, type, and blue actions. The folder selector is desktop-only; developer information is a reviewable placeholder pending owner content. Engine actions and app-update information are separate. |

The browser measured activity and Settings in English and Spanish at 360, 369 at 2×, 738, 800, 1024, and 1920 CSS pixels, plus active progress and empty activity at 369: **26 observations**. In every observation, document and body scroll widths were at or below the viewport width. Visible button and select targets measured at least **44 CSS pixels high**. Opening Settings focused Back; the interactive tests cover keyboard selection, Back focus restoration, notification announcements, and queue/history actions.

One 1C contrast issue was fixed: small secondary Queue/History labels now use the existing `text` token instead of `text-muted`. Against the card background, the token contrast rises from about **4.18:1** to **7.66:1**; blue action text is about **7.50:1** and error text on its field about **5.35:1**. These are calculated from the declared sRGB token colors, not assistive-technology measurements.

The native Windows folder dialog was checked in `npm run tauri dev` using the app window's accessibility controls: Choose folder opened the Windows **Seleccionar carpeta** dialog; selecting its `docs` folder displayed the returned absolute path; reopening and cancelling closed the dialog without changing that path. The path survived a WebView reload, then **Use system Downloads** reset it. No file was written to the selected folder. Android folder hiding and picker selection/cancellation behavior also have focused injected UI tests.

The native pass also found the window title left at “Zownload Android spike” from Gate 0C. The Tauri window configuration now says “Zownload”; a second `npm run tauri dev` launch showed that exact title in the Windows title bar.

The exact Gate 1C V1 command passed after the preview and headless Chrome were stopped: frontend build, **55 interactive tests**, contract check, and **18 Node tests**. Its first run overlapped those browser processes and had transient interactive failures; a separate unobstructed `npm run test:ui` passed all 55, followed by the complete exact V1 pass. The exact V1D Rust command passed `cargo fmt --check` and `cargo check`. Physical-device touch and screen-reader judgement remain open. The owner has not yet judged 1C-06 through 1C-10 visual consistency or approved the 1C checkpoint.
