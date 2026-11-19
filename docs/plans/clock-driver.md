# Shared clock and native app driver: one implementation PR

Status: core implementation merged in #402; integrated qualification completed.
The runtime contract, frozen v1 limits, commands, validation and measured-stage
boundaries are documented in [../clock-driver.md](../clock-driver.md).
Rune-derived acceptance additions are recorded in [rune-adaptation.md](rune-adaptation.md):
patch-to-frame receipts, explicit motion timing across idle/hitch/retarget cases,
and measured allocation ownership. They extend #344/#345 within the same two-task PR.
Local baseline: `1c75169323257fe484ec1bf14218c8c145c11e9f`.
Exact reference baseline: `65a19452362aa883024456673b723239edb47b71`.
This document records the original implementation plan; current validation is
reported in the runtime document linked above and [integrated acceptance](../clock-driver-acceptance.md).

## GitHub tracking

Parent: [#343](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/343).

- [#344](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/344) - Add a shared live/controlled clock and deterministic scheduler
- [#345](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/345) - Add a versioned native app driver with shared input and frame barriers

## Delivery contract

Implement CD-1 (clock/scheduler) first, then CD-2 (driver/input/inspection), in
one branch and one PR. Keep them as reviewable commits and separate GitHub
task issues. Close the parent only after both tasks and integrated acceptance
pass. The collating draft PR published plans and diagnostic evidence; the
implementation branch now delivers CD-1 and CD-2 together. Review measurements
and qualification boundaries in [../clock-driver.md](../clock-driver.md).

Preserve Solid, the phase-aware acknowledged bridge, retained dirty identities,
existing layout/text/paint behavior and event waiting. Taffy evaluation, new
platform hosts, OS UI Automation and general renderer rewrites are separate.

## What exists and what changes

| Existing code | Change |
| --- | --- |
| `quickjs_bridge.c`: performance-counter `__nativeNow`, JS Map timers, 16-ms timeout rAF, pending-job draining | Inject app time; move numeric scheduling records into Zig and retain JS callback roots behind handles. Add explicit bounded dispatch results. |
| `solid_bridge/root.zig`: tick/input/click/key/pointer/viewport/commit APIs | Typed clock and input/inspection glue with documented C buffer ownership; no direct JSValue ABI in Zig. |
| `windows.zig`: direct Raylib input, separate `rl.getTime()` motion, per-frame smoke branches | Shared native input operations, one turn time sample, driver command service and frame barriers. |
| `event_wakeup.c`: waitable timer worker posts GLFW events | Preserve live wakes; generation-check stale wakes and wake controlled runs for commands without advancing app time. |
| `ui_core/transitions.zig`: caller-supplied seconds | Continue accepting caller time; convert from shared app clock at the host boundary. No QuickJS/Windows dependency in UI core. |
| Existing snapshots, retained revisions and work counters | On-demand paginated inspection; retain normal incremental paths and avoid inspection work during ordinary frames. |

Suggested new files: backend-independent `modules/host_runtime/{clock,scheduler,input,inspection,driver}.zig`,
a small Windows pipe adapter, C QuickJS scheduling shims and `tools/driver.mjs`.
Adapt naming/build helpers to repository conventions at implementation time.
Do not split timer state into competing JS and Zig deadline authorities.

## Clock and scheduler decisions

- Zig owns a monotonic elapsed clock and reusable scheduler records. Use checked
  integer nanoseconds internally with an explicit representable horizon;
  expose finite millisecond values to JS/protocol and seconds to native motion.
- Select live or controlled mode at process/runtime startup. No arbitrary
  live/controlled switching, backward seek or rewind in this PR. Reset by
  creating a new runtime generation.
- Live mode samples the real monotonic source. Controlled mode advances only
  by commands. Keep real profiling and transport/watchdog deadlines independent.
- `performance.now()`, JS timers/rAF and native animation use the app clock.
  Controlled date reads use a fixed epoch plus app elapsed time. Preserve
  explicit Date construction/parsing, Date-as-function behavior and constructors;
  test the shim rather than replacing Date with an incomplete wrapper.
- Zig scheduling records hold callback handles, never JSValue internals. The
  QuickJS callback registry owns callable/argument roots. C shims register,
  invoke and release those roots on the UI thread. Avoid source-string eval for
  clock/timer hot paths.
- Use indexed deadline storage (min-heap plus slot/generation table or equivalent),
  stable insertion sequence for ties and checked ID rollover. Bound records and
  provide explicit errors on limit/allocation failure.
- A controlled advance visits timer deadlines in order, settles each turn and
  then reaches the requested final sample. Native transitions and rAF are sampled
  at defined frame boundaries, not once for every unrelated timer.
- New zero-delay callbacks run in a subsequent task turn after the current
  callback's microtasks/Solid work; they do not recursively invoke inline.
- Retain the host's documented callable-timer contract. Specify JS argument
  coercion, negative/nonfinite delays and oversized delays before implementation;
  normalize with explicit compatibility tests instead of unchecked casts.
- Controlled repeating timers schedule from their previous deadline. Live mode
  retains a documented coalescing/no-retroactive-burst policy for missed periods.
  Keep the existing minimum interval policy explicit and tested.
- Define a rational 60-Hz virtual frame cadence derived from frame index, avoiding
  cumulative rounding drift. Timers due at a boundary run before that frame's
  rAF batch; callbacks in a batch see the same timestamp. Newly requested rAFs
  belong to the next frame; cancellation within a batch must be honored.
- Drain QuickJS microtasks/Solid effects and apply/acknowledge native patches
  between logical task turns. Define and test this host ordering; do not claim
  complete browser event-loop conformance.
- `advance(0)` and `settle` service work due now without moving to future
  timers. Report pending future deadlines and external work. Repeating timers,
  long polls and active animation cannot make settle wait indefinitely.
- On exception/budget exhaustion return the last reached time, last committed
  revisions and structured error. Prior callback effects/commits remain real;
  there is no fictional rollback of arbitrary JavaScript.
- Keep accepted HMR semantics and Solid-owned cleanup. Full runtime disposal
  cancels all handles; component cleanup cancels only owned callbacks. A hot
  component update must not silently clear unrelated app timers.
- Stop/release scheduling state before QuickJS destruction; reject stale queued
  callbacks by runtime generation. Reentrant advancing is refused.
- Enforce step/job/callback and real watchdog bounds. A QuickJS interrupt hook can
  bound runaway JS; transport timeout alone does not make a blocked native call
  safe to destroy from another thread.

## Driver v1 contract

Use a development/test build option and a Windows local named pipe with a
small Node CLI. Compile the server/queue/probes out of ordinary release builds.
Keep transport outside the host-independent command protocol. The driver
operates the current Windows host; later host adapters are deferred.

Wire format: newline-delimited UTF-8 JSON, versioned envelope, numeric increasing
request ID, session token and runtime generation. Responses echo the request ID
and include app time plus tree/layout/paint/presentation revisions where known.
Report capabilities, supported commands/preferences and limits on handshake.
Reject malformed/unknown fields, unknown versions, nonfinite geometry/time and
out-of-range values before mutation.

Proposed initial explicit limits: 64 KiB request/response frame, 32 pending
commands, 256-node inspection page and a bounded recent-result cache. Freeze
these as documented constants during implementation and test their boundaries.
Return continuation cursors tied to the inspected revision; restart pagination
after mutation. Large screenshots return an explicit output file and metadata,
not unbounded base64 JSON.

Commands:
`hello`, `tree`, `layout`, `logs`, `pointer.move/down/up/cancel`, `click`,
`key.down/up`, `type`, `scroll`, `resize`, `prefer/reset`,
`clock.advance`, `settle`, `metrics`, `screenshot`, `close`.
Arbitrary JS evaluation and serialization of private component stores are
outside v1. Add optional inspection state only through explicit app registration.

Transport handles partial frames and multiple frames per read. Its worker owns
I/O buffers, queues owned typed requests, posts a wake, and never enters QuickJS
or mutates the tree. The UI thread owns execution and replies. Pipe access is
limited to the current user and a live session handshake; no TCP listener.

Use one mutating controller session in v1. Duplicate IDs return cached replies;
evicted/uncertain results are explicitly reported and never silently re-execute
a click. Reconnection uses a new session and cannot replay prior mutations.
A disconnect cancels held synthetic inputs and controller-scoped pending work;
it does not erase unrelated application timers.

Resolve targets by author test ID, explicit runtime/node identity or role/name
from a minimal semantic projection. Refuse ambiguity; validate visible/disabled,
clipped, transformed and hit-test state at execution. JS aliases and layout
fragments remain associated with author node identity. Stale runtime IDs and
pagination cursors are rejected. Coordinate input names logical pixels; output
also includes framebuffer dimensions/scale.

Extract host input handling once. Both native Raylib events and the driver
enter the same typed actions. Input text insertion, physical key actions and
IME composition remain distinct. Synthetic click drives down/up, normal focus
and hit testing; it never skips directly to a JS callback. Preserve scroll
chaining, popover/select handling and pointer reconciliation.

A completed command means its effects and runnable work at current app time
have settled to the reported committed revision. A screenshot requests a paint
barrier for that revision and reports actual capture dimensions. Read-only tree/
layout/metrics commands do not force layout or presentation. GPU submission and
physical display presentation are distinct; report only observable evidence.
Handle minimized/zero-size surfaces explicitly.

## Exact lessons and project-specific adaptations

Read the pinned implementations, not only the README:
[deadline stepping](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/runner/src/runner/advance.rs),
[driver operations](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/scripts/agent.mjs),
[input cleanup](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/scripts/agent-keys.mjs),
[transport lifetimes](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/scripts/agent-launch.mjs),
[Windows timers](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/timers.rs).

Borrow deadline-ordered commits, bounded progress, cancellation/epoch checks,
semantic discovery and honest timing/presentation evidence. Our adaptations
target QuickJS + Solid, the existing phased JSON bridge, Raylib event waiting,
and allocator-controlled Zig queues. These are design choices to validate;
we are not claiming flaws in Exact or a performance win from the language alone.
Keep v1 small rather than reproducing its full multi-host framework.

## Ownership and efficiency contract

| Lifetime | Owner / release rule |
| --- | --- |
| Clock and scheduler | Host/runtime allocator; teardown after scheduling stops and before VM destruction. |
| Timer/rAF record | Reusable generation slot; rooted JS callback released exactly once at completion/cancel/disposal. |
| Native request | Queue slot owns parsed strings; release after execution and reply/cancel completion. |
| Turn scratch | Reset after all consumers finish; no request/provider may retain a slice into it. |
| Inspection result | Bounded writer/page; copy only requested fields, no always-on duplicate DOM or entire-tree JSON in input paths. |
| Reply/cache | Bounded per session, owned independently of tree/HMR; retire on disconnect. |
| Screenshot | Explicit request owns staging pixels/file work; release after capture/export. |
| Trace | Optional bounded ring with dropped-record count, off by default. |

Avoid replacing one allocation problem with unbounded capacity retention:
shrink/evict after oversized requests according to documented caps. Use checked
size arithmetic, error cleanup paths and allocation-failure injection. Queued
work retains IDs/owned data, never raw Tree/Scene/QuickJS pointers. Avoid moving
QuickJS callbacks off the UI thread to make I/O easier.

## Integrated acceptance and measurement

1. Tic-tac-toe CPU delay: player input, settle, +349 ms unchanged, +1 ms CPU move.
2. A JS timer and native transition share 0/100/200-ms observations; include
   interruption/retarget, delayed and zero-duration transitions.
3. Same-time/nested timers, rAF batching/cancellation, interval self-cancel,
   exception/partial-progress, disposal, stale wakes and ID wrap boundaries.
4. Driver parse/fragmentation/backpressure/version/duplicate/disconnect tests;
   stale targets, obscured targets, held-input cleanup, Unicode/quotes/newlines.
5. Preserve existing 120 unchanged moves, cursor-only, paint-only, layout,
   exposure, resize, focus and timer work assertions via the shared pipeline.
6. Observe stable repeated runs with fixed app data, random seed, epoch, locale,
   viewport/DPI/fonts and preferences. Do not present fixtures as live-network
   or physical input proof.
7. Run JS/bridge and native suites, UI/native builds and app smoke appropriate
   to implementation. Retain live idle/event-wait and desktop interaction checks.
8. Debug allocator and failure-injection runs cover cycles and teardown. Compare
   identical baseline/new release host/runtime/optimization and workloads.
   Report exact native/QuickJS allocation counts/bytes/high-water and retained
   capacity, real CPU/wall duration, idle wake/paint/layout counts, command
   p50/p95/p99/failures and driver/probe overhead. State measured stages;
   physical pointer-to-photon is outside a JS/CPU transaction measurement.

## CD-1: Add a shared live/controlled clock and deterministic scheduler

GitHub issue: [#344](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/344).

Depends on: none; coordinate shared host file ownership.

### Code ownership

- `modules/solid_bridge/{root.zig,quickjs_bridge.c,build.zig}`
- `src/{windows.zig,event_wakeup.c}`
- `modules/ui_core/transitions.zig`
- `proposed modules/host_runtime/{clock,scheduler}.zig`

### Scope

- [x] Add a host-owned monotonic application clock selected at startup: live or controlled, with checked integer duration storage and explicit ms/seconds conversions.
- [x] Own deadline/rAF scheduling records in Zig; keep callable/argument roots in QuickJS behind opaque handles and C dispatch/release functions. Keep JSValue layout and reference management out of Zig.
- [x] Advance controlled time through deadlines and frame boundaries, stable ordering, microtask/Solid settling and bridge commits. Preserve live waitable-timer wakeups and idle no-paint behavior.
- [x] Route performance.now, timer/rAF timestamps and native motion through the same turn sample; define controlled Date.now/new Date epoch without changing explicit-date semantics.

### Edge cases

- Equal deadlines, nested zero-delay timers, cancellation/self-cancellation, rescheduling, interval catch-up and rAF requested/cancelled inside rAF.
- Negative/NaN/infinite/overflow clock requests, precision/rounding, backward time, zero advance and long advances with bounded step budgets.
- Throwing callbacks, runaway jobs, partial committed progress, reentrant advance, HMR scope disposal/full reload, stale wake events, shutdown and allocation failure.

### Acceptance

- [x] One test advances the existing tic-tac-toe CPU timer by 349 ms then 1 ms and observes the boundary through the real QuickJS/native pipeline.
- [x] Native transition samples and JS timer/rAF timestamps agree at fixed app times; deterministic ordering covers the listed timer cases.
- [x] Live event waiting, zero unchanged-frame work, cancellation/shutdown and existing bridge/frame suites remain valid; leak/failure-injection checks cover timer roots/slots.
- [x] Report real CPU duration and native/QuickJS allocation high-water marks under repeated schedule/cancel/advance, separately from virtual elapsed time.

### Ownership and efficiency

Use reusable scheduler storage with generation-checked handles, indexed cancellation, no per-tick JSON/eval or tree traversal, bounded retention and explicit QuickJS root release. Measure against the same host/runtime/optimization baseline.

### Exact references

- [runner/src/runner/advance.rs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/runner/src/runner/advance.rs)
- [runner/src/runner.rs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/runner/src/runner.rs)
- [runner/src/time.rs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/runner/src/time.rs)
- [host/windows/src/timers.rs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/timers.rs)


## CD-2: Add a versioned native app driver with shared input and frame barriers

GitHub issue: [#345](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/345).

Depends on: [#344](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/344).

### Code ownership

- `src/windows.zig`
- `modules/solid_bridge/{root.zig,quickjs_bridge.c}`
- `packages/solid-zig/src/{native.js,renderer.js}`
- `tools/{native-process.mjs,smoke-native.mjs,test-frame-scheduling.mjs}`
- `proposed modules/host_runtime/{input,inspection,driver}.zig and tools/driver.mjs`

### Scope

- [x] Extract normal native input/focus/scroll operations; route human and synthetic input through those operations with native hit testing and pointer/key state.
- [x] Add a build-gated local named-pipe protocol and CLI. Include handshake/capabilities, tree/layout/logs, pointer/click, key/type, scroll, resize/preference overrides, clock.advance/settle, metrics, screenshot and close.
- [x] Return typed replies with session/runtime generation, request ID, app time, tree/layout/paint revisions and pending work. Define committed versus presented barriers and bounded semantics.
- [x] Add a minimal semantic inspection projection with author test IDs and role/name fallback; reject ambiguity/stale/hidden/disabled targets. Preserve full OS UIA work for the Windows accessibility task.
- [x] Migrate current example-specific native probe scenarios into driver scripts; keep a thin existing command compatibility wrapper where useful.

### Edge cases

- Partial/multiple/oversized/invalid frames, duplicate requests/timeouts/disconnects, bounded queue/backpressure, session mismatch and ABI/protocol version errors.
- HMR or removal/reparenting between lookup and execution, clipped/occluded/transformed targets, select/popover hit areas, focus loss, held-key/pointer cancellation and Unicode text.
- Commands while the app waits idle, screenshots after pending layout/motion, framebuffer versus logical pixels, zero-size/minimized windows and read-only inspection without rendering.
- Clock budget or command failure after earlier commits must report partial progress, not imply rollback; release held inputs on controller disconnect.

### Acceptance

- [x] One CLI script discovers and operates CSS and tic-tac-toe examples through normal native input, captures matching committed frames and observes the 349+1 ms timer boundary.
- [x] Existing no-work/paint-only/layout/hover frame assertions are preserved through the common operations, without game-specific branches in windows.zig.
- [x] Protocol/parser and lifecycle tests cover the listed failure paths; a fresh session/reconnect/reload cannot target an old node or replay an uncertain click.
- [x] Default release builds expose no driver endpoint and incur no driver queue/thread/allocation overhead; explicitly enabled testing builds work without global OS cursor automation.

### Ownership and efficiency

Reuse bounded request/response and inspection buffers; page large trees instead of unbounded full snapshots; retain no borrowed tree/arena pointers across a turn. Keep transport I/O off UI/QuickJS execution and define queue ownership.

### Exact references

- [scripts/agent.mjs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/scripts/agent.mjs)
- [scripts/agent-keys.mjs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/scripts/agent-keys.mjs)
- [scripts/agent-launch.mjs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/scripts/agent-launch.mjs)
- [scripts/agent-inspect.mjs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/scripts/agent-inspect.mjs)
- [kernel/src/lib.rs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/kernel/src/lib.rs)
