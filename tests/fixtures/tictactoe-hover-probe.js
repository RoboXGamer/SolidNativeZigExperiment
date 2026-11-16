import { mountApp, discoveryWork, resetDiscoveryWork } from "@zig-ui/solid";
import App from "../../examples/tictactoe/App.jsx";

mountApp(App);
setTimeout(() => {
  const flatten = n => [n, ...n.children.flatMap(flatten)];
  const text = n => n.text + n.children.map(text).join("");
  const read = () => flatten(JSON.parse(uiSnapshot()));
  const start = read().find(n => n.type === "button" && text(n) === "NEW GAME (VS PLAYER)");
  uiDispatchClick(start.id);
  __uiSolid.flush();
  const cells = read().filter(n => n.type === "button").slice(1);
  uiFrameChanges(); uiCommit();
  const sample = fn => {
    const values = [];
    const counts = Object.fromEntries(Object.keys(discoveryWork).map(key => [key, 0]));
    for (let i = 0; i < 60; i++) {
      resetDiscoveryWork();
      const start = performance.now();
      fn(i); uiFrameChanges(); uiCommit();
      values.push(performance.now() - start);
      for (const key of Object.keys(counts)) counts[key] += discoveryWork[key];
    }
    values.sort((a, b) => a - b);
    return { samples: values.length, p50_ms: values[30], p95_ms: values[57], max_ms: values[59], totalWork: counts };
  };
  console.log("TICTACTOE_HOVER_PROFILE", JSON.stringify({
    engine: "QuickJS, optimized interpreter; native Zig Debug host",
    scope: "pointer transaction + computed CSS + bridge delta + commit; excludes native layout, paint, GPU and presentation",
    nodes: read().length,
    unchanged: sample(() => {}),
    tileSwitch: sample(i => uiDispatchPointer(cells[i % cells.length].id, 0, 0)),
    withinTile: sample(() => uiDispatchPointer(cells[0].id, 0, 0)),
  }));
}, 0);
