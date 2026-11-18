import assert from 'node:assert/strict';
import { writeFile, readFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import net from 'node:net';
import os from 'node:os';
import { spawnSync } from 'node:child_process';
import { HmrFixture, buildHost, until, delay } from './hmr-test-session.mjs';
buildHost();
const fixture = await HmrFixture.create('compiler');
const report = { conditions: { platform: process.platform, osVersion: os.release(), cpu: os.cpus()[0]?.model, arch: process.arch, node: process.version, zig: spawnSync('zig', ['version'], { encoding: 'utf8' }).stdout.trim(), optimize: 'Debug host; optimized QuickJS; same Vite process/cache, fixture and graph; fresh native VM plus one warmup before each measured workload', sourceModules: 3, savedPairsPerWorkload: 12, fileWritesPerPair: 2, maxCompilerConcurrency: 1, pendingRequestPolicy: 'one latest request; no queued graph copies', memoryUnits: 'bytes; UTF-8 content accounting separate from sampled process heap/RSS', cpuUnits: 'microseconds; process CPU separate from wall time', latencyCaveat: 'small deterministic acceptance sample; burst reports one final convergence sample, not twelve per-edit native applications' }, workloads: [] };
async function idle() { await until(async () => (await fixture.control('metrics')).active === 0, 'producer idle'); }
async function resetMetrics() { await idle(); await fixture.control('reset-metrics'); }
async function setAndWait(value) {
  const previous = await fixture.readReceipt();
  const at = performance.now(); await fixture.setPair(value);
  await fixture.receipt(previous.revision + 1); await fixture.expectText(`${value}:${value}`);
  return performance.now() - at;
}
try {
  fixture.options.configFile = join(fixture.dir, 'vite.config.mjs');
  // This hangs the actual Vite transform pipeline, not a mocked fetch/client.
  await writeFile(fixture.options.configFile, `import base from ${JSON.stringify(pathToFileURL(resolve('vite.config.mjs')).href)};export default env=>{const c=base(env);return {...c,plugins:[...c.plugins,{name:'fixture-hung-transform',enforce:'pre',transform(code,id){if(code.includes('HMR_HANG_TRANSFORM')){console.log('[hmr-test] actual-transform-hung');return new Promise(()=>{})}}}]}};`);
  await fixture.startProducer(); await fixture.buildBootstrap(); await fixture.startHost();
  await fixture.expectText('1:1'); await idle();
  const beforeArtifacts = fixture.events.filter(e => e.event === 'published').length;
  await writeFile(join(fixture.manifest.dir, 'ignored-artifact.zig'), '// generated cache output');
  await delay(500);
  assert.equal(fixture.events.filter(e => e.event === 'published').length, beforeArtifacts, 'generated Zig/Vite/session artifacts cannot trigger new source generations');
  const a = fixture.entry.replace('app.jsx', 'a.js'), b = fixture.entry.replace('app.jsx', 'b.js');
  const initial = fixture.events.filter(e => e.event === 'published').at(-1);
  const historyStart = fixture.events.length;
  await resetMetrics();
  await fixture.control('pause-module', { module: a });
  await writeFile(join(fixture.dir, 'a.js'), 'export const a=1; // force an owned source event');
  const paused = await until(() => fixture.events.slice(historyStart).find(e => e.event === 'compile-paused'), 'real producer pauses after dependency A');
  await fixture.setPair(2);
  await fixture.expectText('2:2'); await idle();
  const publications = fixture.events.slice(historyStart).filter(e => e.event === 'published');
  assert.ok(publications.length > 0);
  const last = publications.at(-1);
  for (const publication of publications) {
    const pair = [publication.hashes[a], publication.hashes[b]];
    assert.ok((pair[0] === initial.hashes[a] && pair[1] === initial.hashes[b]) || (pair[0] === last.hashes[a] && pair[1] === last.hashes[b]), 'no old/new dependency mixture reaches publication');
  }
  assert.notEqual(last.hashes[a], initial.hashes[a]); assert.notEqual(last.hashes[b], initial.hashes[b]);
  const raceMetrics = await fixture.control('metrics');
  assert.ok(raceMetrics.discarded >= 1); assert.equal(raceMetrics.peakActive, 1);
  report.race = { passed: true, pausedGeneration: paused.generation, publishedGenerations: publications.map(p => p.generation), metrics: raceMetrics };

  for (const [name, baseline, first] of [['sequential', 100, 110], ['burst', 200, 210]]) {
    await fixture.closeHost();
    await fixture.setPair(baseline);
    await until(async () => (await readFile(fixture.manifest.path, 'utf8')).includes(`exports.a = ${baseline}`), 'baseline graph');
    await fixture.startHost(); await fixture.expectText(`${baseline}:${baseline}`);
    await setAndWait(baseline + 1); await resetMetrics();
    const nativeBefore = (await fixture.driver.command('metrics')).quickjs;
    const at = performance.now(), latencies = [], receiptBefore = await fixture.readReceipt();
    const eventStart = fixture.events.length;
    if (name === 'sequential') for (let n = first; n < first + 12; n++) latencies.push(await setAndWait(n));
    else {
      for (let n = first; n < first + 12; n++) await fixture.setPair(n);
      const allWrittenAt = performance.now();
      await fixture.receipt(receiptBefore.revision + 1); await fixture.expectText(`${first + 11}:${first + 11}`);
      latencies.push(performance.now() - allWrittenAt);
    }
    const wallMs = performance.now() - at; await idle();
    const metrics = await fixture.control('metrics'), nativeAfter = (await fixture.driver.command('metrics')).quickjs;
    assert.equal(metrics.failures, 0); assert.equal(metrics.peakActive, 1); assert.equal(metrics.peakPendingRequests, 1);
    assert.ok(metrics.peakRetainedUtf8Bytes < 128 * 1024, 'one small candidate/payload remains bounded during save storms');
    assert.ok(metrics.sampledPeakHeapBytes < metrics.heapBeforeBytes + 64 * 1024 * 1024);
    assert.equal(nativeAfter.roots, nativeBefore.roots);
    latencies.sort((x, y) => x - y);
    report.workloads.push({ name, pairSaves: 12, fileWrites: 24, valueWidth: 3, wallMs, pairSavesPerSecond: 12000 / wallMs, finalNativeValue: `${first + 11}:${first + 11}`, publishedRevisions: fixture.events.slice(eventStart).filter(e => e.event === 'published').length, failures: 0, failureReasons: [], latencyKind: name === 'sequential' ? 'per save to presented receipt' : 'final completed burst write to final presented receipt', latencySamples: latencies.length, latencyP50Ms: latencies[Math.floor(latencies.length * .5)], latencyP95Ms: latencies[Math.min(latencies.length - 1, Math.floor(latencies.length * .95))], latencyP99Ms: latencies[Math.min(latencies.length - 1, Math.floor(latencies.length * .99))], metrics, nativeBefore, nativeAfter });
  }
  await fixture.closeHost();
  const outputStart = fixture.output.length;
  await writeFile(join(fixture.dir, 'a.js'), 'export const a=999; // HMR_HANG_TRANSFORM');
  await until(() => fixture.output.slice(outputStart).includes('[hmr-test] actual-transform-hung'), 'actual Vite transform enters injected hang');
  const producer = fixture.producer, at = performance.now();
  await fixture.control('stop');
  await until(() => producer.exitCode !== null, 'hung-transform shutdown', 4500);
  const shutdownMs = performance.now() - at;
  assert.equal(producer.exitCode, 0); assert.ok(shutdownMs < 4000, '3-second shutdown deadline plus scheduling allowance');
  const probe = net.createServer();
  await new Promise((resolve, reject) => { probe.once('error', reject); probe.listen(fixture.port, '127.0.0.1', resolve); });
  await new Promise(resolve => probe.close(resolve));
  report.shutdown = { passed: true, actualHungViteTransform: true, shutdownMs, producerExit: producer.exitCode, portReused: true, deadlineMs: 3000, schedulingAllowanceMs: 1000 };
  await writeFile('.zig-cache/hmr-compiler-acceptance.json', JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify(report, null, 2));
} catch (error) { throw fixture.diagnostics(error); }
finally { await fixture.dispose(); }
