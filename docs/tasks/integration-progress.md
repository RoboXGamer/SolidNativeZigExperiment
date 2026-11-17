# Integration checkpoint

## Historical validation output

Raw terminal captures were removed during repository cleanup. The filenames below are historical provenance labels, not links to current files. Their useful results are summarized here and in the batch notes below. These checks were not rerun during cleanup and do not establish the current build status.

- Batch 2 and batch 4 JavaScript suites passed. Batch 3 initially failed, then its rerun passed. Both batch 12 test captures ended with exit code 1; integration alone does not imply those tests passed.
- Batch 4 through 7 and batch 9 through 11 records report successful JavaScript, native framebuffer, build and desktop smoke validation. Smoke runs completed with 19 scene items. Empty build captures contained no standalone evidence; build success claims below come from the existing checkpoint notes.
- Final JavaScript and native framebuffer captures ended with passing results. Native coverage included conic colors, subtree opacity, rounded clipping and world transforms.
- Early integration builds and the first native test attempt failed. A subsequent native run passed. Early smoke attempts failed to spawn the executable or crashed; smoke-integration-5 completed successfully with 19 scene items.
- Desktop smoke retained the warning: Timer wakeup unavailable; using 60 FPS event polling.
- Setup recorded QuickJS revision 6a9fe9af5ca0bf7c49ae697edef44864272317d1. Both captured UI bundle builds succeeded. Development output recorded window shutdown; it was not a test result.
- Broad regression success does not prove exhaustive CSS conformance. Feature limitations and partial tickets documented below remain applicable to these historical checkpoints.

Original captures remain recoverable from Git history before this cleanup. The audit source manifest describes its original base commit and intentionally retains the historical dev-check filenames and hashes.


All 12 ORIGINAL batches integrated: 8, 1, 12, 3, 2, 4, 5, 6, 7, 9, 10, 11. This does not establish all 120 issue semantics as verified.

Reconciled view transition lifecycle/type tracking, nested and user/input selectors, attr values, unset, media update queries, logical overflow/writing modes, positioning, transforms and transitions. Both native.js copies match. Fixed native viewport intersection, stray transition syntax, Zig ASCII API compatibility and reflection evaluation quotas.

Validation: batch2-test.log and batch4-test.log: pnpm test PASS after each batch. batch4-native.log: pnpm run test:native PASS (eight framebuffer regressions). batch4-build.log: zig build PASS. batch4-smoke.log: pnpm run test:smoke PASS (19 scene items); UI bundle rebuilt.

Limitations: broad regression suites do not prove every CSS behavior. Batch reports retain feature-specific limitations. Five partial tickets remain partial: #296 font-feature-settings, #295 details-content, #294 content-visibility, #291 active-view-transition, and #178. No issue closures or complete CSS conformance claim.

Batch 5: cherry-pick 1f09447 integrates typography wrapping/balance, overflow, orientation, shadows, stroke/fill and underline controls while retaining whitespace, grapheme, zoom, decoration, feature settings and native fixes. C and Zig text style ABI fields share feature_settings then orientation order. Both native.js mirrors match.

Batch 5 validation: batch5-test.log, batch5-native.log, batch5-build.log and batch5-smoke.log all exit_code=0. Native framebuffer suite passed; rebuilt desktop smoke completed with 19 scene items. Timer wakeup fallback warning remains. These regression checks do not establish exhaustive visual CSS conformance.

Batch 6: integrated tables, filter/system colors, target selectors, emphasis and skip-ink decoration while retaining earlier style pipelines and typography. Zig table APIs adapted to current compiler. Validation: batch6-test.log, batch6-native.log, batch6-build.log, batch6-smoke.log pass; smoke reports 19 scene items. Exhaustive visual conformance remains unproven; five partial issues remain partial.


Batch 7: reconciled additive geometry, paint, style and type declarations, SVG length resolution and table sticky traversal. Preserved previous transition, positioning, table, details and selector pipelines; added conditional/state snapshot style handling and slot projection; mirrored native.js. Fixed Zig reserved integer-type identifier in shape interpolation.

Validation: pnpm test, pnpm run test:native, zig build and pnpm run test:smoke passed (batch7-*.log); smoke reports 19 scene items. These are regression checks, not proof of all batch-7 ticket claims. Source limitations: SVG background rasterizer is a white placeholder; non-circle/ellipse SVG shapes use bounding fill; subgrid parsing does not establish inherited tracks; shape-outside is not wired into block layout; startingStyle is serialized without a native transition lifecycle; polygon interpolation returns destination. Custom state style handling does not prove general selector conformance. Original batch report remains historical unverified scope. Five partial tickets #296, #295, #294, #291, #178 remain partial.

Batch 9: resolved scene, renderer, native bridge and type conflicts additively, preserving previous helpers and APIs. Integrated ruby alignment, root line-height context, registered custom properties, var/revert handling, resolution media evaluation and shared :root selector matching. Mirrored UI sources. Validation: pnpm test, pnpm run test:native, zig build, pnpm run test:smoke all passed; batch9-*.log records evidence. Smoke: 19 scene items; timer polling fallback warning remains. These checks do not prove complete CSS conformance. Existing SVG backgrounds, subgrid, shape-outside and starting-style-selector gaps and five partial tickets remain unresolved.

Batch 10: integrated rect/xywh clipping, read-only editing and style states, quotes, Q units, preference queries, popovers and pointer policies while retaining integrated positioning, transforms, typography and media APIs. JS mirrors match. Validation: batch10-test.log, batch10-native.log, batch10-build.log, batch10-smoke.log pass; smoke 19 items. Regression coverage does not prove exhaustive feature conformance. Host preference detection currently uses environment overrides, not Windows accessibility/theme notifications; preference change listeners, nested q child text, full top-layer escape from ancestor contexts and SVG pointer geometry need further conformance validation. Prior SVG background/subgrid/shape-outside/starting-style-selector gaps and partial tickets #296,#295,#294,#291,#178 remain. No issue closures.

Batch 11: completed original cherry-pick, preserving prior positioning, typography, cascade, interaction, selectors and matchMedia object API. Added inset auto flags, path positioning, overflow-wrap, page helpers, placeholder serialization/drawing and overflow media evaluation. Both native.js mirrors match; redundant isInput declaration omitted. Compiler compatibility and duplicate declarations reconciled.

Validation: batch11-test.log (pnpm test), batch11-native.log (pnpm run test:native), batch11-build.log (zig build), batch11-smoke.log (pnpm run test:smoke) all exit 0. Smoke: 19 scene items; timer polling fallback remains. Broad regression checks do not prove all 120 issue semantics. Five partial tickets #296, #295, #294, #291, #178, SVG backgrounds, subgrid, shape-outside, starting-style-selector and batch10 conformance limitations above remain open. Page/path helpers and paint-order require further feature-specific conformance validation. Parent handles next completion milestone.
