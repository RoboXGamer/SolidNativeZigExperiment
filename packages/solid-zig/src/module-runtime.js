// Vite-transformed modules execute in one QuickJS realm. Solid Refresh owns
// component proxies; this loader owns module caching and hot lifecycle hooks.
export function createModuleHost(externals) {
  const definitions = new Map();
  const modules = new Map();
  const data = new Map();
  const listeners = new Map();
  let entry;
  let invalidated = false;
  function resolve(id, importer) {
    if (!id.startsWith(".")) return id;
    const parts = importer.split("/"); parts.pop();
    for (const part of id.split("/")) {
      if (part === "..") parts.pop(); else if (part && part !== ".") parts.push(part);
    }
    return parts.join("/");
  }
  function emit(event, payload) {
    for (const callback of listeners.get(event) || []) callback(payload);
  }
  function release(id, record) {
    for (const callback of record.disposes) callback(data.get(id));
    for (const [event, callback] of record.listeners) listeners.get(event)?.delete(callback);
  }
  function require(id) {
    if (Object.hasOwn(externals, id)) return externals[id];
    if (modules.has(id)) return modules.get(id).exports;
    const factory = definitions.get(id);
    if (!factory) throw Error(`Module not loaded: ${id}`);
    const record = { exports: {}, accepts: [], dependencies: new Set(), dependencyAccepts: [], disposes: [], prunes: [], listeners: [] };
    modules.set(id, record);
    const hot = {
      data: data.get(id) || {},
      accept(dependencies, callback) {
        if (typeof dependencies === "string" || Array.isArray(dependencies)) {
          const ids = (Array.isArray(dependencies) ? dependencies : [dependencies]).map(dep => resolve(dep, id));
          record.dependencyAccepts.push({ ids, callback: callback || (() => {}), array: Array.isArray(dependencies) });
        } else record.accepts.push(typeof dependencies === "function" ? dependencies : () => {});
      },
      dispose(callback) { record.disposes.push(callback); },
      prune(callback) { record.prunes.push(callback); },
      invalidate() { invalidated = true; },
      on(event, callback) {
        if (!listeners.has(event)) listeners.set(event, new Set());
        listeners.get(event).add(callback);
        record.listeners.push([event, callback]);
      },
      off(event, callback) { listeners.get(event)?.delete(callback); },
    };
    data.set(id, hot.data);
    const load = dependency => { const target = resolve(dependency, id); record.dependencies.add(target); return require(target); };
    try {
      factory(record, record.exports, load, { hot, url: id, import: dependency => Promise.resolve().then(() => load(dependency)) });
    } catch (error) { modules.delete(id); throw error; }
    return record.exports;
  }
  function reset() {
    for (const [id, record] of [...modules].reverse()) release(id, record);
    modules.clear(); data.clear(); listeners.clear();
  }
  return {
    dispose: reset,
    apply(next, nextEntry) {
      const changed = new Set();
      const compiled = new Map();
      const removed = new Set([...definitions.keys()].filter(id => !Object.hasOwn(next, id)));
      // Compile the complete update before mutating the live module graph.
      for (const [id, code] of Object.entries(next)) {
        if (definitions.get(id)?.source !== code) {
          const factory = new Function("module", "exports", "require", "__meta", code);
          factory.source = code;
          compiled.set(id, factory);
          if (modules.has(id)) changed.add(id);
        }
      }
      for (const id of removed) if (modules.has(id)) changed.add(id);
      let grew = true;
      while (grew) {
        grew = false;
        for (const [id, record] of modules) {
          const propagate = [...record.dependencies].some(dep => changed.has(dep) &&
            !record.dependencyAccepts.some(boundary => boundary.ids.includes(dep)) &&
            (!modules.get(dep)?.accepts.length || removed.has(dep)));
          if (!changed.has(id) && propagate) { changed.add(id); grew = true; }
        }
      }
      emit("vite:beforeUpdate", { changed: [...changed] });
      for (const [id, factory] of compiled) definitions.set(id, factory);
      for (const id of removed) definitions.delete(id);
      entry = nextEntry || entry;
      const previous = new Map();
      for (const id of changed) {
        const record = modules.get(id);
        previous.set(id, record);
        release(id, record);
        if (removed.has(id)) {
          for (const prune of record.prunes) prune(data.get(id));
          data.delete(id);
        }
        modules.delete(id);
      }
      for (const id of changed) {
        if (removed.has(id)) continue;
        const exports = require(id);
        for (const accept of previous.get(id).accepts) accept(exports);
      }
      for (const [id, record] of modules) {
        if (changed.has(id)) continue;
        for (const boundary of record.dependencyAccepts) {
          if (boundary.ids.some(dep => changed.has(dep))) {
            const values = boundary.ids.map(dep => removed.has(dep) ? undefined : require(dep));
            boundary.callback(boundary.array ? values : values[0]);
          }
        }
      }
      if (invalidated) { invalidated = false; emit("vite:beforeFullReload", {}); reset(); }
      require(entry);
      emit("vite:afterUpdate", { changed: [...changed] });
    },
  };
}
