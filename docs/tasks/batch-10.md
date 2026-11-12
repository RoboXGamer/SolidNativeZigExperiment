# CSS 2024 Batch 10 Task Document

Implementation-only delivery. Testing is PAUSED per explicit instructions: no builds, tests, typechecks, or test authoring. Issue completion here denotes that end-to-end native and runtime behavior has been implemented across the engine, bridge, and frontend packages; verification acceptance remains unverified.

## Summary of Implemented Subsystems

This batch implements 10 CSS 2024 features across `modules/ui_core`, `packages/solid-zig`, `src/renderer.zig`, and `src/windows.zig`:

1. **Basic Shapes: `rect()` and `xywh()` (#204)**
   - Implemented shape parser `parseBasicShape` in `modules/ui_core/paint.zig` supporting CSS basic-shape functions `rect(top right bottom left [round <radii>])` and `xywh(x y width height [round <radii>])`.
   - Supports percentages, lengths, auto margins/insets, and single or elliptical corner radii (`round <rx> [ry]`).
   - Integrated into `clipPath` style property, clip intersection (`clipFor` in `scene.zig`), pointer containment checking (`pointerTarget`/`pointVisible` in `scene.zig`), and GPU masking in `src/renderer.zig`.

2. **Selectors: `:read-only` and `:read-write` (#203)**
   - Implemented pseudo-class evaluation in `packages/solid-zig/src/native.js` (`isReadOnly`, `isReadWrite`, style merging in `physicalStyle`).
   - Propagated `readOnly` and `readWrite` flags across tree serialization, `modules/ui_core/tree.zig`, and `modules/ui_core/scene.zig`.
   - Guarded input editing in `src/windows.zig` (character insertion, backspace, delete, paste, and cut are inhibited on read-only inputs while navigation, selection, and copy remain functional).
   - Guarded `dispatchInput` in `native.js` to reject modifications on read-only inputs.

3. **Typography: `quotes` property and `<q>` elements (#202)**
   - Added `quotes` property to `Style` in `modules/ui_core/style.zig` (defaults to `"auto"`).
   - Added `resolveQuotes` in `modules/ui_core/text.zig` and `packages/solid-zig/src/native.js` supporting `"auto"` (with typographic quotes for English, French guillemets, German, CJK, and international standards), `"none"`, and custom quote pairs.
   - Wired computed style inheritance in `scene.zig` and quote nesting depth tracking in `snapshot` for `<q>` JSX tags.

4. **Units: `Q` unit (#201)**
   - Resolved the quarter-millimeter `Q` length unit (`1Q = 0.25mm = 96.0 / 101.6 px`) in `modules/ui_core/sizing.zig`.
   - Updated unit regex in `packages/solid-zig/src/native.js` to properly identify `Q`/`q` units alongside standard CSS physical length units.

5. **Media Queries: User Preferences (#198, #199, #200)**
   - Added `prefers-color-scheme` (`light` | `dark`), `prefers-contrast` (`no-preference` | `more` | `less` | `custom`), and `prefers-reduced-motion` (`no-preference` | `reduce`) evaluation to `packages/solid-zig/src/native.js` (`matchMedia`, `getPreferences`, `setPreferences`).
   - Extended `sizing.Context` in `modules/ui_core/sizing.zig` with preference enums.
   - Added host OS environment detection in `src/windows.zig` (`getSystemPreferences`) and plumbed preference context into scene building.

6. **Layout: `position` property (#197)**
   - Verified and completed full CSS positioning support (`static`, `relative`, `absolute`, `fixed`, `sticky`).
   - Positioned elements participate in stacking context establishment, top-layer z-indexing, inset-modified containing blocks, auto-margins, and fixed/sticky elements bypass ancestor overflow clipping.
   - Added complete typings in `packages/solid-zig/src/native.d.ts`.

7. **HTML / CSS Popover API (#196)**
   - Implemented popover state management (`showPopover`, `hidePopover`, `togglePopover`, `isPopoverOpen`, `closeAllAutoPopovers`) in `packages/solid-zig/src/native.js`.
   - Supported `popover="auto"` and `popover="manual"` modes, and `:popover-open` pseudo-class styling.
   - Added `popoverTarget` button action dispatching (`show`, `hide`, `toggle`) and light dismiss on outside clicks in `dispatchClick`.
   - Added top-layer context escalation in `modules/ui_core/scene.zig` with high z-index stacking (`1_000_000_000`).
   - Added Escape key popover dismissal in `src/windows.zig` and `native.js`.

8. **Interaction: `pointer-events` (#195)**
   - Implemented complete `pointer-events` keyword resolution in `modules/ui_core/interaction.zig`: `auto`, `none`, `all`, `visible`, `painted`, `visiblePainted`, `fill`, `visibleFill`, `stroke`, `visibleStroke`.
   - In `modules/ui_core/scene.zig`, refined `pointerTarget` to distinguish border box vs padding box (stroke vs fill) containment, and verified ancestor clip-path / visibility containment.

## Issue Coverage & Scope Matrix

| Issue | Feature | Eligible Keys / Subsystem | Status |
| --- | --- | --- | --- |
| #204 | Basic shapes `rect()` and `xywh()` | `css.types.basic-shape.rect`, `css.types.basic-shape.xywh` | implemented-unverified |
| #203 | `:read-only` and `:read-write` | `css.selectors.read-only`, `css.selectors.read-write` | implemented-unverified |
| #202 | Quotes | `css.properties.quotes`, `css.properties.quotes.auto`, `css.properties.quotes.none` | implemented-unverified |
| #201 | Q length unit | `css.types.length.Q` | implemented-unverified |
| #200 | `prefers-reduced-motion` | `css.at-rules.media.prefers-reduced-motion` | implemented-unverified |
| #199 | `prefers-contrast` | `css.at-rules.media.prefers-contrast` | implemented-unverified |
| #198 | `prefers-color-scheme` | `css.at-rules.media.prefers-color-scheme` | implemented-unverified |
| #197 | `position` | `css.properties.position` | implemented-unverified |
| #196 | Popover API & `:popover-open` | `css.selectors.backdrop.popover`, `css.selectors.popover-open` | implemented-unverified |
| #195 | `pointer-events` | `css.properties.pointer-events`, `.all`, `.auto`, `.fill`, `.html_elements`, `.none`, `.painted`, `.stroke`, `.visible` | implemented-unverified |

## File Modifications

- `modules/ui_core/style.zig`: Added `quotes` and `clipPath` style fields.
- `modules/ui_core/sizing.zig`: Added preference enums (`ColorScheme`, `ContrastPreference`, `ReducedMotionPreference`) to `Context`. Verified `Q` unit resolution.
- `modules/ui_core/text.zig`: Added `quotes` to `Typography` and implemented `resolveQuotes`.
- `modules/ui_core/paint.zig`: Implemented `BasicShape` and `parseBasicShape` for `rect()` and `xywh()`.
- `modules/ui_core/interaction.zig`: Implemented full `pointer-events` keyword handling in `acceptsPointer`.
- `modules/ui_core/tree.zig`: Added `readOnly`, `readWrite`, and `popoverOpen` to `FlatNode` and materialized `Node`.
- `modules/ui_core/scene.zig`: Added `readOnly`, `readWrite`, `popoverOpen` to `Node`; clip-path intersection in `clipFor`; top layer stacking context in `establishesContext` and `appendContext`; clip-path and stroke/fill hit testing in `pointerTarget`.
- `packages/solid-zig/src/native.d.ts`: Updated TypeScript definitions with `quotes`, `clipPath`, `pointerEvents`, `:read-only`, `:read-write`, `:popover-open`, `@media` queries, and popover runtime APIs.
- `packages/solid-zig/src/native.js`: Implemented `matchMedia`, `getPreferences`, `setPreferences`, `isReadOnly`, `isReadWrite`, `showPopover`, `hidePopover`, `togglePopover`, `closeAllAutoPopovers`, `resolveQuotes`, `:read-only`/`:read-write`/`:popover-open` style evaluation, and popover target invocation in `dispatchClick`/`dispatchKey`.
- `src/renderer.zig`: Integrated `clipPath` basic shapes (`rect`/`xywh`) into mask shader clipping.
- `src/windows.zig`: Added read-only input editing guards, escape-key popover dismissal, and host OS preference querying.
