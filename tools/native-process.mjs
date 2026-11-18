import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { nativeEnv } from './hmr-session.mjs';

export function startNative(session) {
  if (!session) throw Error('A native HMR session is required; start pnpm dev or pass --session');
  return spawn("zig", ["build", "run", `-Dui-bundle=${session.bundle}`], {
    stdio: "inherit",
    cwd: fileURLToPath(new URL("../", import.meta.url)),
    env: { ...process.env, ...nativeEnv(session) },
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
