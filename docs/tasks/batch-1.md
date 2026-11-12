# Batch 1 — CSS 2025 Additions Delivery

Implementation-only delivery. The user explicitly stopped all builds, tests,
typechecks and test authoring for this batch. No runtime, browser or test success
is claimed. Issue completion here means the native implementation has been
written; verification acceptance remains outstanding under the active testing pause.
This record documents the native paths and behavior for the 10 assigned CSS 2025
GitHub issues (#299 through #308).

## Architectural Foundations & Native Integration

- **Writing Modes (`modules/ui_core/style.zig`, `scene.zig`, `packages/solid-zig/src/native.js`)**:
  Extended vertical writing-mode infrastructure to support `sideways-rl` and `sideways-lr`.
  In `sideways-rl`, block-flow direction runs right-to-left and inline runs top-to-bottom for LTR.
  In `sideways-lr`, block-flow direction runs left-to-right and inline runs bottom-to-top for LTR.
  Both modes declare vertical block flow (`vertical = true`), correctly mapping logical
  `inlineSize` / `blockSize`, `marginInline` / `marginBlock`, `paddingInline` / `paddingBlock`,
  and `insetInline` / `insetBlock`. Computed writing-mode and direction inherit down the scene tree.

- **View Transitions (`modules/ui_core/view_transitions.zig`, `style.zig`, `packages/solid-zig/src/native.js`, `native.d.ts`)**:
  Implemented native View Transitions Level 1 and 2 subsystem. Supports `view-transition-name`
  (`none`, `match-element`, `auto`, custom idents) and `view-transition-class` (`none`, custom classes).
  For `match-element`, unique element-scoped transition names are generated based on node identity.
  Constructs the full pseudo-element hierarchy (`::view-transition`, `::view-transition-group`,
  `::view-transition-image-pair`, `::view-transition-old`, `::view-transition-new`).
  Evaluates pseudo-element selector queries (`*`, `ident`, `*.class`, `.class`, `ident.class`).
  Interpolates geometry rects between old and new element snapshots, cross-fading old snapshot
  opacity (1 -> 0) and new snapshot opacity (0 -> 1). Exposes `startViewTransition(callback)` in
  Solid Native bridge with standard transition promises (`ready`, `updateCallbackDone`, `finished`).

- **Typography & Text Decorations (`modules/ui_core/style.zig`, `scene.zig`, `text.zig`, `src/windows.zig`)**:
  Implemented full CSS `text-decoration` shorthand and longhands:
  - Supports lines: `none`, `underline`, `overline`, `line-through`, `spelling-error`, `grammar-error`.
  - Supports styles: `solid`, `double`, `dotted`, `dashed`, `wavy`.
  - Supports colors: custom colors, `transparent`, and `currentColor` (resolved against node/inherited `color`).
  - Supports thickness: numeric lengths, CSS lengths, or default font-scaled thickness.
  - Native rendering in `src/windows.zig`: paints geometry for all decoration lines and styles,
    rendering error underlines (wavy red for `spelling-error`, wavy green for `grammar-error`)
    and honoring custom style/color overrides.

- **Inter-Script Text Autospacing (`modules/ui_core/text.zig`, `style.zig`, `scene.zig`)**:
  Implemented `text-autospace` (`normal` | `no-autospace`).
  When `normal` (initial/default), character iteration inspects transitions between CJK / Ideographic
  codepoints (Unified Ideographs, Extension A/B, Hiragana, Katakana, Hangul) and non-ideographic
  Latin/ASCII/numeric alphanumeric codepoints, inserting 1/8 em (`0.125 * px`) inter-script spacing.
  When `no-autospace`, extra spacing is suppressed. Value inherits down the DOM/scene hierarchy.

- **Scrollbar Colors (`modules/ui_core/style.zig`, `scene.zig`, `src/windows.zig`, `packages/solid-zig/src/native.js`)**:
  Implemented `scrollbar-color` (`auto` | `<color> <color>`).
  Decomposes thumb and track colors with `currentColor` resolution. In native Raylib rendering
  (`src/windows.zig`), custom thumb and track colors are applied to vertical and horizontal
  scroll container scrollbars, falling back to default themes when set to `auto`.

- **Selector Donut Scoping (`modules/ui_core/css_scope.zig`, `packages/solid-zig/src/native.js`, `native.d.ts`)**:
  Implemented CSS Cascading and Inheritance Level 6 `@scope` selector evaluation.
  Supports scoping root (`<scope-start>`) and scope boundary limit (`to (<scope-end>)`)
  for donut scoping, verifying that elements match within the scoping root and outside any
  subordinate boundary ancestor. Handles nested selectors (`&` and `:scope`).

- **Print Color Adjustment (`modules/ui_core/style.zig`, `scene.zig`, `paint.zig`, `packages/solid-zig/src/native.js`)**:
  Implemented `print-color-adjust` (`economy` | `exact`).
  Propagates via CSS computed style inheritance. In `paint.zig`, `adjustPrintColor` provides ink-saving
  lightening of heavy saturated or dark backgrounds under `economy` mode, while `exact` preserves
  all authored background, shadow, and border colors without alteration.

- **MathML Typography (`modules/ui_core/style.zig`, `scene.zig`, `text.zig`, `packages/solid-zig/src/native.js`)**:
  Implemented `math-shift` (`normal` | `compact`).
  Inherited through scene typography context. When `compact`, font measurement adjusts baseline
  shift, ascent (scaled by 0.85) and line height (scaled by 0.9) to provide tightened math formula
  layout as specified in MathML Core Level 1.

## Issue & Compatibility Key Inventory

Counts describe the catalog scope, not passed tests.

| Issue | Feature (WebDX ID) | Eligible keys | Status |
| --- | --- | --- | --- |
| #308 | `writing-mode` | `css.properties.writing-mode.sideways-lr`<br>`css.properties.writing-mode.sideways-rl` | implemented-unverified |
| #307 | `view-transitions` | `css.properties.view-transition-name`<br>`css.properties.view-transition-name.match-element`<br>`css.properties.view-transition-name.none`<br>`css.selectors.view-transition`<br>`css.selectors.view-transition-group`<br>`css.selectors.view-transition-image-pair`<br>`css.selectors.view-transition-new`<br>`css.selectors.view-transition-old` | implemented-unverified |
| #306 | `view-transition-class` | `css.properties.view-transition-class`<br>`css.properties.view-transition-class.none` | implemented-unverified |
| #305 | `text-decoration-spelling-grammar` | `css.properties.text-decoration-line.grammar-error`<br>`css.properties.text-decoration-line.spelling-error` | implemented-unverified |
| #304 | `text-decoration` | `css.properties.text-decoration.currentColor`<br>`css.properties.text-decoration.includes_color-and-style`<br>`css.properties.text-decoration.includes_thickness`<br>`css.properties.text-decoration.transparent` | implemented-unverified |
| #303 | `text-autospace` | `css.properties.text-autospace`<br>`css.properties.text-autospace.no-autospace`<br>`css.properties.text-autospace.normal` | implemented-unverified |
| #302 | `scrollbar-color` | `css.properties.scrollbar-color`<br>`css.properties.scrollbar-color.auto` | implemented-unverified |
| #301 | `scope` | `css.selectors.nesting.at-scope` | implemented-unverified |
| #300 | `print-color-adjust` | `css.properties.print-color-adjust`<br>`css.properties.print-color-adjust.economy`<br>`css.properties.print-color-adjust.exact` | implemented-unverified |
| #299 | `mathml` | `css.properties.math-shift` | implemented-unverified |

**Total Issues**: 10
**Total Eligible Compatibility Keys**: 28
**Verified Status**: All unverified (testing is explicitly paused per instructions).
