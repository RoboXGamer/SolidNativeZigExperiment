# Phase-aware bridge and native frame scheduling

The host no longer equates an input event with a frame, or a bridge patch with layout. Solid's reactive graph stays in JavaScript. Its resulting node changes retain their identity and phase information across the native bridge.

## Shared input contract

`modules/ui_core/style.zig` defines separate `LayoutStyle`, `PaintStyle`, `InteractionStyle` and `MotionStyle` input types. The existing flat `Style` wire type is derived from those definitions at compile time. Each new native style field must belong to a phase; there is no separate property-name classifier or fallback list to keep synchronized.

`modules/ui_core/frame_inputs.zig` defines the corresponding node inputs and phase deltas. `node tools/generate-frame-inputs.mjs` generates `packages/solid-zig/src/frame-inputs.json` from those declarations. The JavaScript test command checks that the generated contract is current.

The JavaScript host resolves CSS and compares computed native inputs with the last acknowledged snapshot. `uiFrameChanges()` sends complete nodes for new identities, phase-specific updates for existing identities, and removals. Multiple Solid writes before collection coalesce into one update per node. `uiCommit()` acknowledges a batch; until then it remains available for retry.

The native retained tree applies a batch atomically and advances per-node and tree phase revisions. Existing identities with unchanged child edges commit only the staged entries; they do not clone or traverse the full node map. Structural changes validate the complete graph. Unknown identities, duplicate updates and invalid structures leave the previous tree and revisions intact.

Typography ownership bits are shared by name in the generated contract but sent with the phase of the corresponding property. For example, explicitly specifying or removing inherited `text-shadow` changes paint inputs without invalidating font metrics. Visibility ownership belongs to paint; cursor and pointer-events ownership belongs to interaction. Opening a popover is a paint input because it changes visual stacking.

## Stage ownership

- Layout inputs include structure, text, control values, font metrics and box geometry. Changes run the existing native layout implementation.
- Paint inputs include colors, backgrounds, opacity, radii, outlines and clipping. Changes replace independently owned per-node paint values while retaining node identities, measured boxes and scroll positions. Inherited colors and `currentColor` are recomputed without mutating layout inputs.
- Interaction inputs include hover/active/focus flags, hit-test controls and cursors. Their independent storage updates the retained scene without recreating paint inputs or running layout. Cursor inheritance is retained.
- Motion inputs configure transitions. Active paint transitions sample existing boxes; layout-dependent transitions continue to update geometry. The final transition sample is painted before the host returns to event waiting.

`Scene.updateInputs()` replaces the former `refreshPaint()` and `syncInteraction()` traversals. The layout pass builds an index of retained IDs and their layout aliases. Inheritance records actual parent property reads through `parentValue()`. A reverse index maps each parent property to its readers. A batch seeds only changed IDs; effective property changes enqueue their readers in parent-before-child order. Explicit values remove read edges, even when the effective value stays identical; restoring inheritance adds the edges back. Effective values equal to the previous values stop propagation.

Updates stage only reached nodes and replacement edges before committing. Each node owns its current phase strings independently, so replacing a parent's strings cannot invalidate a child. Repeated updates release the old phase pools. There is no tree materialization, geometry copy, scene walk or text measurement on these paint/interaction paths. Layout-generated aliases retain the same ID and update together; suppressed boxes produce no paint work.

Paint transition retargeting uses the changed ID callback rather than scanning scene items. Sampling visits active transition IDs and their inherited readers through the same index, using per-node replacement storage. Completing or cancelling a transition restores the current authored inputs. Geometry transitions still use the full layout path and rebuild the retained index.

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

Core tests assert that a leaf paint, hover, or background-color animation in a scene with 1,000 children evaluates exactly one retained identity, preserving node, scene-item, root-child and tree-entry storage. Other tests cover transitive color/cursor inheritance, explicit-value boundaries, changing read ownership without changing the effective value, simultaneous parent/child updates, repeated animation samples, motion cancellation, phase isolation, scroll stability and retry after allocation failures.

`tests/css-dependencies.mjs` uses Solid signals and compiled normal CSS to generate `modules/ui_core/fixtures/css-dependencies.json`. Nineteen cases exercise multi-property classes, adjacent siblings, inherited font/color, custom properties, equal computed values, text-shadow, cursor, visibility, and text that expands an auto-sized parent and moves later siblings. JavaScript compares each cached snapshot with a cold recomputation. Zig applies the actual phase packets and compares every scene item's effective style, bounds and parent with a fresh scene. Regenerate with `node --conditions=browser --conditions=development tests/css-dependencies.mjs --write`; `pnpm test` checks freshness. Existing CSS, control, native framebuffer and HMR regressions continue to apply.

## Scope and remaining work

The existing painting/compositing renderer is unchanged. A required paint still uses its current offscreen layers and shaders; improving that machinery or replacing it with another renderer is separate work. Hit testing retains its existing scene search. Geometry changes still run the existing complete layout pass, including parents and siblings; there is no fine-grained native geometry dependency graph yet. JavaScript still performs CSS resolution and snapshot preparation on dirty revisions. The retained read graph introduced here covers native paint and interaction inheritance, not Solid's entire reactive graph or selector invalidation.
