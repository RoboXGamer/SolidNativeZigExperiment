// The historical bad-behavior assertions have been replaced by invariants.
// Preserve the old command as a useful entry point; --output writes new evidence.
import { writeFile } from 'node:fs/promises';
for (const file of ['module_host', 'hmr-lifecycle', 'hmr-api', 'hmr-css', 'hmr-delivery', 'hmr-compiler']) await import(`../tests/${file}.mjs`);
const report = { status: 'passed', runtime: process.version, scope: 'Node invariants; run pnpm test:hmr:native for live Vite/watcher/QuickJS/native delivery' };
if (process.argv[2] === '--output' && process.argv[3]) await writeFile(process.argv[3], JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify(report));
