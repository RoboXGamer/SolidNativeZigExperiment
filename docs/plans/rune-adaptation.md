# Rune adaptations for Solid + Zig

Status: accepted implementation direction, planned work. This planning bundle
publishes the Exact plans, HMR audit and Rune additions together; it does not
implement the runtime features or close their issues.

Local source baseline: `1c75169323257fe484ec1bf14218c8c145c11e9f`.
Rune reference: `842c28c2ca5dd1506c1e4a67052db61800aed721`. Rune was inspected as source, not run or benchmarked.
Keep Solid JSX/CSS, QuickJS and the retained phase-aware bridge as the application
architecture. Renderer and text choices are open: #342's ThorVG prototype,
the current Raylib/DirectWrite baseline, Rune-inspired techniques and other
justified candidates must be compared before selecting a production backend.
Any change must preserve text/editing correctness and native host behavior.

## Tracking and delivery

Rune tracker: [#376](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/376).
New tasks: allocation budgets [#377](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/377), compact storage [#378](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/378), reference rendering [#379](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/379), and open backend selection [#380](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/380).

Existing tasks carry the overlapping behavior. The shared clock and driver
remain **one implementation PR with two tasks** (#344 and #345, parent #343).
HMR fixes stay in tracker #364. Windows platform integration stays in #346.
The draft PR containing this document collates plans/evidence; subsequent
implementation PRs follow those boundaries.

| Rune lesson | Adaptation owner |
| --- | --- |
| Safe hot-edit compatibility and immutable candidates | #374, #375 |
| Stable owner/state boundary and explicit failed-patch recovery | #367, #369 |
| Patch-to-frame receipts and snapshot provenance | #345, #370, #371 |
| Idle/hitch/retarget frame-clock behavior | #344 |
| Measured allocation/resource budgets | #377 |
| Compact layout storage with a baseline oracle | #378 |
| Generated reference rendering and minimized replay | #379 |
| Open paint/text backend choice and matched decision gate | #380, #342 |

## 1. Classify edits before exposing them to the runtime

Rune's [development launcher](https://github.com/anomalyco/rune/blob/842c28c2ca5dd1506c1e4a67052db61800aed721/scripts/rune-dev)
validates candidate bytes before publishing them to a guarded source mirror.
Its Rust hot-patch compatibility rules are not our JavaScript refresh rules.

For our code:

- Classify CSS-only updates, supported app-module/component refresh, explicit
  graph invalidation/full reload, and native/bootstrap restart.
- Fingerprint native bridge schema/ABI, embedded Solid/Refresh/renderer identities
  and relevant bootstrap configuration. Handshake these with the HMR session.
- Host/renderer/Zig/config incompatibility produces a controlled restart-needed
  result with a reason; it cannot be logged as a successful app hot update.
- Capture immutable candidate module bytes and source-generation metadata.
  Validate all candidates before publication; discard/recompile when dependency
  transforms span a newer invalidation generation.
- App edits allowed by the current JS/Solid contract remain hot-editable. Avoid
  importing Rune's Rust field/type restrictions into dynamic application state.

Acceptance extends #374/#375: ordinary JS/CSS edits preserve the documented
behavior, host/schema/config changes trigger the intended restart, mixed source
generations never publish, and a corrected edit recovers after invalid syntax.

## 2. Keep durable ownership separate from replaceable behavior

Rune's [hot runtime](https://github.com/anomalyco/rune/blob/842c28c2ca5dd1506c1e4a67052db61800aed721/crates/rune/src/hot.rs)
keeps long-lived state outside its patchable tip crate. Certain patched callback
panics fall back to startup code; the implementation does not undo arbitrary
side effects or catch every kind of panic.

For our code:

- Stable stores/owners may survive a compatible component update only under an
  explicit lifecycle policy. Component-local state reset remains documented
  Solid behavior; there is no automatic general store/closure migration.
- Associate subscriptions, hot callbacks, styles, pending work and timers with
  owner/runtime/update generations. Cleanup continues after one callback fails.
- Retire old event closures and reject late writes from disposed owners. Do not
  retain application callbacks in native state beyond their rooted lifetime.
- Keep last-applied definitions separate from candidate hashes. After partial
  execution, report failure and recover with a defined clean remount/VM restart
  when a graph cannot safely resume.
- A new valid edit must work after factory, accept, cleanup or render failure,
  even if its source bytes match a previously failed candidate.
- Do not promise rollback by restoring a module Map. VM restart or rehydration
  must state what state is reset and what explicitly supported state is restored.

Acceptance extends #367/#369: failure/correction sequences leave one live owner
set, no stale handlers/listeners/timers and honest update status. Preserve
last-good native storage/frame until a usable replacement is ready.

## 3. Connect the patch receipt to the captured native frame

Rune's [hot headless path](https://github.com/anomalyco/rune/blob/842c28c2ca5dd1506c1e4a67052db61800aed721/crates/rune/src/hot.rs)
reports patch/request identity, motion/scroll state and GPU-readback time.
That proves more than a source-file write, but readback is still not proof of
physical display presentation.

Our shared metadata should include:

`session -> runtime generation -> graph revision -> request/batch ID ->
tree revision -> scene-ready revision -> paint/submission/readback revision`.

- Give each boundary a typed outcome. Do not acknowledge an unspecified latest
  packet or let a file publication imply native scene success.
- Keep app time separate from real diagnostic timestamps. Return viewport,
  framebuffer dimensions, DPI/scale and whether motion is still in flight.
- A screenshot waits for the requested scene/paint barrier and names the
  revision it contains. A capture during animation may intentionally show an
  intermediate pose; record the pose/time rather than pretending it is settled.
- Treat minimized/unavailable surfaces, readback failure and partial native
  application as explicit outcomes. Never reuse old pixels under a new revision.
- Use opaque IDs/generations instead of exposing raw memory addresses as stable
  identity. Capture/readback is on demand, not per normal frame.

Acceptance extends #345/#370/#371: send edits and input around a patch,
verify request-to-image provenance, reject stale batches/targets, and preserve
the native ownership boundary even if scene construction fails.

## 4. Test frame time around idle gaps, hitches and retargets

Rune's [frame clock](https://github.com/anomalyco/rune/blob/842c28c2ca5dd1506c1e4a67052db61800aed721/crates/rune/src/frame/clock.rs)
and [clock walk tests](https://github.com/anomalyco/rune/blob/842c28c2ca5dd1506c1e4a67052db61800aed721/crates/rune/src/frame/clock_walk_tests.rs)
are references for sharing clock rules across window/headless paths and
distinguishing running motion from motion started on a late frame.

Add to #344:

- Long idle followed by a new transition: the new transition starts at its
  actual start boundary instead of receiving the entire idle gap.
- A late frame advances already-running motion by elapsed app time; motion
  started/retargeted by a slow commit uses the documented start/presentation
  policy, without charging pre-start time.
- Test 0/100/200-ms observations, retarget during a hitch, delay/zero duration,
  pause/manual stepping and timer/rAF deadlines coinciding with native motion.
- Define expected motion for controlled frames independently of real GPU/OS
  presentation. All native and JS observations share the same app-time sample.
- Keep application time forward-only in v1. Rune animation seek is not a model
  for reversing arbitrary Solid state, timers, promises or external side effects.
  Future scrubbing requires reset/replay of controlled state and fixtures.

Preserve existing live event waiting and avoid introducing a high-frequency
polling loop merely to make manual stepping easier.

## 5. Measure allocation budgets and evaluate compact storage

Rune's [allocation tests](https://github.com/anomalyco/rune/blob/842c28c2ca5dd1506c1e4a67052db61800aed721/crates/rune/tests/alloc.rs)
gate selected warm runtime paths and state exclusions such as GPU/driver work.
Its [retained Taffy adapter](https://github.com/anomalyco/rune/blob/842c28c2ca5dd1506c1e4a67052db61800aed721/crates/rune-taffy/src/lib.rs)
uses compact records and flat child storage, with a baseline mode and
[size/equivalence tests](https://github.com/anomalyco/rune/blob/842c28c2ca5dd1506c1e4a67052db61800aed721/crates/rune-taffy/src/tests.rs).

Our adaptation has two separate deliverables:

1. Runtime/VM/resource instrumentation and measured stage budgets.
2. An isolated compact layout-store experiment compared with the existing engine.

Zig gives us allocator and lifetime control. It does not establish a performance
advantage before measurement, and Rune demonstrates explicit memory control in
Rust too. Count native calls/bytes, VM roots/heap and OS/GPU resources separately.
Do not call a selected warm path zero-allocation for the whole app.

Keep existing algorithms/storage as a reference and use identical mutated trees
to establish equivalence. Taffy solver adoption remains an optional independent
evaluation, not part of the clock/driver PR or a prerequisite for memory work.

## 6. Differential rendering with minimized replayable failures

Rune's [reference tests](https://github.com/anomalyco/rune/blob/842c28c2ca5dd1506c1e4a67052db61800aed721/crates/rune-ref/tests/differential.rs)
compare generated CPU/GPU scenes and save failures for replay/minimization.

Our first test-scene contract covers existing primitives with an independent
oracle: rounded/rectangular fills, gradients, ordered alpha/group opacity,
transforms and nested clips. Add effects and text only with explicit measured
tolerances and comparable font/layout/raster conditions.

- Serialize scene, seed, mutations, backend, build, viewport, DPI and blend
  conventions. Retain a small minimized scene plus expected/actual/diff output.
- Compare native output against a slow reference and partial updates against
  fresh full redraws. Catch moved/deleted content and ordered overlap.
- Pixel/channel and localized mismatch bounds are feature-specific; a broad
  whole-image average must not hide a broken clip or alpha seam.
- Keep the test interface backend-neutral so it can validate the current renderer,
  ThorVG and any Rune-inspired or other shortlisted adapter. The reference
  rasterizer is a correctness oracle, not a production choice by default.
- Separate these correctness gates from allocation/CPU/GPU/presentation timing.

## Additional Windows references

The existing #347 accessibility and #348 IME tasks can also study Rune's
[Windows UIA adapter](https://github.com/anomalyco/rune/blob/842c28c2ca5dd1506c1e4a67052db61800aed721/crates/rune/src/a11y/windows.rs)
and [Windows composition/reconversion adapter](https://github.com/anomalyco/rune/blob/842c28c2ca5dd1506c1e4a67052db61800aed721/crates/rune/src/platform/ime/windows.rs).
Use one semantic model for inspection/accessibility while preserving the
distinction between assistive actions and pointer hit testing. Check callback
thread/reentrancy/teardown and UTF-16-to-UTF-8 composition/clause offsets.
Native API/model tests do not replace Narrator/IME/live desktop evidence.

## New task specifications

### [Runtime] Enforce native, QuickJS and retained-resource allocation budgets

GitHub issue: [#377](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/377).

**Scope**

- [ ] Instrument allocator boundaries for native tree/layout/paint/scheduler/driver work; expose QuickJS allocation/root metrics separately and count relevant OS/GPU resources explicitly.
- [ ] Define cold, warm, changed-frame, no-op input, inspection and HMR churn workloads with exact baseline counts/high-water/retained capacity. Introduce stage-specific gates from measured baselines.
- [ ] Assert zero additional allocations for measured no-work/disabled-instrumentation paths where feasible; use bounded documented budgets for actual mutations, shaping, decoding and graph compilation.
- [ ] Add allocation-failure cleanup and repeated schedule/cancel/update/reload/dispose checks; resource counts return to the documented live baseline after retirement.

**Edge cases**

- Warm-up hiding first publication costs, native allocations escaping via C/C++/VM/graphics drivers, thread-local versus total counts and allocator wrapper overhead.
- Oversized text/images/requests retaining excessive capacity, deferred destruction/GPU retirement, error/reconnect/shutdown and counter rollover.

**Acceptance**

- [ ] Report exact calls/bytes/live/peak/retained capacity per measured stage with build/runtime/DPI/load conditions; never label all-runtime zero allocations from a narrow warm path.
- [ ] Matched current/new workloads gate regressions while preserving no-layout/paint-only behavior. Native, QuickJS, OS handles and GPU allocations have explicit coverage/exclusions.
- [ ] Failure injection and repeated HMR cycles show no leaked roots/handles/native arenas; disabled instrumentation adds no logging or buffer-allocation work.

**Code ownership:** `modules/ui_core/{tree,scene,retained_updates,transitions}.zig`, `modules/solid_bridge/{root.zig,quickjs_bridge.c}`, `src/{windows.zig,renderer.zig,text_backend.zig}`, `proposed tools/profile-runtime-memory.mjs and allocator test helpers`.

**Related work:** #344, #345, #342, #363, #367, #368.

**Prerequisite:** none; coordinate shared rendering/runtime files.

**Rune references:**

- [crates/rune/tests/alloc.rs](https://github.com/anomalyco/rune/blob/842c28c2ca5dd1506c1e4a67052db61800aed721/crates/rune/tests/alloc.rs)
- [crates/rune/src/tooling/test_alloc.rs](https://github.com/anomalyco/rune/blob/842c28c2ca5dd1506c1e4a67052db61800aed721/crates/rune/src/tooling/test_alloc.rs)


### [Layout] Evaluate compact retained storage against a layout-equivalent baseline

GitHub issue: [#378](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/378).

**Scope**

- [ ] Measure current node/style/cache/child-edge storage, string ownership and mutation allocation patterns before proposing a representation change.
- [ ] Prototype compact hot records, cold/rare style storage, flat child edges and reusable generation-checked slots behind the existing native API, preserving the current implementation as a baseline.
- [ ] Run identical snapshots and mutation sequences through baseline and candidate; compare geometry, order, inheritance/ownership, clipping/hit-test inputs and retained revisions.
- [ ] Treat Taffy solver reuse as an isolated later evaluation, not a prerequisite or automatic engine replacement.

**Edge cases**

- Removal/reparent, aliased layout fragments, slot reuse/stale IDs, inherited values equal to authored values, structural versus paint-only edits and cache-key invalidation.
- Strings referenced by an older scene, arena teardown, capacity growth/compaction, allocation failure and uncommon complex CSS values.

**Acceptance**

- [ ] Full supported fixture/mutation corpus matches the baseline, including existing browser-reference and hot-versus-fresh checks.
- [ ] Record actual per-node bytes, total/peak/retained memory, allocation counts and update/layout CPU against the same build/workloads.
- [ ] Adopt a candidate only after correctness and measured benefit; no compact record may outlive its owned data or narrow the CSS contract silently.

**Code ownership:** `modules/ui_core/{tree,style,scene,sizing}.zig`, `modules/ui_core/{layout_block,layout_flex,layout_grid,retained_updates}.zig`, `proposed isolated layout storage experiment and benchmark fixtures`.

**Related work:** #344, #342, #370.

**Prerequisite:** [#377](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/377).

**Rune references:**

- [crates/rune-taffy/src/lib.rs](https://github.com/anomalyco/rune/blob/842c28c2ca5dd1506c1e4a67052db61800aed721/crates/rune-taffy/src/lib.rs)
- [crates/rune-taffy/src/store.rs](https://github.com/anomalyco/rune/blob/842c28c2ca5dd1506c1e4a67052db61800aed721/crates/rune-taffy/src/store.rs)
- [crates/rune-taffy/src/tests.rs](https://github.com/anomalyco/rune/blob/842c28c2ca5dd1506c1e4a67052db61800aed721/crates/rune-taffy/src/tests.rs)


### [Rendering] Add generated reference comparisons and minimized scene replay

GitHub issue: [#379](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/379).

**Scope**

- [ ] Define a backend-neutral serialized test scene for a bounded first set: rectangles, gradients, ordered alpha/group opacity, transforms and nested clips; expand coverage only with an explicit oracle.
- [ ] Implement a deliberately simple test-only CPU/reference path or independent analytically checked primitive oracle and compare current native rendered output against it.
- [ ] Generate deterministic scenes, measure per-feature pixel tolerances, shrink failing cases and save small scene/seed/backend/build/DPI artifacts for replay.
- [ ] Add partial-update versus fresh-full-render comparisons for movement/removal/overlap. Make the harness usable by every shortlisted backend, including a ThorVG or Rune-inspired adapter, with the production decision kept open.

**Edge cases**

- Premultiplied versus straight alpha, sRGB versus linear blending, clip edges/antialiasing, degenerate/transformed geometry, transparent pixels and device-scale rounding.
- Blur/shadow support and tolerance limits must be explicit; DirectWrite text compares only with shared font/layout/raster conditions, not assumed cross-rasterizer equality.

**Acceptance**

- [ ] Seeded corpus and saved regressions replay deterministically with reference and native images/diffs; no unbounded tolerance or whole-image average hides local defects.
- [ ] A known intentionally injected pixel/compositing defect is detected and minimized; a partial update equals a fresh full redraw for supported scenes.
- [ ] Record verified backends and exclusions. Preserve the current baseline's correctness while comparing #342 candidates; CPU/reference correctness is not production renderer adoption.

**Code ownership:** `src/{renderer.zig,render_check.zig}`, `modules/ui_core/{paint,gradient,transform}.zig`, `existing native framebuffer tests`, `proposed test-only reference renderer, scene generator and replay CLI`.

**Related work:** #342, #368, #370.

**Prerequisite:** none; coordinate shared rendering/runtime files.

**Rune references:**

- [crates/rune-ref/tests/differential.rs](https://github.com/anomalyco/rune/blob/842c28c2ca5dd1506c1e4a67052db61800aed721/crates/rune-ref/tests/differential.rs)
- [crates/rune-ref/regressions/README.md](https://github.com/anomalyco/rune/blob/842c28c2ca5dd1506c1e4a67052db61800aed721/crates/rune-ref/regressions/README.md)




## 7. Renderer and text selection stays open

The user's clarified objective is the best verified application result, not
commitment to ThorVG or DirectWrite. Treat #342 as an open selection/adoption
umbrella, preserving its prototype and all current rendering/text behavior
as comparison baselines.

| Candidate | Worth evaluating | Evidence limit / integration cost |
| --- | --- | --- |
| Current Raylib + DirectWrite | Existing app, shaped-layout/editor consistency and caches | Current renderer has broad paint/offscreen work; no full alternate-backend comparison. |
| ThorVG software/GL + text bridge | Retained vector engine and an existing isolated prototype | Tested GL version lacks partial GPU redraw; software damage/upload and real host/text integration still need validation. |
| Rune-inspired batched GPU + glyph atlas | Retained-texture damage, batched primitives, glyph reuse and raster settings | Effect/compositor paths can fall back; Rust/wgpu integration or a Zig adaptation has build/ABI/maintenance cost. |
| Direct2D + DirectWrite | Windows hardware 2D/text interoperability | Windows-specific and requires a deliberate host/surface interoperability design. |
| Skia with an appropriate text/platform bridge | General graphics/effects across platforms | Screen build size, toolchain, API/FFI and maintenance cost before admitting it to the full matrix. |

Paint backend, shaping/layout/editing, glyph rasterization and atlas/composition
are separate axes. Rune's Windows glyph code also uses DirectWrite, with
Parley-shaped font bytes and Chromium-oriented raster/gamma/phase choices.
Improvement may mean a hybrid or better glyph caching rather than replacing
DirectWrite wholesale. Our current shaping/caret/selection consistency is a
hard correctness gate for any alternative; variation axes/color emoji and
cross-platform text are requirements to compare, not assumed solved.

Rune's retained-texture damage path can avoid full-window redraw in eligible
cases, but its source has explicit full-redraw fallbacks for effects, backdrop
blur and other presentation conditions. Do not equate source-level damage
support with lower end-to-end latency or lower total GPU/CPU work.

Use the same actual CSS, tic-tac-toe, text-heavy and effect workloads, fonts,
viewport/DPI, GPU, build mode and warm-up for admitted candidates. Separate
native application/layout, preparation/raster, upload, GPU completion and
present stages. Record quality, correctness/failures, cold/warm latency
percentiles, CPU/RAM/VRAM, exact binary/dependency bytes, handle/resource
retention and maintenance/platform cost. Reject non-equivalent comparisons.
Preserving the current backend or choosing a measured hybrid is a valid result.

Sources: [Rune damage](https://github.com/anomalyco/rune/blob/842c28c2ca5dd1506c1e4a67052db61800aed721/crates/rune/src/render/damaged.rs),
[Rune Windows glyph rasterization](https://github.com/anomalyco/rune/blob/842c28c2ca5dd1506c1e4a67052db61800aed721/crates/rune/src/text/windows/direct_write.rs),
[ThorVG prototype](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/ff123da950da4c8d432b7e377d12ea9e8f1e12ac/prototypes/thorvg/README.md),
[Direct2D](https://learn.microsoft.com/en-us/windows/win32/direct2d/direct2d-overview),
[Skia](https://skia.org/docs/).

### [Rendering] Select paint and text backends with matched quality, performance and maintenance evidence

GitHub issue: [#380](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/380).

**Scope**

- [ ] Keep renderer/text selection open: compare the current Raylib + DirectWrite baseline, ThorVG software/GL + suitable text bridge, and a Rune-inspired batched GPU/glyph-atlas path on identical real scenes.
- [ ] Evaluate paint/compositing, text shaping/layout/editing, glyph rasterization/atlas and platform presentation as separate decisions. Rune's Windows glyph path also uses DirectWrite; it is not simply a replacement for it.
- [ ] Screen Direct2D/DirectWrite for a Windows-focused backend and Skia for a cross-platform general graphics option if they address requirements the primary candidates fail. Admit candidates only with explicit build/ABI/dependency and maintenance costs.
- [ ] Preserve the current implementation and isolated ThorVG prototype. Use small adapters behind a common scene interface; do not migrate the app or introduce a production dependency before the decision gate.

**Edge cases**

- Sparse hover versus animation/full updates; mixed DPI; glyph fallback/bidi/Indic/emoji/variable fonts; caret/selection/IME correctness and fractional origins.
- Group opacity, nested clips, transforms, blur/backdrop/shadow halos, resize/occlusion/device loss and damage paths that fall back to full redraw.
- Glyph-atlas eviction/growth, subpixel versus grayscale text on transparent/transformed layers, CPU upload/presentation cost and warm-up masking startup work.

**Acceptance**

- [ ] Run the same CSS/tic-tac-toe/text-heavy/effect scenes, fonts, viewport/DPI, build and physical GPU through shortlisted adapters. Report exact bytes/resource counts/CPU/RAM/VRAM, cold/warm p50/p95/p99/failures and rendering/presentation stages separately.
- [ ] Quality and editing correctness are hard gates. Compare sparse/partial output with full redraw and record unsupported/fallback cases rather than comparing non-equivalent scenes.
- [ ] Document a decision based on application workloads, supported platforms and maintenance cost. Keeping the current backend, a hybrid, or a measured alternative are all acceptable outcomes; no framework/source-only benchmark establishes a winner.

**Code ownership:** `src/{renderer.zig,text_backend.cpp,text_backend.zig,windows.zig}`, `existing native framebuffer/text tests`, `isolated backend adapters/prototypes and reproducible comparison artifacts`.

**Related work:** #342, #377, #379.

**Prerequisite:** runtime allocation/resource instrumentation task.

**Rune references:**

- [crates/rune/src/render.rs](https://github.com/anomalyco/rune/blob/842c28c2ca5dd1506c1e4a67052db61800aed721/crates/rune/src/render.rs)
- [crates/rune/src/render/damaged.rs](https://github.com/anomalyco/rune/blob/842c28c2ca5dd1506c1e4a67052db61800aed721/crates/rune/src/render/damaged.rs)
- [crates/rune/src/text/windows.rs](https://github.com/anomalyco/rune/blob/842c28c2ca5dd1506c1e4a67052db61800aed721/crates/rune/src/text/windows.rs)
- [crates/rune/src/text/windows/direct_write.rs](https://github.com/anomalyco/rune/blob/842c28c2ca5dd1506c1e4a67052db61800aed721/crates/rune/src/text/windows/direct_write.rs)
