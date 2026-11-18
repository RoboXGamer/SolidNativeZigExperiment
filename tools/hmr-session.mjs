import { mkdir, writeFile, rename, readFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { randomUUID, createHash } from 'node:crypto';
export async function compatibility() {
  const hash = createHash('sha256');
  for (const file of ['package.json', 'pnpm-lock.yaml', 'vite.config.mjs', 'packages/solid-zig/src/native.js', 'packages/solid-zig/src/renderer.js', 'packages/solid-zig/src/module-runtime.js', 'modules/solid_bridge/quickjs_bridge.c'])
    hash.update(await readFile(file));
  return hash.digest('hex');
}
export async function atomicWrite(file, value, signal) {
  const temp = file + '.tmp';
  await writeFile(temp, value);
  for (let attempt = 0; ; attempt++) {
    signal?.throwIfAborted();
    try { await rename(temp, file); return; } catch (error) {
      if (attempt === 7 || !['EPERM', 'EBUSY', 'EACCES'].includes(error.code)) throw error;
      await new Promise(resolve => setTimeout(resolve, 20 * (attempt + 1)));
    }
  }
}
export async function createSession(entry, port) {
  const session = randomUUID(), dir = resolve('.zig-cache/hmr', session);
  await mkdir(dir, { recursive: true });
  const manifest = { protocol: 1, session, entry, port, compatibility: await compatibility(), dir, path: join(dir, 'graph.js'), status: join(dir, 'status.json'), bundle: join(dir, 'bootstrap', 'ui-bundle.js') };
  await writeFile(join(dir, 'session.json'), JSON.stringify(manifest));
  return manifest;
}
export function nativeEnv(session) {
  return { DRAFT1_HMR: '1', DRAFT1_HMR_PATH: session.path, DRAFT1_HMR_STATUS: session.status, DRAFT1_HMR_SESSION: session.session, DRAFT1_HMR_ENTRY: session.entry, DRAFT1_HMR_COMPATIBILITY: session.compatibility };
}
