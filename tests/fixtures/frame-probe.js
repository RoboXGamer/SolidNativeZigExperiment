import { mountApp, findById } from "@zig-ui/solid";
import * as renderer from "../../packages/solid-zig/src/renderer.js";
import App from "../../examples/css/App.jsx";
mountApp(App);
const flatten = n => [n, ...n.children.flatMap(flatten)];
const button = findById(flatten(JSON.parse(uiSnapshot())).find(n => n.type === "button").id);
// Deterministic fixture data, observed through normal timers and input.
setTimeout(() => renderer.setProp(button, "style", { cursor: "crosshair" }), 100);
setTimeout(() => renderer.setProp(button, "style", { cursor: "crosshair", width: 280 }), 200);
setTimeout(() => renderer.setProp(button, "style", { cursor: "crosshair", width: 280, backgroundColor: "#af00aa" }), 300);
