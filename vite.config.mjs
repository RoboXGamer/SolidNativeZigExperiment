import { defineConfig } from "vite";
import solid from "@solidjs/vite-plugin";
import { fileURLToPath } from "node:url";

export default defineConfig(({ mode }) => ({
  plugins: [solid({ solid: { generate: "universal", moduleName: "@zig-ui/solid/renderer" }, performanceTracks: false })],
  define: { __NATIVE_HMR__: JSON.stringify(mode === "native-hmr") },
  resolve: {
    ...(mode === "native-hmr" ? { conditions: ["development", "browser"] } : {}),
    alias: [
      { find: /^@zig-ui\/solid\/renderer$/, replacement: fileURLToPath(new URL("./packages/solid-zig/src/renderer.js", import.meta.url)) },
      { find: /^@zig-ui\/solid$/, replacement: fileURLToPath(new URL("./packages/solid-zig/src/native.js", import.meta.url)) },
    ],
  },
  optimizeDeps: { noDiscovery: true, include: [] },
  build: {
    outDir: "src",
    emptyOutDir: false,
    minify: false,
    lib: {
      entry: "ui/app.js",
      name: "SolidNativeExperiment",
      formats: ["iife"],
      fileName: () => "ui-bundle.js",
    },
  },
}));
