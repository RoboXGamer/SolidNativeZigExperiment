import assert from 'node:assert/strict';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createSignal, flush } from 'solid-js';
import * as r from '../packages/solid-zig/src/renderer.js';
import { mountApp, discoveryWork, resetDiscoveryWork } from '../packages/solid-zig/src/native.js';
import { setStyleSheet, clearStyleSheets } from '../packages/solid-zig/src/stylesheets.js';
import { compileCss } from '../tools/css-compiler.mjs';

const dir = await mkdtemp(join(tmpdir(), 'change-discovery-'));
const flatten = n => [n, ...n.children.flatMap(flatten)];
const read = () => JSON.parse(uiSnapshot());
const get = n => flatten(read()).find(v => v.id === n.id);
const collect = () => JSON.parse(uiFrameChanges());
const commit = () => { const p = collect(); uiCommit(); return p; };
function coldParity(label) {
  const warm = read();
  r.markTreeChanged();
  assert.deepEqual(read(), warm, `${label}: incremental output matches full invalidation`);
  // Diagnostic recomputation is outside the measured transaction.
  commit();
}

try {
  const file = join(dir, 'app.css');
  await writeFile(file, `
    .tile {width:20px;background-color:red;}
    .tile:hover {background-color:blue;}
    .tile:active {opacity:0.5;}
    .tile:focus {cursor:crosshair;}
    .enabled .target {width:33px;}
    .tile:hover + .next {color:green;}
    .tile:hover ~ .later .nested {height:44px;}
    .theme {--size:37px;color:purple;font-size:23px;}
    .variable {width:var(--size,19px);}
    #renamed > .target {height:31px;}
    .logical:hover .target {opacity:0.25;}
    .logical .target {cursor:help;}
    .empty:empty {width:17px;}
    ${Array.from({length:256}, (_,i) => `.irrelevant-${i}:hover {width:${i + 1}px;}`).join('\n')}
  `);
  const rules = await compileCss(file, dir);
  // The runtime accepts logical pseudos in programmatic sheets; the file
  // compiler deliberately rejects them, along with :has and nth selectors.
  rules.find(rule => rule.selector === '.logical:hover .target').selector = '.logical:is(:hover,:active) .target';
  rules.find(rule => rule.selector === '.logical .target').selector = '.logical:not(:hover) .target';
  setStyleSheet('discovery', rules);
  const counts = [];
  const topologyCounts = [];
  for (const size of [32, 512]) {
    let scene, tile, other, branch, target, next, nested, variable, empty, input, setClass, setVariable;
    mountApp(() => {
      scene = r.createElement('div');
      branch = r.createElement('div', {class:'logical'});
      tile = r.createElement('button', {class:'tile'});
      other = r.createElement('button', {class:'tile'});
      target = r.createElement('div', {class:'target'});
      next = r.createElement('div', {class:'next'});
      const later = r.createElement('div', {class:'later'});
      nested = r.createElement('div', {class:'nested'});
      variable = r.createElement('div', {class:'variable'});
      empty = r.createElement('div', {class:'empty'});
      input = r.createElement('input', {value:''});
      const [cls, write] = createSignal('logical', {ownedWrite:true});
      setClass = write;
      r.effect(cls, value => { r.setProp(branch, 'class', value); });
      r.insertNode(later, nested);
      for (const child of [tile, next, later, other, target, variable, empty, input]) r.insertNode(branch, child);
      r.insertNode(scene, branch);
      const [shown, writeShown] = createSignal(variable, {ownedWrite:true});
      setVariable = writeShown;
      r.insert(branch, shown);
      const unrelated = r.createElement('div');
      for (let i=0;i<size;i++) {
        const n = r.createElement('div', {class:`irrelevant-${i % 256}`});
        r.insertNode(n, r.createTextNode(`Unchanged ${i}`));
        r.insertNode(unrelated, n);
      }
      r.insertNode(scene, unrelated);
      return scene;
    });
    flush(); commit();
    uiDispatchPointer(tile.id); commit();
    resetDiscoveryWork();
    uiDispatchPointer(other.id); const switched = commit();
    counts.push({...discoveryWork});
    assert.ok(discoveryWork.prepare < 15, 'unrelated subtrees are not prepared');
    assert.ok(discoveryWork.css < 12, 'unrelated computed styles are not visited');
    assert.ok(discoveryWork.selectors < 40, 'unrelated selector buckets are not tested');
    assert.ok(discoveryWork.bridge < 12, 'bridge visits only dirty identities');
    assert.ok(switched.updates.length > 0);
    resetDiscoveryWork();
    uiDispatchInput(input.id, 'edited'); commit();
    assert.ok(discoveryWork.prepare < 8 && discoveryWork.bridge === 1, 'input mutation stays local');
    assert.equal(get(input).value, 'edited');
    assert.equal(get(next).style.color, '#000000');
    uiDispatchPointer(tile.id, tile.id, tile.id); commit();
    assert.equal(get(tile).style.backgroundColor, '#00f');
    assert.equal(get(tile).style.opacity, 0.5);
    assert.equal(get(tile).style.cursor, 'crosshair');
    assert.equal(get(next).style.color, 'green');
    assert.equal(get(nested).style.heightCss, '44px');
    assert.equal(get(target).style.opacity, 0.25);
    coldParity('hover active focus, sibling descendants and logical pseudos');
    resetDiscoveryWork();
    uiDispatchPointer(other.id); commit();
    assert.ok(discoveryWork.bridge < 12, 'cold diagnostic does not leave a whole-tree pending delta');
    uiDispatchPointer(tile.id, tile.id, tile.id); commit();
    resetDiscoveryWork();
    uiDispatchPointer(tile.id, tile.id, tile.id); commit();
    assert.deepEqual({...discoveryWork}, {prepare:0,css:0,selectors:0,snapshot:0,bridge:0,membership:0});
    uiDispatchPointer(0); commit();
    assert.equal(get(target).style.cursor, 'help');
    setClass('logical enabled theme'); flush(); commit();
    assert.equal(get(target).style.widthCss, '33px');
    assert.equal(get(variable).style.widthCss, '37px');
    assert.equal(get(target).style.fontSize, 23);
    branch.setAttribute('id', 'renamed'); commit();
    assert.equal(get(target).style.heightCss, '31px');
    branch.removeAttribute('id'); commit();
    assert.equal(get(target).style.heightCss, null);
    r.setProp(tile, 'classList', {tile:false});
    r.setProp(tile, 'class', '');
    uiDispatchPointer(tile.id); commit();
    assert.equal(get(tile).style.backgroundColor, '');
    r.setProp(tile, 'classList', {tile:true}); commit();
    assert.equal(get(tile).style.backgroundColor, '#00f');
    const text = r.createTextNode('content');
    resetDiscoveryWork();
    r.insertNode(empty, text); commit();
    topologyCounts.push({...discoveryWork});
    assert.equal(discoveryWork.membership, 1, 'topology index visits only the inserted identity');
    assert.ok(discoveryWork.prepare < 12 && discoveryWork.bridge < 8, 'insertion skips unrelated subtrees');
    assert.equal(get(empty).style.widthCss, null, ':empty invalidates on insertion');
    r.setProp(tile, 'class', 'tile');
    r.insertNode(branch, next, tile); commit();
    assert.notEqual(get(next).style.color, 'green', 'reorder invalidates adjacency');
    r.insertNode(branch, next, branch.children[branch.children.indexOf(tile)+1]); commit();
    assert.equal(get(next).style.color, 'green');
    r.insertNode(scene, tile); commit();
    assert.equal(get(branch).hovered, false, 'stationary target reparent reconciles ancestry');
    assert.notEqual(get(next).style.color, 'green');
    coldParity('class id variables insertion reorder and reparent');
    // A mutation arriving before acknowledgement must be compared to the
    // acknowledged state, not just to the most recently collected packet.
    r.setProp(target, 'style', {width:81});
    const first = uiFrameChanges();
    assert.equal(uiFrameChanges(), first, 'retry is byte-identical');
    r.setProp(variable, 'style', {height:82});
    const second = collect();
    assert.ok(second.updates.some(n => n.id === target.id && n.layout.style.width === 81));
    assert.ok(second.updates.some(n => n.id === variable.id && n.layout.style.height === 82));
    uiCommit();
    assert.equal(collect().updates.length, 0);
    r.setProp(target, 'style', {width:99}); collect();
    r.setProp(target, 'style', {width:81});
    assert.equal(collect().updates.length, 0, 'restoring committed values cancels pending delta');
    uiCommit();
    r.setProp(target, 'style', {width:83}); collect();
    r.setProp(target, 'style', {width:84});
    uiCommit();
    assert.equal(commit().updates.find(n => n.id === target.id).layout.style.width, 84,
      'acknowledgement of an older packet does not clear newer dirtiness');
    r.setProp(target, 'style', {width:81}); commit();
    await Promise.resolve();
    setClass('logical'); flush(); commit();
    assert.equal(get(variable).style.widthCss, '19px', 'async Solid effect invalidates inheritance');
    r.setProp(variable, 'style', {}); commit();
    // Removed identities cannot remain reachable through pending subscriptions.
    r.setProp(variable, 'style', {height:88}); collect();
    setVariable(null); flush();
    const removal = commit();
    assert.ok(removal.removed.includes(variable.id));
    assert.ok(!removal.updates.some(n => n.id === variable.id));
    setVariable(variable); flush();
    assert.ok(commit().nodes.some(n => n.id === variable.id), 'reinsertion restores forgotten dependencies');
    setStyleSheet('discovery', rules); commit();
    coldParity('HMR replacement');
    const hot = join(dir, 'hot.css');
    await writeFile(hot, '.tile:hover {background-color:green;}');
    setStyleSheet('discovery', [...rules, ...await compileCss(hot, dir)]); commit();
    assert.equal(get(tile).style.backgroundColor, 'green', 'HMR changes an already-hovered node');
    setStyleSheet('discovery', rules); commit();
    uiDispose();
  }
  assert.deepEqual(counts[0], counts[1], 'discovery work is independent of unrelated tree and selector count');
  assert.deepEqual(topologyCounts[0], topologyCounts[1], 'topology discovery does not scan unrelated identities');

  // Equal values still change authored ownership masks in the native packet.
  clearStyleSheets();
  let parent, child;
  mountApp(() => {
    parent = r.createElement('div', {style:{visibility:'visible',color:'red'}});
    child = r.createElement('div');
    r.insertNode(parent, child);
    return parent;
  });
  flush(); commit();
  const before = get(child).style.interactionSpecified;
  r.setProp(child, 'style', {visibility:'visible',color:'red'});
  const ownership = commit();
  assert.notEqual(get(child).style.interactionSpecified, before);
  assert.ok(ownership.updates.some(n => n.id === child.id && n.paint), 'equal-value ownership changes cross the bridge');
  r.setProp(parent, 'style', {visibility:'hidden',color:'blue'}); commit();
  assert.equal(get(child).style.visibility, 'visible');
  r.setProp(child, 'style', {}); commit();
  assert.equal(get(child).style.visibility, 'hidden');
  assert.equal(get(child).style.color, 'blue');
  coldParity('authored versus inherited ownership');
  // Inline nested rules use the separate structural engine. Dependencies on
  // sibling order and the classes of filtered siblings must survive caching.
  clearStyleSheets();
  let first, second, holder;
  mountApp(() => {
    holder = r.createElement('div');
    first = r.createElement('div', {class:'eligible'});
    second = r.createElement('div', {class:'eligible', style:{
      ':nth-child(2 of .eligible)': {width:52},
      ':first-child': {height:53},
      '.selected + .eligible': {opacity:0.3},
    }});
    r.insertNode(holder, first); r.insertNode(holder, second);
    return holder;
  });
  flush(); commit();
  assert.equal(get(second).style.width, 52);
  r.setProp(first, 'class', 'selected'); commit();
  assert.equal(get(second).style.width, null, 'filtered nth dependency responds to sibling class');
  assert.equal(get(second).style.opacity, 0.3, 'inline adjacent selector dependency');
  r.insertNode(holder, second, first); commit();
  assert.equal(get(second).style.height, 53, 'inline structural dependency responds to reorder');
  assert.equal(get(second).style.opacity, 1);
  coldParity('inline structural selectors');
  second.props.style = {':first-child': {height:67}};
  r.markTreeChanged(); commit();
  assert.equal(get(second).style.height, 67, 'raw mutation escape hatch recomputes structural styles');
  let host, slot, named, content, setContent;
  mountApp(() => {
    host = r.createElement('div');
    slot = r.createElement('slot');
    named = r.createElement('slot', {name:'named'});
    content = r.createElement('div');
    const [value, write] = createSignal('before', {ownedWrite:true});
    setContent = write;
    r.insert(content, value);
    r.insertNode(host, slot); r.insertNode(host, named); r.insertNode(host, content);
    return host;
  });
  flush(); commit();
  setContent('after'); flush(); commit();
  assert.equal(get(slot).children[0].children[0].text, 'after', 'distributed text updates revisit the slot host');
  r.setProp(content, 'slot', 'named'); commit();
  assert.equal(get(slot).children.length, 0, 'slot reassignment clears the former distribution');
  assert.equal(get(named).children[0].id, content.id);
  coldParity('slot host and distributed children');
  console.log('PASS retained discovery scaling and mutation correctness', JSON.stringify({hover:counts,insert:topologyCounts}));
} finally {
  globalThis.uiDispose?.();
  clearStyleSheets();
  await rm(dir, {recursive:true,force:true});
}
