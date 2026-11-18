import { resolve, dirname } from "node:path";
import { compileCss } from "./css-compiler.mjs";
const prefix = "\0native-css:";
const idFor = (file) =>
  prefix + Buffer.from(file).toString("base64url") + ".js";
export default function nativeCss() {
  const dependencies = new Map();
  let root;
  return {
    name: "solid-zig-css",
    enforce: "pre",
    configResolved(config) {
      root = config.root;
    },
    async resolveId(source, importer) {
      if (!/\.css(?:\?|$)/i.test(source) || !importer) return;
      if (source.includes("?"))
        throw Error("Native CSS imports do not accept query suffixes");
      const resolved = await this.resolve(source, importer, { skipSelf: true });
      const file = resolved?.id || resolve(dirname(importer), source);
      return idFor(file);
    },
    async load(id) {
      if (!id.startsWith(prefix)) return;
      const file = Buffer.from(
        id.slice(prefix.length, -3),
        "base64url",
      ).toString();
      const watched = new Set();
      dependencies.delete(id);
      const rules = await compileCss(file, root, (path) => {
        watched.add(path.replaceAll("\\", "/"));
        this.addWatchFile(path);
      });
      dependencies.set(id, watched);
      return `import { setStyleSheet, removeStyleSheet } from '@zig-ui/solid';\nsetStyleSheet(${JSON.stringify(file)}, ${JSON.stringify(rules)});\nif(import.meta.hot){import.meta.hot.styleSheet(${JSON.stringify(file)});import.meta.hot.accept();import.meta.hot.dispose(()=>removeStyleSheet(${JSON.stringify(file)}));}`;
    },
    handleHotUpdate(ctx) {
      const modules = [];
      for (const [id, files] of dependencies) {
        if (!ctx.server.environments.client.moduleGraph.getModuleById(id)) { dependencies.delete(id); continue; }
        if (files.has(ctx.file.replaceAll("\\", "/"))) {
          const mod =
            ctx.server.environments.client.moduleGraph.getModuleById(id);
          if (mod) {
            ctx.server.environments.client.moduleGraph.invalidateModule(mod);
            modules.push(mod);
          }
        }
      }
      if (modules.length)
        ctx.server.ws.send({ type: "custom", event: "native:css" });
      return modules.length ? modules : undefined;
    },
    closeBundle() { dependencies.clear(); },
  };
}
