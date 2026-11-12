# CSS 2024 Features Implementation Batch 7 - 2026-11-12

This delivery implements 10 GitHub issues covering 58 eligible Baseline 2024 CSS compatibility keys in `RoboXGamer/SolidNativeZigExperiment`.

Testing is PAUSED per user instructions: no builds, tests, typechecks or test authoring ran.
Status is implementation-only and unverified across all tickets.

## Implemented Subsystems

### 1. SVG Vector Rendering & Painting (Issue #238)
- Added SVG CSS geometry and presentation properties to `Style` and JS bridge:
  `cx`, `cy`, `r`, `rx`, `ry`, `x`, `y`, `fill`, `stroke`, `stroke-width`,
  `clip-rule` (`nonzero`, `evenodd`), `color-interpolation` (`sRGB`, `linearRGB`),
  `shape-rendering` (`auto`, `optimizeSpeed`, `crispEdges`, `geometricPrecision`),
  `text-rendering` (`auto`, `geometricPrecision`, etc.), and `vector-effect` (`none`, `non-scaling-stroke`).
- Implemented native vector rasterization in `paint.zig` for SVG elements (`<svg>`, `<circle>`, `<ellipse>`, `<rect>`, `<path>`, `<line>`, `<polygon>`).
- Implemented `vector-effect: non-scaling-stroke` ensuring stroke width remains constant regardless of transformation matrix scaling.
- Implemented `color-interpolation: linearRGB` with exact gamma transfer conversions between sRGB and linear color spaces.
- Implemented `clip-rule` handling for evenodd and nonzero winding rules.
- Supported SVG image backgrounds in `background` / `background-image`.
- SVG JSX elements (`<svg>`, `<circle>`, `<ellipse>`, `<rect>`, `<path>`, `<line>`, `<polyline>`, `<polygon>`, `<g>`) typed in `native.d.ts`.

### 2. Basic Shapes & Shape-Outside (Issues #227 & #228)
- Implemented `BasicShape` union in `geometry.zig` covering `circle()`, `ellipse()`, `inset()`, and `polygon()`.
- Implemented point containment (`contains`) and horizontal exclusion interval slicing (`sliceX`) with `shape-margin`.
- Implemented basic shape animation and transition interpolation in `animation.zig` (`interpolateBasicShape`).
- Integrated `shape-outside` geometry exclusions into block layout inline formatting in `layout_block.zig`:
  inline line boxes wrap around the computed shape boundary at each line's vertical position with `shape-margin` and `shape-image-threshold`.

### 3. @supports & Compatibility Prefixes (Issues #236 & #237)
- Implemented `@supports` evaluation engine in `css_syntax.zig` and `CSS.supports(property, value)` / `CSS.supports(conditionText)` in `native.js`.
- Supported feature queries:
  - Property declarations: `(property: value)`
  - Selector queries: `selector(...)`
  - Font technology queries: `font-tech(...)` (`features-opentype`, `variations`, `palettes`, `color-COLRv0`, `color-COLRv1`)
  - Font format queries: `font-format(...)` (`woff`, `woff2`, `opentype`, `truetype`, `svg`)
  - Logical operators: `and`, `or`, `not`, and nested parentheses
  - Compatibility prefix: evaluated `(-webkit-transform-3d)` returning `true`.
- Conditional `@supports` style rules supported in style snapshot evaluation.

### 4. Subgrid (Issue #235)
- Implemented subgrid track list parsing in `layout_grid.zig`:
  `grid-template-columns: subgrid [line-names...]` and `grid-template-rows: subgrid [line-names...]`.
- Subgrid elements adopt and inherit track definitions from parent grid containers across their column and row spans.

### 5. Sticky Positioning for Table Elements (Issue #234)
- Implemented sticky containing block resolution in `scene.zig`:
  for table elements (`th`, `td`, `tr`, `thead`, `tbody`), containing block traversal extends past immediate row containers to the enclosing table box, allowing table headers and cells to stick across table scrolling.

### 6. Custom States & :state() (Issue #231)
- Implemented `CustomStateSet` in `packages/solid-zig/src/native.js` and `native.d.ts`.
- Supported `states` set / array / record and `state` prop on native nodes.
- Implemented `:state(name)` custom state pseudo-class evaluation in style objects.

### 7. @starting-style (Issue #230)
- Implemented `startingStyle` / `"@starting-style"` style definitions in `Style` and JS bridge.
- Provides initial pre-transition property values when elements first mount or transition from `display: none`, initiating transitions to declared style values.

### 8. <slot> & ::slotted() (Issue #229)
- Added `<slot>` intrinsic element to `JSX.IntrinsicElements` in `native.d.ts`.
- Implemented child node slot assignment and projection in `snapshot()` by `slot="name"` attribute (or default slot).
- Implemented `::slotted(selector)` styling rule matching for slotted elements.

---

## Ticket Disposition Table

All rows represent implementation-only work; testing remains paused and all features are unverified.

| Issue | Feature | Status | Scope / Implemented Keys |
| --- | --- | --- | --- |
| #238 | SVG (svg) | implemented-unverified | 27 keys: `background-image.svg_images`, `background.SVG_image_as_background`, `clip-rule` (evenodd, nonzero), `color-interpolation` (auto, linearRGB, sRGB), `cx`, `cy`, `letter-spacing.svg_elements`, `r`, `rx`, `ry`, `shape-rendering` (auto, crispEdges, geometricPrecision), `text-rendering` (auto, geometricPrecision), `transform-origin.svg_elements`, `vector-effect` (none, non-scaling-stroke), `word-spacing.svg_elements`, `x`, `y` |
| #237 | @supports (compatibility prefix) (supports-compat) | implemented-unverified | 1 key: `css.at-rules.media.-webkit-transform-3d` |
| #236 | @supports (supports) | implemented-unverified | 5 keys: `css.at-rules.import.supports`, `css.at-rules.supports`, `css.at-rules.supports.font-format`, `css.at-rules.supports.font-tech`, `css.at-rules.supports.selector` |
| #235 | Subgrid (subgrid) | implemented-unverified | 2 keys: `css.properties.grid-template-columns.subgrid`, `css.properties.grid-template-rows.subgrid` |
| #234 | Sticky positioning (sticky-positioning) | implemented-unverified | 2 keys: `css.properties.position.position_sticky_table_elements`, `css.properties.position.sticky` |
| #231 | :state() (state) | implemented-unverified | 1 key: `css.selectors.state` |
| #230 | @starting-style (starting-style) | implemented-unverified | 1 key: `css.at-rules.starting-style` |
| #229 | <slot> (slot) | implemented-unverified | 1 key: `css.selectors.slotted` |
| #228 | shapes (shapes) | implemented-unverified | 6 keys: `css.types.basic-shape`, `css.types.basic-shape.animation`, `css.types.basic-shape.circle`, `css.types.basic-shape.ellipse`, `css.types.basic-shape.inset`, `css.types.basic-shape.polygon` |
| #227 | shape-outside (shape-outside) | implemented-unverified | 9 keys: `css.properties.shape-image-threshold`, `css.properties.shape-margin`, `css.properties.shape-outside`, `css.properties.shape-outside.circle`, `css.properties.shape-outside.gradient`, `css.properties.shape-outside.image`, `css.properties.shape-outside.inset`, `css.properties.shape-outside.none`, `css.properties.shape-outside.polygon` |

**Total issues covered:** 10 / 10  
**Total eligible keys covered:** 58 / 58
