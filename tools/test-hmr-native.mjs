import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { mkdtemp, mkdir, readFile, writeFile, rm, unlink } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { randomBytes } from 'node:crypto';
import { build } from 'vite';
import { Driver } from './driver.mjs';
import { nativeEnv } from './hmr-session.mjs';
import { stopNative } from './native-process.mjs';
const sessions = [], measurements = [];
const root = await mkdtemp(resolve('tests/.hmr-'));
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
async function waitFor(read, label, timeout = 20000) {
  const until = Date.now() + timeout; let last;
  while (Date.now() < until) {
    try { const result = await read(); if (result) return result; } catch (error) { last = error; }
    await delay(30);
  }
  throw Error(`Timed out: ${label} ${last || ''}\n` + sessions.map(s => s.output + s.nativeOutput).join('\n'));
}
function app(text) { return `import {mountApp, findById} from '@zig-ui/solid';import {createSignal} from 'solid-js';import './style.css';import {value} from './dep.js';globalThis.coldStarts=(globalThis.coldStarts||0)+1;if(globalThis.coldStarts>1)throw Error('duplicate cold initialization');mountApp(()=>{const[n,set]=createSignal(0,{ownedWrite:true});return <div><label testId="result">${text}:{value}:{n()}</label><button testId="inc" onClick={()=>set(n()+1)}>increment</button><button testId="lazy" onClick={()=>import('./lazy.js').then(m=>m.apply())}>lazy</button></div>});if(import.meta.hot)import.meta.hot.dispose(()=>{globalThis.coldStarts--});`; }
async function start(index) {
  console.log('Starting isolated HMR session', index);
  const dir = join(root, String(index)); await mkdir(dir);
  await writeFile(join(dir, 'app.jsx'), app('initial'));
  await writeFile(join(dir, 'dep.js'), 'export const value=1;');
  await writeFile(join(dir, 'lazy.js'), `export function apply(){console.log('HMR lazy import executed')}`);
  await writeFile(join(dir, 'style.css'), 'label {color:red;}');
  const entry = '/' + join(dir, 'app.jsx').slice(resolve('.').length + 1).replaceAll('\\', '/');
  const s = { dir, entry, output: '', nativeOutput: '' }; sessions.push(s);
  s.producer = spawn(process.execPath, ['tools/dev.mjs'], { env: { ...process.env, DRAFT1_ENTRY: entry, DRAFT1_VITE_PORT: String(19000 + index + process.pid % 15000) }, stdio: ['ignore', 'pipe', 'pipe', 'ipc'] });
  s.producer.stdout.on('data', c => s.output += c); s.producer.stderr.on('data', c => s.output += c);
  const manifest = await waitFor(() => s.output.match(/; session (.+session\.json)/)?.[1]?.trim(), 'manifest');
  s.manifest = JSON.parse(await readFile(manifest, 'utf8'));
  console.log('Published isolated graph', index);
  await build({ mode: 'native-hmr', logLevel: 'warn', build: { outDir: join(s.manifest.dir, 'bootstrap'), lib: { entry: resolve('tools/hmr-bootstrap.js'), name: 'NativeBootstrap', formats: ['iife'], fileName: () => 'ui-bundle.js' } } });
  const pipe = `hmr-${process.pid}-${index}`, token = randomBytes(24).toString('hex');
  s.native = spawn('zig-out/bin/windows.exe', [], { windowsHide: true, env: { ...process.env, ...nativeEnv(s.manifest), ...(index === 0 ? { SOLID_NATIVE_TEST_SCENE_FAILURE: '1' } : {}), SOLID_NATIVE_PIPE: pipe, SOLID_NATIVE_TOKEN: token, SOLID_NATIVE_DRIVER_HIDDEN: '1', SOLID_NATIVE_DRIVER_SOURCE: s.manifest.bundle }, stdio: ['ignore', 'ignore', 'pipe'] });
  s.native.stderr.on('data', c => s.nativeOutput += c);
  s.driver = await Driver.connect({ pipe, token });
  console.log('Connected native driver', index);
  await receipt(s); return s;
}
async function receipt(s, minimum = 1, phase = 'presented') {
  return waitFor(async () => { const value = JSON.parse(await readFile(s.manifest.status, 'utf8')); return value.revision >= minimum && value.phase === phase ? value : null; }, `receipt ${minimum} ${phase}`);
}
const text = async s => (await s.driver.tree()).filter(n => n.type === 'text').map(n => n.text).join('');
async function edit(s, file, content, expected) {
  const before = JSON.parse(await readFile(s.manifest.status, 'utf8')).revision;
  const at = performance.now(); await writeFile(join(s.dir, file), content);
  await receipt(s, before + 1);
  await waitFor(async () => (await text(s)).includes(expected), expected);
  measurements.push(performance.now() - at);
}
try {
  const compile = spawnSync('zig', ['build', '-Ddriver=true'], { encoding: 'utf8', timeout: 600000 });
  assert.equal(compile.status, 0, compile.stdout + compile.stderr);
  const a = await start(0), b = await start(1);
  assert.notEqual(a.manifest.session, b.manifest.session);
  assert.match(await text(a), /initial:1/);
  await edit(a, 'dep.js', 'export const value=2;', 'initial:2');
  assert.match(a.nativeOutput, /InjectedSceneFailure/);
  assert.match(await text(b), /initial:1/, 'second session is isolated');
  const previous = JSON.parse(await readFile(a.manifest.status, 'utf8')).revision;
  await writeFile(join(a.dir, 'dep.js'), `throw Error('expected bad factory');export const value=3;`);
  await receipt(a, previous + 1, 'failed');
  assert.equal(a.native.exitCode, null);
  await edit(a, 'dep.js', 'export const value=4;', 'initial:4');
  let before = JSON.parse(await readFile(a.manifest.status, 'utf8')).revision;
  const interruptedAt = performance.now();
  await writeFile(join(a.dir, 'dep.js'), 'while(true){};export const value=40;');
  await receipt(a, before + 1, 'failed');
  assert.ok(performance.now() - interruptedAt < 12000, 'HMR loop interrupt is bounded');
  await edit(a, 'dep.js', 'export const value=41;', 'initial:41');
  before = JSON.parse(await readFile(a.manifest.status, 'utf8')).revision;
  await writeFile(join(a.dir, 'dep.js'), `Promise.reject(Error('expected HMR rejection'));export const value=42;`);
  await receipt(a, before + 1, 'failed');
  await edit(a, 'dep.js', 'export const value=43;', 'initial:43');
  await unlink(join(a.dir, 'dep.js'));
  await delay(300);
  await edit(a, 'dep.js', 'export const value=5;', 'initial:5');
  await a.driver.command('click', { target: { testId: 'inc' } });
  await waitFor(async () => (await text(a)).includes('initial:5:1'), 'signal increment');
  await edit(a, 'style.css', 'label {color:blue;}', 'initial:5');
  assert.match(await text(a), /initial:5:1/, 'CSS update preserves component state');
  await a.driver.command('click', { target: { testId: 'lazy' } });
  assert.ok((await a.driver.command('logs')).logs.lines.includes('HMR lazy import executed'));
  before = JSON.parse(await readFile(a.manifest.status, 'utf8')).revision;
  a.producer.send('test-disconnect');
  await receipt(a, before + 1);
  assert.match(await text(a), /initial:5/);
  const ownGraph = await readFile(b.manifest.path, 'utf8');
  await writeFile(b.manifest.path, await readFile(a.manifest.path, 'utf8'));
  await delay(700);
  assert.match(await text(b), /initial:1/, 'foreign session leaves last-good app intact');
  await writeFile(b.manifest.path, ownGraph);
  const baseline = (await a.driver.command('metrics')).quickjs;
  for (let i = 6; i < 26; i++) await edit(a, 'dep.js', `export const value=${i};`, `initial:${i}`);
  await Promise.all(Array.from({ length: 20 }, (_, i) => writeFile(join(a.dir, 'dep.js'), `export const value=${30 + i};`)));
  // A final completed write defines the required latest source after a save burst.
  await edit(a, 'dep.js', 'export const value=99;', 'initial:99');
  const metrics = await a.driver.command('metrics');
  assert.equal(metrics.quickjs.roots, baseline.roots, 'timer callback roots stay bounded');
  assert.ok(metrics.quickjs.live_bytes < baseline.live_bytes + 4 * 1024 * 1024, 'VM retained bytes stay bounded');
  await a.driver.command('close'); a.driver.disconnect(); a.driver = null;
  await waitFor(() => a.native.exitCode === 0, 'normal native close');
  measurements.sort((x, y) => x - y);
  console.log(JSON.stringify({ scenarios: 'two sessions; exactly-once bootstrap; dependency edit; factory failure/correction; interrupted factory/correction; unhandled rejection/correction; delete/recreate; CSS state preservation; lazy import; WebSocket reconnect; foreign-session rejection; scene failure recovery; 20 edits; burst/latest; normal close', edits: measurements.length, p50Ms: measurements[Math.floor(measurements.length * .5)], p95Ms: measurements[Math.floor(measurements.length * .95)], quickjsBefore: baseline, quickjsAfter: metrics.quickjs }, null, 2));
} finally {
  for (const s of sessions) {
    s.driver?.disconnect(); await stopNative(s.native); await stopNative(s.producer);
  }
  await rm(root, { recursive: true, force: true });
}
