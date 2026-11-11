import assert from "node:assert/strict";
import { createRoot, createSignal, createComponent, For, flush } from "solid-js";
import * as renderer from "../src/renderer.js";
import {
  snapshot,
  getOptions,
  getOptionValue,
  getOptionLabel,
  getSelectValue,
  getSelectedLabel,
  isSelectedOption,
  dispatchClick,
  dispatchInput,
  dispatchKey,
  mountApp,
} from "../src/native.js";

function find(node, type) {
  if (!node) return null;
  if (node.type === type) return node;
  for (const child of node.children ?? []) {
    const hit = find(child, type);
    if (hit) return hit;
  }
  return null;
}

// --- Suite 1: Node Tree Serialization (SELECT-01) ---
{
  const select = renderer.createElement("select", { value: "CA" });
  const opt1 = renderer.createElement("option", { value: "UT" });
  renderer.insert(opt1, "Utah");
  const opt2 = renderer.createElement("option", { value: "CA" });
  renderer.insert(opt2, "California");
  const opt3 = renderer.createElement("option", { value: "TX", disabled: true });
  renderer.insert(opt3, "Texas");

  renderer.insert(select, opt1);
  renderer.insert(select, opt2);
  renderer.insert(select, opt3);

  const tree = snapshot(select);

  assert.equal(tree.type, "select", "node type is select");
  assert.equal(tree.value, "CA", "controlled value matches prop");
  assert.equal(tree.text, "California", "text reflects selected option label");
  assert.equal(tree.clickable, true, "enabled select is clickable");
  assert.equal(tree.style.display, "flex", "select display is flex");
  assert.equal(tree.style.flexDirection, "column", "select flexDirection is column");
  assert.equal(tree.children.length, 3, "select serializes all option children");

  // Options when select is closed
  assert.equal(tree.children[0].type, "option");
  assert.equal(tree.children[0].value, "UT");
  assert.equal(tree.children[0].text, "Utah");
  assert.equal(tree.children[0].selected, false);
  assert.equal(tree.children[0].clickable, true);
  assert.equal(tree.children[0].style.display, "none", "options inside closed select are display: none");

  assert.equal(tree.children[1].type, "option");
  assert.equal(tree.children[1].value, "CA");
  assert.equal(tree.children[1].text, "California");
  assert.equal(tree.children[1].selected, true, "option matching select value is selected");
  assert.equal(tree.children[1].clickable, true);
  assert.equal(tree.children[1].style.display, "none");

  assert.equal(tree.children[2].type, "option");
  assert.equal(tree.children[2].value, "TX");
  assert.equal(tree.children[2].text, "Texas");
  assert.equal(tree.children[2].selected, false);
  assert.equal(tree.children[2].clickable, false, "disabled option is not clickable");

  // When select is opened
  select._open = true;
  const openTree = snapshot(select);
  assert.equal(openTree.open, true, "snapshot reflects open state");
  assert.equal(openTree.children[0].style.display, "flex", "options inside open select are display: flex");
  assert.equal(openTree.children[1].style.display, "flex");
  select._open = false;
}

// --- Suite 2: Default Selection & Option Text Extraction ---
{
  const select = renderer.createElement("select");
  const optDisabled = renderer.createElement("option", { value: "first", disabled: true });
  renderer.insert(optDisabled, "First (Disabled)");
  const optSecond = renderer.createElement("option"); // no value prop, text only
  renderer.insert(optSecond, "Second Option");

  renderer.insert(select, optDisabled);
  renderer.insert(select, optSecond);

  // Value should default to first non-disabled option, whose value is inferred from text
  assert.equal(getSelectValue(select), "Second Option", "uncontrolled select defaults to first non-disabled option");
  assert.equal(getOptionValue(optSecond), "Second Option", "option without value prop infers value from text content");
  assert.equal(getSelectedLabel(select), "Second Option");
}

// --- Suite 3: Option List Management (Dynamic Addition & Removal) ---
{
  createRoot((dispose) => {
    const [items, setItems] = createSignal(["Alpha", "Beta"], { ownedWrite: true });
    const select = renderer.createElement("select");
    renderer.insert(
      select,
      () =>
        createComponent(For, {
          get each() {
            return items();
          },
          children(item) {
            const opt = renderer.createElement("option", { value: item });
            renderer.insert(opt, item);
            return opt;
          },
        })
    );
    flush();

    assert.equal(getOptions(select).length, 2, "2 initial options");
    assert.equal(getSelectValue(select), "Alpha", "first option selected by default");

    setItems(["Alpha", "Beta", "Gamma"]);
    flush();
    assert.equal(getOptions(select).length, 3, "3 options after addition");

    setItems(["Beta", "Gamma"]);
    flush();
    assert.equal(getOptions(select).length, 2, "2 options after removal of Alpha");
    assert.equal(getSelectValue(select), "Beta", "Beta becomes first option and selected");

    dispose();
  });
}

// --- Suite 4: Change Event Handling & Value Updates ---
{
  let changeCount = 0;
  let lastChangeEvent = null;
  let inputCount = 0;
  let lastInputEvent = null;

  createRoot((dispose) => {
    mountApp(() => {
      const col = renderer.createElement("column");
      const sel = renderer.createElement("select", {
        value: "item-1",
        onChange: (e) => {
          changeCount++;
          lastChangeEvent = e;
        },
        onInput: (e) => {
          inputCount++;
          lastInputEvent = e;
        },
      });
      const o1 = renderer.createElement("option", { value: "item-1" });
      renderer.insert(o1, "Item 1");
      const o2 = renderer.createElement("option", { value: "item-2" });
      renderer.insert(o2, "Item 2");
      const o3 = renderer.createElement("option", { value: "item-3", disabled: true });
      renderer.insert(o3, "Item 3 (Disabled)");

      renderer.insert(sel, o1);
      renderer.insert(sel, o2);
      renderer.insert(sel, o3);
      renderer.insert(col, sel);
      return col;
    });

    const tree = JSON.parse(globalThis.uiSnapshot());
    const selectNode = find(tree, "select");
    const o2Id = selectNode.children[1].id;
    const o3Id = selectNode.children[2].id;

    // Click select to open
    dispatchClick(selectNode.id);
    let currentSnap = find(JSON.parse(globalThis.uiSnapshot()), "select");
    assert.equal(currentSnap.open, true, "clicking select opens it");

    // Click option 2
    dispatchClick(o2Id);
    currentSnap = find(JSON.parse(globalThis.uiSnapshot()), "select");
    assert.equal(currentSnap.open, false, "selecting an option closes select");
    assert.equal(currentSnap.value, "item-2", "select value updated to item-2");
    assert.equal(changeCount, 1, "onChange was dispatched");
    assert.equal(lastChangeEvent.type, "change");
    assert.equal(lastChangeEvent.target.value, "item-2");
    assert.equal(inputCount, 1, "onInput was dispatched");
    assert.equal(lastInputEvent.type, "input");
    assert.equal(lastInputEvent.target.value, "item-2");

    // Click disabled option 3: should do nothing
    dispatchClick(selectNode.id); // open again
    dispatchClick(o3Id); // disabled option
    assert.equal(changeCount, 1, "disabled option does not trigger change");

    // Click outside (e.g. root or id 0)
    dispatchClick(0);
    currentSnap = find(JSON.parse(globalThis.uiSnapshot()), "select");
    assert.equal(currentSnap.open, false, "click outside closes open select");

    dispose();
  });
}

// --- Suite 5: Keyboard Navigation (SELECT-01) ---
{
  createRoot((dispose) => {
    let committedValue = null;
    let selId = 0;

    mountApp(() => {
      const col = renderer.createElement("column");
      const sel = renderer.createElement("select", {
        value: "apple",
        onChange: (e) => {
          committedValue = e.target.value;
        },
      });
      selId = sel.id;
      for (const [val, lbl] of [
        ["apple", "Apple"],
        ["banana", "Banana"],
        ["cherry", "Cherry"],
        ["date", "Date"],
      ]) {
        const opt = renderer.createElement("option", { value: val });
        renderer.insert(opt, lbl);
        renderer.insert(sel, opt);
      }
      renderer.insert(col, sel);
      return col;
    });

    // 1. Closed select: ArrowDown navigates to next option
    dispatchKey(selId, "ArrowDown");
    let snap = find(JSON.parse(globalThis.uiSnapshot()), "select");
    assert.equal(snap.value, "banana", "ArrowDown on closed select advances to next option");
    assert.equal(committedValue, "banana");

    // 2. Closed select: ArrowUp navigates to previous option
    dispatchKey(selId, "ArrowUp");
    snap = find(JSON.parse(globalThis.uiSnapshot()), "select");
    assert.equal(snap.value, "apple", "ArrowUp on closed select returns to previous option");
    assert.equal(committedValue, "apple");

    // 3. Space / Enter opens popup
    dispatchKey(selId, "Space");
    snap = find(JSON.parse(globalThis.uiSnapshot()), "select");
    assert.equal(snap.open, true, "Space opens select");

    // 4. In open popup: ArrowDown advances highlight
    dispatchKey(selId, "ArrowDown");
    dispatchKey(selId, "ArrowDown");
    snap = find(JSON.parse(globalThis.uiSnapshot()), "select");
    assert.equal(snap.value, "cherry", "ArrowDown moves highlight in open select");

    // 5. Escape cancels and reverts to initial value
    dispatchKey(selId, "Escape");
    snap = find(JSON.parse(globalThis.uiSnapshot()), "select");
    assert.equal(snap.open, false, "Escape closes select");
    assert.equal(snap.value, "apple", "Escape restores initial selection");

    // 6. Open with Enter, navigate to Date, commit with Enter
    dispatchKey(selId, "Enter");
    dispatchKey(selId, "ArrowDown");
    dispatchKey(selId, "ArrowDown");
    dispatchKey(selId, "ArrowDown");
    dispatchKey(selId, "Enter"); // commit
    snap = find(JSON.parse(globalThis.uiSnapshot()), "select");
    assert.equal(snap.open, false, "Enter commits and closes select");
    assert.equal(snap.value, "date", "committed value is date");
    assert.equal(committedValue, "date");

    dispose();
  });
}

// --- Suite 6: Disabled Select Control ---
{
  createRoot((dispose) => {
    let clicks = 0;
    let selId = 0;

    mountApp(() => {
      const sel = renderer.createElement("select", {
        disabled: true,
        value: "one",
        onClick: () => clicks++,
      });
      selId = sel.id;
      const opt = renderer.createElement("option", { value: "one" });
      renderer.insert(opt, "One");
      renderer.insert(sel, opt);
      return sel;
    });

    const snap = find(JSON.parse(globalThis.uiSnapshot()), "select");
    assert.equal(snap.clickable, false, "disabled select is not clickable");

    dispatchClick(selId);
    assert.equal(clicks, 0, "click ignored on disabled select");

    dispatchKey(selId, "ArrowDown");
    assert.equal(find(JSON.parse(globalThis.uiSnapshot()), "select").value, "one", "keyboard ignored on disabled select");

    dispose();
  });
}

// --- Suite 7: DEMO-01 Async Race Condition Guard Test ---
{
  async function testAsyncRaceGuard() {
    let cityRequestId = 0;
    let lastCommittedCities = null;
    let lastCommittedCity = null;

    const mockFetchCities = async (state, delayMs) => {
      await new Promise((res) => setTimeout(res, delayMs));
      return [`${state}-City1`, `${state}-City2`];
    };

    const triggerStateChange = (state, delayMs) => {
      const token = ++cityRequestId;
      return (async () => {
        const c = await mockFetchCities(state, delayMs);
        if (token !== cityRequestId) {
          // Stale response discarded!
          return;
        }
        lastCommittedCities = c;
        lastCommittedCity = c[0] ?? null;
      })();
    };

    // Simulate rapid user state changes:
    // User selects "California" first (which has slow 100ms response)
    const p1 = triggerStateChange("California", 100);
    // User rapidly switches to "Utah" (which has fast 20ms response)
    const p2 = triggerStateChange("Utah", 20);

    await Promise.all([p1, p2]);

    // Even though California resolved after Utah, Utah's token was newer,
    // so California's stale response was discarded.
    assert.deepEqual(lastCommittedCities, ["Utah-City1", "Utah-City2"], "stale city response discarded");
    assert.equal(lastCommittedCity, "Utah-City1", "selected city matches selected state");
  }

  await testAsyncRaceGuard();
}

console.log("All select-control and async race guard tests passed successfully!");
