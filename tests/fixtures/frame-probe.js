import { mountApp, findById } from "@zig-ui/solid";
import * as renderer from "../../packages/solid-zig/src/renderer.js";
import App from "../../examples/css/App.jsx";
mountApp(App);
let button;
globalThis.uiFrameProbe = (step) => {
  if (!button) {
    const flatten = (n) => [n, ...n.children.flatMap(flatten)];
    const node = flatten(JSON.parse(uiSnapshot())).find(
      (n) => n.type === "button",
    );
    button = findById(node.id);
  }
  if (step === 123) renderer.setProp(button, "style", { cursor: "crosshair" });
  if (step === 124)
    renderer.setProp(button, "style", { cursor: "crosshair", width: 280 });
  if (step === 125)
    setTimeout(
      () =>
        renderer.setProp(button, "style", {
          cursor: "crosshair",
          width: 280,
          backgroundColor: "#af00aa",
        }),
      0,
    );
};
