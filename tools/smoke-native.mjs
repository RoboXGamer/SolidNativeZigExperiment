import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
process.chdir(fileURLToPath(new URL("../", import.meta.url)));
const hover = process.argv.includes("--hover");
const frames = process.argv.includes("--frames");
if(hover||frames){await import('./test-frame-scheduling.mjs');process.exit(0);}
const r = spawnSync("zig-out/bin/windows.exe", [], {
  encoding: "utf8",
  timeout: 15000,
  env: {
    ...process.env,
    SOLID_NATIVE_SMOKE: "1",
    ...(hover ? { SOLID_NATIVE_HOVER_SMOKE: "1" } : {}),
    ...(frames ? { SOLID_NATIVE_FRAME_SMOKE: "1" } : {}),
  },
});
const output = (r.stdout || "") + (r.stderr || "");
process.stdout.write(output);
if (
  r.error ||
  r.status !== 0 ||
  !output.includes("Native application smoke completed:") ||
  /\(err\)|ERROR:|Could not|failed:/i.test(output)
) {
  console.error(r.error || "Native application smoke failed");
  process.exit(1);
}
if (
  hover &&
  (!output.includes("Native hover frame regression passed:") ||
    !output.includes("Native hover invalidation passed:"))
) {
  console.error("Native hover frame regression did not run");
  process.exit(1);
}
if (frames && !output.includes("Native frame scheduling passed:")) {
  console.error("Native frame scheduling regression did not run");
  process.exit(1);
}
