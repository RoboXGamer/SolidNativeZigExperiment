# HMR and bridge reliability audit

Baseline: `1c75169323257fe484ec1bf14218c8c145c11e9f` on local `master`.
Node `v26.13.0`, pnpm `12.15.0`, Zig `0.17.0`,
Solid `2.0.0-rc.21`, Vite `8.3.7`.
This audit creates evidence and issues; it makes no runtime fixes.
All earlier local planning documents remain untouched except for a navigation link.

## GitHub tracking

Parent tracker: [#364](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/364).

| Finding | Fix issue | Prerequisites |
| --- | --- | --- |
| H01: Recover failed HMR updates without poisoned module caches or false-success retries | [#369](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/369) | [#367](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/367), [#366](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/366) |
| H02: Make module cleanup exception-safe, async-aware and generation-owned | [#367](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/367) | Independent / coordinate shared files |
| H03: Restore full native API parity and canonical runtime identities in dev HMR | [#365](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/365) | Independent / coordinate shared files |
| H04: Keep CSS cascade order and stylesheet ownership correct across HMR and reset | [#372](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/372) | [#367](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/367) |
| H05: Honor invalidation, full-reload and entry changes as explicit lifecycle operations | [#373](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/373) | [#367](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/367) |
| H06: Replace the unversioned HMR file mailbox with reliable session and revision delivery | [#371](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/371) | Independent / coordinate shared files |
| H07: Recover Vite disconnects and make bootstrap/native-host restart boundaries explicit | [#374](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/374) | [#371](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/371) |
| H08: Build consistent HMR graph generations with bounded compilation and shutdown | [#375](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/375) | [#371](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/371) |
| H09: Make native bridge acknowledgement and scene publication failure-consistent | [#370](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/370) | Independent / coordinate shared files |
| H10: Surface QuickJS promise failures and bound HMR execution with structured diagnostics | [#366](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/366) | Independent / coordinate shared files |
| H11: Gate HMR with isolated end-to-end failure and lifecycle regressions | [#368](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/368) | Independent / coordinate shared files |

## Assessment

The current path has material reliability gaps despite successful simple edits.
There is no measured stability percentage. Ten focused Node reproductions
demonstrate loader/Solid/CSS defects, and one real QuickJS C-bridge fixture
demonstrates a silent unhandled rejection. Five additional areas below are
source-confirmed implementation/coverage gaps; their Windows fault/stress
scenarios have not been executed here.

Ordinary component-local signal reset during Solid component replacement is
documented behavior, not counted as a bug. Computed dynamic import paths,
top-level-await modules, DOM/Node APIs and native host edits requiring restart
are documented support limits; implementing every unsupported feature is not
a prerequisite for this hardening work. The restart boundary still needs
explicit detection/status and recovery rather than silent stale operation.

## Pipeline inspected

`Vite update -> recursive HTTP graph transform -> Babel CommonJS factories ->
shared src/ui-hmr file -> Windows directory notification -> QuickJS evaluation ->
module cache/accept/dispose -> Solid host mutations -> JS phased packet ->
native Tree.applyChanges -> JS acknowledge -> Scene update/layout -> paint`.

A successful file publication currently proves neither VM application nor scene
publication. Recovery and version identity must cover the whole chain.

## Executed evidence

- `node tests/module_host.mjs`: passes (small happy-path module graph probe).
- `node --conditions=browser --conditions=development tests/refresh_probe.mjs`:
  passes (synthetic Solid Refresh/universal renderer probe).
- `node --conditions=browser --conditions=development tools/audit-hmr.mjs --output docs/audit/hmr-bridge-results.json`:
  10/10 current defect scenarios reproduced.
- Real C harness linked the current `modules/solid_bridge/quickjs_bridge.c`
  and pinned local QuickJS-NG sources with `zig cc -O2`. A rejected promise
  produced only `AUDIT_VM_RESULT init=1 tick=1`, exit 0, and no rejection report.
- No live user dev graph, example source or generated UI bundle was rewritten.
  CSS probe fixtures were created in an owned temporary directory and removed.
- No native window, directory-watcher race, multi-session stress, full app build
  or framebuffer/physical input validation was performed.

Evidence files:
[Node observations](hmr-bridge-results.json),
[QuickJS observations](hmr-bridge-quickjs-results.json),
[Node diagnostic](../../tools/audit-hmr.mjs),
[C fixture](../../tests/fixtures/hmr-rejection-audit.c).

The diagnostic asserts the existing bad behavior to document it. Its exit 0
means the observations reproduced, not that HMR passed acceptance. Each issue
requires replacing those checks with corrected invariant-based regressions.

To reproduce the C observation, compile the fixture plus
`modules/solid_bridge/quickjs_bridge.c` and QuickJS's
`cutils.c dtoa.c libregexp.c libunicode.c quickjs.c`, using
`-O2 -D_GNU_SOURCE -DWIN32_LEAN_AND_MEAN -I vendor/quickjs`, into an owned
temporary executable with Zig 0.17. Run it and capture stdout/stderr.
The fixture is intentionally separate from Raylib/GLFW/window delivery.

## Finding index

| ID | Priority | Evidence | Finding |
| --- | --- | --- | --- |
| H01 | P1 | Focused Node reproduction | Recover failed HMR updates without poisoned module caches or false-success retries |
| H02 | P1 | Focused Node reproduction | Make module cleanup exception-safe, async-aware and generation-owned |
| H03 | P1 | Focused Node reproduction | Restore full native API parity and canonical runtime identities in dev HMR |
| H04 | P1 | Focused Node reproduction | Keep CSS cascade order and stylesheet ownership correct across HMR and reset |
| H05 | P1 | Focused Node reproduction | Honor invalidation, full-reload and entry changes as explicit lifecycle operations |
| H06 | P1 | Source / coverage inspection | Replace the unversioned HMR file mailbox with reliable session and revision delivery |
| H07 | P1 | Source / coverage inspection | Recover Vite disconnects and make bootstrap/native-host restart boundaries explicit |
| H08 | P2 | Source / coverage inspection | Build consistent HMR graph generations with bounded compilation and shutdown |
| H09 | P1 | Source / coverage inspection | Make native bridge acknowledgement and scene publication failure-consistent |
| H10 | P1 | Real QuickJS fixture | Surface QuickJS promise failures and bound HMR execution with structured diagnostics |
| H11 | P1 | Source / coverage inspection | Gate HMR with isolated end-to-end failure and lifecycle regressions |

## Recovery principles

1. Use one generation identity from source compilation to native application.
   Keep published, VM-applied, tree-accepted, scene-ready and presented status
   separate. Carry session/runtime compatibility too.
2. Keep the last successfully applied graph independently of candidate hashes.
   Any failure must leave an explicit retry/recovery state, never a success
   caused merely by matching the already-written factory source.
3. Arbitrary JS side effects cannot be rolled back by restoring a Map. Prepare
   what can be prepared, prevent publication of failed generations, then use a
   documented clean remount/VM restart when a live graph cannot safely recover.
4. Do not simply move `acknowledge()` after layout. Tree commits already retire
   node storage. Stage ownership across scene construction or recover with a
   valid independent full snapshot and unambiguous receipts.
5. Treat callback/listener/timer/stylesheet ownership as lifecycle state.
   Cleanup must continue after errors, have bounded async semantics and invalidate
   stale work without cancelling unrelated accepted-HMR application work.
6. Avoid success logs before async acceptance/VM/native outcome. Keep errors
   attributable to module, update, phase and real source location.
7. Measure repeated-edit retained memory and actual end-to-end applied latency.
   Preserve phase-aware incremental rendering; broad full snapshots or VM
   restarts may be explicit recovery paths, not the normal edit path.

## Relation to existing plans

Clock/scheduler #344 and driver #345 are coordination points for generation
metadata, timer ownership, bounded jobs and inspection. They are not prerequisites
for fixing existing recovery/API/CSS defects. This audit adds HMR hardening tasks
instead of inflating the previously agreed single clock/driver PR.

#342 remains painting/compositing optimization, #333 remains SDK packaging, and
#363 remains optional frame diagnostics. HMR recovery/native commit correctness
and mandatory error reporting have their own acceptance here.

## Implementation order

- Start immediately: actual-host API parity (H03), diagnostics (H10), exception-
  safe lifecycle (H02) and regression capture (H11).
- Recovery correctness: H01 after H02/H10; native ownership/publication H09.
- Graph lifecycle and delivery: H04/H05 and versioned mailbox H06; reconnect/
  restart H07 and consistent bounded compiler H08.
- Validate integrated bad-edit -> correction, async failure, source deletion/
  recreation, CSS reorder, full reload, restart and long edit bursts through
  real Vite + watcher + QuickJS + native scene. Check leak/handle/idle behavior.

## Findings and issue specifications

### H01 (P1): Recover failed HMR updates without poisoned module caches or false-success retries

GitHub issue: [#369](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/369).

**Evidence:** Node reproduction R01: an accept callback throws after the new module has changed live state; reapplying identical code returns without rerunning that callback.

**Source:**

- [packages/solid-zig/src/module-runtime.js:63](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/1c75169323257fe484ec1bf14218c8c145c11e9f/packages/solid-zig/src/module-runtime.js#L63-L118)
- [src/windows.zig:620](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/1c75169323257fe484ec1bf14218c8c145c11e9f/src/windows.zig#L620-L625)

**Fix scope:**

- [ ] Define prepared/applying/applied/failed/recovering generations. Keep the last successfully applied graph independently of a published candidate.
- [ ] Do not promote candidate source hashes/cache entries as successfully applied before evaluation and acceptance settle. Retry must not silently no-op after failure.
- [ ] On irreversible factory/accept side effects, perform an explicit clean remount/runtime recovery from a known-good graph or require a visible controlled restart. Suspend invalid input/publication while recovering.

**Edge cases:**

- Throwing factories, accept callbacks, component render/effects and failure during recovery itself; multiple changed modules with earlier successful side effects.
- Identical retry, corrected edit, another edit arriving during failure, failed initial load and accepted versus full-reload behavior. Arbitrary application side effects cannot be promised rollback.

**Acceptance:**

- [ ] R01 becomes a regression asserting either successful reapplication or explicit recovery/failure, never false applied status.
- [ ] A bad edit followed by its correction restores a usable app without killing the native window; last-good/fresh-start policy is explicit and all VM/tree revisions match.
- [ ] Record recovery reason, failed generation and reset state; UI work from a failed candidate cannot later publish.

**Owned files:** `packages/solid-zig/src/module-runtime.js`, `modules/solid_bridge/quickjs_bridge.c`, `src/windows.zig`, `tools/dev.mjs`.

**Prerequisites:** [#367](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/367), [#366](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/366).

**Related existing work:** #343, #344, #345.


### H02 (P1): Make module cleanup exception-safe, async-aware and generation-owned

GitHub issue: [#367](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/367).

**Evidence:** Node R02 loses a valid update after a disposer throws; R03 retains a listener from a failed factory; R04 skips remaining cleanup on reset; R05 emits afterUpdate before async acceptance finishes.

**Source:**

- [packages/solid-zig/src/module-runtime.js:18](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/1c75169323257fe484ec1bf14218c8c145c11e9f/packages/solid-zig/src/module-runtime.js#L18-L59)
- [packages/solid-zig/src/module-runtime.js:87](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/1c75169323257fe484ec1bf14218c8c145c11e9f/packages/solid-zig/src/module-runtime.js#L87-L118)
- [packages/solid-zig/src/native.js:2477](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/1c75169323257fe484ec1bf14218c8c145c11e9f/packages/solid-zig/src/native.js#L2477-L2493)

**Fix scope:**

- [ ] Release listeners and remaining owned resources in finally-style cleanup even if one disposer/pruner throws; aggregate errors without abandoning teardown.
- [ ] Release registrations made by a factory that throws before its record becomes live. Make reset/dispose idempotent and guard recursive disposal.
- [ ] Specify and implement bounded async accept/dispose/prune settlement or explicitly reject unsupported promises. afterUpdate/applied must follow that policy.
- [ ] Associate module/app async work with update/owner generations; disposal invalidates stale callbacks and releases owned registrations. Coordinate timer ownership with #344.

**Edge cases:**

- Several failing cleanups, cleanup registering more hooks, recursive uiDispose/host.dispose, rejected or never-resolving callbacks and module deletion.
- Late promise/timer/listener completion after replacement, full restart versus accepted HMR, cancellation/disposal during a pending update.

**Acceptance:**

- [ ] R02-R05 convert into passing cleanup/retry/settlement regressions; failed records leave no active listeners.
- [ ] Repeated create/update/fail/prune/dispose cycles release module data, callback roots and listeners with bounded retained memory.
- [ ] Existing Solid component cleanup/state semantics remain intact; cleanup errors are visible with module/update identity.

**Owned files:** `packages/solid-zig/src/module-runtime.js`, `packages/solid-zig/src/native.js`, `modules/solid_bridge/quickjs_bridge.c`.

**Prerequisites:** none; coordinate shared file ownership.

**Related existing work:** #344.


### H03 (P1): Restore full native API parity and canonical runtime identities in dev HMR

GitHub issue: [#365](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/365).

**Evidence:** Node R10 uses the actual mountApp-created module host: native.findById is a public function but require('native-host').findById is undefined. tests/css-dev.mjs supplies the full native namespace and therefore hides this production/dev mismatch.

**Source:**

- [packages/solid-zig/src/native.js:2283](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/1c75169323257fe484ec1bf14218c8c145c11e9f/packages/solid-zig/src/native.js#L2283-L2292)
- [tools/dev.mjs:22](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/1c75169323257fe484ec1bf14218c8c145c11e9f/tools/dev.mjs#L22-L31)
- [tests/css-dev.mjs:42](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/1c75169323257fe484ec1bf14218c8c145c11e9f/tests/css-dev.mjs#L42-L47)

**Fix scope:**

- [ ] Expose the complete supported @zig-ui/solid API through one canonical host namespace; avoid maintaining a three-function hand-written subset.
- [ ] Centralize package/external identity resolution for the app graph and embedded Solid/Refresh/renderer internals; diagnose unsupported subpaths instead of accidentally duplicating owner/context state.
- [ ] Run dev parity tests using the exact external table and bootstrap used in QuickJS, not a more capable Node-only substitute.

**Edge cases:**

- Public APIs added later, package aliases and pnpm/unoptimized/optimized paths, direct internal imports, lazy imports and runtime/refresh version mismatch.
- Component/context/owner identity across bootstrap and module graph, and intentional native-host restart boundaries.

**Acceptance:**

- [ ] R10 becomes a parity regression covering the supported public export set and a real dev app importing findById plus other native APIs.
- [ ] A component/context/cleanup smoke proves a single Solid/renderer identity across cold boot and HMR.
- [ ] Unsupported imports fail with actionable module/path diagnostics before publication.

**Owned files:** `packages/solid-zig/src/native.js`, `packages/solid-zig/src/module-runtime.js`, `tools/dev.mjs`, `vite.config.mjs`, `tests/css-dev.mjs`.

**Prerequisites:** none; coordinate shared file ownership.

**Related existing work:** #333.


### H04 (P1): Keep CSS cascade order and stylesheet ownership correct across HMR and reset

GitHub issue: [#372](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/372).

**Evidence:** Node R08: A then B yields blue; hot-reordering imports to B then A remains blue, while fresh-loading the same graph yields red. R09: CSS module styles remain registered after host.dispose().

**Source:**

- [tools/vite-native-css.mjs:24](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/1c75169323257fe484ec1bf14218c8c145c11e9f/tools/vite-native-css.mjs#L24-L38)
- [packages/solid-zig/src/stylesheets.js:12](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/1c75169323257fe484ec1bf14218c8c145c11e9f/packages/solid-zig/src/stylesheets.js#L12-L80)
- [packages/solid-zig/src/module-runtime.js:57](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/1c75169323257fe484ec1bf14218c8c145c11e9f/packages/solid-zig/src/module-runtime.js#L57-L59)

**Fix scope:**

- [ ] Track stylesheet order from the current import/module graph rather than Map insertion history and cached side-effect execution.
- [ ] Define reference/ownership scopes for shared and lazy CSS; release sheets on graph retirement/full reset without removing sheets still owned by live modules.
- [ ] Bound and retire CSS dependency-watch metadata, including errors/removal and asset/import changes.

**Edge cases:**

- Import reorder, nested @import, shared sheet in multiple branches, lazy load/unload, duplicate imports, removed/re-added files and failed CSS updates.
- Layers/specificity/important ties, conditional branches and full runtime remount versus CSS-only state-preserving update.

**Acceptance:**

- [ ] R08 hot-versus-fresh cascade equality and R09 owned-sheet cleanup become regressions.
- [ ] CSS-only edits preserve valid component state; deleting/reordering/importing the same styles reaches the same computed result as a fresh app.
- [ ] Repeated CSS graph churn does not retain orphan rules/watch entries.

**Owned files:** `tools/vite-native-css.mjs`, `packages/solid-zig/src/stylesheets.js`, `packages/solid-zig/src/module-runtime.js`, `packages/solid-zig/src/native.js`.

**Prerequisites:** [#367](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/367).


### H05 (P1): Honor invalidation, full-reload and entry changes as explicit lifecycle operations

GitHub issue: [#373](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/373).

**Evidence:** Node R06: hot.invalidate outside apply waits for another publication; R07: switching entry while definitions stay present leaves both entry owners live. The publisher also collapses update and full-reload into the same apply call.

**Source:**

- [packages/solid-zig/src/module-runtime.js:9](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/1c75169323257fe484ec1bf14218c8c145c11e9f/packages/solid-zig/src/module-runtime.js#L9-L42)
- [packages/solid-zig/src/module-runtime.js:87](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/1c75169323257fe484ec1bf14218c8c145c11e9f/packages/solid-zig/src/module-runtime.js#L87-L118)
- [tools/dev.mjs:100](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/1c75169323257fe484ec1bf14218c8c145c11e9f/tools/dev.mjs#L100-L105)

**Fix scope:**

- [ ] Schedule invalidation immediately through a host wake/callback with the original reason, including invalidation outside an apply callback.
- [ ] Carry update/full-reload/entry-change intent in the protocol and implement their distinct owner/state reset semantics.
- [ ] Retire old entry ownership and invalidate stale work exactly once; preserve state only for supported accepted boundaries.

**Edge cases:**

- Deferred invalidation, repeated invalidate, invalidation during update/recovery, unchanged full-reload payload and entry removal/switch.
- Recursive reset/dispose, stylesheet/owner cleanup and late acceptance callbacks from the replaced generation.

**Acceptance:**

- [ ] R06/R07 become immediate invalidation and single-live-entry regressions.
- [ ] An unchanged full-reload request performs the documented reset; CSS-only ordinary updates do not force unnecessary app remount.
- [ ] No extra edit is needed to recover an invalidated boundary.

**Owned files:** `packages/solid-zig/src/module-runtime.js`, `packages/solid-zig/src/native.js`, `tools/dev.mjs`, `src/windows.zig`.

**Prerequisites:** [#367](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/367).

**Related existing work:** #344, #345.


### H06 (P1): Replace the unversioned HMR file mailbox with reliable session and revision delivery

GitHub issue: [#371](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/371).

**Evidence:** Source-confirmed: every process writes src/ui-hmr.tmp and src/ui-hmr.js; the payload has no session/revision/compatibility envelope or native receipt. ui_watch_changed clears the event before ui_reload attempts to read/apply; read failures have no retry without another event. Watch overflow/error has no rescan/health recovery.

**Source:**

- [tools/dev.mjs:86](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/1c75169323257fe484ec1bf14218c8c145c11e9f/tools/dev.mjs#L86-L90)
- [src/hmr_watcher.c:13](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/1c75169323257fe484ec1bf14218c8c145c11e9f/src/hmr_watcher.c#L13-L39)
- [src/hmr_watcher.c:41](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/1c75169323257fe484ec1bf14218c8c145c11e9f/src/hmr_watcher.c#L41-L62)
- [modules/solid_bridge/quickjs_bridge.c:147](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/1c75169323257fe484ec1bf14218c8c145c11e9f/modules/solid_bridge/quickjs_bridge.c#L147-L166)

**Fix scope:**

- [ ] Use session-owned publication paths/transport with example/entry, runtime/bridge compatibility, monotonic graph revision and payload validation.
- [ ] Distinguish compiled/published/read/applied/native-committed receipts; reconcile latest applied revision at startup and after missed notifications.
- [ ] Implement bounded read/replace retries, watcher overflow/error rescan and health reporting; never consume the only signal on a transient failure.
- [ ] Prevent two dev sessions from sharing a mailbox or applying a stale graph from another example/run.

**Edge cases:**

- Reader/rename sharing races, partial/truncated file, zero-byte overflow, rapid saves, stale file at startup, producer/native restart and two ports/examples.
- Duplicate/out-of-order delivery, shutdown while a read/write is pending, failed apply and process crash before acknowledgement.

**Acceptance:**

- [ ] An isolated two-session stress test proves no cross-session graph application.
- [ ] Injected missed events/read/rename failures recover the latest valid revision without another user edit; duplicates are idempotent.
- [ ] Source-confirmed risks are exercised on a real Windows watcher/QuickJS host and limits/statuses are documented.

**Owned files:** `tools/dev.mjs`, `src/hmr_watcher.c`, `modules/solid_bridge/quickjs_bridge.c`, `modules/solid_bridge/root.zig`, `src/windows.zig`.

**Prerequisites:** none; coordinate shared file ownership.

**Related existing work:** #345.


### H07 (P1): Recover Vite disconnects and make bootstrap/native-host restart boundaries explicit

GitHub issue: [#374](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/374).

**Evidence:** Source-confirmed: tools/dev.mjs creates one WebSocket with an error log but no close/reconnect/resync path. Native/renderer/config edits require restart per README, yet compatibility and restart-needed state are not negotiated. Startup executes the app-containing IIFE before loading the dev graph, so module-scope effects require explicit double-evaluation audit.

**Source:**

- [tools/dev.mjs:95](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/1c75169323257fe484ec1bf14218c8c145c11e9f/tools/dev.mjs#L95-L129)
- [src/windows.zig:501](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/1c75169323257fe484ec1bf14218c8c145c11e9f/src/windows.zig#L501-L526)
- [tools/run-example.mjs:1](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/1c75169323257fe484ec1bf14218c8c145c11e9f/tools/run-example.mjs#L1-L8)
- [README.md:23](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/1c75169323257fe484ec1bf14218c8c145c11e9f/README.md#L23-L27)

**Fix scope:**

- [ ] Reconnect with bounded backoff, refreshed endpoint/token, version handshake and full revision resync after Vite restart; show disconnected/restarting status.
- [ ] Classify application edits versus embedded host/renderer/runtime/config changes, and orchestrate or explicitly request the required bootstrap/native restart.
- [ ] Separate loader bootstrap from application side effects or otherwise guarantee one app/module initialization per intended generation.

**Edge cases:**

- Config-triggered restart, startup connection failure, token change, server/native dies first, two-terminal mismatched examples and stop during reconnect/build.
- Module-scope timers/listeners/stores duplicated at cold dev startup; component-local state reset remains an intentional documented policy.

**Acceptance:**

- [ ] Restart Vite/config/native side while editing and regain a working synchronized app without restarting unrelated sessions.
- [ ] Host edits cannot report a successful hot application while continuing to use an incompatible embedded host.
- [ ] Count cold-start module side effects and active owners through the actual bootstrap and first graph, proving intended exactly-once behavior.

**Owned files:** `tools/dev.mjs`, `tools/run-example.mjs`, `tools/native-process.mjs`, `vite.config.mjs`, `packages/solid-zig/src/native.js`, `src/windows.zig`.

**Prerequisites:** [#371](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/371).

**Related existing work:** #333.


### H08 (P2): Build consistent HMR graph generations with bounded compilation and shutdown

GitHub issue: [#375](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/375).

**Evidence:** Source-confirmed: compileGraph fetches live transformed modules recursively without a generation consistency check; each update enqueues another whole-graph compile. Fetches have no abort/timeout and stop waits on pending. Change bursts or a hung transform can delay current edits or shutdown indefinitely.

**Source:**

- [tools/dev.mjs:33](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/1c75169323257fe484ec1bf14218c8c145c11e9f/tools/dev.mjs#L33-L85)
- [tools/dev.mjs:92](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/1c75169323257fe484ec1bf14218c8c145c11e9f/tools/dev.mjs#L92-L114)

**Fix scope:**

- [ ] Stamp compilation with source/change generation; discard/recompile a graph if its dependency transforms span an invalidated generation.
- [ ] Coalesce queued changes into the latest complete graph while preserving lifecycle/removal semantics and user-visible failures.
- [ ] Bound transform/fetch/compile time and queue/memory use, abort owned work on shutdown, and release CSS/import dependency bookkeeping.
- [ ] Centralize canonical module IDs/query handling and report unsupported syntax/imports with real source location.

**Edge cases:**

- Changes/add/delete/rename during recursive fetch, CSS asset edits, diamond/cyclic graphs, literal lazy dependencies and transform errors.
- Save storms, hung HTTP/transform, stop during write/publish and corrected source after an earlier compile error.

**Acceptance:**

- [ ] A deterministic race harness proves no mixed-generation graph is published and corrected/latest edits are not stuck behind obsolete queue work.
- [ ] Injected hanging transform shuts down within a documented real deadline and owned resources close.
- [ ] Measure graph work, peak queue/retained bytes and end-to-end edit-to-applied latency under matched conditions.

**Owned files:** `tools/dev.mjs`, `tools/vite-native-css.mjs`, `tools/example-entry.mjs`.

**Prerequisites:** [#371](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/371).


### H09 (P1): Make native bridge acknowledgement and scene publication failure-consistent

GitHub issue: [#370](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/370).

**Evidence:** Source-confirmed: synchronize applies Tree changes and acknowledges JS at windows.zig:448-453, before buildScene/updateInputs at 756-778. A scene/update failure breaks the window loop. Tree mutation may already free old node arenas, so moving acknowledge alone does not restore a valid prior scene.

**Source:**

- [src/windows.zig:448](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/1c75169323257fe484ec1bf14218c8c145c11e9f/src/windows.zig#L448-L453)
- [src/windows.zig:748](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/1c75169323257fe484ec1bf14218c8c145c11e9f/src/windows.zig#L748-L778)
- [modules/ui_core/tree.zig:62](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/1c75169323257fe484ec1bf14218c8c145c11e9f/modules/ui_core/tree.zig#L62-L104)
- [packages/solid-zig/src/native.js:2455](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/1c75169323257fe484ec1bf14218c8c145c11e9f/packages/solid-zig/src/native.js#L2455-L2471)

**Fix scope:**

- [ ] Define batch/runtime identity and separate accepted-tree, layout-ready and presented revisions.
- [ ] Stage native ownership through scene validation or implement a safe full-snapshot recovery path; keep the last published frame/storage valid until replacement succeeds.
- [ ] Acknowledge the exact accepted batch according to the defined boundary, with explicit retry/reject/recovery results. Handle recoverable dev layout/application errors without exiting the app.

**Edge cases:**

- Allocation failure at tree/scene/retained update, malformed patch, invalid root/reference, remount between collection and acknowledgement and corrected edit.
- Old Scene borrowing freed Tree strings, partial paint updates, duplicate/stale batch receipt, focus/scroll/transition state after recovery.

**Acceptance:**

- [ ] Fault injection at each ownership/publication boundary leaves either a valid last-good frame or explicit recoverable status; the app remains correctable.
- [ ] No dangling old-scene storage or incorrect acknowledgement; replay/retry does not corrupt retained revisions.
- [ ] Existing incremental paint-only/no-layout work behavior is preserved with allocator/leak checks.

**Owned files:** `src/windows.zig`, `modules/ui_core/{tree,scene,retained_updates}.zig`, `modules/solid_bridge/{root.zig,quickjs_bridge.c}`, `packages/solid-zig/src/native.js`.

**Prerequisites:** none; coordinate shared file ownership.

**Related existing work:** #343, #345, #342.


### H10 (P1): Surface QuickJS promise failures and bound HMR execution with structured diagnostics

GitHub issue: [#366](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/366).

**Evidence:** Real QuickJS-NG C fixture: Promise.reject(Error('AUDIT_UNHANDLED_REJECTION')) yields only 'AUDIT_VM_RESULT init=1 tick=1', with no rejection report. Source also lacks an interrupt handler, module source identities/maps and structured update/native outcomes.

**Source:**

- [modules/solid_bridge/quickjs_bridge.c:33](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/1c75169323257fe484ec1bf14218c8c145c11e9f/modules/solid_bridge/quickjs_bridge.c#L33-L54)
- [modules/solid_bridge/quickjs_bridge.c:55](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/1c75169323257fe484ec1bf14218c8c145c11e9f/modules/solid_bridge/quickjs_bridge.c#L55-L84)
- [modules/solid_bridge/quickjs_bridge.c:147](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/1c75169323257fe484ec1bf14218c8c145c11e9f/modules/solid_bridge/quickjs_bridge.c#L147-L166)
- [packages/solid-zig/src/module-runtime.js:68](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/1c75169323257fe484ec1bf14218c8c145c11e9f/packages/solid-zig/src/module-runtime.js#L68-L71)
- [tools/dev.mjs:90](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/1c75169323257fe484ec1bf14218c8c145c11e9f/tools/dev.mjs#L90-L107)

**Fix scope:**

- [ ] Install host promise rejection tracking with handled-later lifecycle and route errors into update/runtime status.
- [ ] Attach module ID/source mapping to generated factories and preserve phase, graph revision, request/session and native outcome in diagnostics.
- [ ] Bound synchronous HMR/cleanup/job execution using real-time/step budgets and a QuickJS interrupt strategy; report partial progress and use explicit recovery.
- [ ] Replace boolean success/publication logs with compiled/applied/committed/failed/recovering status; never claim a file write proves application.

**Edge cases:**

- Unhandled versus handled-later rejection, async acceptance failure, exception while reporting another error, endless JS loops and pending jobs at the drain limit.
- Interrupt during candidate apply, timeout during cleanup/recovery, duplicate errors, oversized logs and shutdown.

**Acceptance:**

- [ ] The C fixture becomes a regression asserting the rejection is reported and attributed; a handled-later promise does not remain a false persistent failure.
- [ ] An isolated infinite-loop/update fixture is interrupted within a documented real bound and recovers according to H01.
- [ ] Diagnostics identify module/update/phase and distinguish native application from publication without an always-on trace cost.

**Owned files:** `modules/solid_bridge/{quickjs_bridge.c,root.zig}`, `packages/solid-zig/src/module-runtime.js`, `tools/dev.mjs`, `src/windows.zig`.

**Prerequisites:** none; coordinate shared file ownership.

**Related existing work:** #344, #345, #363.


### H11 (P1): Gate HMR with isolated end-to-end failure and lifecycle regressions

GitHub issue: [#368](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/368).

**Evidence:** Coverage inspection: tests/module_host.mjs is not invoked by package scripts; test:refresh covers a synthetic refresh host only. test:css:dev supplies full native externals and applies graphs in Node; optional native smoke cold-loads a graph but does not verify an edit across a running QuickJS window. Existing probes all passed while R01-R10 failed.

**Source:**

- [package.json:9](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/1c75169323257fe484ec1bf14218c8c145c11e9f/package.json#L9-L24)
- [tests/module_host.mjs:1](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/1c75169323257fe484ec1bf14218c8c145c11e9f/tests/module_host.mjs#L1-L15)
- [tests/refresh_probe.mjs:1](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/1c75169323257fe484ec1bf14218c8c145c11e9f/tests/refresh_probe.mjs#L1-L42)
- [tests/css-dev.mjs:42](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/1c75169323257fe484ec1bf14218c8c145c11e9f/tests/css-dev.mjs#L42-L100)

**Fix scope:**

- [ ] Convert audit diagnostics into invariant-based regressions as fixes land, add loader tests to the normal gate, and ensure tests use the actual bootstrap/external table.
- [ ] Add real Vite -> publication/watcher -> QuickJS -> bridge/native revision tests across edits, error/correction, delete/readd, CSS, lazy imports and boundaries.
- [ ] Isolate fixture roots, ports, session artifacts and generated bundles; restore on every failure and stop only owned child process trees.
- [ ] Add repeated update/failure/reconnect/disposal stress and retained-memory/root/handle checks, with deterministic scheduling where available.

**Edge cases:**

- Parallel dev/test sessions, crashes/timeouts/SIGINT, tests overwriting a live user's mailbox/source, late child exit and stale artifacts.
- Warm versus cold imports, cycles/diamonds, component cleanup/local-state policy, accept/prune/dispose failures and async jobs.

**Acceptance:**

- [ ] Root gate exercises loader recovery/cleanup/CSS/API parity and the real QuickJS bridge instead of Node-only substitutes.
- [ ] A live native session survives bad-to-good edits; tests assert applied/native revisions and no leaked owners/callbacks/resources.
- [ ] Audit probe success currently means bad behavior reproduced; replaced regressions assert the corrected invariants and do not preserve defects.

**Owned files:** `package.json`, `tests/module_host.mjs`, `tests/refresh_probe.mjs`, `tests/css-dev.mjs`, `tools/audit-hmr.mjs`, `tests/fixtures/hmr-rejection-audit.c`, `tools/native-process.mjs`.

**Prerequisites:** none; coordinate shared file ownership.

**Related existing work:** #344, #345.
