import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

export function startNative() {
  return spawn("zig", ["build", "run"], {
    stdio: "inherit",
    cwd: fileURLToPath(new URL("../", import.meta.url)),
    env: { ...process.env, DRAFT1_HMR: "1" },
  });
}

export async function stopNative(child) {
  if (!child?.pid || child.exitCode !== null || child.signalCode !== null) return;
  if (process.platform === "win32") {
    // Zig starts the executable as a descendant. Stop only this owned tree.
    await new Promise(resolve => {
      const stop = spawn("taskkill", ["/PID", String(child.pid), "/T", "/F"], {
        stdio: "ignore", windowsHide: true,
      });
      stop.once("error", resolve);
      stop.once("exit", resolve);
    });
  } else child.kill("SIGTERM");
}
