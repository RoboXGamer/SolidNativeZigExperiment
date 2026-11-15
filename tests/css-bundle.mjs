import { readFileSync } from "node:fs";
import vm from "node:vm";
import assert from "node:assert/strict";
const context = vm.createContext({
  console,
  performance,
  queueMicrotask,
  setTimeout,
  clearTimeout,
  setInterval,
  clearInterval,
});
vm.runInContext(readFileSync("src/ui-bundle.js", "utf8"), context, {
  timeout: 10000,
});
await new Promise((resolve) => setTimeout(resolve, 10));
const tree = JSON.parse(
  vm.runInContext("uiSnapshot()", context, { timeout: 10000 }),
);
const nodes = [];
const visit = (n) => {
  nodes.push(n);
  n.children.forEach(visit);
};
visit(tree);
assert.ok(
  nodes.some((n) => n.style.backgroundImage.includes("data:image/png;base64")),
);
const button = nodes.find((n) => n.type === "button");
vm.runInContext(`uiDispatchClick(${button.id})`, context);
await new Promise((resolve) => setTimeout(resolve, 10));
assert.match(
  vm.runInContext("uiSnapshot()", context, { timeout: 10000 }),
  /#24554c/,
);
console.log(
  "PASS production CSS demo bundle: native snapshot contains image bytes and reactive class changes",
);
vm.runInContext("uiDispose()", context);
