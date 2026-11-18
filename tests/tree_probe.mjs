import assert from "node:assert/strict";
import { createRoot, createSignal, createComponent, Show, flush } from "solid-js";
import * as renderer from "../packages/solid-zig/src/renderer.js";

createRoot(dispose => {
  const [value, setValue] = createSignal("before", { ownedWrite: true });
  const [visible, setVisible] = createSignal(true, { ownedWrite: true });
  const container = renderer.createElement("div");
  renderer.insert(container, () => createComponent(Show, {
    get when() { return visible(); },
    get children() {
      const label = renderer.createElement("label");
      renderer.insert(label, value);
      return label;
    },
  }));
  flush();
  const text = () => container.children.filter(node => node.type === "label").map(node => node.children.map(c => c.text).join(""));
  assert.deepEqual(text(), ["before"]);
  setVisible(false);
  flush();
  assert.deepEqual(text(), []);
  setValue("after");
  flush();
  assert.deepEqual(text(), [], "hidden content stays absent when its value changes");
  setVisible(true);
  flush();
  assert.deepEqual(text(), ["after"], "showing content renders its current value");
  dispose();
});
console.log("Solid renderer tree and control-flow test passed");
