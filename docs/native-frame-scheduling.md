# Phase-aware bridge and native frame scheduling

The host no longer equates an input event with a frame, or a bridge patch with layout. Solid's reactive graph stays in JavaScript. Its resulting node changes retain their identity and phase information across the native bridge.

## Shared input contract

`modules/ui_core/style.zig` defines separate `LayoutStyle`, `PaintStyle`, `InteractionStyle` and `MotionStyle` input types. The existing flat `Style` wire type is derived from those definitions at compile time. Each new native style field must belong to a phase; there is no separate property-name classifier or fallback list to keep synchronized.

`modules/ui_core/frame_inputs.zig` defines the corresponding node inputs and phase deltas. `node tools/generate-frame-inputs.mjs` generates `packages/solid-zig/src/frame-inputs.json` from those declarations. The JavaScript test command checks that the generated contract is current.

The JavaScript host resolves CSS and compares computed native inputs with the last acknowledged snapshot. `uiFrameChanges()` sends complete nodes for new identities, phase-specific updates for existing identities, and removals. Multiple Solid writes before collection coalesce into one update per node. `uiCommit()` acknowledges a batch; until then it remains available for retry. The legacy `uiChanges()` full-node API remains available for diagnostics and existing callers.

The native retained tree applies a batch atomically, validates its structure and advances per-node and tree phase revisions. Phase deltas compare only the input groups actually supplied. Unknown identities, duplicate updates and invalid structures leave the previous tree and revisions intact.

## Stage ownership

- Layout inputs include structure, text, control values, font metrics and box geometry. Changes run the existing native layout implementation.
- Paint inputs include colors, backgrounds, opacity, radii, outlines and clipping. Changes refresh independently owned paint values while retaining measured boxes and scroll positions. Inherited colors and `currentColor` are recomputed without mutating layout inputs.
- Interaction inputs include hover/active/focus flags, hit-test controls and cursors. Their independent storage updates the retained scene without recreating paint inputs or running layout. Cursor inheritance is retained.
- Motion inputs configure transitions. Active paint transitions sample existing boxes; layout-dependent transitions continue to update geometry. The final transition sample is painted before the host returns to event waiting.

Anonymous layout projections that cannot be mapped back to retained identities conservatively rebuild the scene. Ordinary CSS demo nodes use the retained paths.

## Input processing and presentation

The Windows loop processes input, timer jobs and HMR before consuming the bridge batch. It updates the required stages and the native cursor, then draws only for an initial frame, changed pixels/geometry, scrolling, editing/focus changes, active animation or window damage.

When pixels are unchanged, the loop calls Raylib's input processing directly without `BeginDrawing`, renderer execution, `EndDrawing` or a buffer swap. Event waiting and timer deadlines are scheduled on both paths. The polling fallback sleeps between iterations. Viewport information is sent to JavaScript on resize rather than on every mouse event.

A chained GLFW refresh callback invalidates painting for window exposure. Resize requests layout and painting. Scrolling reapplies offsets from retained unscrolled boxes, rather than rerunning layout or accumulating previous translations. Geometry/hit-test changes beneath a stationary pointer schedule immediate reconciliation.

## Verification

```powershell
pnpm test
zig build test
zig build test-native
pnpm test:frames:native
pnpm test:hover:native
```

The native frame test builds `tests/fixtures/frame-probe.js`, runs a hidden native application with actual GLFW event waiting, and injects local pointer coordinates without moving the user's OS cursor. It checks every iteration:

- Initial paint, followed by 120 moves within unchanged content: no additional painting or layout.
- Hover background entry: painting without layout; entering the button's text: neither.
- Cursor-only style change: neither painting nor layout.
- Width change: layout and painting.
- Timer-driven color change: painting without layout.
- Windows `WM_PAINT` exposure: painting without layout.
- Resize: layout and painting.
- Focus change: painting without layout.

The measured run completed 130 iterations with 7 paints and 3 layout builds, including initialization. These are asserted application work counts, not measurements of physical mouse latency or Task Manager utilization. The test driver restores the ordinary CSS bundle and executable afterward.

Core tests cover phase isolation, stable geometry and text-measure counts, retained interaction-node identity, atomic batch failure, string ownership, repeated paint refreshes, scroll stability and paint transitions. JavaScript tests exercise actual Solid signals, phase-specific packets, coalescing and acknowledgement retries. Existing CSS, control, native framebuffer and HMR regressions continue to apply.

## Scope and remaining work

The existing painting/compositing renderer is unchanged. A required paint still uses its current offscreen layers and shaders; improving that machinery or replacing it with another renderer is separate work. Geometry changes still run the existing complete layout pass. JavaScript still performs CSS resolution and snapshot preparation on dirty revisions; this change preserves phase granularity across the bridge rather than moving Solid's reactive graph into Zig.
