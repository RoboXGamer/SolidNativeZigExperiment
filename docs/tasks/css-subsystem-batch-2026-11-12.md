# CSS subsystem batch â€” 2026-11-12

Implementation-only delivery. The user explicitly stopped all builds, tests,
typechecks and test authoring for this batch. No runtime, browser or test success
is claimed. Issue completion here means the native implementation has been
written; verification acceptance remains outstanding. This record supersedes
the historical source-only statuses for the listed native paths, not the global
Baseline conformance assessment.

The batch groups shared infrastructure rather than isolated ticket patches:

- Values/math: typed constants, sign, trigonometry, exponential and rounding
  families share the sizing parser. Raw typed results preserve nonfinite values
  and signed zero; final layout lengths retain safety validation. The scalar
  dimension model does not represent compound/inverse dimensions. Newer
  device-dependent line-width rounding is outside the pinned ticket scope.
- Colors/paint: one parser supplies named, RGB/HSL/HWB, Lab/LCH/Oklab/OKLCH and
  explicit color spaces to backgrounds, gradients, shadows, text and borders.
  The backend targets its existing 8-bit sRGB framebuffer; HDR/wide-gamut output,
  relative colors, color-mix(), CSS cascade and color-scheme queries are separate
  features. CurrentColor is resolved from inherited native computed styles.
- Easing/motion: validated cubic, stepped and piecewise-linear curves feed the
  retained transition timeline, including ownership, retarget and cancellation.
  This does not implement the separate CSS keyframe-animation family.
- Native integration: percentage/scientific opacity, isolated stacking contexts,
  ignored static insets and math-aware font/transform consumers. The retained
  Tree owns new CSS strings through its existing reflective cloning.

## Frozen ticket scopes

Lab/LCH, Oklab/OKLCH and color() tickets #144/#178/#41 remain open: their
parsers and conversion paths are written, but the framebuffer still clips
wide-gamut values instead of implementing perceptual gamut mapping.

The machine-readable companion lists each eligible compatibility key and its
implementation owner. Counts describe the catalog scope, not passed tests.

| Issue | Feature | Eligible keys | Status |
| --- | --- | --- | --- |
| #232 | static-positioning | 1 | implemented-unverified |
| #179 | opacity | 4 | implemented-unverified |
| #143 | isolation | 1 | implemented-unverified |
| #63 | cubic-bezier-easing | 2 | implemented-unverified |
| #233 | steps-easing | 2 | implemented-unverified |
| #152 | linear-easing | 1 | implemented-unverified |
| #289 | abs-sign | 2 | implemented-unverified |
| #30 | calc-constants | 5 | implemented-unverified |
| #267 | trig-functions | 7 | implemented-unverified |
| #80 | exp-functions | 5 | implemented-unverified |
| #215 | round-mod-rem | 6 | implemented-unverified |
| #169 | named-color | 3 | implemented-unverified |
| #212 | rgb | 7 | implemented-unverified |
| #127 | hsl | 4 | implemented-unverified |
| #128 | hwb | 2 | implemented-unverified |
| #144 | lab | 4 | partial-unverified |
| #178 | oklab | 4 | partial-unverified |
| #41 | color-function | 2 | partial-unverified |
| #293 | conic-gradients | 2 | implemented-unverified |
| #297 | gradients | 4 | implemented-unverified |
