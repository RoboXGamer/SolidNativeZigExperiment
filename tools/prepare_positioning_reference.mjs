import fs from 'node:fs';
import { snapshot } from '../packages/solid-zig/src/native.js';

const file = new URL('../modules/ui_core/fixtures/positioning-browser.json', import.meta.url);
const data = JSON.parse(fs.readFileSync(file, 'utf8'));
function node(input, parent = null) {
  const n = { id: input.id, type: input.text ? 'text' : 'column', text: input.text ?? '', props: { style: input.style }, children: [], parent };
  n.children = input.children.map(child => node(child, n));
  return n;
}
const fixtures = data.cases.map(c => ({ name: c.name, scene: JSON.stringify({ id: 0, type: 'root', style: { display: 'block', width: 400, height: 300, padding: 0 }, children: [snapshot(node(c.tree))] }), expected: c.expected }));
fs.writeFileSync(new URL('../modules/ui_core/fixtures/positioning-native.json', import.meta.url), JSON.stringify(fixtures, null, 2) + '\n');
console.log(`Prepared ${fixtures.length} browser->bridge->native comparison fixtures.`);
