import assert from "node:assert/strict";

// `native.js` reads the Vite define as a bare identifier; provide it for Node.
globalThis.__NATIVE_HMR__ = false;
const { mountApp } = await import("../packages/solid-zig/src/native.js");
const renderer = await import("../packages/solid-zig/src/renderer.js");

// Regression guard: the JS bridge must emit a display/flexDirection pair whose
// axis matches how heights are resolved. Containers defaulted to `display:
// block` while `flexDirection` defaulted to `row`, so a label's height was
// computed as a row but its children were stacked as a column — text siblings
// overflowed the label and overlapped the next row.
const label = renderer.createElement("label");
renderer.insert(label, "Loading states: ");
renderer.insert(label, "no");

const column = renderer.createElement("div", { style: { display: "flex", flexDirection: "column" } });
renderer.insert(column, renderer.createElement("button"));

const row = renderer.createElement("div", { style: { display: "flex", flexDirection: "row" } });
renderer.insert(row, "a");

const text = renderer.createTextNode("plain");
const block = renderer.createElement("div");
const grid = renderer.createElement("div", { style: { display: "grid" } });
const defaultFlex = renderer.createElement("div", { style: { display: "flex" } });
const trackedGrid = renderer.createElement("div", { style: { display: "grid", gridTemplateColumns: "100px 1fr" } });

mountApp(() => {
  const root = renderer.node("root");
  renderer.insert(root, label);
  renderer.insert(root, column);
  renderer.insert(root, row);
  renderer.insert(root, text);
  renderer.insert(root, block);
  renderer.insert(root, grid);
  renderer.insert(root, defaultFlex);
  renderer.insert(root, trackedGrid);
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

const nodes = [];
function visit(node) { nodes.push(node); for (const child of node.children) visit(child); }
visit(tree);
assert.equal(nodes.find(n => n.id === block.id).style.display, "block");
assert.equal(nodes.find(n => n.id === column.id).style.display, "flex");
assert.equal(nodes.find(n => n.id === column.id).style.flexDirection, "column");
assert.equal(nodes.find(n => n.id === row.id).style.flexDirection, "row");
assert.equal(nodes.find(n => n.id === grid.id).style.display, "grid");
assert.equal(nodes.find(n => n.id === defaultFlex.id).style.flexDirection, "row");
assert.equal(nodes.find(n => n.id === trackedGrid.id).style.gridTemplateColumnsCss, "100px 1fr");

assert.equal(find(tree, "text").style.display, "block", "text nodes stay block leaves");

console.log("JS bridge display/flexDirection defaults test passed");
