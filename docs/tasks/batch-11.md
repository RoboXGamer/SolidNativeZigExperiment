# CSS 2024 Batch 11 Implementation — 2026-11-12

Implementation-only delivery for 10 GitHub issues in `RoboXGamer/SolidNativeZigExperiment`.
Testing PAUSED: As requested by the user, all builds, tests, typechecks, and test authoring
were explicitly stopped for this batch. No runtime or test verification is claimed.
Status is implementation-only and unverified (`implemented-unverified`).

## Architecture & Subsystem Integration

### 1. Form Controls & Placeholder Subsystem (#194, #193)
- `:placeholder-shown` pseudo-class:
  - Semantic matcher `isPlaceholderShown(node)` implemented in `packages/solid-zig/src/native.js` and `ui/native.js`.
  - Supports `<input>` and `<textarea>` elements across text and non-text types (`text`, `search`, `url`, `tel`, `email`, `password`, `number`). Non-supported types (`checkbox`, `radio`, `file`, `button`, etc.) and non-input elements are excluded.
  - Matches dynamically when element has a non-empty `placeholder` attribute and value is empty string.
  - Snapshot integration routes `:placeholder-shown` style overrides into element styles.
  - `Node.placeholder` and `Node.isPlaceholderShown()` added in native Zig (`modules/ui_core/tree.zig`, `scene.zig`).
- `::placeholder` pseudo-element:
  - Support for `::placeholder` styling (`placeholderColor`, `placeholderOpacity`, `placeholderStyle`).
  - Native rendering in `src/windows.zig` draws the placeholder text with styled color and opacity when value is empty and placeholder is present.

### 2. Box Model & Physical Positioning Properties (#192)
- Physical insets `top`, `right`, `bottom`, `left`:
  - Fully supports lengths, percentages, CSS calculations, and explicit `"auto"`.
  - `topAuto`, `rightAuto`, `bottomAuto`, `leftAuto` boolean indicators added in `modules/ui_core/style.zig` and `scene.zig`.
  - In `scene.zig` relative positioning: respects auto flags (auto insets contribute 0 offset; opposites resolve cleanly per LTR/RTL rules).
  - In `scene.zig` out-of-flow layout (`layoutOutOfFlowChildren`):
    - Absolute and fixed sizing: when both opposite insets are specified (`left` and `right`, or `top` and `bottom`) and width/height is auto/null, the element stretches between the insets.
    - Explicit `auto` insets place children using default static / margin flow boundaries.

### 3. Basic Shape path() & Motion Path (#191)
- `modules/ui_core/path_shape.zig`:
  - Full SVG path data parser supporting commands `M`, `m`, `L`, `l`, `H`, `h`, `V`, `v`, `C`, `c`, `S`, `s`, `Q`, `q`, `T`, `t`, `A`, `a`, `Z`, `z`.
  - Supports `path([<fill-rule>,] <string>)` with `nonzero` and `evenodd` fill rules.
  - Computes axis-aligned bounding box (`computeBounds`).
  - Implements point-in-path testing (`contains(px, py)`) using winding number (`nonzero`) and ray-crossing parity (`evenodd`) for clip-path clipping and hit testing.
  - Motion path distance & fraction evaluation (`pointAtDistance`, `pointAtFraction`) yielding position `(x, y)` and tangent angle.
  - Integrated into `modules/ui_core/style.zig` (`clipPath`, `offsetPath`, `offsetDistance`, `offsetRotate`) and `scene.zig` (`layoutOutOfFlowChildren`).

### 4. Vector & Text Paint Order (#190)
- `paint-order` property:
  - Added `paintOrder` in `modules/ui_core/style.zig`, `text.zig` (`Typography.paint_order`), `scene.zig`, `src/text_backend.zig`, and `packages/solid-zig/src/native.js`.
  - Controls paint sequence: `normal` (fill, stroke, markers) vs custom permutations (e.g. `stroke fill`).
  - Cached in text rasterization hash and honored during drawing.

### 5. Paged Media Setup, Page Selectors & Page Breaks (#189, #188, #187)
- `modules/ui_core/page.zig`:
  - Standard paper dimensions in typographic points/pixels:
    - JIS sizes: `jis-b4` (257mm x 364mm -> 728.5 x 1031.8 pt) and `jis-b5` (182mm x 257mm -> 515.9 x 728.5 pt).
    - ISO sizes: `a3`, `a4`, `a5`, `b4`, `b5`.
    - North American sizes: `letter`, `legal`, `ledger`.
  - Supports orientation keywords (`portrait`, `landscape`) and explicit `<length>{1,2}` dimensions.
  - Page selectors: `:first` (matches first page index 0), `:left`, `:right`, `:blank`, and named pages (`page` property).
  - Page fragmentation:
    - `break-before`: `auto`, `avoid`, `avoid-page`, `page`, `left`, `right`, `recto`, `verso`.
    - `break-after`: `auto`, `avoid`, `avoid-page`, `page`, `left`, `right`, `recto`, `verso`.
    - `break-inside`: `auto`, `avoid`, `avoid-page`.
    - `Paginator.paginate()` algorithm distributes layout boxes across pages, inserting blank pages for left/right parity when required.

### 6. Text Wrapping & overflow-wrap (#185)
- `overflow-wrap` (and `wordWrap` alias):
  - Values: `normal`, `break-word`, `anywhere`.
  - In `modules/ui_core/text.zig`:
    - `minContentWidth`: when `overflow-wrap: anywhere`, soft wrap opportunities between graphemes are considered during min-content sizing, allowing intrinsic width to shrink to the widest single grapheme.
    - `shapeLines`: when `overflow-wrap` is `break-word` or `anywhere`, unbreakable words that exceed available capacity are broken at grapheme boundaries instead of overflowing the container.

### 7. Responsive Overflow Media Queries (#182)
- `modules/ui_core/media_query.zig`:
  - Evaluates `overflow-block` media feature: `none`, `scroll`, `paged`.
  - Evaluates `overflow-inline` media feature: `none`, `scroll`.
  - Supports boolean feature queries (`(overflow-block)`, `(overflow-inline)`), explicit value tests (`(overflow-block: scroll)`), media types (`screen`, `print`, `all`), and logical operators (`and`, `or`/comma, `not`).
  - Exported in JS bridge as `matchMedia(query, context)`.

---

## Issue Coverage & Ticket Disposition

| Issue | Feature ID / Name | Eligible Compatibility Keys | Scope Status | Notes / Remaining Limitations |
| --- | --- | --- | --- | --- |
| #194 | `placeholder-shown` | `css.selectors.placeholder-shown`<br>`css.selectors.placeholder-shown.non_text_types` | implemented-unverified | Matches text and non-text types (number, search, etc.) with empty value and placeholder attribute; reactive bridge update; unverified due to paused testing |
| #193 | `placeholder` | `css.selectors.placeholder` | implemented-unverified | `::placeholder` styling (color, opacity) routed through snapshot and native input text rasterizer; unverified |
| #192 | `physical-properties` | `css.properties.bottom`<br>`css.properties.bottom.auto`<br>`css.properties.left`<br>`css.properties.left.auto`<br>`css.properties.right`<br>`css.properties.right.auto`<br>`css.properties.top`<br>`css.properties.top.auto` | implemented-unverified | Physical insets top/right/bottom/left with lengths, percentages and explicit auto keyword across relative and out-of-flow layout; unverified |
| #191 | `path-shape` | `css.types.basic-shape.path`<br>`css.types.basic-shape.path.clip-path`<br>`css.types.basic-shape.path.offset-path` | implemented-unverified | SVG path parser, nonzero/evenodd fill rules, bounding box, winding point-in-path, and offset-path motion path distance/angle evaluation; unverified |
| #190 | `paint-order` | `css.properties.paint-order` | implemented-unverified | `paint-order` property, normal/fill/stroke/markers ordering, text styling and rasterizer cache hash integration; unverified |
| #189 | `page-setup` | `css.at-rules.page`<br>`css.at-rules.page.size`<br>`css.at-rules.page.size.jis-b4`<br>`css.at-rules.page.size.jis-b5`<br>`css.properties.page` | implemented-unverified | `@page` rule parser, `page` property, paper sizes including JIS-B4/JIS-B5/A4/Letter, orientation portrait/landscape, and page margin geometry; unverified |
| #188 | `page-selectors` | `css.selectors.first` | implemented-unverified | `@page :first` pseudo-class selector matching page index 0, plus `:left`, `:right`, `:blank` and named page selectors; unverified |
| #187 | `page-breaks` | `css.properties.break-after`<br>`css.properties.break-after.auto`<br>`css.properties.break-after.left`<br>`css.properties.break-after.page`<br>`css.properties.break-after.paged_context`<br>`css.properties.break-after.paged_context.page`<br>`css.properties.break-after.right`<br>`css.properties.break-before`<br>`css.properties.break-before.auto`<br>`css.properties.break-before.left`<br>`css.properties.break-before.page`<br>`css.properties.break-before.paged_context`<br>`css.properties.break-before.paged_context.page`<br>`css.properties.break-before.right`<br>`css.properties.break-inside`<br>`css.properties.break-inside.auto`<br>`css.properties.break-inside.avoid`<br>`css.properties.break-inside.avoid-page`<br>`css.properties.break-inside.paged_context` | implemented-unverified | Fragmentation engine with break-before, break-after, and break-inside in paged context, page parity blank insertions, and avoid-page constraints; unverified |
| #185 | `overflow-wrap` | `css.properties.overflow-wrap`<br>`css.properties.overflow-wrap.anywhere`<br>`css.properties.overflow-wrap.break-word`<br>`css.properties.overflow-wrap.normal` | implemented-unverified | `overflow-wrap` (normal, break-word, anywhere) and word-wrap alias in text shaping and minContentWidth intrinsic calculation; unverified |
| #182 | `overflow` | `css.at-rules.media.overflow-block`<br>`css.at-rules.media.overflow-inline` | implemented-unverified | `overflow-block` (none, scroll, paged) and `overflow-inline` (none, scroll) media feature evaluations in Zig and JS bridge; unverified |
