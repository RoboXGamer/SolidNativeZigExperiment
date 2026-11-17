import { copyFileSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawn, spawnSync } from "node:child_process";
import { projectRoot } from "./example-entry.mjs";

const source = join(projectRoot, "dist/SolidNative.exe");
const pe = readFileSync(source);
const header = pe.readUInt32LE(0x3c);
if (pe.toString("ascii", header, header + 4) !== "PE\0\0" ||
    pe.readUInt16LE(header + 24 + 68) !== 2)
  throw Error("Expected a Windows GUI executable");
const directory = mkdtempSync(join(tmpdir(), "solid-native-portable-"));
try {
  const executable = join(directory, "SolidNative.exe");
  copyFileSync(source, executable);
  const env = { ...process.env, SOLID_NATIVE_SMOKE: "1" };
  for (const name of ["DRAFT1_HMR", "SOLID_NATIVE_HOVER_SMOKE", "SOLID_NATIVE_FRAME_SMOKE", "SOLID_NATIVE_SCREENSHOT"])
    delete env[name];
  const result = spawnSync(executable, [], { cwd: directory, env, encoding: "utf8", timeout: 30000 });
  const output = (result.stdout ?? "") + (result.stderr ?? "");
  process.stdout.write(output);
  if (result.error || result.status !== 0 || !output.includes("Native application smoke completed:") || /\(err\)|ERROR:|Could not|failed:/i.test(output))
    throw result.error ?? Error(`Portable smoke failed (exit ${result.status})`);
  console.log("Portable GUI executable passed from an isolated folder containing only the EXE.");
  // Hidden smoke windows do not exercise Windows' visible-window refresh path.
  delete env.SOLID_NATIVE_SMOKE;
  const visible = spawn(executable, [], { cwd: directory, env });
  let visibleOutput = "";
  visible.stdout.on("data", data => { visibleOutput += data; });
  visible.stderr.on("data", data => { visibleOutput += data; });
  try {
    await new Promise((resolve, reject) => {
      const timer = setTimeout(resolve, 5000);
      visible.once("error", error => { clearTimeout(timer); reject(error); });
      visible.once("exit", code => {
        clearTimeout(timer);
        reject(Error(`Visible launch exited early (${code}): ${visibleOutput}`));
      });
    });
    const closed = new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(Error("Visible window did not close")), 10000);
      visible.once("exit", code => {
        clearTimeout(timer);
        if (code === 0) resolve();
        else reject(Error(`Visible launch failed (${code}): ${visibleOutput}`));
      });
    });
    const close = spawnSync("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command",
      `if (-not (Get-Process -Id ${visible.pid}).CloseMainWindow()) { exit 1 }`], { encoding: "utf8" });
    if (close.status !== 0) visible.kill();
    await closed;
    if (close.status !== 0) throw Error("Could not close the visible window normally");
    console.log("Visible portable window stayed open for 5 seconds and closed normally.");
  } finally {
    if (visible.exitCode === null) visible.kill();
  }
} finally {
  rmSync(directory, { recursive: true, force: true });
}
