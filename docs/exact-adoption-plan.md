# Exact ideas for Solid + Zig

Implementation-ready plans and GitHub tracking:

- [Shared clock and driver: one PR, two tasks](plans/clock-driver.md) - tracker [#343](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/343).
- [Windows host: 17 implementation tasks](plans/windows-host.md) - tracker [#346](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/346).
- [Complete issue index and prerequisites](plans/exact-tracking.md).
- [Rune adaptations and acceptance additions](plans/rune-adaptation.md).

The detailed plans refine the exploratory notes below. All work is planned;
no runtime implementation or implementation PR was created during planning.

This records the requested direction: retain Solid as the application programming
model and adopt useful runtime, validation and Windows integration ideas from
Expo's Exact. This is a design/backlog document. No runtime features were
implemented or newly validated while preparing it.

## Inspection baseline

- Local checkout: `1c75169323257fe484ec1bf14218c8c145c11e9f`.
- Exact main observed during research:
  `65a19452362aa883024456673b723239edb47b71`.
- Exact is changing quickly. Module presence describes source organization,
  not complete parity or live Windows qualification.
- Existing local behavior below comes from source inspection and the current
  implementation documents, rather than a fresh application/test run.

## 1. Shared driver

A driver is a stable command interface to an app. A test, a developer and an
agent should use the same operations. Future platform adapters implement the
same protocol against each host. It does not require replacing Solid, adding
Contract, or adopting Exact's runtime.

Exact's [driver](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/scripts/agent.mjs)
provides tree/layout/state/log reads, input, screenshots, resizing, preferences
and clock control. Its targets can use test IDs or labels and ambiguous matches
are reported. These are reference ideas; the proposed protocol below is ours.

### Proposed first protocol

| Operation | Required result |
| --- | --- |
| `tree` | Stable node IDs, element type, accessible role/name, value and state; exclude callback/private application objects. |
| `layout` | Native computed bounds, clipping/visibility, scroll extents and viewport in logical pixels; identify layout aliases. |
| `logs` | Structured warnings/errors with sequence numbers and an application generation. |
| `pointer.move/down/up`, `click` | Resolve a target, use native hit testing and the normal input pipeline, then report the resulting committed generation. |
| `key`, `type` | Use normal focus, editing and keyboard dispatch; distinguish text insertion from key presses. |
| `scroll` | Use the normal scroll chain, with explicit units and pointer/target position. |
| `resize`, `prefer` | Apply a viewport or supported host preference override through normal invalidation. |
| `clock.advance` | Move controlled application time forward and process the intervening scheduled work. |
| `settle` | Drain work runnable at the current app time, with a bounded step limit. Return pending timers/external work instead of waiting indefinitely. |
| `screenshot` | Capture the completed framebuffer for the reported generation and app time. Include framebuffer size and scale. |
| `metrics` | Existing layout/paint/bridge work counters and real-clock timing; keep virtual time separate. |

These are proposed names, not existing commands. Prefer semantic role/name or an
explicit test ID to coordinates. Reject ambiguous and stale targets. A later
`state` operation should expose explicitly registered inspection state only.

Use a versioned request/response envelope and identify the application
generation, committed tree revision and app time. Start with a local development
transport, such as a named pipe or stdio; retain production builds without an
automation endpoint by default.

### Reuse what exists

- `modules/solid_bridge/root.zig`: input, click, key, pointer, viewport, commit and
  job/timer entry points.
- `packages/solid-zig/src/native.js`: retained identities and snapshot/phase
  updates. Its snapshot is not yet an OS accessibility tree or a complete
  computed-layout inspection API.
- `src/windows.zig`: actual hit testing, focus, editing, scrolling, scene layout
  and paint scheduling.
- `tests/fixtures/frame-probe.js` and `tools/test-frame-scheduling.mjs`: existing
  native work-count regressions to preserve and gradually express through the
  driver.

Extract normal input handling into reusable host operations before routing a
driver through them. Calling a JavaScript click handler directly is useful for
a bridge unit test, but does not validate native targeting, occlusion, focus,
disabled controls or pointer-down/up behavior. Keep a separate live OS-input
test layer for message delivery, capture, native dialogs and assistive tools.

### Acceptance target

The same recorded operation sequence can drive the CSS and tic-tac-toe examples
without adding example-specific frame-number branches to `windows.zig`. An
agent can discover a control, activate it, read the result and capture the same
committed frame. A future host reuses the protocol and scenarios.

## 2. Shared, injectable application clock

Currently `quickjs_bridge.c` reads `QueryPerformanceCounter` (or a monotonic
clock elsewhere) for `__nativeNow` and JavaScript timer deadlines.
`src/windows.zig` separately passes `rl.getTime()` to native transitions.
The former is expressed in milliseconds and the latter in seconds. This is
adequate for live execution but provides no single controllable test timeline.

Introduce one host-owned clock with two modes:

- **Live:** derive elapsed application time from a monotonic clock. Existing
  event waiting and OS wakeups continue to schedule real deadlines.
- **Controlled:** time stays fixed until the driver advances it. Real elapsed
  time does not independently fire application timers or advance transitions.

Use a single explicit unit, preferably milliseconds, at the clock boundary.
Convert at native transition APIs that currently expect seconds. Share the
same sampled time across QuickJS and native work in a turn. Real profiling,
watchdog deadlines and OS event delivery retain their own real clock.

### Work that should share application time

1. JavaScript `setTimeout`/`setInterval` and `performance.now()`.
2. Animation-frame timestamps and a defined test frame cadence.
3. Native transition/animation start times and samples.
4. Framework-owned debounce, long-press, repeat, tooltip and caret schedules as
   those features are added. OS-owned controls need separate live validation.
5. An explicit wall-time policy: for controlled runs use a fixed epoch plus
   elapsed app time for date reads. Specify `Date.now()` and zero-argument
   `new Date()` consistently; keep explicit-date construction compatible.

### Advancing correctly

Advance through due deadlines in stable order, rather than setting time to the
final value and firing every callback there. Drain promise jobs and Solid work
between scheduled events, collect and acknowledge bridge updates, and sample
native motion at the defined observation/frame boundaries. Respect timer
cancellation and callbacks that schedule more callbacks. Bound processing to
report endless zero-delay loops or non-settling work.

`settle` only drains currently runnable work. A repeating interval or active
animation does not mean the test must run forever. Long advances may require
many simulated steps; they remove real waiting, not the computation itself.

### Concrete local scenario

`examples/tictactoe/App.jsx` schedules a CPU move after 350 ms. After the player
move, settle its effects and timers, then assert:

```text
clock.advance 349 ms -> CPU has not moved
clock.advance   1 ms -> CPU move runs; settle and inspect the board
```

This is proposed test syntax. It replaces a fragile real sleep with an exact
boundary assertion. Another scenario samples a native transition at 0, 100 and
200 ms while JavaScript timers observe the same timeline.

Exact's [runner](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/runner/src/lib.rs)
is driven by host-supplied time. Its
[time model](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/runner/src/time.rs)
also carries epoch, locale, zone and seed facts. Its live Windows
[timers](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/timers.rs)
and [modal-loop integration](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/modal.rs)
show why controlled runner time and real OS scheduling need distinct policies.

### Limits and additional controls

A virtual clock does not make a live HTTP request finish, simulate Windows IME,
or prove GPU presentation latency. Reproducible scenarios also need fixed data
fixtures/completion order, random seeds, fonts, locale, viewport, DPI and
preferences. Live OS-control timing and physical input remain separate checks.
Keep real elapsed-time performance measurements separate from virtual app time.

## 3. Taffy: adopt its method first, evaluate the dependency separately

[Taffy](https://github.com/DioxusLabs/taffy) is an existing Rust layout library
implementing block, flex and grid algorithms. Given styles, children and
measurement callbacks, it computes geometry. CSS parsing/cascade, text shaping,
painting, widgets, accessibility and the OS event loop remain other layers.

Exact vendors Taffy 0.14.0 and records its divergences in a
[patch inventory](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/vendor/taffy/EXACT-PATCHES.md).
Examples include percentage-padding bases, layout-cache inputs, aspect-ratio
sizing, negative margins and positioned containing blocks. The inventory
distinguishes upstream fixes from Exact-specific changes and records browser
fixtures/regressions and dependency-refresh work.

Its [layout wrapper](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/kernel/src/layout.rs)
derives a Taffy tree from the retained arena, injects host text measurement and
publishes changed geometry back to retained nodes.

For this project:

- Keep the present Zig layout engine while introducing the driver and clock.
- Extend existing frozen Edge/reference geometry cases into repeatable browser
  differentials for the supported layout contract.
- Compare incremental layout against fresh layout for the same mutated tree;
  this catches missing cache/invalidation inputs even when one screenshot looks
  correct. Existing dependency/cold-cache tests are a useful foundation.
- Keep a small ledger connecting each semantic correction to its fixture,
  reference behavior and supported limits.
- Evaluate Taffy later in an isolated, equivalent-layout prototype if reducing
  layout maintenance becomes a priority. A Zig integration would need a Rust
  artifact, C ABI wrapper, node/style mapping and text-measurement callbacks.
  Replacing the engine is a separate decision; no rewrite is authorized here.

## 4. Requested Windows platform backlog

The following names come from Exact's
[Windows host module list](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/lib.rs)
and the corresponding source headers. All are recorded as desired areas for
this project. Priorities below are recommendations, not completed work.

Existing local foundations include DirectWrite shaping/rasterization, logical
and device-pixel separation, font invalidation, persistent cursors, basic
focus/Tab/activation, text clipboard operations, scrolling and timer wakeups.
Those features should be extended and qualified rather than counted as absent.

### First: accessible input and dependable host behavior

| Desired area | Exact source name | Local starting point / intended work |
| --- | --- | --- |
| Windows UI Automation accessibility | `accessibility.rs`, `accessibility/model.rs` | Add semantic role/name/value/state/focus and action routing from retained identities; expose bounds and text/selection. Evaluate direct UIA versus an AccessKit adapter. Exact uses AccessKit. |
| Full IME composition | `ime.rs` | Current text backend positions IMM composition/candidate windows. Add and verify composition/preedit, commit/cancel, selected clauses and key suppression through the normal editing pipeline. |
| System caret integration | `caret.rs` | Extend painted caret/selection with system caret geometry, Windows blink preferences and accessibility interoperability. |
| Keyboard conventions | `keyboard.rs` | Preserve existing Tab/Shift+Tab/Enter/Space/editing; add comprehensive modifier, layout, navigation, shortcut and IME interaction behavior. |
| Native multi-click behavior | `clicks.rs` | Use Windows double-click time/rectangle and define double/triple-click text selection. |
| Wheel and precision scrolling | `wheel.rs` | Replace the fixed `-wheel * 40` policy with settings-aware notches, horizontal/precision deltas and verified scroll chaining. |
| Appearance and settings changes | `appearance.rs` | Connect actual system theme/high contrast, text scale and relevant setting-change notifications; current CSS preferences are partly environment overrides. Include locale/time-zone and resume notifications where needed. |
| Display enumeration and coordinates | `displays.rs` | Build on DPI-aware text/compositor work; expose monitor geometry and conversions, pointer coordinates and multi-monitor changes. |
| Window reachability | `placement.rs` | Keep windows reachable after DPI, monitor and work-area changes; qualify taskbar/work-area boundaries. |
| Live scheduling | `timers.rs` | Preserve the existing waitable-timer wakeup path; define cancellation, stale callback handling, tolerance and deadline behavior around the new clock. |
| Work during native modal loops | `modal.rs` | Define timer/job/frame servicing while resizing, dragging a window, displaying menus or using common file dialogs. |
| Host event-loop integration | `window.rs` | Keep input, settings, accessibility, driver commands and painting coordinated on the owning UI thread. This is an integration area, not a replacement of the entire host by default. |

### Next: normal desktop application features

| Desired area | Exact source name | Intended work |
| --- | --- | --- |
| Native Open/Save dialogs | `file_dialog.rs` | Common item dialogs, filters, cancellation and result delivery. |
| Native editing context menu | `edit_menu.rs` | OS-owned Cut/Copy/Paste/Select All menu with correct enabled states and dismissal. |
| Rich clipboard formats | `clipboard.rs` | Extend existing text copy/cut/paste with declared image/bitmap formats and ownership/lifetime handling. |
| Native tooltips | `tooltip.rs` | OS tooltip behavior with correct placement, delay and dismissal. |
| App/window icons | `icon.rs` | Executable resources plus correctly sized title-bar/taskbar icons. |
| Single-instance activation | `instance.rs` | Forward a later launch's arguments to the running app and focus/show its existing window. |
| External URL opening | `url.rs` | Open links through the user's registered handler; keep incoming deep-link routing a separate feature. |
| Tray/status icon | `tray.rs` | Notification-area icon, activation, menu, lifetime and accessibility. |
| Taskbar jump lists | `jump_list.rs` | App shortcuts/tasks that activate the proper location in the app. |
| Desktop services | `desktop.rs` | Global hotkeys, attention requests and an explicit opt-in launch-at-login API. Implementing support does not enable any of them on this machine. |

### Later or application-driven

| Desired area | Exact source name | Intended work |
| --- | --- | --- |
| Touch and pen | `touch.rs` | Contact IDs, capture/cancellation, coordinates and mouse-event deduplication. |
| Convertible orientation | `orientation.rs` | Opt-in orientation preference where Windows/device support applies. |
| Gamepad input | `pads.rs`, `pad_poll.rs` | XInput mapping, connection state and deliberate polling/wakeup policy. |
| Screen capture API | `screen_capture.rs` | User-requested display/window capture; distinct from capturing our framebuffer for regression tests. |
| Live frame diagnostics | `probe.rs` | Opt-in event/frame observations with causes and real timing. |

Source entry points for the first three areas:
[accessibility](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/accessibility.rs),
[IME](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/ime.rs),
[caret](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/caret.rs).

Use a shared semantic model for driver discovery and accessibility, while
keeping their actions and validation distinct. Driver success cannot establish
Narrator/UIA interoperability. Native file dialogs, IME, DPI changes and shell
integration each require live Windows checks in addition to model regressions.

## Recommended implementation order

1. Shared live/controlled clock; preserve current event waiting.
2. Common native input operations and a versioned local driver; migrate one
   tic-tac-toe timer scenario and one transition/frame scenario.
3. Semantic accessibility model and UIA adapter, coupled with keyboard, IME and
   system-caret work.
4. Settings-aware wheel/appearance and display/window/modal-loop behavior.
5. Native file dialogs, edit menus, icons, activation, URL and clipboard APIs.
6. Tray, jump lists, hotkeys and optional device/capture integrations as real
   application needs demand.

Taffy evaluation can proceed separately after the layout conformance contract
and comparable fixtures are defined. Keep Solid, the phase-aware bridge and
backend-independent core throughout this sequence.
