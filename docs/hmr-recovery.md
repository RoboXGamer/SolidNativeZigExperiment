# HMR recovery and delivery

Implementation for tracker #364 (H01–H11), November 18, 2026. The original
[audit](audit/hmr-bridge.md) remains historical defect evidence.

## Running

`pnpm dev --example counter` creates a unique `.zig-cache/hmr/<session>` directory,
starts Vite, builds a runtime-only bootstrap there and launches the native host.
Application module initialization occurs only when its first graph is received.
For two terminals, start `pnpm dev:ui --example counter`, then run the exact
`pnpm dev:app --session <absolute session.json path>` command it prints.
Different sessions use different ports, mailboxes, bootstraps and Vite caches.

## Boundaries

Each envelope carries protocol 1, session, entry, compatibility hash and a
monotonic graph revision. Foreign sessions/entries/runtimes are rejected;
duplicate/older applied revisions are inert. Publication logs prove only file
publication. The session's `status.json` distinguishes read, VM-applied,
tree-accepted, scene-ready, presented, failed and restart-required states.
Presentation means the host submitted the matching framebuffer; it does not
certify physical monitor scanout. No-change graphs can reuse an existing frame.

Compilation coalesces changes, aborts obsolete fetches and checks the source
generation before publication. Limits: 1,024 modules, 24 MiB transformed source,
32 MiB serialized delivery, 10 seconds per compile and 3 seconds for shutdown.
Shutdown cancels owned work and stops only its native child tree. Publication
rename retries are bounded. The Windows watcher also rescans every 500 ms and
falls back to rescan wakeups if notifications fail. This adds development-only
wakeups; ordinary native builds retain their existing idle scheduling.

WebSocket close reconnects with 100 ms to 3 second backoff, using Vite's current
token and resynchronizing the complete graph. Embedded host, renderer, native
and config edits publish restart-required instead of applying against an
incompatible bootstrap. Restart `pnpm dev` for those changes. A separately
restarted producer creates a new session: restart its matching host with the
new manifest. A producer restart does not transfer ownership of another run.

## Failure and lifecycle policy

Factory/accept failures mark the generation failed, release its module hooks,
listeners, owned timers and stylesheet registrations, and suspend bridge
publication. The next corrected graph cold-remounts in the same native window.
Matching candidate source does not count as applied. Full reload, entry change
and deferred `hot.invalidate()` explicitly retire the old application owner.
Arbitrary external JavaScript side effects are not rolled back.

Accept/dispose/prune/event hooks are synchronous. A returned thenable fails
explicitly and requires a runtime restart, since its future side effects cannot
be cancelled safely. For asynchronous application work use `hot.guard(callback)`
or check `hot.signal.aborted`, and synchronously register cancellation with
`hot.dispose()`. Timers created during factory/hook/guarded-callback execution
are generation owned and cancelled on retirement. Async continuations outside
those scopes must use the explicit guard/cancellation API.

QuickJS tracks up to 64 outstanding unhandled rejections, releases handled-later
roots and reports module/phase/revision context and stacks where available.
Synchronous VM turns have a 5 second real-time interrupt budget and drains have
a 1,024-job budget. Recovery cleanup has its own VM budget. A new dev generation
clears retired rejection roots. Errors remain in diagnostics history.

CSS ownership follows live modules. Disposal removes sheets, disconnected
modules are pruned, and current dependency traversal determines cascade order.
CSS-only updates preserve component state. The dev external table is the actual
native namespace and shares the embedded Solid/Refresh/renderer identities.
Unsupported embedded subpaths fail before publication.

Native frames carry exact batch IDs. Acknowledgement follows successful scene
construction or retained update. Full remount packets replace the entire tree
atomically, including identities retired while JS was failing. The old scene
owns its strings independently; failed tree/scene work can retain that frame.
Scene failure forces a rebuild on the next turn, without exiting a dev window.
Paint-only updates retain their existing phase-specific path.

## Regression gates and evidence

`pnpm test` runs the ordinary JS suites, corrected HMR invariants, real QuickJS
runtime tests and the isolated native integration harness.
`pnpm test:hmr:native` reruns the live harness alone. `pnpm test:css:dev` now uses
that isolated harness rather than rewriting an example or shared mailbox.
`tools/audit-hmr.mjs` now asserts corrected invariants; historical JSON files in
`docs/audit` are unchanged records of the original failures.

Executed Windows evidence during implementation:

- Node regressions: API identity, failed/retried factories and accepts, cleanup
  errors, async-hook rejection, stale guards, invalidate, entry switch, exact
  batch rejection, foreign sessions, CSS hot/fresh order and 200 lifecycle cycles.
- Real QuickJS: rejected and handled-later promises, real-time infinite-loop
  interruption, runaway-job bounds, timer roots and allocator accounting.
- Native core: 136 tests including old-scene storage after tree retirement and
  failed replacement, plus retained-update allocation-failure retries.
- Two live Vite/watcher/QuickJS/native sessions: exactly-once initialization,
  edit isolation, factory failure/correction, delete/recreate, CSS, injected
  scene failure, repeated edits, a save burst with latest-source convergence,
  bounded timer roots/VM storage and normal close.
- Expanded live cases also pass for interrupted factory/correction, unhandled
  rejection/correction, CSS signal-state preservation, literal lazy import,
  WebSocket close/reconnect/full resync and foreign-session packet rejection.
- The original standalone C rejection fixture now asserts reported rejection
  and handled-later release. It runs in the root gate alongside Zig VM tests.

This is bounded regression evidence. Physical input/monitor scanout, exhaustive
filesystem failure injection and an hours-long soak are not established here.

### Delivery acceptance follow-up (#371)

`node tools/test-hmr-delivery-native.mjs` passes against a real driver build.
The driver fixture suppresses directory notifications, leaving the real 500 ms
rescan fallback active. A Windows `FileStream` lock then denies native reads;
after release, the latest graph reaches the presented receipt without another
source edit. A second sharing lock denies rename through all eight publication
attempts. The producer retains/retries that latest edit and applies it after
release, again without another edit. Truncated delivery and duplicate replay
leave the last-good frame and acknowledged revision intact. Fault controls are
compiled only into driver builds; locks touch session-owned files only.

### Restart acceptance follow-up (#374)

`node tools/test-hmr-restarts.mjs` passes actual Vite server replacement and
WebSocket token rotation while saving, then another edit through the replacement
watcher. The adapter binds each new server by lifecycle epoch and refreshes its
connection/token. Runtime fingerprints cover native/bridge/renderer sources and
the selected configuration, excluding generated caches. A fixture config edit
causes a real config-triggered Vite restart and an explicit restart-required
receipt. Graceful producer shutdown and native restart then load the new config
and an edit made while the producer was down. A second session keeps its PID,
identity and app, and still accepts its own edits. An initially throwing graph
also keeps the native window alive and recovers after correction: the host
establishes a valid bootstrap tree/scene before evaluating the dev graph.

### Compiler acceptance follow-up (#375)

`node tools/test-hmr-compiler-native.mjs` pauses the real producer after compiling
dependency A, changes both source dependencies, and checks hashes of every
published graph. Only complete old/new pairs may publish; an obsolete attempt
must be discarded. Native output then converges to the latest pair.

The same fixture runs two measured 12-pair/24-file-write workloads: sequential
save/present turns and a burst converging to its final value. Both use the same
Vite process/cache, three-module graph, Debug host and optimized QuickJS, with
a fresh native VM and one warmup before each workload. The
[recorded acceptance measurements](audit/hmr-compiler-acceptance.json) include
module/source work, active/latest-request high water, candidate/payload UTF-8
bytes, sampled producer heap/RSS, process CPU, native VM storage/roots, wall
time and receipt latency. UTF-8 content bytes do not include JS object/AST
overhead; sampled heap/RSS are separate. A single burst convergence sample is
not twelve per-edit applications or a general latency distribution.

Finally, a fixture Vite plugin enters an unresolved transform promise. The
actual producer is stopped during that request and exits within its 3-second
deadline plus the test's 1-second scheduling allowance; rebinding the same port
proves the listener was released. Measurements are opt-in with
`DRAFT1_HMR_METRICS=1` (or the owned fixture IPC channel); normal dev operation
does not sample process memory/CPU per module. The root `pnpm test` gate now
runs all three delivery/restart/compiler boundary scripts.

Integrated follow-up validation completed November 19, 2026: `pnpm test` and
`zig build test test-native --summary all` pass. Vite's source watcher excludes
all generated `.zig-cache` and `zig-out` directories, including previous HMR
sessions and standalone-module caches. The compiler harness verifies generated
cache churn cannot trigger a publication; fresh CLI startup and all restart
cases are exercised by the full gate. The recorded JSON above is refreshed
from that integrated run.
