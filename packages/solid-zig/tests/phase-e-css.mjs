import assert from "node:assert/strict";
import { physicalStyle, snapshot } from "../src/native.js";

const node = style => ({ id: 1, type: "column", text: "", props: { style }, children: [] });

// ---------------------------------------------------------------------------
// 1. CSS Positioning & Insets
// ---------------------------------------------------------------------------
{
  const s = snapshot(node({
    position: "relative",
    top: 10,
    left: "20px",
    right: "15%",
    bottom: -5,
    zIndex: 42,
  })).style;

  assert.equal(s.position, "relative");
  assert.equal(s.top, 10);
  assert.equal(s.topCss, null);
  assert.equal(s.left, null);
  assert.equal(s.leftCss, "20px");
  assert.equal(s.right, null);
  assert.equal(s.rightCss, "15%");
  assert.equal(s.bottom, -5);
  assert.equal(s.zIndex, 42);
}

// Inset shorthands
{
  const p = physicalStyle({ inset: "10px 20px 30px 40px" });
  assert.equal(p.top, "10px");
  assert.equal(p.right, "20px");
  assert.equal(p.bottom, "30px");
  assert.equal(p.left, "40px");

  const s = snapshot(node({ inset: "5px 10px" })).style;
  assert.equal(s.topCss, "5px");
  assert.equal(s.bottomCss, "5px");
  assert.equal(s.rightCss, "10px");
  assert.equal(s.leftCss, "10px");
}

// ---------------------------------------------------------------------------
// 2. CSS Grid Layout Properties
// ---------------------------------------------------------------------------
{
  const s = snapshot(node({
    display: "grid",
    gridTemplateColumns: "repeat(3, 1fr)",
    gridTemplateRows: "100px minmax(50px, auto)",
    gridAutoFlow: "row dense",
    gridTemplateAreas: '"header header" "sidebar main"',
    gridColumn: "1 / span 2",
    gridRow: "2",
    gridArea: "header",
    gridColumnStart: 1,
    gridColumnEnd: 3,
    gridRowStart: 2,
    gridRowEnd: 3,
  })).style;

  assert.equal(s.display, "grid");
  assert.equal(s.gridTemplateColumnsCss, "repeat(3, 1fr)");
  assert.equal(s.gridTemplateRowsCss, "100px minmax(50px, auto)");
  assert.equal(s.gridAutoFlow, "row dense");
  assert.equal(s.gridTemplateAreas, '"header header" "sidebar main"');
  assert.equal(s.gridColumn, "1 / span 2");
  assert.equal(s.gridRow, "2");
  assert.equal(s.gridArea, "header");
  assert.equal(s.gridColumnStart, 1);
  assert.equal(s.gridColumnEnd, 3);
  assert.equal(s.gridRowStart, 2);
  assert.equal(s.gridRowEnd, 3);
}

// ---------------------------------------------------------------------------
// 3. CSS Box Alignment Shorthands
// ---------------------------------------------------------------------------
{
  const p = physicalStyle({
    placeContent: "space-between center",
    placeItems: "center stretch",
    placeSelf: "start end",
  });
  assert.equal(p.alignContent, "space-between");
  assert.equal(p.justifyContent, "center");
  assert.equal(p.alignItems, "center");
  assert.equal(p.justifyItems, "stretch");
  assert.equal(p.alignSelf, "start");
  assert.equal(p.justifySelf, "end");

  const s = snapshot(node({
    placeItems: "safe center",
    placeSelf: "unsafe end",
  })).style;
  assert.equal(s.alignItems, "safe center");
  assert.equal(s.justifyItems, "safe center");
  assert.equal(s.alignSelf, "unsafe end");
  assert.equal(s.justifySelf, "unsafe end");
}

// ---------------------------------------------------------------------------
// 4. CSS Visual Effects & Transforms
// ---------------------------------------------------------------------------
{
  const s = snapshot(node({
    backgroundGradient: "linear-gradient(90deg, #ff0000 0%, #0000ff 100%)",
    boxShadow: "0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06)",
    opacity: 0.85,
    transform: "translate(20px, 30px) rotate(45deg) scale(1.5)",
    transformOrigin: "center center",
  })).style;

  assert.equal(s.backgroundGradient, "linear-gradient(90deg, #ff0000 0%, #0000ff 100%)");
  assert.equal(s.boxShadow, "0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06)");
  assert.equal(s.opacity, 0.85);
  assert.equal(s.transform, "translate(20px, 30px) rotate(45deg) scale(1.5)");
  assert.equal(s.transformOrigin, "center center");
}

// ---------------------------------------------------------------------------
// 5. CSS Transitions & Animation Hooks
// ---------------------------------------------------------------------------
{
  const s = snapshot(node({
    transition: "opacity 300ms ease, transform 500ms cubic-bezier(0.4, 0, 0.2, 1)",
    transitionProperty: "opacity",
    transitionDuration: "300ms",
    transitionTimingFunction: "cubic-bezier(0.4, 0, 0.2, 1)",
    transitionDelay: "50ms",
  })).style;

  assert.equal(s.transition, "opacity 300ms ease, transform 500ms cubic-bezier(0.4, 0, 0.2, 1)");
  assert.equal(s.transitionProperty, "opacity");
  assert.equal(s.transitionDuration, 0.3);
  assert.equal(s.transitionTimingFunction, "cubic-bezier(0.4, 0, 0.2, 1)");
  assert.equal(s.transitionDelay, 0.05);
}

console.log("Phase E CSS bridge tests passed successfully!");

// CSS Logical 1 flow-relative inset mapping, including sideways-lr's reversed inline axis.
for (const [writingMode, direction, start, end] of [
  ['horizontal-tb', 'ltr', 'left', 'right'],
  ['horizontal-tb', 'rtl', 'right', 'left'],
  ['vertical-rl', 'ltr', 'top', 'bottom'],
  ['vertical-lr', 'rtl', 'bottom', 'top'],
  ['sideways-lr', 'ltr', 'bottom', 'top'],
  ['sideways-rl', 'rtl', 'bottom', 'top'],
]) {
  const style = physicalStyle({ 'inset-inline': 'auto -10%', insetInlineStart: 0 }, { writingMode, direction });
  assert.equal(style[start], 0);
  assert.equal(style[end], '-10%');
  assert.equal(physicalStyle({ insetInlineStart: 4, [start]: 9 }, { writingMode, direction })[start], 9);
  assert.equal(physicalStyle({ [start]: 9, insetInlineStart: 4 }, { writingMode, direction })[start], 4);
}
assert.throws(() => physicalStyle({ insetInline: '1px 2px 3px' }));
assert.equal(physicalStyle({ insetBlock: 'calc(10% - 2px) auto' }).top, 'calc(10% - 2px)');
for (const position of ['absolute', 'fixed']) {
  assert.equal(snapshot(node({ position, display: 'inline-flex' })).style.display, 'flex');
  assert.equal(snapshot(node({ position, display: 'inline' })).style.display, 'block');
}
