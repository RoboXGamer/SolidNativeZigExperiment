import assert from "node:assert/strict";
import { mkdtemp, writeFile, mkdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { compileCss } from "../tools/css-compiler.mjs";
import {
  setStyleSheet,
  clearStyleSheets,
} from "../packages/solid-zig/src/stylesheets.js";
import { node } from "../packages/solid-zig/src/renderer.js";
import { snapshot } from "../packages/solid-zig/src/native.js";
const dir = await mkdtemp(join(tmpdir(), "css-files-"));
try {
  await mkdir(join(dir, "nested"));
  await writeFile(
    join(dir, "nested", "pixel.png"),
    Buffer.from(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==",
      "base64",
    ),
  );
  await writeFile(
    join(dir, "nested", "base.css"),
    '.card { width: 120px; color: red; background-image: url("./pixel.png"); }',
  );
  const file = join(dir, "app.css");
  await writeFile(
    file,
    '@import "./nested/base.css"; .card { margin: 1px 2px; width: 200px !important; --gap: 12px; padding: var(--gap); } #target { width: 300px; color: blue; } .card { margin-left: 7px; }',
  );
  const rules = await compileCss(file, dir);
  assert.equal(rules.length, 4);
  assert.match(JSON.stringify(rules), /data:image\/png;base64/);
  setStyleSheet("test", rules);
  const parent = node("div");
  parent.props = { id: "target", class: "card", style: { width: 400 } };
  const child = node("text", "Hello");
  child.parent = parent;
  parent.children = [child];
  let result = snapshot(parent);
  assert.equal(result.style.widthCss, "200px");
  assert.equal(result.style.marginLeftCss, "7px");
  assert.equal(result.style.paddingTopCss, "12px");
  parent.props.style.gap = "16px";
  assert.equal(snapshot(parent).style.rowGapCss, "16px");
  assert.equal(snapshot(parent).style.columnGapCss, "16px");
  assert.equal(result.children[0].style.color, "#00f");
  parent.props.class = "";
  result = snapshot(parent);
  assert.equal(result.style.width, 400);
  assert.equal(result.style.marginLeftCss, null);
  child.props.style = { color: "initial" };
  result = snapshot(parent);
  assert.notEqual(result.children[0].style.color, "#00f");
  await writeFile(
    file,
    "@layer base, theme; @layer base { .card { color: red !important; } } @layer theme { .card { color: blue !important; } } .card { color: green; }",
  );
  setStyleSheet("test", await compileCss(file, dir));
  parent.props = { class: "card", style: { color: "purple !important" } };
  assert.equal(
    snapshot(parent).style.color,
    "purple",
    "inline important wins layered important",
  );
  parent.props.style = {};
  assert.equal(
    snapshot(parent).style.color,
    "red",
    "important reverses layer order",
  );
  await writeFile(
    file,
    ".card { --a: var(--a, red); color: var(--a, blue); font-size: 2em; } .child { font-size: 50%; padding: inherit; }",
  );
  setStyleSheet("test", await compileCss(file, dir));
  child.type = "label";
  child.props = { class: "child" };
  result = snapshot(parent);
  assert.equal(result.style.color, "blue", "cyclic custom property falls back");
  assert.equal(result.style.fontSize, 32);
  assert.equal(result.children[0].style.fontSize, 16);
  child.props.style = { fontSize: "inherit" };
  result = snapshot(parent);
  assert.equal(result.children[0].style.fontSize, 32);
  await writeFile(
    file,
    ".card { color: red; } @media (width <= 600px) { .card { color: blue; } }",
  );
  setStyleSheet("test", await compileCss(file, dir));
  globalThis.__uiViewport = { width: 500, height: 720 };
  assert.equal(snapshot(parent).style.color, "#00f");
  globalThis.__uiViewport = { width: 1000, height: 720 };
  assert.equal(snapshot(parent).style.color, "red");
  await writeFile(file, ".card::before { color:red; }");
  await assert.rejects(
    compileCss(file, dir),
    /Unsupported native CSS selector/,
  );
  console.log(
    "PASS CSS files: nested imports/assets, important vs inline, specificity, shorthand ordering, variables, inheritance and reactive class removal",
  );
} finally {
  clearStyleSheets();
  await rm(dir, { recursive: true, force: true });
}
