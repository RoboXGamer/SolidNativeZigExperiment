import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
process.chdir(fileURLToPath(new URL("../", import.meta.url)));
function run(command, args, env = {}) {
  const r = spawnSync(command, args, {
    encoding: "utf8",
    timeout: 120000,
    env: { ...process.env, ...env },
  });
  if (r.status !== 0)
    throw Error(
      `${command} ${args.join(" ")}\n${r.stdout || ""}${r.stderr || ""}${r.error || ""}`,
    );
  return (r.stdout || "") + (r.stderr || "");
}
try {
  run(process.execPath, ["tools/build-ui.mjs"], {
    DRAFT1_ENTRY: "/tests/fixtures/frame-probe.js",
  });
  run("zig", ["build"]);
  const output = run(process.execPath, ["tools/smoke-native.mjs", "--frames"]);
  console.log(
    output
      .split(/\r?\n/)
      .filter((line) =>
        /Native frame scheduling passed|Native application smoke completed/.test(
          line,
        ),
      )
      .join("\n"),
  );
} finally {
  run(process.execPath, ["tools/build-ui.mjs"], {
    DRAFT1_ENTRY: "/examples/css/app.js",
  });
  run("zig", ["build"]);
}
