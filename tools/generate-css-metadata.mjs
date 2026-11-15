import { createRequire } from "node:module";
import { writeFileSync } from "node:fs";
const require = createRequire(import.meta.url);
const definitions = require("cssstyle/lib/generated/propertyDefinitions.js");
const { shorthandProperties } = require("cssstyle/lib/normalize.js");
const properties = Object.fromEntries(
  [...definitions]
    .filter(
      ([name, d]) =>
        !name.startsWith("-") &&
        !shorthandProperties.has(name) &&
        typeof d.initial === "string",
    )
    .map(([name, d]) => [
      name,
      { initial: d.initial, inherited: d.inherited === "yes" },
    ]),
);
writeFileSync(
  new URL("../packages/solid-zig/src/css-properties.json", import.meta.url),
  JSON.stringify(properties, null, 2) + "\n",
);
