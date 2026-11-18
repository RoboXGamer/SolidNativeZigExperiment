import * as s from "solid-js";
import * as r from "../packages/solid-zig/src/renderer.js";

const text = node => node.text + node.children.map(text).join("");
const turn = async () => { for (let i = 0; i < 8; i++) await Promise.resolve(); };
const deferred = () => {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
};

// Shared by a Node client-runtime probe and the actual embedded QuickJS bundle.
export async function runStableContract() {
  let checks = 0;
  const check = (condition, message) => {
    if (!condition) throw Error("Stable contract: " + message);
    checks++;
  };

  let read, write, dispose, owner, cleaned = 0;
  const label = r.createElement("label");
  const refs = [];
  s.createRoot(d => {
    dispose = d;
    owner = s.getOwner();
    [read, write] = s.createSignal(0);
    r.insert(label, read);
    r.ref(() => [
      node => refs.push(["first", node]),
      [node => refs.push(["second", node])],
    ], label);
    s.onCleanup(() => cleaned++);
  });
  try {
    check(refs.map(([name]) => name).join(",") === "first,second" &&
      refs.every(([, node]) => node === label), "nested refs receive the retained node in order");
    write(1);
    check(read() === 0 && text(label) === "0", "ordinary writes stay staged");
    s.flush();
    check(read() === 1 && text(label) === "1", "flush publishes state and retained text together");
    const observations = [];
    s.onFlush(() => { write(2); s.onFlush(() => observations.push("nested:" + read())); });
    s.onFlush(() => observations.push("next:" + read()));
    await turn();
    check(observations.join(",") === "next:2,nested:2", "each flush callback commits before the next callback");
    check(text(label) === "2", "flush-callback writes reach renderer effects");
    if (s.DEV) {
      for (const forbidden of [() => s.createMemo(() => 1), () => s.onCleanup(() => {})]) {
        let rejected = false;
        try { s.runWithOwner(owner, () => r.ref(() => forbidden, label)); } catch (error) {
          rejected = /PRIMITIVE_IN_EFFECT_CALLBACK|CLEANUP_IN_FORBIDDEN_SCOPE/.test(String(error));
        }
        check(rejected, "ref callbacks reject owned primitives and cleanup registration");
      }
    }
  } finally { dispose(); }
  check(cleaned === 1, "the ref component owner cleans up exactly once");

  const root = r.node("root");
  const requests = Object.fromEntries(["first", "slow", "fast", "bad", "retry", "abandoned"].map(key => [key, deferred()]));
  let choose, value, reset, disposeState, disposeView, viewCleanups = 0;
  s.createRoot(d => {
    disposeState = d;
    const [key, setKey] = s.createSignal("first");
    choose = setKey;
    value = s.createMemo(() => requests[key()].promise);
    disposeView = r.render(() => {
      s.onCleanup(() => viewCleanups++);
      return s.createComponent(s.Errored, {
        fallback: (_error, retry) => { reset = retry; return "error"; },
        get children() {
          return s.createComponent(s.Loading, {
            fallback: "loading",
            get children() {
              const node = r.createElement("label");
              r.insert(node, value);
              return node;
            },
          });
        },
      });
    }, root);
  });
  try {
    s.flush();
    check(text(root) === "loading", "first load renders the boundary fallback");
    requests.first.resolve("first");
    await s.resolve(value);
    s.flush();
    check(text(root) === "first", "first async value reaches native nodes");
    choose("slow"); s.flush();
    check(text(root) === "first" && s.isPending(value), "refresh keeps committed content while pending");
    choose("fast"); s.flush();
    requests.fast.resolve("fast");
    await s.resolve(value);
    requests.slow.resolve("stale");
    await turn(); s.flush();
    check(text(root) === "fast" && !s.isPending(value), "a superseded result cannot overwrite the newer answer");
    choose("bad"); s.flush();
    const rejected = s.resolve(value).then(() => false, error => error.message === "expected rejection");
    requests.bad.reject(Error("expected rejection"));
    check(await rejected, "async rejection remains observable");
    await turn(); s.flush();
    check(text(root) === "error" && typeof reset === "function", "error boundary replaces failed native content");
    choose("retry"); reset(); s.flush();
    requests.retry.resolve("recovered");
    await s.resolve(value); s.flush();
    check(text(root) === "recovered", "retry recovers the native subtree");
    choose("abandoned"); s.flush();
  } finally { disposeView(); disposeState(); }
  requests.abandoned.resolve("too late");
  await turn();
  check(root.children.length === 0 && viewCleanups === 1, "late results cannot resurrect a disposed view");

  const listRoot = r.node("root");
  const removed = [];
  let store, setStore, projection, disposeList, disposeStore;
  s.createRoot(d => {
    disposeStore = d;
    [store, setStore] = s.createStore({ rows: [{ id: "a", label: "A" }, { id: "b", label: "B" }, { id: "c", label: "C" }] });
    projection = s.createProjection(draft => { draft.count = store.rows.length; }, { count: 0 });
    disposeList = r.render(() => s.createComponent(s.For, {
      get each() { return store.rows; },
      children(row) {
        const id = s.untrack(() => row.id);
        const node = r.createElement("label", { id });
        r.insert(node, () => row.label);
        s.onCleanup(() => removed.push(id));
        return node;
      },
    }), listRoot);
  });
  try {
    s.flush();
    const original = listRoot.children.filter(node => node.type === "label");
    setStore(draft => { draft.rows.reverse(); }); s.flush();
    const moved = listRoot.children.filter(node => node.type === "label");
    check(moved[0] === original[2] && moved[2] === original[0], "keyed moves preserve retained identity");
    check(moved.every(node => node.parent === listRoot) && removed.length === 0, "moves preserve parent links without disposal");
    setStore(draft => { draft.rows.splice(1, 1); draft.rows[0].label = "Changed"; }); s.flush();
    check(text(listRoot) === "ChangedA" && removed.join(",") === "b", "removal disposes only its keyed row and text stays reactive");
    check(projection.count === 2, "projections track structural store mutations");
  } finally { disposeList(); disposeStore(); }
  check(removed.length === 3, "remaining keyed rows dispose exactly once");

  const actionWait = deferred();
  let optimistic, mutate, disposeAction;
  s.createRoot(d => {
    disposeAction = d;
    const [readOptimistic, setOptimistic] = s.createOptimistic("truth");
    optimistic = readOptimistic;
    mutate = s.action(function* () { setOptimistic("guess"); yield actionWait.promise; });
  });
  try {
    const outcome = mutate().then(() => false, error => error.message === "action failed");
    s.flush();
    check(optimistic() === "guess", "pending action exposes its optimistic value");
    actionWait.reject(Error("action failed"));
    check(await outcome, "action rejection is delivered to its caller");
    s.flush();
    check(optimistic() === "truth" && !s.isPending(optimistic), "failed action rolls back and releases pending state");
  } finally { disposeAction(); }

  // More than the host's per-drain job budget must still make progress.
  let jobs = Promise.resolve();
  for (let i = 0; i < 3000; i++) jobs = jobs.then(() => {});
  await jobs;
  check(true, "microtasks beyond a single native drain continue to completion");
  return { checks, development: Boolean(s.DEV) };
}
