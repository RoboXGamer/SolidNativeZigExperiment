import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { mkdtemp, mkdir, readFile, writeFile, rm } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { randomBytes } from 'node:crypto';
import { build } from 'vite';
import { Driver } from './driver.mjs';
import { nativeEnv } from './hmr-session.mjs';
import { stopNative } from './native-process.mjs';

export const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
export async function until(read, label, timeout = 20000) {
  const deadline = performance.now() + timeout; let last;
  while (performance.now() < deadline) {
    try { const result = await read(); if (result) return result; } catch (error) { last = error; }
    await delay(20);
  }
  throw Error(`Timed out: ${label} ${last || ''}`);
}
export function buildHost() {
  const result = spawnSync('zig', ['build', '-Ddriver=true'], { encoding: 'utf8', timeout: 600000 });
  assert.equal(result.status, 0, result.stdout + result.stderr);
}
export class HmrFixture {
  static async create(name, options = {}) {
    const fixture = new HmrFixture();
    fixture.name = name; fixture.options = options;
    fixture.dir = await mkdtemp(resolve('tests/.hmr-'));
    fixture.entry = '/' + join(fixture.dir, 'app.jsx').slice(resolve('.').length + 1).replaceAll('\\', '/');
    fixture.port = options.port || 20000 + Math.floor(Math.random() * 30000);
    fixture.output = ''; fixture.nativeOutput = ''; fixture.events = [];
    await writeFile(join(fixture.dir, 'app.jsx'), `import {mountApp} from '@zig-ui/solid';import {a} from './a.js';import {b} from './b.js';globalThis.boots=(globalThis.boots||0)+1;if(boots!==1)throw Error('duplicate boot');mountApp(()=> <label>{a}:{b}</label>);if(import.meta.hot)import.meta.hot.dispose(()=>{globalThis.boots--});`);
    await fixture.setPair(1);
    return fixture;
  }
  async setPair(value) {
    await Promise.all(['a', 'b'].map(id => writeFile(join(this.dir, id + '.js'), `export const ${id}=${value};`)));
  }
  async startProducer(extraEnv = {}) {
    this.output = ''; this.events = [];
    this.producer = spawn(process.execPath, ['tools/dev.mjs'], {
      windowsHide: true, env: { ...process.env, DRAFT1_ENTRY: this.entry, DRAFT1_VITE_PORT: String(this.port), DRAFT1_HMR_TEST: '1', ...(this.options.configFile ? { DRAFT1_VITE_CONFIG: this.options.configFile } : {}), ...extraEnv },
      stdio: ['ignore', 'pipe', 'pipe', 'ipc'],
    });
    this.producer.stdout.on('data', c => { this.output += c; });
    this.producer.stderr.on('data', c => { this.output += c; });
    this.producer.on('message', event => this.events.push(event));
    const path = await until(() => this.output.match(/; session (.+session\.json)/)?.[1]?.trim(), 'producer manifest');
    this.manifest = JSON.parse(await readFile(path, 'utf8'));
    await until(() => this.output.includes('[native-hmr] published'), 'initial publication');
    return this;
  }
  async buildBootstrap() {
    await build({ mode: 'native-hmr', logLevel: 'silent', ...(this.options.configFile ? { configFile: this.options.configFile } : {}), build: { outDir: join(this.manifest.dir, 'bootstrap'), lib: { entry: resolve('tools/hmr-bootstrap.js'), name: 'NativeBootstrap', formats: ['iife'], fileName: () => 'ui-bundle.js' } } });
  }
  async startHost(env = {}, beforeConnect) {
    const pipe = `hmr-boundary-${process.pid}-${randomBytes(5).toString('hex')}`, token = randomBytes(24).toString('hex');
    this.nativeOutput = '';
    this.native = spawn('zig-out/bin/windows.exe', [], { windowsHide: true, env: { ...process.env, ...nativeEnv(this.manifest), SOLID_NATIVE_PIPE: pipe, SOLID_NATIVE_TOKEN: token, SOLID_NATIVE_DRIVER_HIDDEN: '1', SOLID_NATIVE_DRIVER_SOURCE: this.manifest.bundle, ...env }, stdio: ['ignore', 'ignore', 'pipe'] });
    this.native.stderr.on('data', c => { this.nativeOutput += c; });
    await beforeConnect?.();
    this.driver = await Driver.connect({ pipe, token });
    await this.receipt(); return this;
  }
  async receipt(minimum = 1, phase = 'presented') {
    return until(async () => { const value = await this.readReceipt(); return value.revision >= minimum && value.phase === phase ? value : null; }, `${this.name}: revision ${minimum} ${phase}`);
  }
  async readReceipt() { return JSON.parse(await readFile(this.manifest.status, 'utf8')); }
  async text() { return (await this.driver.tree()).filter(n => n.type === 'text').map(n => n.text).join(''); }
  async expectText(text) { await until(async () => (await this.text()) === text, `${this.name}: text ${text}`); }
  async control(op, payload = {}) {
    const id = randomBytes(8).toString('hex');
    this.producer.send({ id, op, ...payload });
    const event = await until(() => this.events.find(e => e.id === id), `control ${op}`);
    if (event.error) throw Error(event.error); return event.result;
  }
  async closeHost() {
    if (this.driver) {
      try { await this.driver.command('close'); } finally { this.driver.disconnect(); this.driver = null; }
      await until(() => this.native.exitCode !== null, 'normal native close');
      assert.equal(this.native.exitCode, 0);
    }
  }
  async dispose() {
    this.driver?.disconnect(); this.driver = null;
    await stopNative(this.native); await stopNative(this.producer);
    await rm(this.dir, { recursive: true, force: true });
  }
  diagnostics(error) { return Error(`${error.stack || error}\nPRODUCER:\n${this.output}\nNATIVE:\n${this.nativeOutput}`); }
}
export async function lockFile(path, share = 'None') {
  const child = spawn('powershell', ['-NoProfile', '-File', resolve('tests/fixtures/lock-hmr-file.ps1'), '-Path', path, '-Share', share], { windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
  let output = ''; child.stdout.on('data', c => { output += c; }); child.stderr.on('data', c => { output += c; });
  try { await until(() => output.includes('LOCKED'), `Windows file lock: ${output}`, 10000); }
  catch (error) { await stopNative(child); throw error; }
  return async () => { child.stdin.end('\n'); await until(() => child.exitCode !== null, 'release file lock'); assert.equal(child.exitCode, 0, output); };
}
