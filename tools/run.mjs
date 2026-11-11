import { startNative, stopNative } from "./native-process.mjs";

const child = startNative();
child.on("error", error => { console.error(error); process.exitCode = 1; });
child.on("exit", (code, signal) => { process.exitCode = code ?? (signal ? 1 : 0); });
process.on("SIGINT", () => void stopNative(child));
process.on("SIGTERM", () => void stopNative(child));
