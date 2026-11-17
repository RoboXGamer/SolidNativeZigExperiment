# Native runtime hardening implementation tracking

The draft planning bundle publishes the Exact plans, HMR audit/evidence and
[Rune adaptations](rune-adaptation.md) together. Runtime implementation remains
tracked by the issues below; publishing this bundle does not complete them.

Rune tracker: [#376](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/376); new tasks:
[allocation/resource budgets #377](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/377),
[compact layout experiment #378](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/378),
[rendering reference #379](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/379), and
[open renderer/text selection #380](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/380).
Existing HMR/clock/driver/UIA/IME issues receive Rune-specific acceptance and
reference additions. Renderer and text backend choices are open, including
retaining the current implementation if it wins a matched comparison.

HMR reliability follow-up: [evidence-backed audit](../audit/hmr-bridge.md) and
[tracker #364](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/364) with 11 scoped fix issues.
This is a separate hardening workstream; it does not expand the one-PR clock/driver scope.

The shared clock and driver are two tasks delivered in **one implementation PR**.
Windows work is split into 17 follow-up task issues grouped by behavior and ownership.
All issues are open/planned; issue creation does not mean implementation or testing
has begun. No implementation PR was opened during planning.

## Plans and parent trackers

| Workstream | Saved implementation plan | GitHub tracker |
| --- | --- | --- |
| Shared clock + driver | [clock-driver.md](clock-driver.md) | [#343](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/343) |
| Windows host | [windows-host.md](windows-host.md) | [#346](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/346) |

## Task index and prerequisites

| Task | GitHub issue | Prerequisites |
| --- | --- | --- |
| CD-1: Add a shared live/controlled clock and deterministic scheduler | [#344](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/344) | Independent; coordinate shared host files |
| CD-2: Add a versioned native app driver with shared input and frame barriers | [#345](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/345) | [#344](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/344) |
| W01: Expose retained UI semantics and actions through UI Automation | [#347](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/347) | [#345](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/345) |
| W02: Implement full IME composition and stable editing-session routing | [#348](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/348) | [#345](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/345) |
| W03: Add system caret integration and accessible text ranges | [#349](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/349) | [#347](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/347), [#348](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/348), [#344](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/344) |
| W04: Complete keyboard focus, modifier and multi-click editing conventions | [#350](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/350) | [#345](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/345) |
| W05: Respect wheel settings and precision/horizontal scrolling | [#351](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/351) | [#345](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/345) |
| W06: Observe system appearance, contrast, text scale and locale changes | [#352](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/352) | Independent; coordinate shared host files |
| W07: Add monitor geometry and keep windows reachable across DPI changes | [#353](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/353) | Independent; coordinate shared host files |
| W08: Preserve scheduled work inside native modal and resize loops | [#354](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/354) | [#344](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/344), [#345](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/345) |
| W09: Add asynchronous native Open and Save file dialogs | [#355](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/355) | [#354](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/354) |
| W10: Add rich clipboard, native edit menus and tooltips | [#356](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/356) | [#345](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/345), [#354](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/354) |
| W11: Add app icons, single-instance activation and URL routing | [#357](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/357) | Independent; coordinate shared host files |
| W12: Add tray icons and accessible status menus | [#358](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/358) | [#357](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/357), [#354](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/354), [#347](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/347) |
| W13: Add jump-list tasks and opt-in desktop services | [#359](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/359) | [#357](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/357) |
| W14: Add touch/pen input and convertible orientation preferences | [#360](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/360) | [#345](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/345) |
| W15: Add XInput gamepad mapping and economical polling | [#361](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/361) | [#344](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/344) |
| W16: Add user-requested screen capture with shared display geometry | [#362](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/362) | [#353](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/353) |
| W17: Add opt-in frame diagnostics with real timing and bounded traces | [#363](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/363) | [#344](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/344), [#345](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/345) |

Both parent trackers contain task checklists and native GitHub sub-issue relationships.
The 22 prerequisite edges are also registered as native GitHub blocked-by relationships.
Child issues include prerequisites, affected/proposed files, scope, edge cases,
allocation/lifetime considerations, acceptance checks and pinned Exact references.

Implementation priority: CD-1 then CD-2 in one PR; accessible input, native
settings/display/scheduling next; desktop controls/activation; optional shell,
hardware and capture capabilities. Independent tasks can start earlier when shared
file ownership is coordinated. Taffy replacement remains a separate evaluation.

Existing related issues remain distinct: #342 painting/compositing, #333 SDK,
#44/#198/#199/#200 CSS preferences, #32 caret-color, #65 cursor and #261 touch-action.
The new Windows issues reference their overlap without changing previous status.

The plans and diagnostic fixtures are versioned in the planning bundle; GitHub
issues link to a published snapshot. Initial Exact/Windows planning was source
inspection only. The separate HMR audit records the executed Node/QuickJS
observations and the native-window/fault scenarios still unvalidated. Rune
was inspected as source, not run or benchmarked against this application.
