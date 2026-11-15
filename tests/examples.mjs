import assert from "node:assert/strict";
import vm from "node:vm";
import { build } from "vite";
import {
  exampleEntry,
  listExamples,
  configureExample,
} from "../tools/example-entry.mjs";

assert.ok(listExamples().includes("css"));
assert.ok(listExamples().includes("states"));
assert.equal(exampleEntry({}), "/examples/css/app.js");
assert.equal(exampleEntry({ example: "states" }), "/examples/states/app.js");
assert.throws(() => exampleEntry({ example: "../ui" }), /Unknown example/);
assert.throws(() => configureExample(["--example"]), /needs a name/);
const originalEntry = process.env.DRAFT1_ENTRY;
const originalExample = process.env.DRAFT1_EXAMPLE;
try {
  for (const name of ["css", "states"]) {
    process.env.DRAFT1_ENTRY = "/ui/app.js";
    const selected = configureExample(["--example", name]);
    assert.equal(
      selected.entry,
      `/examples/${name}/app.js`,
      "explicit selection overrides the legacy entry",
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
    else {
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
