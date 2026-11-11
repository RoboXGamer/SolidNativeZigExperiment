import assert from "node:assert/strict";
import { snapshot } from "../src/native.js";

const node = (style, props = {}) => ({
  id: 1,
  type: "column",
  text: "",
  props: { style, ...props },
  children: [],
});

// 1. Overflow shorthand and per-axis properties (SCROLL-01)
{
  const s = snapshot(node({ overflow: "scroll hidden" })).style;
  assert.equal(s.overflow, "scroll hidden");
  assert.equal(s.overflowX, "scroll");
  assert.equal(s.overflowY, "hidden");
}

{
  const s = snapshot(node({ overflowX: "auto", overflowY: "clip" })).style;
  assert.equal(s.overflowX, "auto");
  assert.equal(s.overflowY, "clip");
}

{
  const s = snapshot(node({ scrollbarGutter: "stable", scrollbarWidth: "thin" })).style;
  assert.equal(s.scrollbarGutter, "stable");
  assert.equal(s.scrollbarWidth, "thin");
}

// 2. Text layout, alignment, and line height (TEXT-01, TEXT-04)
{
  const s = snapshot(node({ whiteSpace: "nowrap", textAlign: "right" })).style;
  assert.equal(s.whiteSpace, "nowrap");
  assert.equal(s.textAlign, "right");
}

{
  // Numeric line-height
  const s = snapshot(node({ lineHeight: 28 })).style;
  assert.equal(s.lineHeight, 28);
  assert.equal(s.lineHeightCss, "");
}

{
  // CSS length line-height
  const s = snapshot(node({ lineHeight: "1.5em" })).style;
  assert.equal(s.lineHeight, null);
  assert.equal(s.lineHeightCss, "1.5em");
}

// 3. Inline Formatting Context display (TEXT-02)
{
  const s = snapshot(node({ display: "inline-flex" })).style;
  assert.equal(s.display, "inline-flex");
}

// 4. Focusable and tabIndex separation (INPUT-01, INPUT-02)
{
  // Button enabled
  const snapBtn = snapshot({ id: 2, type: "button", text: "Click", props: {}, children: [] });
  assert.equal(snapBtn.clickable, true);
  assert.equal(snapBtn.focusable, true);

  // Button disabled
  const snapBtnDis = snapshot({ id: 3, type: "button", text: "Disabled", props: { disabled: true }, children: [] });
  assert.equal(snapBtnDis.clickable, false);
  assert.equal(snapBtnDis.focusable, false);

  // Input
  const snapInput = snapshot({ id: 4, type: "input", text: "", props: { value: "abc" }, children: [] });
  assert.equal(snapInput.clickable, true);
  assert.equal(snapInput.focusable, true);

  // Custom div with tabIndex 0
  const snapTab0 = snapshot({ id: 5, type: "div", text: "", props: { tabIndex: 0 }, children: [] });
  assert.equal(snapTab0.tabIndex, 0);
  assert.equal(snapTab0.focusable, true);

  // Custom div with tabIndex -1
  const snapTabNeg = snapshot({ id: 6, type: "div", text: "", props: { tabIndex: -1 }, children: [] });
  assert.equal(snapTabNeg.tabIndex, -1);
  assert.equal(snapTabNeg.focusable, true);

  // Custom div with focusable: true
  const snapFoc = snapshot({ id: 7, type: "div", text: "", props: { focusable: true }, children: [] });
  assert.equal(snapFoc.focusable, true);
  assert.equal(snapFoc.tabIndex, null);

  // Plain div without focus
  const snapPlain = snapshot({ id: 8, type: "div", text: "", props: {}, children: [] });
  assert.equal(snapPlain.focusable, false);
  assert.equal(snapPlain.clickable, false);
}

console.log("Phase D text-overflow tests passed");
