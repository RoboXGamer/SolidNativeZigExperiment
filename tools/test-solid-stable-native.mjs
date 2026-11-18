import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

process.chdir(fileURLToPath(new URL("../", import.meta.url)));
const testEnv = { ...process.env };
delete testEnv.DRAFT1_HMR;

function run(command, args, extraEnv = {}) {
  const result = spawnSync(command, args, {
    encoding: "utf8",
    timeout: 180000,
    windowsHide: true,
    env: { ...testEnv, ...extraEnv },
  });
  const output = (result.stdout || "") + (result.stderr || "");
  if (result.error || result.status !== 0) throw Error(output + (result.error || ""));
  return output;
}

try {
  for (const [mode, development] of [["production", false], ["native-hmr", true]]) {
    console.log(`Building native Solid 2 contract fixture (${mode})`);
    run(process.execPath, ["tools/build-ui.mjs", "--mode", mode], {
      DRAFT1_ENTRY: "/tests/fixtures/solid-stable.jsx", DRAFT1_EXAMPLE: "",
    });
    run("zig", ["build"]);
    const output = run(process.execPath, ["tools/smoke-native.mjs"]);
    const marker = output.split(/\r?\n/).find(line =>
      /PASS Solid 2 stable contracts: \d+ checks/.test(line) && line.includes(`development=${development}`));
    if (!marker || output.includes("STABLE_CONTRACT_FAILURE"))
      throw Error(`Embedded ${mode} contract did not complete: ${output}`);
    console.log(marker);
  }
} finally {
  run(process.execPath, ["tools/build-ui.mjs", "--example", "css"]);
  run("zig", ["build"]);
}
