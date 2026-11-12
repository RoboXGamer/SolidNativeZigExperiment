import * as solid from "solid-js";
import * as refresh from "solid-js/refresh";
import * as renderer from "./renderer.js";
import { createModuleHost } from "./module-runtime.js";
import { matchMedia, evaluateMediaQuery, setScriptingState, getScriptingState } from "./media.js";
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

function displayOf(node, style) {
  if (typeof style.display === "string") return style.display;
  if (node.type === "text") return "block";
  if (node.type === "grid") return "grid";
  if (node.type === "option" && node.parent?.type === "select") {
    return node.parent._open ? "flex" : "none";
  }
  return "flex";
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

function isLengthOrKeyword(val) {
  if (typeof val !== "string") return false;
  const s = val.trim();
  if (s === "auto" || s === "content" || s === "min-content" || s === "max-content" || s === "fit-content") return true;
  if (/px|%|em|rem|vw|vh|vmin|vmax|calc\(|min\(|max\(|clamp\(/i.test(s)) return true;
  return isNaN(Number(s));
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
export function physicalStyle(style, inherited = {}) {
  const mode = style.writingMode ?? inherited.writingMode ?? "horizontal-tb";
  const direction = style.direction ?? inherited.direction ?? "ltr";
  if (!["horizontal-tb", "vertical-rl", "vertical-lr"].includes(mode) || !["ltr", "rtl"].includes(direction)) throw Error("Unsupported writing mode or direction");
  const vertical = mode !== "horizontal-tb";
  const inlineStart = vertical ? (direction === "ltr" ? "Top" : "Bottom") : (direction === "ltr" ? "Left" : "Right");
  const inlineEnd = vertical ? (direction === "ltr" ? "Bottom" : "Top") : (direction === "ltr" ? "Right" : "Left");
  const blockStart = vertical ? (mode === "vertical-rl" ? "Right" : "Left") : "Top";
  const blockEnd = vertical ? (mode === "vertical-rl" ? "Left" : "Right") : "Bottom";
  const logical = { InlineStart: inlineStart, InlineEnd: inlineEnd, BlockStart: blockStart, BlockEnd: blockEnd };
  const sizes = { inlineSize: vertical ? "height" : "width", blockSize: vertical ? "width" : "height",
    minInlineSize: vertical ? "minHeight" : "minWidth", minBlockSize: vertical ? "minWidth" : "minHeight",
    maxInlineSize: vertical ? "maxHeight" : "maxWidth", maxBlockSize: vertical ? "maxWidth" : "maxHeight" };
  const result = { writingMode: mode, direction };
  for (const [key, value] of Object.entries(style)) {
    if (value == null) continue;
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
    if (key === "inset") {
      const sides = boxSides(value, { negative: true });
      for (const [letter, side] of [["t", "top"], ["r", "right"], ["b", "bottom"], ["l", "left"]]) result[side] = sides[letter];
      continue;
    }
    if (key === "insetInline") {
      const parts = typeof value === "string" ? splitSpacing(value.trim()) : [value];
      result[vertical ? (direction === "ltr" ? "top" : "bottom") : (direction === "ltr" ? "left" : "right")] = parts[0];
      result[vertical ? (direction === "ltr" ? "bottom" : "top") : (direction === "ltr" ? "right" : "left")] = parts[1] ?? parts[0];
      continue;
    }
    if (key === "insetBlock") {
      const parts = typeof value === "string" ? splitSpacing(value.trim()) : [value];
      result[vertical ? (mode === "vertical-rl" ? "right" : "left") : "top"] = parts[0];
      result[vertical ? (mode === "vertical-rl" ? "left" : "right") : "bottom"] = parts[1] ?? parts[0];
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
    if (sizes[key]) { result[sizes[key]] = value; continue; }
    const edge = key.match(/^(margin|padding|border|scrollMargin|scrollPadding)(InlineStart|InlineEnd|BlockStart|BlockEnd)(Width)?$/);
    if (edge) { result[edge[1] + logical[edge[2]] + (edge[3] ?? "")] = value; continue; }
    const pair = key.match(/^(margin|padding|border|scrollMargin|scrollPadding)(Inline|Block)(Width)?$/);
    if (pair) {
      const parts = typeof value === "string" ? splitSpacing(value.trim()) : [value];
      if (parts.length < 1 || parts.length > 2) throw Error(`Invalid logical sides: ${value}`);
      result[pair[1] + logical[pair[2] + "Start"] + (pair[3] ?? "")] = parts[0];
      result[pair[1] + logical[pair[2] + "End"] + (pair[3] ?? "")] = parts[1] ?? parts[0];
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

export function snapshot(node, inherited = {}) {
  const style = physicalStyle(node.props.style || {}, inherited);
  if(typeof style.outline==="string") {
    let width,kind,color;
    for(const token of splitSpacing(style.outline)) {
      if(["none","auto","solid","dashed","dotted","double","groove","ridge","inset","outset"].includes(token)) kind=token;
      else if(["thin","medium","thick"].includes(token) || /^[+\-.\d]/.test(token) || /^(calc|min|max|clamp|abs|round)\(/i.test(token)) width=token;
      else color=token;
    }
    style.outlineWidth??=width??"medium"; style.outlineStyle??=kind??"none"; style.outlineColor??=color??"currentColor";
  }
  const typographySpecified=authoredMask(style,["fontFamily","fontWeight","fontStyle","language","letterSpacing","wordSpacing","tabSize","textTransform","textAlignLast","textIndent"]) | (node.props.lang != null ? 1 << 3 : 0);
  const interactionSpecified=authoredMask(style,["visibility","pointerEvents","cursor"]);
  const letterSpacing=styleLength(style.letterSpacing,{normal:true,negative:true});
  const wordSpacing=styleLength(style.wordSpacing,{normal:true,negative:true});
  const textIndent=styleLength(style.textIndent,{negative:true});
  const outlineWidth=styleLength(style.outlineWidth);
  const outlineOffset=styleLength(style.outlineOffset,{negative:true});
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
  for (const key of ["width", "height", "minWidth", "minHeight", "maxWidth", "maxHeight"]) emitLength(key, size(style[key]));
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
    emitLength(side, style[side] == null ? null : spacingValue(style[side], { negative: true }));
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
  const textStyle = {
    color: typeof style.color === "string" ? style.color : (inherited.color || ""),
    fontSize: typeof style.fontSize === "number" ? style.fontSize : (inherited.fontSize || 0),
    fontSizeCss: typeof style.fontSize === "string" ? style.fontSize.trim() : null,
    fontFamily: style.fontFamily ?? inherited.fontFamily ?? "system-ui",
    fontWeight: typeof style.fontWeight==="number" ? style.fontWeight : (inherited.fontWeight ?? 400),
    fontWeightCss: typeof style.fontWeight==="string" ? style.fontWeight : null,
    fontStyle: style.fontStyle ?? inherited.fontStyle ?? "normal",
    language: node.props.lang ?? style.language ?? inherited.language ?? "",
    textTransform: style.textTransform ?? inherited.textTransform ?? "none",
    textAlignLast: style.textAlignLast ?? inherited.textAlignLast ?? "auto",
    cursor: style.cursor ?? inherited.cursor ?? "auto",
    visibility: style.visibility ?? inherited.visibility ?? "visible",
    pointerEvents: style.pointerEvents ?? inherited.pointerEvents ?? "auto",
    whiteSpace: style.whiteSpace ?? inherited.whiteSpace ?? "normal",
    textAlign: style.textAlign ?? inherited.textAlign ?? "left",
    lineHeight: style.lineHeight ?? inherited.lineHeight,
    writingMode: style.writingMode,
    direction: style.direction,
  };
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
  const clickable = !node.props.disabled && (
    typeof node.props.onClick === "function" ||
    isButton ||
    isInput ||
    isSelect ||
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
          node.type === "option" ? getOptionLabel(node) : node.text,
    clickable,
    focusable,
    tabIndex,
    value: node.type === "input" ? String(node.props.value ?? "") :
           node.type === "select" ? getSelectValue(node) :
           node.type === "option" ? getOptionValue(node) : "",
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
      typographySpecified,
      interactionSpecified,
      letterSpacing:letterSpacing.number, letterSpacingCss:letterSpacing.css,
      wordSpacing:wordSpacing.number, wordSpacingCss:wordSpacing.css,
      textIndent:textIndent.number, textIndentCss:textIndent.css,
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
      whiteSpace: typeof style.whiteSpace === "string" ? style.whiteSpace : (inherited.whiteSpace || "normal"),
      textAlign: typeof style.textAlign === "string" ? style.textAlign : (inherited.textAlign || "left"),
      lineHeight,
      lineHeightCss: lineHeightCss ?? "",
      outlineWidth:outlineWidth.number ?? 0, outlineWidthCss:outlineWidth.css ?? (typeof style.outlineWidth==="number" ? style.outlineWidth+"px" : null),
      outlineOffset:outlineOffset.number ?? 0, outlineOffsetCss:outlineOffset.css,
      outlineStyle:style.outlineStyle ?? "none",
      outlineColor: typeof style.outlineColor === "string" ? style.outlineColor : "",
      boxShadow: typeof style.boxShadow === "string" ? style.boxShadow : "",
      position: typeof style.position === "string" ? style.position.trim().toLowerCase() : "static",
      zIndex: typeof style.zIndex === "number" ? Math.trunc(style.zIndex) : null,
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
      transform: typeof style.transform === "string" ? style.transform : "",
      transformOrigin: typeof style.transformOrigin === "string" ? style.transformOrigin : "50% 50%",
      transition: typeof style.transition === "string" ? style.transition : "",
      transitionProperty: typeof style.transitionProperty === "string" ? style.transitionProperty : "all",
      transitionDuration: typeof style.transitionDuration === "number" ? style.transitionDuration : (typeof style.transitionDuration === "string" ? (parseFloat(style.transitionDuration) * (style.transitionDuration.endsWith("ms") ? 0.001 : 1.0) || 0) : 0),
      transitionTimingFunction: typeof style.transitionTimingFunction === "string" ? style.transitionTimingFunction : "ease",
      transitionDelay: typeof style.transitionDelay === "number" ? style.transitionDelay : (typeof style.transitionDelay === "string" ? (parseFloat(style.transitionDelay) * (style.transitionDelay.endsWith("ms") ? 0.001 : 1.0) || 0) : 0),
      ...textStyle,
      lineHeight,
      lineHeightCss,
      ...defaultSelectStyle,
      ...defaultOptionStyle,
    },
    children: node.children.map(child => snapshot(child, textStyle)),
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
  selectNode.props.value = newValue;
  selectNode._value = newValue;
  dispatch(selectNode, "onInput", "input", newValue);
  dispatch(selectNode, "onChange", "change", newValue);
}

export function dispatchClick(id) {
  const target = findId(root, id);
  if (!target) {
    closeAllSelects();
    return;
  }
  if (target.props.disabled) return;

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

export function dispatchInput(id, value) {
  const target = findId(root, id);
  if (!target || target.type !== "input" || target.props.disabled || target.props.readOnly) return;
  target.props.value = value;
  dispatch(target, "onInput", "input", value);
}

export function dispatchKey(id, key) {
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
  matches,
  querySelector,
  querySelectorAll,
  closest,
  calculateSpecificity,
};

