import { createServer } from "vite";
import { writeFile, rename } from "node:fs/promises";

const server = await createServer({ server: { host: "127.0.0.1", port: 5173, strictPort: true } });
await server.listen();
const url = "http://127.0.0.1:5173";
const counterPath = "/ui/counter.jsx";
let pending = Promise.resolve();

async function loadCounter() {
  const response = await fetch(`${url}${counterPath}?t=${Date.now()}`);
  if (!response.ok) throw new Error(`Vite transform: HTTP ${response.status}`);
  let code = await response.text();
  code = code.replace(/^import \{ createHotContext as __vite__createHotContext \} from "\/@vite\/client";import\.meta\.hot = __vite__createHotContext\("[^"]+"\);/, "");
  code = code.replace(/import \{ ([\w$]+) as ([\w$]+) \} from "\/ui\/renderer\.js";/g, "const $2 = globalThis.__uiRenderer.$1;");
  code = code.replace(/export function Counter\(/, "function Counter(");
  code = code.replace(/if \(import\.meta\.hot\) import\.meta\.hot\.accept\(\);/, "");
  code = code.replace(/\/\/# sourceMappingURL=.*$/m, "");
  if (/\b(?:import|export)\s/.test(code) || !/function Counter\(/.test(code)) {
    throw new Error("Unsupported component imports/exports; restart the app after changing its module dependencies");
  }
  const patch = `(function () {\n${code}\n globalThis.__applyCounter(Counter);\n})();\n`;
  await writeFile("src/ui-hmr.tmp", patch, "utf8");
  await rename("src/ui-hmr.tmp", "src/ui-hmr.js");
  console.log("[native-hmr] sent Counter update to QuickJS");
}

// Load once so Vite's module graph knows the explicit accept boundary.
await fetch(`${url}${counterPath}`);
const token = server.config.webSocketToken;
const ws = new WebSocket(`ws://127.0.0.1:5173/?token=${encodeURIComponent(token)}`, "vite-hmr");
ws.addEventListener("open", () => console.log("[native-hmr] connected to Vite; run zig build run in another terminal"));
ws.addEventListener("message", event => {
  const message = JSON.parse(event.data);
  if (message.type === "update" && message.updates.some(u => u.path === counterPath || u.acceptedPath === counterPath)) {
    pending = pending.then(loadCounter).catch(error => console.error("[native-hmr]", error.message));
  } else if (message.type === "error") {
    console.error("[vite]", message.err?.message || "transform failed");
  } else if (message.type === "full-reload") {
    console.warn("[native-hmr] Vite requested a full reload; rebuild UI and restart Zig for changes outside Counter");
  }
});
ws.addEventListener("error", () => console.error("[native-hmr] Vite websocket error"));
async function stop() { ws.close(); await server.close(); process.exit(); }
process.on("SIGINT", stop);
process.on("SIGTERM", stop);
