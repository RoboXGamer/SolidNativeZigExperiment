import { mkdir, writeFile, rename, readFile, readdir } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { randomUUID, createHash } from 'node:crypto';
export async function compatibility(configFile = resolve('vite.config.mjs')) {
  const hash = createHash('sha256');
  const files = ['package.json', 'pnpm-lock.yaml', 'build.zig', 'build.zig.zon', configFile];
  async function scan(dir) {
    for (const entry of await readdir(dir, { withFileTypes: true })) {
      const file = join(dir, entry.name);
      if (entry.isDirectory() && !entry.name.startsWith('.') && !['fixtures', 'tests', 'node_modules', 'zig-out'].includes(entry.name)) await scan(file);
      else if (entry.isFile() && /\.(?:js|json|zig|c|cpp|h)$/.test(entry.name) && !/^ui-(?:bundle|hmr)/.test(entry.name)) files.push(file);
    }
  }
  for (const dir of ['packages/solid-zig/src', 'modules', 'src']) await scan(dir);
  for (const file of [...new Set(files)].sort()) { hash.update(file); hash.update(await readFile(file)); }
  return hash.digest('hex');
}
export async function atomicWrite(file, value, signal, onRetry = () => {}) {
  const temp = file + '.tmp';
  await writeFile(temp, value);
  for (let attempt = 0; ; attempt++) {
    signal?.throwIfAborted();
    try { await rename(temp, file); return; } catch (error) {
      if (attempt === 7 || !['EPERM', 'EBUSY', 'EACCES'].includes(error.code)) throw error;
      onRetry({ attempt: attempt + 1, code: error.code });
      await new Promise(resolve => setTimeout(resolve, 20 * (attempt + 1)));
    }
  }
}
export async function createSession(entry, port, configFile = resolve('vite.config.mjs')) {
  const session = randomUUID(), dir = resolve('.zig-cache/hmr', session);
  await mkdir(dir, { recursive: true });
  const manifest = { protocol: 1, session, entry, port, configFile, compatibility: await compatibility(configFile), dir, path: join(dir, 'graph.js'), status: join(dir, 'status.json'), bundle: join(dir, 'bootstrap', 'ui-bundle.js') };
  await writeFile(join(dir, 'session.json'), JSON.stringify(manifest));
  return manifest;
}
export function nativeEnv(session) {
  return { DRAFT1_HMR: '1', DRAFT1_HMR_PATH: session.path, DRAFT1_HMR_STATUS: session.status, DRAFT1_HMR_SESSION: session.session, DRAFT1_HMR_ENTRY: session.entry, DRAFT1_HMR_COMPATIBILITY: session.compatibility };
}
