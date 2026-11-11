// Small synchronous module host for Vite-transformed application modules.
// Solid's refresh runtime owns component proxies; this owns module lifetime.
export function createModuleHost(externals) {
  const definitions = new Map();
  const modules = new Map();
  const data = new Map();
  let entry;
  function require(id) {
    if (id in externals) return externals[id];
    if (modules.has(id)) return modules.get(id).exports;
    const factory = definitions.get(id);
    if (!factory) throw Error(`Module not loaded: ${id}`);
    const record = { exports: {}, accepts: [], disposes: [], dependencies: new Set() };
    modules.set(id, record);
    const hot = {
      data: data.get(id) || {},
      accept(callback) { record.accepts.push(typeof callback === "function" ? callback : () => {}); },
      dispose(callback) { record.disposes.push(callback); },
      invalidate() { throw Error(`HMR invalidated ${id}; restart the app`); },
    };
    data.set(id, hot.data);
    const load = dependency => { record.dependencies.add(dependency); return require(dependency); };
    try {
      factory(record, record.exports, load, { hot, url: id, import: dependency => Promise.resolve(load(dependency)) });
    } catch (error) { modules.delete(id); throw error; }
    return record.exports;
  }
  return {
    apply(next, nextEntry) {
      const changed = new Set();
      const compiled = new Map();
      for (const [id, code] of Object.entries(next)) {
        if (definitions.get(id)?.source !== code) {
          const factory = new Function("module", "exports", "require", "__meta", code);
          factory.source = code;
          compiled.set(id, factory);
          if (modules.has(id)) changed.add(id);
        }
      }
      for (const [id, factory] of compiled) definitions.set(id, factory);
      entry = nextEntry || entry;
      // Changes to ordinary helpers propagate until a refresh boundary accepts.
      let grew = true;
      while (grew) {
        grew = false;
        for (const [id, record] of modules) {
          if (!changed.has(id) && [...record.dependencies].some(dep => changed.has(dep) && !modules.get(dep)?.accepts.length)) {
            changed.add(id); grew = true;
          }
        }
      }
      const previous = new Map();
      for (const id of changed) {
        const record = modules.get(id);
        previous.set(id, record);
        for (const dispose of record.disposes) dispose(data.get(id));
        modules.delete(id);
      }
      for (const id of changed) {
        const exports = require(id);
        for (const accept of previous.get(id).accepts) accept(exports);
      }
      require(entry);
    },
  };
}
