import { createServer, build } from "vite";
import { transformAsync } from "@babel/core";
import commonjs from "@babel/plugin-transform-modules-commonjs";
import { writeFile, rename } from "node:fs/promises";
import { startNative, stopNative } from "./native-process.mjs";
import { fileURLToPath } from "node:url";
process.chdir(fileURLToPath(new URL("../", import.meta.url)));
const port = Number(process.env.DRAFT1_VITE_PORT || 5173);
const server = await createServer({ mode: "native-hmr", server: { host: "127.0.0.1", port, strictPort: true } });
await server.listen();
const origin = `http://127.0.0.1:${port}`;
const entry = process.env.DRAFT1_ENTRY || "/ui/app.js";
const clean = id => {
  const url = new URL(id, origin);
  url.searchParams.delete("t"); url.searchParams.delete("v");
  return url.pathname + url.search;
};
function external(id) {
  id = id.split("?")[0];
  if (id === "/ui/native.js" || id === "/packages/solid-zig/src/native.js") return "native-host";
  if (id === "/ui/renderer.js" || id === "/packages/solid-zig/src/renderer.js") return "native-renderer";
  if (/^\/node_modules\/\.vite\/deps\/solid-js_refresh\.js(?:\?|$)/.test(id)) return "solid-refresh";
  if (/^\/node_modules\/\.vite\/deps\/solid-js\.js(?:\?|$)/.test(id)) return "solid-js";
  // Unoptimized package paths must share the embedded Solid runtime too.
  if (/\/node_modules\/(?:\.pnpm\/[^/]+\/node_modules\/)?solid-js\/dist\/solid(?:\.dev)?\.js$/.test(id)) return "solid-js";
  if (/\/node_modules\/(?:\.pnpm\/[^/]+\/node_modules\/)?solid-js\/dist\/refresh(?:\.dev)?\.js$/.test(id)) return "solid-refresh";
  return null;
}
async function compileGraph() {
  const graph = {};
  const visiting = new Set();
  async function visit(id) {
    id = clean(id);
    if (visiting.has(id)) return;
    visiting.add(id);
    const response = await fetch(`${origin}${id}`);
    if (!response.ok) throw Error(`Vite transform failed: ${id} (${response.status})`);
    const source = await response.text();
    const dependencies = new Set();
    const rewrite = () => ({ visitor: {
      ImportDeclaration(path) {
        const value = path.node.source.value;
        if (value === "/@vite/client") { path.remove(); return; }
        const dependency = clean(new URL(value, origin + id).href);
        path.node.source.value = external(dependency) || dependency;
        if (!external(dependency)) dependencies.add(dependency);
      },
      ExportNamedDeclaration(path) {
        if (path.node.source) {
          const dependency = clean(new URL(path.node.source.value, origin + id).href);
          path.node.source.value = external(dependency) || dependency;
          if (!external(dependency)) dependencies.add(dependency);
        }
      },
      ExportAllDeclaration(path) {
        const dependency = clean(new URL(path.node.source.value, origin + id).href);
        path.node.source.value = external(dependency) || dependency;
        if (!external(dependency)) dependencies.add(dependency);
      },
      ExpressionStatement(path) {
        const e = path.node.expression;
        if (e.type === "AssignmentExpression" && e.right.type === "CallExpression" && e.right.callee.name === "__vite__createHotContext") path.remove();
      },
      MetaProperty(path) {
        if (path.node.meta.name === "import") path.replaceWith({ type: "Identifier", name: "__meta" });
      },
      ImportExpression(path) {
        if (path.node.source.type !== "StringLiteral") throw path.buildCodeFrameError("Native dynamic imports must use a literal module path");
        const dependency = clean(new URL(path.node.source.value, origin + id).href);
        const target = external(dependency) || dependency;
        if (!external(dependency)) dependencies.add(dependency);
        path.replaceWith({ type: "CallExpression", callee: { type: "MemberExpression", object: { type: "Identifier", name: "__meta" }, property: { type: "Identifier", name: "import" }, computed: false }, arguments: [{ type: "StringLiteral", value: target }] });
      },
    } });
    const result = await transformAsync(source, { filename: id, configFile: false, babelrc: false, sourceType: "module", plugins: [rewrite, commonjs], comments: false });
    graph[id] = result.code;
    await Promise.all([...dependencies].map(visit));
  }
  await visit(entry);
  return graph;
}
async function publish() {
  const graph = await compileGraph();
  await writeFile("src/ui-hmr.tmp", `globalThis.__uiModules.apply(${JSON.stringify(graph)}, ${JSON.stringify(entry)});\n`, "utf8");
  await rename("src/ui-hmr.tmp", "src/ui-hmr.js");
  console.log(`[native-hmr] published ${Object.keys(graph).length} application modules`);
}
let pending = Promise.resolve();
let child;
let stopping = false;
const ws = new WebSocket(`ws://127.0.0.1:${port}/?token=${encodeURIComponent(server.config.webSocketToken)}`, "vite-hmr");
await new Promise((resolve, reject) => {
  ws.addEventListener("open", resolve, { once: true });
  ws.addEventListener("error", reject, { once: true });
});
ws.addEventListener("message", event => {
  if (stopping) return;
  let message;
  try { message = JSON.parse(event.data); } catch { return; }
  if (message.type === "update" || message.type === "full-reload") pending = pending.then(publish).catch(error => console.error("[native-hmr]", error.message));
  if (message.type === "error") console.error("[vite]", message.err?.message);
});
ws.addEventListener("error", () => console.error("[native-hmr] websocket error"));
async function stop(code = 0) {
  if (stopping) return;
  stopping = true;
  await stopNative(child);
  ws.close();
  await pending.catch(() => {});
  await server.close();
  process.exitCode = typeof code === "number" ? code : 0;
}
process.on("SIGINT", stop);
process.on("SIGTERM", stop);
try {
  await (pending = pending.then(publish));
  if (process.argv.includes("--app")) {
    await build({ mode: "native-hmr" });
    if (!stopping) {
      child = startNative();
      child.on("error", error => { console.error(error); void stop(1); });
      child.on("exit", code => void stop(code ?? 1));
    }
  } else console.log("[native-hmr] connected; run pnpm dev:app in another terminal");
} catch (error) { console.error(error); await stop(1); }
