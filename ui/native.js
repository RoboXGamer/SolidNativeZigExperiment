import * as solid from "solid-js";
import * as refresh from "solid-js/refresh";
import * as renderer from "./renderer.js";

let root = renderer.node("root");
let dispose;

function mount(Component) {
  const nextRoot = renderer.node("root");
  const nextDispose = renderer.render(() => renderer.createComponent(Component, {}), nextRoot);
  if (dispose) dispose();
  root = nextRoot;
  dispose = nextDispose;
}

function find(node, type) {
  if (node.type === type) return node;
  for (const child of node.children) {
    const match = find(child, type);
    if (match) return match;
  }
}
function text(node) {
  return node.text + node.children.map(text).join("");
}

export function mountApp(Component) {
  globalThis.__uiRenderer = renderer;
  globalThis.__uiSolid = solid;
  if (__NATIVE_HMR__) {
    const hot = {
      data: {},
      accept(callback) { if (typeof callback === "function") this.callback = callback; },
      invalidate() { throw new Error("Solid Refresh requested a full app restart"); },
    };
    const registry = refresh.$$registry();
    Component = refresh.$$component(registry, "Counter", Component);
    refresh.$$refresh("vite", hot, registry);
    globalThis.__uiRefresh = refresh;
    globalThis.__uiHot = hot;
  }
  globalThis.uiLabel = () => text(find(root, "label"));
  globalThis.uiButton = () => text(find(root, "button"));
  globalThis.uiClick = () => find(root, "button").props.onClick();
  mount(Component);
}
