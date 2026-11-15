import { build } from "vite";
import { configureExample, projectRoot } from "./example-entry.mjs";
process.chdir(projectRoot);
const selection = configureExample(process.argv.slice(2));
let mode = "production";
for (let i = 0; i < selection.args.length; i++) {
  if (selection.args[i] === "--mode" && selection.args[i + 1])
    mode = selection.args[++i];
  else throw Error(`Unknown build argument: ${selection.args[i]}`);
}
console.log(`[example] building ${selection.entry}`);
await build({ mode });
