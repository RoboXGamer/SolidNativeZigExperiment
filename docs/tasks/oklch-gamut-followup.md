# #178 gamut mapping followup

Prerequisite: integration PR #328 at 92ca03867fecf4ebf742d09b88bfdf8ee57a1751, incorporated by fast-forward; all twelve original batches retained.

Implements CSS Color 4 (13 February 2024) section 13.2.1 local MINDE for absolute and relative Oklab/OKLCH output to sRGB. Search retains lightness/hue before local clipping, uses JND 0.02 and epsilon 0.0001, handles black/white endpoints and preserves alpha through existing packing.

Oracle: Color.js 0.5.2 toGamut({method: css}), run independently for four saturated vectors. Expected bytes: (255,88,67), (0,194,72), (52,37,255), (218,0,198). Tolerance one byte per channel (conversion coefficient precision and quantization). Tests also cover neutral, endpoints, mixed percentages/angle units, alpha and invalid grammar. Native scene JSON background is rendered and read from actual OpenGL framebuffer at (20,20), expected (255,88,67), tolerance one byte.

Validation: zig test modules/ui_core/colors.zig passes; pnpm test passes; pnpm run test:native passes including new framebuffer fixture; zig build passes. See followup logs. Smoke FAILS with DuplicateNode after both default and native-hmr bundle builds; unresolved.

Remaining #178 limits: no frozen browser/platform/device-scale comparison, reactive bridge fixture, comprehensive calc/extreme-value fixtures, or preservation of unquantized relative origin coordinates. Existing relative parser converts origin to 8-bit RGB before computing relative channels. This draft therefore does not establish full #178 acceptance or authorize closure. Other four partial tickets #296, #295, #294, #291 remain pending, along with previously documented source gaps.