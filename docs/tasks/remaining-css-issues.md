# Remaining CSS work after the 12-batch integration

Scope note: this file is a standalone backlog record. It is **not** part of the
12-batch integration PR (#328) and carries no validation claims for any item
listed here.

The 12 original batches integrated into `master` covered 120 distinct GitHub
issues across `#168`–`#308`. Two separate groups of work remain open:

1. **21 issues in the `#168`–`#308` range that no batch covered.**
2. **5 issues whose batch implementation landed but is documented as partial.**

All 26 issues are still OPEN on `RoboXGamer/SolidNativeZigExperiment`. None of
them were implemented, and none were validated.

---

## Group 1 — Not covered by any of the 12 batches (21 issues)

These issue numbers fall inside the `#168`–`#308` span covered by the batches,
but were never assigned to one of the 12 batch scopes.

### CSS 2024 (18 issues)

| Issue | Title | Feature key |
|---|---|---|
| #169 | Named colors | `named-color` |
| #179 | opacity | `opacity` |
| #180 | outline | `outline` |
| #181 | Outlines | `outlines` |
| #183 | overflow: clip | `overflow-clip` |
| #184 | overflow | `overflow-shorthand` |
| #186 | padding | `padding` |
| #212 | RGB | `rgb` |
| #215 | round(), mod(), and rem() | `round-mod-rem` |
| #232 | Static positioning | `static-positioning` |
| #233 | steps() easing | `steps-easing` |
| #241 | tab-size | `tab-size` |
| #245 | text-align | `text-align` |
| #267 | Trigonometric functions | `trig-functions` |
| #275 | Small, large, and dynamic viewport units | `viewport-unit-variants` |
| #276 | Viewport units | `viewport-units` |
| #280 | white-space | `white-space` |
| #285 | word-spacing | `word-spacing` |

### CSS 2025 additions (3 issues)

| Issue | Title | Feature key |
|---|---|---|
| #289 | abs() and sign() | `abs-sign` |
| #293 | Conic gradients | `conic-gradients` |
| #297 | Gradients | `gradients` |

---

## Group 2 — Partial implementations carried over from the batches (5 issues)

These landed inside a batch scope but the batch report and the integration
checkpoint both record them as **partial**, not complete.

| Issue | Title | Feature key | Batch | Partial status as documented |
|---|---|---|---|---|
| #296 | font-feature-settings | `font-feature-settings` | batch 2 | Native plumbing exists; full CSS font-feature-settings behaviour not established. |
| #295 | ::details-content | `details-content` | batch 2 | Pseudo-element is serialised, but the full `::details-content` lifecycle is not established. |
| #294 | content-visibility | `content-visibility` | batch 2 | Containment behaviour is not established end to end. |
| #291 | Active view transition | `active-view-transition` | batch 2 | Active transition entry is not wired to a native transition lifecycle. |
| #178 | Oklab and OkLCh | `oklab` | batch 12 | Mixed-type parameters and sRGB conversion covered; full Oklab/OkLCh conformance not established. |

---

## Related known gaps (not separate issues)

These are limitations recorded in the batch reports and integration checkpoint.
They are not tracked as their own GitHub issues.

- SVG background rasterizer is a white placeholder.
- Non-circle/ellipse SVG shapes use bounding fill.
- Subgrid parsing does not establish inherited tracks.
- `shape-outside` is not wired into block layout.
- `starting-style` is serialised without a native transition lifecycle.
- Polygon interpolation returns the destination value.
- Host preference detection uses environment overrides, not Windows
  accessibility/theme notifications.
- Preference change listeners, nested `q` child text, full top-layer escape from
  ancestor contexts and SVG pointer geometry need further conformance work.
- Page/path helpers and `paint-order` require further feature-specific
  conformance validation.

---

## Status

Everything listed above is unimplemented or partial. No builds, tests,
typechecks or test authoring were performed for any item in this file.
