import assert from "node:assert/strict";
import { mkdtemp, writeFile, readFile, rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { createSignal, flush } from "solid-js";
import * as renderer from "../packages/solid-zig/src/renderer.js";
import { mountApp, findById } from "../packages/solid-zig/src/native.js";
import { compileCss } from "../tools/css-compiler.mjs";
import {
  setStyleSheet,
  clearStyleSheets,
} from "../packages/solid-zig/src/stylesheets.js";

const dir = await mkdtemp(join(tmpdir(), "native-css-dependencies-"));
const source = await readFile(
  new URL("../modules/ui_core/style.zig", import.meta.url),
  "utf8",
);
const defaults = Object.fromEntries(
  [...source.matchAll(/^    (\w+): [^\n]+? = ([^\n]+),$/gm)].map(
    ([, key, value]) => [key, value === "&.{}" ? [] : JSON.parse(value)],
  ),
);
const compactStyle = (style) =>
  Object.fromEntries(
    Object.entries(style).filter(
      ([key, value]) =>
        Object.hasOwn(defaults, key) &&
        JSON.stringify(value) !== JSON.stringify(defaults[key]),
    ),
  );
const compactNode = (node) => ({
  ...node,
  style: compactStyle(node.style),
  children: node.children.map((child) =>
    typeof child === "object" ? compactNode(child) : child,
  ),
});
const compactPatch = (patch) => ({
  ...patch,
  nodes: patch.nodes.map(compactNode),
  updates: patch.updates.map((update) =>
    Object.fromEntries(
      Object.entries(update).map(([key, value]) => [
        key,
        value?.style ? { ...value, style: compactStyle(value.style) } : value,
      ]),
    ),
  ),
});
const records = [];
let setRoot, setItem, setText, rootNode, item, sibling, variable, panel;
const cases = [];
function capture(name, layout, paint, check = () => {}) {
  flush();
  const patch = JSON.parse(uiFrameChanges());
  const incremental = JSON.parse(uiSnapshot());
  check(incremental, patch);
  const hasLayout =
    patch.nodes.length > 0 ||
    patch.removed.length > 0 ||
    patch.updates.some((update) => update.layout);
  const hasPaint = hasLayout || patch.updates.some((update) => update.paint);
  cases.push({ name, layout: hasLayout, paint: hasPaint });
  assert.equal(hasLayout, layout, `${name}: layout phase`);
  assert.equal(hasPaint, paint, `${name}: paint phase`);
  uiCommit();
  const clear = (node) => {
    for (const key of Object.keys(node))
      if (key.startsWith("_css") || key.startsWith("_snapshot"))
        delete node[key];
    node.children.forEach(clear);
  };
  clear(findById(incremental.id));
  const cold = JSON.parse(uiSnapshot());
  assert.deepEqual(
    incremental,
    cold,
    `${name}: cached computed CSS differs from a cold recomputation`,
  );
  records.push({
    name,
    layout,
    paint,
    patch: JSON.stringify(compactPatch(patch)),
    cold: JSON.stringify(compactNode(cold)),
  });
}
const flatten = (node) => [node, ...node.children.flatMap(flatten)];
const get = (tree, node) => flatten(tree).find((item) => item.id === node.id);
try {
  const file = join(dir, "app.css");
  await writeFile(
    file,
    `
#scene { display:flex;flex-direction:column;width:500px;color:#112233;font-size:16px;gap:10px; }
.row {display:flex;flex-direction:row;align-items:flex-start;gap:10px;}
.item,.sibling,.variable {width:100px;height:20px;flex-shrink:0;background-color:#223344;}
.item.expanded {width:180px;height:40px;background-color:#445566;cursor:crosshair;}
.item.expanded + .sibling {width:140px;background-color:#667788;}
.panel {display:flex;flex-direction:column;width:240px;}
.variable {width:var(--size,100px);}
.theme {color:#778899 !important;font-size:24px !important;}
.variables {--size:190px;}
.paint,.paint-same {background-color:#123456;}
.shadow {text-shadow:2px 2px #123456;}
.cursor {cursor:crosshair;}
.hidden {visibility:hidden;}
.inherit-bg {background-color:var(--missing,inherit);}
`,
  );
  setStyleSheet("dependencies", await compileCss(file, dir));
  mountApp(() => {
    const [rootClass, writeRoot] = createSignal("", { ownedWrite: true });
    setRoot = writeRoot;
    const [itemClass, writeItem] = createSignal("item", { ownedWrite: true });
    setItem = writeItem;
    const [text, writeText] = createSignal("Short", { ownedWrite: true });
    setText = writeText;
    rootNode = renderer.createElement("column", { id: "scene" });
    renderer.effect(rootClass, (value) => {
      renderer.setProp(rootNode, "class", value);
    });
    const row = renderer.createElement("row", { class: "row" });
    item = renderer.createElement("column");
    renderer.effect(itemClass, (value) => {
      renderer.setProp(item, "class", value);
    });
    sibling = renderer.createElement("column", { class: "sibling" });
    variable = renderer.createElement("column", { class: "variable" });
    panel = renderer.createElement("column", { class: "panel" });
    renderer.insert(panel, text);
    renderer.insertNode(row, item);
    renderer.insertNode(row, sibling);
    renderer.insertNode(rootNode, row);
    renderer.insertNode(rootNode, variable);
    renderer.insertNode(rootNode, panel);
    renderer.insertNode(
      rootNode,
      renderer.createElement("column", {
        class: "inherit-bg",
        style: { height: 10 },
      }),
    );
    renderer.insertNode(
      rootNode,
      renderer.createElement("column", { style: { width: 100, height: 10 } }),
    );
    return rootNode;
  });
  capture("initial", true, true);
  setRoot("noop");
  capture("class with no effective CSS change", false, false);
  setItem("item expanded");
  capture(
    "one class changes layout paint cursor and adjacent sibling",
    true,
    true,
    (tree, patch) => {
      assert.equal(get(tree, item).style.widthCss, "180px");
      assert.equal(get(tree, sibling).style.widthCss, "140px");
      assert.ok(
        patch.updates.find((update) => update.id === item.id)?.interaction,
      );
      assert.ok(
        patch.updates.find((update) => update.id === sibling.id)?.layout,
      );
    },
  );
  setItem("item");
  capture("remove class restores sibling and child inputs", true, true);
  setRoot("theme");
  capture(
    "inherited font and color change descendants",
    true,
    true,
    (tree, patch) => {
      assert.equal(get(tree, panel).style.fontSize, 24);
      assert.ok(patch.updates.find((update) => update.id === panel.id)?.layout);
    },
  );
  setRoot("");
  capture("inherited font removal restores descendants", true, true);
  setRoot("variables");
  capture(
    "ancestor custom property changes descendant size",
    true,
    true,
    (tree) => assert.equal(get(tree, variable).style.widthCss, "190px"),
  );
  setRoot("");
  capture("custom property removal restores descendant size", true, true);
  setRoot("paint");
  capture("paint class and explicit inherited background", false, true);
  setRoot("paint-same");
  capture("different class same effective computed CSS", false, false);
  setRoot("");
  capture("paint class removal", false, true);
  setRoot("shadow");
  capture("inherited text shadow is paint only", false, true);
  setRoot("");
  capture("text shadow removal is paint only", false, true);
  setRoot("cursor");
  capture("inherited cursor class is interaction only", false, false);
  setRoot("");
  capture("cursor class removal is interaction only", false, false);
  setRoot("hidden");
  capture("inherited visibility is paint only", false, true);
  setRoot("");
  capture("visibility removal is paint only", false, true);
  setText(
    "This longer text wraps onto multiple lines and must increase the auto-sized parent height and move the following sibling.",
  );
  capture("text changes auto parent and following sibling layout", true, true);
  setText("Short");
  capture("text shrink restores parent and following sibling", true, true);
  const output = JSON.stringify(records, null, 2) + "\n";
  const fixture = new URL(
    "../modules/ui_core/fixtures/css-dependencies.json",
    import.meta.url,
  );
  if (process.argv.includes("--write"))
    await writeFile(fixture, output, "utf8");
  else if (process.argv.includes("--check"))
    assert.equal(
      await readFile(fixture, "utf8"),
      output,
      "computed CSS bridge fixtures are stale",
    );
  console.log(
    "PASS computed CSS dependency batches and cold-cache parity:",
    JSON.stringify(cases),
  );
} finally {
  globalThis.uiDispose?.();
  clearStyleSheets();
  await rm(dir, { recursive: true, force: true });
}
