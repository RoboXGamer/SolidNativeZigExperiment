# CSS 2024 Implementation Batch 9

This delivery implements the designated 10 CSS 2024 issues in `RoboXGamer/SolidNativeZigExperiment` covering registered custom properties, relative color syntax, relative positioning, root font-relative units (rem, rlh), resolution media queries with webkit compatibility prefixes, the revert keyword, the :root pseudo-class selector, and ruby text alignment.

As instructed, testing is paused (no builds, tests, typechecks, browser comparisons, or test authoring ran). All features are marked as `implemented-unverified` or `partial-unverified` accordingly.

## Ticket Disposition and Coverage

| Issue | Feature ID | Status | Scope Implemented / Remaining Scope |
| --- | --- | --- | --- |
| #205 | `registered-custom-properties` | implemented-unverified | Implemented `@property` custom property registry (`registerProperty`), descriptor attributes (`name`, `syntax`, `inherits`, `initialValue`), variable inheritance filtering based on `inherits` flag, fallback to `initialValue`, and `var(--name, fallback)` resolution across styles. Exposed on `CSS.registerProperty`. |
| #206 | `relative-color` | implemented-unverified | Implemented CSS Color 5 relative color parsing in `colors.zig` for `rgb(from ...)`, `rgba(from ...)`, `hsl(from ...)`, `hsla(from ...)`, `hwb(from ...)`, `lab(from ...)`, `lch(from ...)`, `oklab(from ...)`, `oklch(from ...)`, and `color(from ...)`. Added forward color conversions `rgbToHsl`, `rgbToHwb`, `rgbToLab`, `rgbToLch`, `rgbToOklab`, `rgbToOklch`. Channel variable substitution and `calc(...)` evaluation on color components (`css.types.calc.color_component`). |
| #207 | `relative-positioning` | implemented-unverified | Implemented relative positioning (`position: relative`) in `modules/ui_core/scene.zig`. Normal flow layout preservation for siblings; offset computation using `top`, `bottom`, `left`, `right`; CSS Position 3 specification precedence (in LTR `left` wins, in RTL `right` wins; `top` wins over `bottom`); definite containing-block percentage inset resolution; stacking context participation with `zIndex`. |
| #208 | `rem` | implemented-unverified | Implemented root-font-relative length unit `rem` resolving against root element computed `root_font_size` in `sizing.Context` and `scene.zig`. Initial value fallback on root element itself. Supported across layout sizing, margins, padding, borders, gaps, and font size in both Zig and JavaScript. |
| #209 | `resolution` | implemented-unverified | Added `"x"` unit alias for `dppx` in `sizing.zig` `Dimension.resolution` alongside `dppx`, `dpi`, and `dpcm`. Implemented resolution media query evaluation in `matchMedia` (`resolution`, `min-resolution`, `max-resolution`) with standard conversion ratios (96 dpi = 1 dppx, 1 dpcm = 96/2.54 dpi). |
| #210 | `resolution-compat` | implemented-unverified | Implemented `-webkit-device-pixel-ratio`, `-webkit-min-device-pixel-ratio`, and `-webkit-max-device-pixel-ratio` compatibility media query parsing and matching in `matchMedia`, supporting decimal and fractional ratios (e.g. `3/2`). |
| #211 | `revert-value` | implemented-unverified | Implemented CSS global keyword `revert` in `packages/solid-zig/src/native.js`. Differentiates between inherited properties (rolling back to inherited value from parent) and non-inherited properties (rolling back to user-agent / default element style). |
| #213 | `rlh` | implemented-unverified | Implemented root line-height relative length unit `rlh` resolving against root element computed `root_line_height` in `sizing.Context`. Computed default root line-height from text metrics when unstated; propagated through child contexts in `scene.zig`. Added `rlh` and `lh` to JavaScript length recognition. |
| #214 | `root` | implemented-unverified | Implemented `:root` pseudo-class matching in `renderer.js` and `native.js` via `matchesSelector(node, ":root")`, identifying tree root (`node.type === "root"` or `node.parent == null`). |
| #216 | `ruby-align` | implemented-unverified | Added `rubyAlign` property to `Style` in `style.zig` and `Typography` in `text.zig`. Initial value is `"space-around"`. Allowed keyword values: `"start"`, `"center"`, `"space-between"`, `"space-around"`. Inherited down the tree via `inheritComputedStyle` and propagated through `textContext`. Expose in TypeScript declarations and JavaScript snapshot serializer. |

## Files Modified

- `modules/ui_core/colors.zig`: Forward color conversions (`rgbToHsl`, `rgbToHwb`, `rgbToLab`, `rgbToLch`, `rgbToOklab`, `rgbToOklch`), channel evaluation with `calc()` on color components, and relative color parser for `rgb`, `hsl`, `hwb`, `lab`, `lch`, `oklab`, `oklch`, and `color`.
- `modules/ui_core/sizing.zig`: Added `"x"` unit to `Dimension.resolution`.
- `modules/ui_core/style.zig`: Added `rubyAlign: []const u8 = "space-around"` to `Style`.
- `modules/ui_core/text.zig`: Added `ruby_align` field to `Typography`.
- `modules/ui_core/scene.zig`: Added `rubyAlign` validation in `resolveStyle`, inheritance in `inheritComputedStyle`, assignment in `textContext`; computed and propagated `root_line_height` in `length_context`; updated `position: relative` offset resolution respecting `rtl`/`ltr` direction and inset precedence.
- `packages/solid-zig/src/native.js`: Added `propertyRegistry`, `registerProperty`, variable resolution (`resolveVariablesInString`, `resolveNodeVariables`), `revert` resolution, `matchMedia` with resolution and webkit device-pixel-ratio queries, `rem`/`rlh` regex matching, `rubyAlign` snapshot serialization.
- `packages/solid-zig/src/native.d.ts`: Added `rubyAlign`, custom property index signature `[key: --${string}]: any`, `PropertyDefinition`, `registerProperty`, and `matchMedia` declarations.
- `packages/solid-zig/src/renderer.js`: Added `matchesSelector` supporting `:root` pseudo-class.
