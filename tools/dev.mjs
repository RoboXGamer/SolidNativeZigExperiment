import { createServer } from "vite";
import { transformAsync } from "@babel/core";
import commonjs from "@babel/plugin-transform-modules-commonjs";
import { writeFile, rename } from "node:fs/promises";
const port = Number(process.env.DRAFT1_VITE_PORT || 5173);
const server = await createServer({ server: { host: "127.0.0.1", port, strictPort: true } });
await server.listen();
const origin = `http://127.0.0.1:${port}`;
const entry = "/ui/app.js";
const clean = id => id.split("?")[0];
function external(id) {
  if (id === "/ui/native.js" || id === "/packages/solid-zig/src/native.js") return "native-host";
  if (id === "/ui/renderer.js" || id === "/packages/solid-zig/src/renderer.js") return "native-renderer";
  if (id.includes("solid-js_refresh")) return "solid-refresh";
  if (id.includes("solid-js.js")) return "solid-js";
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
        const dependency = clean(value);
        path.node.source.value = external(dependency) || dependency;
        if (!external(dependency)) dependencies.add(dependency);
      },
      ExportNamedDeclaration(path) {
        if (path.node.source) {
          const dependency = clean(path.node.source.value);
          path.node.source.value = external(dependency) || dependency;
          if (!external(dependency)) dependencies.add(dependency);
        }
      },
      ExpressionStatement(path) {
        const e = path.node.expression;
        if (e.type === "AssignmentExpression" && e.right.type === "CallExpression" && e.right.callee.name === "__vite__createHotContext") path.remove();
      },
      MetaProperty(path) { path.replaceWith({ type: "Identifier", name: "__meta" }); },
      ImportExpression(path) {
        if (path.node.source.type !== "StringLiteral") throw path.buildCodeFrameError("Native dynamic imports must use a literal module path");
        const dependency = clean(new URL(path.node.source.value, origin + id).pathname);
        dependencies.add(dependency);
        path.replaceWith({ type: "CallExpression", callee: { type: "MemberExpression", object: { type: "Identifier", name: "__meta" }, property: { type: "Identifier", name: "import" }, computed: false }, arguments: [{ type: "StringLiteral", value: dependency }] });
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
await publish();
const ws = new WebSocket(`ws://127.0.0.1:${port}/?token=${encodeURIComponent(server.config.webSocketToken)}`, "vite-hmr");
ws.addEventListener("open", () => console.log("[native-hmr] connected; run pnpm dev:app"));
ws.addEventListener("message", event => {
  const message = JSON.parse(event.data);
  if (message.type === "update" || message.type === "full-reload") pending = pending.then(publish).catch(error => console.error("[native-hmr]", error.message));
  if (message.type === "error") console.error("[vite]", message.err?.message);
});
ws.addEventListener("error", () => console.error("[native-hmr] websocket error"));
async function stop() { ws.close(); await server.close(); process.exit(); }
process.on("SIGINT", stop);
process.on("SIGTERM", stop);
