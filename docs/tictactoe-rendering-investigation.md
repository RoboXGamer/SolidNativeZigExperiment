# Tic-tac-toe rendering investigation

Measured on the local Windows/Intel laptop, 2026-11-16. These results apply to
the uncommitted tic-tac-toe example and renderer changes in this checkout.

## Reproduction and scope

Run `node tools/profile-tictactoe-hover.mjs`. It builds the real Vite example
with a diagnostic entry, runs it in the optimized QuickJS interpreter in the
native Zig Debug host, and restores the normal tic-tac-toe bundle/executable.
It operates on the 50-node player-versus-player board, with 60 samples per case.
The native window is hidden. This does not move the user's physical cursor.

The measured transaction includes pointer dispatch, computed CSS/snapshot
preparation, phase packet serialization, and acknowledgement. It excludes Zig
tree application, layout, paint, GPU execution, presentation and OS input delay.

The completed run measured tile switching at 285.94 ms median, 351.32 ms p95,
and 379.63 ms maximum. Unchanged collection measured 0.0406 ms median and
0.0473 ms p95. Repeating the same tile target measured 0.6003 ms median and
0.8870 ms p95; its first sample changes from the preceding tile, so its maximum
of 278.68 ms is a real target change, not an unchanged-target measurement.

The first attempt emitted similar timings but exceeded the ordinary smoke
runner's 15-second limit. The profiler now runs the native executable with its
own 180-second process cap and checks normal native completion. The numbers
above are from the successfully completed run.

## Confirmed update work

`dispatchPointer()` updates ancestry flags and increments a global host revision.
`collectChanges()` then calls `snapshot(root)`. `prepareSnapshot()` recursively
visits the tree, calls `computedNodeStyle()` on every node, and creates control,
own-state and subtree fingerprints. Stylesheet matching runs before its cache
key comparison. The bridge then visits the snapshot tree to recover changed
nodes and compares serialized phase projections.

Consequently a small final bridge delta does not imply a small amount of work
to discover it. The measured stage alone can explain visibly delayed hover;
the measurement does not apportion that time between its individual functions.

## Text and paint limitations

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

First replace global change discovery with explicit dirty identities and
selector dependency tracking. State-dependent selectors must invalidate the
right ancestors, descendants and siblings; effective inherited changes must
propagate, and equal computed values must stop propagation. Preserve the
existing correctness fixtures while removing whole-tree fingerprint work.

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
