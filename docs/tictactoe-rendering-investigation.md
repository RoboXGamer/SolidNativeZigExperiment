# Tic-tac-toe rendering investigation

Measured on the local Windows/Intel laptop, 2026-11-16. The original investigation
applies to foundation commit `c357d694364e838e6dc02d2feb675af25a5902c7`.
The retained change-discovery implementation and current measurements are
described below and in [change-discovery.md](change-discovery.md).

## Reproduction and scope

Run `node tools/profile-tictactoe-hover.mjs`. It builds the real Vite example
with a diagnostic entry, runs it in the optimized QuickJS interpreter in the
native Zig Debug host, and restores the normal tic-tac-toe bundle/executable.
It operates on the 50-node player-versus-player board, with 60 samples per case.
The native window is hidden. This does not move the user's physical cursor.

The measured transaction includes pointer dispatch, computed CSS/snapshot
preparation, phase packet serialization, and acknowledgement. It excludes Zig
tree application, layout, paint, GPU execution, presentation and OS input delay.

The original pre-fix run measured tile switching at 285.94 ms median, 351.32 ms p95,
and 379.63 ms maximum. Unchanged collection measured 0.0406 ms median and
0.0473 ms p95. Repeating the same tile target measured 0.6003 ms median and
0.8870 ms p95; its first sample changes from the preceding tile, so its maximum
of 278.68 ms is a real target change, not an unchanged-target measurement.

The first attempt emitted similar timings but exceeded the ordinary smoke
runner's 15-second limit. The profiler now runs the native executable with its
own 180-second process cap and checks normal native completion. The numbers
above are from the successfully completed run.

## Matched retained-discovery measurement

The final pair uses the common native host from master `0d8946f` (including
DirectWrite), Zig 0.17.0 Debug, and QuickJS-NG
`6a9fe9af5ca0bf7c49ae697edef44864272317d1` with interpreter C compiled at `-O2`.
The original JavaScript sources at `c357d69` and the retained implementation at
`35da21c` ran consecutively in this worktree, using its own installed dependencies,
generated bundles and executable. Both ran the same 50-node player board and 60
sequential samples per case, with native smoke completion verified.

For the baseline, only `native.js`, `renderer.js`, `stylesheets.js`,
`selectors-user.js`, `selectors-structural.js` and the hover probe were restored
from `c357d69`; the common native host and build options stayed fixed. Afterward,
the implementation sources were restored and the same probe ran again. The
extended probe records work counters outside the timed interval; its timed
dispatch/collection/commit sequence is unchanged.

All values below are milliseconds. Raw results and exact revisions are retained
in [tictactoe-hover-baseline.json](tictactoe-hover-baseline.json) and
[tictactoe-hover-retained.json](tictactoe-hover-retained.json).

| Case | Baseline p50 | Retained p50 | Baseline p95 | Retained p95 | Baseline max | Retained max |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Tile target switch | 63.7014 | 10.1415 | 73.1897 | 11.8345 | 103.4968 | 16.2021 |
| Unchanged collection | 0.0405 | 0.0460 | 0.0473 | 0.0588 | 0.0871 | 0.2956 |
| Repeat same tile, including first target change | 0.1497 | 0.0571 | 0.2340 | 0.0693 | 63.1368 | 10.2338 |

Tile switching is 6.28 times faster at the median in this final pair. Earlier
baseline medians varied from approximately 64 to 299 ms; a successful pair before
integrating master measured 285.67 to 10.01 ms. CPU frequency, affinity and other
system activity were not controlled, so the final comparison uses its fresh
baseline rather than claiming a speedup against the historical 285.94 ms result.
These are JavaScript bridge transaction timings, not physical pointer-to-photon
latency. Native tree application, layout, text rasterization, paint, GPU and
presentation remain outside the timed interval.

Across all 60 target switches, the retained path performs 359 preparation visits,
123 CSS computations, 721 compiled candidate-selector tests, 123 snapshot
computations and 123 bridge identity visits, with zero topology membership visits.
The first switch changes the initially unhovered ancestry; subsequent switches
typically change two tiles and their paths. All 60 unchanged collections perform
zero preparation, CSS, selector, snapshot, bridge and membership work. The
separate scaling regressions cover unrelated trees, selectors and mutations
beyond hover; see [change-discovery.md](change-discovery.md).

## Validation of the integrated checkout

- `pnpm run test`: full bridge, CSS, hover/dependency, Solid lifecycle and all
  three example suites pass, including the new scaling/mutation regressions.
- `zig build test --summary all`: 139/139 core tests pass.
- `zig build test-native --summary all`: native framebuffer regressions pass.
- `node tools/test-frame-scheduling.mjs`: passes 120 unchanged moves,
  cursor-only, paint, layout, timer, exposure, resize and focus checks;
  7 paints / 3 layouts across 130 iterations.
- `node tools/smoke-native.mjs --hover`: immediate entry/text ancestry and native
  invalidation pass (2 paints / 1 layout; entering text skips paint).
- Both native profiling runs complete and restore a normal tictactoe build;
  `node tools/smoke-native.mjs` then passes with 25 menu scene items.

One cold post-merge host build exceeded the frame helper's 120-second compilation
cap. A standalone `zig build --summary all` succeeded and the unmodified frame
helper subsequently passed. Runtime smoke limits were unchanged. Visual testing
with physical pointer input remains with the user.

## Original update work

`dispatchPointer()` updates ancestry flags and increments a global host revision.
`collectChanges()` then calls `snapshot(root)`. `prepareSnapshot()` recursively
visits the tree, calls `computedNodeStyle()` on every node, and creates control,
own-state and subtree fingerprints. Stylesheet matching runs before its cache
key comparison. The bridge then visits the snapshot tree to recover changed
nodes and compares serialized phase projections.

Consequently a small final bridge delta does not imply a small amount of work
to discover it. The measured stage alone can explain visibly delayed hover;
the measurement does not apportion that time between its individual functions.

## Foundation text and paint observations

These observations describe `c357d69`. Master subsequently gained the DirectWrite
font pipeline in PR #340; see [native-text.md](native-text.md) for the current
text backend. The CSS/discovery PR preserves that pipeline and its native tests.

The GDI/Uniscribe backend rounds font height to integer pixels and obtains
integer glyph advances/extents. It rasterizes whole strings into bitmap
textures. Fractional positioning then samples those bitmaps rather than
rerasterizing glyphs for that placement. Window DPI is not an explicit input to
the text cache/rasterization path. These are verified implementation limits;
their individual contribution to the supplied screenshot has not been measured.

Recent fixes preserve alpha coverage, remove unnecessary item/context layers,
cache measured runs and correct split inline-run sizing. A needed paint still
rebuilds paint order, visits the scene and serializes style data to validate
paint texture caches. The renderer does not yet retain per-item drawing commands
and damage regions across frames. Clip/isolation surfaces remain full-window.
Presentation uses GLFW through Raylib with vsync. No pointer-to-photon or GPU
stage timing was captured, so there is no claim that the remaining cost is all
GPU work or that changing vsync would fix it.

## Recommended direction

The JavaScript step is now implemented: renderer mutation identities, indexed
candidate selectors, separate stylesheet/inline-selector dependency channels,
retained snapshots and changed-phase projection replace the original discovery
passes. [change-discovery.md](change-discovery.md) documents supported semantics,
work-count regressions and explicit conservative invalidation boundaries.

For the graphics/text backend, prefer a Skia proof of concept with SkParagraph
and its shaping dependencies, through a small C ABI consumed by Zig. Use the
same text layout result for measuring, glyph drawing and caret geometry. Retain
paint nodes/commands, track old and new effect bounds, and repaint damage with
the intersecting ordered content, including overlap and group effects. Skia's
SkSG scene and invalidation facilities are candidates to evaluate, not an
automatic CSS dependency graph.

ThorVG is also a credible vector backend: its documented smart partial rendering
is specifically a software-backend capability. Its text behavior and GPU damage
path need independent evaluation for this project's requirements. It should not
be selected on the assumption that all backends already provide partial redraw.

Neither library removes the measured JavaScript stall, CSS semantics, event
scheduling or swap/presentation integration. Measure those stages independently
before claiming a renderer migration fixes end-to-end hover latency.

Primary references:
- [Skia text shaping API](https://api.skia.org/classSkShaper.html)
- [SkParagraph interface](https://skia.googlesource.com/skia/+/refs/heads/main/modules/skparagraph/include/Paragraph.h)
- [SkSG invalidation](https://api.skia.org/classsksg_1_1InvalidationController.html)
- [ThorVG smart partial rendering](https://www.thorvg.org/post/thorvg-v1-0-a-new-generation-released)
- [DirectWrite fractional positioning and natural layout](https://learn.microsoft.com/en-us/windows/win32/directwrite/introducing-directwrite)
