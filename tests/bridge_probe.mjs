import assert from "node:assert/strict";

// `native.js` reads the Vite define as a bare identifier; provide it for Node.
globalThis.__NATIVE_HMR__ = false;
const { mountApp } = await import("../ui/native.js");
const renderer = await import("../ui/renderer.js");

// Regression guard: the JS bridge must emit a display/flexDirection pair whose
// axis matches how heights are resolved. Containers defaulted to `display:
// block` while `flexDirection` defaulted to `row`, so a label's height was
// computed as a row but its children were stacked as a column — text siblings
// overflowed the label and overlapped the next row.
const label = renderer.createElement("label");
renderer.insert(label, "Loading states: ");
renderer.insert(label, "no");

const column = renderer.createElement("column");
renderer.insert(column, renderer.createElement("button"));

const row = renderer.createElement("row");
renderer.insert(row, "a");

const text = renderer.createTextNode("plain");

mountApp(() => {
  const root = renderer.node("root");
  renderer.insert(root, label);
  renderer.insert(root, column);
  renderer.insert(root, row);
  renderer.insert(root, text);
  return root;
});

const tree = JSON.parse(globalThis.uiSnapshot());

function find(node, type) {
  if (node.type === type) return node;
  for (const child of node.children ?? []) {
    const hit = find(child, type);
    if (hit) return hit;
  }
  return null;
}

assert.equal(find(tree, "label").style.display, "flex", "labels are flex containers");
assert.equal(find(tree, "label").style.flexDirection, "row", "labels lay their text out inline");

assert.equal(find(tree, "column").style.display, "flex");
assert.equal(find(tree, "column").style.flexDirection, "column", "column stacks on the main axis");

assert.equal(find(tree, "row").style.flexDirection, "row");

assert.equal(find(tree, "text").style.display, "block", "text nodes stay block leaves");

console.log("JS bridge display/flexDirection defaults test passed");
