import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { compileGraph, clean, external } from '../tools/hmr-compiler.mjs';
const sources = { '/app.js': `import {x} from './dep.js?t=42';export const lazy=()=>import('./lazy.js');`, '/dep.js': 'export const x=1;', '/lazy.js': 'export const lazy=2;' };
const server = createServer((req, res) => { if (req.url === '/hung.js') return; res.end(sources[req.url] || 'invalid !'); });
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const origin = `http://127.0.0.1:${server.address().port}`;
try {
  const graph = await compileGraph({ origin, entry: '/app.js', signal: AbortSignal.timeout(2000) });
  assert.deepEqual(Object.keys(graph).sort(), ['/app.js', '/dep.js', '/lazy.js']);
  assert.equal(clean('/dep.js?t=42&raw=1', origin), '/dep.js?raw=1');
  assert.equal(external('/node_modules/.pnpm/solid-js@2/node_modules/solid-js/dist/solid.dev.js'), 'solid-js');
  assert.throws(() => external('/packages/solid-zig/src/invalidation.js'), /Unsupported embedded/);
  assert.throws(() => external('/node_modules/solid-js/store/dist/store.js'), /Unsupported embedded/);
  sources['/app.js'] = 'await Promise.resolve();';
  await assert.rejects(() => compileGraph({ origin, entry: '/app.js' }), /top-level await/);
  sources['/app.js'] = 'export const x=1;';
  let generation = 0;
  await assert.rejects(() => compileGraph({ origin, entry: '/app.js', generation: () => generation++ }), /Source generation changed/);
  const at = performance.now();
  await assert.rejects(() => compileGraph({ origin, entry: '/hung.js', signal: AbortSignal.timeout(50) }), /timeout|abort/i);
  assert.ok(performance.now() - at < 1000);
} finally { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
console.log('Compiler canonical IDs, lazy closure, unsupported imports/syntax and hung-fetch abort passed');
