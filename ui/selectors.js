/**
 * CSS Selectors engine for Solid Native Zig.
 * Covers CSS Selectors 3/4 Core, :scope, and ::part:
 * - Types and namespaces: E, ns|E, *|E, |E
 * - Universal and namespaces: *, ns|*, *|*, |*
 * - Attributes: [attr], [attr=val], [attr~=val], [attr|=val], [attr^=val], [attr$=val], [attr*=val], [attr=val i], [attr=val s]
 * - Classes: .class
 * - IDs: #id
 * - Combinators: descendant (' '), child ('>'), next-sibling ('+'), subsequent-sibling ('~')
 * - Selector lists: A, B
 * - Pseudo-classes: :scope
 * - Pseudo-elements: ::part(ident)
 */

export function calculateSpecificity(selectorStr) {
  const parsed = parseSelectorList(selectorStr);
  let max = [0, 0, 0];
  for (const sel of parsed) {
    const spec = [0, 0, 0];
    for (const step of sel) {
      if (step.id) spec[0]++;
      if (step.classes) spec[1] += step.classes.length;
      if (step.attributes) spec[1] += step.attributes.length;
      if (step.isScope) spec[1]++;
      if (step.type) spec[2]++;
      if (step.part) spec[2]++;
    }
    if (compareSpecificity(spec, max) > 0) {
      max = spec;
    }
  }
  return max;
}

export function compareSpecificity(a, b) {
  if (a[0] !== b[0]) return a[0] - b[0];
  if (a[1] !== b[1]) return a[1] - b[1];
  return a[2] - b[2];
}

function parseAttributes(raw) {
  const attrs = [];
  const regex = /\[\s*(?:([\w-]+|\*)\|)?([\w-]+)\s*(?:([~|^$*]?=)\s*(?:"([^"]*)"|'([^']*)'|([^\]\s]+))\s*([is])?)?\s*\]/g;
  let match;
  while ((match = regex.exec(raw)) !== null) {
    const ns = match[1];
    const name = match[2];
    const op = match[3] || "exists";
    const val = match[4] ?? match[5] ?? match[6] ?? "";
    const flag = match[7];
    attrs.push({
      namespace: ns,
      name,
      op,
      value: val,
      caseInsensitive: flag === "i" || (flag !== "s" && ["class", "id", "type"].includes(name.toLowerCase())),
    });
  }
  return attrs;
}

function parseCompound(str) {
  let s = str.trim();
  if (!s) return null;

  const result = {
    namespace: null,
    type: null,
    id: null,
    classes: [],
    attributes: [],
    isScope: false,
    part: null,
  };

  // ::part(ident)
  const partMatch = s.match(/::part\(\s*([\w-]+)\s*\)/);
  if (partMatch) {
    result.part = partMatch[1];
    s = s.replace(partMatch[0], "");
  }

  // :scope
  if (s.includes(":scope")) {
    result.isScope = true;
    s = s.replace(/:scope/g, "");
  }

  // Attributes [...]
  result.attributes = parseAttributes(s);
  s = s.replace(/\[[^\]]+\]/g, "");

  // Classes .class
  const classMatches = s.match(/\.([\w-]+)/g);
  if (classMatches) {
    result.classes = classMatches.map(c => c.slice(1));
    s = s.replace(/\.[\w-]+/g, "");
  }

  // ID #id
  const idMatch = s.match(/#([\w-]+)/);
  if (idMatch) {
    result.id = idMatch[1];
    s = s.replace(/#[\w-]+/g, "");
  }

  // Type / Tag with optional namespace: ns|tag, *|tag, |tag, tag, *
  s = s.trim();
  if (s.length > 0) {
    const nsTagMatch = s.match(/^(?:([\w-]+|\*)\|)?([\w-]+|\*)$/);
    if (nsTagMatch) {
      result.namespace = nsTagMatch[1] ?? null;
      const tag = nsTagMatch[2];
      if (tag !== "*") {
        result.type = tag;
      }
    } else if (s !== "*") {
      result.type = s;
    }
  }

  return result;
}

export function parseSelectorList(selectorText) {
  const lists = [];
  const rawSelectors = splitSelectorList(selectorText);

  for (const raw of rawSelectors) {
    const steps = [];
    const tokens = tokenizeSelector(raw);
    for (let i = 0; i < tokens.length; i++) {
      const tok = tokens[i];
      if (tok === ">" || tok === "+" || tok === "~") {
        if (steps.length > 0) {
          steps[steps.length - 1].combinator = tok;
        }
      } else if (tok === " ") {
        if (steps.length > 0 && !steps[steps.length - 1].combinator) {
          steps[steps.length - 1].combinator = " ";
        }
      } else {
        const compound = parseCompound(tok);
        if (compound) {
          steps.push(compound);
        }
      }
    }
    if (steps.length > 0) {
      lists.push(steps);
    }
  }

  return lists;
}

function splitSelectorList(str) {
  const parts = [];
  let depth = 0;
  let inQuote = false;
  let quoteChar = "";
  let start = 0;

  for (let i = 0; i < str.length; i++) {
    const c = str[i];
    if (inQuote) {
      if (c === quoteChar) inQuote = false;
    } else if (c === "'" || c === '"') {
      inQuote = true;
      quoteChar = c;
    } else if (c === "(" || c === "[") {
      depth++;
    } else if (c === ")" || c === "]") {
      depth = Math.max(0, depth - 1);
    } else if (c === "," && depth === 0) {
      parts.push(str.slice(start, i).trim());
      start = i + 1;
    }
  }
  if (start < str.length) {
    const remainder = str.slice(start).trim();
    if (remainder) parts.push(remainder);
  }
  return parts;
}

function tokenizeSelector(str) {
  const tokens = [];
  let current = "";
  let inBracket = 0;
  let inParen = 0;
  let inQuote = false;
  let quoteChar = "";

  for (let i = 0; i < str.length; i++) {
    const c = str[i];
    if (inQuote) {
      current += c;
      if (c === quoteChar) inQuote = false;
    } else if (c === "'" || c === '"') {
      inQuote = true;
      quoteChar = c;
      current += c;
    } else if (c === "[") {
      inBracket++;
      current += c;
    } else if (c === "]") {
      inBracket = Math.max(0, inBracket - 1);
      current += c;
    } else if (c === "(") {
      inParen++;
      current += c;
    } else if (c === ")") {
      inParen = Math.max(0, inParen - 1);
      current += c;
    } else if (inBracket === 0 && inParen === 0) {
      if (c === ">" || c === "+" || c === "~") {
        if (current.trim()) tokens.push(current.trim());
        tokens.push(c);
        current = "";
      } else if (/\s/.test(c)) {
        if (current.trim()) {
          tokens.push(current.trim());
          tokens.push(" ");
          current = "";
        }
      } else {
        current += c;
      }
    } else {
      current += c;
    }
  }
  if (current.trim()) {
    tokens.push(current.trim());
  }

  // Filter out redundant consecutive spaces
  const cleaned = [];
  for (let i = 0; i < tokens.length; i++) {
    const t = tokens[i];
    if (t === " ") {
      if (cleaned.length === 0 || [">", "+", "~", " "].includes(cleaned[cleaned.length - 1])) {
        continue;
      }
      if (i + 1 < tokens.length && [">", "+", "~"].includes(tokens[i + 1])) {
        continue;
      }
    }
    cleaned.push(t);
  }
  return cleaned;
}

export function getNodeAttr(node, name) {
  if (!node || !node.props) return null;
  if (name === "id") {
    return node.props.id != null ? String(node.props.id) : (node.id != null ? String(node.id) : null);
  }
  if (name === "class" || name === "className") {
    return node.props.class ?? node.props.className ?? null;
  }
  if (name === "type") {
    return node.type ?? null;
  }
  if (name === "value") {
    return node.props.value != null ? String(node.props.value) : (node.value ?? null);
  }
  if (name === "part") {
    return node.props.part ?? null;
  }
  return node.props[name] != null ? String(node.props[name]) : null;
}

export function matchCompound(node, compound, scopeNode = null) {
  if (!node) return false;

  // :scope
  if (compound.isScope) {
    if (!scopeNode || node !== scopeNode) return false;
  }

  // Tag / type
  if (compound.type) {
    if (node.type.toLowerCase() !== compound.type.toLowerCase()) return false;
  }

  // ID
  if (compound.id) {
    const idVal = getNodeAttr(node, "id");
    if (idVal !== compound.id) return false;
  }

  // Classes
  if (compound.classes.length > 0) {
    const classVal = getNodeAttr(node, "class") || "";
    const classList = classVal.trim().split(/\s+/);
    for (const cls of compound.classes) {
      if (!classList.includes(cls)) return false;
    }
  }

  // ::part(ident)
  if (compound.part) {
    const partVal = getNodeAttr(node, "part") || "";
    const partList = partVal.trim().split(/\s+/);
    if (!partList.includes(compound.part)) return false;
  }

  // Attributes
  for (const attr of compound.attributes) {
    const actual = getNodeAttr(node, attr.name);
    if (attr.op === "exists") {
      if (actual == null) return false;
    } else {
      if (actual == null) return false;
      const act = attr.caseInsensitive ? actual.toLowerCase() : actual;
      const exp = attr.caseInsensitive ? attr.value.toLowerCase() : attr.value;
      if (attr.op === "=") {
        if (act !== exp) return false;
      } else if (attr.op === "~=") {
        const words = act.trim().split(/\s+/);
        if (!words.includes(exp)) return false;
      } else if (attr.op === "|=") {
        if (act !== exp && !act.startsWith(exp + "-")) return false;
      } else if (attr.op === "^=") {
        if (!act.startsWith(exp)) return false;
      } else if (attr.op === "$=") {
        if (!act.endsWith(exp)) return false;
      } else if (attr.op === "*=") {
        if (!act.includes(exp)) return false;
      }
    }
  }

  return true;
}

export function matches(node, selectorText, scopeNode = null) {
  if (!node || !selectorText) return false;
  const lists = parseSelectorList(selectorText);
  if (lists.length === 0) return false;

  for (const steps of lists) {
    if (matchComplexBackwards(node, steps, steps.length - 1, scopeNode)) {
      return true;
    }
  }
  return false;
}

function matchComplexBackwards(node, steps, stepIdx, scopeNode) {
  if (stepIdx < 0) return true;
  if (!node) return false;

  const currentStep = steps[stepIdx];
  if (!matchCompound(node, currentStep, scopeNode)) return false;
  if (stepIdx === 0) return true;

  const prevStep = steps[stepIdx - 1];
  const combinator = prevStep.combinator || " ";

  if (combinator === ">") {
    // Child: immediate parent
    return matchComplexBackwards(node.parent, steps, stepIdx - 1, scopeNode);
  } else if (combinator === " ") {
    // Descendant: any ancestor
    let ancestor = node.parent;
    while (ancestor) {
      if (matchComplexBackwards(ancestor, steps, stepIdx - 1, scopeNode)) {
        return true;
      }
      ancestor = ancestor.parent;
    }
    return false;
  } else if (combinator === "+") {
    // Next sibling: immediately preceding sibling in parent's children
    if (!node.parent) return false;
    const siblings = node.parent.children;
    const idx = siblings.indexOf(node);
    if (idx > 0) {
      return matchComplexBackwards(siblings[idx - 1], steps, stepIdx - 1, scopeNode);
    }
    return false;
  } else if (combinator === "~") {
    // Subsequent sibling: any preceding sibling in parent's children
    if (!node.parent) return false;
    const siblings = node.parent.children;
    const idx = siblings.indexOf(node);
    for (let i = idx - 1; i >= 0; i--) {
      if (matchComplexBackwards(siblings[i], steps, stepIdx - 1, scopeNode)) {
        return true;
      }
    }
    return false;
  }

  return false;
}

export function querySelector(rootNode, selectorText) {
  if (!rootNode) return null;
  const list = [];
  walkTree(rootNode, (n) => {
    if (n !== rootNode && matches(n, selectorText, rootNode)) {
      list.push(n);
      return true; // Stop after first match
    }
    return false;
  });
  return list[0] ?? null;
}

export function querySelectorAll(rootNode, selectorText) {
  if (!rootNode) return [];
  const list = [];
  walkTree(rootNode, (n) => {
    if (n !== rootNode && matches(n, selectorText, rootNode)) {
      list.push(n);
    }
    return false;
  });
  return list;
}

export function closest(node, selectorText) {
  let cur = node;
  while (cur) {
    if (matches(cur, selectorText, cur)) return cur;
    cur = cur.parent;
  }
  return null;
}

function walkTree(node, callback) {
  if (!node) return;
  for (const child of node.children || []) {
    if (callback(child)) return;
    walkTree(child, callback);
  }
}

export { NamespaceRegistry, parseAnPlusB, matchesSelector, expandNesting, resolveNestedStyles } from "./selectors-structural.js";

export {checkValidity, specificity, splitSelectorList, parseComplexSelector, parseCompoundSelector, compileStyleSheet, applySelectorStyles} from "./selectors-user.js";
