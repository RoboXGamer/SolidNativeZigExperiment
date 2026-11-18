import assert from "node:assert/strict";
import { createSignal, flush } from "solid-js";
import * as renderer from "../packages/solid-zig/src/renderer.js";
import { mountApp } from "../packages/solid-zig/src/native.js";
let node, setStyle, setText;
mountApp(() => {
  const [style, writeStyle] = createSignal(
    { width: 120, backgroundColor: "red" },
    { ownedWrite: true },
  );
  const [text, writeText] = createSignal("Original", { ownedWrite: true });
  setStyle = writeStyle;
  setText = writeText;
  node = renderer.createElement("button");
  renderer.effect(style, (value) => {
    renderer.setProp(node, "style", value);
  });
  renderer.insert(node, text);
  return node;
});
flush();
const initial = JSON.parse(uiFrameChanges());
assert.ok(initial.nodes.length > 1);
uiCommit();
uiDispatchPointer(node.id, 0, 0);
let patch = JSON.parse(uiFrameChanges());
assert.equal(patch.nodes.length, 0);
assert.ok(patch.updates.length > 0);
assert.ok(
  patch.updates.every(
    (delta) => delta.interaction && !delta.layout && !delta.paint,
  ),
);
uiCommit();
setStyle({ width: 120, backgroundColor: "red", cursor: "pointer" });
flush();
patch = JSON.parse(uiFrameChanges());
assert.ok(
  patch.updates.some((delta) => delta.id === node.id && delta.interaction),
);
assert.ok(patch.updates.every((delta) => !delta.layout && !delta.paint));
uiCommit();
setStyle({ width: 120, backgroundColor: "blue", cursor: "pointer" });
flush();
patch = JSON.parse(uiFrameChanges());
assert.ok(patch.updates.some((delta) => delta.id === node.id && delta.paint));
assert.ok(patch.updates.every((delta) => !delta.layout));
uiCommit();
setStyle({ width: 180, backgroundColor: "blue", cursor: "pointer" });
setStyle({ width: 200, backgroundColor: "blue", cursor: "pointer" });
flush();
patch = JSON.parse(uiFrameChanges());
assert.equal(
  patch.updates.filter((delta) => delta.id === node.id).length,
  1,
  "writes coalesce by identity",
);
assert.equal(
  patch.updates.find((delta) => delta.id === node.id).layout.style.width,
  200,
);
uiCommit();
setText("Changed");
flush();
patch = JSON.parse(uiFrameChanges());
assert.ok(patch.updates.some((delta) => delta.layout?.text === "Changed"));
uiCommit();
assert.equal(JSON.parse(uiFrameChanges()).updates.length, 0);
uiDispose();
console.log(
  "PASS Solid signal updates preserve layout/paint/interaction phases, coalescing and acknowledgements across the native bridge",
);
