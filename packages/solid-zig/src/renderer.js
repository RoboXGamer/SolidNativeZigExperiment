import { createRenderer } from "@solidjs/universal";
import { matches, querySelector, querySelectorAll, closest } from "./selectors.js";
import { changed, forget } from "./invalidation.js";

// Minimal retained tree; Solid owns mutations and disposal.
let nextNodeId = 1;
let treeVersion = 0;
let structureVersion = 0;
let fullVersion = 0;
const structureChanges = new Set();
export const getStructureChanges = () => structureChanges;
export const clearStructureChanges = () => structureChanges.clear();
export const getFullVersion = () => fullVersion;
export const getStructureVersion = () => structureVersion;
export const getTreeVersion = () => treeVersion;
// Escape hatch for callers making otherwise unobservable raw mutations.
export function markTreeChanged(n) {
  treeVersion++;
  structureVersion++;
  fullVersion++;
  if (n) changed(n, '*');
}
export function forgetTree(n) { forget(n); for (const c of n.children) forgetTree(c); }
export const node = (type, text = "") => {
  const n = {
    id: nextNodeId++,
    type,
    text,
    children: [],
    parent: null,
    props: {},
    getAttribute(name) {
      if (name === "id") return this.props.id != null ? String(this.props.id) : String(this.id);
      return this.props[name] != null ? String(this.props[name]) : null;
    },
    setAttribute(name, value) {
      this.props[name] = String(value);
      changed(this, 'props');
      treeVersion++;
    },
    hasAttribute(name) {
      return this.props[name] !== undefined || (name === "id" && this.id != null);
    },
    removeAttribute(name) {
      delete this.props[name];
      changed(this, 'props');
      treeVersion++;
    },
    matches(selector) {
      return matches(this, selector, this);
    },
    querySelector(selector) {
      return querySelector(this, selector);
    },
    querySelectorAll(selector) {
      return querySelectorAll(this, selector);
    },
    closest(selector) {
      return closest(this, selector);
    },
  };
  return n;
};

const renderer = createRenderer({
  createElement: (type, props) => Object.assign(node(type), { props: props || {} }),
  createTextNode: text => node("text", String(text)),
  replaceText: (n, text) => { n.text = String(text); changed(n, 'children'); treeVersion++; },
  isTextNode: n => n.type === "text",
  setProperty: (n, key, value) => { n.props[key] = value; changed(n, 'props'); treeVersion++; },
  insertNode(parent, child, anchor) {
    treeVersion++;
    structureVersion++;
    structureChanges.add(child);
    if (child.parent) {
      changed(child.parent, 'children');
      const old = child.parent.children;
      const index = old.indexOf(child);
      if (index >= 0) old.splice(index, 1);
    }
    const i = anchor ? parent.children.indexOf(anchor) : -1;
    parent.children.splice(i < 0 ? parent.children.length : i, 0, child);
    child.parent = parent;
    changed(parent, 'children');
    const moved = n => { changed(n, 'parent'); for (const c of n.children) moved(c); };
    moved(child);
  },
  removeNode(parent, child) {
    treeVersion++;
    structureVersion++;
    structureChanges.add(child);
    const i = parent.children.indexOf(child);
    if (i >= 0) parent.children.splice(i, 1);
    changed(parent, 'children');
    child.parent = null;
    changed(child, 'parent');
    forgetTree(child);
  },
  getParentNode: n => n.parent || undefined,
  getFirstChild: n => n.children[0],
  getNextSibling: n => n.parent?.children[n.parent.children.indexOf(n) + 1]
});

export const { render, effect, memo, createComponent, createElement, createTextNode, insertNode, insert, spread, setProp, mergeProps, applyRef, ref } = renderer;
export { matches, querySelector, querySelectorAll, closest };

let currentTargetId = "";
let currentTargetText = "";
export function setTarget(id) { currentTargetId = id ? String(id).replace(/^#/, "") : ""; }
export function setTargetText(text) { currentTargetText = text || ""; }
export function getTarget() { return currentTargetId; }
export function getTargetText() { return currentTargetText; }


export const matchesSelector = matches;

