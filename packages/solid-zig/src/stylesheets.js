import { CSSStyleDeclaration } from "cssstyle";
import {
  specificity,
  splitSelectorList,
  compareSpecificity,
  compileSelector,
} from "./selectors-user.js";
import definitions from "./css-properties.json" with { type: "json" };
const sheets = new Map();
let sheetVersion = 0;
export const getStyleSheetVersion = () => sheetVersion;
let computedVersion = 0;
let metadata;
let ruleId = 0;
const declarationCache = new Map();
function preparedRules(rules) {
  return rules.map((rule) =>
    rule.condition
      ? { ...rule, rules: preparedRules(rule.rules) }
      : {
          ...rule,
          id: ++ruleId,
          selectors: splitSelectorList(rule.selector).map((selector) => ({
            test: compileSelector(selector),
            spec: specificity(selector),
          })),
        },
  );
}
function parsedDeclaration(property, value) {
  const key = `${property}\0${value}`;
  if (declarationCache.has(key)) return declarationCache.get(key);
  const declaration = new CSSStyleDeclaration();
  declaration.setProperty(property, value);
  const entries = [...declaration._values];
  if (declarationCache.size >= 2048) declarationCache.clear();
  declarationCache.set(key, entries);
  return entries;
}
export function setStyleSheet(id, rules) {
  sheets.set(id, preparedRules(rules));
  declarationCache.clear();
  sheetVersion++;
}
export function removeStyleSheet(id) {
  sheets.delete(id);
  sheetVersion++;
}
export function clearStyleSheets() {
  sheets.clear();
  sheetVersion++;
}
export function stylesheetMedia(query, fallback) {
  const viewport = globalThis.__uiViewport || { width: 1280, height: 720 };
  return query.split(",").some((group) => {
    let q = group.trim();
    const negate = /^not\s+/i.test(q);
    q = q
      .replace(/^(?:not\s+|only\s+)?(?:screen|all)\s*(?:and\s*)?/i, "")
      .replace(/^not\s+/i, "");
    const parts = q.split(/\s+and\s+/i);
    const matched = parts.every((part) => {
      let match = part.match(
        /^\(\s*(min-|max-)?(width|height)\s*:\s*([\d.]+)(px|em|rem)\s*\)$/,
      );
      if (match) {
        const actual = viewport[match[2]],
          size = Number(match[3]) * (match[4] === "px" ? 1 : 16);
        return match[1] === "min-"
          ? actual >= size
          : match[1] === "max-"
            ? actual <= size
            : actual === size;
      }
      match = part.match(
        /^\(\s*(width|height)\s*(<=|>=|<|>|=)\s*([\d.]+)(px|em|rem)\s*\)$/,
      );
      if (match) {
        const actual = viewport[match[1]],
          size = Number(match[3]) * (match[4] === "px" ? 1 : 16);
        return {
          "<=": actual <= size,
          ">=": actual >= size,
          "<": actual < size,
          ">": actual > size,
          "=": actual === size,
        }[match[2]];
      }
      return !part || fallback(part);
    });
    return negate ? !matched : matched;
  });
}
const camel = (p) =>
  p.startsWith("--")
    ? p
    : p
        .replace(/^-(webkit|moz)-/, "")
        .replace(/-([a-z])/g, (_, c) => c.toUpperCase());
const cssName = (p) =>
  p.startsWith("--") ? p : p.replace(/[A-Z]/g, (c) => "-" + c.toLowerCase());
const numeric = new Set([
  "opacity",
  "flexGrow",
  "flexShrink",
  "order",
  "zIndex",
  "fontWeight",
  "tabSize",
  "columnCount",
  "fillOpacity",
  "strokeOpacity",
  "floodOpacity",
  "orphans",
  "widows",
  "zoom",
]);
function nativeValue(property, value) {
  if (typeof value !== "string") return value;
  if (numeric.has(property) && /^[-+]?\d*\.?\d+$/.test(value))
    return Number(value);
  if (property === "fontWeight" && ["normal", "bold"].includes(value))
    return value === "bold" ? 700 : 400;
  if (property === "fontFamily") return value.replace(/^['"]|['"]$/g, "");
  return value;
}

function findVar(value, offset = 0) {
  let quote = "";
  for (let i = offset; i < value.length; i++) {
    const ch = value[i];
    if (ch === "\\") {
      i++;
      continue;
    }
    if (quote) {
      if (ch === quote) quote = "";
      continue;
    }
    if (ch === '"' || ch === "'") {
      quote = ch;
      continue;
    }
    if (value.slice(i, i + 4).toLowerCase() === "var(") return i;
  }
  return -1;
}
// Resolve nested fallbacks while retaining quoted strings and escaped tokens.
function substitute(value, variables, stack = new Set()) {
  if (typeof value !== "string") return value;
  let result = "",
    offset = 0;
  while (true) {
    const start = findVar(value, offset);
    if (start < 0) return result + value.slice(offset);
    result += value.slice(offset, start);
    let depth = 1,
      end = start + 4,
      comma = -1,
      quote = "";
    for (; end < value.length; end++) {
      if (value[end] === "\\") {
        end++;
        continue;
      }
      if (quote) {
        if (value[end] === quote) quote = "";
        continue;
      }
      if (value[end] === '"' || value[end] === "'") {
        quote = value[end];
        continue;
      }
      if (value[end] === "(") depth++;
      if (value[end] === ")" && --depth === 0) break;
      if (value[end] !== ")" && value[end] === "," && depth === 1 && comma < 0)
        comma = end;
    }
    if (depth !== 0) return undefined;
    const name = value.slice(start + 4, comma < 0 ? end : comma).trim();
    let replacement;
    if (!stack.has(name) && Object.hasOwn(variables, name))
      replacement = substitute(
        variables[name],
        variables,
        new Set([...stack, name]),
      );
    if (replacement === undefined && comma >= 0)
      replacement = substitute(
        value.slice(comma + 1, end).trim(),
        variables,
        stack,
      );
    if (replacement === undefined) return undefined;
    result += replacement;
    offset = end + 1;
  }
}

export function sheetStyle(node, inline, inheritedKeys, initials, evaluate) {
  if (!sheets.size) {
    if (node._cssCacheKey !== "no-stylesheets") {
      node._cssCacheKey = "no-stylesheets";
      node._cssComputedVersion = ++computedVersion;
      node._cssInheritanceVersion = ++computedVersion;
      delete node._cssComputed;
      delete node._cssComputedSignature;
      delete node._cssInheritanceSignature;
      delete node._cssVariables;
    }
    return inline || {};
  }
  if (!metadata)
    metadata = {
      inheritedKeys: new Set([
        ...inheritedKeys,
        ...Object.entries(definitions)
          .filter(([, d]) => d.inherited)
          .map(([p]) => camel(p)),
      ]),
      initials: {
        ...Object.fromEntries(
          Object.entries(definitions).map(([p, d]) => [
            camel(p),
            nativeValue(camel(p), d.initial),
          ]),
        ),
        ...initials,
        color: "#000000",
        fontSize: 16,
        fontFamily: "system-ui",
        backgroundColor: "transparent",
        fontWeight: 400,
        borderColor: "currentColor",
        borderTopColor: "currentColor",
        borderRightColor: "currentColor",
        borderBottomColor: "currentColor",
        borderLeftColor: "currentColor",
      },
    };
  ({ inheritedKeys, initials } = metadata);
  const winners = new Map();
  const candidates = new Map();
  const layers = new Map();
  const matched = [];
  let order = 0;
  function offer(
    property,
    value,
    important,
    spec,
    layer = null,
    sourceProperty = property,
  ) {
    const key = camel(property);
    const rank = [
      Number(important),
      Number(important && spec[0] === 1),
      important
        ? layer === null
          ? 0
          : 100000 - layer
        : layer === null
          ? 100000
          : layer,
      ...spec,
      order++,
    ];
    if (!candidates.has(key)) candidates.set(key, []);
    candidates.get(key).push({
      value,
      sourceProperty,
      rank,
      layer: spec[0] === 1 ? "inline" : layer,
    });
  }
  function visit(rules, layer = null) {
    for (const rule of rules) {
      if (rule.condition) {
        if (rule.condition === "layer") {
          for (const name of rule.query.split(","))
            if (!layers.has(name.trim())) layers.set(name.trim(), layers.size);
          visit(rule.rules, layers.get(rule.query.trim()));
        } else if (evaluate(rule.condition, rule.query))
          visit(rule.rules, layer);
        continue;
      }
      let spec = null;
      for (const selector of rule.selectors)
        if (selector.test(node)) {
          const next = selector.spec;
          if (!spec || compareSpecificity(next, spec) > 0) spec = next;
        }
      if (!spec) continue;
      matched.push({ rule, spec, layer });
    }
  }
  for (const rules of sheets.values()) visit(rules);
  const needsParent =
    matched.some(({ rule }) =>
      rule.declarations.some(
        (d) => d.value === "inherit" || /var\(/i.test(d.value),
      ),
    ) ||
    Object.values(inline || {}).some(
      (value) => value === "inherit" || /var\(/i.test(String(value)),
    );
  const cacheKey = JSON.stringify([
    sheetVersion,
    matched.map(({ rule, spec, layer }) => [rule.id, spec, layer]),
    inline,
    node.parent?._cssInheritanceVersion,
    needsParent ? node.parent?._cssComputedVersion : null,
  ]);
  if (node._cssCacheKey === cacheKey) return node._cssComputed;
  node._cssCacheKey = cacheKey;
  for (const { rule, spec, layer } of matched) {
    for (const d of rule.declarations)
      for (const leaf of d.leaves)
        offer(leaf, d.value, d.important, [0, ...spec], layer, d.property);
  }
  // Inline declarations participate in the same per-property cascade.
  for (const [key, value] of Object.entries(inline || {})) {
    if (value == null || typeof value === "object") continue;
    const property = cssName(key);
    const raw = String(value).replace(/\s*!important\s*$/i, "");
    const important =
      typeof value === "string" && /!important\s*$/i.test(value);
    const parsed = parsedDeclaration(
      property,
      typeof value === "number" && !numeric.has(key) && value !== 0
        ? `${value}px`
        : raw,
    );
    const entries = parsed.filter(([p]) => p !== property);
    if (entries.length)
      for (const [p, v] of entries) offer(p, v, important, [1, 0, 0, 0]);
    else
      offer(
        property,
        typeof value === "number" ? value : raw,
        important,
        [1, 0, 0, 0],
      );
  }
  for (const [key, list] of candidates) {
    list.sort((a, b) => {
      for (let i = 0; i < a.rank.length; i++)
        if (a.rank[i] !== b.rank[i]) return b.rank[i] - a.rank[i];
      return 0;
    });
    const excluded = new Set();
    for (const candidate of list) {
      if (excluded.has(candidate.layer)) continue;
      if (candidate.value === "revert-layer") {
        excluded.add(candidate.layer);
        continue;
      }
      winners.set(key, candidate);
      break;
    }
  }
  const parent = node.parent?._cssComputed || {};
  const variables = { ...node.parent?._cssVariables };
  for (const [key, winner] of winners)
    if (key.startsWith("--")) {
      if (winner.value === "initial") delete variables[key];
      else if (!["inherit", "unset", "revert"].includes(winner.value))
        variables[key] = winner.value;
    }
  // CSS cycles include references inside fallbacks. A fallback cannot make a
  // self-referential custom property valid.
  const cyclic = new Set();
  function detect(key, path = []) {
    if (path.includes(key)) {
      for (const name of path.slice(path.indexOf(key))) cyclic.add(name);
      return;
    }
    const value = String(variables[key] ?? "");
    for (
      let start = findVar(value);
      start >= 0;
      start = findVar(value, start + 4)
    ) {
      const name = value.slice(start + 4).match(/^\s*(--[\w-]+)/)?.[1];
      if (name && Object.hasOwn(variables, name)) detect(name, [...path, key]);
    }
  }
  for (const key of Object.keys(variables)) detect(key);
  for (const key of cyclic) variables[key] = undefined;
  const rawVariables = { ...variables };
  // Freeze inherited custom properties at their defining element.
  for (const key of Object.keys(variables))
    variables[key] = substitute(
      rawVariables[key],
      rawVariables,
      new Set([key]),
    );
  node._cssVariables = variables;
  const result = {};
  for (const key of inheritedKeys)
    if (parent[key] !== undefined) result[key] = parent[key];
  if (!node.parent) {
    result.fontSize = 16;
    result.color = "#000000";
  }
  for (const [key, winner] of winners) {
    if (key.startsWith("--")) {
      result[key] = variables[key];
      continue;
    }
    let value = substitute(winner.value, variables);
    if (
      ["initial", "inherit", "unset", "revert", "revert-layer"].includes(
        value,
      ) ||
      value === undefined
    ) {
      const inherit =
        value === "inherit" ||
        ((value === undefined ||
          value === "unset" ||
          value?.startsWith("revert")) &&
          inheritedKeys.has(key));
      result[key] = inherit ? (parent[key] ?? initials[key]) : initials[key];
      continue;
    }
    if (camel(winner.sourceProperty) !== key) {
      value =
        parsedDeclaration(winner.sourceProperty, value).find(
          ([p]) => p === cssName(key),
        )?.[1] || initials[key];
    }
    result[key] = nativeValue(key, value);
  }
  // Preserve existing object-style pseudo rules and host-specific controls.
  for (const [key, value] of Object.entries(inline || {}))
    if (typeof value === "object" && value !== null) result[key] = value;
  for (const [key, value] of Object.entries(variables))
    if (value !== undefined) result[key] = value;
  const parentFont = typeof parent.fontSize === "number" ? parent.fontSize : 16;
  const rootFont = node.parent?._cssRootFont || 16;
  function pixels(value, basis) {
    if (typeof value === "number") return value;
    const match = String(value).match(/^([+-]?[\d.]+)(px|em|rem|%)$/);
    if (!match) return value;
    const number = Number(match[1]);
    return match[2] === "px"
      ? number
      : match[2] === "rem"
        ? number * rootFont
        : match[2] === "%"
          ? (number * basis) / 100
          : number * basis;
  }
  if (result.fontSize !== undefined)
    result.fontSize = pixels(result.fontSize, parentFont);
  if (String(result.color).toLowerCase() === "currentcolor")
    result.color = parent.color ?? initials.color;
  node._cssRootFont = node.parent ? rootFont : (result.fontSize ?? 16);
  for (const key of ["letterSpacing", "wordSpacing"])
    if (winners.has(key))
      result[key] = pixels(result[key], result.fontSize ?? parentFont);
  if (winners.has("lineHeight") && /(?:px|em|rem|%)$/.test(result.lineHeight))
    result.lineHeight = `${pixels(result.lineHeight, result.fontSize ?? parentFont)}px`;
  const signature = JSON.stringify(result);
  if (signature !== node._cssComputedSignature) {
    node._cssComputed = result;
    node._cssComputedSignature = signature;
    node._cssComputedVersion = ++computedVersion;
  }
  const inheritance = JSON.stringify([
    [...inheritedKeys].map((key) => result[key]),
    variables,
    node._cssRootFont,
  ]);
  if (inheritance !== node._cssInheritanceSignature) {
    node._cssInheritanceSignature = inheritance;
    node._cssInheritanceVersion = ++computedVersion;
  }
  return node._cssComputed;
}
