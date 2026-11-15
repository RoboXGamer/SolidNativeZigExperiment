import { mountApp } from "@zig-ui/solid";
import App from "../../examples/css/App.jsx";
mountApp(App);
setTimeout(() => {
  const nodes = [];
  const visit = (n) => {
    nodes.push(n);
    n.children.forEach(visit);
  };
  visit(JSON.parse(uiSnapshot()));
  const button = nodes.find((n) => n.type === "button");
  const text = button.children.find((n) => n.type === "text");
  function summary(values) {
    const sorted = [...values].sort((a, b) => a - b);
    return {
      samples: values.length,
      p50_ms: sorted[Math.floor(sorted.length * 0.5)],
      p95_ms:
        sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * 0.95))],
      max_ms: sorted.at(-1),
    };
  }
  uiChanges();
  uiCommit();
  const idle = [],
    hover = [];
  let previous = null;
  for (let i = 0; i < 30; i++) {
    const start = performance.now();
    uiChanges();
    uiCommit();
    idle.push(performance.now() - start);
  }
  for (let i = 0; i < 30; i++) {
    const target = i % 2 ? text.id : button.id;
    const start = performance.now();
    if (previous !== null) uiDispatchHover(previous, false);
    uiDispatchHover(target, true);
    const changes = JSON.parse(uiChanges());
    uiCommit();
    hover.push(performance.now() - start);
    previous = target;
    if (i < 2)
      console.log(
        "HOVER_PROBE_STATE",
        JSON.stringify({
          target: target === button.id ? "button-padding" : "button-text",
          buttonColor: JSON.parse(uiSnapshot())
            .children.flatMap(function flatten(n) {
              return [n, ...n.children.flatMap(flatten)];
            })
            .find((n) => n.id === button.id).style.backgroundColor,
          changedNodes: changes.nodes.length,
        }),
      );
  }
  console.log(
    "HOVER_PROBE_RESULT",
    JSON.stringify({
      engine: "QuickJS native host",
      idle: summary(idle),
      hoverSwitch: summary(hover),
    }),
  );
  if (typeof uiDispatchPointer === "function") {
    const batch = [];
    for (let i = 0; i < 30; i++) {
      const start = performance.now();
      uiDispatchPointer(i % 2 ? text.id : button.id, 0, 0);
      uiChanges();
      uiCommit();
      batch.push(performance.now() - start);
    }
    console.log("HOVER_BATCH_RESULT", JSON.stringify(summary(batch)));
  }
}, 0);
