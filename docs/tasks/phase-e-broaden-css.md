# CSS Broadening Implementation Handoff (Phase E)

Source baseline: `feat/phase-e-broaden-css` branch in `C:\Users\A5IN\.t3\worktrees\draft1\feat-phase-e-broaden-cs-5a4d75e62ce733d0`.
Follows Phase A (`docs/tasks/box-model-sizing.md`), Phase B (`docs/tasks/flex-block-layout.md`), Phase C (`docs/tasks/select-control-phase-c.md`), and Phase D (`docs/tasks/text-overflow.md`).
References:
- `docs/compatibility-audit-2026-11-11.md` (Sections 7.7, 7.8, 7.9, Section 8 Phase E)
- Issues: #290 (CSS Positioning Engine & Containing Blocks), #293 (CSS Gradients Engine), #297 (Box Effects & 2D Transforms)
- W3C CSS Positioned Layout Module Level 3
- W3C CSS Grid Layout Module Level 2
- W3C CSS Box Alignment Module Level 3
- W3C CSS Images Module Level 3 & 4 (Gradients)
- W3C CSS Transforms Module Level 1
- W3C CSS Transitions Level 1

---

## Scope of Work & Completed Deliverables

This phase delivers complete CSS Positioning (`relative`, `absolute`, `fixed`, `sticky`), containing block geometry calculations, stacking contexts and `z-index` paint & hit-test ordering, complete CSS Grid Layout (explicit & implicit tracks, `repeat()`, `minmax()`, `fr`, named areas & lines, dense/sparse placement), CSS Box Alignment (`place-content`, `place-items`, `place-self`, `safe`/`unsafe` overflow safety, directional alignment), visual painting effects (linear, radial, conic gradients, multi-layer box-shadow with blur, opacity, border-radius clipping), 2D transforms (`translate`, `rotate`, `scale`, `skew`, `matrix`, `transform-origin`), and CSS transition interpolation with timing curves.

### 1. CSS Positioning Engine (Issue #290)
- **Position Schemes:**
  - `position: relative`: Computes insets (`top`, `right`, `bottom`, `left`) as visual offsets from normal flow position without affecting the flow position of surrounding siblings.
  - `position: absolute`: Extracts child from normal block, flex, and grid flow. Computes containing block as the padding box of the nearest positioned ancestor (or viewport if no positioned ancestor exists). Insets place the element within this containing block.
  - `position: fixed`: Extracts child from normal flow. Containing block is the viewport (`0, 0, viewport_width, viewport_height`). Fixed elements remain pinned to the viewport and are unaffected by parent scroll offsets.
  - `position: sticky`: Evaluates within normal flow and clamps between the scroll container's sticky inset (`viewport.y + top`) and the parent content box boundary (`parent.bottom - item.height`).
- **Stacking Contexts & Z-Index Ordering:**
  - `Scene.getPaintOrder(allocator)` produces a paint index order sorted by `zIndex` ascending while preserving document tree order for elements with identical z-index.
  - `windows.zig` `renderScene` iterates through `getPaintOrder(allocator)` to ensure higher z-index elements paint over lower z-index elements.
  - `Scene.hitTest` traverses `getPaintOrder` in reverse order so the topmost painted element receives pointer clicks and focus first.
  - Document order in `Scene.items` is preserved, maintaining document focus sequence for Tab navigation (FLEX-06).

### 2. Complete CSS Grid Layout
- **Track Definition & Sizing (`modules/ui_core/layout_grid.zig`):**
  - Explicit and implicit tracks with `fr`, `px`, `%`, `minmax()`, `auto`, `min-content`, and `max-content`.
  - `repeat()` syntax with integer repetitions and dynamic `auto-fill` / `auto-fit` based on available container size and min-track sizes.
  - Named grid lines with `[line-name]` syntax and line/span resolution.
- **Named Areas & Auto-Placement:**
  - `grid-template-areas`: Parses ASCII area matrices into 2D row and column span bounds.
  - `grid-area`, `grid-column`, `grid-row`, `grid-column-start`, `grid-column-end`, `grid-row-start`, `grid-row-end`.
  - Dense (`gridAutoFlow: "row dense"` or `"column dense"`) and sparse auto-placement algorithm with 2D cell occupancy collision detection.
- **Out-of-flow Extraction:**
  - `position: absolute` and `position: fixed` children are extracted prior to track generation and placed via `layoutOutOfFlowChildren`.

### 3. CSS Box Alignment Module
- **Two-Axis Alignment Shorthands:**
  - `place-content`: Shorthand for `align-content` and `justify-content`.
  - `place-items`: Shorthand for `align-items` and `justify-items`.
  - `place-self`: Shorthand for `align-self` and `justify-self`.
  - Intelligently parses safety qualifiers (`safe` vs `unsafe`) so compound values like `"safe center"` apply correctly to both axes.
- **Overflow Safety Keywords:**
  - Supports `safe` vs `unsafe` alignment. When `safe` is specified and free space is negative (causing overflow), alignment falls back to `start` (`lead = 0`), preventing data loss off the start edge.
- **Directional Alignment Keywords:**
  - Supports `start`, `end`, `left`, `right`, `center`, `space-between`, `space-around`, `space-evenly` across flex and grid.

### 4. CSS Painting, Visual Effects & Transforms (Issues #293, #297)
- **CSS Gradients Engine (`modules/ui_core/gradient.zig`):**
  - `linear-gradient(...)`: Direction angles (`to top`, `to right`, `to bottom`, `to left`, `deg`, `rad`, `turn`), color stop parsing with percentage/degree positions, automatic stop distribution for missing positions, and color evaluation across bounding rects.
  - `radial-gradient(...)`: Circle and ellipse shapes, center positioning (`at center`, percentages), and radial color evaluation.
  - `conic-gradient(...)`: Start angles (`from 0deg`), center positions, and angular stop distribution.
- **Visual Effects & Rendering (`src/windows.zig`):**
  - Multi-layer `boxShadow`: Parses comma-separated shadows with horizontal offset, vertical offset, blur radius, spread radius, and hex/rgb/rgba color strings.
  - `opacity`: Alpha channel attenuation across all backgrounds, gradients, borders, shadows, and text.
  - Border radius clipping and uniform / per-side border stroke drawing.
- **2D Transforms Engine (`modules/ui_core/transform.zig`):**
  - `Matrix2D` 3x2 affine transformation matrix (a, b, c, d, tx, ty).
  - Transformation primitives: `makeTranslate`, `makeScale`, `makeRotate`, `makeSkew`, matrix multiplication, determinant, and matrix inversion.
  - CSS transform string parser for `translate()`, `translateX()`, `translateY()`, `scale()`, `scaleX()`, `scaleY()`, `rotate()`, `skew()`, `skewX()`, `skewY()`, and `matrix()`.
  - `transform-origin` parsing (percentages, keywords like `center`, `left`, `top`, pixel values).
  - Inverted pointer coordinate transformation (`inverseTransformPointWithOrigin`) for accurate hit testing on transformed elements.

### 5. CSS Transitions & Animation Hooks (`modules/ui_core/animation.zig`)
- **Timing Curves:**
  - Analytical and iterative (Newton-Raphson + bisection fallback) cubic-bezier curve solver.
  - Built-in W3C presets: `linear`, `ease`, `ease-in`, `ease-out`, `ease-in-out`, and custom `cubic-bezier(x1, y1, x2, y2)`.
- **Property Interpolation:**
  - Numeric property interpolation (`interpolateNumber`).
  - RGBA color interpolation with alpha preservation (`interpolateColor`).
  - 2D affine matrix interpolation (`interpolateMatrix`).
  - Transition progress evaluation with delay, duration, and timing function curves (`evaluateTransitionProgress`).

---

## Test Verification

1. **Zig Core Regression Tests (`modules/ui_core/root.zig`):**
   - All 85 unit tests pass cleanly:
     - `position: relative offsets without affecting normal flow of siblings (POS-01)`
     - `position: absolute takes out of flow and uses positioned ancestor padding box (POS-02)`
     - `position: fixed uses viewport containing block and ignores scroll offsets (POS-03)`
     - `position: sticky sticks within scroll container and clamps to parent (POS-04)`
     - `stacking context and z-index hit testing order (STACK-01)`
     - `CSS grid track parsing, repeat, and minmax (GRID-01)`
     - `CSS grid named areas layout (GRID-02)`
     - `CSS box alignment safe vs unsafe in flex layout (ALIGN-01)`
     - `CSS gradients evaluation for linear, radial, and conic (GRAD-01)`
     - `CSS 2D transforms and transformed hit testing (TRANS-01)`
     - `CSS transitions and cubic-bezier interpolation (ANIM-01)`
2. **Node Bridge Test Suite (`packages/solid-zig/tests/`):**
   - `npm test` runs all probe tests, select control tests, and package tests including `packages/solid-zig/tests/phase-e-css.mjs`. All pass successfully.
