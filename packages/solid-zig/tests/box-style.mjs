// Focused source fixtures. Unexecuted while application testing is paused.
import assert from "node:assert/strict";
import { physicalStyle, snapshot } from "../src/native.js";

for (const [mode, direction, start, block] of [
  ["horizontal-tb", "ltr", "marginLeft", "paddingTop"],
  ["horizontal-tb", "rtl", "marginRight", "paddingTop"],
  ["vertical-rl", "ltr", "marginTop", "paddingRight"],
  ["vertical-rl", "rtl", "marginBottom", "paddingRight"],
  ["vertical-lr", "ltr", "marginTop", "paddingLeft"],
  ["vertical-lr", "rtl", "marginBottom", "paddingLeft"],
]) {
  const result = physicalStyle({ writingMode: mode, direction, marginInlineStart: -1, paddingBlockStart: 3 });
  assert.equal(result[start], -1);
  assert.equal(result[block], 3);
}
assert.equal(physicalStyle({ marginLeft: 8, marginInlineStart: 0 }).marginLeft, 0);
assert.equal(physicalStyle({ marginInlineStart: 0, marginLeft: 8 }).marginLeft, 8);
assert.equal(physicalStyle({ paddingLeft: 0, padding: 20 }).paddingLeft, 20);
assert.equal(physicalStyle({ padding: 20, paddingLeft: 0 }).paddingLeft, 0);
for (const [input, expected] of [
  ["1px", ["1px", "1px", "1px", "1px"]],
  ["1px 2px", ["1px", "2px", "1px", "2px"]],
  ["1px 2px 3px", ["1px", "2px", "3px", "2px"]],
  ["1px 2px 3px 4px", ["1px", "2px", "3px", "4px"]],
]) {
  const value = physicalStyle({ padding: input });
  assert.deepEqual([value.paddingTop, value.paddingRight, value.paddingBottom, value.paddingLeft], expected);
}
assert.equal(physicalStyle({ writingMode: "vertical-rl", inlineSize: 25 }).height, 25);
assert.equal(physicalStyle({ writingMode: "vertical-lr", blockSize: 25 }).width, 25);

const node = style => ({ id: 1, type: "column", text: "", props: { style }, children: [] });
const projected = snapshot(node({ width: 0, maxWidth: "none", margin: "-1px auto", padding: "20px 0", borderWidth: 4, borderLeftWidth: 0 })).style;
assert.equal(projected.width, 0);
assert.equal(projected.maxWidthCss, "none");
assert.equal(projected.marginTopCss, "-1px");
assert.equal(projected.marginRightAuto, true);
assert.equal(projected.paddingLeftCss, "0");
assert.equal(projected.borderLeftWidth, 0);
assert.throws(() => snapshot(node({ width: NaN })));
assert.throws(() => snapshot(node({ padding: Infinity })));

const parent = node({ display: "contents" });
const child = { id: 2, type: "button", text: "", props: {}, children: [], parent };
parent.children.push(child);
assert.equal(snapshot(parent).children[0].id, 2);
assert.equal(child.parent, parent);
