import assert from "node:assert/strict";
import { physicalStyle, snapshot } from "../src/native.js";

const node = style => ({ id: 1, type: "column", text: "", props: { style }, children: [] });

// 1. Flex shorthand tests (FLEX-07)
// flex: "1 20px" -> grow 1, shrink 1, basis "20px"
{
  const s = snapshot(node({ flex: "1 20px" })).style;
  assert.equal(s.flexGrow, 1);
  assert.equal(s.flexShrink, 1);
  assert.equal(s.flexBasisCss, "20px");
  assert.equal(s.flexBasis, null);
}

// flex: "20px 1" -> grow 1, shrink 1, basis "20px"
{
  const s = snapshot(node({ flex: "20px 1" })).style;
  assert.equal(s.flexGrow, 1);
  assert.equal(s.flexShrink, 1);
  assert.equal(s.flexBasisCss, "20px");
}

// flex: "2 3 100px"
{
  const s = snapshot(node({ flex: "2 3 100px" })).style;
  assert.equal(s.flexGrow, 2);
  assert.equal(s.flexShrink, 3);
  assert.equal(s.flexBasisCss, "100px");
}

// flex: "1 2" -> grow 1, shrink 2, basis 0
{
  const s = snapshot(node({ flex: "1 2" })).style;
  assert.equal(s.flexGrow, 1);
  assert.equal(s.flexShrink, 2);
  assert.equal(s.flexBasis, 0);
}

// flex: "none" -> grow 0, shrink 0, basis "auto"
{
  const s = snapshot(node({ flex: "none" })).style;
  assert.equal(s.flexGrow, 0);
  assert.equal(s.flexShrink, 0);
  assert.equal(s.flexBasis, null);
  assert.equal(s.flexBasisCss, null);
}

// flex: "auto" -> grow 1, shrink 1, basis "auto"
{
  const s = snapshot(node({ flex: "auto" })).style;
  assert.equal(s.flexGrow, 1);
  assert.equal(s.flexShrink, 1);
}

// flex: 2 -> grow 2, shrink 1, basis 0
{
  const s = snapshot(node({ flex: 2 })).style;
  assert.equal(s.flexGrow, 2);
  assert.equal(s.flexShrink, 1);
  assert.equal(s.flexBasis, 0);
}

// 2. Typed flexBasis keywords and strings
{
  const sContent = snapshot(node({ flexBasis: "content" })).style;
  assert.equal(sContent.flexBasisContent, true);
  assert.equal(sContent.flexBasis, null);

  const sMax = snapshot(node({ flexBasis: "max-content" })).style;
  assert.equal(sMax.flexBasisCss, "max-content");

  const sMin = snapshot(node({ flexBasis: "min-content" })).style;
  assert.equal(sMin.flexBasisCss, "min-content");

  const sFit = snapshot(node({ flexBasis: "fit-content" })).style;
  assert.equal(sFit.flexBasisCss, "fit-content");

  const sPx = snapshot(node({ flexBasis: "25px" })).style;
  assert.equal(sPx.flexBasisCss, "25px");

  const sNum = snapshot(node({ flexBasis: 50 })).style;
  assert.equal(sNum.flexBasis, 50);
}

// 3. flexFlow shorthand expansion
{
  const s = physicalStyle({ flexFlow: "column-reverse wrap" });
  assert.equal(s.flexDirection, "column-reverse");
  assert.equal(s.flexWrap, "wrap");

  const snap = snapshot(node({ flexFlow: "row wrap-reverse" })).style;
  assert.equal(snap.flexDirection, "row");
  assert.equal(snap.flexWrap, "wrap-reverse");
}

// 4. Gaps: gap shorthand and rowGap / columnGap
{
  const s = physicalStyle({ gap: "10px 20px" });
  assert.equal(s.rowGap, "10px");
  assert.equal(s.columnGap, "20px");

  const snap = snapshot(node({ gap: "10px 20px" })).style;
  assert.equal(snap.rowGapCss, "10px");
  assert.equal(snap.columnGapCss, "20px");

  const snapNum = snapshot(node({ gap: 15, rowGap: 5, columnGap: 25 })).style;
  assert.equal(snapNum.gap, 15);
  assert.equal(snapNum.rowGap, 5);
  assert.equal(snapNum.columnGap, 25);
}

console.log("Flex and block style bridge tests passed!");
