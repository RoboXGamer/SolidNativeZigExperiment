<!-- solid-native-css-baseline:2024:selectors -->
## Goal

Implement **Selectors (core)** in the native Solid/Zig style/rendering system for the exact Baseline-through-2024 CSS slice below. This issue tracks WebDX feature ID `selectors`; it is not a claim that the feature is already supported or tested.

## Scope and current evidence

- Cutoff: **2024-12-31**, cumulative Baseline newly available, including older features.
- Pinned inventory: `web-features@3.45.0`; **12 eligible CSS compatibility keys**.
- Historical audit status at [`8873c31`](https://github.com/RoboXGamer/SolidNativeZigExperiment/commit/8873c312668b3223789848056abb68aca6e00183): **missing feature path**. Absent: no complete CSS feature implementation path.
- Area: **Selectors and pseudo-element/state matching**. WebDX groups: `selectors`.
- The audit is a source assessment, not an executed conformance result. Reassess newer changes, especially ongoing box/sizing work, before implementing or closing this ticket. A later partial commit is not by itself completion evidence.

## Required work

- [ ] Implement parsing, matching, specificity and scoping rules for this group's eligible selectors or pseudo-elements.
- [ ] Provide the required semantic attributes/tree relationships/state or generated boxes; the retained renderer tree is not already a DOM/selector engine.
- [ ] Invalidate matches after relevant tree, attribute, interaction or inherited-style changes and route generated output through native layout/paint.
- [ ] Cover every eligible compatibility key listed below, including its values/contexts. Keep later-than-2024 additions and Chrome-only extras outside this ticket unless explicitly approved.
- [ ] Preserve Solid's official universal renderer and native Zig backend; document any required host services and unavailable dependencies explicitly.

## Foundations and coordination

- Coordinate with [`is`](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues?q=is%3Aissue%20in%3Atitle%20%22(is)%22).
- Coordinate with [`not`](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues?q=is%3Aissue%20in%3Atitle%20%22(not)%22).
- Coordinate with [`where`](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues?q=is%3Aissue%20in%3Atitle%20%22(where)%22).

These are related foundation tickets, not a claim that the dependency graph is acyclic or already implemented. Share interfaces/fixtures instead of duplicating style engines. If an eligible key needs a larger semantic subsystem, name it and keep that key open; do not silently drop it. Duplicate/historical WebDX group overlaps need an explicit per-key disposition before either ticket is closed.

## Acceptance criteria

- [ ] Include positive/negative matching, nested scopes, specificity/cascade and dynamic state/tree mutation cases.
- [ ] For generated/pseudo content, verify box creation, painting, hit/accessibility consequences and disposal rather than testing only string matching.
- [ ] Record the applicable specification/WPT fixture IDs, the frozen browser/platform/font/DPI context where relevant, and exact expected results for this feature's eligible keys.
- [ ] Verify the real authoring/bridge/native-consumer path and reactive changes/disposal; a field, export, parser-only assertion or demo screenshot alone is insufficient.
- [ ] Update the feature status with implementing commit(s), executed checks and remaining limitations. Never mark source-only fixtures as passed. Respect any active testing pause and distinguish implementation from runtime verification.

## Eligible CSS compatibility keys

This table is the pinned ticket denominator, not a list of tests already passed. The group itself may have later additions; only the individually eligible keys are included.

| Compatibility key | Baseline newly available | Chrome support metadata |
| --- | --- | --- |
| `css.selectors.attribute` | 2015-07-29 | 1 |
| `css.selectors.child` | 2015-07-29 | 1 |
| `css.selectors.class` | 2015-07-29 | 1 |
| `css.selectors.descendant` | 2015-07-29 | 1 |
| `css.selectors.id` | 2015-07-29 | 1 |
| `css.selectors.list` | 2015-07-29 | 1 |
| `css.selectors.next-sibling` | 2015-07-29 | 1 |
| `css.selectors.subsequent-sibling` | 2015-07-29 | 1 |
| `css.selectors.type` | 2015-07-29 | 1 |
| `css.selectors.type.namespaces` | 2015-07-29 | 1 |
| `css.selectors.universal` | 2015-07-29 | 1 |
| `css.selectors.universal.namespaces` | 2015-07-29 | 1 |

## References and code entry points

- [Specification](https://drafts.csswg.org/selectors-4/)
- [Pinned feature inventory](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/c4a9b4a3567424a2601af21634e37cc2a2c46631/docs/audit/baseline-2024-css.json)
- [Compatibility audit and named findings](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/c4a9b4a3567424a2601af21634e37cc2a2c46631/docs/compatibility-audit-2026-11-11.md)
- [Scored source-review checklist](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/c4a9b4a3567424a2601af21634e37cc2a2c46631/docs/audit/coverage-checklist.md)
- [packages/solid-zig/src/renderer.js:5](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/8873c312668b3223789848056abb68aca6e00183/packages/solid-zig/src/renderer.js#L5)
- [packages/solid-zig/src/native.js:194](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/8873c312668b3223789848056abb68aca6e00183/packages/solid-zig/src/native.js#L194)
- [modules/ui_core/tree.zig:4](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/8873c312668b3223789848056abb68aca6e00183/modules/ui_core/tree.zig#L4)
- [modules/ui_core/style.zig:1](https://github.com/RoboXGamer/SolidNativeZigExperiment/blob/8873c312668b3223789848056abb68aca6e00183/modules/ui_core/style.zig#L1)

Specification links can evolve; use the ticket's pinned key/date boundary and an appropriate historical oracle. Native layout references such as Taffy cover only their own algorithms; they do not certify CSS parsing, text shaping, painting, controls or accessibility.
