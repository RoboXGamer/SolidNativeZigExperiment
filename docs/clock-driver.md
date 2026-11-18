# Shared clock and Windows driver v1

This implements the clock/driver design in `plans/clock-driver.md`, tracked by
#343, #344 and #345. The clock and scheduler are backend-independent Zig. The
current application adapter uses QuickJS, Solid, retained native updates and
Raylib/GLFW on Windows.

## Running

```powershell
pnpm build:ui --example tictactoe
zig build -Ddriver=true
$env:SOLID_NATIVE_PIPE = "solid-native-review"
$env:SOLID_NATIVE_TOKEN = [guid]::NewGuid().ToString("N")
$env:SOLID_NATIVE_CONTROLLED = "1"
```

Start `zig-out/bin/windows.exe` in that environment. From a second terminal with
the same pipe/token variables, run `node tools/driver.mjs tree`. The CLI accepts
a command followed by one JSON argument object, for example:

```powershell
node tools/driver.mjs clock.advance '{"ms":349}'
node tools/driver.mjs screenshot '{"path":"review.png"}'
node tools/driver.mjs close
```

Use the exported `Driver` class from `tools/driver.mjs` for a continuous controller
session (held keys/pointers are released when the CLI disconnects). Tests provide
complete launch/discovery/input/capture examples:

```text
pnpm test:runtime
pnpm test:driver
node tools/test-clock-driver.mjs --release
pnpm test:frames:native
```

Ordinary `zig build`, including ReleaseSafe/portable builds, does not link the
pipe adapter, allocate its controller/cache state, start a driver thread or
enable VM allocation/log probes. Runtime mode is chosen before evaluating the
application; controlled mode requires the explicit driver build and environment
flag. No runtime mode switch or backward seek is provided.

Driver builds can load a bounded (32 MiB) application bundle from the startup
`SOLID_NATIVE_DRIVER_SOURCE` path. The integrated test runner uses that setting
to exercise multiple examples with one host binary. `SOLID_NATIVE_DRIVER_HIDDEN`
keeps automated input/idle checks isolated from desktop events. Both settings
are compiled out of ordinary builds; visible driver runs use the embedded app
when neither is set.

## Clock and event ordering

- App time uses integer nanoseconds in `[0, 9007199254740991]` (about 104 days).
  Commands take finite nonnegative millisecond durations, rounded up to the next
  nanosecond. Overflow fails before changing time. JS reads milliseconds; native
  transitions receive seconds from the same sample. Real monotonic/CPU clocks
  remain separate for profiling and watchdogs.
- Controlled stepping visits the earliest deadline or active-motion frame before
  reaching the requested final time. Each callback drains its microtasks/Solid
  work, then the host applies and acknowledges native patches. This is a defined
  host ordering, not a browser event-loop conformance claim.
- Equal deadlines preserve insertion order. Timers at a frame boundary precede
  that boundary's rAF batch. A timer created inside the batch follows the batch;
  rAF requested inside a callback belongs to the next frame. Cancellation of a
  later member of a batch is effective. Frame times derive from the rational
  60-Hz frame index, without accumulating rounded frame durations.
- Controlled intervals repeat from their previous deadline. Live intervals
  coalesce missed periods and rearm from the current turn sample. Live due work
  shares its turn sample until drained. The live waitable timer only wakes the
  UI thread; generation and deadline checks reject stale deliveries.
- Timers accept callable callbacks and up to 64 arguments. Delay coercion uses
  JS numeric conversion. NaN, negatives and negative infinity become zero;
  positive infinity/oversized delays clamp to 2147483647 ms. Intervals have a
  1-ms minimum. Capacity/deadline/ID exhaustion throws a RangeError; string
  callbacks are rejected. Cancellation accepts exact, finite positive handles.
- `performance.now()` uses app time. Controlled `Date.now()`, `new Date()` and
  calling `Date()` use epoch 1700000000000 ms plus app time. Explicit arguments,
  parsing, Date prototype/constructor identity and subclass construction remain
  native Date operations. Locale/time zone are those of the machine.
- `settle`/zero advance run work due now, never future timers. Commands stop at
  10000 turns or a 10-second real watchdog checked between turns. Each JS entry has a 5-second interrupt
  watchdog (a running turn can extend the command bound by at most that amount);
  pending jobs are bounded at 1024 per drain. Reentrant advancement is
  refused. Errors report the last reached time/revisions; previous effects remain
  committed. Arbitrary JS is never rolled back.
  An unrecoverable bridge/job failure emits the last committed receipt before
  the UI thread shuts down the unusable runtime.

The scheduler uses 4096 reusable slots and an indexed binary heap. Numeric IDs
include a monotonically checked slot generation. Cancellation is indexed, ties
are stable, and the timer hot path has no JSON/eval or tree traversal. QuickJS
owns function/argument roots behind these handles, releasing them on completion,
cancellation and shutdown. Component/HMR cleanup retains Solid ownership;
accepted HMR does not clear unrelated timers. Full disposal releases all roots
before destroying QuickJS. Runtime generations and controller sessions reject
old identities.

## Protocol and ownership

The endpoint is a byte-mode Windows local named pipe. Its DACL allows the current
user SID; remote clients are rejected. A startup token authenticates `hello`.
Connection session numbers start from an OS-random nonce and increase; runtime
generation and graph stamps are separate from request IDs.

```json
{"version":1,"id":1,"cmd":"hello","token":"startup token"}
{"version":1,"id":2,"cmd":"click","session":123,"generation":456,"target":{"testId":"entry"}}
```

Subsequent requests include the returned session/generation and increasing safe
integer IDs. The envelope and command fields are strict. Unknown versions,
fields, invalid UTF-8, duplicate object fields, nonfinite/out-of-range geometry,
invalid targets and unsupported operations fail before command mutation.

Frozen v1 limits are 65536 bytes per JSON frame, 256 nodes per page, 16 cached
results, 4096 timer records and 4096 bytes per text insertion. **The pending
command limit is one**, a stricter adaptation of the plan's proposed 32: a worker
owns one framed request, waits for the UI's reply, then admits the next. Pipe
backpressure bounds pipelined writes. Fragments and multiple frames per read are
supported. Oversized framing closes the connection and cleans up held input.
An empty frame is malformed input, distinct from disconnect.

The worker only frames bytes, owns I/O buffers and posts wake events. The UI
thread strictly decodes into owned typed requests, executes QuickJS/tree work,
and produces bounded replies. Request strings are copied, so the worker can
reuse its frame buffer after reply. IDs are reserved before mutation; cached
duplicates return identical receipts, and evicted/uncertain IDs cannot reexecute
a click. Reconnect starts a new session. The Node client never retries uncertain
mutations.

Supported commands are returned by `hello`: tree/layout/logs/metrics, pointer
move/down/up/cancel, click, key down/up, type, scroll, resize, prefer/reset,
clock.advance/settle, screenshot, close, and `surface.expose` for the normal OS
exposure regression. No arbitrary eval/private-store serialization is exposed.
Preferences are color-scheme, contrast and reduced-motion using the native enum
values. Keys supported by this host are Tab, Enter, Escape, Space, arrows,
Home/End, Backspace/Delete, Shift/Control and a/c/x/v. Text insertion is distinct
from physical key actions; it preserves the existing single-line edit policy
(stop at the first line break). IME remains the physical host's existing path;
the driver does not fabricate composition events.

Human and synthetic input produce the same `Input` snapshot. Down focuses and
selects text through native hit testing; up activates the matching pressed
control. Synthetic click uses two normal turns. The common path retains select/
popover handling, transforms/clipping, scroll chaining, caret movement and
pointer reconciliation. Semantic target discovery uses `data-testid`/`testId`,
explicit node identity, or role/name. Ambiguity, disabled and obscured targets
are refused. Tree/layout pages describe the retained native scene projection;
non-layout/hidden authors have no actionable scene target. Fragment aliases keep
the author node ID. Accessible-name fallback reads descendant text on demand.

Pagination cursors bind tree, scene and graph revisions; mutation/resize/motion
requires restarting pagination. Read-only requests do not force layout, motion
advance or painting. Replies include session/runtime/graph/request identity,
app time, tree/scene/layout/paint/submission revisions, framebuffer dimensions,
scale and pending timers/jobs. `screenshot` forces a paint barrier, flushes the
draw batch, performs GPU readback before swap, and exports a PNG plus actual
dimensions/readback identity. Unavailable/minimized surfaces return an error.
Native-ready, submission and GPU readback are observable stages. No receipt
claims physical display presentation or pointer-to-photon latency.

VM callbacks stay on the UI thread. Trace/log capture is bounded and only enabled
in driver builds (32 lines, 1024 bytes per line, dropped count). Native scratch
retention is capped at 1 MiB per turn. The driver cache and transport buffers have
fixed capacity. PNG staging is freed after export. Enabled builds assert that
the tracked native allocations are released at teardown; runtime tests verify
zero remaining VM bytes and callback roots after disposal and inject allocation
failures in registration and every protocol allocation.

## Validation and measurement

Recorded on Windows x64, Zig 0.17.0, pinned QuickJS-NG, Solid 2.0.0, local
OpenGL/Raylib, logical 1280x720 at framebuffer 1600x900 (scale 1.25). Driver tests
use fixed controlled time/epoch, fixture data and preferences. Tic-tac-toe CPU
choice uses the existing deterministic minimax. Fonts, locale and time zone are
the machine's; this is local native proof, not cross-machine reproducibility.

- JS/type/bridge/refresh/CSS/package/example suites pass.
- Native UI-core and actual framebuffer/text regressions pass.
- Runtime suite passes in Debug and ReleaseSafe: deterministic ordering, rAF
  cancellation/batch isolation, interval policies, coercion/Date behavior,
  callback errors/partial progress, interrupts, disposal, capacity/ID boundaries,
  request validation/cache and allocator failures.
- Native driver scenarios exercise CSS and tic-tac-toe through hit testing;
  the CPU move remains pending at 349 ms and commits at 350 ms. A separate
  fixture checks Unicode/quotes/newlines, disabled/ambiguous targets, native
  opacity and JS observations at 0/100/200 ms after idle, interruption/retarget,
  delayed/zero-duration motion, stale pagination/runtime/session, fragmentation,
  pipelining, malformed/oversized frames, replay protection and disconnect cleanup.
- The migrated frame script checks 120 unchanged moves, hover/text ancestry,
  cursor-only updates, layout, timer paint, OS exposure, resize and focus, without
  example-specific branches in the native host. Captured PNG dimensions are
  checked against receipts; the tic-tac-toe capture was visually inspected.

Matched **timer-stage microbenchmark**, ReleaseSafe Zig and QuickJS C `-O2`,
same executable/VM allocator/controlled mode: 200000 schedule/cancel pairs followed
by 10000 schedule/dispatch cycles, concurrency one. The previous JS Map timer
functions are reproduced in an isolated runtime; the other runtime uses the new
Zig scheduler. Timing includes the same host eval/dispatch test loop. Profiling
uses real monotonic time and Windows process CPU time, independently of app time.

| Stage | Real wall ns | Process CPU ns | VM allocations | VM frees | VM live bytes | VM high-water bytes | VM high-water count |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Previous JS Map timers | 468769500 | 468750000 | 3370177 | 3370113 | 105132 | 106774 | 1161 |
| Zig scheduler | 107511400 | 109375000 | 770097 | 770091 | 97842 | 99727 | 1059 |

Allocation/free counts cover the measured stage; live/high-water figures include
VM startup. Both runtimes release all measured bytes at disposal. The scheduler
reserves **180288 native bytes** (no dynamic scheduling allocations); the old Map
does not need that fixed native storage. These are requested VM bytes, excluding
allocator headers/OS rounding. This is a matched scheduling-stage comparison,
not a whole-application speedup or total-memory reduction claim. Do not infer
GPU, DirectWrite, physical input/display or live network performance from it.
This is one local run, with CPU affinity and background system load unpinned;
Windows process CPU counters have finite accounting granularity.

The driver script writes exact command p50/p95/p99, failure counts, native/VM
allocation counters, retained driver storage and idle CPU/wall/turn observations
to `.zig-cache/driver-measurements.json`. Command samples are 50 sequential
`metrics` operations per app; idle samples wait 1200 real ms at unchanged app
time. Counters cover the allocator passed to retained tree/scene/text/renderer/
request/scratch owners, not C/OS/GPU allocations that bypass it. VM probes and
controller/inspection work are included in enabled-build command timings.

Full OS UI Automation, additional hosts, synthetic IME composition, network
settlement, physical presentation qualification and renderer rewrites remain
outside v1. HMR keeps the existing accepted-update boundary; there is no rollback
of arbitrary effects, clock rewind, animation seek or serialization of private
component state.

The checked-in [measurement snapshot](clock-driver-measurements.json) pins the
measured source commits and contains complete Debug/ReleaseSafe command,
allocation and idle counters. Release driver samples precede the final cursor/
fatal-job follow-ups; those follow-ups passed the Debug native driver suite.
The ordinary ReleaseSafe gate also passed a normal visible launch and close
with no endpoint despite supplying driver environment variables.
