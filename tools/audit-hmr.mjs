// Diagnostic reproductions for the current HMR implementation. No runtime fixes.
// Run: node --conditions=browser --conditions=development tools/audit-hmr.mjs
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, rm, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { createModuleHost } from '../packages/solid-zig/src/module-runtime.js';
import * as native from '../packages/solid-zig/src/native.js';
import * as renderer from '../packages/solid-zig/src/renderer.js';
import { compileCss } from './css-compiler.mjs';

const results = [];
async function observe(id, run) {
  try {
    const observation = await run();
    results.push({ id, status: 'reproduced', ...observation });
  } catch (error) {
    results.push({ id, status: 'probe-error', error: error.stack });
  }
}

await observe('R01-runtime-failure-retry', () => {
  const s = { value: 0, calls: 0 };
  const host = createModuleHost({ s });
  const first = 'require("s").value=1;exports.version=1;__meta.hot.accept(next=>{require("s").calls++;if(next.version===2)throw Error("accept failed");});';
  const next = first.replace('value=1', 'value=2').replace('version=1', 'version=2');
  host.apply({ app: first }, 'app');
  assert.throws(() => host.apply({ app: next }, 'app'), /accept failed/);
  const afterFailure = { ...s };
  host.apply({ app: next }, 'app');
  assert.equal(s.calls, 1);
  assert.equal(s.value, 2);
  host.dispose();
  return { afterFailure, afterIdenticalRetry: { ...s }, defect: 'Failed update mutates live state; identical retry reports success without rerunning the failed accept.' };
});

await observe('R02-dispose-failure-loses-valid-update', () => {
  const s = { value: 0, throwCleanup: true };
  const host = createModuleHost({ s });
  const first = 'require("s").value=1;__meta.hot.accept();__meta.hot.dispose(()=>{if(require("s").throwCleanup)throw Error("cleanup failed")});';
  const next = first.replace('value=1', 'value=2');
  host.apply({ app: first }, 'app');
  assert.throws(() => host.apply({ app: next }, 'app'), /cleanup failed/);
  s.throwCleanup = false;
  host.apply({ app: next }, 'app');
  assert.equal(s.value, 1);
  host.dispose();
  return { observed: s.value, expectedAfterRecovery: 2, defect: 'Definitions advanced but old module stayed cached; valid identical retry is lost.' };
});

await observe('R03-failed-factory-listener-leak', () => {
  const s = { ghosts: 0 };
  const host = createModuleHost({ s });
  assert.throws(() => host.apply({ bad: '__meta.hot.on("vite:beforeUpdate",()=>require("s").ghosts++);throw Error("factory failed");' }, 'bad'), /factory failed/);
  host.apply({ good: 'exports.ok=true;' }, 'good');
  assert.equal(s.ghosts, 1);
  host.dispose();
  return { callbacksFromFailedModule: s.ghosts, defect: 'Factory failure removes the module cache entry without releasing its registered listener.' };
});

await observe('R04-reset-aborts-remaining-cleanup', () => {
  const s = { cleaned: [] };
  const host = createModuleHost({ s });
  host.apply({ app: 'require("dep");__meta.hot.dispose(()=>require("s").cleaned.push("app"));', dep: '__meta.hot.dispose(()=>{throw Error("dep dispose failed")});' }, 'app');
  assert.throws(() => host.dispose(), /dep dispose failed/);
  assert.deepEqual(s.cleaned, []);
  return { cleaned: s.cleaned, defect: 'Reverse reset stops at one throwing disposer; later modules and host maps are not cleaned.' };
});

await observe('R05-async-accept-settlement', async () => {
  let release;
  const s = { events: [], gate: new Promise(resolve => { release = resolve; }) };
  const host = createModuleHost({ s });
  const first = 'exports.version=1;__meta.hot.on("vite:afterUpdate",()=>require("s").events.push("afterUpdate"));__meta.hot.accept(async()=>{await require("s").gate;require("s").events.push("accept-complete")});';
  host.apply({ app: first }, 'app');
  s.events.length = 0;
  host.apply({ app: first.replace('version=1', 'version=2') }, 'app');
  const atReturn = [...s.events];
  assert.deepEqual(atReturn, ['afterUpdate']);
  release();
  await Promise.resolve();
  assert.deepEqual(s.events, ['afterUpdate', 'accept-complete']);
  host.dispose();
  return { atApplyReturn: atReturn, afterAsyncCompletion: s.events, defect: 'apply/afterUpdate finishes before an async acceptance callback completes.' };
});

await observe('R06-invalidation-outside-apply', () => {
  const s = { mounts: 0 };
  const host = createModuleHost({ s });
  const app = 'require("s").mounts++;require("s").invalidate=()=>__meta.hot.invalidate();';
  host.apply({ app }, 'app');
  s.invalidate();
  assert.equal(s.mounts, 1);
  const beforeAnotherPublication = s.mounts;
  host.apply({ app }, 'app');
  assert.equal(s.mounts, 2);
  host.dispose();
  return { beforeAnotherPublication, afterAnotherPublication: s.mounts, defect: 'Invalidation takes effect only when another graph is applied.' };
});

await observe('R07-entry-switch-keeps-old-owner', () => {
  const s = { live: new Set() };
  const host = createModuleHost({ s });
  const graph = Object.fromEntries(['a', 'b'].map(id => [id, `require("s").live.add("${id}");__meta.hot.dispose(()=>require("s").live.delete("${id}"));`]));
  host.apply(graph, 'a');
  host.apply(graph, 'b');
  assert.deepEqual([...s.live], ['a', 'b']);
  const owners = [...s.live];
  host.dispose();
  return { liveOwnersAfterEntrySwitch: owners, defect: 'Entry identity changes do not retire the previous entry owner.' };
});

const dir = await mkdtemp(join(tmpdir(), 'solid-hmr-audit-'));
try {
  const a = join(dir, 'a.css'), b = join(dir, 'b.css');
  await writeFile(a, '.hmr-audit-cascade {color:red;}');
  await writeFile(b, '.hmr-audit-cascade {color:blue;}');
  const rules = { a: await compileCss(a, dir), b: await compileCss(b, dir) };
  const target = renderer.node('div');
  target.props = { class: 'hmr-audit-cascade' };
  const read = () => native.snapshot(target).style.color;
  const graph = {
    app: 'require("css-a");require("css-b");',
    'css-a': 'require("styles").setStyleSheet("hmr-audit-a",require("rules").a);__meta.hot.accept();__meta.hot.prune(()=>require("styles").removeStyleSheet("hmr-audit-a"));',
    'css-b': 'require("styles").setStyleSheet("hmr-audit-b",require("rules").b);__meta.hot.accept();__meta.hot.prune(()=>require("styles").removeStyleSheet("hmr-audit-b"));',
  };
  const make = () => createModuleHost({ styles: native, rules });
  await observe('R08-css-import-reorder', () => {
    const host = make();
    host.apply(graph, 'app');
    const before = read();
    const reversed = { ...graph, app: 'require("css-b");require("css-a");' };
    host.apply(reversed, 'app');
    const hot = read();
    host.dispose();
    native.removeStyleSheet('hmr-audit-a');
    native.removeStyleSheet('hmr-audit-b');
    const cold = make();
    cold.apply(reversed, 'app');
    const fresh = read();
    assert.equal(hot, before);
    assert.notEqual(hot, fresh);
    cold.dispose();
    return { before, hotAfterReorder: hot, freshAfterReorder: fresh, defect: 'Hot cascade order differs from a fresh load of the same reordered imports.' };
  });
  await observe('R09-css-dispose-leak', () => {
    native.removeStyleSheet('hmr-audit-a');
    native.removeStyleSheet('hmr-audit-b');
    const host = make();
    host.apply(graph, 'app');
    const before = read();
    host.dispose();
    const after = read();
    assert.equal(after, before);
    return { beforeDispose: before, afterDispose: after, defect: 'Generated CSS modules release sheets only on prune; host.dispose/reset does not release them.' };
  });
} finally {
  native.removeStyleSheet('hmr-audit-a');
  native.removeStyleSheet('hmr-audit-b');
  await rm(dir, { recursive: true, force: true });
}

await observe('R10-native-api-external-parity', () => {
  globalThis.__NATIVE_HMR__ = true;
  native.mountApp(() => renderer.createElement('label'));
  const host = globalThis.__uiModules;
  assert.equal(typeof native.findById, 'function');
  host.apply({ app: 'globalThis.__hmrAuditApi=typeof require("native-host").findById;' }, 'app');
  assert.equal(globalThis.__hmrAuditApi, 'undefined');
  const observed = globalThis.__hmrAuditApi;
  globalThis.uiDispose();
  delete globalThis.__hmrAuditApi;
  delete globalThis.__uiModules;
  delete globalThis.__NATIVE_HMR__;
  return { publicApiType: typeof native.findById, devExternalApiType: observed, defect: 'Actual mountApp external table omits findById and other public native exports.' };
});

const source = await readFile(new URL('../packages/solid-zig/src/module-runtime.js', import.meta.url), 'utf8');
assert.ok(source.includes('for (const callback of record.disposes) callback(data.get(id));'));
const report = JSON.stringify({ runtime: process.version, scope: 'Node module-host/Solid/CSS reproductions; no QuickJS/native-window execution', results }, null, 2) + '\n';
if (process.argv[2] === '--output' && process.argv[3]) {
  await writeFile(process.argv[3], report, 'utf8');
  console.log(`Recorded ${results.filter(result => result.status === 'reproduced').length}/${results.length} current-behavior reproductions to ${process.argv[3]}`);
} else console.log(report);
if (results.some(result => result.status === 'probe-error')) process.exitCode = 1;
