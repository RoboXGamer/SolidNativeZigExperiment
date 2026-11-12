# Batch 6: CSS 2024 Feature Implementation Batch

Delivery date: 2026-11-12
Repository: RoboXGamer/SolidNativeZigExperiment

## Overview & Execution Context

This delivery implements end-to-end behavior for 10 CSS 2024 GitHub issues:
- **#250**: text-emphasis (`text-emphasis`)
- **#249**: text-decoration-skip-ink (`text-decoration-skip-ink`)
- **#248**: text-decoration (`text-decoration`)
- **#247**: text-combine-upright (`text-combine-upright`)
- **#246**: text-align-last (`text-align-last`)
- **#244**: ::target-text (`target-text`)
- **#243**: :target (`target`)
- **#242**: Tables (`table`)
- **#240**: System colors (`system-color`)
- **#239**: SVG filters (`svg-filters`)

Testing was **explicitly paused** by user instruction: no builds, test runs, typechecks, or test authoring were executed. All statuses are implementation-only and unverified (`implemented-unverified` or `partial-unverified`).

---

## Native Architecture & Subsystem Implementations

### 1. Typography & Text Decoration Subsystem (#250, #249, #248, #247, #246)
- **Text Emphasis (#250)**:
  - Supports `text-emphasis-style` with shape keywords (`dot`, `circle`, `double-circle`, `triangle`, `sesame`), fill modifiers (`filled`, `open`), and custom string glyphs.
  - Supports `text-emphasis-color` with named/system colors, `currentColor`, and `transparent`.
  - Supports `text-emphasis-position` (`over`, `under`, `over right`, `under left`, etc.).
  - Inherited computed styles propagate through `inheritComputedStyle` and `Typography`.
  - Native Windows text renderer calculates glyph positions and draws emphasis marks centered above or below individual non-whitespace text clusters.
- **Text Decoration & Skip Ink (#248, #249)**:
  - Shorthand `text-decoration` splits line, style, color, and thickness components.
  - `text-decoration-line`: Supports `underline`, `overline`, `line-through`, and `none` (or combinations).
  - `text-decoration-style`: Implements `solid`, `double` (spaced parallel lines), `dashed`, `dotted` (sampled arc points), and `wavy` (sine wave rasterization).
  - `text-decoration-thickness`: Supports `auto`, `from-font`, explicit length (`px`), and `percentage` of font size.
  - `text-decoration-skip-ink`: Implements `auto` and `none`. In `auto` mode, descender glyphs ('g', 'j', 'p', 'q', 'y') interrupt underlines to skip ink collision; in `none` mode, continuous lines are drawn.
- **Text Combine Upright (#247)**:
  - Supports `text-combine-upright: all` and `none`. In vertical writing modes (`vertical-rl`, `vertical-lr`), `all` clamps the shaped run advance to 1em (`fontSize`), orienting characters upright within vertical layout.
- **Text Align Last (#246)**:
  - Supports `text-align-last`: `auto`, `start`, `end`, `left`, `right`, `center`, and `justify`.
  - When `auto` is combined with `text-align: justify`, the final shaped line aligns to `start` (left in LTR, right in RTL) per CSS Text 3 specification rules.

### 2. Table Layout Engine (#242)
- Added dedicated CSS table formatting module `modules/ui_core/layout_table.zig`:
  - Recognizes table elements and display types: `table` (`display: table`), `caption` (`display: table-caption`), row groups (`thead`, `tbody`, `tfoot`), rows (`tr` / `display: table-row`), and cells (`td`, `th` / `display: table-cell`).
  - **`border-collapse`**: Supports `separate` (independent cell borders with cell spacing) and `collapse` (adjoining cell borders collapse together, border-spacing ignored).
  - **`border-spacing`**: Supports 1-value (uniform) or 2-value (horizontal `borderSpacingX` and vertical `borderSpacingY`) cell gap resolution.
  - **`caption-side`**: Positions captions at `top` (before table grid) or `bottom` (after table grid).
  - **`empty-cells`**: Implements `show` and `hide`. In `separate` mode, `hide` skips background and border painting for cells without visible content.
  - **`table-layout`**: Supports `fixed` (first row dictates column widths; remaining width divided among unconstrained columns) and `auto` (computes min-content and max-content column widths across all rows and distributes width proportionally).

### 3. System Colors (#240)
- Implemented in `modules/ui_core/colors.zig`:
  - Full CSS Color 4 system color palette: `AccentColor`, `AccentColorText`, `ActiveText`, `ButtonBorder`, `ButtonFace`, `ButtonText`, `Canvas`, `CanvasText`, `Field`, `FieldText`, `GrayText`, `Highlight`, `HighlightText`, `LinkText`, `Mark`, `MarkText`, `SelectedItem`, `SelectedItemText`, `VisitedText`.
  - Historical CSS2 system colors: `ActiveCaption`, `AppWorkspace`, `Background`, `ButtonHighlight`, `ButtonShadow`, `CaptionText`, `InactiveBorder`, `InactiveCaption`, `InactiveCaptionText`, `InfoBackground`, `InfoText`, `Menu`, `MenuText`, `Scrollbar`, `ThreeDDarkShadow`, `ThreeDFace`, `ThreeDHighlight`, `ThreeDLightShadow`, `ThreeDShadow`, `Window`, `WindowFrame`, `WindowText`.
  - Case-insensitive ASCII token parsing with zero-allocation stack buffers.

### 4. SVG Filters Properties (#239)
- Extended `Style`, `native.d.ts`, `native.js`, and `modules/ui_core/paint.zig`:
  - `color-interpolation-filters`: `auto`, `linearRGB`, `sRGB`.
  - `flood-color`: `<color>`, `currentColor`, `transparent`.
  - `flood-opacity`: Number or percentage resolved with opacity scaling.
  - `lighting-color`: `<color>`, `currentColor`, `transparent`.
  - Inherited computed styles and currentColor resolution through ancestor nodes.

### 5. Target Selectors (#243, #244)
- **`:target` (#243)**:
  - Document/URL target fragment routing in `renderer.js` and `native.js` (`setTarget`, `getTarget`).
  - Matches `node.props.id === currentTarget` or `node.props.target`.
  - Evaluates and applies `:target` rules in style snapshots and layout.
- **`::target-text` (#244)**:
  - Text fragment navigation state (`setTargetText`, `getTargetText`).
  - Matches targeted text snippets or `node.props.targetText`.
  - Applies target text highlight background and foreground coloring during native text rendering.

---

## Ticket Disposition & Coverage Summary

| Issue | Feature | Status | Eligible Keys | Scope / Delivered Behavior |
| --- | --- | --- | :---: | --- |
| #250 | text-emphasis | implemented-unverified | 19 | Full shorthand, shapes (circle/dot/double-circle/triangle/sesame), fill/open, custom strings, over/under/left/right positions, currentColor, transparent |
| #249 | text-decoration-skip-ink | implemented-unverified | 3 | `auto` and `none` modes; descender ink-skipping in underline drawing |
| #248 | text-decoration | implemented-unverified | 19 | Shorthand, line (underline/overline/line-through/none), styles (solid/double/dotted/dashed/wavy), thickness (auto/from-font/percentage/length), currentColor, transparent |
| #247 | text-combine-upright | implemented-unverified | 3 | `none` and `all`; horizontal composition and 1em advance compression in vertical writing modes |
| #246 | text-align-last | implemented-unverified | 2 | `auto` (resolves justify to start), keywords (start, end, left, right, center, justify) |
| #244 | ::target-text | implemented-unverified | 1 | Target text fragment state, pseudo-element style cascading, highlight background & color rendering |
| #243 | :target | implemented-unverified | 1 | Target URI fragment ID matching, pseudo-class style merging, native reactive invalidation |
| #242 | Tables | implemented-unverified | 13 | Table formatting context, `border-collapse` (separate/collapse), `border-spacing` (X/Y), `caption-side` (top/bottom), `empty-cells` (show/hide), `table-layout` (auto/fixed) |
| #240 | System colors | implemented-unverified | 1 | Complete CSS Color 4 system colors and legacy CSS system color keywords in `parseColor` |
| #239 | SVG filters | implemented-unverified | 11 | `color-interpolation-filters` (auto/linearRGB/sRGB), `flood-color` (currentColor/transparent), `flood-opacity`, `lighting-color` (currentColor/transparent) |

Total issues: **10**  
Total compatibility keys covered: **73**  
Verification status: **Unverified** (validation paused per instructions).
