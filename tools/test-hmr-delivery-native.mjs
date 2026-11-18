import assert from 'node:assert/strict';
import { readFile, writeFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { HmrFixture, buildHost, until, lockFile, delay } from './hmr-test-session.mjs';
buildHost();
const fixture = await HmrFixture.create('delivery');
let unlock;
const results = [];
try {
  await fixture.startProducer(); await fixture.buildBootstrap();
  const gate = join(fixture.manifest.dir, 'watch.gate');
  await fixture.startHost({ SOLID_NATIVE_TEST_MISSED_NOTIFICATIONS: '1', SOLID_NATIVE_TEST_WATCH_GATE: gate });
  assert.match(fixture.nativeOutput, /notifications suppressed; rescan fallback active/);
  await fixture.expectText('1:1');
  await writeFile(gate, 'paused');
  const before = await fixture.readReceipt();
  await fixture.setPair(2);
  await until(async () => (await readFile(fixture.manifest.path, 'utf8')).includes('exports.a = 2'), 'new graph published');
  unlock = await lockFile(fixture.manifest.path);
  await rm(gate);
  await until(() => fixture.nativeOutput.includes('[native-hmr] read-retry'), 'real sharing violation reaches native reader');
  assert.equal((await fixture.readReceipt()).revision, before.revision, 'locked delivery cannot be falsely acknowledged');
  const releasedAt = performance.now(); await unlock(); unlock = null;
  await fixture.receipt(before.revision + 1); await fixture.expectText('2:2');
  results.push({ case: 'missed notifications + denied read; no further source edit', recoveryMs: performance.now() - releasedAt });

  const previousOutput = fixture.output.length;
  const receipt = await fixture.readReceipt();
  unlock = await lockFile(fixture.manifest.path, 'Read');
  await fixture.setPair(3);
  await until(() => fixture.output.slice(previousOutput).includes('publication-retry'), 'rename retries exhaust while latest graph is retained');
  assert.match(fixture.output.slice(previousOutput), /rename-retry/);
  assert.equal((await fixture.readReceipt()).revision, receipt.revision);
  const renameAt = performance.now(); await unlock(); unlock = null;
  await fixture.receipt(receipt.revision + 1); await fixture.expectText('3:3');
  results.push({ case: 'denied rename across retry exhaustion; no further source edit', recoveryMs: performance.now() - renameAt });

  const valid = await readFile(fixture.manifest.path, 'utf8');
  const accepted = await fixture.readReceipt();
  await writeFile(fixture.manifest.path, 'globalThis.__uiReceive({');
  await until(() => /SyntaxError/.test(fixture.nativeOutput), 'truncated envelope rejected');
  assert.equal((await fixture.readReceipt()).revision, accepted.revision);
  await fixture.expectText('3:3');
  await writeFile(fixture.manifest.path, valid); await delay(700);
  assert.equal((await fixture.readReceipt()).revision, accepted.revision, 'duplicate replay is inert');
  await fixture.expectText('3:3');
  await fixture.closeHost();
  console.log(JSON.stringify({ passed: true, cases: results, truncatedAndDuplicate: 'last-good frame retained; exact revision unchanged' }, null, 2));
} catch (error) { throw fixture.diagnostics(error); }
finally { await unlock?.(); await fixture.dispose(); }
