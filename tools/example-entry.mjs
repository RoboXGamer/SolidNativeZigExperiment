import { existsSync, readdirSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const projectRoot = fileURLToPath(new URL("../", import.meta.url));
export function listExamples() {
  return readdirSync(resolve(projectRoot, "examples"), { withFileTypes: true })
    .filter(
      (item) =>
        item.isDirectory() &&
        existsSync(resolve(projectRoot, "examples", item.name, "app.js")),
    )
    .map((item) => item.name)
    .sort();
}

export function exampleEntry(
  { example, entry } = process.env.DRAFT1_EXAMPLE
    ? { example: process.env.DRAFT1_EXAMPLE }
    : { entry: process.env.DRAFT1_ENTRY },
) {
  if (!example && entry) return entry.startsWith("/") ? entry : "/" + entry;
  const name = example || "css";
  if (!listExamples().includes(name))
    throw Error(
      `Unknown example "${name}". Available: ${listExamples().join(", ")}`,
    );
  return `/examples/${name}/app.js`;
}

export function configureExample(args) {
  let example;
  const rest = [];
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--") continue;
    if (arg === "--example" || arg.startsWith("--example=")) {
      if (example !== undefined) throw Error("Pass --example only once");
      example =
        arg === "--example" ? args[++i] : arg.slice("--example=".length);
      if (!example || example.startsWith("-"))
        throw Error("--example needs a name");
    } else rest.push(arg);
  }
  const entry =
    example === undefined ? exampleEntry() : exampleEntry({ example });
  // Share one resolved entry between the dev graph and its Vite bootstrap build.
  delete process.env.DRAFT1_EXAMPLE;
  process.env.DRAFT1_ENTRY = entry;
  return { entry, args: rest };
}
