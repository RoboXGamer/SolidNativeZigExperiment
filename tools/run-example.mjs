import { build } from "vite";
import { configureExample, projectRoot } from "./example-entry.mjs";
import { startNative, stopNative } from "./native-process.mjs";
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { compatibility } from './hmr-session.mjs';
process.chdir(projectRoot);
const args = process.argv.slice(2), index = args.indexOf('--session');
if (index < 0 || !args[index + 1]) throw Error('Start pnpm dev, or pass --session <session.json> printed by dev:ui');
const session = JSON.parse(await readFile(args[index + 1], 'utf8')); args.splice(index, 2);
const selection = configureExample(args);
if (selection.args.length)
  throw Error(`Unknown run argument: ${selection.args.join(" ")}`);
if (session.compatibility !== await compatibility(session.configFile)) throw Error('Runtime changed; restart dev:ui to create a compatible session');
if (args.some(a => a.startsWith('--example')) && session.entry !== selection.entry) throw Error('Session example mismatch');
await build({ mode: "native-hmr", configFile: session.configFile, build: { outDir: join(session.dir, 'bootstrap'), lib: { entry: join(projectRoot, 'tools/hmr-bootstrap.js'), name: 'NativeBootstrap', formats: ['iife'], fileName: () => 'ui-bundle.js' } } });
const child = startNative(session);
child.on("error", (error) => {
  console.error(error);
  process.exitCode = 1;
});
child.on("exit", (code, signal) => {
  process.exitCode = code ?? (signal ? 1 : 0);
});
process.on("SIGINT", () => void stopNative(child));
process.on("SIGTERM", () => void stopNative(child));
