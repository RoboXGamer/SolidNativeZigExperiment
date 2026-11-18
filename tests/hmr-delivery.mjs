import assert from 'node:assert/strict';
import { initializeDevHost } from '../packages/solid-zig/src/native.js';
globalThis.__NATIVE_HMR__ = true;
globalThis.__hmrSession = 'session-a'; globalThis.__hmrEntry = 'app'; globalThis.__hmrCompatibility = 'runtime-a';
initializeDevHost();
const packet = { protocol: 1, session: 'session-a', entry: 'app', compatibility: 'runtime-a', revision: 1, type: 'update', graph: { app: `const api=require('native-host'); api.mountApp(()=>require('native-renderer').createElement('label'));` } };
try {
  assert.throws(() => __uiReceive({ ...packet, session: 'session-b' }), /mismatch/);
  assert.throws(() => __uiReceive({ ...packet, compatibility: 'stale' }), /mismatch/);
  assert.equal(__uiReceive(packet), true);
  let batch = JSON.parse(uiFrameChanges()); assert.equal(batch.replace, true);
  assert.throws(() => uiCommit(batch.batch - 1), /Stale native batch/);
  uiCommit(batch.batch);
  assert.equal(__uiReceive(packet), false, 'duplicate receipt is idempotent');
  __uiReceive({ ...packet, revision: 2, type: 'full-reload' });
  const next = JSON.parse(uiFrameChanges()); assert.equal(next.replace, true);
  assert.ok(next.batch > batch.batch); assert.throws(() => uiCommit(batch.batch), /Stale native batch/);
  uiCommit(next.batch);
  __uiReceive({ ...packet, revision: 3, graph: { app: 'throw Error("bad generation");' } });
} catch (error) {
  if (!/bad generation/.test(error.message)) throw error;
  assert.equal(__hmrDelivery.phase, 'failed');
  assert.throws(() => uiFrameChanges(), /not ready/);
  __uiReceive({ ...packet, revision: 4 });
  assert.equal(__hmrDelivery.phase, 'vm-applied');
  assert.equal(JSON.parse(uiFrameChanges()).replace, true);
} finally { uiDispose(); delete globalThis.__uiModules; }
console.log('Session/runtime validation, duplicate delivery, exact batches and full-snapshot recovery passed');
