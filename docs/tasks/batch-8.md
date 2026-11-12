# CSS 2024 Baseline Batch 8 — Implementation Report

This batch implements 10 GitHub issues covering CSS 2024 features in `RoboXGamer/SolidNativeZigExperiment`:
- Issues: #217, #218, #219, #220, #221, #222, #223, #224, #225, #226.
- Implementation performed directly without subagents.
- Testing is explicitly **PAUSED** per instructions: no builds, tests, typechecks, or test authoring ran.
- Status of all covered compatibility keys is **implemented-unverified**.

---

## Architecture and Implementation Summary

### 1. Selectors Core & Scoping (Issues #225, #219, #226)
- **`modules/ui_core/selectors.zig` & `packages/solid-zig/src/selectors.js`**:
  - Implemented CSS selector tokenizer, parser, and matcher.
  - Core selectors: Universal (`*`, `ns|*`, `*|*`, `|*`), Type (`tag`, `ns|tag`, `*|tag`, `|tag`), ID (`#id`), Class (`.class`).
  - Attribute selectors: `[attr]`, `[attr=val]`, `[attr~=val]`, `[attr|=val]`, `[attr^=val]`, `[attr$=val]`, `[attr*=val]` with case flags `i` and `s`.
  - Combinators: Descendant (` `), Child (`>`), Next-sibling (`+`), Subsequent-sibling (`~`), and selector lists (`,`).
  - Specificity calculation: standard `[a, b, c]` tuple calculation and comparison.
  - Pseudo-class `:scope` (#219): Matches the contextual scope node in selector queries and DOM APIs (`node.matches(":scope")`, `node.querySelector(...)`).
  - Pseudo-element `::part(name)` (#226): Matches elements exposing shadow parts via the `part` attribute.
  - DOM APIs attached to Solid retained nodes in `packages/solid-zig/src/renderer.js`: `matches`, `querySelector`, `querySelectorAll`, `closest`, `getAttribute`, `setAttribute`, `hasAttribute`, `removeAttribute`.

### 2. Scrollbars & Scrolling (Issues #221, #222, #223, #224)
- **`scrollbar-width` (#224)**:
  - Supported values: `auto` (8px standard track/thumb), `thin` (4px compact track/thumb), `none` (scrollbar suppressed / 0px width).
  - Integrated into `scene.zig` (`scrollbarTrackWidth`), `style.zig`, `native.d.ts`, `native.js`, and rendered in `src/windows.zig` for both horizontal and vertical axes.
- **`scrollbar-gutter` (#223)**:
  - Supported values: `auto`, `stable`, `stable both-edges`.
  - In `scene.zig`, `Node.scrollbarGutterReserved()` calculates the gutter inset. `contentBox` and inner layout dimensions reserve track width (respecting `scrollbar-width` and text direction).
  - Integrated into `layout_block.zig` and `layout_flex.zig` so in-flow children avoid overlapping reserved gutter space.
- **`scroll-behavior` (#221)**:
  - Values: `auto`, `smooth`.
  - Added `scrollBehavior` to `Style`, `NativeStyle`, and snapshot serialization.
  - Added `scrollTo({ left, top, behavior })` and `scrollBy(...)` on retained nodes.
- **`scroll-snap` (#222)**:
  - Container properties: `scroll-snap-type` (`none`, `x`, `y`, `block`, `inline`, `both`, with `mandatory` or `proximity`), `scroll-padding` (4 sides + shorthands + `auto`).
  - Child properties: `scroll-snap-align` (`none`, `start`, `end`, `center`), `scroll-snap-stop` (`normal`, `always`), `scroll-margin` (4 sides + shorthands).
  - Full logical property expansion (`scrollMarginInline`, `scrollMarginBlock`, `scrollPaddingInline`, `scrollPaddingBlock`, etc.) in `native.js`.
  - Snapping algorithm implemented in `modules/ui_core/scene.zig` (`snapToNearest`), snapping to candidate alignments when scrolling or chaining wheel events.

### 3. Media Queries: Scripting (Issue #220)
- **`modules/ui_core/media.zig` & `packages/solid-zig/src/media.js`**:
  - Implemented media feature evaluation for `@media (scripting: none | initial-only | enabled)` and boolean `(scripting)`.
  - In our runtime environment, scripting is active and dynamic, evaluating `(scripting: enabled)` and `(scripting)` to `true`, and `(scripting: none)` to `false`.
  - Provided `matchMedia(query)` API with `matches`, `media`, and listener support.

### 4. Safe Area Inset Environment Variables (Issue #218)
- **`modules/ui_core/sizing.zig` & `packages/solid-zig/src/native.js`**:
  - Added `safe_area_inset_top`, `safe_area_inset_right`, `safe_area_inset_bottom`, `safe_area_inset_left` to `sizing.Context`.
  - Extended parser `atom()` to handle `env(variable, fallback?)` function calls.
  - Added environment variable registry in `native.js` (`getEnvironmentVariable`, `setEnvironmentVariable`, `resolveEnv`) with defaults (`0px`), resolving `env(...)` in style lengths and values.

### 5. Ruby Position (Issue #217)
- **`modules/ui_core/text.zig`, `modules/ui_core/style.zig`, `scene.zig`, `native.js`**:
  - Supported `ruby-position: over | under`.
  - Added `ruby_position` to `Typography`.
  - Implemented `measureRuby(base, annotation, font_size, ruby_pos)` in `text.zig`, computing dual-run metrics and vertical offsets for base text and annotation text.

---

## Ticket Disposition Table

| Issue | Feature | Eligible Compatibility Keys | Status | Scope / Implementation Details |
| --- | --- | --- | --- | --- |
| **#226** | **shadow-parts** | `css.selectors.part` | implemented-unverified | `::part(ident)` parsing, specificity calculation (0, 1, 1), and matching against `node.props.part` token lists across tree traversal and selector queries in JS and Zig. |
| **#225** | **selectors** | `css.selectors.attribute`<br>`css.selectors.child`<br>`css.selectors.class`<br>`css.selectors.descendant`<br>`css.selectors.id`<br>`css.selectors.list`<br>`css.selectors.next-sibling`<br>`css.selectors.subsequent-sibling`<br>`css.selectors.type`<br>`css.selectors.type.namespaces`<br>`css.selectors.universal`<br>`css.selectors.universal.namespaces` | implemented-unverified | Full core selector engine supporting universal, type, ID, class, attributes with operators (`=`, `~=`, `\|=`, `^=`, `$=`, `*=`, and case flags `i`/`s`), combinators (` `, `>`, `+`, `~`), lists (`,`), and namespace prefixes in both `modules/ui_core/selectors.zig` and `packages/solid-zig/src/selectors.js`. DOM query methods `matches`, `querySelector`, `querySelectorAll`, and `closest`. |
| **#224** | **scrollbar-width** | `css.properties.scrollbar-width`<br>`css.properties.scrollbar-width.auto`<br>`css.properties.scrollbar-width.none`<br>`css.properties.scrollbar-width.thin` | implemented-unverified | Native style typing, serialization, and rendering support for `auto` (8px), `thin` (4px), and `none` (0px / suppressed rendering) across vertical and horizontal scrollbars in `scene.zig` and `src/windows.zig`. |
| **#223** | **scrollbar-gutter** | `css.properties.scrollbar-gutter`<br>`css.properties.scrollbar-gutter.auto`<br>`css.properties.scrollbar-gutter.stable` | implemented-unverified | `auto`, `stable`, and `stable both-edges` keyword parsing, validation, and layout reservation in `scene.zig`, `layout_block.zig`, and `layout_flex.zig`, preserving scroll gutter dimensions without shifting content. |
| **#222** | **scroll-snap** | `css.properties.scroll-margin`<br>`css.properties.scroll-margin-block`<br>`css.properties.scroll-margin-block-end`<br>`css.properties.scroll-margin-block-start`<br>`css.properties.scroll-margin-bottom`<br>`css.properties.scroll-margin-inline`<br>`css.properties.scroll-margin-inline-end`<br>`css.properties.scroll-margin-inline-start`<br>`css.properties.scroll-margin-left`<br>`css.properties.scroll-margin-right`<br>`css.properties.scroll-margin-top`<br>`css.properties.scroll-padding`<br>`css.properties.scroll-padding-block`<br>`css.properties.scroll-padding-block-end`<br>`css.properties.scroll-padding-block-end.auto`<br>`css.properties.scroll-padding-block-start`<br>`css.properties.scroll-padding-block-start.auto`<br>`css.properties.scroll-padding-block.auto`<br>`css.properties.scroll-padding-bottom`<br>`css.properties.scroll-padding-inline`<br>`css.properties.scroll-padding-inline-end`<br>`css.properties.scroll-padding-inline-end.auto`<br>`css.properties.scroll-padding-inline-start`<br>`css.properties.scroll-padding-inline-start.auto`<br>`css.properties.scroll-padding-inline.auto`<br>`css.properties.scroll-padding-left`<br>`css.properties.scroll-padding-right`<br>`css.properties.scroll-padding-top`<br>`css.properties.scroll-padding.auto`<br>`css.properties.scroll-snap-align`<br>`css.properties.scroll-snap-align.center`<br>`css.properties.scroll-snap-align.end`<br>`css.properties.scroll-snap-align.none`<br>`css.properties.scroll-snap-align.start`<br>`css.properties.scroll-snap-stop`<br>`css.properties.scroll-snap-stop.always`<br>`css.properties.scroll-snap-stop.normal`<br>`css.properties.scroll-snap-type`<br>`css.properties.scroll-snap-type.block`<br>`css.properties.scroll-snap-type.both`<br>`css.properties.scroll-snap-type.inline`<br>`css.properties.scroll-snap-type.none`<br>`css.properties.scroll-snap-type.x`<br>`css.properties.scroll-snap-type.y` | implemented-unverified | Full scroll snap layout model: `scroll-snap-type` (axes and strictness: mandatory/proximity), `scroll-padding` (including `auto`), child `scroll-snap-align` (start, end, center, none), `scroll-snap-stop` (normal, always), and 4-way `scroll-margin` and `scroll-padding` with logical property expansion. Snapping algorithm implemented in `scene.zig` (`snapToNearest`). |
| **#221** | **scroll-behavior** | `css.properties.scroll-behavior`<br>`css.properties.scroll-behavior.auto`<br>`css.properties.scroll-behavior.smooth` | implemented-unverified | `auto` and `smooth` parsing, style validation, programmatic `scrollTo`/`scrollBy` options `{ behavior: "smooth" }`, and smooth scroll state tracking in `Scene` and `native.js`. |
| **#220** | **scripting** | `css.at-rules.media.scripting` | implemented-unverified | Evaluator for `@media (scripting: none \| initial-only \| enabled)` and boolean `(scripting)` in `modules/ui_core/media.zig` and `packages/solid-zig/src/media.js`, plus `matchMedia(query)` API for runtime feature detection. |
| **#219** | **scope-pseudo** | `css.selectors.scope`<br>`css.selectors.scope.dom_api` | implemented-unverified | `:scope` pseudo-class parsing, specificity calculation (0, 1, 0), matching against scoping context node in `modules/ui_core/selectors.zig` and `packages/solid-zig/src/selectors.js`, and integration with `element.matches(selector)` / `element.querySelector(selector)`. |
| **#218** | **safe-area-inset** | `css.types.env`<br>`css.types.env.safe-area-inset-bottom`<br>`css.types.env.safe-area-inset-left`<br>`css.types.env.safe-area-inset-right`<br>`css.types.env.safe-area-inset-top` | implemented-unverified | `env(...)` function parsing with optional fallback support in `modules/ui_core/sizing.zig` `atom()` and `packages/solid-zig/src/native.js` `resolveEnv()`. Environment variable registration (`getEnvironmentVariable`, `setEnvironmentVariable`) and Context propagation (`safe_area_inset_*`). |
| **#217** | **ruby-position** | `css.properties.ruby-position`<br>`css.properties.ruby-position.over`<br>`css.properties.ruby-position.under` | implemented-unverified | `ruby-position: over \| under` style property representation in `Style`, typography mapping in `textContext`, and dual-run ruby measurement and baseline placement in `modules/ui_core/text.zig` (`measureRuby`). |
