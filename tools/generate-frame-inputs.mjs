import { readFile, writeFile } from "node:fs/promises";
const root = new URL("../", import.meta.url);
const styles = await readFile(
  new URL("modules/ui_core/style.zig", root),
  "utf8",
);
const inputs = await readFile(
  new URL("modules/ui_core/frame_inputs.zig", root),
  "utf8",
);
function fields(source, name) {
  const body = source.match(
    new RegExp(`pub const ${name} = struct \\{([\\s\\S]*?)\\n\\};`),
  )?.[1];
  if (!body) throw Error(`Missing phase input type: ${name}`);
  return [...body.matchAll(/^\s+(\w+):/gm)].map((match) => match[1]);
}
const schema = {};
for (const phase of ["layout", "paint", "interaction", "motion"]) {
  const type = phase[0].toUpperCase() + phase.slice(1);
  schema[phase] = {
    node:
      phase === "motion"
        ? []
        : fields(inputs, type + "Inputs").filter((key) => key !== "style"),
    style: fields(styles, type + "Style"),
  };
}
const typography = [
  ...styles
    .match(/pub const typographyFields = \.\{([\s\S]*?)\n\};/)[1]
    .matchAll(/"(\w+)"/g),
].map((match) => match[1]);
const paintTypographyMask = typography.reduce(
  (mask, field, index) =>
    schema.paint.style.includes(field) ? mask | (1 << index) : mask,
  0,
);
const output =
  JSON.stringify({ phases: schema, typography, paintTypographyMask }, null, 2) +
  "\n";
const path = new URL("packages/solid-zig/src/frame-inputs.json", root);
if (process.argv.includes("--check")) {
  if ((await readFile(path, "utf8")).replaceAll("\r\n", "\n") !== output)
    throw Error(
      "Native phase schema is stale: node tools/generate-frame-inputs.mjs",
    );
} else await writeFile(path, output, "utf8");
