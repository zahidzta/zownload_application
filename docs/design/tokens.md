<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Phase 1A visual tokens

These values are implemented in [`src/styles.css`](../../src/styles.css) with Tailwind v4 `@theme` variables. Tailwind utilities such as `bg-canvas`, `border-border`, `rounded-card`, `p-card`, and `text-body` use the same variables as the CSS for the existing bridge probe. The values are candidates for the 1A-05 owner visual review.

## Reference and measurement

- Primary references: [desktop main input](desktop/main-input.png) at 1920 × 1200 and [mobile main input](mobile/main-input.png) at 738 × 1600. The mobile status bar and browser toolbar are outside the app.
- The same dark canvas, field fill, card border, and blue action recur in the other [indexed images](README.md). The mobile capture shifts the blue by one RGB step; the desktop image provides the CSS value.
- Desktop main input shows a 30 px card inset, about 30 px between the input card and side cards, roughly 16 px card corners, 10 px control corners, and a 56 px primary button. The mobile capture is approximately twice CSS pixel density; these measurements are guides for later layout work, not fixed screenshot coordinates.
- No visible card elevation is present in the main input references. The card shadow token is therefore `none`; separation comes from a border.

## Color

| Token | Value | Use |
|---|---|---|
| `--color-canvas`, `--color-card` | `#0a0a0a` | App background and card fill |
| `--color-field` | `#171717` | URL input fill |
| `--color-border` | `#262626` | Card, field, and unselected control border |
| `--color-primary` | `#155dfc` | Primary action fill |
| `--color-selection` | `#0d1623` | Selected format fill |
| `--color-selection-border` | `#2b7fff` | Selected format border |
| `--color-accent-text` | `#50a2ff` | Selected format text and small accent copy |
| `--color-text-strong` | `#f5f5f5` | Main headings and action text |
| `--color-text` | `#a1a1a1` | Labels, card headings, normal copy |
| `--color-text-muted` | `#737373` | Decorative or disabled copy only |
| `--color-focus` | `#50a2ff` | Keyboard focus outline |

Normal text on the canvas has a measured contrast ratio of 7.66:1; strong text is 18.16:1. Strong text on the blue action is 4.81:1. Muted text is 4.18:1 and is not for essential body copy. The screenshot border is intentionally subtle (1.31:1 against the canvas); visible focus uses a 3 px blue outline with a 2 px offset. Focus treatment is an accessibility extension because the references do not show a focused state.

## Size, shape, and type

| Token | Value | Intended use |
|---|---|---|
| `--spacing-compact` | 8 px | Small vertical separation |
| `--spacing-control-gap` | 10 px | Input/button padding and compact gaps |
| `--spacing-stack` | 16 px | Default component spacing |
| `--spacing-section` | 24 px | Group and mobile card spacing |
| `--spacing-card` | 30 px | Desktop card inset and column gap |
| `--spacing-shell` | 40 px | Header-to-content breathing room |
| `--radius-control` | 10 px | Input and button corners |
| `--radius-card` | 16 px | Card corners |
| `--shadow-card` | none | Flat cards with a 1 px border |
| `--font-sans` | System UI stack | Sans serif approximation; the source font is not identifiable from raster images |
| `--text-small` | 14/20 px | Secondary copy |
| `--text-body` | 16/24 px | Inputs, labels, body copy |
| `--text-card-title` | 18/24 px | Card headings |
| `--text-app-title` | 24/32 px | App name |

The scale is a reusable interpretation of the visible spacing and typography. Exact responsive positions belong to tasks 1A-07 and 1A-08; the desktop side placement and header settings action remain owner decisions recorded in [Gate 1A](../gates/gate-1a.md).
