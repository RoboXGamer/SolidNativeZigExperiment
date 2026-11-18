import { createServer, build } from 'vite';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { configureExample, projectRoot } from './example-entry.mjs';
import { startNative, stopNative } from './native-process.mjs';
import { compileGraph } from './hmr-compiler.mjs';
import { createSession, atomicWrite } from './hmr-session.mjs';
process.chdir(projectRoot);
const selection = configureExample(process.argv.slice(2));
if (selection.args.some(arg => arg !== '--app')) throw Error(`Unknown dev arguments: ${selection.args.join(' ')}`);
const port = Number(process.env.DRAFT1_VITE_PORT || 5173);
const session = await createSession(selection.entry, port);
const server = await createServer({ mode: 'native-hmr', cacheDir: join(session.dir, 'vite'), server: { host: '127.0.0.1', port, strictPort: true } });
await server.listen();
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
      await atomicWrite(session.path, source, controller.signal);
      if (generation !== sourceGeneration || stopping) continue;
      reload = false; finished = request;
      console.log(`[native-hmr] published session=${session.session} revision=${revision} modules=${Object.keys(graph).length} bytes=${Buffer.byteLength(source)} type=${packet.type}`);
    } catch (error) {
      if (generation !== sourceGeneration || request !== requested) continue;
      finished = request; console.error('[native-hmr] compile-failed', error.message);
    } finally { clearTimeout(timeout); }
  }
}
function request(full = false) {
  requested++; reload ||= full;
  controller?.abort(Error('Superseded source generation'));
  if (!pending) pending = publish().finally(() => { pending = undefined; if (!stopping && finished !== requested) request(); });
}
server.watcher.on('all', (event, file) => {
  if (!['add', 'change', 'unlink'].includes(event)) return;
  const path = file.replaceAll('\\', '/');
  if (/\/(?:\.zig-cache|zig-out|node_modules)\//.test(path) || /\/src\/ui-(?:bundle|hmr)/.test(path)) return;
  sourceGeneration++; controller?.abort(Error('Source changed'));
  if ((/\/(?:packages\/solid-zig\/src|modules|src)\//.test(path) && /\.(?:[cm]?[jt]sx?|json|zig|c|cpp|h)$/.test(path)) || /\/(?:vite\.config\.mjs|pnpm-lock\.yaml|package\.json)$/.test(path)) {
    restartRequired = true;
    console.error('[native-hmr] restart-required: embedded runtime changed; restart pnpm dev');
    request();
  } else request(); // also covers deletion and recreation without an HMR message
});
let retry = 100;
function connect() {
  if (stopping) return;
  ws = new WebSocket(`ws://127.0.0.1:${port}/?token=${encodeURIComponent(server.config.webSocketToken)}`, 'vite-hmr');
  ws.addEventListener('open', () => { retry = 100; console.log('[native-hmr] connected; resynchronizing'); request(true); });
  ws.addEventListener('message', event => {
    if (stopping) return;
    let message; try { message = JSON.parse(event.data); } catch { return; }
    if (message.type === 'update' || message.type === 'full-reload' || message.event === 'native:css') request(message.type === 'full-reload');
    if (message.type === 'error') console.error('[vite]', message.err?.message);
  });
  ws.addEventListener('error', () => console.error('[native-hmr] disconnected'));
  ws.addEventListener('close', () => {
    if (stopping) return;
    reload = true; reconnect = setTimeout(connect, retry); retry = Math.min(3000, retry * 2);
  });
}
async function stop(code = 0) {
  if (stopping) return; stopping = true;
  clearTimeout(reconnect); clearInterval(polling); controller?.abort(Error('Shutdown')); ws?.close();
  await stopNative(child);
  // Vite plugin shutdown is bounded even if an owned transform never settles.
  const deadline = setTimeout(() => process.exit(typeof code === 'number' ? code : 0), 3000); deadline.unref();
  await Promise.allSettled([pending, server.close()]);
  clearTimeout(deadline); process.exitCode = typeof code === 'number' ? code : 0;
}
process.on('SIGINT', () => void stop()); process.on('SIGTERM', () => void stop());
// An inherited IPC channel is available only to an owning test process.
if (process.send) process.on('message', message => {
  if (message === 'test-disconnect') ws?.close();
});
try {
  connect(); request(); await pending;
  polling = setInterval(async () => {
    try { const receipt = await readFile(session.status, 'utf8'); if (receipt !== lastReceipt) { lastReceipt = receipt; console.log('[native-hmr] receipt', receipt); } } catch {}
  }, 250);
  console.log(`[example] ${session.entry}; session ${join(session.dir, 'session.json')}`);
  if (selection.args.includes('--app')) {
    await build({ mode: 'native-hmr', build: { outDir: join(session.dir, 'bootstrap'), lib: { entry: join(projectRoot, 'tools/hmr-bootstrap.js'), name: 'NativeBootstrap', formats: ['iife'], fileName: () => 'ui-bundle.js' } } });
    if (!stopping) {
      child = startNative(session);
      child.on('error', error => { console.error(error); void stop(1); });
      child.on('exit', code => void stop(code ?? 1));
    }
  } else console.log(`[native-hmr] run pnpm dev:app --session ${join(session.dir, 'session.json')}`);
} catch (error) { console.error(error); await stop(1); }
