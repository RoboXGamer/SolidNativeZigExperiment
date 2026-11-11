import { createSignal } from "solid-js";
import * as renderer from "./renderer.js";
import { Counter } from "./counter.jsx";

let root = renderer.node("root");
const [count, setCount] = createSignal(0);
let button, dispose;
const props = {
  count,
  onClick: () => setCount(count() + 1),
  buttonRef: (n) => {
    button = n;
  },
};
function mount(Component) {
  const nextRoot = renderer.node("root");
  const previousButton = button;
  let nextDispose;
  try {
    nextDispose = renderer.render(
      () => renderer.createComponent(Component, props),
      nextRoot,
    );
  } catch (error) {
    button = previousButton;
    throw error;
  }
  if (dispose) dispose();
  root = nextRoot;
  dispose = nextDispose;
}
globalThis.__uiRenderer = renderer;
globalThis.__applyCounter = mount;
mount(Counter);
globalThis.uiLabel = () =>
  root.children[0].children[0].children.map((n) => n.text).join("");
globalThis.uiButton = () => button.children.map((n) => n.text).join("");
globalThis.uiClick = () => button.props.onClick();
globalThis.uiReset = () => setCount(0);
globalThis.uiGetCount = count;
globalThis.uiSetCount = setCount;
