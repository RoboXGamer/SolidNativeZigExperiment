# ThorVG retained UI prototype

**Recommendation: conditional adoption for the vector drawing layer. Do not migrate production yet.** ThorVG can represent this UI and runs through a C ABI from Zig on this Windows machine. Software smart rendering gives useful sparse updates when static effects are cached. The release's OpenGL backend redraws the full target, and live shadows can remove most of the software advantage. ThorVG does not replace CSS invalidation or a modern text layout backend.

This is an isolated decision prototype based on parent commit `c357d694364e838e6dc02d2feb675af25a5902c7`. It does not modify the project's fonts, JS invalidation, generated bundle, native executable, or production renderer. No physical pointer/window automation was used; native windows were hidden. The interactive viewer is provided for the user to launch.

## Reproduce

From the repository root, in PowerShell:

```powershell
./prototypes/thorvg/setup.ps1
./prototypes/thorvg/build.ps1 -Run
uv run prototypes/thorvg/analyze.py
```

`build.ps1 -Check` runs pixel/DPI/resize checks without repeating the timing matrix. `build.ps1 -View` opens a preview for manual inspection: hover the nine tiles, press **G** to toggle the first tile's width, resize the window, then close it to exit. Its event-driven native hover bypasses JS and does not reproduce the complete tic-tac-toe application. Native hover speed must not be presented as a JS latency fix. The viewer code is built but its manual interaction is intentionally left to the user; automated evidence comes from hidden runs. Run builds separately from a currently open viewer on Windows.

Only this directory's `.deps`, `.build`, and `artifacts` are written. Required tools: Git, Zig **0.17.0**, uv, Ninja (**1.13.2** used), internet for the initial source/archive/tool fetch, and Windows system graphics/text APIs. Meson **1.12.1** is isolated with `uv tool run`. Analysis is a real PEP 723 Python script run with uv and pinned Pillow **12.0.0**.

## Pin, build, and machine

- Official latest release checked on 2026-11-16: [ThorVG 1.1.3](https://github.com/thorvg/thorvg/releases/tag/v1.1.3), exact commit **589bc4120f2097fb1b135e552c2ef39f6581612b**. Setup refuses a different or locally modified dependency checkout.
- GLFW **3.4**, official Windows x64 binary archive; SHA-256 **54efa829400f2a0537f742b2b3bdd74e437bb4f2f048e4b7d3c5557d11a611e6**. The MinGW DLL is used through its C import library. Both upstream license notices are included under `licenses`.
- Meson release `-O3`, static ThorVG, CPU + desktop GL, C API, TTF only, partial rendering compiled in, threads compiled in but **Initializer::init(0): synchronous single-thread execution**, SIMD **disabled**. SVG, Lottie, PNG/JPEG, OTF, WebGPU, expression JS and OpenMP are not built. This is a deliberately small vector/text configuration, not a measurement of all ThorVG features.
- Windows 11 Home Single Language **10.0.26300**, Intel Core i7-13650HX (14 cores / 20 logical processors), Balanced power plan. The session is a shared development machine; CPU clock, thermal state, AC state and other agents were not controlled. Per-sample timing is retained, and small differences between sequential runs are not a universal ranking.
- Actual GL context: **Intel / Intel(R) RaptorLake-S Mobile Graphics Controller / OpenGL 3.3.0, driver 32.0.101.7026**. The machine also lists an NVIDIA RTX 4050 Laptop GPU; that adapter was not forced or benchmarked. These are backend comparisons on the Intel adapter, not an adapter comparison.
- WebGPU was **not built or run**. `pkg-config --modversion wgpu_native` reports it absent. The pin's build requires `wgpu_native` and its README names v29.0.1.1. WebGPU performance/quality and DirectX/Vulkan interop remain unproven here. No library was installed globally to manufacture availability.

The AVX2 build compiled but the final Zig C++ link failed on `__cpu_indicator_init` and `__cpu_model`. The reproducible build therefore disables SIMD rather than inventing a CPU feature stub. MSVC or a properly supplied compiler runtime could resolve this, but was not tested. Do not treat these scalar numbers as ThorVG's best possible CPU performance.

The other discovered build issue was `lld-link: error: glBindTexture was replaced`: ThorVG's Windows GL loader has global GL function-pointer names that collide with direct host OpenGL imports. The probe loads its GL calls through `glfwGetProcAddress` under separate symbol names. `abi-smoke.zig` uses explicit extern declarations because this Zig version has removed `@cImport`. The smoke was compiled, linked to the real static C API, run, and checked rounded rectangle pixels.

## Workload and correctness

`probe.cpp` builds and retains real `Scene`, `Shape`, `Picture` and `Text` objects. Each update changes existing paint properties. Shapes are not reconstructed for hover, and the entire retained scene is submitted to ThorVG's `update/draw/sync` path. Geometry changes reset only one retained tile's path.

The 800 x 600 logical composition contains an opaque background; a rounded 3 x 3 board; round-capped Xs and stroked Os; a blurred drop shadow; two nested clips; a scene at opacity 128 with two overlapping opaque children; rotation plus translation; ordered overlapping siblings; native ThorVG TTF text; and a separate DirectWrite/Direct2D text bitmap containing Latin, Arabic and Devanagari. The flat top on the cyan clip example is intentional: a rectangular clip intersects a circular clip.

Pixel checks test interiors against specific expected colors, the exposed rounded corner, both clip boundaries, the shadow outside the board, group opacity at overlap versus a single child, z order and transformed position. Exact whole-image comparisons verify unchanged frames, sparse hover versus a forced full clear/redraw, geometry shrink/restore, transform old-position restoration, and same-canvas resize/DPI round trips. The final benchmark state is also checked against a forced full redraw outside each timing interval, including the 64-board case. Tests are assertions about this fixture, not exhaustive CSS renderer conformance.

Initial image checks use 800 x 600 and separate 1200 x 900 / 1.5 scale canvases. Resize checks rebind the **same** retained canvas to 1200 x 900, rerasterize DirectWrite at 144 DPI, then restore 800 x 600 / 96 DPI and require identical pixels. These are programmatic framebuffer and DPI-resource tests; moving a physical window between real monitors and handling `WM_DPICHANGED` is not tested.

See [run.txt](artifacts/run.txt), [software image](artifacts/sw-smart.png), [GL image](artifacts/gl-full.png), [150% DPI image](artifacts/gl-full-dpi150.png), and [image comparison](artifacts/image-analysis.json). Cross-backend edge pixels are not identical: the analysis records their maximum error and count. Interior and temporal correctness assertions are separate from that quality comparison; no assertion says the two rasterizers have identical antialiasing.

## Measurement definitions

The complete result matrix is [matrix.md](artifacts/matrix.md), with machine-readable [timings.csv](artifacts/timings.csv) and every measured [sample](artifacts/samples.csv). [comparison.html](artifacts/comparison.html) plots selected matched cases. All reported durations are **milliseconds**. Every timed row uses **20 warmup iterations and 100 samples**. p50 is sorted index 50, p95 index 94, maximum index 99. Mean is arithmetic. No samples are filtered.

[Selected matched results](artifacts/selected.md) place sparse software, forced full software, sparse software plus a real full upload, direct GL, and live bounded software effects side by side at both node counts. The complete CSV retains the unbounded effect, all-color, unchanged and geometry cases as well.

The final run's selected p50 / p95 values were:

| Matched path | 1 board | 64 miniature boards |
|---|---:|---:|
| Software smart, cached shadow | 1.1042 / 1.2490 | 0.4229 / 0.6176 |
| Software forced full, cached shadow | 15.9367 / 16.9501 | 17.6138 / 18.8102 |
| Software smart + full upload, cached shadow | 3.2955 / 4.1423 | 2.4090 / 3.6389 |
| GL full clear/redraw, cached shadow | 4.0609 / 4.4870 | 9.1428 / 9.9949 |
| Software smart, live bounded shadow | 3.3260 / 4.3034 | 3.5427 / 3.9963 |

The full upload consumed much of the sparse software gain but did **not negate it** for this fixture. That conclusion is specific to these dimensions, static effect/text resources, scalar build and synchronous transfer. The 64-board hover changes a much smaller tile than the one-board hover, so its lower sparse time does not imply that increasing scene size makes rendering faster.

The timing viewport is **1280 x 800**, logical root scale **1.333333**, with the root's 800 x 600 background covering the left approximately 1067 pixels; the remaining target strip is transparent/cleared. The same composition/target applies to both engines. One board uses full-size tiles; 64 boards use an 8 x 8 arrangement of scaled mini boards within the same target, so this compares backend behavior at two scene densities, not a perfectly linear scaling model. No marks or tiles are occluded by another board. Each board has 9 retained tile backgrounds, 3 Xs and 3 Os. The rest of the sentinels remain present.

Exact paint counts, including clip shapes and grouping scenes, are recorded per row: unbounded live shadow **32 / 1040**, clipped live shadow **33 / 1041**, cached shadow **31 / 1039**, for 1 / 64 boards. Text and text construction are excluded from the benchmark scenes; text is exercised by correctness and interoperability runs. The correctness scene adds one text Picture and one native Text. The scratch shadow canvas is excluded from the retained target count and frame timing.

Timed drawing includes property mutations (including geometry reset/append), the small C++ dispatch logic, ThorVG update, draw and sync. GL additionally calls **glFinish each frame**, measuring CPU-visible GPU completion instead of only queued submission. This intentionally serializes frames; it is not an isolated GPU timestamp and is not production pipelined throughput. Correctness readbacks, PNG conversion, object creation, shadow bitmap creation, initial text shaping/rasterization and first render are outside these steady-state samples. Initial canvas render timings are printed separately and include backend preparation and lazy resources/shader work; they are single observations, not percentiles or cold-process startup measurements. The GL clear diagnostic runs before those fixture timings and can warm shared driver resources.

Excluded: QuickJS, selector matching, CSS/layout, native tree bridge application, OS input, message dispatch latency, swap/present/vsync, compositor latency and pointer-to-photon delay. This prototype cannot demonstrate improvement over the existing Raylib renderer because that renderer was not run under this synthetic matched fixture. The parent's measured optimized-QuickJS tile switch remains **285.94 ms p50 before native drawing**; this work does not fix it.

Workloads: `unchanged` still calls update/draw/sync without mutations; `hover` alternates one tile's fill; `all-colors` alternates every tile; `geometry` alternates one tile's width 94/82; `forced-full-hover` alternates one tile and calls `draw(true)` every frame. `none` disables smart rendering; `smart-request` enables it on software but is ignored on GL. Forced full clear/redraw within the smart canvas is the most direct sparse/full matched pair; the disabled-smart rows are also included. **All GL frames clear**, because that backend fully redraws and cannot correctly preserve partially transparent edge pixels. Thus GL `hover` and `forced-full-hover` have the same clear policy; differences between their sequential timings are variation, not evidence of GPU damage optimization.

`probe_dirty_area` comes from the public dirty-region API **between draw and sync**, in a separate representative update after sampling. It sums rectangle areas and may include overlap/partition rounding; it is not a unique-pixel or GPU traffic measurement. API querying/readback is excluded from the timed frames. A no-op host should skip drawing altogether when no paint revision changes; the measured `unchanged` row measures ThorVG overhead if it is called anyway.

`full-texture-upload-only` uploads **4,096,000 bytes per update** (1280 x 800 x RGBA8) with `glTexSubImage2D` and `glFinish`. `hover-plus-full-upload` actually performs the software hover draw and the upload in one measured interval. It is not the sum of independently measured medians. It excludes the final textured quad and presentation. No PBO, texture ring, partial upload or CPU/GPU overlap is used.

## Why the shadow strategy matters

- **Live unbounded:** a retained ThorVG DropShadow scene. The pinned scene implementation damages its current renderer viewport when effects exist, even if only another object's fill changed. Without an explicit rectangular clip that is the whole canvas. This is a confirmed limitation of this scene arrangement, not a general claim that all ThorVG scenes invalidate everything.
- **Live bounded:** the same shadow, padded to 380 x 380 logical pixels with a rectangular clip. This constrains software damage but still recomputes/recomposites the effect every update. It does not turn the software allocator into a tightly bounded layer allocator.
- **Cached bitmap:** render the same static rounded panel and shadow once into a 380 x 380 premultiplied software bitmap, retain it as a ThorVG Picture, then mutate tiles independently. Both CPU and GL consume the same cached shadow pixels. This is an explicit application cache, not automatic ThorVG effect retention. Cache generation/invalidation must be paid when its geometry, shadow parameters or DPI changes. The timing fixture keeps that cache static.

At 800 x 600, a one-tile hover reports software damage of **480,000 px** for unbounded effects, **160,400 px** for the clipped live scene, and **24,836 px** with the static shadow cached. The latter still exceeds the tile area because of region partitioning. GL reports **480,000 px** in all cases. These are direct correctness-run observations, distinct from the 1280 x 800 timing probes in the CSV.

## Integration assessment and blockers

**Retained rendering and damage:** use one stable ThorVG paint/group per native paint identity, update only changed properties, and preserve sibling paint order. ThorVG can retain geometry and raster resources and perform software damage redraw. The application's layout, style propagation, old/new effect bounds, deletion/reordering and event scheduling remain its responsibility. Bounded effect clips and explicit static-layer caches must be designed rather than assuming every Scene automatically caches its output.

**Software upload:** the measured combined upload rows show whether the large sparse CPU reduction survives a mandatory full transfer. A full transfer creates a size-dependent lower bound even when ThorVG only changes one small region. Do not promise proportional end-to-end savings from CPU smart rendering alone. Use the dirty-region API for subrectangle uploads with full source stride, keep premultiplied-alpha blending correct, and skip upload/present entirely for unchanged frames. Texture rings/PBOs could reduce stalls but were not evaluated. Higher DPI multiplies upload bytes quadratically; 2560 x 1600 would be **16,384,000 bytes** per full update, a byte calculation, not a measured upload time.

**Software layers:** source inspection of `SwRenderer::request` shows compositor storage at the full target dimensions, or a square of max(width,height) for post-processing. Bounding the draw clip reduces pixel work/damage, not these backing allocations. For genuinely bounded surfaces use separate small offscreen canvases and retained pictures, as the cached-shadow path does. Multiple simultaneously live effects can still require sizeable intermediate memory; this prototype did not profile peak layer memory or allocator churn.

**GL and host:** the tested path keeps a GLFW-created desktop GL context current and targets framebuffer 0 with the real WGL context. ThorVG also accepts an FBO id; targeting a Raylib render texture is a plausible integration step, **not tested here**. Keep rendering on the context-owning thread, flush Raylib's pending rlgl batch before entering ThorVG, restore/re-establish host GL state afterwards, and test alternating text/vector/host drawing. Sharing a context avoids full CPU framebuffer uploads. Replacing Raylib with a minimal GLFW host is also feasible but requires retaining input, clipboard, DPI, cursor, wakeup and window lifecycle behavior. No production Raylib interop or replacement host was implemented.

The pinned [GL API](https://github.com/thorvg/thorvg/blob/589bc4120f2097fb1b135e552c2ef39f6581612b/inc/thorvg.h) explicitly ignores SmartRender. `GlRenderer::damage` and `partial` are TODOs; its dirty-regions API returns the full target. The [upstream GPU partial-rendering issue](https://github.com/thorvg/thorvg/issues/3865) remains open. Retained geometry is useful, but is not GPU damage redraw. Internal GL composition uses a 4-sample color/stencil FBO and resolves; those internal passes and final resolve are included in the completed-draw times. No `glFinish` should be inserted into every production frame just to copy this benchmark; use appropriate resource lifetime/fences and measure submission, execution and present separately.

A diagnostic deliberately draws GL without clearing: at the fractional right edge of the scaled opaque background it changes **800 pixels, x=1066 and y=0..799**, by accumulating coverage against the previous target. Clearing restores exact pixels. Both the incorrect and corrected images are persisted as `gl-no-clear.png` / `gl-cleared.png`; the final timing matrix uses the corrected clear policy. This is an integration requirement, not a claim that ThorVG promises GPU smart redraw and implements it incorrectly.

**Text:** ThorVG's native TTF path runs, supports fractional sizing and returns vector glyphs. In this pin the SFNT loader iterates Unicode codepoints and adjacent glyph positioning; it does not provide a full application text backend with bidirectional shaping, script shaping, system fallback, editable-text clusters, selection and caret geometry. Native TTF success is not evidence those needs are solved.

The separate modern-text path really calls DirectWrite layout and Direct2D grayscale rasterization to a **600 x 100 logical** transparent WIC bitmap, imports premultiplied pixels into a ThorVG Picture, and rerasterizes at DPI changes. It is a viable Windows interoperability demonstration. It does not implement an atlas, text cache policy, hit testing, IME, caret/selection or font fallback regression suite. Production must use the same DirectWrite layout result for measure/draw/caret geometry and rerasterize after font/text/DPI changes rather than scale old bitmaps. An outline/glyph-atlas bridge can avoid whole-run bitmaps but was not implemented. Cross-platform text would need another backend such as HarfBuzz/FreeType with appropriate bidi and fallback handling; this is a design option, not tested functionality.

**Distribution and maintenance:** see `artifacts/build-info.json` for exact built file sizes. These are executable/archive sizes, not incremental costs versus the existing application. ThorVG's C++ runtime is statically linked; Windows graphics/text DLLs remain system dependencies and GLFW is a separate DLL. A C API boundary avoids exposing C++ ownership/ABI to Zig, but requires lifecycle/error handling, version pinning and binding maintenance (effects include varargs). The prototype disables most format loaders, which limits dependencies and attack/maintenance surface; enabling SVG/Lottie/media changes the result. ThorVG and GLFW license notices are retained. MSVC and native WebGPU toolchains are unvalidated.

## Adoption steps

1. Accept this as a **vector-backend candidate**, with a modern text backend kept separate. Do not combine it with the independent JS invalidation change or claim end-to-end hover improvement from these measurements.
2. Resolve the SIMD/compiler-runtime build issue and pin a production Windows toolchain. Regenerate/validate Zig C declarations against the pinned header rather than expanding unreviewed manual bindings.
3. Add a native paint-id to ThorVG-object adapter in an isolated backend switch. Handle removal, z-order changes, clipping, inherited/group opacity, transforms and old/new effect bounds. Add existing project conformance fixtures, not only this synthetic board.
4. For a first small-UI integration, evaluate **software SmartRender + dirty-rectangle upload + cached static effects** and **direct GL + cached static effects** on the same real UI. Keep CPU/GPU sync and present as separately measured stages. If GPU partial redraw is a requirement, this release does not satisfy it; application-managed tiles/caches or a verified future upstream implementation would be additional work.
5. Prove Raylib context/state interop, or deliberately replace the host after implementing its window/input/DPI behavior. Test real user-controlled visual quality at 100%, 125%, 150%, 200% DPI, text scripts and interactive resize. The programmatic 150% checks are only an initial gate.
6. Measure the actual optimized-JS transaction, layout, native command application, draw, upload, swap and pointer-to-photon separately. Adopt only if those matched real-application numbers and visual checks justify the added adapter/caching work.

This prototype supports a conditional ThorVG direction without forcing a production migration. If the requirement is an immediate drop-in renderer that supplies GPU damage redraw and a complete text system, **reject that requirement match for ThorVG 1.1.3**.

## Primary references inspected

- [Pinned source and C++ API](https://github.com/thorvg/thorvg/tree/589bc4120f2097fb1b135e552c2ef39f6581612b), [C API](https://github.com/thorvg/thorvg/blob/589bc4120f2097fb1b135e552c2ef39f6581612b/src/bindings/capi/thorvg_capi.h), [Meson options](https://github.com/thorvg/thorvg/blob/589bc4120f2097fb1b135e552c2ef39f6581612b/meson_options.txt).
- [Pinned scene update/effect damage](https://github.com/thorvg/thorvg/blob/589bc4120f2097fb1b135e552c2ef39f6581612b/src/renderer/tvgScene.h), [software compositor/dirty regions](https://github.com/thorvg/thorvg/blob/589bc4120f2097fb1b135e552c2ef39f6581612b/src/renderer/cpu_engine/tvgSwRenderer.cpp), [GL renderer](https://github.com/thorvg/thorvg/blob/589bc4120f2097fb1b135e552c2ef39f6581612b/src/renderer/gpu_engine/gl/tvgGlRenderer.cpp), [SFNT loader](https://github.com/thorvg/thorvg/blob/589bc4120f2097fb1b135e552c2ef39f6581612b/src/loaders/sfnt/tvgSfntLoader.cpp).
- [Official smart-rendering release explanation](https://www.thorvg.org/post/thorvg-v1-0-a-new-generation-released), [Microsoft DirectWrite](https://learn.microsoft.com/en-us/windows/win32/directwrite/direct-write-portal), [official GLFW 3.4 release](https://github.com/glfw/glfw/releases/tag/3.4).
