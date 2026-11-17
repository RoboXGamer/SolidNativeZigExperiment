# Native screenshot provenance

These PNGs show output from the real Windows native host, with the production Solid bundle running inside QuickJS-NG. They are framebuffer captures from hidden native windows, rather than browser previews or design mockups.

Captured on **2026-11-17 UTC** (the local session crossed into **2026-11-18 IST**). Native runtime and existing example sources match `b7c31dc51966eb8264d0bf803105375f80f4c4c0`; the counter is the new local example accompanying the README update.

| Image | Source | Captured state |
| --- | --- | --- |
| [Tic-tac-toe](tictactoe-native.png) | [App.jsx](../../examples/tictactoe/App.jsx) and [game.css](../../examples/tictactoe/styles/game.css) | Initial mark-selection/new-game screen |
| [Counter](counter-native.png) | [App.jsx](../../examples/counter/App.jsx) and [app.css](../../examples/counter/app.css) | Initial count of zero |
| [CSS demo](css-native.png) | [App.jsx](../../examples/css/App.jsx) and [demo.css](../../examples/css/styles/demo.css) | Initial classes, inherited text and embedded checker image |

Environment: Windows, Zig 0.17.0, Node.js v26.13.0, pnpm 12.15.0, Solid 2.0.0-rc.21, Raylib 6.2/OpenGL and DirectWrite. The host reports a **1280 × 720 logical window**, **1600 × 900 render viewport** and **125% display scale**. Font appearance depends on the installed Windows fonts.

Each published PNG is a pixel-for-pixel copy of that 1600 × 900 viewport. Raylib's raw export on this display includes unused black padding above and to the right; only that padding is removed. No UI content, colors, text or styling were changed in the images. Raw captures are retained locally in the ignored `zig-out/readme-captures/` directory.

## Reproduce a capture

After the repository setup, run from its root in PowerShell:

```powershell
./tools/capture-readme.ps1 -Example tictactoe
./tools/capture-readme.ps1 -Example counter
./tools/capture-readme.ps1 -Example css
```

The [capture helper](../../tools/capture-readme.ps1) builds the selected production UI and native executable, runs the existing smoke runner with `SOLID_NATIVE_SCREENSHOT`, reads the actual render dimensions, and saves the viewport PNG. The raw PNG and smoke output remain in `zig-out/readme-captures/` after each reproduction. Run captures sequentially because all examples share one generated bundle and executable.

The native smoke completed for all three captures. The example suite also checks the counter's transition from zero to one after a dispatched click. These images are static evidence of the captured states; they do not demonstrate HMR reliability, physical pointer interaction, accessibility, IME or multi-monitor correctness.
