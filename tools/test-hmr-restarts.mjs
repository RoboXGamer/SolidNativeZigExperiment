import assert from 'node:assert/strict';
import { writeFile, readFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { HmrFixture, buildHost, until } from './hmr-test-session.mjs';
buildHost();
const a = await HmrFixture.create('restart'), b = await HmrFixture.create('unrelated');
const results = [];
const config = version => `import base from ${JSON.stringify(pathToFileURL(resolve('vite.config.mjs')).href)};export default env=>{const config=base(env);return {...config,plugins:[...config.plugins,{name:'fixture-config-version',enforce:'pre',transform(code,id){if(id.split('?')[0].endsWith('/config-value.js'))return ${JSON.stringify('export const configVersion=' + JSON.stringify(version) + ';')}}}]}};`;
try {
  a.options.configFile = join(a.dir, 'vite.config.mjs');
  await writeFile(a.options.configFile, config('v1'));
  const appFile = join(a.dir, 'app.jsx');
  await writeFile(join(a.dir, 'config-value.js'), 'export const configVersion="untransformed";');
  await writeFile(appFile, `import {configVersion} from './config-value.js';\n` + (await readFile(appFile, 'utf8')).replace('{a}:{b}</label>', '{a}:{b}:{configVersion}</label>'));
  for (const fixture of [a, b]) { await fixture.startProducer(); await fixture.buildBootstrap(); await fixture.startHost(); }
  await a.expectText('1:1:v1'); await b.expectText('1:1');
  const unrelated = { native: b.native.pid, producer: b.producer.pid, session: b.manifest.session };
  const initial = await a.control('describe');
  const before = await a.readReceipt();
  const at = performance.now();
  const restarting = a.control('restart-vite');
  await a.setPair(2); // save while a complete Vite process boundary is in flight
  const restarted = await restarting;
  assert.notEqual(restarted.tokenDigest, initial.tokenDigest, 'Vite restart rotates its actual WebSocket token');
  await a.receipt(before.revision + 1); await a.expectText('2:2:v1');
  await until(async () => (await a.control('describe')).connected, 'new-token WebSocket handshake');
  results.push({ case: 'actual Vite restart + token rotation + save during restart', recoveredMs: performance.now() - at });
  const revision = (await a.readReceipt()).revision;
  await a.setPair(3); await a.receipt(revision + 1); await a.expectText('3:3:v1');
  results.push({ case: 'watcher remains bound after Vite replacement', passed: true });

  const oldNative = a.native.pid;
  await a.closeHost();
  await a.setPair(4);
  await until(async () => (await readFile(a.manifest.path, 'utf8')).includes('exports.a = 4'), 'publish while native is stopped');
  await a.startHost(); await a.expectText('4:4:v1');
  assert.notEqual(a.native.pid, oldNative);
  results.push({ case: 'native process restart consumes latest published graph exactly once', passed: true });

  const prior = await a.readReceipt();
  const beforeConfig = await a.control('describe');
  await writeFile(a.options.configFile, config('v2'));
  await a.receipt(prior.revision + 1, 'restart-required');
  await until(async () => { const status = await a.control('describe'); return status.online && status.connected && status.tokenDigest !== beforeConfig.tokenDigest; }, 'actual config restart and new-token handshake');
  await a.expectText('4:4:v1'); // incompatible bootstrap is not hot applied
  const oldSession = a.manifest.session, oldCompatibility = a.manifest.compatibility;
  const oldProducer = a.producer;
  await a.control('stop');
  await until(() => oldProducer.exitCode !== null, 'producer stops gracefully');
  assert.equal(oldProducer.exitCode, 0);
  await a.setPair(5); // edit while the producer is down
  await writeFile(join(a.dir, 'a.js'), `throw Error('expected bad startup');export const a=5;`);
  await a.startProducer();
  assert.notEqual(a.manifest.session, oldSession);
  assert.notEqual(a.manifest.compatibility, oldCompatibility);
  await a.closeHost(); await a.buildBootstrap();
  await a.startHost({}, async () => {
    const failed = await a.receipt(1, 'failed');
    assert.equal(a.native.exitCode, null, 'an initially bad dev graph keeps the window alive');
    await a.setPair(5);
    await a.receipt(failed.revision + 1);
  });
  await a.expectText('5:5:v2');
  const newRevision = (await a.readReceipt()).revision;
  await a.setPair(6); await a.receipt(newRevision + 1); await a.expectText('6:6:v2');
  results.push({ case: 'config-triggered Vite restart requests bootstrap restart; producer/native restart adopts new config and intervening edit', passed: true });
  assert.equal(b.native.pid, unrelated.native); assert.equal(b.producer.pid, unrelated.producer); assert.equal(b.manifest.session, unrelated.session);
  await b.expectText('1:1');
  const bRevision = (await b.readReceipt()).revision;
  await b.setPair(7); await b.receipt(bRevision + 1); await b.expectText('7:7');
  await a.closeHost(); await b.closeHost();
  console.log(JSON.stringify({ passed: true, unrelatedSessionUnchanged: true, results }, null, 2));
} catch (error) { throw a.diagnostics(error); }
finally { await a.dispose(); await b.dispose(); }
