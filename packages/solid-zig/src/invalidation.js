// Retained identities, separate from the native acknowledgement boundary.
// Weak dependency edges include unsuccessful selector tests: a later mutation
// must be able to make a previously non-matching selector match.
let clock = 0;
let observer;
const readers = new WeakMap();
const subscriptions = new WeakMap();
export const work = { prepare: 0, css: 0, selectors: 0, snapshot: 0, bridge: 0, membership: 0 };
export function resetWork() { for (const key of Object.keys(work)) work[key] = 0; }
export function dirty(node, css = false) {
  if (!node) return;
  if (css) node._cssDirty = true;
  node._snapshotDirty = true;
  for (let child = node, parent = node.parent; parent; child = parent, parent = parent.parent) {
    (parent._snapshotDirtyChildren ||= new Set()).add(child);
  }
  clock++;
}
export const getMutationVersion = () => clock;
export function observe(node, key) {
  if (!observer || !node) return;
  let keys = readers.get(node);
  if (!keys) readers.set(node, keys = new Map());
  let targets = keys.get(key);
  if (!targets) keys.set(key, targets = new Set());
  if (!targets.has(observer)) {
    targets.add(observer);
    observer.edges.push(targets);
  }
}
export function forget(node, channel) {
  const channels = subscriptions.get(node);
  if (!channels) return;
  for (const [key, token] of channels) if (!channel || channel === key) {
    for (const targets of token.edges) targets.delete(token);
    channels.delete(key);
  }
  if (!channels.size) subscriptions.delete(node);
}
export function tracking(node, fn, channel = 'css') {
  forget(node, channel);
  let channels = subscriptions.get(node);
  if (!channels) subscriptions.set(node, channels = new Map());
  const token = { node, css: channel === 'css', edges: [] };
  channels.set(channel, token);
  const previous = observer;
  observer = token;
  try { return fn(); } finally { observer = previous; }
}
export function changed(node, key) {
  dirty(node, true);
  const keys = readers.get(node);
  const targets = key === '*' ? [...(keys?.values() || [])].flatMap(set => [...set]) : [...(keys?.get(key) || []), ...(keys?.get('*') || [])];
  for (const target of new Set(targets)) dirty(target.node, target.css);
}
