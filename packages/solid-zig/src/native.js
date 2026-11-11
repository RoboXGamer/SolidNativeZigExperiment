import * as solid from "solid-js";
import * as refresh from "solid-js/refresh";
import * as renderer from "./renderer.js";
import { createModuleHost } from "./module-runtime.js";

let root = renderer.node("root");
let dispose;
let committed = new Map();
let pendingCommit;

function mount(Component) {
  const nextRoot = renderer.node("root");
  const nextDispose = renderer.render(() => renderer.createComponent(Component, {}), nextRoot);
  if (dispose) dispose();
  root = nextRoot;
  dispose = nextDispose;
}

// Containers are flex boxes by default (the custom elements are flex
// primitives); text nodes stay block leaves. The default direction has to match
// the axis that height/width resolution assumes, otherwise boxes are sized for
// one axis and their children laid out on the other.
function flexDirectionOf(node, style) {
  if (typeof style.flexDirection === "string") return style.flexDirection;
  return ["row", "label", "button", "input"].includes(node.type) ? "row" : "column";
}

function displayOf(node, style) {
  if (typeof style.display === "string") return style.display;
  return node.type === "text" ? "block" : "flex";
}

function spacingValue(value) {
  if (typeof value === "number") return value;
  if (value === "auto") return -1;
  if (typeof value === "string") {
    const n = parseFloat(value);
    return Number.isFinite(n) ? n : 0;
  }
  return 0;
}

function boxSides(value) {
  if (typeof value !== "string") return null;
  const parts = value.trim().split(/\s+/).filter(v => v.length > 0).map(spacingValue);
  if (parts.length === 0 || parts.length > 4) return null;
  if (parts.length === 1) return { t: parts[0], r: parts[0], b: parts[0], l: parts[0] };
  if (parts.length === 2) return { t: parts[0], r: parts[1], b: parts[0], l: parts[1] };
  if (parts.length === 3) return { t: parts[0], r: parts[1], b: parts[2], l: parts[1] };
  return { t: parts[0], r: parts[1], b: parts[2], l: parts[3] };
}

function snapshot(node, inherited = {}) {
  const style = node.props.style || {};
  const marginBox = boxSides(style.margin);
  const textStyle = {
    color: typeof style.color === "string" ? style.color : (inherited.color || ""),
    fontSize: typeof style.fontSize === "number" ? style.fontSize : (inherited.fontSize || 0),
  };
  const columns = style.gridTemplateColumns == null ? [] :
    (Array.isArray(style.gridTemplateColumns) ? style.gridTemplateColumns : String(style.gridTemplateColumns).trim().split(/\s+/)).map(track => {
      if (typeof track === "number") return track;
      if (/^\d+(?:\.\d+)?fr$/.test(track)) return -Number(track.slice(0, -2));
      if (/^\d+(?:\.\d+)?px$/.test(track)) return Number(track.slice(0, -2));
      throw Error(`Unsupported grid track: ${track}; use px or fr tracks`);
    });
  return {
    id: node.id,
    type: node.type,
    text: node.text,
    clickable: typeof node.props.onClick === "function" || node.type === "input",
    value: node.type === "input" ? String(node.props.value ?? "") : "",
    style: {
      direction: flexDirectionOf(node, style),
      display: displayOf(node, style),
      flexDirection: flexDirectionOf(node, style),
      flexWrap: typeof style.flexWrap === "string" ? style.flexWrap : "nowrap",
      justifyContent: typeof style.justifyContent === "string" ? style.justifyContent : "flex-start",
      alignItems: typeof style.alignItems === "string" ? style.alignItems : "stretch",
      alignContent: typeof style.alignContent === "string" ? style.alignContent : "stretch",
      alignSelf: typeof style.alignSelf === "string" ? style.alignSelf : "auto",
      flexGrow: typeof style.flexGrow === "number" ? style.flexGrow : (typeof style.flex === "number" ? style.flex : (typeof style.flex === "string" ? (parseFloat(style.flex.split(/\\s+/)[0]) || 0) : 0)),
      flexShrink: typeof style.flexShrink === "number" ? style.flexShrink : (typeof style.flex === "string" ? (parseFloat(style.flex.split(/\\s+/)[1]) || 1) : 1),
      flexBasis: typeof style.flexBasis === "number" ? style.flexBasis : (style.flexBasis === "auto" ? -1 : style.flexBasis === "content" ? -2 : (typeof style.flex === "string" ? (function (t) { return t === "auto" ? -1 : t === "content" ? -2 : (parseFloat(t) || 0); })(style.flex.split(/\\s+/)[2]) : -1)),
      order: typeof style.order === "number" ? style.order : 0,
      width: typeof style.width === "number" ? style.width : 0,
      height: typeof style.height === "number" ? style.height : 0,
      minWidth: typeof style.minWidth === "number" ? style.minWidth : 0,
      minHeight: typeof style.minHeight === "number" ? style.minHeight : 0,
      maxWidth: typeof style.maxWidth === "number" ? style.maxWidth : 0,
      maxHeight: typeof style.maxHeight === "number" ? style.maxHeight : 0,
      aspectRatio: typeof style.aspectRatio === "number" ? style.aspectRatio : 0,
      padding: typeof style.padding === "number" ? style.padding : 0,
      paddingTop: typeof style.paddingTop === "number" ? style.paddingTop : 0,
      paddingRight: typeof style.paddingRight === "number" ? style.paddingRight : 0,
      paddingBottom: typeof style.paddingBottom === "number" ? style.paddingBottom : 0,
      paddingLeft: typeof style.paddingLeft === "number" ? style.paddingLeft : 0,
      margin: marginBox ? 0 : (typeof style.margin === "number" ? style.margin : (style.margin === "auto" ? -1 : 0)),
      marginTop: style.marginTop === "auto" ? -1 : (typeof style.marginTop === "number" ? style.marginTop : (marginBox ? marginBox.t : 0)),
      marginRight: style.marginRight === "auto" ? -1 : (typeof style.marginRight === "number" ? style.marginRight : (marginBox ? marginBox.r : 0)),
      marginBottom: style.marginBottom === "auto" ? -1 : (typeof style.marginBottom === "number" ? style.marginBottom : (marginBox ? marginBox.b : 0)),
      marginLeft: style.marginLeft === "auto" ? -1 : (typeof style.marginLeft === "number" ? style.marginLeft : (marginBox ? marginBox.l : 0)),
      gap: typeof style.gap === "number" ? style.gap : 0,
      columns,
      backgroundColor: typeof style.backgroundColor === "string" ? style.backgroundColor : "",
      borderColor: typeof style.borderColor === "string" ? style.borderColor : "",
      borderTopColor: typeof style.borderTopColor === "string" ? style.borderTopColor : "",
      borderRightColor: typeof style.borderRightColor === "string" ? style.borderRightColor : "",
      borderBottomColor: typeof style.borderBottomColor === "string" ? style.borderBottomColor : "",
      borderLeftColor: typeof style.borderLeftColor === "string" ? style.borderLeftColor : "",
      borderWidth: typeof style.borderWidth === "number" ? style.borderWidth : 0,
      borderTopWidth: typeof style.borderTopWidth === "number" ? style.borderTopWidth : 0,
      borderRightWidth: typeof style.borderRightWidth === "number" ? style.borderRightWidth : 0,
      borderBottomWidth: typeof style.borderBottomWidth === "number" ? style.borderBottomWidth : 0,
      borderLeftWidth: typeof style.borderLeftWidth === "number" ? style.borderLeftWidth : 0,
      borderRadius: typeof style.borderRadius === "number" ? style.borderRadius : 0,
      borderTopLeftRadius: typeof style.borderTopLeftRadius === "number" ? style.borderTopLeftRadius : 0,
      borderTopRightRadius: typeof style.borderTopRightRadius === "number" ? style.borderTopRightRadius : 0,
      borderBottomRightRadius: typeof style.borderBottomRightRadius === "number" ? style.borderBottomRightRadius : 0,
      borderBottomLeftRadius: typeof style.borderBottomLeftRadius === "number" ? style.borderBottomLeftRadius : 0,
      boxSizing: typeof style.boxSizing === "string" ? style.boxSizing : "border-box",
      overflow: typeof style.overflow === "string" ? style.overflow : "visible",
      outlineWidth: typeof style.outlineWidth === "number" ? style.outlineWidth : 0,
      outlineColor: typeof style.outlineColor === "string" ? style.outlineColor : "",
      boxShadow: typeof style.boxShadow === "string" ? style.boxShadow : "",
      minWidth: typeof style.minWidth === "number" ? style.minWidth : 0,
      minHeight: typeof style.minHeight === "number" ? style.minHeight : 0,
      maxWidth: typeof style.maxWidth === "number" ? style.maxWidth : 0,
      maxHeight: typeof style.maxHeight === "number" ? style.maxHeight : 0,
      aspectRatio: typeof style.aspectRatio === "number" ? style.aspectRatio : 0,
      ...textStyle,
    },
    children: node.children.map(child => snapshot(child, textStyle)),
  };
}

function findId(node, id) {
  if (node.id === id) return node;
  for (const child of node.children) {
    const match = findId(child, id);
    if (match) return match;
  }
}

export function mountApp(Component) {
  globalThis.__uiRenderer = renderer;
  globalThis.__uiSolid = solid;
  if (__NATIVE_HMR__) {
    globalThis.__uiModules ||= createModuleHost({
      "solid-js": solid,
      "solid-refresh": refresh,
      "native-renderer": renderer,
      "native-host": { mountApp },
    });
  }
  globalThis.uiSnapshot = () => JSON.stringify(snapshot(root));
  globalThis.uiChanges = () => {
    const nodes = [];
    const current = new Map();
    function visit(node) {
      const flat = { ...node, children: node.children.map(child => child.id) };
      const signature = JSON.stringify(flat);
      current.set(node.id, signature);
      if (committed.get(node.id) !== signature) nodes.push(flat);
      node.children.forEach(visit);
    }
    visit(snapshot(root));
    const removed = [...committed.keys()].filter(id => !current.has(id));
    pendingCommit = current;
    return JSON.stringify({ root: root.id, nodes, removed });
  };
  globalThis.uiCommit = () => { if (pendingCommit) committed = pendingCommit; pendingCommit = undefined; };
  globalThis.uiDispatchClick = id => {
    const target = findId(root, id);
    if (target && typeof target.props.onClick === "function") target.props.onClick();
  };
  globalThis.uiDispatchInput = (id, value) => {
    const target = findId(root, id);
    if (!target || target.type !== "input") return;
    target.props.value = value;
    const event = { target: { value }, currentTarget: { value } };
    if (typeof target.props.onInput === "function") target.props.onInput(event);
  };
  mount(Component);
}
