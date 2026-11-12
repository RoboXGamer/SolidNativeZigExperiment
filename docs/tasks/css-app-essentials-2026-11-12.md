# Everyday-app CSS implementation batch - 2026-11-12

This delivery used exactly two parallel subagents: typography/text and box
visuals/interaction. The parent integrated JSX serialization, explicit inheritance
masks, the native renderer, input hit geometry, focus and cursor lifecycle.

No tests, builds, typechecks, browser comparisons or test authoring ran. The user
explicitly paused them. Status is implementation-only and unverified. This is a
practical common-app feature group, not a measured 80% CSS compatibility claim.

## Native paths

- Immutable typography context now reaches intrinsic measurement, wrapping,
  baseline calculations, texture caching, glyph painting and caret positions.
- Windows Uniscribe selects installed font stacks/generic families, weight/style,
  spacing and tab stops. NLS transformations preserve the original author/editor
  text and source offsets. Font-size keywords and inheritance are resolved natively.
- First-line indentation, final-line alignment and basic clipped ellipsis share
  the shaped-line projection. Parent formatting containers can project their LTR
  nowrap overflow onto text nodes. Complete inline fragmentation remains separate.
- Elliptical/percentage/corner radii share CSS overlap normalization across cached
  backgrounds, borders, shadows, padding masks and transformed hit testing.
- Native outlines support width keywords, offsets, listed line styles, color and
  transparent/currentColor. Auto chooses a backend focus ring; dashed/dotted
  curved perimeters use sampled arc spacing.
- Hidden nodes retain layout and may have explicitly visible descendants. Hidden
  nodes leave pointer/focus targeting; pointer-events:none retains keyboard focus.
- Cursor resources are owned/cached and released on shutdown. Local Raylib image
  files and Windows .cur/.ani resources support hotspot selection. Network, data
  and SVG cursor loading are not implemented. Unsupported stock shapes use the
  nearest Windows stock cursor.

## Ticket disposition

Only rows marked implemented-unverified are implementation closures. Partial
rows remain open with their missing semantics named here and in the JSON ledger.
No row represents a passed conformance result.

| Issue | Feature | Status | Scope / remaining work |
| --- | --- | --- | --- |
| #94 | font-family | implemented-unverified | Installed native stacks and generic families; shared shaping/layout/paint |
| #95 | font-family-system | implemented-unverified | system-ui native font selection |
| #101 | font-size | partial-unverified | Absolute/relative keywords and unit sizing; complete zero-size semantics still require follow-up |
| #104 | font-style | partial-unverified | Native normal/italic/oblique; @font-face descriptors and exact oblique angles remain |
| #117 | font-weight | partial-unverified | Native numeric/normal/bold/bolder/lighter; @font-face descriptor/variable-font coverage remains |
| #147 | letter-spacing | implemented-unverified | Inherited typed lengths/normal in glyph advances, measurements and caret mapping |
| #285 | word-spacing | implemented-unverified | Shared styled word advances in measurement, shaping and paint |
| #241 | tab-size | implemented-unverified | Number and length-based tab stops shared by layout and native shaping |
| #251 | text-indent | partial-unverified | First shaped text-run indentation; complete multi-inline fragmentation remains |
| #246 | text-align-last | partial-unverified | Final-line alignment values; full justification engine remains |
| #253 | text-overflow | partial-unverified | Clipped nowrap/pre ellipsis and ancestor LTR projection; full RTL/fragmented inline edges remain |
| #256 | text-transform | partial-unverified | Locale-aware native case transforms without source mutation; full Unicode capitalization boundaries and all combinations remain |
| #25 | border-radius | implemented-unverified | Elliptical/percentage/slash/per-corner radii, zero override, overlap normalization, shared paint and hit geometry |
| #180 | outline | implemented-unverified | Shorthand, widths, styles, color and offset through native raster cache |
| #181 | outlines | implemented-unverified | All listed native outline style paths; auto uses backend solid focus ring |
| #65 | cursor | partial-unverified | Native keywords and local image/.cur/.ani URL resources; network/data/SVG cursors and exact uncommon platform shapes remain |
| #277 | visibility | partial-unverified | Inherited visible/hidden/collapse paint and input policy; flex struts/table collapse layout remain |
| #195 | pointer-events | partial-unverified | Native box auto/none and descendant overrides; SVG-specific painted/fill/stroke hit regions remain |
