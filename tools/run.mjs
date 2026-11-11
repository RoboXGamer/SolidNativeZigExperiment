import { spawn } from "node:child_process";

const child = spawn("zig", ["build", "run"], {
  stdio: "inherit",
  env: { ...process.env, DRAFT1_HMR: "1" },
});
child.on("error", error => { console.error(error); process.exitCode = 1; });
child.on("exit", (code, signal) => { process.exitCode = code ?? (signal ? 1 : 0); });
