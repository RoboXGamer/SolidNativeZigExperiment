import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';

const directory = new URL('../modules/ui_core/fixtures/', import.meta.url);
const cases = JSON.parse(fs.readFileSync(new URL('positioning-source.json', directory), 'utf8'));
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'positioning-edge-'));
const process = spawn('C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe', [
  '--headless', '--no-first-run', '--no-default-browser-check', '--remote-debugging-port=0',
  '--remote-debugging-address=127.0.0.1', `--user-data-dir=${profile}`, 'about:blank',
], { windowsHide: true, stdio: 'ignore' });
let socket;
const pending = new Map();
let sequence = 0;
function command(method, params = {}) {
  const id = ++sequence;
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => { pending.delete(id); reject(Error(`CDP timeout: ${method}`)); }, 15000);
    pending.set(id, { resolve, reject, timeout });
    socket.send(JSON.stringify({ id, method, params }));
  });
}
try {
  let port;
  for (let attempt = 0; attempt < 200; attempt++) {
    const file = path.join(profile, 'DevToolsActivePort');
    if (fs.existsSync(file)) { port = fs.readFileSync(file, 'utf8').split('\n')[0].trim(); break; }
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  if (!port) throw Error('Headless Edge did not expose its debugging port');
  const pages = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
  const page = pages.find(p => p.type === 'page');
  if (!page) throw Error('Headless Edge did not create its reference page');
  socket = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => { socket.addEventListener('open', resolve, { once: true }); socket.addEventListener('error', reject, { once: true }); });
  socket.addEventListener('message', event => {
    const message = JSON.parse(event.data), task = pending.get(message.id);
    if (!task) return;
    pending.delete(message.id); clearTimeout(task.timeout);
    if (message.error) task.reject(Error(JSON.stringify(message.error))); else task.resolve(message.result);
  });
  await command('Emulation.setDeviceMetricsOverride', { width: 400, height: 300, deviceScaleFactor: 1, mobile: false });
  const version = await command('Browser.getVersion');
  const font = fs.readFileSync(new URL('Ahem.ttf', directory));
  const loaded = await command('Runtime.evaluate', { expression: `(async () => { const f = new FontFace('OracleAhem', 'url(data:font/ttf;base64,${font.toString('base64')})'); await f.load(); document.fonts.add(f); return f.status; })()`, awaitPromise: true, returnByValue: true });
  if (loaded.result?.value !== 'loaded') throw Error(`Ahem reference font did not load: ${JSON.stringify(loaded)}`);
  const result = [];
  for (const c of cases) {
    const expression = `(${function capture(tree) {
      document.body.innerHTML = '';
      document.body.style.cssText = 'margin:0;font:10px/10px OracleAhem';
      function build(n) {
        const el = document.createElement('div'); el.dataset.id = n.id;
        if (n.text) el.textContent = n.text;
        for (const [key, value] of Object.entries(n.style)) el.style[key] = typeof value === 'number' && !['zIndex','opacity','flexGrow','flexShrink','order'].includes(key) ? value + 'px' : value;
        n.children.forEach(child => el.append(build(child))); return el;
      }
      document.body.append(build(tree));
      return [...document.querySelectorAll('[data-id]')].map(el => {
        const b = el.getBoundingClientRect(), s = getComputedStyle(el);
        const radii = ['borderTopLeftRadius','borderTopRightRadius','borderBottomRightRadius','borderBottomLeftRadius'].map(k => { const p = s[k].split(' ').map(parseFloat); return [p[0],p[1] ?? p[0]]; });
        return { id: Number(el.dataset.id), x:b.x, y:b.y, width:b.width, height:b.height, radii };
      });
    }})(${JSON.stringify(c.tree)})`;
    const output = await command('Runtime.evaluate', { expression, returnByValue: true });
    if (output.exceptionDetails) throw Error(JSON.stringify(output.exceptionDetails));
    result.push({ ...c, expected: output.result.value });
  }
  fs.writeFileSync(new URL('positioning-browser.json', directory), JSON.stringify({ oracle: { ...version, engine: 'installed Microsoft Edge', platform: `${os.platform()} ${os.release()} ${os.arch()}`, viewport:[400,300], dpr:1, font:'10px/10px OracleAhem', fontSource:'https://wpt.live/fonts/Ahem.ttf', fontSha256:createHash('sha256').update(font).digest('hex'), references: ['css/css-logical/logical-values-float-clear-1.html','css/css-logical/logical-values-float-clear-2.html','https://drafts.csswg.org/css-position-3/','https://drafts.csswg.org/css-logical-1/'] }, cases: result }, null, 2) + '\n');
  console.log(`Captured ${result.length} reference cases: ${version.product}`);
} finally {
  if (socket?.readyState === WebSocket.OPEN) { await command('Browser.close').catch(() => {}); socket.close(); }
  for (const task of pending.values()) clearTimeout(task.timeout);
  if (process.exitCode === null) process.kill();
}
