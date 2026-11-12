import { createRenderer } from "@solidjs/universal";

// Minimal retained tree; Solid owns mutations and disposal.
let nextNodeId = 1;
export const node = (type, text = "") => ({ id: nextNodeId++, type, text, children: [], parent: null, props: {} });
const renderer = createRenderer({
  createElement: (type, props) => Object.assign(node(type), { props: props || {} }),
  createTextNode: text => node("text", String(text)),
  replaceText: (n, text) => { n.text = String(text); },
  isTextNode: n => n.type === "text",
  setProperty: (n, key, value) => { n.props[key] = value; },
  insertNode(parent, child, anchor) {
    if (child.parent) {
      const old = child.parent.children;
      const index = old.indexOf(child);
      if (index >= 0) old.splice(index, 1);
    }
    const i = anchor ? parent.children.indexOf(anchor) : -1;
    parent.children.splice(i < 0 ? parent.children.length : i, 0, child);
    child.parent = parent;
  },
  removeNode(parent, child) { const i = parent.children.indexOf(child); if (i >= 0) parent.children.splice(i, 1); child.parent = null; },
  getParentNode: n => n.parent || undefined,
  getFirstChild: n => n.children[0],
  getNextSibling: n => n.parent?.children[n.parent.children.indexOf(n) + 1]
});

export const { render, effect, memo, createComponent, createElement, createTextNode, insertNode, insert, spread, setProp, mergeProps, applyRef, ref } = renderer;

export function matchesSelector(n, selector) {
  if (!n || typeof selector !== "string") return false;
  const s = selector.trim();
  if (s === ":root") {
    return n.type === "root" || n.parent == null;
  }
  if (s === "*" || s === n.type) return true;
  if (s.startsWith("#") && n.props?.id === s.slice(1)) return true;
  if (s.startsWith(".") && n.props?.class && n.props.class.split(/\s+/).includes(s.slice(1))) return true;
  return false;
}

