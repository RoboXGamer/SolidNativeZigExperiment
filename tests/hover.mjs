import assert from "node:assert/strict";
import { mkdtemp, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { compileCss } from "../tools/css-compiler.mjs";
import {
  setStyleSheet,
  clearStyleSheets,
  removeStyleSheet,
} from "../packages/solid-zig/src/stylesheets.js";
import * as renderer from "../packages/solid-zig/src/renderer.js";
import {
  mountApp,
  setEnvironmentVariable,
} from "../packages/solid-zig/src/native.js";

const dir = await mkdtemp(join(tmpdir(), "native-hover-"));
try {
  const file = join(dir, "hover.css");
  await writeFile(
    file,
    `:root { --pad: 12px; } .button {padding:var(--pad); color:red;} .button:hover {background-color:blue;} .button:hover + .sibling { color:green; } .button:active {opacity:0.5;} .static {padding:var(--pad);color:purple;} .static:hover {background-color:yellow;} .inherited {background-color:var(--missing, inherit);} .environment {width:env(safe-area-inset-left);}`,
  );
  setStyleSheet("hover", await compileCss(file, dir));
  let button, text, sibling, staticNode, inheritedNode;
  const events = [];
  function App() {
    const container = renderer.createElement("div");
    button = renderer.createElement("button", {
      class: "button",
      onHover: (value) => events.push(value),
    });
    text = renderer.createTextNode("Hover me");
    renderer.insertNode(button, text);
    sibling = renderer.createElement("label", { class: "sibling" });
    renderer.insertNode(sibling, renderer.createTextNode("Sibling"));
    staticNode = renderer.createElement("div", {
      class: "static environment",
    });
    inheritedNode = renderer.createElement("label", { class: "inherited" });
    renderer.insertNode(inheritedNode, renderer.createTextNode("Inherited"));
    renderer.insertNode(staticNode, inheritedNode);
    renderer.insertNode(container, button);
    renderer.insertNode(container, sibling);
    renderer.insertNode(container, staticNode);
    return container;
  }
  mountApp(App);
  await new Promise((resolve) => setTimeout(resolve, 10));
  const flatten = (tree) => [tree, ...tree.children.flatMap(flatten)];
  const nodes = () => flatten(JSON.parse(uiSnapshot()));
  uiFrameChanges();
  uiCommit();
  uiDispatchPointer(button.id, 0, 0);
  uiFrameChanges();
  uiCommit();
  assert.equal(
    nodes().find((n) => n.id === button.id).style.backgroundColor,
    "#00f",
  );
  assert.equal(
    nodes().find((n) => n.id === sibling.id).style.color,
    "green",
    "sibling selector invalidates without a global tree change",
  );
  uiDispatchPointer(text.id, text.id, button.id);
  uiFrameChanges();
  uiCommit();
  assert.equal(
    nodes().find((n) => n.id === button.id).style.backgroundColor,
    "#00f",
    "hover remains on parent when text is targeted",
  );
  assert.equal(
    nodes().find((n) => n.id === button.id).style.opacity,
    0.5,
    "active path includes parent",
  );
  assert.deepEqual(
    events,
    [true],
    "moving within a control does not emit leave/reenter",
  );
  uiDispatchPointer(sibling.id, 0, 0);
  uiFrameChanges();
  uiCommit();
  assert.deepEqual(events, [true, false]);
  assert.equal(
    nodes().find((n) => n.id === button.id).style.backgroundColor,
    "",
  );
  assert.notEqual(
    nodes().find((n) => n.id === sibling.id).style.color,
    "green",
  );
  setEnvironmentVariable("safe-area-inset-left", "23px");
  assert.equal(
    nodes().find((n) => n.id === staticNode.id).style.widthCss,
    "23px",
    "host environment changes invalidate cached snapshots",
  );
  uiDispatchPointer(text.id, 0, 0);
  uiFrameChanges();
  uiCommit();
  renderer.insertNode(staticNode, button);
  uiFrameChanges();
  uiCommit();
  assert.equal(
    nodes().find((n) => n.id === staticNode.id).hovered,
    true,
    "reparenting a stationary pointer target updates its ancestor path",
  );
  assert.equal(
    nodes().find((n) => n.id === inheritedNode.id).style.backgroundColor,
    "#ff0",
    "inherit from a var fallback responds to parent hover changes",
  );
  assert.equal(
    nodes().find((n) => n.id === inheritedNode.id).style.color,
    "purple",
  );
  uiDispatchPointer(0, 0, 0);
  uiFrameChanges();
  uiCommit();
  assert.equal(nodes().find((n) => n.id === staticNode.id).hovered, false);
  assert.notEqual(
    nodes().find((n) => n.id === inheritedNode.id).style.backgroundColor,
    "#ff0",
  );
  removeStyleSheet("hover");
  assert.equal(
    nodes().find((n) => n.id === staticNode.id).style.paddingTopCss,
    null,
    "removing the last stylesheet clears cached styles",
  );
  console.log(
    "PASS hover ancestry, active batching, sibling selectors and host invalidation",
  );
} finally {
  globalThis.uiDispose?.();
  clearStyleSheets();
  await rm(dir, { recursive: true, force: true });
}
