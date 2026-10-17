# Zownload design references

These images are the confirmed visual references for Zownload. They define the visual language for the screens and components they show; they are not executable specifications of application behavior.

## Authority

Use the following order when implementing the UI:

1. `PROJECT.md` defines behavior, requirements, state transitions and business rules.
2. `shared/contract.ts` and `src-tauri/src/contract.rs` define data fields and serialized types.
3. The images indexed here define visual appearance and layout for the states/components they show.

If an image conflicts with `PROJECT.md` or either contract, report the conflict to the owner. Do not silently change confirmed behavior to match a screenshot.

## Reference inventory

### Desktop

| File | Reference | Dimensions |
|---|---|---:|
| [`desktop/main-input.png`](desktop/main-input.png) | Main input state | 1920 × 1200 |
| [`desktop/analysis-input.png`](desktop/analysis-input.png) | URL analysis/loading state | 1920 × 1200 |
| [`desktop/single-download.png`](desktop/single-download.png) | Single-item download state | 1920 × 1200 |
| [`desktop/playlist-download.png`](desktop/playlist-download.png) | Playlist download state | 1920 × 1200 |
| [`desktop/progress-bar-single.png`](desktop/progress-bar-single.png) | Single-item queue/progress component | 466 × 300 |
| [`desktop/progress-bar-playlist.png`](desktop/progress-bar-playlist.png) | Playlist queue/progress component | 497 × 426 |

### Mobile

| File | Reference | Dimensions |
|---|---|---:|
| [`mobile/main-input.png`](mobile/main-input.png) | Main input state | 738 × 1600 |
| [`mobile/single-download.png`](mobile/single-download.png) | Single-item download state | 738 × 1600 |
| [`mobile/playlist-download.png`](mobile/playlist-download.png) | Playlist download state and long-content behavior | 738 × 3263 |

## Implementation rules

- Preserve the references' colors, contrast relationships, shapes, spacing rhythm, borders, shadows, visual hierarchy and overall tone.
- During Phase 1, derive reusable design tokens instead of scattering sampled values through components. Document the chosen tokens when they are implemented.
- Implement reference dimensions faithfully, then create responsive behavior for intermediate widths rather than treating the images as fixed-size canvases.
- Use semantic HTML, visible focus states, keyboard navigation, sufficient contrast and large touch targets. Accessibility may refine a detail but must preserve the established visual identity.
- All UI copy must support English and Spanish. Text expansion must not break the layout.
- Do not embed these screenshots in the production interface or place them in `src/assets`; they are documentation references only.

## Freedom for missing designs

Screens, states and components not represented by an image may be designed by the implementing AI. This freedom is constrained by:

- the colors and visual language of the existing references;
- the layout and behavioral requirements in `PROJECT.md`;
- consistency between desktop and mobile;
- accessibility and responsive behavior;
- existing handcrafted Tailwind components; no external component library.

Examples of currently unillustrated areas include Settings, History, persistent error notifications, empty/error variants, `postProcessing`, `packaging`, focus/hover/disabled states and some mobile component details. Their absence is not permission to invent new product behavior.

## Phase usage

- **Gate 0A:** verify every indexed path exists and preserve the files. Do not implement the production UI.
- **Phase 1A:** derive tokens and implement the shared shell/layout.
- **Phase 1B:** implement the input, analysis, single and playlist flows against a mock engine.
- **Phase 1C:** implement queue/progress references and create missing history/settings/error states consistently.
- **Phase 6A:** perform final accessibility, translation and visual consistency review.

## Change control

- New references must be added to this inventory with their purpose and dimensions.
- Replacing a confirmed image requires owner approval.
- Keep filenames descriptive and use lowercase kebab-case.
- Do not overwrite a reference merely to make an implementation mismatch disappear.
