import assert from "node:assert/strict";
import vm from "node:vm";
import { build } from "vite";
import {
  exampleEntry,
  configureExample,
} from "../tools/example-entry.mjs";

assert.equal(exampleEntry({}), "/examples/css/app.js");
assert.throws(() => exampleEntry({ example: "../ui" }), /Unknown example/);
assert.throws(() => configureExample(["--example"]), /needs a name/);
const originalEntry = process.env.DRAFT1_ENTRY;
const originalExample = process.env.DRAFT1_EXAMPLE;
try {
  for (const name of ["counter", "css", "states", "tictactoe"]) {
    process.env.DRAFT1_ENTRY = "/examples/css/app.js";
    const selected = configureExample(["--example", name]);
    assert.equal(
      selected.entry,
      `/examples/${name}/app.js`,
      "explicit selection overrides the environment entry",
    );
    const result = await build({ logLevel: "silent", build: { write: false } });
    const output = (Array.isArray(result) ? result[0] : result).output;
    const bundle = output.find((item) => item.type === "chunk").code;
    const context = vm.createContext({
      console,
      performance,
      queueMicrotask,
      setTimeout,
      clearTimeout,
      setInterval,
      clearInterval,
    });
    vm.runInContext(bundle, context, { timeout: 10000 });
    await new Promise((resolve) =>
      setTimeout(resolve, name === "states" ? 1200 : 10),
    );
    const snapshot = JSON.parse(
      vm.runInContext("uiSnapshot()", context, { timeout: 10000 }),
    );
    const nodes = [];
    const visit = (n) => {
      nodes.push(n);
      n.children.forEach(visit);
    };
    visit(snapshot);
    if (name === "css")
      assert.ok(
        nodes.some((n) =>
          n.style.backgroundImage.includes("data:image/png;base64"),
        ),
      );
    else if (name === "states") {
      assert.equal(nodes.filter((n) => n.type === "select").length, 2);
      assert.ok(
        nodes.some((n) => n.type === "option" && n.text === "California"),
      );
      assert.ok(
        nodes.some((n) => n.type === "option" && n.text === "Los Angeles"),
      );
      assert.ok(
        nodes.every(
          (n) => !n.style.backgroundImage.includes("data:image/png;base64"),
        ),
        "CSS demo must not leak into states",
      );
    }
    else if (name === "counter") {
      const button = nodes.find((n) => n.type === "button");
      assert.ok(button, "counter has a native button");
      assert.match(JSON.stringify(snapshot), /Clicked 0 times/);
      vm.runInContext(`uiDispatchClick(${button.id}); __uiSolid.flush()`, context);
      await new Promise(resolve => setTimeout(resolve, 10));
      assert.match(vm.runInContext("uiSnapshot()", context), /Clicked 1 times/);
    }
    else {
      const read = () => JSON.parse(vm.runInContext("uiSnapshot()", context));
      const flatten = n => [n, ...n.children.flatMap(flatten)];
      const text = n => n.text + n.children.map(text).join("");
      const click = async n => {
        assert.ok(n, "expected clickable game control");
        vm.runInContext(`uiDispatchClick(${n.id}); __uiSolid.flush()`, context);
        await new Promise(resolve => setTimeout(resolve, 5));
      };
      const clickText = value => click(flatten(read()).find(n => n.type === "button" && text(n) === value));
      assert.ok(flatten(read()).some(n => text(n) === "PICK PLAYER 1’S MARK"));
      await clickText("NEW GAME (VS PLAYER)");
      const cell = index => flatten(read()).filter(n => n.type === "button")[index + 1];
      for (const index of [0, 3, 1, 4, 2]) await click(cell(index));
      assert.ok(flatten(read()).some(n => text(n) === "PLAYER 1 WINS!"));
      assert.ok(flatten(read()).some(n => text(n) === "X (P1)1"));
      await clickText("NEXT ROUND");
      assert.equal(flatten(read()).filter(n => n.type === "button").length, 10);
      assert.ok(flatten(read()).some(n => text(n) === "X (P1)1"), "score persists between rounds");
      await clickText("↻");
      assert.ok(flatten(read()).some(n => text(n) === "RESTART GAME?"));
      await clickText("NO, CANCEL");
      for (const index of [0, 1, 2, 4, 3, 5, 7, 6, 8]) await click(cell(index));
      assert.ok(flatten(read()).some(n => text(n) === "ROUND TIED"));
      await clickText("QUIT");
      assert.ok(flatten(read()).some(n => text(n) === "PICK PLAYER 1’S MARK"));
      await clickText("NEW GAME (VS CPU)");
      await click(cell(0));
      await new Promise(resolve => setTimeout(resolve, 500));
      const cells = flatten(read()).filter(n => n.type === "button").slice(1);
      assert.equal(cells.filter(n => n.children.length > 0).length, 2, "CPU responds with a move");
    }
    vm.runInContext("uiDispose()", context);
    console.log(
      `PASS example ${name}: selected Vite build and application snapshot`,
    );
  }
} finally {
  if (originalEntry === undefined) delete process.env.DRAFT1_ENTRY;
  else process.env.DRAFT1_ENTRY = originalEntry;
  if (originalExample === undefined) delete process.env.DRAFT1_EXAMPLE;
  else process.env.DRAFT1_EXAMPLE = originalExample;
}
