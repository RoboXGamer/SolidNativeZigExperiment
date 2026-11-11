import assert from "node:assert/strict";
import { createRoot, createSignal, createComponent, For, Show, flush } from "solid-js";
import * as renderer from "../ui/renderer.js";

createRoot(dispose => {
  const [items, setItems] = createSignal(["A", "B", "C"], { ownedWrite: true });
  const [visible, setVisible] = createSignal(true, { ownedWrite: true });
  const container = renderer.createElement("column");
  renderer.insert(container, () => createComponent(Show, {
    get when() { return visible(); },
    get children() {
      return createComponent(For, {
        get each() { return items(); },
        children(item) {
          const label = renderer.createElement("label");
          renderer.insert(label, item);
          return label;
        },
      });
    },
  }));
  flush();
  const names = () => container.children.filter(node => node.type === "label").map(node => node.children.map(c => c.text).join(""));
  assert.deepEqual(names(), ["A", "B", "C"]);
  setItems(["C", "A", "D"]);
  flush();
  assert.deepEqual(names(), ["C", "A", "D"]);
  setVisible(false);
  flush();
  assert.deepEqual(names(), []);
  setVisible(true);
  flush();
  assert.deepEqual(names(), ["C", "A", "D"]);
  dispose();
});
console.log("Solid renderer tree and control-flow test passed");
