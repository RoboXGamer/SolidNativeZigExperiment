// Arbitrary JS effects cannot be rolled back. Failed generations are torn down;
// the next graph gets a clean remount. Lifecycle callbacks must be synchronous.
let owner;
const installedTimers = new Map();
function owned(record, callback) {
  const previous = owner; owner = record;
  try { return callback(); } finally { owner = previous; }
}
function installTimers() {
  for (const [name, cancel, once] of [['setTimeout', 'clearTimeout', true], ['setInterval', 'clearInterval', false], ['requestAnimationFrame', 'cancelAnimationFrame', true]]) {
    if (!globalThis[name] || installedTimers.get(name) === globalThis[name]) continue;
    const schedule = globalThis[name], clear = globalThis[cancel];
    const wrapper = (callback, ...args) => {
      const record = owner;
      if (!record || typeof callback !== 'function') return schedule(callback, ...args);
      if (!record.active) return 0;
      let release;
      const id = schedule((...values) => {
        if (once) record.timers.delete(release);
        if (record.active) return owned(record, () => callback(...values));
      }, ...args);
      release = () => clear(id); record.timers.add(release); return id;
    };
    globalThis[name] = wrapper; installedTimers.set(name, wrapper);
  }
}
export function createModuleHost(externals, options = {}) {
  installTimers();
  const definitions = new Map(), modules = new Map(), data = new Map(), listeners = new Map();
  let entry, applying = false, resetting = false, invalidated = false, revision = 0, lastGood;
  let status = { phase: 'idle', revision: 0 };
  const errors = [];
  function state(phase, detail = {}) { status = { phase, revision, ...detail }; options.status?.(status); }
  function sync(callback, args, id, phase) {
    try {
      const result = callback(...args);
      if (result && typeof result.then === 'function') {
        Promise.resolve(result).catch(error => options.diagnostic?.({ id, phase, revision, error: String(error) }));
        throw Error(`Async ${phase} is unsupported; use hot.guard/signal and synchronous cancellation`);
      }
      return result;
    } catch (error) { throw Error(`${id} [${phase}, revision ${revision}]: ${error.message}`, { cause: error }); }
  }
  function resolve(id, importer) {
    if (!id.startsWith('.')) return id;
    const parts = importer.split('/'); parts.pop();
    for (const part of id.split('/')) {
      if (part === '..') parts.pop(); else if (part && part !== '.') parts.push(part);
    }
    return parts.join('/');
  }
  function emit(event, payload) {
    for (const [record, callback] of [...(listeners.get(event) || [])])
      if (record.active) sync(callback, [payload], record.id, event);
  }
  function cleanup(record, prune) {
    if (!record?.active) return;
    record.active = false; record.signal.aborted = true;
    for (const cancel of record.timers) cancel(); record.timers.clear();
    for (const [event, token] of record.listeners) {
      const callbacks = listeners.get(event); callbacks?.delete(token);
      if (!callbacks?.size) listeners.delete(event);
    }
    for (const [phase, callbacks] of [['dispose', record.disposes], ['prune', prune ? record.prunes : []]])
      for (const callback of callbacks.splice(0)) {
        try { sync(callback, [data.get(record.id)], record.id, phase); } catch (error) { errors.push(error); }
      }
    record.listeners.length = 0;
  }
  function require(id) {
    if (Object.hasOwn(externals, id)) return externals[id];
    if (modules.has(id)) return modules.get(id).exports;
    const factory = definitions.get(id);
    if (!factory) throw Error(`Module not loaded: ${id}`);
    const record = { id, active: true, timers: new Set(), signal: { aborted: false }, sheets: [], exports: {}, accepts: [], dependencies: new Set(), dependencyAccepts: [], disposes: [], prunes: [], listeners: [] };
    modules.set(id, record);
    const guard = callback => (...args) => record.active ? owned(record, () => callback(...args)) : undefined;
    const register = (list, callback) => {
      if (!record.active) throw Error(`Cannot register on retired module: ${id}`);
      if (typeof callback !== 'function') throw Error(`Expected lifecycle callback: ${id}`);
      list.push(callback);
    };
    const hot = {
      data: data.get(id) || {}, signal: record.signal, guard,
      styleSheet(sheet) { if (record.active) record.sheets.push(sheet); },
      accept(dependencies, callback) {
        if (typeof dependencies === 'string' || Array.isArray(dependencies)) {
          const ids = (Array.isArray(dependencies) ? dependencies : [dependencies]).map(dep => resolve(dep, id));
          record.dependencyAccepts.push({ ids, callback: callback || (() => {}), array: Array.isArray(dependencies) });
        } else register(record.accepts, typeof dependencies === 'function' ? dependencies : () => {});
      },
      dispose: callback => register(record.disposes, callback),
      prune: callback => register(record.prunes, callback),
      invalidate: guard(() => {
        invalidated = true;
        if (!applying && !resetting && lastGood) host.apply(lastGood.graph, entry, { type: 'full-reload', reason: 'invalidate' });
      }),
      on(event, callback) {
        if (!record.active) throw Error(`Retired module: ${id}`);
        if (!listeners.has(event)) listeners.set(event, new Set());
        const token = [record, callback]; listeners.get(event).add(token); record.listeners.push([event, token]);
      },
      off(event, callback) {
        for (const [name, token] of record.listeners) if (name === event && token[1] === callback) listeners.get(event)?.delete(token);
      },
    };
    data.set(id, hot.data);
    const load = dependency => { const target = resolve(dependency, id); record.dependencies.add(target); return require(target); };
    try {
      owned(record, () => factory(record, record.exports, load, { hot, url: id, import: dependency => Promise.resolve().then(() => {
        if (!record.active) throw Error(`Import from retired module: ${id}`);
        return load(dependency);
      }) }));
    } catch (error) {
      cleanup(record, true); modules.delete(id); data.delete(id);
      throw Error(`${id} [factory, revision ${revision}]: ${error.message}`, { cause: error });
    }
    return record.exports;
  }
  function reset() {
    if (resetting) return;
    resetting = true;
    try {
      for (const record of [...modules.values()].reverse()) cleanup(record, true);
      modules.clear(); data.clear(); listeners.clear();
      try { options.reset?.(); } catch (error) { errors.push(error); }
    } finally { resetting = false; }
  }
  function checkCleanup() {
    if (errors.length) { const failures = errors.splice(0); throw new AggregateError(failures, 'HMR cleanup failed: ' + failures.map(e => e.message).join('; ')); }
  }
  const host = {
    get status() { return status; },
    get resources() { return { modules: modules.size, data: data.size, listeners: [...listeners.values()].reduce((n, set) => n + set.size, 0) }; },
    dispose() {
      reset(); definitions.clear(); lastGood = undefined; entry = undefined;
      state('disposed'); checkCleanup();
    },
    apply(next, nextEntry = entry, operation = {}) {
      if (applying || resetting) throw Error('Recursive HMR apply is unsupported');
      const recovering = status.phase === 'failed';
      applying = true; revision++; state('prepared', { reason: operation.reason });
      try {
        const compiled = new Map();
        for (const [id, code] of Object.entries(next)) {
          if (typeof code !== 'string') throw Error(`Invalid module source: ${id}`);
          if (definitions.get(id)?.source === code) compiled.set(id, definitions.get(id));
          else {
            const factory = new Function('module', 'exports', 'require', '__meta', code + '\n//# sourceURL=' + id.replace(/[\r\n]/g, ''));
            factory.source = code; compiled.set(id, factory);
          }
        }
        if (!compiled.has(nextEntry)) throw Error(`Missing entry: ${nextEntry}`);
        const removed = new Set([...definitions.keys()].filter(id => !compiled.has(id)));
        const changed = new Set([...modules.keys()].filter(id => definitions.get(id) !== compiled.get(id)));
        let grew = true;
        while (grew) {
          grew = false;
          for (const [id, record] of modules) {
            if (!changed.has(id) && [...record.dependencies].some(dep => changed.has(dep) &&
                !record.dependencyAccepts.some(boundary => boundary.ids.includes(dep)) &&
                (!modules.get(dep)?.accepts.length || removed.has(dep)))) { changed.add(id); grew = true; }
          }
        }
        const full = recovering || invalidated || (entry && entry !== nextEntry) || operation.type === 'full-reload';
        state(full ? 'recovering' : 'applying');
        if (full) { emit('vite:beforeFullReload', {}); reset(); }
        else emit('vite:beforeUpdate', { changed: [...changed] });
        invalidated = false;
        const previous = new Map();
        if (!full) for (const id of changed) {
          const record = modules.get(id); previous.set(id, record);
          cleanup(record, removed.has(id)); modules.delete(id);
          if (removed.has(id)) data.delete(id);
        }
        checkCleanup();
        definitions.clear(); for (const [id, factory] of compiled) definitions.set(id, factory);
        entry = nextEntry;
        if (!full) {
          for (const id of changed) {
            if (removed.has(id)) continue;
            const exports = require(id);
            for (const accept of previous.get(id).accepts) sync(accept, [exports], id, 'accept');
          }
          for (const [id, record] of modules) {
            if (changed.has(id)) continue;
            for (const boundary of record.dependencyAccepts) if (boundary.ids.some(dep => changed.has(dep))) {
              const values = boundary.ids.map(dep => removed.has(dep) ? undefined : require(dep));
              sync(boundary.callback, [boundary.array ? values : values[0]], id, 'accept');
            }
          }
        }
        require(entry);
        if (invalidated) {
          invalidated = false; reset(); checkCleanup(); require(entry);
          if (invalidated) throw Error('Module repeatedly invalidated during reload');
        }
        const seen = new Set(), sheets = [];
        function order(id) {
          if (seen.has(id)) return; seen.add(id);
          const record = modules.get(id); if (!record) return;
          for (const dependency of record.dependencies) order(dependency);
          sheets.push(...record.sheets);
        }
        order(entry); options.order?.(sheets);
        emit('vite:afterUpdate', { changed: [...changed] });
        lastGood = { graph: { ...next }, entry }; state('applied'); return status;
      } catch (error) {
        reset(); errors.splice(0).forEach(e => options.diagnostic?.({ phase: 'cleanup', revision, error: String(e) }));
        state('failed', { error: String(error), recovery: 'clean-remount-on-next-graph' }); throw error;
      } finally { applying = false; }
    },
  };
  return host;
}
