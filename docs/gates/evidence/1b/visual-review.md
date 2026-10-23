<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# 1B-11 responsive and accessibility review

Date: 2026-10-23. The built app was loaded in headless Chrome from a temporary local static file server, which shut down after the measurements. No Vite or Tauri dev server was started. The simulator stayed offline. The [raw measurements](captures/measurements.json), [keyboard observations](captures/keyboard.json), and captures below are retained for review.

## Reference comparison

| Indexed state | Built capture | Observation |
|---|---|---|
| [Desktop Input](../../../design/desktop/main-input.png) | [Input](captures/desktop-input.png) | Main card and right Queue/History column follow the accepted 1A placement; form fields, format choices, and Convert match the reference structure. |
| [Desktop analyzing](../../../design/desktop/analysis-input.png) | [Analyzing](captures/desktop-analyzing.png) | Disabled blue action and spinner use the confirmed loading treatment. |
| [Desktop single](../../../design/desktop/single-download.png) | [Single](captures/desktop-single.png) | Thumbnail, metadata, quality, and Download retain the confirmed hierarchy. The fixture media differs from the reference, and its missing estimate correctly hides size. |
| [Desktop playlist](../../../design/desktop/playlist-download.png) | [Playlist](captures/desktop-playlist.png) | Two-column preview, Back, Max/Min, and separate bounded title card follow the reference structure. The offline Blender mock thumbnail and 17-item fixture differ from the pictured album. |
| [Mobile Input](../../../design/mobile/main-input.png) | [Input](captures/mobile-input.png) | One-column card and controls fit the 369 CSS-pixel app area of the 738-pixel, 2× reference. Browser chrome and system status bars in the reference are outside this app capture. |
| [Mobile single](../../../design/mobile/single-download.png) | [Single](captures/mobile-single.png) | Thumbnail, metadata, quality, full-width Download, Queue, and History fit without clipping. History remains empty until 1C. |
| [Mobile playlist](../../../design/mobile/playlist-download.png) | [Playlist](captures/mobile-playlist.png) | Preview and title card stack before Queue and History. The title list scrolls within its card and preserves long names. |

The unindexed mobile analyzing state uses the confirmed mobile Input layout and desktop loading treatment: [capture](captures/mobile-analyzing.png). The minimal accepted Queue row from 1B-10 is shown in [mobile queued](captures/mobile-queued.png); progress and controls are 1C work.

## Browser measurements

Headless Chrome used 1920 × 1200 desktop, 369 × 800 CSS pixels at device scale 2 for the indexed 738-pixel mobile width, and 360, 738, 800, and 1024 CSS-pixel intermediate widths. At each width, both English and Spanish were measured in Input, typed error, single preview, playlist preview, and accepted Queue states: 60 combinations total. `document.documentElement.scrollWidth` and `document.body.scrollWidth` equaled the viewport width in all 60; no horizontal overflow was measured.

| CSS width | Locale/state combinations | Playlist list height / content height | Horizontal overflow |
|---:|---:|---:|---:|
| 360 | 10 | 352 / 1032 px | 0 |
| 369 at 2× | 10 | 352 / 984 px | 0 |
| 738 | 10 | 352 / 744 px | 0 |
| 800 | 10 | 352 / 744 px | 0 |
| 1024 | 10 | 416 / 768 px | 0 |
| 1920 | 10 | 416 / 744 px | 0 |

Every playlist measurement contained 17 list items and `scrollHeight > clientHeight`. At 369 CSS pixels, Back was 44 px high, and the quality selector and Download button were each 279 × 44 px in both languages. A focused quality selector changed from 320 to 256 with Arrow Down; Enter on focused Back restored Input; Arrow Down on the focused playlist region moved its scroll position to 40 px. The error appeared in an `alert` region in both languages at every width; the Input tests also assert `aria-invalid` and immediate translation.

No 1B-specific clipping, focus, or touch issue was found in these measurements, so no component or style change was needed. Browser emulation checks layout and keyboard behavior; physical-device touch and assistive-technology judgement remain for the owner and later accessibility review.

## Verification and pending review

Exact 1B-11 V1 passed on 2026-10-23: `powershell -NoProfile -Command 'npm run build; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; npm run test:ui; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; npm run check:contracts; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; node --test --test-concurrency=1; exit $LASTEXITCODE'`. Results: build passed, 32 interactive tests passed, contract check passed, and 18 Node tests passed. No dependency, contract, `PROJECT.md`, or Rust file changed in this task.

**PENDING owner review:** judge visual fidelity of 1B-08 single, 1B-09 playlist, 1B-10 queued row, and 1B-11 responsive treatment, especially the new mobile analyzing state. The owner should inspect the running app at the indexed dimensions before accepting the 1B checkpoint. The indexed History examples are not implemented in 1B; their behavior belongs to 1C. The Gate 1B checkpoint and explicit acceptance remain 1B-12, and 1C must not start until that acceptance.
