// CSS Selectors Level 3 / Level 4 Engine for Solid Native
// Supports:
// - :nth-child(), :nth-last-child()
// - :nth-child(An+B of <selector>), :nth-last-child(An+B of <selector>)
// - :first-child, :last-child, :only-child (including no_parent_required)
// - :nth-of-type(), :nth-last-of-type(), :first-of-type(), :last-of-type(), :only-of-type()
// - :not(<selector-list>)
// - CSS Nesting (&, direct descendant, relative combinators)
// - @namespace at-rule and namespace prefix selectors (prefix|E, *|E, |E)

export class NamespaceRegistry {
  constructor() {
    this.namespaces = new Map();
    this.defaultNamespace = null;
  }

  register(prefix, url) {
    if (!prefix || prefix === "") {
      this.defaultNamespace = url;
    } else {
      this.namespaces.set(prefix, url);
    }
  }

  parseAtRule(atRuleStr) {
    const trimmed = atRuleStr.trim();
    const match = trimmed.match(/^@namespace\s+(?:([a-zA-Z0-9_-]+)\s+)?(?:url\(["']?([^"')]+)["']?\)|["']([^"']+)["']);?$/i);
    if (!match) return false;
    const prefix = match[1] || "";
    const url = match[2] || match[3] || "";
    this.register(prefix, url);
    return true;
  }

  get(prefix) {
    if (!prefix || prefix === "") return this.defaultNamespace;
    return this.namespaces.get(prefix) ?? null;
  }
}

export function parseAnPlusB(expr) {
  if (expr == null) return null;
  const s = String(expr).trim().toLowerCase();
  if (s === "even") return { a: 2, b: 0, matches: (i) => i % 2 === 0 };
  if (s === "odd") return { a: 2, b: 1, matches: (i) => i % 2 === 1 };

  // Integer only, e.g. "3", "-2"
  if (/^[+-]?\d+$/.test(s)) {
    const b = parseInt(s, 10);
    return { a: 0, b, matches: (i) => i === b };
  }

  // An+B patterns: e.g. "2n+1", "2n", "+n-3", "-n+5", "n"
  const match = s.match(/^([+-]?\d*)?n(?:\s*([+-])\s*(\d+))?$/);
  if (match) {
    let aStr = match[1];
    let a = 1;
    if (aStr === "" || aStr === "+") a = 1;
    else if (aStr === "-") a = -1;
    else if (aStr != null) a = parseInt(aStr, 10);

    let b = 0;
    if (match[3] != null) {
      b = parseInt(match[3], 10);
      if (match[2] === "-") b = -b;
    }

    return {
      a,
      b,
      matches: (i) => {
        if (a === 0) return i === b;
        const diff = i - b;
        return (diff % a === 0) && (diff / a >= 0);
      }
    };
  }

  return null;
}

function getNodeNamespace(node) {
  if (!node) return null;
  return node.props?.xmlns ?? node.props?.namespace ?? node.namespace ?? null;
}

export function splitSelectorList(selectorStr) {
  const selectors = [];
  let depth = 0;
  let start = 0;
  const s = selectorStr.trim();
  for (let i = 0; i < s.length; i++) {
    const ch = s[i];
    if (ch === "(") depth++;
    else if (ch === ")") depth--;
    else if (ch === "," && depth === 0) {
      selectors.push(s.slice(start, i).trim());
      start = i + 1;
    }
  }
  if (start < s.length) selectors.push(s.slice(start).trim());
  return selectors.filter(Boolean);
}

// Check if a single simple selector (e.g. "button", ".btn", ":first-child", "[disabled]", "svg|path") matches node
function matchesSimpleSelector(node, part, context = {}) {
  if (!part) return true;
  const { namespaces, defaultNamespace } = context;

  // Nesting reference &
  if (part === "&") return true;

  // Namespace prefix: prefix|element, *|element, |element
  if (part.includes("|") && !part.startsWith("||")) {
    const pipeIdx = part.indexOf("|");
    const prefix = part.slice(0, pipeIdx);
    const rest = part.slice(pipeIdx + 1);
    const nodeNs = getNodeNamespace(node);

    if (prefix === "*") {
      // Any namespace including no namespace
      return matchesSimpleSelector(node, rest, context);
    } else if (prefix === "") {
      // Element in no namespace
      if (nodeNs != null && nodeNs !== "") return false;
      return matchesSimpleSelector(node, rest, context);
    } else {
      const targetNs = namespaces?.get ? namespaces.get(prefix) : namespaces?.[prefix];
      if (!targetNs || nodeNs !== targetNs) return false;
      return matchesSimpleSelector(node, rest, context);
    }
  }

  // Type selector
  if (/^[a-zA-Z0-9_-]+$/.test(part)) {
    if (defaultNamespace && getNodeNamespace(node) !== defaultNamespace) return false;
    return node.type === part;
  }

  // Universal selector *
  if (part === "*") return true;

  // ID selector #id
  if (part.startsWith("#")) {
    const id = part.slice(1);
    return node.props?.id === id || String(node.id) === id;
  }

  // Class selector .class
  if (part.startsWith(".")) {
    const cls = part.slice(1);
    const classProp = node.props?.class || node.props?.className || "";
    const classes = String(classProp).split(/\s+/);
    return classes.includes(cls);
  }

  // Attribute selector [attr] or [attr=val]
  if (part.startsWith("[") && part.endsWith("]")) {
    const attrBody = part.slice(1, -1).trim();
    const match = attrBody.match(/^([a-zA-Z0-9_-]+)(?:([~|^$*]?=)["']?([^"']*)["']?)?$/);
    if (!match) return false;
    const [, attrName, op, expectedVal] = match;
    const actualVal = node.props ? node.props[attrName] : undefined;
    if (op == null) {
      return actualVal !== undefined && actualVal !== false && actualVal !== null;
    }
    const actualStr = String(actualVal ?? "");
    switch (op) {
      case "=": return actualStr === expectedVal;
      case "~=": return actualStr.split(/\s+/).includes(expectedVal);
      case "^=": return actualStr.startsWith(expectedVal);
      case "$=": return actualStr.endsWith(expectedVal);
      case "*=": return actualStr.includes(expectedVal);
      case "|=": return actualStr === expectedVal || actualStr.startsWith(expectedVal + "-");
      default: return false;
    }
  }

  // Pseudo-classes
  if (part.startsWith(":")) {
    const parent = node.parent;
    const siblings = parent ? parent.children : [node];
    const index = siblings.indexOf(node) + 1; // 1-based

    if (part === ":first-child") {
      return siblings[0] === node;
    }
    if (part === ":last-child") {
      return siblings[siblings.length - 1] === node;
    }
    if (part === ":only-child") {
      // CSS selectors only-child with no_parent_required: matches if no parent or single child
      return !parent || siblings.length === 1;
    }

    // :first-of-type, :last-of-type, :only-of-type
    if (part === ":first-of-type") {
      const typeSiblings = siblings.filter(s => s.type === node.type);
      return typeSiblings[0] === node;
    }
    if (part === ":last-of-type") {
      const typeSiblings = siblings.filter(s => s.type === node.type);
      return typeSiblings[typeSiblings.length - 1] === node;
    }
    if (part === ":only-of-type") {
      const typeSiblings = siblings.filter(s => s.type === node.type);
      return typeSiblings.length === 1;
    }

    // :nth-of-type(An+B), :nth-last-of-type(An+B)
    const nthOfTypeMatch = part.match(/^:(nth-of-type|nth-last-of-type)\(([^)]+)\)$/i);
    if (nthOfTypeMatch) {
      const isLast = nthOfTypeMatch[1].toLowerCase() === "nth-last-of-type";
      const rule = parseAnPlusB(nthOfTypeMatch[2]);
      if (!rule) return false;
      const typeSiblings = siblings.filter(s => s.type === node.type);
      const typeIdx = typeSiblings.indexOf(node);
      if (typeIdx < 0) return false;
      const rank = isLast ? (typeSiblings.length - typeIdx) : (typeIdx + 1);
      return rule.matches(rank);
    }

    // :nth-child(An+B [of <selector>]) and :nth-last-child(An+B [of <selector>])
    const nthChildMatch = part.match(/^:(nth-child|nth-last-child)\((.+)\)$/i);
    if (nthChildMatch) {
      const isLast = nthChildMatch[1].toLowerCase() === "nth-last-child";
      const inner = nthChildMatch[2].trim();
      let anPlusBStr = inner;
      let ofSelector = null;

      // Check for "of <selector>"
      const ofMatch = inner.match(/^(.+?)\s+of\s+(.+)$/i);
      if (ofMatch) {
        anPlusBStr = ofMatch[1].trim();
        ofSelector = ofMatch[2].trim();
      }

      const rule = parseAnPlusB(anPlusBStr);
      if (!rule) return false;

      let candidateSiblings = siblings;
      if (ofSelector) {
        // If node itself doesn't match ofSelector, it doesn't match :nth-child(... of <selector>)
        if (!matchesSelector(node, ofSelector, context)) return false;
        candidateSiblings = siblings.filter(s => matchesSelector(s, ofSelector, context));
      }

      const candidateIdx = candidateSiblings.indexOf(node);
      if (candidateIdx < 0) return false;
      const rank = isLast ? (candidateSiblings.length - candidateIdx) : (candidateIdx + 1);
      return rule.matches(rank);
    }

    // :not(<selector-list>)
    const notMatch = part.match(/^:not\((.+)\)$/i);
    if (notMatch) {
      const selectorList = splitSelectorList(notMatch[1]);
      for (const sel of selectorList) {
        if (matchesSelector(node, sel, context)) return false;
      }
      return true;
    }

    // :is(<selector-list>), :where(<selector-list>)
    const isMatch = part.match(/^:(is|where)\((.+)\)$/i);
    if (isMatch) {
      const selectorList = splitSelectorList(isMatch[2]);
      for (const sel of selectorList) {
        if (matchesSelector(node, sel, context)) return true;
      }
      return false;
    }
  }

  return false;
}

// Tokenize a compound selector into simple parts (tag, classes, ids, attrs, pseudos)
function splitCompoundSelector(compound) {
  const parts = [];
  let current = "";
  let inParen = 0;
  let inBracket = 0;

  for (let i = 0; i < compound.length; i++) {
    const ch = compound[i];
    if (ch === "(") inParen++;
    else if (ch === ")") inParen--;
    else if (ch === "[") inBracket++;
    else if (ch === "]") inBracket--;

    if (inParen === 0 && inBracket === 0) {
      if ((ch === "." || ch === "#" || ch === ":" || ch === "[") && current.length > 0) {
        parts.push(current);
        current = "";
      }
    }
    current += ch;
  }
  if (current.length > 0) parts.push(current);
  return parts;
}

// Matches a single compound selector (e.g. "div.card:first-child") against node
function matchesCompound(node, compound, context) {
  if (!node) return false;
  const parts = splitCompoundSelector(compound.trim());
  for (const part of parts) {
    if (!matchesSimpleSelector(node, part, context)) return false;
  }
  return true;
}

// Tokenize a complex selector by combinators: ' ', '>', '+', '~'
function parseComplexSelector(selector) {
  const tokens = [];
  let current = "";
  let inParen = 0;
  let inBracket = 0;
  const s = selector.trim();

  for (let i = 0; i < s.length; i++) {
    const ch = s[i];
    if (ch === "(") inParen++;
    else if (ch === ")") inParen--;
    else if (ch === "[") inBracket++;
    else if (ch === "]") inBracket--;

    if (inParen === 0 && inBracket === 0) {
      if (ch === ">" || ch === "+" || ch === "~") {
        if (current.trim()) tokens.push(current.trim());
        tokens.push(ch);
        current = "";
        continue;
      } else if (/\s/.test(ch)) {
        if (current.trim()) {
          tokens.push(current.trim());
          tokens.push(" ");
          current = "";
        }
        continue;
      }
    }
    current += ch;
  }
  if (current.trim()) tokens.push(current.trim());

  // Clean redundant whitespace tokens around explicit combinators
  const cleaned = [];
  for (let i = 0; i < tokens.length; i++) {
    const t = tokens[i];
    if (t === " ") {
      const prev = cleaned[cleaned.length - 1];
      const next = tokens[i + 1];
      if (prev === ">" || prev === "+" || prev === "~" || next === ">" || next === "+" || next === "~") {
        continue;
      }
    }
    cleaned.push(t);
  }
  return cleaned;
}

// Matches complex selector right-to-left
function matchComplex(node, tokens, context) {
  if (tokens.length === 0) return true;
  const lastIndex = tokens.length - 1;
  const targetCompound = tokens[lastIndex];

  if (!matchesCompound(node, targetCompound, context)) return false;
  if (tokens.length === 1) return true;

  const combinator = tokens[lastIndex - 1];
  const remainingTokens = tokens.slice(0, lastIndex - 1);

  if (combinator === ">") {
    // Child combinator
    return node.parent ? matchComplex(node.parent, remainingTokens, context) : false;
  } else if (combinator === " ") {
    // Descendant combinator
    let ancestor = node.parent;
    while (ancestor) {
      if (matchComplex(ancestor, remainingTokens, context)) return true;
      ancestor = ancestor.parent;
    }
    return false;
  } else if (combinator === "+") {
    // Next adjacent sibling
    if (!node.parent) return false;
    const siblings = node.parent.children;
    const idx = siblings.indexOf(node);
    if (idx <= 0) return false;
    return matchComplex(siblings[idx - 1], remainingTokens, context);
  } else if (combinator === "~") {
    // Subsequent sibling
    if (!node.parent) return false;
    const siblings = node.parent.children;
    const idx = siblings.indexOf(node);
    for (let i = idx - 1; i >= 0; i--) {
      if (matchComplex(siblings[i], remainingTokens, context)) return true;
    }
    return false;
  }

  return false;
}

export function matchesSelector(node, selectorStr, context = {}) {
  if (!node || !selectorStr) return false;
  const selectorList = splitSelectorList(selectorStr);
  for (const sel of selectorList) {
    const tokens = parseComplexSelector(sel);
    if (matchComplex(node, tokens, context)) return true;
  }
  return false;
}

export function querySelectorAllStructural(rootNode, selectorStr, context = {}) {
  const results = [];
  function walk(n) {
    if (!n) return;
    if (matchesSelector(n, selectorStr, context)) results.push(n);
    for (const child of n.children || []) walk(child);
  }
  walk(rootNode);
  return results;
}

export function expandNesting(parentSelector, nestedSelector) {
  const p = parentSelector.trim();
  const n = nestedSelector.trim();
  if (n.includes("&")) {
    return n.replace(/&/g, p);
  }
  // CSS Nesting relative combinators or direct selector
  if (n.startsWith(">") || n.startsWith("+") || n.startsWith("~")) {
    return `${p} ${n}`;
  }
  if (n.startsWith(":")) {
    return `${p}${n}`;
  }
  return `${p} ${n}`;
}

export function resolveNestedStyles(node, styleObj, context = {}) {
  if (!styleObj || typeof styleObj !== "object") return styleObj || {};
  const flatStyle = {};
  const nestedRules = [];

  for (const [key, value] of Object.entries(styleObj)) {
    if (value != null && typeof value === "object" && !Array.isArray(value)) {
      nestedRules.push([key, value]);
    } else {
      flatStyle[key] = value;
    }
  }

  for (const [sel, nestedObj] of nestedRules) {
    // If selector matches node, merge properties
    if (matchesSelector(node, sel, context)) {
      const resolvedSub = resolveNestedStyles(node, nestedObj, context);
      Object.assign(flatStyle, resolvedSub);
    }
  }

  return flatStyle;
}
