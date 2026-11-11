import * as solid from "solid-js";
import * as renderer from "../ui/renderer.js";

// The probe in features.js expects the same globals that mountApp() installs.
globalThis.__uiSolid = solid;
globalThis.__uiRenderer = renderer;
await import("../tests/features.js");

const deadline = Date.now() + 5000;
while (globalThis.__featureResult === "pending" || globalThis.__featureResult === undefined) {
  if (Date.now() > deadline) break;
  await new Promise(resolve => setTimeout(resolve, 10));
}
const result = globalThis.__featureResult;
if (result !== "passed") {
  console.error(`Solid API surface test failed: ${result}`);
  process.exit(1);
}
console.log("Solid API surface test passed");
