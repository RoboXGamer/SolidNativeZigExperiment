import assert from "node:assert/strict";
import { createSignal, createComponent, onCleanup } from "solid-js";
import { $$registry, $$component, $$refresh } from "solid-js/refresh";
import { node, render, createElement, createTextNode, insertNode } from "../ui/renderer.js";

const hot = { data: {}, accept(fn) { this.callback = fn; }, invalidate() { throw Error("Unexpected invalidation"); } };
const [parentCount, setParentCount] = createSignal(0);
let setLocal, readLocal;
let cleanups = 0;
function component(text) {
  return function Counter() {
    const [local, set] = createSignal(0);
    setLocal = set;
    readLocal = local;
    onCleanup(() => cleanups++);
    const label = createElement("label");
    insertNode(label, createTextNode(text));
    return label;
  };
}
const first = $$registry();
const Counter = $$component(first, "Counter", component("old"));
$$refresh("vite", hot, first);
const root = node("root");
const dispose = render(() => createComponent(Counter, {}), root);
assert.equal(root.children[0].children[0].text, "old");
setParentCount(7);
setLocal(5);
const second = $$registry();
$$component(second, "Counter", component("new"));
const acceptPrevious = hot.callback;
$$refresh("vite", hot, second);
acceptPrevious({});
await Promise.resolve();
assert.equal(root.children[0].children[0].text, "new");
assert.equal(parentCount(), 7, "unrelated signal survives component refresh");
assert.equal(readLocal(), 0, "local signal resets when its component is replaced");
assert.equal(cleanups, 1, "old component is disposed during refresh");
dispose();
assert.equal(cleanups, 2, "new component is disposed when its root is disposed");
console.log("Solid Refresh universal renderer smoke test passed");
