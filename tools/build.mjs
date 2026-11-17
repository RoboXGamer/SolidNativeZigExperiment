import { build } from "vite";
import { spawnSync } from "node:child_process";
import { copyFileSync, mkdirSync, statSync } from "node:fs";
import { configureExample, projectRoot } from "./example-entry.mjs";

process.chdir(projectRoot);
if (process.platform !== "win32") throw Error("Portable executable builds currently require Windows.");
const selection = configureExample(process.argv.slice(2));
if (selection.args.length) throw Error(`Unknown build argument: ${selection.args.join(" ")}`);
function run(command, args) {
  const result = spawnSync(command, args, { stdio: "inherit" });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}

// Publish only after both stages succeed; never copy a stale native build.
run(process.execPath, ["tools/setup.mjs"]);
console.log(`[build] Production UI: ${selection.entry}`);
await build({ mode: "production", build: { outDir: ".zig-cache/portable-ui" } });
run("zig", ["build", "-Doptimize=ReleaseSafe", "-Dcpu=baseline", "-Dportable=true", "-Dui-bundle=.zig-cache/portable-ui/ui-bundle.js", "--prefix", "zig-out/portable"]);
mkdirSync("dist", { recursive: true });
copyFileSync("zig-out/portable/bin/windows.exe", "dist/SolidNative.exe");
// Keep the embedded interpreter's license alongside distributed binaries.
copyFileSync("vendor/quickjs/LICENSE", "dist/LICENSE-QuickJS.txt");
console.log(`[build] dist/SolidNative.exe (${statSync("dist/SolidNative.exe").size} bytes)`);
console.log("[build] Portable Windows app; no Node.js, pnpm or source checkout needed to run.");
