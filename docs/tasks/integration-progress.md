# Integration checkpoint

Eleven batches integrated: 8, 1, 12, 3, 2, 4, 5, 6, 7, 9, 10. Batch 11 remains a future milestone.

Reconciled view transition lifecycle/type tracking, nested and user/input selectors, attr values, unset, media update queries, logical overflow/writing modes, positioning, transforms and transitions. Both native.js copies match. Fixed native viewport intersection, stray transition syntax, Zig ASCII API compatibility and reflection evaluation quotas.

Validation: batch2-test.log and batch4-test.log: pnpm test PASS after each batch. batch4-native.log: pnpm run test:native PASS (eight framebuffer regressions). batch4-build.log: zig build PASS. batch4-smoke.log: pnpm run test:smoke PASS (19 scene items); UI bundle rebuilt.

Limitations: broad regression suites do not prove every CSS behavior. Batch reports retain feature-specific limitations. Five partial tickets remain partial: #296 font-feature-settings, #295 details-content, #294 content-visibility, #291 active-view-transition, and #178. No issue closure or complete twelve-batch claim.

Batch 5: cherry-pick 1f09447 integrates typography wrapping/balance, overflow, orientation, shadows, stroke/fill and underline controls while retaining whitespace, grapheme, zoom, decoration, feature settings and native fixes. C and Zig text style ABI fields share feature_settings then orientation order. Both native.js mirrors match.

Batch 5 validation: batch5-test.log, batch5-native.log, batch5-build.log and batch5-smoke.log all exit_code=0. Native framebuffer suite passed; rebuilt desktop smoke completed with 19 scene items. Timer wakeup fallback warning remains. These regression checks do not establish exhaustive visual CSS conformance.

Batch 6: integrated tables, filter/system colors, target selectors, emphasis and skip-ink decoration while retaining earlier style pipelines and typography. Zig table APIs adapted to current compiler. Validation: batch6-test.log, batch6-native.log, batch6-build.log, batch6-smoke.log pass; smoke reports 19 scene items. Exhaustive visual conformance remains unproven; five partial issues remain partial.


Batch 7: reconciled additive geometry, paint, style and type declarations, SVG length resolution and table sticky traversal. Preserved previous transition, positioning, table, details and selector pipelines; added conditional/state snapshot style handling and slot projection; mirrored native.js. Fixed Zig reserved integer-type identifier in shape interpolation.

Validation: pnpm test, pnpm run test:native, zig build and pnpm run test:smoke passed (batch7-*.log); smoke reports 19 scene items. These are regression checks, not proof of all batch-7 ticket claims. Source limitations: SVG background rasterizer is a white placeholder; non-circle/ellipse SVG shapes use bounding fill; subgrid parsing does not establish inherited tracks; shape-outside is not wired into block layout; startingStyle is serialized without a native transition lifecycle; polygon interpolation returns destination. Custom state style handling does not prove general selector conformance. Original batch report remains historical unverified scope. Five partial tickets #296, #295, #294, #291, #178 remain partial.

Batch 9: resolved scene, renderer, native bridge and type conflicts additively, preserving previous helpers and APIs. Integrated ruby alignment, root line-height context, registered custom properties, var/revert handling, resolution media evaluation and shared :root selector matching. Mirrored UI sources. Validation: pnpm test, pnpm run test:native, zig build, pnpm run test:smoke all passed; batch9-*.log records evidence. Smoke: 19 scene items; timer polling fallback warning remains. These checks do not prove complete CSS conformance. Existing SVG backgrounds, subgrid, shape-outside and starting-style-selector gaps and five partial tickets remain unresolved.

Batch 10: integrated rect/xywh clipping, read-only editing and style states, quotes, Q units, preference queries, popovers and pointer policies while retaining integrated positioning, transforms, typography and media APIs. JS mirrors match. Validation: batch10-test.log, batch10-native.log, batch10-build.log, batch10-smoke.log pass; smoke 19 items. Regression coverage does not prove exhaustive feature conformance. Host preference detection currently uses environment overrides, not Windows accessibility/theme notifications; preference change listeners, nested q child text, full top-layer escape from ancestor contexts and SVG pointer geometry need further conformance validation. Prior SVG background/subgrid/shape-outside/starting-style-selector gaps and partial tickets #296,#295,#294,#291,#178 remain. No issue closures.
