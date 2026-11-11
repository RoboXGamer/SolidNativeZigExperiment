<!-- solid-native-css-baseline:2024:box-sizing -->
## Goal

Implement **box-sizing** in the native Solid/Zig style/rendering system for the exact Baseline-through-2024 CSS slice below. This issue tracks WebDX feature ID `box-sizing`; it is not a claim that the feature is already supported or tested.

## Scope and current evidence

- Cutoff: **2024-12-31**, cumulative Baseline newly available, including older features.
- Pinned inventory: `web-features@3.45.0`; **3 eligible CSS compatibility keys**.
- Historical audit status at [`8873c31`](https://github.com/RoboXGamer/SolidNativeZigExperiment/commit/8873c312668b3223789848056abb68aca6e00183): **partial native analogue**. Horizontal block adjustment only; BOX-05.
- Area: **Layout and box sizing**. WebDX groups: `layout`.
- The audit is a source assessment, not an executed conformance result. Reassess newer changes, especially ongoing box/sizing work, before implementing or closing this ticket. A later partial commit is not by itself completion evidence.

## Required work

- [ ] Finish the shared box contract and content-/border-box adjustments across both axes and every supported formatting path (BOX-04/05/06); coordinate with the active box/sizing milestone.
- [ ] Define typed specified/computed/used values and available-space dependencies for this group's keys; preserve zero, auto, percentages and invalid declarations distinctly.
- [ ] Apply the feature in the appropriate block/flex/grid/leaf sizing or box-generation path; propagate final sizes, baselines and overflow instead of adding a transport-only field.
- [ ] Keep one content/padding/border/margin ownership contract and cover nesting, constraints, writing direction and layout-mode interactions.
- [ ] Cover every eligible compatibility key listed below, including its values/contexts. Keep later-than-2024 additions and Chrome-only extras outside this ticket unless explicitly approved.
- [ ] Preserve Solid's official universal renderer and native Zig backend; document any required host services and unavailable dependencies explicitly.

## Foundations and coordination

- Coordinate with [`width-height`](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues?q=is%3Aissue%20in%3Atitle%20%22(width-height)%22).
- Coordinate with [`min-max-width-height`](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues?q=is%3Aissue%20in%3Atitle%20%22(min-max-width-height)%22).
- Coordinate with [`display`](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues?q=is%3Aissue%20in%3Atitle%20%22(display)%22).
- Coordinate with [`logical-properties`](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues?q=is%3Aissue%20in%3Atitle%20%22(logical-properties)%22).

These are related foundation tickets, not a claim that the dependency graph is acyclic or already implemented. Share interfaces/fixtures instead of duplicating style engines. If an eligible key needs a larger semantic subsystem, name it and keep that key open; do not silently drop it. Duplicate/historical WebDX group overlaps need an explicit per-key disposition before either ticket is closed.

## Acceptance criteria

- [ ] Encode exact rectangle/used-size fixtures for the eligible values, zero/auto, conflicting min/max, definite/indefinite containing blocks and nested boxes.
- [ ] Compare supported block/flex/grid cases with the specification and suitable Taffy fixtures; use the frozen browser oracle for behavior Taffy does not own.
- [ ] Record the applicable specification/WPT fixture IDs, the frozen browser/platform/font/DPI context where relevant, and exact expected results for this feature's eligible keys.
- [ ] Verify the real authoring/bridge/native-consumer path and reactive changes/disposal; a field, export, parser-only assertion or demo screenshot alone is insufficient.
- [ ] Update the feature status with implementing commit(s), executed checks and remaining limitations. Never mark source-only fixtures as passed. Respect any active testing pause and distinguish implementation from runtime verification.

## Eligible CSS compatibility keys

This table is the pinned ticket denominator, not a list of tests already passed. The group itself may have later additions; only the individually eligible keys are included.

| Compatibility key | Baseline newly available | Chrome support metadata |
| --- | --- | --- |
| `css.properties.box-sizing` | 2015-07-29 | 10 |
| `css.properties.box-sizing.border-box` | 2015-07-29 | 10 |
| `css.properties.box-sizing.content-box` | 2015-07-29 | 10 |

## References and code entry points

- [Specification](https://drafts.csswg.org/css-sizing-3/#propdef-box-sizing)
- [Pinned feature inventory](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/c4a9b4a3567424a2601af21634e37cc2a2c46631/docs/audit/baseline-2024-css.json)
- [Compatibility audit and named findings](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/c4a9b4a3567424a2601af21634e37cc2a2c46631/docs/compatibility-audit-2026-11-11.md)
- [Scored source-review checklist](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/c4a9b4a3567424a2601af21634e37cc2a2c46631/docs/audit/coverage-checklist.md)
- [modules/ui_core/style.zig:1](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/8873c312668b3223789848056abb68aca6e00183/modules/ui_core/style.zig#L1)
- [modules/ui_core/scene.zig:136](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/8873c312668b3223789848056abb68aca6e00183/modules/ui_core/scene.zig#L136)
- [modules/ui_core/layout_block.zig:19](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/8873c312668b3223789848056abb68aca6e00183/modules/ui_core/layout_block.zig#L19)
- [modules/ui_core/layout_flex.zig:122](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/8873c312668b3223789848056abb68aca6e00183/modules/ui_core/layout_flex.zig#L122)
- [packages/solid-zig/src/native.js:77](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/8873c312668b3223789848056abb68aca6e00183/packages/solid-zig/src/native.js#L77)

Specification links can evolve; use the ticket's pinned key/date boundary and an appropriate historical oracle. Native layout references such as Taffy cover only their own algorithms; they do not certify CSS parsing, text shaping, painting, controls or accessibility.
