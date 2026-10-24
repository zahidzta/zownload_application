<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 1B checkpoint — 2026-10-23

**Status:** 1B-02 through 1B-11 are integrated. The owner approved the pending 1B visual changes on 2026-10-23. This checkpoint records the review and verification for 1B-12; explicit owner acceptance of the **1B checkpoint** is still required before 1C under [Appendix A](../../../../PROJECT.md) and the [Gate 1B plan](../../gate-1b.md).

## Acceptance evidence

| Criterion | Evidence and result |
|---|---|
| AC-01 — persistent header, logo, name, language, Settings | [1A checkpoint](../1a/checkpoint.md) records the accepted shell; the mounted [header interaction test](../../../../tests/interactive/header.test.tsx) exercises language controls. |
| AC-02 — translated red invalid/unsupported URL error in Input | [Input tests](../../../../tests/interactive/input.test.tsx) exercise typed failures, location below the URL, `aria-invalid`, and immediate en/es switching. [Simulator tests](../../../../tests/interactive/simulator.test.tsx) distinguish invalid, unsupported, missing, and restricted cases. |
| AC-03 — single preview and quality | [Single tests](../../../../tests/interactive/single.test.tsx) cover metadata, four MP3 requested maxima, available MP4 heights, Back, null-thumbnail fallback, and optional matching size estimates. The [visual review](visual-review.md) compares desktop and mobile references. |
| AC-04 — playlist preview, Max/Min, titles | [Playlist tests](../../../../tests/interactive/playlist.test.tsx) cover all 17 titles, bounded keyboard scrolling, long/duplicate names, Max/Min, and null-image fallback. The [visual review](visual-review.md) compares desktop and mobile references. |
| AC-05 — Back returns to Input | [Flow tests](../../../../tests/interactive/flow.test.tsx) and [single tests](../../../../tests/interactive/single.test.tsx) cover Back, preserved URL/format, and invalidation of pending analysis. |
| AC-10 — immediate English/Spanish copy | [Flow](../../../../tests/interactive/flow.test.tsx), [Input](../../../../tests/interactive/input.test.tsx), [enqueue](../../../../tests/interactive/enqueue.test.tsx), and existing Node i18n tests cover complete labels, translated errors, and live switching. The [browser review](visual-review.md) measured both languages in each 1B state. |
| AC-18 — cleared Input after accepted Download | [Enqueue tests](../../../../tests/interactive/enqueue.test.tsx) cover exact single MP3 and playlist MP4 Min requests, duplicate-click blocking, immediate cleared Input after acceptance, the queued snapshot, and typed rejection without an invented item. AC-18's terminal queue-removal clause belongs to 1C and is **open**. |

## Deterministic scenarios and contract decisions

- The injected [offline simulator](../../../../src/transport/simulator.ts) analyzes the observed short-video URL, a pure 17-entry Blender playlist, and a watch/list URL that resolves to one video. Its [interactive tests](../../../../tests/interactive/simulator.test.tsx) also cover typed error paths, ordered queue snapshots with distinct ids, removable queue subscriptions, and rejected malformed requests. It performs no network fetch or media write; these results establish UI flow and exchanged shapes, not actual download behavior.
- The owner approved `AnalyzeResult.single.estimates?` in the [1B plan](../../gate-1b.md). Both contracts include the optional, format-specific quality estimate; the UI shows size only for a matching entry. The fixture supplies no estimate, so its preview shows no invented size.
- The owner confirmed MP3 presets as requested maxima: copy an MP3 source at or below the selected bitrate, reencode one above it, and encode a non-MP3 source to the selected bitrate. [PROJECT.md](../../../../PROJECT.md) and both contracts were reconciled in 1B-02. The simulator does not establish production encoding behavior.
- The owner requested the actual short-video still, a full-width mobile Download button, and playlist cover selection that prefers the playlist cover then its first entry. The bundled artwork and attribution are in [public fixtures](../../../../public/fixtures/README.md); the [visual review](visual-review.md) contains updated captures. Each eventual playlist download must keep its own entry thumbnail.

## Visual and accessibility review

The owner approved the pending 1B-08 through 1B-11 visual changes on 2026-10-23. The [1B-11 visual review](visual-review.md) compares every indexed 1B Input, analyzing, single, and playlist reference with built-app captures. Its 60 en/es viewport/state measurements at 360, 369 (2×), 738, 800, 1024, and 1920 CSS pixels found no horizontal overflow. The 17-title list remained bounded; mobile Back, quality, and Download controls were at least 44 CSS pixels high. Browser keyboard checks changed quality, activated Back, and scrolled the playlist region; errors appeared in an alert region. The mobile analyzing state combines the owner-approved mobile Input layout with the desktop loading treatment. Physical-device touch and assistive-technology review remain open.

## Checkpoint verification

From `task-1b-12` on 2026-10-23, the exact V2 command exited **0**:

```powershell
powershell -NoProfile -Command 'npm run build; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; npm run test:ui; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; node --test --test-concurrency=1; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; powershell -NoProfile -File scripts/verify-foundation.ps1; exit $LASTEXITCODE'
```

- Frontend build passed; 7 interactive test files passed with **33/33 tests**.
- The sequential Node suite passed **18/18 tests** with no failures. Vite rescanned dependencies during this suite, extending it to about 316 seconds; the rescans did not fail a test.
- The foundation verifier repeated the frontend build, checked TypeScript/shared JSON contract fixtures, passed **6 Rust unit tests plus 1 Rust contract-parity test**, and verified all **9 tracked design images** at their indexed dimensions.
- This checkpoint task changes documentation only; no production source, dependency, contract, or design image is changed.

## Exit and carried limits

Gate 1B supplies an offline mock flow through accepted enqueue and a minimal queued row. Queue progress and controls, terminal removal, history, redownload, settings controls, notifications, and restart persistence belong to 1C. Real engine output and source-bitrate behavior remain for later production stages. The Android distribution blocker and other release conditions in [STATE](../../../STATE.md) remain open. No 1C planning or implementation begins until the owner explicitly accepts this checkpoint.
