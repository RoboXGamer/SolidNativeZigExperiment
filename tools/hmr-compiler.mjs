import { transformAsync } from "@babel/core";
import commonjs from "@babel/plugin-transform-modules-commonjs";
export const clean = (id, origin) => {
  const url = new URL(id, origin);
  url.searchParams.delete("t"); url.searchParams.delete("v");
  return url.pathname + url.search;
};
export function external(id) {
  id = id.split("?")[0];
  if (id === "/packages/solid-zig/src/native.js") return "native-host";
  if (id === "/packages/solid-zig/src/renderer.js") return "native-renderer";
  if (/^\/node_modules\/\.vite\/deps\/solid-js_refresh\.js(?:\?|$)/.test(id)) return "solid-refresh";
  if (/^\/node_modules\/\.vite\/deps\/solid-js\.js(?:\?|$)/.test(id)) return "solid-js";
  // Unoptimized package paths must share the embedded Solid runtime too.
  if (/\/node_modules\/(?:\.pnpm\/[^/]+\/node_modules\/)?solid-js\/dist\/solid(?:\.dev)?\.js$/.test(id)) return "solid-js";
  if (/\/node_modules\/(?:\.pnpm\/[^/]+\/node_modules\/)?solid-js\/dist\/refresh(?:\.dev)?\.js$/.test(id)) return "solid-refresh";
  if (/\/packages\/solid-zig\/src\//.test(id) || /\/node_modules\/(?:\.pnpm\/[^/]+\/node_modules\/)?(?:solid-js|@solidjs)\//.test(id))
    throw Error(`Unsupported embedded runtime import: ${id}; import solid-js, solid-js/refresh or @zig-ui/solid instead`);
  return null;
}
export async function compileGraph({ origin, entry, signal = AbortSignal.timeout(10000), generation = () => 0 }) {
  const started = generation();
  const graph = {};
  const visiting = new Set();
  let bytes = 0;
  async function visit(id) {
    signal?.throwIfAborted();
    id = clean(id, origin);
    if (visiting.has(id)) return;
    visiting.add(id);
    if (visiting.size > 1024) throw Error('Native graph exceeds 1024 modules');
    const response = await fetch(`${origin}${id}`, { signal });
    if (!response.ok) throw Error(`Vite transform failed: ${id} (${response.status})`);
    const source = await response.text();
    bytes += Buffer.byteLength(source);
    if (bytes > 24 * 1024 * 1024) throw Error('Native graph exceeds 24 MiB source budget');
    const dependencies = new Set();
    const rewrite = () => ({ visitor: {
      AwaitExpression(path) { if (!path.getFunctionParent()) throw path.buildCodeFrameError('Native modules do not support top-level await'); },
      ImportDeclaration(path) {
        const value = path.node.source.value;
        if (value === "/@vite/client") { path.remove(); return; }
        const dependency = clean(new URL(value, origin + id).href, origin);
        path.node.source.value = external(dependency) || dependency;
        if (!external(dependency)) dependencies.add(dependency);
      },
      ExportNamedDeclaration(path) {
        if (path.node.source) {
          const dependency = clean(new URL(path.node.source.value, origin + id).href, origin);
          path.node.source.value = external(dependency) || dependency;
          if (!external(dependency)) dependencies.add(dependency);
        }
      },
      ExportAllDeclaration(path) {
        const dependency = clean(new URL(path.node.source.value, origin + id).href, origin);
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
        const dependency = clean(new URL(path.node.source.value, origin + id).href, origin);
        const target = external(dependency) || dependency;
        if (!external(dependency)) dependencies.add(dependency);
        path.replaceWith({ type: "CallExpression", callee: { type: "MemberExpression", object: { type: "Identifier", name: "__meta" }, property: { type: "Identifier", name: "import" }, computed: false }, arguments: [{ type: "StringLiteral", value: target }] });
      },
    } });
    const result = await transformAsync(source, { filename: id, configFile: false, babelrc: false, sourceType: "module", plugins: [rewrite, commonjs], comments: false });
    graph[id] = result.code;
    for (const dependency of dependencies) await visit(dependency);
  }
  await visit(entry);
  signal?.throwIfAborted();
  if (generation() !== started) throw Error('Source generation changed during graph compilation');
  return graph;
}

