import { defineConfig } from "vite";
import solid from "@solidjs/vite-plugin";

export default defineConfig({
  plugins: [solid({ solid: { generate: "universal", moduleName: "./renderer.js" }, performanceTracks: false, refresh: { disabled: true } })],
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
});
