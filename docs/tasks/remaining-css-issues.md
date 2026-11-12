# Remaining CSS work after the 12-batch integration

Scope note: this file is a standalone backlog record. It is **not** part of the
12-batch integration PR (#328) and carries no validation claims for any item
listed here.

The 12 original batches integrated into `master` (PR #328) covered 120 distinct
GitHub issues across `#168`–`#308`. **None of those 120 were closed by the
integration** — all 120 remain open. The PR body itself stated "No issue
closures or complete CSS conformance claim."

The earlier version of this file incorrectly listed 21 issues in that range as
"not covered by any batch." Those 21 are in fact already **closed** by earlier
merged work (PRs #314 and #315 plus Phase E / box-model work) and are not
remaining work.

What remains open from this integration:

1. **5 issues whose batch implementation landed but is documented as partial.**
2. **#144 (Lab and LCH) and #41 (color())** — open, marked
   `partial-unverified` by the earlier css-subsystem batch (#314).
3. **146 other open issues below `#168`** from the original 2024 Baseline
   catalog that were never part of the 12 batches.

All 26 issues are still OPEN on `RoboXGamer/SolidNativeZigExperiment`. None of
them were implemented, and none were validated.

---

## Group 1 — Correction: the 21 "uncovered" issues are already closed

Note: a earlier pass of this file listed 21 issues inside `#168`–`#308` that
appeared to fall outside the 12 batch scopes. That was wrong. Those 21 issues
are in fact **already CLOSED** on GitHub — they were implemented and closed by
earlier merged work, not by the 12-batch integration:

- 10 of them (#169, #179, #212, #215, #232, #233, #267, #289, #293, #297)
  were closed by PR #314 (`feat/css-small-batch`) via "Fixes #N".
- 4 of them (#180, #181, #241, #285) were closed by PR #315
  (`feat/css-app-essentials`).
- The remaining 7 (#183, #184, #186, #245, #275, #276, #280) were closed by
  earlier Phase E / box-model-sizing work.

They are **not** remaining work and should not be re-opened. They are listed
here only so the earlier incorrect "remaining 21" list is corrected.

The 120 issues that **were** covered by the 12 batches are all still **OPEN**
after the integration PR #328 — none were closed. The PR body itself stated
"No issue closures or complete CSS conformance claim."

---

## Group 2 — Partial implementations carried over from the batches (5 issues)

These landed inside a batch scope but the batch report and the integration
checkpoint both record them as **partial**, not complete.

| Issue | Title | Feature key | Batch | Partial status as documented |
|---|---|---|---|---|
| #296 | font-feature-settings | `font-feature-settings` | batch 2 | Native plumbing exists; full CSS font-feature-settings behaviour not established. |
| #295 | ::details-content | `details-content` | batch 2 | Pseudo-element is serialised, but the full `::details-content` lifecycle is not established. |
| #294 | content-visibility | `content-visibility` | batch 2 | Containment behaviour is not established end to end. |
| #291 | Active view transition | `active-view-transition` | batch 2 | Active transition entry is not wired to a native transition lifecycle. |
| #178 | Oklab and OkLCh | `oklab` | batch 12 | Mixed-type parameters and sRGB conversion covered; full Oklab/OkLCh conformance not established. |

---

## Related known gaps (not separate issues)

These are limitations recorded in the batch reports and integration checkpoint.
They are not tracked as their own GitHub issues.

- SVG background rasterizer is a white placeholder.
- Non-circle/ellipse SVG shapes use bounding fill.
- Subgrid parsing does not establish inherited tracks.
- `shape-outside` is not wired into block layout.
- `starting-style` is serialised without a native transition lifecycle.
- Polygon interpolation returns the destination value.
- Host preference detection uses environment overrides, not Windows
  accessibility/theme notifications.
- Preference change listeners, nested `q` child text, full top-layer escape from
  ancestor contexts and SVG pointer geometry need further conformance work.
- Page/path helpers and `paint-order` require further feature-specific
  conformance validation.

---

## Status

Everything listed above is unimplemented or partial. No builds, tests,
typechecks or test authoring were performed for any item in this file.
