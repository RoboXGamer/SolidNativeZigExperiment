import { createServer, build } from 'vite';
import { readFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { createHash } from 'node:crypto';
import { configureExample, projectRoot } from './example-entry.mjs';
import { startNative, stopNative } from './native-process.mjs';
import { compileGraph } from './hmr-compiler.mjs';
import { createSession, atomicWrite, compatibility } from './hmr-session.mjs';
process.chdir(projectRoot);
const selection = configureExample(process.argv.slice(2));
if (selection.args.some(arg => arg !== '--app')) throw Error(`Unknown dev arguments: ${selection.args.join(' ')}`);
const port = Number(process.env.DRAFT1_VITE_PORT || 5173);
const configFile = resolve(process.env.DRAFT1_VITE_CONFIG || 'vite.config.mjs');
const session = await createSession(selection.entry, port, configFile);
let server, online = false, serverEpoch = 0;
const origin = `http://127.0.0.1:${port}`;
let stopping = false, pending, controller, ws, reconnect, child, polling;
let sourceGeneration = 0, requested = 0, finished = 0, revision = 0, reload = false, restartRequired = false;
let lastReceipt = '';
async function publish() {
  while (!stopping && finished !== requested) {
    const generation = sourceGeneration, request = requested, full = reload;
    controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(Error('Graph compilation exceeded 10 seconds')), 10000);
    try {
      const graph = restartRequired ? {} : await compileGraph({ origin, entry: session.entry, signal: controller.signal, generation: () => sourceGeneration });
      if (generation !== sourceGeneration || request !== requested || stopping) continue;
      const packet = { protocol: 1, session: session.session, entry: session.entry, compatibility: session.compatibility, revision: ++revision, type: restartRequired ? 'restart-required' : full ? 'full-reload' : 'update', graph };
      const source = `globalThis.__uiReceive(${JSON.stringify(packet)});\n`;
      if (Buffer.byteLength(source) > 32 * 1024 * 1024) throw Error('Serialized graph exceeds 32 MiB');
      await atomicWrite(session.path, source, controller.signal, retry => console.warn('[native-hmr] rename-retry', JSON.stringify(retry)));
      if (generation !== sourceGeneration || stopping) continue;
      reload = false; finished = request;
      console.log(`[native-hmr] published session=${session.session} revision=${revision} modules=${Object.keys(graph).length} bytes=${Buffer.byteLength(source)} type=${packet.type}`);
    } catch (error) {
      if (generation !== sourceGeneration || request !== requested) continue;
      if (!stopping && ['EPERM', 'EBUSY', 'EACCES'].includes(error.code)) {
        console.warn('[native-hmr] publication-retry: latest revision retained');
        await new Promise(resolve => setTimeout(resolve, 250));
        continue;
      }
      finished = request; console.error('[native-hmr] compile-failed', error.message);
    } finally { clearTimeout(timeout); }
  }
}
function request(full = false) {
  requested++; reload ||= full;
  controller?.abort(Error('Superseded source generation'));
  if (online && !pending) pending = publish().finally(() => { pending = undefined; if (!stopping && finished !== requested) request(); });
}
function sourceChanged(event, file) {
  if (!['add', 'change', 'unlink'].includes(event)) return;
  const path = file.replaceAll('\\', '/');
  if (/\/(?:\.zig-cache|zig-out|node_modules)\//.test(path) || /\/src\/ui-(?:bundle|hmr)/.test(path)) return;
  sourceGeneration++; controller?.abort(Error('Source changed'));
  const rootConfig = ['vite.config.mjs', 'pnpm-lock.yaml', 'package.json', 'build.zig', 'build.zig.zon'].some(name => resolve(file) === join(projectRoot, name));
  if (resolve(file) === configFile || rootConfig || (/\/(?:packages\/solid-zig\/src|modules|src)\//.test(path) && /\.(?:[cm]?[jt]sx?|json|zig|c|cpp|h)$/.test(path))) {
    restartRequired = true;
    console.error('[native-hmr] restart-required: embedded runtime changed; restart pnpm dev');
    request();
  } else request(); // also covers deletion and recreation without an HMR message
}
function bindServer(next) {
  server = next; online = false; sourceGeneration++; controller?.abort(Error('Vite server restarting'));
  const epoch = ++serverEpoch;
  const http = next.httpServer; // configureServer receives Vite's forwarding proxy
  next.watcher.on('all', sourceChanged);
  http.once('listening', async () => {
    if (stopping || serverEpoch !== epoch) return;
    if (await compatibility(configFile) !== session.compatibility) {
      restartRequired = true;
      console.error('[native-hmr] restart-required: runtime/config fingerprint changed');
    }
    if (stopping || serverEpoch !== epoch) return;
    online = true; clearTimeout(reconnect); ws?.close(); connect(); request(true);
  });
  http.once('close', () => {
    if (serverEpoch === epoch) { online = false; controller?.abort(Error('Vite disconnected')); }
  });
}
let retry = 100;
function connect() {
  if (stopping || !online) return;
  const socket = new WebSocket(`ws://127.0.0.1:${port}/?token=${encodeURIComponent(server.config.webSocketToken)}`, 'vite-hmr');
  ws = socket;
  socket.addEventListener('open', () => { if (stopping || socket !== ws) return; retry = 100; console.log('[native-hmr] connected; resynchronizing'); request(true); });
  socket.addEventListener('message', event => {
    if (stopping) return;
    let message; try { message = JSON.parse(event.data); } catch { return; }
    if (message.type === 'update' || message.type === 'full-reload' || message.event === 'native:css') request(message.type === 'full-reload');
    if (message.type === 'error') console.error('[vite]', message.err?.message);
  });
  socket.addEventListener('error', () => console.error('[native-hmr] disconnected'));
  socket.addEventListener('close', () => {
    if (stopping || socket !== ws) return;
    reload = true; reconnect = setTimeout(connect, retry); retry = Math.min(3000, retry * 2);
  });
}
async function stop(code = 0) {
  if (stopping) return; stopping = true;
  const exitCode = typeof code === 'number' ? code : 0;
  // A restart can still own a not-yet-listening server when stop arrives.
  // Exit this owned producer after close, or at the deadline; do not leave
  // restart-created sockets/watchers keeping an apparently stopped CLI alive.
  const deadline = setTimeout(() => process.exit(exitCode), 3000);
  clearTimeout(reconnect); clearInterval(polling); controller?.abort(Error('Shutdown')); ws?.close();
  await stopNative(child);
  await Promise.allSettled([pending, server?.close()]);
  clearTimeout(deadline);
  if (process.connected) process.disconnect();
  process.exit(exitCode);
}
process.on('SIGINT', () => void stop()); process.on('SIGTERM', () => void stop());
// An inherited IPC channel is available only to an owning test process.
if (process.send) process.on('message', message => {
  if (message === 'test-disconnect') ws?.close();
  if (process.env.DRAFT1_HMR_TEST !== '1' || !message?.id) return;
  if (message.op === 'stop') { process.send({ id: message.id, result: { stopping: true } }, () => void stop()); return; }
  void (async () => {
    try {
      if (message.op === 'restart-vite') await server.restart();
      else if (message.op !== 'describe') throw Error(`Unknown test control: ${message.op}`);
      if (process.connected) process.send({ id: message.id, result: { session: session.session, tokenDigest: createHash('sha256').update(server.config.webSocketToken).digest('hex'), connected: ws?.readyState === 1, online } });
    } catch (error) { if (process.connected) process.send({ id: message.id, error: String(error) }); }
  })();
});
try {
  server = await createServer({ mode: 'native-hmr', configFile, cacheDir: join(session.dir, 'vite'), plugins: [{ name: 'native-session-lifecycle', configureServer: bindServer }], server: { host: '127.0.0.1', port, strictPort: true } });
  await server.listen();
  // The listening hook performs fingerprint validation before starting work.
  while (!online && !stopping) await new Promise(resolve => setTimeout(resolve, 10));
  request(); await pending;
  polling = setInterval(async () => {
    try { const receipt = await readFile(session.status, 'utf8'); if (receipt !== lastReceipt) { lastReceipt = receipt; console.log('[native-hmr] receipt', receipt); } } catch {}
  }, 250);
  console.log(`[example] ${session.entry}; session ${join(session.dir, 'session.json')}`);
  if (selection.args.includes('--app')) {
    await build({ mode: 'native-hmr', configFile, build: { outDir: join(session.dir, 'bootstrap'), lib: { entry: join(projectRoot, 'tools/hmr-bootstrap.js'), name: 'NativeBootstrap', formats: ['iife'], fileName: () => 'ui-bundle.js' } } });
    if (!stopping) {
      child = startNative(session);
      child.on('error', error => { console.error(error); void stop(1); });
      child.on('exit', code => void stop(code ?? 1));
    }
  } else console.log(`[native-hmr] run pnpm dev:app --session ${join(session.dir, 'session.json')}`);
} catch (error) { console.error(error); await stop(1); }
