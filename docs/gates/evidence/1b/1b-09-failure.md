<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# 1B-09 verification interruption

On 2026-10-23, the first exact V1 run passed `npm run build` and then stopped in `npm run test:ui`: 26 tests passed and two playlist tests failed. `npm run check:contracts` and the Node suite were not reached. Both failures reported `Found multiple elements with the role "region" and name "Items in list"` at `tests/interactive/playlist.test.tsx:40` and `:77`.

Cause: `Card` renders a `<section aria-labelledby>` whose heading is “Items in list”. `PlaylistPreview` nested a focusable `<div role="region" aria-label="Items in list">` inside it. Both elements consequently had the same role and accessible name. The test query was valid: it intended to select the scrollable region and then check its bounded height, 17 entries, and keyboard focus.

Correction: the outer visual card is now a plain `<div>` with a visible `<h2>`. The inner scrollable region uses that heading through `aria-labelledby` and keeps `tabIndex={0}`. The tests and acceptance criteria were not weakened.

The initial work commit is `f0f8b23`; the initial blocked-state commit is `fcc9d69`. Subsequent verification and review results are recorded in `docs/STATE.md`.
