# Portable Windows build

Install Zig 0.17.0, Node.js (`^22.18.0 || >=24.11.0`), pnpm and Git on the build machine, then run:

```powershell
pnpm install --frozen-lockfile
pnpm build
```

The build verifies/fetches the pinned QuickJS checkout, bundles the production UI,
and compiles the native host in ReleaseSafe mode with the Windows GUI subsystem
and baseline CPU instructions for the build machine's architecture.
The result is `dist/SolidNative.exe`. Double-click it to launch without a console.
The default example is `css`; select another with `pnpm build --example states`
or `pnpm build --example tictactoe`. Each build replaces the same output file.
Production uses `.zig-cache/portable-ui` and `zig-out/portable` so development
builds cannot replace its UI bundle or native binary. Run only one production
build at a time.

The executable embeds the UI bundle and compiled CSS image assets. It can run
outside the repository without Node.js, pnpm, Zig, a dev server or sidecar UI
files. Windows system libraries, installed fonts and a working graphics driver
are still required. Custom application code that reads external resources must
provide those resources separately.

Keep `dist/LICENSE-QuickJS.txt` with distributions and retain applicable licenses
for dependencies and any application assets. The build produces no installer,
shortcuts or registry entries. `pnpm build:ui` remains available for rebuilding
only the UI; `pnpm dev` remains the development workflow.

After building, `pnpm test:portable` checks the GUI subsystem and runs a temporary
copy of only the executable outside the repository. It opens the real native
window hidden for a short smoke run, then verifies a normal visible launch stays
open for five seconds and closes normally. It then removes the temporary copy.
