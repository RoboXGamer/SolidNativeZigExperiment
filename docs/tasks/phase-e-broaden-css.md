# Phase E implementation and verification â€” 2026-11-12

This supersedes the initial handoff, whose completion claims were not supported
by application build or framebuffer tests. The PR's executable scope is the five
subsystems assigned in the Phase E implementation brief; this is not a claim of
complete Chrome/Baseline compatibility.

## Implemented paths and their owners

- Positioning: `modules/ui_core/scene.zig`. Relative/absolute/fixed/sticky,
  positioned/transformed containing blocks, out-of-flow extraction, percentage
  re-resolution at the actual containing block, fixed subtrees, sticky descendant
  offsets, auto margins and self alignment. Paint order isolates nested stacking
  contexts; transformed input uses the same composed matrices as drawing.
- Grid: `modules/ui_core/layout_grid.zig`. Balanced repeat/minmax parsing,
  named lines/areas, numeric lines/spans, implicit row/column patterns, dense and
  sparse placement, column-flow wrapping, frozen fractional minima, spanning
  contributions, auto-fit collapse, content/item alignment and intrinsic heights.
- Alignment: `layout_flex.zig`, `layout_grid.zig`, and the Solid style adapter.
  Place shorthands, safe/unsafe alignment, physical/logical start/end and RTL.
- Paint: `paint.zig`, `gradient.zig`, `transform.zig`, `src/renderer.zig` and
  `src/shaders`. Cached multi-stop linear/radial/conic backgrounds; parsed shadow
  layers with separable Gaussian blur, spread and inset masks; rounded clipping;
  subtree opacity composition; composed affine transforms for all content.
- Motion: `animation.zig`, `transitions.zig`, and the native event loop. Property
  changes start/retarget numeric, color and transform transitions; layout changes
  move siblings. Delay, duration, cubic-bezier and step timing are evaluated by
  the host. Frame wakeups stop when transitions settle.

## Phase Aâ€“D integration repairs

- Fixed a Zig 0.17 `ArrayList` API error in the multiline painter that core tests
  previously never instantiated. The full application now builds.
- Replaced estimated Windows ascent/descent and separate measure/draw behavior
  with a shared Uniscribe shaping/raster path and font fallback. Native checks
  exercise Latin, Indic and Arabic metrics and shaped glyph texture creation.
- Replaced the small combining-mark list with Unicode 16.0 extended grapheme
  segmentation, checked against the checked-in official GraphemeBreakTest corpus.
- Preserved the author tree while collapsing normal/nowrap scene text so layout
  and paint share whitespace. Fixed empty optional CSS transport, inherited text
  style handling and percentage line-height's font-size basis.
- Fixed focus ordering for positive tabindex and positioned controls, transformed
  pointer caret coordinates, initial click placement, and scrolling along the
  targeted ancestor chain. The native host positions the Windows IME candidate UI.

## Repeatable gates

Run from the project directory on Windows with Zig 0.17.0, Node and pnpm:

```powershell
pnpm run setup
pnpm test
pnpm run build:ui
zig build test
zig build test-native
zig build
pnpm run test:smoke
```

`test-native` creates a hidden real OpenGL window and checks framebuffer pixels
for intermediate gradient stops, radial/conic colors, subtree opacity, rounded
descendant clipping and transformed content. It also exercises native text
shaping. `test:smoke` runs the actual bundled Solid/QuickJS application for three
hidden frames and requires a successful scene/render completion marker.

The new regressions retain the three failures from the PR review: nested stacking
isolation, minmax/fr redistribution and column auto-placement. Existing Aâ€“D suites
remain in the same gate. Manual IME candidate/composition behavior is not certified
by the automated smoke test.

## Compatibility boundary

No full WPT/browser oracle has been run. These regression gates establish their
named cases, not every CSS value/context or 100% CSS Grid/Chrome conformance.
Stylesheets/selectors/cascade, custom properties, query families, subgrid, tables,
ruby, full browser controls/accessibility and the remaining catalog features are
separate compatibility work. The 2024/2025 catalogs and issues remain the source
of that backlog; their historical status labels are not current conformance data.
The older audit's broader Phase E/F roadmap is not completed by one implementation
PR. No Baseline issue is automatically closed by this PR on the strength of
helper tests or a transported property alone.