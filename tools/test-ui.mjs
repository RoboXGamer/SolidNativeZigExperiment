import { spawnSync } from "node:child_process";
import { mkdirSync } from "node:fs";

mkdirSync(".zig-cache", { recursive: true });
const output = ".zig-cache/ui-smoke.exe";
const sources = ["cutils.c", "dtoa.c", "libregexp.c", "libunicode.c", "quickjs.c"].map(file => `vendor/quickjs/${file}`);
const build = spawnSync("zig", ["cc", "-Ivendor/quickjs", "-D_GNU_SOURCE", "-DWIN32_LEAN_AND_MEAN", "tests/ui_smoke.c", "src/quickjs_bridge.c", ...sources, "-o", output], { stdio: "inherit" });
if (build.status !== 0) process.exit(build.status ?? 1);
const test = spawnSync(output, [], { stdio: "inherit" });
process.exit(test.status ?? 1);
