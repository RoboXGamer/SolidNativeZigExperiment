import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { readFile, writeFile, rm } from "node:fs/promises";
import vm from "node:vm";
import * as solid from "solid-js";
import * as refresh from "solid-js/refresh";
import * as native from "../packages/solid-zig/src/native.js";
import * as renderer from "../packages/solid-zig/src/renderer.js";
import { createModuleHost } from "../packages/solid-zig/src/module-runtime.js";
const cssFile = new URL("../ui/styles/theme/base.css", import.meta.url);
const original = await readFile(cssFile, "utf8");
const child = spawn(process.execPath, ["tools/dev.mjs"], {
  env: { ...process.env, DRAFT1_VITE_PORT: "5187" },
  stdio: ["ignore", "pipe", "pipe"],
});
let output = "",
  publications = 0;
const waiters = [];
function log(chunk) {
  output += chunk;
  publications = (output.match(/\[native-hmr\] published/g) || []).length;
  for (const waiter of [...waiters])
    if (publications >= waiter.count) waiter.resolve();
}
child.stdout.on("data", log);
child.stderr.on("data", log);
function published(count) {
  return new Promise((resolve, reject) => {
    if (publications >= count) return resolve();
    const timer = setTimeout(
      () => reject(Error("Native dev publish timed out: " + output)),
      45000,
    );
    waiters.push({
      count,
      resolve: () => {
        clearTimeout(timer);
        resolve();
      },
    });
  });
}
const host = createModuleHost({
  "solid-js": solid,
  "solid-refresh": refresh,
  "native-renderer": renderer,
  "native-host": native,
});
async function apply() {
  vm.runInNewContext(await readFile("src/ui-hmr.js", "utf8"), {
    globalThis: { __uiModules: host },
  });
  await new Promise((resolve) => setTimeout(resolve, 10));
  return globalThis.uiSnapshot();
}
try {
  await published(1);
  let tree = await apply();
  assert.match(tree, /data:image\/png;base64/);
  const nodes = [];
  const visit = (n) => {
    nodes.push(n);
    n.children.forEach(visit);
  };
  visit(JSON.parse(tree));
  globalThis.uiDispatchClick(nodes.find((n) => n.type === "button").id);
  await new Promise((resolve) => setTimeout(resolve, 10));
  assert.match(globalThis.uiSnapshot(), /#24554c/);
  await writeFile(
    cssFile,
    original + "\n#css-demo .description { color: #ff00ff; }\n",
  );
  await published(2);
  tree = await apply();
  assert.match(tree, /#f0f/);
  assert.match(tree, /#24554c/, "CSS HMR preserves component state");
  await writeFile(cssFile, original);
  await published(3);
  tree = await apply();
  assert.doesNotMatch(tree, /#f0f/);
  if (process.env.CSS_NATIVE_SMOKE) {
    const smoke = spawnSync(process.execPath, ["tools/smoke-native.mjs"], {
      encoding: "utf8",
      env: { ...process.env, DRAFT1_HMR: "1" },
      timeout: 25000,
    });
    assert.equal(smoke.status, 0, smoke.stdout + smoke.stderr);
    console.log(
      "PASS QuickJS native executable loaded the actual Vite development graph",
    );
  }
  console.log(
    "PASS actual native Vite development graph: nested @import update/removal and CSS HMR preserves reactive component state",
  );
} finally {
  child.kill();
  await writeFile(cssFile, original);
  host.dispose();
  globalThis.uiDispose?.();
  await rm("src/ui-hmr.js", { force: true });
}
