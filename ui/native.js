import * as solid from "solid-js";
import * as refresh from "solid-js/refresh";
import * as renderer from "./renderer.js";

import { createModuleHost } from "./module-runtime.js";
import { matchMedia, evaluateMediaQuery, setScriptingState, getScriptingState, getPreferences, setPreferences } from "./media.js";
import { matches, querySelector, querySelectorAll, closest, calculateSpecificity } from "./selectors.js";

const envVars = new Map([
  ["safe-area-inset-top", "0px"],
  ["safe-area-inset-right", "0px"],
  ["safe-area-inset-bottom", "0px"],
  ["safe-area-inset-left", "0px"],
]);

export function getEnvironmentVariable(name) {
  return envVars.get(name);
}

export function setEnvironmentVariable(name, value) {
  envVars.set(name, String(value));
}

export function resolveEnv(str) {
  if (typeof str !== "string" || !str.includes("env(")) return str;
  return str.replace(/env\(\s*([\w-]+)\s*(?:,\s*([^)]+))?\s*\)/g, (_, name, fallback) => {
    if (envVars.has(name)) return envVars.get(name);
    return fallback ? fallback.trim() : "0px";
  });
}
import {
  NamespaceRegistry,
  parseAnPlusB,
  matchesSelector,
  expandNesting,
  resolveNestedStyles,
} from "./selectors.js";
export {
  checkValidity,
  specificity,
  splitSelectorList,
  parseComplexSelector,
  parseCompoundSelector,
  compileStyleSheet,
  applySelectorStyles
} from "./selectors.js";
import { checkValidity } from "./selectors.js";

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
// one axis and their children laid out on the other directions.
function flexDirectionOf(node, style) {
  if (typeof style.flexDirection === "string") return style.flexDirection;
  if (node.type === "select") return "column";
  return ["row", "label", "button", "input", "option"].includes(node.type) ? "row" : "column";
}

function blockifyDisplay(d) {
  if (d === "inline" || d === "inline-block") return "block";
  if (d === "inline-flex") return "flex";
  if (d === "inline-grid") return "grid";
  if (d === "inline-table") return "table";
  return d;
}

function displayOf(node, style) {
  if (node.props?.popover != null && !isPopoverOpen(node)) return "none";
  let d = style.display;
  let resolvedDisplay = null;
  if (typeof d === "string") {
    const tokens = d.trim().toLowerCase().split(/\s+/);
    if (tokens.length === 2) {
      const [first, second] = tokens;
      const outside = ["block", "inline"].includes(first) ? first : (["block", "inline"].includes(second) ? second : null);
      const inside = ["flow", "flow-root", "flex", "grid", "table", "ruby"].includes(second) ? second : (["flow", "flow-root", "flex", "grid", "table", "ruby"].includes(first) ? first : null);
      if (outside === "block" && inside === "flow") resolvedDisplay = "block";
      else if (outside === "inline" && inside === "flow") resolvedDisplay = "inline";
      else if (outside === "block" && inside === "flow-root") resolvedDisplay = "flow-root";
      else if (outside === "inline" && inside === "flow-root") resolvedDisplay = "inline-block";
      else if (outside === "block" && inside === "flex") resolvedDisplay = "flex";
      else if (outside === "inline" && inside === "flex") resolvedDisplay = "inline-flex";
      else if (outside === "block" && inside === "grid") resolvedDisplay = "grid";
      else if (outside === "inline" && inside === "grid") resolvedDisplay = "inline-grid";
      else if (outside === "inline" && inside === "table") resolvedDisplay = "inline-table";
      else if (outside === "block" && inside === "table") resolvedDisplay = "table";
      else if (first === "inline" && second === "block") resolvedDisplay = "inline-block";
      else if (first === "block" && second === "inline") resolvedDisplay = "inline-block";
      else resolvedDisplay = d;
    } else if (tokens.length === 1) {
      resolvedDisplay = tokens[0];
    } else {
      resolvedDisplay = d;
    }
  } else if (node.type === "text") {
    resolvedDisplay = "block";
  } else if (node.type === "grid") {
    resolvedDisplay = "grid";
  } else if (node.type === "table") {
    resolvedDisplay = "table";
  } else if (node.type === "caption") {
    resolvedDisplay = "table-caption";
  } else if (["thead", "tbody", "tfoot"].includes(node.type)) {
    resolvedDisplay = "table-row-group";
  } else if (node.type === "tr") {
    resolvedDisplay = "table-row";
  } else if (["td", "th"].includes(node.type)) {
    resolvedDisplay = "table-cell";
  } else if (node.type === "option" && node.parent?.type === "select") {
    resolvedDisplay = node.parent._open ? "flex" : "none";
  } else {
    resolvedDisplay = "flex";
  }
  const isOutOfFlow = style.position === "absolute" || style.position === "fixed" || (style.float != null && style.float !== 'none');
  if (isOutOfFlow && resolvedDisplay !== "none" && resolvedDisplay !== "contents") {
    return blockifyDisplay(resolvedDisplay);
  }
  return resolvedDisplay;
}

function spacingValue(value, { auto = false, negative = false } = {}) {
  if (auto && value === "auto") return value;
  if (typeof value === "string") {
    const resolved = resolveEnv(value).trim();
    if (resolved) return resolved;
  }
  if (typeof value !== "number" || !Number.isFinite(value) || (!negative && value < 0)) throw Error(`Invalid length: ${value}`);
  return value;
}

function splitSpacing(value) {
  const parts = [];
  let depth = 0, start = 0;
  for (let i = 0; i < value.length; i++) {
    if (value[i] === "(") depth++;
    else if (value[i] === ")") { if (--depth < 0) throw Error(`Invalid spacing: ${value}`); }
    else if (/\s/.test(value[i]) && depth === 0) {
      if (i > start) parts.push(value.slice(start, i));
      start = i + 1;
    }
  }
  if (depth !== 0) throw Error(`Invalid spacing: ${value}`);
  if (start < value.length) parts.push(value.slice(start));
  return parts;
}

function splitAlignment(str) {
  const tokens = splitSpacing(str.trim());
  const values = [];
  for (let i = 0; i < tokens.length; i++) {
    if ((tokens[i] === "safe" || tokens[i] === "unsafe") && i + 1 < tokens.length) {
      values.push(tokens[i] + " " + tokens[i + 1]);
      i++;
    } else {
      values.push(tokens[i]);
    }
  }
  return values;
}

function boxSides(value, options) {
  if (value == null) return null;
  const parts = (typeof value === "string" ? splitSpacing(value.trim()) : [value]).map(v => spacingValue(v, options));
  if (parts.length === 0 || parts.length > 4) throw Error(`Invalid spacing: ${value}`);
  if (parts.length === 1) return { t: parts[0], r: parts[0], b: parts[0], l: parts[0] };
  if (parts.length === 2) return { t: parts[0], r: parts[1], b: parts[0], l: parts[1] };
  if (parts.length === 3) return { t: parts[0], r: parts[1], b: parts[2], l: parts[1] };
  return { t: parts[0], r: parts[1], b: parts[2], l: parts[3] };
}

export const propertyRegistry = new Map();

export function registerProperty(definition) {
  if (!definition || !definition.name || !definition.name.startsWith("--")) {
    throw Error("Invalid custom property name");
  }
  propertyRegistry.set(definition.name, {
    name: definition.name,
    syntax: definition.syntax ?? "*",
    inherits: definition.inherits ?? true,
    initialValue: definition.initialValue != null ? String(definition.initialValue) : undefined,
  });
}

if (typeof globalThis !== "undefined") {
  globalThis.CSS = globalThis.CSS || {};
  globalThis.CSS.registerProperty = registerProperty;
}

function resolutionMedia(query, context = {}) {
  const currentDppx = context.resolution ?? context.devicePixelRatio ?? 1.0;
  let q = String(query).trim();
  if (q.startsWith("(") && q.endsWith(")")) q = q.slice(1, -1).trim();

  // -webkit-device-pixel-ratio compatibility prefixes
  const webkitMatch = q.match(/^(-webkit-(?:min-|max-)?device-pixel-ratio)\s*:\s*([\d\.\/]+)$/i);
  if (webkitMatch) {
    const name = webkitMatch[1].toLowerCase();
    const valStr = webkitMatch[2];
    let val = 1.0;
    if (valStr.includes("/")) {
      const [num, den] = valStr.split("/");
      val = Number(num) / Number(den);
    } else {
      val = Number(valStr);
    }
    if (name === "-webkit-device-pixel-ratio") return { matches: Math.abs(currentDppx - val) < 1e-4, media: query };
    if (name === "-webkit-min-device-pixel-ratio") return { matches: currentDppx >= val - 1e-4, media: query };
    if (name === "-webkit-max-device-pixel-ratio") return { matches: currentDppx <= val + 1e-4, media: query };
  }

  // resolution media queries
  const resMatch = q.match(/^(min-|max-)?resolution\s*:\s*([\d\.]+)(dpi|dpcm|dppx|x)$/i);
  if (resMatch) {
    const prefix = (resMatch[1] || "").toLowerCase();
    const val = Number(resMatch[2]);
    const unit = resMatch[3].toLowerCase();
    let reqDppx = val;
    if (unit === "dpi") reqDppx = val / 96.0;
    else if (unit === "dpcm") reqDppx = val * 2.54 / 96.0;
    if (prefix === "min-") return { matches: currentDppx >= reqDppx - 1e-4, media: query };
    if (prefix === "max-") return { matches: currentDppx <= reqDppx + 1e-4, media: query };
    return { matches: Math.abs(currentDppx - reqDppx) < 1e-4, media: query };
  }

  return { matches: false, media: query };
}

if (typeof globalThis !== "undefined") {
  globalThis.matchMedia = globalThis.matchMedia || matchMedia;
}

const inheritedProperties = new Set([
  "color", "fontSize", "fontFamily", "fontWeight", "fontStyle", "language",
  "letterSpacing", "wordSpacing", "tabSize", "textIndent", "textTransform",
  "textAlignLast", "textAlign", "whiteSpace", "rubyAlign", "visibility",
  "cursor", "pointerEvents", "direction", "writingMode", "lineHeight"
]);

function resolveVariablesInString(str, varsMap) {
  if (typeof str !== "string" || !str.includes("var(")) return str;
  return str.replace(/var\(\s*(--[a-zA-Z0-9-_]+)\s*(?:,\s*([^)]+))?\)/g, (match, name, fallback) => {
    if (varsMap.has(name)) {
      return resolveVariablesInString(varsMap.get(name), varsMap);
    }
    if (fallback != null) {
      return resolveVariablesInString(fallback.trim(), varsMap);
    }
    return match;
  });
}

function resolveNodeVariables(nodeStyle, inheritedVars = new Map(), quoteDepth = 0) {
  const currentVars = new Map();
  for (const [k, v] of inheritedVars.entries()) {
    const reg = propertyRegistry.get(k);
    if (reg && reg.inherits === false) {
      if (reg.initialValue !== undefined) currentVars.set(k, reg.initialValue);
    } else {
      currentVars.set(k, v);
    }
  }
  for (const [k, reg] of propertyRegistry.entries()) {
    if (!currentVars.has(k) && reg.initialValue !== undefined) {
      currentVars.set(k, reg.initialValue);
    }
  }
  for (const [k, v] of Object.entries(nodeStyle)) {
    if (k.startsWith("--") && v != null) {
      currentVars.set(k, String(v));
    }
  }
  return currentVars;
}

function isLengthOrKeyword(val) {
  if (typeof val !== "string") return false;
  const s = val.trim();
  if (s === "auto" || s === "content" || s === "min-content" || s === "max-content" || s === "fit-content") return true;
  if (/px|%|em|rem|lh|rlh|vw|vh|vmin|vmax|q|cm|mm|in|pt|pc|calc\(|min\(|max\(|clamp\(/i.test(s)) return true;
  return isNaN(Number(s));
}

export { getPreferences, setPreferences };

export function isReadWrite(node) {
  if (!node) return false;
  if (node.props?.contentEditable === true || node.props?.contenteditable === "true" || node.props?.contenteditable === "") {
    return true;
  }
  if (node.type === "input" || node.type === "textarea") {
    return !node.props?.disabled && !node.props?.readOnly && !node.props?.readonly;
  }
  return false;
}

export function isReadOnly(node) {
  return !isReadWrite(node);
}

const openPopovers = new Set();

export function isPopoverOpen(node) {
  if (!node) return false;
  return openPopovers.has(node) || Boolean(node._popoverOpen) || Boolean(node.props?.open && node.props?.popover);
}

export function showPopover(node) {
  if (!node || !node.props?.popover) return;
  const kind = String(node.props.popover).toLowerCase();
  if (kind !== "manual") {
    for (const other of Array.from(openPopovers)) {
      if (String(other.props?.popover).toLowerCase() !== "manual" && !isAncestor(other, node)) {
        hidePopover(other);
      }
    }
  }
  openPopovers.add(node);
  node._popoverOpen = true;
}

export function hidePopover(node) {
  if (!node) return;
  openPopovers.delete(node);
  node._popoverOpen = false;
}

export function togglePopover(node, force) {
  if (force === undefined) {
    if (isPopoverOpen(node)) hidePopover(node);
    else showPopover(node);
  } else if (force) {
    showPopover(node);
  } else {
    hidePopover(node);
  }
}

export function closeAllAutoPopovers(exceptNode = null) {
  for (const p of Array.from(openPopovers)) {
    if (p !== exceptNode && String(p.props?.popover).toLowerCase() !== "manual" && !isAncestor(p, exceptNode)) {
      hidePopover(p);
    }
  }
}

function isAncestor(parent, child) {
  let cur = child?.parent;
  while (cur) {
    if (cur === parent) return true;
    cur = cur.parent;
  }
  return false;
}

export function resolveQuotes(quotes = "auto", lang = "", depth = 0) {
  if (quotes === "none") return null;
  if (quotes === "auto" || !quotes) {
    const l = String(lang).toLowerCase();
    if (l.startsWith("fr")) {
      return depth % 2 === 0 ? { open: "« ", close: " »" } : { open: "“", close: "”" };
    } else if (l.startsWith("de")) {
      return depth % 2 === 0 ? { open: "„", close: "“" } : { open: "‚", close: "‘" };
    } else if (l.startsWith("ja") || l.startsWith("zh")) {
      return depth % 2 === 0 ? { open: "「", close: "」" } : { open: "『", close: "』" };
    } else {
      return depth % 2 === 0 ? { open: "“", close: "”" } : { open: "‘", close: "’" };
    }
  }
  const parts = quotes.match(/(?:[^\s"']+|"[^"]*"|'[^']*')+/g) || [];
  const cleanParts = parts.map(p => p.replace(/^["']|["']$/g, ""));
  const pairs = [];
  for (let i = 0; i < cleanParts.length; i += 2) {
    if (i + 1 < cleanParts.length) {
      pairs.push({ open: cleanParts[i], close: cleanParts[i + 1] });
    }
  }
  if (pairs.length === 0) return { open: "“", close: "”" };
  return pairs[Math.min(depth, pairs.length - 1)];
}

function flexValues(style) {
  let grow = 0, shrink = 1, basis = "auto";
  if (typeof style.flex === "number") {
    grow = style.flex;
    basis = 0;
  } else if (style.flex === "none") {
    grow = 0;
    shrink = 0;
    basis = "auto";
  } else if (style.flex === "auto") {
    grow = 1;
    shrink = 1;
    basis = "auto";
  } else if (style.flex === "initial") {
    grow = 0;
    shrink = 1;
    basis = "auto";
  } else if (typeof style.flex === "string") {
    const parts = splitSpacing(style.flex.trim());
    if (parts.length < 1 || parts.length > 3) throw Error(`Invalid flex: ${style.flex}`);
    if (parts.length === 1) {
      if (isLengthOrKeyword(parts[0])) {
        grow = 1;
        shrink = 1;
        basis = parts[0];
      } else {
        grow = Number(parts[0]);
        shrink = 1;
        basis = 0;
      }
    } else if (parts.length === 2) {
      if (isLengthOrKeyword(parts[0])) {
        basis = parts[0];
        grow = Number(parts[1]);
        shrink = 1;
      } else if (isLengthOrKeyword(parts[1])) {
        grow = Number(parts[0]);
        shrink = 1;
        basis = parts[1];
      } else {
        grow = Number(parts[0]);
        shrink = Number(parts[1]);
        basis = 0;
      }
    } else {
      grow = Number(parts[0]);
      shrink = Number(parts[1]);
      basis = parts[2];
    }
  }
  if (style.flexGrow != null) grow = style.flexGrow;
  if (style.flexShrink != null) shrink = style.flexShrink;
  if (typeof grow !== "number" || !Number.isFinite(grow) || grow < 0 || typeof shrink !== "number" || !Number.isFinite(shrink) || shrink < 0) throw Error("Invalid flex factor");
  return {
    grow,
    shrink,
    basis: style.flexBasis ?? basis,
  };
}

// Inline object declarations are applied in insertion order. Logical and
// physical declarations targeting the same side therefore obey last-declared
// precedence; the mode and direction are computed for the whole style object.
export function physicalStyle(style, inherited = {}, currentVars = new Map(), node = null) {
  const mode = style.writingMode ?? style['writing-mode'] ?? inherited.writingMode ?? "horizontal-tb";
  const direction = style.direction ?? inherited.direction ?? "ltr";
  if (!["horizontal-tb", "vertical-rl", "vertical-lr", "sideways-rl", "sideways-lr"].includes(mode) || !["ltr", "rtl"].includes(direction)) throw Error("Unsupported writing mode or direction");
  const vertical = mode !== "horizontal-tb";
  const isSidewaysLr = mode === "sideways-lr";
  const inlineStart = vertical ? (isSidewaysLr ? (direction === "ltr" ? "Bottom" : "Top") : (direction === "ltr" ? "Top" : "Bottom")) : (direction === "ltr" ? "Left" : "Right");
  const inlineEnd = vertical ? (isSidewaysLr ? (direction === "ltr" ? "Top" : "Bottom") : (direction === "ltr" ? "Bottom" : "Top")) : (direction === "ltr" ? "Right" : "Left");
  const blockStart = vertical ? ((mode === "vertical-rl" || mode === "sideways-rl") ? "Right" : "Left") : "Top";
  const blockEnd = vertical ? ((mode === "vertical-rl" || mode === "sideways-rl") ? "Left" : "Right") : "Bottom";
  const logical = { InlineStart: inlineStart, InlineEnd: inlineEnd, BlockStart: blockStart, BlockEnd: blockEnd };
  const sizes = { inlineSize: vertical ? "height" : "width", blockSize: vertical ? "width" : "height",
    minInlineSize: vertical ? "minHeight" : "minWidth", minBlockSize: vertical ? "minWidth" : "minHeight",
    maxInlineSize: vertical ? "maxHeight" : "maxWidth", maxBlockSize: vertical ? "maxWidth" : "maxHeight" };
  const result = { writingMode: mode, direction };
  for (let [key, value] of Object.entries(style)) {
    if (value == null) continue;
    if (!key.startsWith('--') && !key.startsWith('@') && !key.startsWith(':')) key = key.replace(/-([a-z])/g, (_, c) => c.toUpperCase());
    if (key.startsWith("@media")) {
      const match = key.replace(/^@media\s*/i, "");
      if (matchMedia(match).matches && typeof value === "object" && value !== null) {
        Object.assign(result, physicalStyle(value, { ...inherited, writingMode: mode, direction }, currentVars, node));
      }
      continue;
    }
    if (key === ":read-only") {
      if (node && isReadOnly(node) && typeof value === "object" && value !== null) {
        Object.assign(result, physicalStyle(value, { ...inherited, writingMode: mode, direction }, currentVars, node));
      }
      continue;
    }
    if (key === ":read-write") {
      if (node && isReadWrite(node) && typeof value === "object" && value !== null) {
        Object.assign(result, physicalStyle(value, { ...inherited, writingMode: mode, direction }, currentVars, node));
      }
      continue;
    }
    if (key === ":popover-open") {
      if (node && isPopoverOpen(node) && typeof value === "object" && value !== null) {
        Object.assign(result, physicalStyle(value, { ...inherited, writingMode: mode, direction }, currentVars, node));
      }
      continue;
    }
    if (value === "revert") {
      if (inheritedProperties.has(key)) {
        value = inherited[key] ?? null;
        if (value == null) continue;
      } else {
        continue;
      }
    }
    if (typeof value === "string") {
      value = resolveVariablesInString(value, currentVars);
    }
    if (key === "flexFlow" && typeof value === "string") {
      const parts = splitSpacing(value.trim());
      for (const part of parts) {
        if (["row", "column", "row-reverse", "column-reverse"].includes(part)) {
          result.flexDirection = part;
        } else if (["nowrap", "wrap", "wrap-reverse"].includes(part)) {
          result.flexWrap = part;
        }
      }
      continue;
    }
    if (key === "gap" && typeof value === "string") {
      const parts = splitSpacing(value.trim());
      if (parts.length === 2) {
        result.rowGap = parts[0];
        result.columnGap = parts[1];
        continue;
      }
    }
    if (key === "columns") {
      if (typeof value === "number") {
        result.columnCount = value;
        result.columnWidth = "auto";
      } else if (typeof value === "string") {
        const parts = splitSpacing(value.trim());
        if (parts.length === 1) {
          if (parts[0] === "auto") {
            result.columnCount = "auto";
            result.columnWidth = "auto";
          } else if (/^\d+$/.test(parts[0])) {
            result.columnCount = Number(parts[0]);
            result.columnWidth = "auto";
          } else {
            result.columnWidth = parts[0];
            result.columnCount = "auto";
          }
        } else if (parts.length === 2) {
          if (/^\d+$/.test(parts[0])) {
            result.columnCount = Number(parts[0]);
            result.columnWidth = parts[1];
          } else {
            result.columnWidth = parts[0];
            result.columnCount = /^\d+$/.test(parts[1]) ? Number(parts[1]) : parts[1];
          }
        }
      }
      continue;
    }
    if (key === "columnRule" && typeof value === "string") {
      const tokens = splitSpacing(value.trim());
      const ruleStyles = ["none", "hidden", "dotted", "dashed", "solid", "double", "groove", "ridge", "inset", "outset"];
      let width, styleName, color;
      for (const token of tokens) {
        if (ruleStyles.includes(token)) {
          styleName = token;
        } else if (["thin", "medium", "thick"].includes(token) || /^[+\-.\d]/.test(token) || /^(calc|min|max|clamp)\(/i.test(token)) {
          width = token;
        } else {
          color = token;
        }
      }
      result.columnRuleWidth = width ?? "medium";
      result.columnRuleStyle = styleName ?? "none";
      result.columnRuleColor = color ?? "currentColor";
      continue;
    }
    if (key === "placeContent" && typeof value === "string") {
      const parts = splitAlignment(value);
      result.alignContent = parts[0];
      result.justifyContent = parts[1] ?? parts[0];
      continue;
    }
    if (key === "placeItems" && typeof value === "string") {
      const parts = splitAlignment(value);
      result.alignItems = parts[0];
      result.justifyItems = parts[1] ?? parts[0];
      continue;
    }
    if (key === "placeSelf" && typeof value === "string") {
      const parts = splitAlignment(value);
      result.alignSelf = parts[0];
      result.justifySelf = parts[1] ?? parts[0];
      continue;
    }
    if (key === "wordWrap") {
      result.overflowWrap = value;
      continue;
    }
    if (key === "pageBreakBefore") {
      result.breakBefore = value;
      continue;
    }
    if (key === "pageBreakAfter") {
      result.breakAfter = value;
      continue;
    }
    if (key === "pageBreakInside") {
      result.breakInside = value;
      continue;
    }
    if (key === "inset") {
      const sides = boxSides(value, { auto: true, negative: true });
      for (const [letter, side] of [["t", "top"], ["r", "right"], ["b", "bottom"], ["l", "left"]]) result[side] = sides[letter];
      continue;
    }
    if (key === "insetInline" || key === "inset-inline") {
      const parts = (typeof value === "string" ? splitSpacing(value.trim()) : [value]).map(v => spacingValue(v, { auto: true, negative: true }));
      if (parts.length < 1 || parts.length > 2) throw Error(`Invalid logical sides: ${value}`);
      result[logical.InlineStart.toLowerCase()] = parts[0];
      result[logical.InlineEnd.toLowerCase()] = parts[1] ?? parts[0];
      continue;
    }
    if (key === "insetBlock" || key === "inset-block") {
      const parts = (typeof value === "string" ? splitSpacing(value.trim()) : [value]).map(v => spacingValue(v, { auto: true, negative: true }));
      if (parts.length < 1 || parts.length > 2) throw Error(`Invalid logical sides: ${value}`);
      result[logical.BlockStart.toLowerCase()] = parts[0];
      result[logical.BlockEnd.toLowerCase()] = parts[1] ?? parts[0];
      continue;
    }
    if (key === "insetInlineStart" || key === "inset-inline-start") {
      result[logical.InlineStart.toLowerCase()] = spacingValue(value, { auto: true, negative: true });
      continue;
    }
    if (key === "insetInlineEnd" || key === "inset-inline-end") {
      result[logical.InlineEnd.toLowerCase()] = spacingValue(value, { auto: true, negative: true });
      continue;
    }
    if (key === "insetBlockStart" || key === "inset-block-start") {
      result[logical.BlockStart.toLowerCase()] = spacingValue(value, { auto: true, negative: true });
      continue;
    }
    if (key === "insetBlockEnd" || key === "inset-block-end") {
      result[logical.BlockEnd.toLowerCase()] = spacingValue(value, { auto: true, negative: true });
      continue;
    }
    if (key === "margin" || key === "padding" || key === "borderWidth" || key === "border" || key === "scrollMargin" || key === "scrollPadding") {
      const options = (key === "margin" || key === "scrollMargin") ? { auto: true, negative: true } : (key === "scrollPadding" ? { auto: true } : {});
      const sides = boxSides(value, options);
      const isBorder = key === "borderWidth" || key === "border";
      const prefix = isBorder ? "border" : key;
      const suffix = isBorder ? "Width" : "";
      for (const [letter, side] of [["t", "Top"], ["r", "Right"], ["b", "Bottom"], ["l", "Left"]]) result[prefix + side + suffix] = sides[letter];
      continue;
    }
    if (key === "overflowBlock") {
      result[vertical ? "overflowX" : "overflowY"] = value;
      continue;
    }
    if (key === "overflowInline") {
      result[vertical ? "overflowY" : "overflowX"] = value;
      continue;
    }
    if (sizes[key]) { result[sizes[key]] = value; continue; }
    const corner = key.match(/^border(Start|End)(Start|End)Radius$/);
    if (corner) {
      const block = logical['Block' + corner[1]];
      const inline = logical['Inline' + corner[2]];
      const topBottom = ['Top', 'Bottom'].includes(block) ? block : inline;
      const leftRight = ['Left', 'Right'].includes(block) ? block : inline;
      result['border' + topBottom + leftRight + 'Radius'] = value;
      continue;
    }
    const edge = key.match(/^(margin|padding|border|scrollMargin|scrollPadding)(InlineStart|InlineEnd|BlockStart|BlockEnd)(Width)?$/);
    if (edge && edge[1] !== 'border') { result[edge[1] + logical[edge[2]] + (edge[3] ?? "")] = value; continue; }
    const logicalBorder = key.match(/^border(Inline|Block)(Start|End)?(Width|Color|Style)?$/);
    if (logicalBorder) {
      const sides = logicalBorder[2] ? [logical[logicalBorder[1] + logicalBorder[2]]] : [logical[logicalBorder[1] + 'Start'], logical[logicalBorder[1] + 'End']];
      const suffix = logicalBorder[3];
      sides.forEach(side => {
        const prefix = 'border' + side;
        if (!(prefix + 'Style' in result)) result[prefix + 'Style'] = prefix + 'Width' in result ? 'solid' : 'none';
        if (!(prefix + 'Width' in result)) result[prefix + 'Width'] = 'medium';
        if (!(prefix + 'Color' in result)) result[prefix + 'Color'] = 'currentColor';
      });
      if (suffix) {
        const values = typeof value === 'string' ? splitSpacing(value.trim()) : [value];
        if (!values.length || values.length > sides.length) throw Error(`Invalid logical border: ${value}`);
        if (suffix === 'Style' && values.some(v => !['none', 'hidden', 'solid', 'double', 'dotted', 'dashed', 'groove', 'ridge', 'inset', 'outset'].includes(v))) throw Error(`Invalid border style: ${value}`);
        if (suffix === 'Width' && values.some(v => typeof v === 'number' ? !Number.isFinite(v) || v < 0 : /^-/.test(v) || v.includes('%'))) throw Error(`Invalid border width: ${value}`);
        sides.forEach((side, i) => { result['border' + side + suffix] = values[i] ?? values[0]; });
      } else {
        const styles = ['none', 'hidden', 'solid', 'double', 'dotted', 'dashed', 'groove', 'ridge', 'inset', 'outset'];
        let width = 'medium', line = 'none', color = 'currentColor';
        const seen = new Set();
        for (const token of splitSpacing(String(value).trim())) {
          const kind = styles.includes(token) ? 'style' : /^(thin|medium|thick)$|^(?:calc|min|max|clamp)\(|^[+\-.\d]/.test(token) ? 'width' : 'color';
          if (seen.has(kind)) throw Error(`Invalid logical border: ${value}`);
          seen.add(kind);
          if (kind === 'style') line = token; else if (kind === 'width') width = token; else color = token;
        }
        sides.forEach(side => {
          result['border' + side + 'Width'] = width;
          result['border' + side + 'Style'] = line;
          result['border' + side + 'Color'] = color;
        });
      }
      continue;
    }
    const pair = key.match(/^(margin|padding|border|scrollMargin|scrollPadding)(Inline|Block)(Width)?$/);
    if (pair) {
      const parts = typeof value === "string" ? splitSpacing(value.trim()) : [value];
      if (parts.length < 1 || parts.length > 2) throw Error(`Invalid logical sides: ${value}`);
      result[pair[1] + logical[pair[2] + "Start"] + (pair[3] ?? "")] = parts[0];
      result[pair[1] + logical[pair[2] + "End"] + (pair[3] ?? "")] = parts[1] ?? parts[0];
      continue;
    }
    if ((key === "textWrap" || key === "whiteSpaceCollapse") && typeof value === "string") {
      const parts = splitSpacing(value.trim());
      for (const part of parts) {
        if (["wrap", "nowrap"].includes(part)) {
          result.textWrapMode = part;
        } else if (["auto", "balance", "stable", "pretty"].includes(part)) {
          result.textWrapStyle = part;
        }
      }
      result.textWrap = value;
      continue;
    }
    if ((key === "webkitTextStroke" || key === "-webkit-text-stroke" || key === "textStroke") && typeof value === "string") {
      const parts = splitSpacing(value.trim());
      for (const part of parts) {
        if (["thin", "medium", "thick"].includes(part) || /^[+\-.\d]/.test(part) || /^(calc|min|max|clamp)\(/i.test(part)) {
          result.textStrokeWidth = part;
        } else {
          result.textStrokeColor = part;
        }
      }
      continue;
    }
    if (key === "webkitTextStrokeColor" || key === "-webkit-text-stroke-color") {
      result.textStrokeColor = value;
      continue;
    }
    if (key === "webkitTextStrokeWidth" || key === "-webkit-text-stroke-width") {
      result.textStrokeWidth = value;
      continue;
    }
    if (key === "webkitTextFillColor" || key === "-webkit-text-fill-color") {
      result.textFillColor = value;
      continue;
    }
    if (key === "textDecoration" && typeof value === "string") {
      const parts = splitSpacing(value.trim());
      for (const part of parts) {
        if (["none", "underline", "overline", "line-through", "spelling-error", "grammar-error"].includes(part)) {
          result.textDecorationLine = result.textDecorationLine && part !== "none" ? result.textDecorationLine + " " + part : part;
        } else if (["auto", "from-font"].includes(part) || /^[+\-.\d]/.test(part) || /^(calc|min|max|clamp)\(/i.test(part)) {
          result.textDecorationThickness = part;
        } else if (["solid", "double", "dotted", "dashed", "wavy"].includes(part)) {
          result.textDecorationStyle = part;
        } else {
          result.textDecorationColor = part;
        }
      }
      result.textDecoration = value;
      continue;
    }
    result[key] = value;
  }
  return result;
}

function opacityValue(value) {
  if (value == null) return { number: 1, css: null };
  if (typeof value === "number" && Number.isFinite(value)) return {number: Math.max(0, Math.min(1, value)),css:null};
  if (typeof value === "string") {
    const str=value.trim();
    if (/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?%?$/i.test(str)) {
      const number=Number(str.endsWith("%")?str.slice(0,-1):str)/(str.endsWith("%")?100:1);
      return {number:Math.max(0,Math.min(1,number)),css:null};
    }
    if(/^(?:calc|min|max|clamp|abs|sign|round|mod|rem|sin|cos|tan|asin|acos|atan|atan2|pow|sqrt|hypot|log|exp)\(/i.test(str)) return {number:1,css:str};
  }
  throw Error("Invalid opacity: " + value);
}

function authoredMask(style,names) {return names.reduce((mask,key,i)=>mask|(style[key]!=null?1<<i:0),0);}
function radiusCss(value) {
  if(value==null) return null;
  if(typeof value==="number" && Number.isFinite(value) && value>=0) return value+"px";
  if(typeof value==="string" && value.trim()) return value.trim();
  throw Error("Invalid border radius: "+value);
}
function styleLength(value,{normal=false,negative=false}={}) {
  if(value==null || (normal && value==="normal")) return {number:null,css:null};
  if(typeof value==="number" && Number.isFinite(value) && (negative || value>=0)) return {number:value,css:null};
  if(typeof value==="string" && value.trim()) return {number:null,css:value.trim()};
  throw Error("Invalid style length: "+value);
}

export class CustomStateSet extends Set {
  add(val) { return super.add(String(val).replace(/^--/, "")); }
  has(val) { return super.has(String(val).replace(/^--/, "")); }
  delete(val) { return super.delete(String(val).replace(/^--/, "")); }
}

export function supportsProperty(property, value) {
  if (!property) return false;
  const prop = property.trim().toLowerCase();
  const known = [
    "display", "position", "top", "right", "bottom", "left", "inset",
    "grid-template-columns", "grid-template-rows", "grid-auto-flow", "subgrid",
    "flex", "flex-direction", "flex-wrap", "flex-grow", "flex-shrink", "flex-basis",
    "justify-content", "align-items", "align-content", "align-self",
    "shape-outside", "shape-margin", "shape-image-threshold", "clip-path",
    "clip-rule", "color-interpolation", "shape-rendering", "text-rendering", "vector-effect",
    "cx", "cy", "r", "rx", "ry", "x", "y", "fill", "stroke", "stroke-width",
    "transform", "transform-origin", "transition", "opacity", "overflow", "box-sizing",
    "background", "background-image", "background-color", "color", "font-size", "font-family",
    "letter-spacing", "word-spacing"
  ];
  if (!known.includes(prop) && !prop.startsWith("--")) return false;
  if (value == null) return true;
  const val = String(value).trim();
  if (prop === "grid-template-columns" || prop === "grid-template-rows") {
    if (val.startsWith("subgrid")) return true;
  }
  if (prop === "position" && val === "sticky") return true;
  return true;
}

export function evalSupportsCondition(cond) {
  const s = String(cond).trim();
  if (!s) return false;
  if (s.includes("-webkit-transform-3d")) return true;
  if (/^selector\(.+\)$/i.test(s)) return true;
  if (/^font-tech\(.+\)$/i.test(s)) {
    return /features-opentype|variations|palettes|color-COLRv0|color-COLRv1/i.test(s);
  }
  if (/^font-format\(.+\)$/i.test(s)) {
    return /woff|woff2|opentype|truetype|collection|svg/i.test(s);
  }
  if (/^not\s+/i.test(s)) {
    return !evalSupportsCondition(s.slice(4).trim());
  }
  if (s.startsWith("(") && s.endsWith(")")) {
    const inner = s.slice(1, -1).trim();
    if (inner.includes(" and ")) {
      const parts = inner.split(" and ");
      return parts.every(p => evalSupportsCondition(p.trim()));
    }
    if (inner.includes(" or ")) {
      const parts = inner.split(" or ");
      return parts.some(p => evalSupportsCondition(p.trim()));
    }
    if (inner.includes(":")) {
      const [prop, ...valParts] = inner.split(":");
      return supportsProperty(prop.trim(), valParts.join(":").trim());
    }
    return evalSupportsCondition(inner);
  }
  return false;
}

export const CSS = {
  supports(first, second) {
    if (second !== undefined) return supportsProperty(first, second);
    return evalSupportsCondition(first);
  }
};
if (typeof globalThis !== "undefined") {
  globalThis.CSS = CSS;
}

export function resolveAttr(val, props) {
  if (typeof val !== "string" || !val.includes("attr(")) return val;
  return val.replace(/attr\(\s*([\w-]+)(?:\s+([\w%]+))?(?:\s*,\s*([^)]*))?\s*\)/g, (match, attrName, typeOrUnit, fallback) => {
    let found = props ? props[attrName] : undefined;
    if (found === undefined && props) {
      const camel = attrName.replace(/-([a-z])/g, (_, c) => c.toUpperCase());
      found = props[camel];
    }
    if (found !== undefined && found !== null) {
      if (typeOrUnit && !isNaN(Number(found)) && !String(found).endsWith(typeOrUnit)) {
        return String(found) + typeOrUnit;
      }
      return String(found);
    }
    if (fallback !== undefined) {
      return fallback.trim();
    }
    return "";
  });
}

function zoomValue(value, inherited = 1.0) {
  if (value == null) return inherited;
  if (typeof value === "number") {
    if (!Number.isFinite(value) || value <= 0) throw Error("Invalid zoom: " + value);
    return value * inherited;
  }
  if (typeof value === "string") {
    const s = value.trim().toLowerCase();
    if (s === "normal" || s === "reset") return 1.0;
    if (s.endsWith("%")) {
      const num = Number(s.slice(0, -1));
      if (!Number.isFinite(num) || num <= 0) throw Error("Invalid zoom: " + value);
      return (num / 100) * inherited;
    }
    const num = Number(s);
    if (Number.isFinite(num) && num > 0) return num * inherited;
  }
  throw Error("Invalid zoom: " + value);
}

function zIndexValue(value) {
  if (value == null || value === "auto") return null;
  if (typeof value === "number" && Number.isFinite(value)) return Math.trunc(value);
  if (typeof value === "string") {
    const trimmed = value.trim();
    if (trimmed === "auto") return null;
    if (/^[+-]?\d+$/.test(trimmed)) {
      const parsed = parseInt(trimmed, 10);
      if (Number.isFinite(parsed)) return parsed;
    }
  }
  throw Error("Invalid zIndex: " + value);
}

const fontFaceRegistry = new Map();
export function registerFontFace(descriptor) {
  if (descriptor && descriptor.fontFamily) {
    fontFaceRegistry.set(descriptor.fontFamily.toLowerCase(), descriptor);
  }
}

let activeViewTransition = false;
let activeViewTransitionTypes = new Set();
export function isViewTransitionActive(type) {
  if (!activeViewTransition) return false;
  if (type) return activeViewTransitionTypes.has(type);
  return true;
}

export const INHERITED_CSS_PROPERTIES = new Set([
  "color", "fontFamily", "fontSize", "fontWeight", "fontStyle", "language",
  "lineHeight", "letterSpacing", "wordSpacing", "tabSize", "textAlign",
  "textAlignLast", "textTransform", "textIndent", "whiteSpace", "visibility",
  "cursor", "direction", "writingMode"
]);

export const INITIAL_CSS_VALUES = {
  display: "block",
  writingMode: "horizontal-tb",
  direction: "ltr",
  flexDirection: "row",
  flexWrap: "nowrap",
  justifyContent: "normal",
  alignItems: "stretch",
  alignContent: "stretch",
  alignSelf: "auto",
  flexGrow: 0,
  flexShrink: 1,
  flexBasis: "auto",
  order: 0,
  width: null,
  height: null,
  minWidth: null,
  minHeight: null,
  maxWidth: null,
  maxHeight: null,
  aspectRatio: null,
  margin: 0,
  padding: 0,
  borderWidth: 0,
  borderColor: "",
  borderRadius: 0,
  backgroundColor: "",
  color: "",
  fontFamily: "system-ui",
  fontSize: 0,
  fontWeight: 400,
  fontStyle: "normal",
  language: "",
  lineHeight: "normal",
  letterSpacing: "normal",
  wordSpacing: "normal",
  tabSize: 8,
  textAlign: "left",
  textAlignLast: "auto",
  textTransform: "none",
  textIndent: 0,
  textOverflow: "clip",
  whiteSpace: "normal",
  visibility: "visible",
  pointerEvents: "auto",
  cursor: "auto",
  position: "static",
  top: null,
  right: null,
  bottom: null,
  left: null,
  zIndex: null,
  opacity: 1.0,
  isolation: "auto",
  transform: "none",
  transformOrigin: "50% 50%",
  transformBox: "border-box",
  backfaceVisibility: "visible",
  transformStyle: "flat",
  perspective: null,
  perspectiveOrigin: "50% 50%",
  touchAction: "auto",
  transition: "",
  transitionProperty: "all",
  transitionDuration: 0,
  transitionTimingFunction: "ease",
  transitionDelay: 0,
  transitionBehavior: "normal",
  boxSizing: "content-box",
  overflow: "visible",
  outlineStyle: "none",
  outlineWidth: 0,
  outlineColor: ""
};

export function resolveUnsetValues(style, inherited = {}) {
  const resolved = { ...style };
  for (const [key, value] of Object.entries(resolved)) {
    if (value === "unset") {
      if (INHERITED_CSS_PROPERTIES.has(key)) {
        resolved[key] = inherited[key] !== undefined ? inherited[key] : INITIAL_CSS_VALUES[key];
      } else {
        resolved[key] = INITIAL_CSS_VALUES[key];
      }
    }
  }
  return resolved;
}

export function snapshot(node, inherited = {}, inheritedVars = new Map(), quoteDepth = 0) {
  let authored = resolveUnsetValues(node.props.style || {}, inherited);
  const nodeStates = node.states || (node.props?.states instanceof Set ? node.props.states : (Array.isArray(node.props?.states) ? new Set(node.props.states) : (typeof node.props?.states === "object" ? new Set(Object.keys(node.props.states).filter(k => node.props.states[k])) : new Set())));
  if (node.props?.state) nodeStates.add(String(node.props.state));

  const resolvedPropsStyle = authored;
  for (const [key, val] of Object.entries(resolvedPropsStyle)) {
    if (key.startsWith(":state(") && key.endsWith(")")) {
      const stateName = key.slice(7, -1).trim().replace(/^--/, "");
      if (nodeStates.has(stateName) && typeof val === "object" && val !== null) {
        Object.assign(resolvedPropsStyle, val);
      }
    } else if (key.startsWith("@supports") && typeof val === "object" && val !== null) {
      const condition = key.slice(9).trim();
      if (evalSupportsCondition(condition)) {
        Object.assign(resolvedPropsStyle, val);
      }
    }
  }

  if (node.children && node.children.some(c => c.type === "slot")) {
    const defaultSlot = node.children.find(c => c.type === "slot" && !c.props.name);
    const namedSlots = new Map();
    for (const c of node.children) {
      if (c.type === "slot" && c.props.name) namedSlots.set(c.props.name, c);
    }
    for (const child of node.children) {
      if (child.type === "slot") continue;
      const slotName = child.props.slot;
      const targetSlot = slotName ? namedSlots.get(slotName) : defaultSlot;
      if (targetSlot) {
        targetSlot._slottedChildren = targetSlot._slottedChildren || [];
        if (!targetSlot._slottedChildren.includes(child)) targetSlot._slottedChildren.push(child);
      }
    }
  }

  if (node.props?.slot || node.parent?.type === "slot") {
    const slotParent = node.parent?.type === "slot" ? node.parent.parent : node.parent;
    if (slotParent?.props?.style) {
      for (const [k, v] of Object.entries(slotParent.props.style)) {
        if (k.startsWith("::slotted(") && k.endsWith(")") && typeof v === "object" && v !== null) {
          const innerSel = k.slice(10, -1).trim();
          if (innerSel === "*" || innerSel === node.type || (node.props?.class && node.props.class.includes(innerSel.replace(/^\./, "")))) {
            Object.assign(resolvedPropsStyle, v);
          }
        }
      }
    }
  }


  if (node._isHovered) {
    if (authored[":hover"]) Object.assign(authored, resolveUnsetValues(authored[":hover"], inherited));
    if (authored["_hover"]) Object.assign(authored, resolveUnsetValues(authored["_hover"], inherited));
    if (node.props[":hover"]) Object.assign(authored, resolveUnsetValues(node.props[":hover"], inherited));
    if (node.props["_hover"]) Object.assign(authored, resolveUnsetValues(node.props["_hover"], inherited));
  }
  if (node._isFocused) {
    if (authored[":focus"]) Object.assign(authored, resolveUnsetValues(authored[":focus"], inherited));
    if (authored["_focus"]) Object.assign(authored, resolveUnsetValues(authored["_focus"], inherited));
    if (node.props[":focus"]) Object.assign(authored, resolveUnsetValues(node.props[":focus"], inherited));
    if (node.props["_focus"]) Object.assign(authored, resolveUnsetValues(node.props["_focus"], inherited));
  }
  if (node._isActive) {
    if (authored[":active"]) Object.assign(authored, resolveUnsetValues(authored[":active"], inherited));
    if (authored["_active"]) Object.assign(authored, resolveUnsetValues(authored["_active"], inherited));
    if (node.props[":active"]) Object.assign(authored, resolveUnsetValues(node.props[":active"], inherited));
    if (node.props["_active"]) Object.assign(authored, resolveUnsetValues(node.props["_active"], inherited));
  }
  let effectivePropsStyle = authored;
  if (node._userInteracted) {
    const valid = checkValidity(node);
    if (valid && effectivePropsStyle[":user-valid"]) {
      Object.assign(effectivePropsStyle, effectivePropsStyle[":user-valid"]);
    } else if (!valid && effectivePropsStyle[":user-invalid"]) {
      Object.assign(effectivePropsStyle, effectivePropsStyle[":user-invalid"]);
    }
  }

  for (const [k, v] of Object.entries(effectivePropsStyle)) {
    effectivePropsStyle[k] = resolveAttr(v, node.props);
  }
  if (activeViewTransition && effectivePropsStyle.activeViewTransition) {
    Object.assign(effectivePropsStyle, effectivePropsStyle.activeViewTransition);
  }
  const nestedStyle = resolveNestedStyles(node, effectivePropsStyle);
  const currentVars = resolveNodeVariables(nestedStyle, inheritedVars);
  const style = physicalStyle(nestedStyle, inherited, currentVars, node);

  const activeTarget = renderer.getTarget ? renderer.getTarget() : "";
  const isTarget = Boolean(node.props.target || (node.props.id && String(node.props.id) === activeTarget));
  if (isTarget && style[":target"]) {
    Object.assign(style, style[":target"]);
  }
  const activeTargetText = renderer.getTargetText ? renderer.getTargetText() : "";
  const isTargetText = Boolean(node.props.targetText || (node.type === "text" && activeTargetText && node.text.includes(activeTargetText)));
  if (isTargetText && style["::target-text"]) {
    Object.assign(style, style["::target-text"]);
  }

  if (typeof style.textDecoration === "string") {
    const parts = splitSpacing(style.textDecoration.trim());
    const line = [];
    let decorStyle, decorColor, decorThickness;
    for (const token of parts) {
      if (["none", "underline", "overline", "line-through", "spelling-error", "grammar-error"].includes(token)) {
        line.push(token);
      } else if (["solid", "double", "dotted", "dashed", "wavy"].includes(token)) {
        decorStyle = token;
      } else if (token === "auto" || token === "from-font" || /^[+\-]?\d+(?:\.\d+)?(?:px|%|em|rem)?$/i.test(token)) {
        decorThickness = token;
      } else {
        decorColor = token;
      }
    }
    if (line.length > 0) style.textDecorationLine ??= line.join(" ");
    if (decorStyle) style.textDecorationStyle ??= decorStyle;
    if (decorColor) style.textDecorationColor ??= decorColor;
    if (decorThickness != null) style.textDecorationThickness ??= decorThickness;
  }

  if (typeof style.textEmphasis === "string") {
    const parts = splitSpacing(style.textEmphasis.trim());
    const emphStyle = [];
    let emphColor;
    for (const token of parts) {
      if (["none", "circle", "dot", "double-circle", "triangle", "sesame", "filled", "open"].includes(token) || /^['"].*['"]$/.test(token)) {
        emphStyle.push(token);
      } else {
        emphColor = token;
      }
    }
    if (emphStyle.length > 0) style.textEmphasisStyle ??= emphStyle.join(" ");
    if (emphColor) style.textEmphasisColor ??= emphColor;
  }

  let borderSpacingX = 0, borderSpacingY = 0, borderSpacingCss = null;
  if (style.borderSpacing != null) {
    if (typeof style.borderSpacing === "number") {
      borderSpacingX = style.borderSpacing;
      borderSpacingY = style.borderSpacing;
    } else if (typeof style.borderSpacing === "string") {
      const parts = splitSpacing(style.borderSpacing.trim());
      if (parts.length === 1) {
        const v = parseFloat(parts[0]) || 0;
        borderSpacingX = v; borderSpacingY = v;
      } else if (parts.length >= 2) {
        borderSpacingX = parseFloat(parts[0]) || 0;
        borderSpacingY = parseFloat(parts[1]) || 0;
      }
      borderSpacingCss = style.borderSpacing.trim();
    }
  }

  const floodOp = style.floodOpacity != null ? opacityValue(style.floodOpacity) : { number: 1, css: null };


  let nextQuoteDepth = quoteDepth;
  let qText = node.text;
  if (node.type === "q") {
    nextQuoteDepth = quoteDepth + 1;
    if (qText) {
      const pair = resolveQuotes(style.quotes ?? inherited.quotes ?? "auto", node.props.lang ?? style.language ?? inherited.language ?? "", quoteDepth);
      if (pair) qText = `${pair.open}${qText}${pair.close}`;
    }
  }
  if(typeof style.outline==="string") {
    let width,kind,color;
    for(const token of splitSpacing(style.outline)) {
      if(["none","auto","solid","dashed","dotted","double","groove","ridge","inset","outset"].includes(token)) kind=token;
      else if(["thin","medium","thick"].includes(token) || /^[+\-.\d]/.test(token) || /^(calc|min|max|clamp|abs|round)\(/i.test(token)) width=token;
      else color=token;
    }
    style.outlineWidth??=width??"medium"; style.outlineStyle??=kind??"none"; style.outlineColor??=color??"currentColor";
  }
  const isTextarea = node.type === "textarea";
  const placeholder = (node.type === "input" || isTextarea) ? String(node.props.placeholder ?? "") : "";
  const isPlaceholder = isPlaceholderShown(node);
  if (isPlaceholder && node.props?.style?.[":placeholder-shown"]) {
    Object.assign(style, node.props.style[":placeholder-shown"]);
  }
  if (isPlaceholder && node.props?.placeholderShownStyle) {
    Object.assign(style, node.props.placeholderShownStyle);
  }
  const objectFit = ["fill", "contain", "cover", "none", "scale-down"].includes(style.objectFit) ? style.objectFit : "fill";
  const objectPosition = typeof style.objectPosition === "string" && style.objectPosition.trim() ? style.objectPosition.trim() : "50% 50%";

  let columnCount = null;
  let columnCountCss = null;
  if (typeof style.columnCount === "number") {
    columnCount = Math.max(1, Math.trunc(style.columnCount));
  } else if (typeof style.columnCount === "string") {
    const trimmed = style.columnCount.trim().toLowerCase();
    if (trimmed === "auto") {
      columnCountCss = "auto";
    } else if (/^\d+$/.test(trimmed)) {
      columnCount = Math.max(1, parseInt(trimmed, 10));
    } else {
      columnCountCss = trimmed;
    }
  }

  const columnWidthParsed = styleLength(style.columnWidth);
  const columnWidth = columnWidthParsed.number;
  let columnWidthCss = columnWidthParsed.css;
  if (style.columnWidth === "auto") columnWidthCss = "auto";

  const colRuleWidth = styleLength(style.columnRuleWidth);
  const columnRuleStyle = style.columnRuleStyle ?? "none";
  const columnRuleColor = typeof style.columnRuleColor === "string" ? style.columnRuleColor : "";

  const typographyNames = [
    "fontFamily", "fontWeight", "fontStyle", "language", "letterSpacing", "wordSpacing",
    "tabSize", "textTransform", "textAlignLast", "textIndent", "wordBreak", "whiteSpaceCollapse", "verticalAlign", "textOrientation", "textShadow",
    "textFillColor", "textStrokeWidth", "textStrokeColor", "textUnderlineOffset",
    "textUnderlinePosition", "textDecoration", "textDecorationLine", "textDecorationColor",
    "textDecorationThickness", "textWrap", "textWrapMode", "textWrapStyle", "rubyAlign"
  ];
  const typographySpecified = authoredMask(style, typographyNames) | (node.props.lang != null ? 1 << 3 : 0);
  const interactionSpecified = authoredMask(style, ["visibility", "pointerEvents", "cursor", "willChange"]);
  const letterSpacing = styleLength(style.letterSpacing, { normal: true, negative: true });
  const wordSpacing = styleLength(style.wordSpacing, { normal: true, negative: true });
  const textIndent = styleLength(style.textIndent, { negative: true });
  const textStrokeWidth = styleLength(style.textStrokeWidth);
  const textUnderlineOffset = styleLength(style.textUnderlineOffset, { negative: true });
  const textDecorationThickness = styleLength(style.textDecorationThickness);
  const outlineWidth = styleLength(style.outlineWidth);
  const outlineOffset = styleLength(style.outlineOffset, { negative: true });
  const opacity=opacityValue(style.opacity);
  const isolation=style.isolation == null ? "auto" : String(style.isolation).trim().toLowerCase();
  if(!["auto","isolate"].includes(isolation)) throw Error("Invalid isolation: "+style.isolation);
  const marginBox = boxSides(style.margin, { auto: true, negative: true });
  const paddingBox = boxSides(style.padding, {});
  const marginSide = (key, side) => style[key] == null ? marginBox?.[side] : spacingValue(style[key], { auto: true, negative: true });
  const paddingSide = (key, side) => style[key] == null ? paddingBox?.[side] : spacingValue(style[key]);
  const margin = { t: marginSide("marginTop", "t"), r: marginSide("marginRight", "r"), b: marginSide("marginBottom", "b"), l: marginSide("marginLeft", "l") };
  const size = value => value == null ? null : spacingValue(value, { auto: true });
  const border = value => value == null ? null : spacingValue(value);
  const lengths = {};
  function emitLength(key, value) {
    lengths[key] = typeof value === "number" ? value : null;
    lengths[key + "Css"] = typeof value === "string" ? value : null;
  }
  for (const key of ["width", "height", "minWidth", "minHeight", "maxWidth", "maxHeight", "cx", "cy", "r", "rx", "ry", "x", "y", "shapeMargin", "strokeWidth"]) emitLength(key, size(style[key]));
  const scrollMarginBox = boxSides(style.scrollMargin, { auto: true, negative: true });
  const scrollPaddingBox = boxSides(style.scrollPadding, { auto: true });
  const scrollMarginSide = (key, side) => style[key] == null ? scrollMarginBox?.[side] : spacingValue(style[key], { auto: true, negative: true });
  const scrollPaddingSide = (key, side) => style[key] == null ? scrollPaddingBox?.[side] : spacingValue(style[key], { auto: true });
  for (const [key, side] of [["Top", "t"], ["Right", "r"], ["Bottom", "b"], ["Left", "l"]]) {
    emitLength("padding" + key, paddingSide("padding" + key, side));
    emitLength("margin" + key, margin[side] === "auto" ? null : margin[side]);
    emitLength("border" + key + "Width", border(style["border" + key + "Width"]));
    emitLength("scrollMargin" + key, scrollMarginSide("scrollMargin" + key, side));
    emitLength("scrollPadding" + key, scrollPaddingSide("scrollPadding" + key, side));
  }
  for (const side of ["top", "right", "bottom", "left"]) {
    const raw = style[side] == null ? null : spacingValue(style[side], { auto: true, negative: true });
    if (raw === "auto") {
      lengths[side] = null;
      lengths[side + "Css"] = "auto";
      lengths[side + "Auto"] = true;
    } else {
      emitLength(side, raw);
      lengths[side + "Auto"] = false;
    }
  }
  const flex = flexValues(style);
  const rawBasis = flex.basis;
  let basis = rawBasis;
  if (typeof rawBasis === "number") {
    if (!Number.isFinite(rawBasis) || rawBasis < 0) throw Error(`Invalid flex basis: ${rawBasis}`);
  } else if (typeof rawBasis === "string") {
    const trimmed = rawBasis.trim();
    if (trimmed === "auto" || trimmed === "content" || trimmed === "min-content" || trimmed === "max-content" || trimmed === "fit-content") {
      basis = trimmed;
    } else {
      basis = spacingValue(trimmed);
    }
  }

  const parseGap = v => {
    if (v == null) return null;
    if (typeof v === "number") {
      if (!Number.isFinite(v) || v < 0) throw Error(`Invalid gap: ${v}`);
      return { num: v, css: null };
    }
    if (typeof v === "string") {
      const trimmed = v.trim();
      const num = Number(trimmed);
      if (Number.isFinite(num) && num >= 0) return { num, css: null };
      return { num: null, css: trimmed };
    }
    throw Error(`Invalid gap: ${v}`);
  };

  const gapParsed = parseGap(style.gap);
  const rowGapParsed = parseGap(style.rowGap);
  const colGapParsed = parseGap(style.columnGap);
  if (style.aspectRatio != null && (typeof style.aspectRatio !== "number" || !Number.isFinite(style.aspectRatio) || style.aspectRatio <= 0)) throw Error(`Invalid aspect ratio: ${style.aspectRatio}`);
  if (style.fontSize != null && !(typeof style.fontSize === "string" && style.fontSize.trim()) && (typeof style.fontSize !== "number" || !Number.isFinite(style.fontSize) || style.fontSize <= 0)) throw Error(`Invalid font size: ${style.fontSize}`);
  const willChange = style.willChange == null ? "auto" : String(style.willChange).trim();
  const wordBreak = style.wordBreak ?? inherited.wordBreak ?? "normal";
  let whiteSpaceCollapse = style.whiteSpaceCollapse ?? inherited.whiteSpaceCollapse;
  if (!whiteSpaceCollapse) {
    if (style.whiteSpace === "pre" || style.whiteSpace === "pre-wrap") whiteSpaceCollapse = "preserve";
    else if (style.whiteSpace === "pre-line") whiteSpaceCollapse = "preserve-breaks";
    else if (style.whiteSpace === "break-spaces") whiteSpaceCollapse = "break-spaces";
    else whiteSpaceCollapse = "collapse";
  }
  let verticalAlign = "baseline";
  let verticalAlignCss = null;
  let verticalAlignOffset = null;
  if (style.verticalAlign != null) {
    if (typeof style.verticalAlign === "number") {
      verticalAlignOffset = style.verticalAlign;
      verticalAlign = "offset";
    } else if (typeof style.verticalAlign === "string") {
      const vTrim = style.verticalAlign.trim();
      if (["baseline", "sub", "super", "top", "text-top", "middle", "bottom", "text-bottom"].includes(vTrim)) {
        verticalAlign = vTrim;
      } else {
        verticalAlignCss = vTrim;
      }
    }
  }
  const registeredFace = fontFaceRegistry.get((style.fontFamily ?? inherited.fontFamily ?? "").toLowerCase());
  const defaultFontFeatureSettings = registeredFace?.fontFeatureSettings ?? "normal";
  const currentZoom = zoomValue(style.zoom, inherited.zoom ?? 1.0);
  const textStyle = {
    color: typeof style.color === "string" ? style.color : (inherited.color || ""),
    fontSize: typeof style.fontSize === "number" ? style.fontSize : (inherited.fontSize || 0),
    fontSizeCss: typeof style.fontSize === "string" ? style.fontSize.trim() : null,
    fontFamily: style.fontFamily ?? inherited.fontFamily ?? "system-ui",
    fontFeatureSettings: style.fontFeatureSettings ?? inherited.fontFeatureSettings ?? defaultFontFeatureSettings,
    zoom: currentZoom,
    fontWeight: typeof style.fontWeight==="number" ? style.fontWeight : (inherited.fontWeight ?? 400),
    fontWeightCss: typeof style.fontWeight==="string" ? style.fontWeight : null,
    fontStyle: style.fontStyle ?? inherited.fontStyle ?? "normal",
    language: node.props.lang ?? style.language ?? inherited.language ?? "",
    textTransform: style.textTransform ?? inherited.textTransform ?? "none",
    textAlignLast: style.textAlignLast ?? inherited.textAlignLast ?? "auto",
    wordBreak,
    whiteSpaceCollapse,
    verticalAlign,
    verticalAlignCss,
    verticalAlignOffset,
    textOrientation: style.textOrientation ?? inherited.textOrientation ?? "mixed",
    textShadow: typeof style.textShadow === "string" ? style.textShadow : (inherited.textShadow || ""),
    textFillColor: typeof style.textFillColor === "string" ? style.textFillColor : (inherited.textFillColor || ""),
    textStrokeColor: typeof style.textStrokeColor === "string" ? style.textStrokeColor : (inherited.textStrokeColor || ""),
    textUnderlinePosition: style.textUnderlinePosition ?? inherited.textUnderlinePosition ?? "auto",
    textDecoration: typeof style.textDecoration === "string" ? style.textDecoration : (inherited.textDecoration || "none"),
    textDecorationLine: typeof style.textDecorationLine === "string" ? style.textDecorationLine : (inherited.textDecorationLine || "none"),
    textDecorationColor: typeof style.textDecorationColor === "string" ? style.textDecorationColor : (inherited.textDecorationColor || ""),
    textWrap: style.textWrap ?? inherited.textWrap ?? "wrap",
    textWrapMode: style.textWrapMode ?? inherited.textWrapMode ?? "wrap",
    textWrapStyle: style.textWrapStyle ?? inherited.textWrapStyle ?? "auto",
    rubyAlign: style.rubyAlign ?? inherited.rubyAlign ?? "space-around",
    cursor: style.cursor ?? inherited.cursor ?? "auto",
    visibility: style.visibility ?? inherited.visibility ?? "visible",
    contentVisibility: style.contentVisibility ?? inherited.contentVisibility ?? "visible",
    pointerEvents: style.pointerEvents ?? inherited.pointerEvents ?? "auto",
    quotes: style.quotes ?? inherited.quotes ?? "auto",
    whiteSpace: style.whiteSpace ?? inherited.whiteSpace ?? "normal",
    textAlign: style.textAlign ?? inherited.textAlign ?? "left",
    overflowWrap: style.overflowWrap ?? inherited.overflowWrap ?? "normal",
    paintOrder: style.paintOrder ?? inherited.paintOrder ?? "normal",
    lineHeight: style.lineHeight ?? inherited.lineHeight,
    writingMode: style.writingMode ?? inherited.writingMode ?? "horizontal-tb",
    direction: style.direction ?? inherited.direction ?? "ltr",
    textAutospace: style.textAutospace ?? inherited.textAutospace ?? "normal",
    mathShift: style.mathShift ?? inherited.mathShift ?? "normal",
    printColorAdjust: style.printColorAdjust ?? inherited.printColorAdjust ?? "economy",
    scrollbarColor: style.scrollbarColor ?? inherited.scrollbarColor ?? "auto",
    rootFontSize: inherited.rootFontSize ?? (typeof style.fontSize === "number" ? style.fontSize : 20),
    rootLineHeight: inherited.rootLineHeight ?? (typeof style.lineHeight === "number" ? style.lineHeight : 24),
  };
  const containIntrinsicWidth = styleLength(style.containIntrinsicWidth ?? style.containIntrinsicSize);
  const containIntrinsicHeight = styleLength(style.containIntrinsicHeight ?? style.containIntrinsicSize);
  let columns = [];
  let gridTemplateColumnsCss = null;
  if (displayOf(node, style) === "grid" && style.gridTemplateColumns != null) {
    if (typeof style.gridTemplateColumns === "string") {
      gridTemplateColumnsCss = style.gridTemplateColumns.trim();
      try {
        const parts = gridTemplateColumnsCss.split(/\s+/);
        const parsed = parts.map(track => {
          if (/^\d+(?:\.\d+)?fr$/.test(track)) return -Number(track.slice(0, -2));
          if (/^\d+(?:\.\d+)?px$/.test(track)) return Number(track.slice(0, -2));
          const num = Number(track);
          if (Number.isFinite(num)) return num;
          throw Error("complex track");
        });
        columns = parsed;
      } catch {
        columns = [];
      }
    } else if (Array.isArray(style.gridTemplateColumns)) {
      columns = style.gridTemplateColumns.map(track => {
        if (typeof track === "number") return track;
        if (/^\d+(?:\.\d+)?fr$/.test(track)) return -Number(track.slice(0, -2));
        if (/^\d+(?:\.\d+)?px$/.test(track)) return Number(track.slice(0, -2));
        return Number(track) || 0;
      });
    }
  }
  const isButton = node.type === "button";
  const isInput = node.type === "input";
  const isSelect = node.type === "select";
  const isOption = node.type === "option";
  const isSummary = node.type === "summary";
  const clickable = !node.props.disabled && (
    typeof node.props.onClick === "function" ||
    isButton ||
    isInput ||
    isSelect ||
    isSummary ||
    (isOption && (!node.parent || !node.parent.props.disabled))
  );
  const tabIndex = typeof node.props.tabIndex === "number" ? Math.trunc(node.props.tabIndex) : null;
  const focusable = Boolean(node.props.focusable) || (tabIndex != null) || (!node.props.disabled && (isInput || isButton || isSelect));

  let overflowX = typeof style.overflowX === "string" ? style.overflowX : "";
  let overflowY = typeof style.overflowY === "string" ? style.overflowY : "";
  let overflow = typeof style.overflow === "string" ? style.overflow : "visible";
  if (typeof style.overflow === "string") {
    const parts = splitSpacing(style.overflow.trim());
    if (parts.length === 2) {
      if (!overflowX) overflowX = parts[0];
      if (!overflowY) overflowY = parts[1];
    }
  }

  let lineHeight = null;
  let lineHeightCss = null;
  const lineHeightValue = style.lineHeight ?? inherited.lineHeight;
  if (typeof lineHeightValue === "number") {
    lineHeight = lineHeightValue;
  } else if (typeof lineHeightValue === "string") {
    const trimmed = lineHeightValue.trim();
    const num = Number(trimmed);
    if (Number.isFinite(num) && num > 0 && !/[a-z%]/i.test(trimmed)) {
      lineHeight = num * (textStyle.fontSize || 20);
    } else if (trimmed && trimmed !== "normal") {
      lineHeightCss = trimmed;
    }
  }

  const isSelected = isSelectedOption(node);
  const defaultSelectStyle = node.type === "select" ? {
    backgroundColor: style.backgroundColor || "#2d2d2d",
    borderColor: style.borderColor || "#4f4f4f",
    borderTopWidth: lengths.borderTopWidth != null ? lengths.borderTopWidth : 1,
    borderRightWidth: lengths.borderRightWidth != null ? lengths.borderRightWidth : 1,
    borderBottomWidth: lengths.borderBottomWidth != null ? lengths.borderBottomWidth : 1,
    borderLeftWidth: lengths.borderLeftWidth != null ? lengths.borderLeftWidth : 1,
    borderRadius: typeof style.borderRadius === "number" ? style.borderRadius : 4,
    paddingTop: lengths.paddingTop != null ? lengths.paddingTop : 6,
    paddingBottom: lengths.paddingBottom != null ? lengths.paddingBottom : 6,
    paddingLeft: lengths.paddingLeft != null ? lengths.paddingLeft : 10,
    paddingRight: lengths.paddingRight != null ? lengths.paddingRight : 10,
  } : {};
  const defaultOptionStyle = node.type === "option" ? {
    backgroundColor: style.backgroundColor || (isSelected ? "#2563eb" : "#1e1e1e"),
    color: style.color || "#ffffff",
    paddingTop: lengths.paddingTop != null ? lengths.paddingTop : 6,
    paddingBottom: lengths.paddingBottom != null ? lengths.paddingBottom : 6,
    paddingLeft: lengths.paddingLeft != null ? lengths.paddingLeft : 10,
    paddingRight: lengths.paddingRight != null ? lengths.paddingRight : 10,
  } : {};
  return {
    id: node.id,
    type: node.type,
    text: node.type === "select" ? getSelectedLabel(node) :
          node.type === "option" ? getOptionLabel(node) :
          node.type === "q" ? qText : node.text,
    clickable,
    focusable,
    readOnly: isReadOnly(node),
    readWrite: isReadWrite(node),
    popoverOpen: isPopoverOpen(node),
    tabIndex,
    hovered: Boolean(node._isHovered),
    active: Boolean(node._isActive),
    focused: Boolean(node._isFocused),
    value: node.type === "input" ? String(node.props.value ?? "") :
           node.type === "select" ? getSelectValue(node) :
           node.type === "option" ? getOptionValue(node) : "",
    placeholder,
    placeholderShown: isPlaceholder,
    selected: node.type === "option" ? isSelectedOption(node) : undefined,
    open: node.type === "select" ? Boolean(node._open) : undefined,
    style: {
      direction: style.direction ?? "ltr",
      writingMode: style.writingMode,
      display: displayOf(node, style),
      flexDirection: flexDirectionOf(node, style),
      flexWrap: typeof style.flexWrap === "string" ? style.flexWrap : "nowrap",
      justifyContent: typeof style.justifyContent === "string" ? style.justifyContent : "normal",
      alignItems: typeof style.alignItems === "string" ? style.alignItems : "stretch",
      alignContent: typeof style.alignContent === "string" ? style.alignContent : "stretch",
      alignSelf: typeof style.alignSelf === "string" ? style.alignSelf : "auto",
      flexGrow: flex.grow,
      flexShrink: flex.shrink,
      flexBasis: typeof basis === "number" ? basis : null,
      flexBasisCss: typeof basis === "string" && basis !== "auto" && basis !== "content" ? basis : null,
      flexBasisContent: basis === "content",
      order: typeof style.order === "number" ? style.order : 0,
      ...lengths,
      topAuto: Boolean(lengths.topAuto),
      rightAuto: Boolean(lengths.rightAuto),
      bottomAuto: Boolean(lengths.bottomAuto),
      leftAuto: Boolean(lengths.leftAuto),
      overflowWrap: style.overflowWrap ?? inherited.overflowWrap ?? "normal",
      paintOrder: typeof style.paintOrder === "string" ? style.paintOrder : (inherited.paintOrder || "normal"),
      clipPath: typeof style.clipPath === "string" ? style.clipPath : "",
      clipPathCss: typeof style.clipPath === "string" ? style.clipPath : null,
      offsetPath: typeof style.offsetPath === "string" ? style.offsetPath : "",
      offsetPathCss: typeof style.offsetPath === "string" ? style.offsetPath : null,
      offsetDistance: typeof style.offsetDistance === "number" ? style.offsetDistance : (parseFloat(style.offsetDistance) || 0),
      offsetDistanceCss: typeof style.offsetDistance === "string" ? style.offsetDistance : null,
      offsetRotate: typeof style.offsetRotate === "string" ? style.offsetRotate : "auto",
      page: typeof style.page === "string" ? style.page : "auto",
      breakBefore: typeof style.breakBefore === "string" ? style.breakBefore : "auto",
      breakAfter: typeof style.breakAfter === "string" ? style.breakAfter : "auto",
      breakInside: typeof style.breakInside === "string" ? style.breakInside : "auto",
      placeholderColor: typeof style.placeholderColor === "string" ? style.placeholderColor : (style["::placeholder"]?.color ?? style[":placeholder"]?.color ?? style.placeholderStyle?.color ?? ""),
      placeholderOpacity: typeof style.placeholderOpacity === "number" ? style.placeholderOpacity : (style["::placeholder"]?.opacity ?? style[":placeholder"]?.opacity ?? style.placeholderStyle?.opacity ?? 0.6),
      aspectRatio: style.aspectRatio ?? null,
      marginTopAuto: margin.t === "auto", marginRightAuto: margin.r === "auto",
      marginBottomAuto: margin.b === "auto", marginLeftAuto: margin.l === "auto",
      gap: gapParsed?.num ?? 0,
      rowGap: rowGapParsed?.num ?? null,
      columnGap: colGapParsed?.num ?? null,
      rowGapCss: rowGapParsed?.css ?? null,
      columnGapCss: colGapParsed?.css ?? null,
      columns,
      backgroundColor: typeof style.backgroundColor === "string" ? style.backgroundColor : "",
      borderColor: typeof style.borderColor === "string" ? style.borderColor : "",
      borderTopColor: typeof style.borderTopColor === "string" ? style.borderTopColor : "",
      borderRightColor: typeof style.borderRightColor === "string" ? style.borderRightColor : "",
      borderBottomColor: typeof style.borderBottomColor === "string" ? style.borderBottomColor : "",
      borderLeftColor: typeof style.borderLeftColor === "string" ? style.borderLeftColor : "",
      borderTopStyle: style.borderTopStyle ?? 'solid',
      borderRightStyle: style.borderRightStyle ?? 'solid',
      borderBottomStyle: style.borderBottomStyle ?? 'solid',
      borderLeftStyle: style.borderLeftStyle ?? 'solid',
      typographySpecified,
      interactionSpecified,
      letterSpacing:letterSpacing.number, letterSpacingCss:letterSpacing.css,
      wordSpacing:wordSpacing.number, wordSpacingCss:wordSpacing.css,
      textIndent:textIndent.number, textIndentCss:textIndent.css,
      textStrokeWidth:textStrokeWidth.number ?? 0, textStrokeWidthCss:textStrokeWidth.css,
      textUnderlineOffset:textUnderlineOffset.number, textUnderlineOffsetCss:textUnderlineOffset.css,
      textDecorationThickness:textDecorationThickness.number, textDecorationThicknessCss:textDecorationThickness.css,
      tabSize:typeof style.tabSize==="number" ? style.tabSize : 8,
      tabSizeCss:typeof style.tabSize==="string" ? style.tabSize : null,
      textOverflow:style.textOverflow ?? "clip",
      borderRadiusCss:radiusCss(style.borderRadius),
      borderTopLeftRadiusCss:radiusCss(style.borderTopLeftRadius),
      borderTopRightRadiusCss:radiusCss(style.borderTopRightRadius),
      borderBottomRightRadiusCss:radiusCss(style.borderBottomRightRadius),
      borderBottomLeftRadiusCss:radiusCss(style.borderBottomLeftRadius),
      borderRadius: typeof style.borderRadius === "number" ? style.borderRadius : 0,
      borderTopLeftRadius: typeof style.borderTopLeftRadius === "number" ? style.borderTopLeftRadius : 0,
      borderTopRightRadius: typeof style.borderTopRightRadius === "number" ? style.borderTopRightRadius : 0,
      borderBottomRightRadius: typeof style.borderBottomRightRadius === "number" ? style.borderBottomRightRadius : 0,
      borderBottomLeftRadius: typeof style.borderBottomLeftRadius === "number" ? style.borderBottomLeftRadius : 0,
      boxSizing: typeof style.boxSizing === "string" ? style.boxSizing : "content-box",
      overflow,
      overflowX,
      overflowY,
      scrollbarGutter: typeof style.scrollbarGutter === "string" ? style.scrollbarGutter : "auto",
      scrollbarWidth: typeof style.scrollbarWidth === "string" ? style.scrollbarWidth : "auto",
      rubyPosition: typeof style.rubyPosition === "string" ? style.rubyPosition : (inherited.rubyPosition || "over"),
      scrollBehavior: typeof style.scrollBehavior === "string" ? style.scrollBehavior : "auto",
      scrollSnapType: typeof style.scrollSnapType === "string" ? style.scrollSnapType : "none",
      scrollSnapAlign: typeof style.scrollSnapAlign === "string" ? style.scrollSnapAlign : "none",
      scrollSnapStop: typeof style.scrollSnapStop === "string" ? style.scrollSnapStop : "normal",
      overflowBlock: typeof style.overflowBlock === "string" ? style.overflowBlock : "",
      overflowInline: typeof style.overflowInline === "string" ? style.overflowInline : "",
      contentVisibility: textStyle.contentVisibility,
      containIntrinsicWidth: containIntrinsicWidth.number,
      containIntrinsicWidthCss: containIntrinsicWidth.css,
      containIntrinsicHeight: containIntrinsicHeight.number,
      containIntrinsicHeightCss: containIntrinsicHeight.css,
      zoom: currentZoom,
      activeViewTransition: isViewTransitionActive(),
      scrollbarGutter: typeof style.scrollbarGutter === "string" ? style.scrollbarGutter : "",
      scrollbarWidth: typeof style.scrollbarWidth === "string" ? style.scrollbarWidth : "",
      scrollbarColor: typeof style.scrollbarColor === "string" ? style.scrollbarColor : (inherited.scrollbarColor ?? "auto"),
      textAutospace: typeof style.textAutospace === "string" ? style.textAutospace : (inherited.textAutospace ?? "normal"),
      textDecoration: typeof style.textDecoration === "string" ? style.textDecoration : "",
      textDecorationLine: typeof style.textDecorationLine === "string" ? style.textDecorationLine : "none",
      textDecorationStyle: typeof style.textDecorationStyle === "string" ? style.textDecorationStyle : "solid",
      textDecorationColor: typeof style.textDecorationColor === "string" ? style.textDecorationColor : "",
      mathShift: typeof style.mathShift === "string" ? style.mathShift : (inherited.mathShift ?? "normal"),
      printColorAdjust: typeof style.printColorAdjust === "string" ? style.printColorAdjust : (inherited.printColorAdjust ?? "economy"),
      viewTransitionName: typeof style.viewTransitionName === "string" ? style.viewTransitionName : "none",
      viewTransitionClass: typeof style.viewTransitionClass === "string" ? style.viewTransitionClass : "none",
      whiteSpace: typeof style.whiteSpace === "string" ? style.whiteSpace : (inherited.whiteSpace || "normal"),
      textAlign: typeof style.textAlign === "string" ? style.textAlign : (inherited.textAlign || "left"),
      lineHeight,
      lineHeightCss: lineHeightCss ?? "",
      outlineWidth:outlineWidth.number ?? 0, outlineWidthCss:outlineWidth.css ?? (typeof style.outlineWidth==="number" ? style.outlineWidth+"px" : null),
      outlineOffset:outlineOffset.number ?? 0, outlineOffsetCss:outlineOffset.css,
      outlineStyle:style.outlineStyle ?? "none",
      outlineColor: typeof style.outlineColor === "string" ? style.outlineColor : "",
      boxShadow: typeof style.boxShadow === "string" ? style.boxShadow : "",
      quotes: style.quotes ?? inherited.quotes ?? "auto",
      clipPath: typeof style.clipPath === "string" ? style.clipPath.trim() : "",
      position: typeof style.position === "string" ? style.position.trim().toLowerCase() : (isPopoverOpen(node) ? "fixed" : "static"),
      positionInline: typeof style.display === 'string' && style.display.startsWith('inline'),
      zIndex: zIndexValue(style.zIndex) ?? (isPopoverOpen(node) ? 1000000 : null),
      gridTemplateColumnsCss: gridTemplateColumnsCss,
      gridTemplateRowsCss: typeof style.gridTemplateRows === "string" ? style.gridTemplateRows : (Array.isArray(style.gridTemplateRows) ? style.gridTemplateRows.join(" ") : null),
      gridAutoFlow: typeof style.gridAutoFlow === "string" ? style.gridAutoFlow : "row",
      gridTemplateAreas: typeof style.gridTemplateAreas === "string" ? style.gridTemplateAreas : "",
      gridColumn: style.gridColumn != null ? String(style.gridColumn) : (style.gridColumnStart != null || style.gridColumnEnd != null ? `${style.gridColumnStart ?? "auto"} / ${style.gridColumnEnd ?? "auto"}` : ""),
      gridRow: style.gridRow != null ? String(style.gridRow) : (style.gridRowStart != null || style.gridRowEnd != null ? `${style.gridRowStart ?? "auto"} / ${style.gridRowEnd ?? "auto"}` : ""),
      gridArea: typeof style.gridArea === "string" ? style.gridArea : "",
      gridColumnStart: typeof style.gridColumnStart === "number" ? Math.trunc(style.gridColumnStart) : null,
      gridColumnEnd: typeof style.gridColumnEnd === "number" ? Math.trunc(style.gridColumnEnd) : null,
      gridRowStart: typeof style.gridRowStart === "number" ? Math.trunc(style.gridRowStart) : null,
      gridRowEnd: typeof style.gridRowEnd === "number" ? Math.trunc(style.gridRowEnd) : null,
      justifyItems: typeof style.justifyItems === "string" ? style.justifyItems : "stretch",
      justifySelf: typeof style.justifySelf === "string" ? style.justifySelf : "auto",
      backgroundGradient: typeof style.backgroundGradient === "string" ? style.backgroundGradient : (typeof style.backgroundImage === "string" && /-gradient\(/i.test(style.backgroundImage) ? style.backgroundImage : ""),
      opacity: opacity.number,
      opacityCss: opacity.css,
      isolation,
      objectFit,
      objectPosition,
      columnCount,
      columnCountCss,
      columnWidth,
      columnWidthCss,
      columnsCss: typeof style.columns === "string" ? style.columns : null,
      columnRuleWidth: colRuleWidth.number ?? (style.columnRuleWidth === "thin" ? 1 : style.columnRuleWidth === "thick" ? 5 : (style.columnRuleStyle && style.columnRuleStyle !== "none" ? 3 : 0)),
      columnRuleWidthCss: colRuleWidth.css ?? (typeof style.columnRuleWidth === "string" ? style.columnRuleWidth : null),
      columnRuleStyle,
      columnRuleColor,
      willChange,
      transform: typeof style.transform === "string" ? style.transform : "",
      transformOrigin: typeof style.transformOrigin === "string" ? style.transformOrigin : "50% 50%",
      transition: typeof style.transition === "string" ? style.transition : "",
      transitionProperty: typeof style.transitionProperty === "string" ? style.transitionProperty : "all",
      transitionDuration: typeof style.transitionDuration === "number" ? style.transitionDuration : (typeof style.transitionDuration === "string" ? (parseFloat(style.transitionDuration) * (style.transitionDuration.endsWith("ms") ? 0.001 : 1.0) || 0) : 0),
      transitionTimingFunction: typeof style.transitionTimingFunction === "string" ? style.transitionTimingFunction : "ease",
      transitionDelay: typeof style.transitionDelay === "number" ? style.transitionDelay : (typeof style.transitionDelay === "string" ? (parseFloat(style.transitionDelay) * (style.transitionDelay.endsWith("ms") ? 0.001 : 1.0) || 0) : 0),
      transitionBehavior: typeof style.transitionBehavior === "string" ? style.transitionBehavior : "normal",
      transformBox: typeof style.transformBox === "string" ? style.transformBox : "border-box",
      backfaceVisibility: typeof style.backfaceVisibility === "string" ? style.backfaceVisibility : "visible",
      transformStyle: typeof style.transformStyle === "string" ? style.transformStyle : "flat",
      perspective: typeof style.perspective === "number" ? style.perspective : null,
      perspectiveCss: typeof style.perspective === "string" ? style.perspective : (typeof style.perspective === "number" ? String(style.perspective) + "px" : null),
      perspectiveOrigin: typeof style.perspectiveOrigin === "string" ? style.perspectiveOrigin : "50% 50%",
      touchAction: typeof style.touchAction === "string" ? style.touchAction : "auto",


      textDecorationSkipInk: style.textDecorationSkipInk ?? inherited.textDecorationSkipInk ?? "auto",
      textEmphasisStyle: style.textEmphasisStyle ?? inherited.textEmphasisStyle ?? "none",
      textEmphasisColor: style.textEmphasisColor ?? inherited.textEmphasisColor ?? "",
      textEmphasisPosition: style.textEmphasisPosition ?? inherited.textEmphasisPosition ?? "over right",
      textCombineUpright: style.textCombineUpright ?? inherited.textCombineUpright ?? "none",
      borderCollapse: style.borderCollapse ?? inherited.borderCollapse ?? "separate",
      borderSpacing: borderSpacingX,
      borderSpacingX,
      borderSpacingY,
      borderSpacingCss,
      captionSide: style.captionSide ?? inherited.captionSide ?? "top",
      emptyCells: style.emptyCells ?? inherited.emptyCells ?? "show",
      tableLayout: style.tableLayout ?? inherited.tableLayout ?? "auto",
      colorInterpolationFilters: style.colorInterpolationFilters ?? inherited.colorInterpolationFilters ?? "auto",
      floodColor: style.floodColor ?? inherited.floodColor ?? "",
      floodOpacity: floodOp.number,
      floodOpacityCss: floodOp.css,
      lightingColor: style.lightingColor ?? inherited.lightingColor ?? "",
      isTarget,
      isTargetText,
      targetTextColor: style.targetTextColor ?? "",
      targetTextBackgroundColor: style.targetTextBackgroundColor ?? "",
      shapeOutside: typeof style.shapeOutside === "string" ? style.shapeOutside : "",
      shapeMargin: lengths.shapeMargin ?? 0,
      shapeMarginCss: lengths.shapeMarginCss,
      shapeImageThreshold: typeof style.shapeImageThreshold === "number" ? style.shapeImageThreshold : 0,
      clipRule: typeof style.clipRule === "string" ? style.clipRule : "nonzero",
      colorInterpolation: typeof style.colorInterpolation === "string" ? style.colorInterpolation : "sRGB",
      shapeRendering: typeof style.shapeRendering === "string" ? style.shapeRendering : "auto",
      textRendering: typeof style.textRendering === "string" ? style.textRendering : "auto",
      vectorEffect: typeof style.vectorEffect === "string" ? style.vectorEffect : "none",
      cx: lengths.cx,
      cxCss: lengths.cxCss,
      cy: lengths.cy,
      cyCss: lengths.cyCss,
      r: lengths.r,
      rCss: lengths.rCss,
      rx: lengths.rx,
      rxCss: lengths.rxCss,
      ry: lengths.ry,
      ryCss: lengths.ryCss,
      x: lengths.x,
      xCss: lengths.xCss,
      y: lengths.y,
      yCss: lengths.yCss,
      fill: typeof style.fill === "string" ? style.fill : "",
      stroke: typeof style.stroke === "string" ? style.stroke : "",
      strokeWidth: lengths.strokeWidth ?? 1.0,
      strokeWidthCss: lengths.strokeWidthCss,
      float: typeof style.float === "string" ? style.float : "none",
      clear: typeof style.clear === "string" ? style.clear : "none",
      startingStyle: style.startingStyle ? JSON.stringify(style.startingStyle) : (style["@starting-style"] ? JSON.stringify(style["@starting-style"]) : null),
      ...textStyle,
      lineHeight,
      lineHeightCss,
      ...defaultSelectStyle,
      ...defaultOptionStyle,
    },
    children: (() => {
      let childrenNodes = (node.type === "slot" && node._slottedChildren ? node._slottedChildren : node.children) || [];
      if (node.type === "details") {
        const summaryChild = childrenNodes.find(c => c.type === "summary");
        const contentChildren = childrenNodes.filter(c => c.type !== "summary");
        const isOpen = Boolean(node.props.open);
        const contentBox = {
          id: node.id + 1000000,
          type: "details-content",
          text: "",
          children: contentChildren,
          parent: node,
          props: {
            style: {
              display: isOpen ? "block" : "none",
              ...(style.detailsContent || {}),
              ...(node.props.detailsContentStyle || {}),
            }
          }
        };
        childrenNodes = summaryChild ? [summaryChild, contentBox] : [contentBox];
      }
      return childrenNodes.map(child => snapshot(child, textStyle, currentVars, nextQuoteDepth));
    })(),
  };
}

export function getOptions(selectNode) {
  const options = [];
  function collect(n) {
    if (!n) return;
    if (n.type === "option") {
      options.push(n);
      return;
    }
    if (["optgroup", "div", "row", "column"].includes(n.type)) {
      for (const child of n.children || []) collect(child);
    }
  }
  for (const child of selectNode.children || []) {
    collect(child);
  }
  return options;
}

export function getOptionLabel(optNode) {
  let label = "";
  function walk(n) {
    if (!n) return;
    if (n.type === "text") label += n.text ?? "";
    for (const child of n.children || []) walk(child);
  }
  walk(optNode);
  return label.trim() || String(optNode.props.value ?? "");
}

export function getOptionValue(optNode) {
  if (optNode.props.value !== undefined) return String(optNode.props.value);
  return getOptionLabel(optNode);
}

export function getSelectValue(selectNode) {
  if (selectNode.props.value !== undefined && selectNode.props.value !== null) {
    return String(selectNode.props.value);
  }
  if (selectNode._value !== undefined && selectNode._value !== null) {
    return String(selectNode._value);
  }
  const options = getOptions(selectNode);
  const selectedOpt = options.find(o => o.props.selected && !o.props.disabled);
  if (selectedOpt) return getOptionValue(selectedOpt);
  const firstEnabled = options.find(o => !o.props.disabled);
  return firstEnabled ? getOptionValue(firstEnabled) : "";
}

export function getSelectedLabel(selectNode) {
  const val = getSelectValue(selectNode);
  const options = getOptions(selectNode);
  const opt = options.find(o => getOptionValue(o) === val);
  if (opt) return getOptionLabel(opt);
  return val;
}

export function isSelectedOption(optNode) {
  if (optNode.props.selected) return true;
  if (optNode.parent && optNode.parent.type === "select") {
    return getSelectValue(optNode.parent) === getOptionValue(optNode);
  }
  return false;
}

export function findId(node, id) {
  if (!node) return null;
  if (node.id === id) return node;
  for (const child of node.children || []) {
    const match = findId(child, id);
    if (match) return match;
  }
  return null;
}

export function closeAllSelects(exceptNode = null) {
  function walk(n) {
    if (!n) return;
    if (n.type === "select" && n !== exceptNode) {
      n._open = false;
    }
    for (const child of n.children || []) walk(child);
  }
  walk(root);
}

export function dispatch(target, name, type, value) {
  let stopped = false;
  const event = {
    type,
    target: { id: target.id, value: value ?? target.props.value },
    currentTarget: undefined,
    stopPropagation() { stopped = true; },
  };
  for (let current = target; current; current = current.parent) {
    event.currentTarget = { id: current.id, value: current.props.value };
    if (typeof current.props[name] === "function") current.props[name](event);
    if (stopped) break;
  }
}

export function dispatchSelectChange(selectNode, newValue) {
  selectNode._userInteracted = true;
  selectNode.props.value = newValue;
  selectNode._value = newValue;
  dispatch(selectNode, "onInput", "input", newValue);
  dispatch(selectNode, "onChange", "change", newValue);
}

export function dispatchClick(id) {
  const target = findId(root, id);
  if (!target) {
    closeAllSelects();
    closeAllAutoPopovers();
    return;
  }
  if (target.props.disabled) return;
  target._userInteracted = true;

  closeAllAutoPopovers(target);
  const popoverTargetId = target.props?.popoverTarget ?? target.props?.popovertarget;
  if (popoverTargetId) {
    const targetPopover = findId(root, popoverTargetId) || querySelector(root, "#" + popoverTargetId);
    if (targetPopover && targetPopover.props?.popover) {
      const action = String(target.props?.popoverTargetAction ?? target.props?.popovertargetaction ?? "toggle").toLowerCase();
      if (action === "show") {
        showPopover(targetPopover);
      } else if (action === "hide") {
        hidePopover(targetPopover);
      } else {
        togglePopover(targetPopover);
      }
    }
  }


  if (target.type === "select") {
    closeAllSelects(target);
    target._open = !target._open;
    if (target._open) {
      target._initialValue = getSelectValue(target);
      const options = getOptions(target).filter(o => !o.props.disabled);
      target._highlightedIndex = options.findIndex(o => getOptionValue(o) === target._initialValue);
    }
    dispatch(target, "onClick", "click");
    return;
  }

  if (target.type === "option") {
    let selectNode = target.parent;
    while (selectNode && selectNode.type !== "select") {
      selectNode = selectNode.parent;
    }
    if (selectNode && !selectNode.props.disabled) {
      selectNode._userInteracted = true;
      const newValue = getOptionValue(target);
      selectNode._open = false;
      dispatch(target, "onClick", "click");
      dispatchSelectChange(selectNode, newValue);
    }
    return;
  }

  closeAllSelects();
  dispatch(target, "onClick", "click");
}

export function findById(id) {
  return findId(root, id);
}

export function dispatchInput(id, value) {
  const target = findId(root, id);
  if (!target || target.type !== "input" || target.props.disabled || isReadOnly(target)) return;
  target._userInteracted = true;
  target.props.value = value;
  dispatch(target, "onInput", "input", value);
}

export function dispatchKey(id, key) {
  if (key === "Escape") {
    closeAllAutoPopovers();
  }
  const target = findId(root, id);
  if (!target) return;
  if (target.type === "select" && !target.props.disabled) {
    const options = getOptions(target).filter(o => !o.props.disabled);
    if (options.length === 0) return;

    if (key === "ArrowDown" || key === "Down") {
      if (!target._open) {
        const curVal = getSelectValue(target);
        const curIdx = options.findIndex(o => getOptionValue(o) === curVal);
        const nextIdx = Math.min(options.length - 1, (curIdx < 0 ? 0 : curIdx + 1));
        const nextVal = getOptionValue(options[nextIdx]);
        if (nextVal !== curVal) {
          dispatchSelectChange(target, nextVal);
        }
      } else {
        const curIdx = target._highlightedIndex ?? options.findIndex(o => getOptionValue(o) === getSelectValue(target));
        target._highlightedIndex = Math.min(options.length - 1, (curIdx < 0 ? 0 : curIdx + 1));
        const nextVal = getOptionValue(options[target._highlightedIndex]);
        dispatchSelectChange(target, nextVal);
      }
    } else if (key === "ArrowUp" || key === "Up") {
      if (!target._open) {
        const curVal = getSelectValue(target);
        const curIdx = options.findIndex(o => getOptionValue(o) === curVal);
        const prevIdx = Math.max(0, (curIdx < 0 ? 0 : curIdx - 1));
        const prevVal = getOptionValue(options[prevIdx]);
        if (prevVal !== curVal) {
          dispatchSelectChange(target, prevVal);
        }
      } else {
        const curIdx = target._highlightedIndex ?? options.findIndex(o => getOptionValue(o) === getSelectValue(target));
        target._highlightedIndex = Math.max(0, curIdx - 1);
        const prevVal = getOptionValue(options[target._highlightedIndex]);
        dispatchSelectChange(target, prevVal);
      }
    } else if (key === "Enter" || key === "Space" || key === " ") {
      if (!target._open) {
        closeAllSelects(target);
        target._open = true;
        target._initialValue = getSelectValue(target);
        target._highlightedIndex = options.findIndex(o => getOptionValue(o) === target._initialValue);
      } else {
        const curIdx = target._highlightedIndex ?? options.findIndex(o => getOptionValue(o) === getSelectValue(target));
        if (curIdx >= 0 && curIdx < options.length) {
          const commitVal = getOptionValue(options[curIdx]);
          dispatchSelectChange(target, commitVal);
        }
        target._open = false;
      }
    } else if (key === "Escape") {
      if (target._open) {
        if (target._initialValue !== undefined) {
          dispatchSelectChange(target, target._initialValue);
        }
        target._open = false;
      }
    }
  }
}

export function dispatchHover(id, hovered) {
  const target = findId(root, id);
  if (target) {
    target._isHovered = Boolean(hovered);
    if (typeof target.props.onHover === "function") {
      target.props.onHover(Boolean(hovered));
    }
  }
}

export function dispatchActive(id, active) {
  const target = findId(root, id);
  if (target) {
    target._isActive = Boolean(active);
  }
}

export function dispatchFocus(id, focused) {
  const target = findId(root, id);
  if (target) {
    target._isFocused = Boolean(focused);
  }
}

export function mountApp(Component) {
  globalThis.__uiRenderer = renderer;
  globalThis.__uiSolid = solid;
  if (typeof __NATIVE_HMR__ !== "undefined" && __NATIVE_HMR__) {
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
  globalThis.uiDispatchClick = id => dispatchClick(id);
  globalThis.uiDispatchHover = (id, hovered) => dispatchHover(id, hovered);
  globalThis.uiDispatchActive = (id, active) => dispatchActive(id, active);
  globalThis.uiDispatchFocus = (id, focused) => dispatchFocus(id, focused);
  globalThis.uiDispatchInput = (id, value) => dispatchInput(id, value);
  globalThis.uiDispatchKey = (id, key) => dispatchKey(id, key);
  globalThis.uiDispose = () => {
    dispose?.();
    dispose = undefined;
    globalThis.__uiModules?.dispose();
    root = renderer.node("root");
    committed.clear();
    pendingCommit = undefined;
  };
  mount(Component);
}

export {
  matchMedia,
  evaluateMediaQuery,
  setScriptingState,
  getScriptingState,
  querySelector,
  closest,
  calculateSpecificity,
};
export function startViewTransition(updateCallback, options = {}) {
  activeViewTransition = true;
  activeViewTransitionTypes = new Set(options.types || []);
  let finishedResolve, readyResolve, updateCallbackDoneResolve;
  const finished = new Promise(resolve => { finishedResolve = resolve; });
  const ready = new Promise(resolve => { readyResolve = resolve; });
  const updateCallbackDone = new Promise(resolve => { updateCallbackDoneResolve = resolve; });

  let skipped = false;
  const vt = {
    finished,
    ready,
    updateCallbackDone,
    skipTransition() {
      skipped = true;
      activeViewTransition = false; activeViewTransitionTypes.clear();
      updateCallbackDoneResolve();
      readyResolve();
      finishedResolve();
    }
  };

  (async () => {
    try {
      if (typeof updateCallback === "function") {
        await updateCallback();
      }
      updateCallbackDoneResolve();
      readyResolve();
      setTimeout(() => {
        activeViewTransition = false; activeViewTransitionTypes.clear();
        if (!skipped) finishedResolve();
      }, 250);
    } catch (err) {
      activeViewTransition = false; activeViewTransitionTypes.clear();
      updateCallbackDoneResolve();
      readyResolve();
      finishedResolve();
    }
  })();

  return vt;
}

export function createScope(options = {}, styles = {}) {
  const { root = null, limit = null } = options;
  const scoped = {};
  for (const [key, value] of Object.entries(styles)) {
    scoped[key] = {
      ...value,
      _scopeRoot: root,
      _scopeLimit: limit,
    };
  }
  return scoped;
}

export function computeObjectFit(fit, containerWidth, containerHeight, intrinsicWidth, intrinsicHeight) {
  const cw = Math.max(0, containerWidth);
  const ch = Math.max(0, containerHeight);
  const iw = Math.max(0, intrinsicWidth);
  const ih = Math.max(0, intrinsicHeight);
  if (iw <= 0 || ih <= 0 || cw <= 0 || ch <= 0) {
    return { width: cw, height: ch };
  }
  const f = (fit || "fill").toLowerCase();
  switch (f) {
    case "fill":
      return { width: cw, height: ch };
    case "none":
      return { width: iw, height: ih };
    case "contain": {
      const scale = Math.min(cw / iw, ch / ih);
      return { width: iw * scale, height: ih * scale };
    }
    case "cover": {
      const scale = Math.max(cw / iw, ch / ih);
      return { width: iw * scale, height: ih * scale };
    }
    case "scale-down": {
      const scale = Math.min(cw / iw, ch / ih);
      if (scale < 1.0) {
        return { width: iw * scale, height: ih * scale };
      } else {
        return { width: iw, height: ih };
      }
    }
    default:
      return { width: cw, height: ch };
  }
}

export function computeObjectPosition(position, containerWidth, containerHeight, objectWidth, objectHeight) {
  const cw = Math.max(0, containerWidth);
  const ch = Math.max(0, containerHeight);
  const ow = Math.max(0, objectWidth);
  const oh = Math.max(0, objectHeight);
  const tokens = splitSpacing(String(position || "50% 50%").trim());

  let posX = 0.5, posY = 0.5;
  let offsetX = 0, offsetY = 0;

  function parseAxis(token, isVertical = false) {
    if (token === "left") return { pos: 0, offset: 0 };
    if (token === "right") return { pos: 1, offset: 0 };
    if (token === "top") return { pos: 0, offset: 0 };
    if (token === "bottom") return { pos: 1, offset: 0 };
    if (token === "center") return { pos: 0.5, offset: 0 };
    if (token.endsWith("%")) {
      return { pos: parseFloat(token) / 100, offset: 0 };
    }
    if (token.endsWith("px") || /^[+-]?\d+(?:\.\d+)?$/.test(token)) {
      return { pos: 0, offset: parseFloat(token) };
    }
    return { pos: isVertical ? 0.5 : 0.5, offset: 0 };
  }

  if (tokens.length === 1) {
    if (["top", "bottom"].includes(tokens[0])) {
      const v = parseAxis(tokens[0], true);
      posY = v.pos; offsetY = v.offset;
      posX = 0.5;
    } else {
      const h = parseAxis(tokens[0], false);
      posX = h.pos; offsetX = h.offset;
      posY = 0.5;
    }
  } else if (tokens.length === 2) {
    const isFirstVert = ["top", "bottom"].includes(tokens[0]);
    if (isFirstVert) {
      const v = parseAxis(tokens[0], true);
      const h = parseAxis(tokens[1], false);
      posY = v.pos; offsetY = v.offset;
      posX = h.pos; offsetX = h.offset;
    } else {
      const h = parseAxis(tokens[0], false);
      const v = parseAxis(tokens[1], true);
      posX = h.pos; offsetX = h.offset;
      posY = v.pos; offsetY = v.offset;
    }
  } else if (tokens.length === 4) {
    for (let i = 0; i < 4; i += 2) {
      const edge = tokens[i];
      const val = parseFloat(tokens[i + 1]) || 0;
      if (edge === "left") { posX = 0; offsetX = val; }
      else if (edge === "right") { posX = 1; offsetX = -val; }
      else if (edge === "top") { posY = 0; offsetY = val; }
      else if (edge === "bottom") { posY = 1; offsetY = -val; }
    }
  }

  const x = (cw - ow) * posX + offsetX;
  const y = (ch - oh) * posY + offsetY;
  return { x, y };
}

export function computeObjectRect(container, intrinsicWidth, intrinsicHeight, fit, position) {
  const cw = container.width ?? 0;
  const ch = container.height ?? 0;
  const size = computeObjectFit(fit, cw, ch, intrinsicWidth, intrinsicHeight);
  const pos = computeObjectPosition(position, cw, ch, size.width, size.height);
  return {
    x: (container.x ?? 0) + pos.x,
    y: (container.y ?? 0) + pos.y,
    width: size.width,
    height: size.height,
  };
}

export {
  NamespaceRegistry,
  parseAnPlusB,
  matchesSelector,
  expandNesting,
  resolveNestedStyles,
};
export { setTarget, setTargetText, getTarget, getTargetText } from "./renderer.js";

// ---------------------------------------------------------------------------
// CSS 2024 Batch 11 Helpers
// ---------------------------------------------------------------------------

export function isPlaceholderShown(node) {
  if (!node) return false;
  const isInput = node.type === "input";
  const isTextarea = node.type === "textarea";
  if (!isInput && !isTextarea) return false;
  const inputType = String(node.props?.type ?? "text").toLowerCase();
  const supports = ["text", "search", "url", "tel", "email", "password", "number"].includes(inputType);
  if (!supports && !isTextarea) return false;
  const ph = node.props?.placeholder;
  if (!ph || typeof ph !== "string" || ph.length === 0) return false;
  const val = node.props?.value ?? node.value ?? "";
  return String(val).length === 0;
}

export const PAGE_SIZES = {
  "jis-b4": { width: 728.5039, height: 1031.811 },
  "jis-b5": { width: 515.9055, height: 728.5039 },
  a4: { width: 595.2756, height: 841.8898 },
  a3: { width: 841.8898, height: 1190.551 },
  a5: { width: 419.5276, height: 595.2756 },
  b4: { width: 708.6614, height: 1000.6299 },
  b5: { width: 498.8976, height: 708.6614 },
  letter: { width: 612.0, height: 792.0 },
  legal: { width: 612.0, height: 1008.0 },
  ledger: { width: 792.0, height: 1224.0 },
};

export function pageSetup(input = {}) {
  let sizeStr = typeof input === "string" ? input : (input.size ?? "a4");
  let orientation = input.orientation ?? null;
  const margin = input.margin ? boxSides(input.margin) : { t: 36, r: 36, b: 36, l: 36 };
  let width = PAGE_SIZES.a4.width;
  let height = PAGE_SIZES.a4.height;

  const tokens = splitSpacing(sizeStr.toLowerCase());
  for (const token of tokens) {
    if (token === "portrait" || token === "landscape") {
      orientation = token;
    } else if (PAGE_SIZES[token]) {
      width = PAGE_SIZES[token].width;
      height = PAGE_SIZES[token].height;
    } else if (token.endsWith("in")) {
      width = parseFloat(token) * 72;
    } else if (token.endsWith("mm")) {
      width = parseFloat(token) * (72 / 25.4);
    } else if (token.endsWith("pt") || /^\d+(\.\d+)?$/.test(token)) {
      width = parseFloat(token);
    }
  }

  if (orientation === "landscape" && width < height) {
    const tmp = width; width = height; height = tmp;
  } else if (orientation === "portrait" && width > height) {
    const tmp = width; width = height; height = tmp;
  }

  return {
    name: input.name ?? "auto",
    selector: input.selector ?? ":first",
    size: { width, height },
    orientation: orientation ?? (width > height ? "landscape" : "portrait"),
    margin: { top: margin.t, right: margin.r, bottom: margin.b, left: margin.l },
    contentWidth: Math.max(0, width - margin.l - margin.r),
    contentHeight: Math.max(0, height - margin.t - margin.b),
  };
}

export function paginate(nodes = [], setup = pageSetup()) {
  const pages = [];
  let pageNumber = 1;
  let isLeft = false;
  let contentH = setup.contentHeight;
  let remainingH = contentH;

  pages.push({
    pageNumber,
    isLeft,
    isBlank: false,
    dimensions: setup.size,
    items: [],
  });

  for (const item of nodes) {
    const style = item.style || {};
    const h = item.bounds?.height || (typeof style.height === "number" ? style.height : 20);
    const bb = style.breakBefore ?? "auto";
    const ba = style.breakAfter ?? "auto";
    const bi = style.breakInside ?? "auto";

    if (["page", "left", "right"].includes(bb)) {
      pageNumber++;
      isLeft = !isLeft;
      if (bb === "left" && !isLeft) {
        pages.push({ pageNumber, isLeft: false, isBlank: true, dimensions: setup.size, items: [] });
        pageNumber++;
        isLeft = true;
      } else if (bb === "right" && isLeft) {
        pages.push({ pageNumber, isLeft: true, isBlank: true, dimensions: setup.size, items: [] });
        pageNumber++;
        isLeft = false;
      }
      pages.push({ pageNumber, isLeft, isBlank: false, dimensions: setup.size, items: [] });
      remainingH = contentH;
    }

    if (h > remainingH && (bi === "avoid" || bi === "avoid-page" || remainingH < contentH * 0.2)) {
      pageNumber++;
      isLeft = !isLeft;
      pages.push({ pageNumber, isLeft, isBlank: false, dimensions: setup.size, items: [] });
      remainingH = contentH;
    }

    pages[pages.length - 1].items.push(item);
    remainingH = Math.max(0, remainingH - h);

    if (["page", "left", "right"].includes(ba)) {
      pageNumber++;
      isLeft = !isLeft;
      if (ba === "left" && !isLeft) {
        pages.push({ pageNumber, isLeft: false, isBlank: true, dimensions: setup.size, items: [] });
        pageNumber++;
        isLeft = true;
      } else if (ba === "right" && isLeft) {
        pages.push({ pageNumber, isLeft: true, isBlank: true, dimensions: setup.size, items: [] });
        pageNumber++;
        isLeft = false;
      }
      pages.push({ pageNumber, isLeft, isBlank: false, dimensions: setup.size, items: [] });
      remainingH = contentH;
    }
  }

  return pages;
}

export function parsePathShape(pathStr) {
  let s = String(pathStr || "").trim();
  let fillRule = "nonzero";
  if (s.startsWith("path(") && s.endsWith(")")) {
    const inner = s.slice(5, -1).trim();
    const comma = inner.indexOf(",");
    if (comma >= 0) {
      const rule = inner.slice(0, comma).trim().toLowerCase();
      if (rule === "evenodd" || rule === "nonzero") fillRule = rule;
      s = inner.slice(comma + 1).trim();
    } else {
      s = inner;
    }
  }
  if ((s.startsWith('"') && s.endsWith('"')) || (s.startsWith("'") && s.endsWith("'"))) {
    s = s.slice(1, -1);
  }

  const commands = [];
  const regex = /([a-df-z])([^a-df-z]*)/gi;
  let match;
  while ((match = regex.exec(s)) !== null) {
    const type = match[1];
    const args = (match[2].trim().match(/[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?/gi) || []).map(Number);
    commands.push({ type, args });
  }

  return {
    fillRule,
    d: s,
    commands,
  };
}

