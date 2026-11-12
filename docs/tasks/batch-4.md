# CSS 2024 Batch 4 Implementation Task Report

Implementation-only delivery for 10 GitHub issues (#271, #270, #269, #268, #266, #265, #264, #263, #262, #261) in `RoboXGamer/SolidNativeZigExperiment`.

Testing is explicitly **PAUSED**: no builds, tests, typechecks or test authoring were executed. All features are documented as `implemented-unverified` with end-to-end paths implemented across Solid universal renderer, QuickJS bridge, native scene/layout, and raylib rendering/event systems.

---

## Implemented Subsystems & Native Paths

### 1. User Action Pseudo-Classes (#271: `user-action-pseudos`)
- **Native Event Detection & Dispatch**:
  - `src/windows.zig`: Evaluates `scene.pointerTarget(x, y)` on mouse movement to detect hovered item transitions; tracks `last_hovered` and dispatches `runtime.hover(id, is_hovered)`.
  - Tracks left mouse button down on hovered items to detect active state; dispatches `runtime.active(id, is_active)`.
  - Tracks focused item changes and dispatches `runtime.focus(id, is_focused)`.
- **Bridge & Universal Renderer**:
  - `modules/solid_bridge/root.zig`: Added `hover(id, is_hovered)`, `active(id, is_active)`, and `focus(id, is_focused)` to `Runtime`.
  - `packages/solid-zig/src/native.js`: Implemented `dispatchHover`, `dispatchActive`, and `dispatchFocus`; registered global dispatchers `uiDispatchHover`, `uiDispatchActive`, `uiDispatchFocus`.
  - Supported pseudo-classes in JSX styling: `:hover`, `:active`, `:focus` (as well as `_hover`, `_active`, `_focus`) on all elements including `<a>` elements and non-`<a>` elements (`<button>`, `<input>`, `<select>`, `<div>`, `<row>`, etc.).
- **Retained State**:
  - `modules/ui_core/tree.zig` & `modules/ui_core/scene.zig`: Added `hovered`, `active`, `focused` flags to `FlatNode` and `Node`.

### 2. Update Frequency Media Query (#270: `update`)
- **Query Evaluation**:
  - `modules/ui_core/sizing.zig`: Added `UpdateFrequency` enum (`none`, `slow`, `fast`) and `evaluateUpdateMediaQuery(query, current_frequency)`.
  - `packages/solid-zig/src/native.js`: Implemented `evaluateMediaQuery(query)` and `matchMedia(query)` supporting `(update: fast)` (evaluates to `true`), `(update: slow)` / `(update: none)` (`false`), and boolean `(update)` (`true` for continuous native 60fps refresh).

### 3. CSS `unset` Keyword (#269: `unset-value`)
- **Cascading & Reset Logic**:
  - `packages/solid-zig/src/native.js`: Implemented `resolveUnsetValues(style, inherited)` based on CSS Cascading and Inheritance Level 4.
  - Inherited properties (`color`, `fontFamily`, `fontSize`, `fontWeight`, `fontStyle`, `language`, `lineHeight`, `letterSpacing`, `wordSpacing`, `tabSize`, `textAlign`, `textAlignLast`, `textTransform`, `textIndent`, `whiteSpace`, `visibility`, `cursor`, `direction`, `writingMode`) resolve to inherited parent values (or initial if root).
  - Non-inherited properties (`display`, `margin*`, `padding*`, `border*`, `width`, `height`, `minWidth`, `minHeight`, `maxWidth`, `maxHeight`, `position`, insets, `opacity`, `isolation`, `transform`, `transformOrigin`, `transformBox`, `backfaceVisibility`, `transformStyle`, `perspective`, `perspectiveOrigin`, `touchAction`, `transition*`, `boxSizing`, `overflow`, `outline*`, `zIndex`) reset to spec initial defaults.

### 4. Two-Value Display Property (#268: `two-value-display`)
- **Multi-Keyword Normalization**:
  - `packages/solid-zig/src/native.js`: Enhanced `displayOf` to parse multi-keyword syntax combining outside display (`block`, `inline`) and inside display (`flow`, `flow-root`, `flex`, `grid`, `table`, `ruby`) in either order.
  - Mapped combinations: `block flow` -> `block`, `inline flow` -> `inline`, `block flow-root` -> `flow-root`, `inline flow-root` -> `inline-block`, `block flex` -> `flex`, `inline flex` -> `inline-flex`, `block grid` -> `grid`, `inline grid` -> `inline-grid`, `inline table` -> `inline-table`, `block table` -> `table`, and legacy `inline block` / `block inline` -> `inline-block`.

### 5. Transitions (#266: `transitions`)
- **Timing Functions & Sizing**:
  - `modules/ui_core/transitions.zig`: Comprehensive support for longhands (`transition-property`, `transition-duration`, `transition-delay`, `transition-timing-function`) and shorthand (`transition`).
  - Supported timing functions: `ease`, `ease-in`, `ease-out`, `ease-in-out`, `linear`, `step-start`, `step-end`, `steps()` with `jump-start`, `jump-end`, `jump-none`, and `jump-both`.
  - Property matching supports `all`, `none`, and individual identifiers. Correctly handles `transition: none` and `transition-property: none`.

### 6. Transition-Behavior (#265: `transition-behavior`)
- **Discrete Property Transitions**:
  - `modules/ui_core/style.zig`: Added `transitionBehavior: []const u8 = "normal"`.
  - `modules/ui_core/transitions.zig`: Config parses `transition-behavior` property and shorthand keywords `normal` and `allow-discrete`.
  - Discrete transitions supported via `Value.discrete` at the CSS Transitions Level 2 50% midpoint threshold.

### 7. 3D Transforms (#264: `transforms3d`)
- **4x4 Matrix Mathematics & Projection**:
  - `modules/ui_core/transform.zig`: Introduced `Matrix4x4` struct with column-major memory layout compatible with OpenGL and raylib `rl.Matrix`.
  - Implemented 4x4 multiplication, inversion (2x2 cofactor block method), and 3D transformation functions:
    - `translate3d(tx, ty, tz)`, `translateZ(tz)`
    - `scale3d(sx, sy, sz)`, `scaleZ(sz)`
    - `rotateX(rad)`, `rotateY(rad)`, `rotateZ(rad)`, `rotate3d(x, y, z, rad)`
    - `perspective(d)` and `perspective(none)`
    - `matrix3d(m0..m15)`
- **Properties & Renderer Integration**:
  - `modules/ui_core/style.zig`: Added `perspective`, `perspectiveCss`, `perspectiveOrigin`, `transformStyle`, `backfaceVisibility`.
  - `modules/ui_core/scene.zig`: Added `localTransform4x4`, `worldTransform4x4`, and perspective origin projection.
  - `src/renderer.zig`: Enabled `rl.gl.rlMultMatrixf(&matrix)` with full 4x4 matrix for layer, content, and outline rendering.
  - Implemented backface culling when `backface-visibility: hidden` and normal faces away from viewer (`w4.isBackface()`).

### 8. 2D Transforms (#263: `transforms2d`)
- **Functions, Origin & Units**:
  - `modules/ui_core/transform.zig`: Full support for 2D functions (`matrix`, `rotate`, `scale`, `scaleX`, `scaleY`, `skew`, `skewX`, `skewY`, `translate`, `translateX`, `translateY`) and `transform: none`.
  - Supported angle units: `deg`, `rad`, `grad`, `turn`, and `<angle-percentage>` (`100% = 360deg`).
  - Supported `transform-origin`: 1-value, 2-value, 3-value (`three_value_syntax` with z offset), and 4-value position syntax (`right 10px bottom 20px`, etc.).
  - Preserved inverse transformation for mouse hit testing and local coordinate mapping.

### 9. Transform-Box (#262: `transform-box`)
- **Reference Box Resolution**:
  - `modules/ui_core/style.zig`: Added `transformBox: []const u8 = "border-box"`.
  - `modules/ui_core/scene.zig`: In `localTransform4x4`, resolved reference box according to `transformBox`:
    - `content-box`: reference box is `item.node.contentBox(item.bounds)`.
    - `border-box` / `view-box` / `fill-box` / `stroke-box`: reference box is `item.bounds`.
  - Origin coordinates and percentage sizing compute relative to the selected reference box.

### 10. Touch-Action (#261: `touch-action`)
- **Touch & Gesture Policy**:
  - `modules/ui_core/style.zig`: Added `touchAction: []const u8 = "auto"`.
  - `modules/ui_core/interaction.zig`: Implemented `touchActionAllowsPanX`, `touchActionAllowsPanY`, and `touchActionAllowsPinchZoom`.
  - `src/windows.zig`: When mouse wheel / scroll events occur, checks hit target's `touchAction`; inhibits vertical scrolling when `touchActionAllowsPanY` is false (e.g. `touch-action: none` or `touch-action: pan-x`).

---

## Issue Coverage & Verification Status Table

| Issue | Feature ID | Eligible Keys | Status | Scope / Implementation Notes |
|---|---|---|---|---|
| #271 | `user-action-pseudos` | 6 | implemented-unverified | Native hover/active/focus tracking, QuickJS bridge dispatch, JSX :hover/:active/:focus overrides for all elements |
| #270 | `update` | 1 | implemented-unverified | Update frequency media feature evaluation (fast, slow, none) in native sizing and JS matchMedia |
| #269 | `unset-value` | 1 | implemented-unverified | Full CSS Cascading Level 4 unset resolution: inherited properties to parent, non-inherited to initial |
| #268 | `two-value-display` | 1 | implemented-unverified | Multi-keyword outside + inside display values in either order mapped to native layout |
| #266 | `transitions` | 25 | implemented-unverified | Transition shorthand and longhands, delay, duration, property (all, none, ident), timing functions (ease*, linear, step*, jump*) |
| #265 | `transition-behavior` | 1 | implemented-unverified | transition-behavior property ("normal", "allow-discrete") and shorthand syntax, 50% midpoint discrete switching |
| #264 | `transforms3d` | 26 | implemented-unverified | 4x4 matrix, 3D functions (translate3d, translateZ, scale3d, scaleZ, rotate3d, rotateX, rotateY, rotateZ, matrix3d, perspective), backface culling |
| #263 | `transforms2d` | 30 | implemented-unverified | 2D functions, angle types (deg, rad, grad, turn, angle-percentage), 1/2/3/4-value transform-origin and position syntax |
| #262 | `transform-box` | 6 | implemented-unverified | Reference box selection (content-box, border-box, fill-box, stroke-box, view-box) for transform & transform-origin |
| #261 | `touch-action` | 6 | implemented-unverified | Touch-action values (auto, none, pan-x, pan-y, pinch-zoom, manipulation) and native scroll inhibition |

**Total issues**: 10  
**Total eligible keys covered**: 103  
**Verification note**: Per user instructions, testing was paused (no builds, tests, typechecks or test authoring). Status is implementation-only and unverified.
