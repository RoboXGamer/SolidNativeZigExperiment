import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
process.chdir(fileURLToPath(new URL("../", import.meta.url)));
function run(command, args, env = {}) {
  const r = spawnSync(command, args, { encoding: "utf8", timeout: 180000, env: { ...process.env, ...env } });
  if (r.error || r.status !== 0) throw Error(`${command} ${args.join(" ")}\n${r.stdout || ""}${r.stderr || ""}${r.error || ""}`);
  return (r.stdout || "") + (r.stderr || "");
}
try {
  run(process.execPath, ["tools/build-ui.mjs"], { DRAFT1_ENTRY: "/tests/fixtures/tictactoe-hover-probe.js", DRAFT1_EXAMPLE: "" });
  run("zig", ["build"]);
  // A deliberately repeated expensive CSS transaction can exceed the ordinary
  // smoke runner's 15-second cap. Keep the longer timeout local to this probe.
  const output = run("zig-out/bin/windows.exe", [], { SOLID_NATIVE_SMOKE: "1" });
  const result = output.split(/\r?\n/).find(line => line.includes("TICTACTOE_HOVER_PROFILE"));
  if (!result) throw Error(`Hover profile did not execute\n${output}`);
  if (!output.includes("Native application smoke completed:")) throw Error(`Native profile did not complete\n${output}`);
  console.log(result);
} finally {
  run(process.execPath, ["tools/build-ui.mjs", "--example", "tictactoe"]);
  run("zig", ["build"]);
}
