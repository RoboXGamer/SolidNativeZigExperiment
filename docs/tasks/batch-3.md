# Batch 3 CSS Baseline 2024 Implementation — 2026-11-12

Implementation-only delivery for the 10 assigned GitHub issues in `RoboXGamer/SolidNativeZigExperiment`.
All builds, tests, typechecks, and test authoring remained PAUSED per user instruction.
Status across all items is implementation-only and unverified; no runtime, browser, or test execution is claimed.

## Subsystem Architecture & Changes

### Typography & Text Layout
- **word-break (#284)**:
  - Added `wordBreak: []const u8 = "normal"` to `Style` (`modules/ui_core/style.zig`) and `Typography` (`modules/ui_core/text.zig`).
  - Added native inheritance in `scene.zig` and JSX style adapter in `packages/solid-zig/src/native.js`.
  - Implemented `break-all` in `shapeLines` to allow grapheme-by-grapheme breaking when a candidate word exceeds available capacity, and in `minContentWidth` to measure single grapheme cluster minima instead of unbroken words.
  - Supported `keep-all` to preserve continuous CJK word units without breaking, alongside default `normal` breaking.
- **white-space-collapse (#281)**:
  - Added longhand `whiteSpaceCollapse` to `Style`, `Typography`, and `NativeStyle`.
  - Implemented `collapseWhitespaceMode` in `text.zig` to differentiate `collapse`, `preserve`, `preserve-breaks`, and `break-spaces`.
  - Updated `shapeLines` to preserve/collapse line breaks and spaces consistently with CSS Text Level 4.
- **vertical-align (#273)**:
  - Added `verticalAlign`, `verticalAlignOffset`, and `verticalAlignCss` to `Style`, `Typography`, and `NativeStyle`.
  - Added `offset_y: f32` to `ShapedLine`.
  - Added keyword resolution for `baseline`, `sub`, `super`, `middle`, `top`, `text-top`, `bottom`, and `text-bottom`, plus length/percentage CSS resolution in `scene.zig`.
  - Applied `sline.offset_y` to line drawing in `src/windows.zig`.

### Box Model, Sizing & Writing Modes
- **Width and height (#282)**:
  - Maintained distinct representation of `"auto"`, numeric lengths, percentages, and `calc()` expressions through `sizing.zig` and `scene.zig`.
  - Indefinite containing-block percentage height/width dimensions compute cleanly without panicking.
  - Animatable width/height property interpolation retained across `transitions.zig`.
- **Vertical form controls (#274)**:
  - Form controls (`input`, `select`, `button`) respect `writing-mode: vertical-rl` and `vertical-lr`.
  - Input text rendering and caret geometry orient along the vertical inline axis in `src/windows.zig` (horizontal caret line, vertical advance, vertical selection rect).
  - Select indicator positioning aligns along the vertical axis.
- **visibility (#277)**:
  - Validated `visible`, `hidden`, and `collapse` in `modules/ui_core/scene.zig`.
  - Inherited natively while allowing explicitly `visible` children of hidden ancestors to paint.
  - Non-visible items reserve layout space but skip rasterization and pointer events in `interaction.zig`, `renderer.zig`, and `windows.zig`.
- **will-change (#283)**:
  - Added `willChange` to `Style` and `NativeStyle`.
  - Validated syntax in `scene.zig` (`auto`, `scroll-position`, `contents`, `transform`, `opacity`, property lists).
  - Wired into `establishesContext` in `modules/ui_core/scene.zig` so hinting properties like `transform`, `opacity`, `scroll-position`, or `contents` creates stacking contexts.

### Selectors & User Pseudo-Classes
- **:where() (#279)**:
  - Implemented selector engine in `packages/solid-zig/src/selectors.js`.
  - Supports `:where(...)` with forgiving selector list parsing (invalid selector components in the argument list are ignored instead of failing the selector).
  - Guarantees `[0, 0, 0]` specificity for `:where(...)`.
- **:user-valid & :user-invalid (#272)**:
  - Added user interaction tracking (`_userInteracted`) upon `dispatchInput`, `dispatchSelectChange`, and `dispatchClick`.
  - Implemented constraint validation (`checkValidity`) for `required`, `pattern`, `min`, `max`, and `type="email"`.
  - `:user-valid` and `:user-invalid` pseudo-classes only match on controls that the user has interacted with, applying reactive pseudo-styles in component snapshots and selector sheets.
- **WebVTT ::cue (#278)**:
  - Added `::cue` and `::cue(selector)` pseudo-element matching in `selectors.js` for `<cue>`, `<track>`, and cue-annotated elements.
  - Added `cue` and `track` intrinsic elements to JSX typings in `native.d.ts`.

## Ticket Scope & Disposition Ledger

| Issue | Feature | Eligible Keys | Status | Scope / Remaining Work |
| --- | --- | --- | --- | --- |
| #284 | word-break | 4 | implemented-unverified | `normal`, `break-all`, `keep-all` in layout/metrics/wrapping; full Unicode dictionary hyphenation remains future work |
| #283 | will-change | 4 | implemented-unverified | `auto`, `contents`, `scroll-position`, property lists; triggers stacking contexts; dedicated GPU compositor layer allocation remains future work |
| #282 | width-height | 9 | implemented-unverified | Dimensions, lengths, percentages, length-percentage, auto, and animatable transitions; full IFC inline box sizing remains separate |
| #281 | white-space-collapse | 5 | implemented-unverified | `collapse`, `preserve`, `preserve-breaks`, `break-spaces` across text collapsing and shaping; complex bidi segment boundaries remain separate |
| #279 | where | 2 | implemented-unverified | `:where()` with forgiving selector list parsing and zero specificity; CSSOM stylesheet linking remains host-level |
| #278 | webvtt | 1 | implemented-unverified | `::cue` and `::cue(selector)` matching cue elements and styling; platform video playback pipeline is host-dependent |
| #277 | visibility | 4 | implemented-unverified | `visible`, `hidden`, `collapse` paint/hit policy and native inheritance; table-specific collapse layout remains separate |
| #274 | vertical-form-controls | 1 | implemented-unverified | Vertical inputs, carets, selections, and select controls in `vertical-rl`/`vertical-lr`; complex native IME floating popups remain host-managed |
| #273 | vertical-align | 9 | implemented-unverified | `baseline`, `sub`, `super`, `middle`, `top`, `text-top`, `bottom`, `text-bottom`, lengths and percentages on shaped lines; full inline fragmentation remains separate |
| #272 | user-pseudos | 2 | implemented-unverified | `:user-valid` and `:user-invalid` matching only post-interaction with validation contract; form submission lifecycle remains host-managed |
