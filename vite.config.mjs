import { defineConfig } from "vite";
import solid from "@solidjs/vite-plugin";

export default defineConfig(({ mode }) => ({
  plugins: [solid({ solid: { generate: "universal", moduleName: "./renderer.js" }, performanceTracks: false })],
  define: { __NATIVE_HMR__: JSON.stringify(mode === "native-hmr") },
  resolve: mode === "native-hmr" ? { conditions: ["development", "browser"] } : {},
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
