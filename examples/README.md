# Examples

Each demo has its own folder and `app.js` entry. All demos share the root dependencies, Vite configuration, CSS compiler, Solid adapter and Zig engine. Run commands from the repository root.

| Example         | Entry                    | Purpose                                                                                       |
| --------------- | ------------------------ | --------------------------------------------------------------------------------------------- |
| `css` (default) | `examples/css/app.js`    | Normal CSS, class/ID selectors, inheritance, reactive classes, imported styles and image URLs |
| `states`        | `examples/states/app.js` | Async state/city selection with native select controls                                        |

```powershell
pnpm dev --example css
pnpm dev --example states
```

Only run one demo at a time: this alpha still shares the generated `src/ui-bundle.js`, `src/ui-hmr.js` and native executable. Stop the running demo before selecting another.

For the two-terminal development workflow, select the same example in both terminals:

```powershell
# Terminal 1
pnpm dev:ui --example states
# Terminal 2
pnpm dev:app --example states
```

For a production bundle and native launch:

```powershell
pnpm build:ui --example states
zig build run
```

`pnpm dev` and `pnpm build:ui` default to `css`. Advanced scripts can still set `DRAFT1_ENTRY` to a custom repository-relative module path. An explicit `--example` takes precedence over environment selection.

To add a demo, create `examples/my-demo/app.js` and any adjacent components, CSS and assets:

```js
// examples/my-demo/app.js
import { mountApp } from "@zig-ui/solid";
import App from "./App.jsx";
mountApp(App);
```

Then run `pnpm dev --example my-demo`. Folders with an `app.js` entry are discovered automatically; no engine or root configuration changes are needed. Keep imports local to the demo where practical. No per-demo package installation or SDK publishing is required.

External SDK packaging is deferred in [issue #333](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/333).
