<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 1A checkpoint — 2026-10-22

**Status:** 1A-02 through 1A-09 are integrated, 1A-10 verification passed, and the owner explicitly accepted the Gate 1A results on 2026-10-22. This satisfies the owner-acceptance condition for 1B planning; 1B implementation still requires review of the [Gate 1B task plan](../../gate-1b.md). Scope and exit criteria: [Gate 1A](../../gate-1a.md) and [PROJECT.md Appendix A](../../../../PROJECT.md).

## Focused verification

From `task-1a-10` at `5ef80c3`, the exact 1A-10 command completed with exit code 0:

```powershell
powershell -NoProfile -Command 'node --test; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; powershell -NoProfile -File scripts/verify-foundation.ps1'
```

- `node --test`: **18 passed, 0 failed** across the existing header, i18n, navigation, primitive, shell, and transport tests. These cover en/es key parity and all contract error names, shell copy switching, navigation state, semantic markup, accessible names, disabled primitive semantics, and transport shape. They do not simulate a full screen reader or prove pixels.
- Foundation verifier: `npm run build`, `npm run check:contracts`, Rust tests (**6 passed**), and design inventory (**9 tracked images at indexed dimensions**) all passed. The latest commit affecting `package.json`, `package-lock.json`, or either contract file predates 1A (`ef52bf0`); this stage added no dependency or contract edit.
- The parallel Node test run emitted non-fatal Vite SSR optimizer messages about port `24678` being in use and Windows `EPERM` renaming temporary dependency bundles. All 18 assertions and the subsequent build passed. Revisit test isolation when planning the interactive 1B suite; this was not treated as a new dependency approval.

## Visual and interaction observations

- **Desktop, 1920 × 1200:** In headless Chrome, the main card starts at CSS `(270, 126)` and is 900 px wide; the Queue and History cards stack to its right. Header height, dark canvas, flat outlined cards, spacing, and negative space align with the [confirmed desktop main-input image](../../../design/desktop/main-input.png) and [visual tokens](../../../design/tokens.md). The visible Download card is intentionally an empty 1A slot; URL/form controls are a 1B deliverable. The Settings icon is the owner-approved addition to the reference header.
- **Mobile, 369 CSS px at 2× density (738 × 1600 capture):** The main card starts at CSS `(24, 94)`, with Queue and History below. Relative to the app area of the [confirmed mobile main-input image](../../../design/mobile/main-input.png), the card top is about 2 CSS px away after excluding its 80 physical-pixel status bar. Card width, 24 px gutters, and vertical spacing follow the reference. The reference browser toolbar is outside the app. The [1A-08 PR](https://github.com/zahidzta/zownload_application/pull/80) records the earlier responsive review; the owner accepted that shell on 2026-10-22.
- **Intermediate widths:** Browser device emulation measured `document.documentElement.scrollWidth === clientWidth` at 360, 369, 738, 1024, and 1920 CSS px in both en and es. The shell is one column below 1024 px and two columns at 1024 px. Spanish card headings expanded without clipping.
- **Settings and focus:** In a 360 px browser viewport, Tab reached the language and Settings buttons in order, each with a computed 3 px blue focus outline. Opening Settings produced one visible named main landmark and focused **Back to downloads**; activating Back restored the main shell and returned focus to Settings. Its single-card treatment follows the owner's 1A-09 direction and visual approval; [1A-09 PR](https://github.com/zahidzta/zownload_application/pull/81) contains the implementation review. The browser check used button click activation after the Tab/focus check; native keyboard semantics and disabled behavior are covered by the primitive tests. The shell has no disabled action to exercise yet.

## Decisions, limits, and exit

- The owner chose Queue/History on the **right** for desktop, resolving the conflict with `PROJECT.md:107-108` in favor of the [confirmed desktop image](../../../design/desktop/main-input.png). The owner chose Settings to the right of language, resolving the header image omission against `PROJECT.md:102,651`. The owner approved one Settings card with Back and has now accepted its visual treatment. These directions are recorded in [STATE](../../../STATE.md); no authority file or confirmed image was changed.
- 1A supplies a shell, not the Input controls, live queue, history entries, Settings controls, notifications, or download engine. Missing mobile analysis and later Settings/error/progress states were [1B/1C design decisions](../../phase-1-outline.md) at this checkpoint. Already-MP3 bitrate behavior, interactive test dependencies, exact Spanish copy, final logo/icon, accessibility baseline, developer-info content, and error grouping were owner questions at 1A exit; the subsequent [1B plan](../../gate-1b.md) records the decisions made for that stage.
- **Exit status: accepted by the owner on 2026-10-22.** The owner explicitly approved the 1A results, allowing task **1B-01 — prepare the Gate 1B task plan and decision review** to begin under [Appendix A's delivery rule](../../../../PROJECT.md).
