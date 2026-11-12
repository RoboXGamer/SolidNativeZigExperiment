// CSS Selectors Level 4 Engine with :where(), user-action pseudos, and WebVTT cue support.

/**
 * Checks HTML5 constraint validation on a node.
 * Returns true if valid, false if invalid.
 */
export function checkValidity(node) {
  if (!node || !node.props) return true;
  if (typeof node.props.validity?.valid === "boolean") return node.props.validity.valid;
  if (node.props.invalid === true) return false;
  if (node.props.valid === false) return false;

  const value = node.type === "input"
    ? String(node.props.value ?? "")
    : (node.type === "select" && typeof node._value !== "undefined" ? String(node._value) : String(node.props.value ?? ""));

  if (node.props.required) {
    if (!value || value.trim().length === 0) return false;
  }

  if (node.props.pattern && value) {
    try {
      const reg = new RegExp(`^(?:${node.props.pattern})$`);
      if (!reg.test(value)) return false;
    } catch {
      return false;
    }
  }

  if (node.props.type === "email" && value) {
    const emailReg = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailReg.test(value)) return false;
  }

  if (node.props.min != null && value !== "") {
    const n = Number(value);
    if (!isNaN(n) && n < Number(node.props.min)) return false;
  }

  if (node.props.max != null && value !== "") {
    const n = Number(value);
    if (!isNaN(n) && n > Number(node.props.max)) return false;
  }

  return true;
}

/**
 * Splits a comma-separated selector list respecting parentheses and brackets.
 */
export function splitSelectorList(input) {
  const list = [];
  let depth = 0;
  let start = 0;
  for (let i = 0; i < input.length; i++) {
    const c = input[i];
    if (c === "(" || c === "[") depth++;
    else if (c === ")" || c === "]") { if (depth > 0) depth--; }
    else if (c === "," && depth === 0) {
      const part = input.slice(start, i).trim();
      if (part) list.push(part);
      start = i + 1;
    }
  }
  const last = input.slice(start).trim();
  if (last) list.push(last);
  return list;
}

/**
 * Tokenizes a single complex selector into compound items and combinators.
 */
export function parseComplexSelector(str) {
  const tokens = [];
  let i = 0;
  const s = str.trim();
  while (i < s.length) {
    // Check combinators
    while (i < s.length && /\s/.test(s[i])) i++;
    if (i >= s.length) break;

    let combinator = " ";
    if (s[i] === ">" || s[i] === "+" || s[i] === "~") {
      combinator = s[i];
      i++;
      while (i < s.length && /\s/.test(s[i])) i++;
    } else if (tokens.length > 0 && /\s/.test(s[i - 1])) {
      combinator = " ";
    }

    // Read compound selector
    const start = i;
    let depth = 0;
    while (i < s.length) {
      const c = s[i];
      if (c === "(" || c === "[") depth++;
      else if (c === ")" || c === "]") { if (depth > 0) depth--; }
      else if (depth === 0 && (/\s/.test(c) || c === ">" || c === "+" || c === "~")) {
        break;
      }
      i++;
    }
    const compoundStr = s.slice(start, i).trim();
    if (compoundStr) {
      tokens.push({ combinator, compound: parseCompoundSelector(compoundStr) });
    }
  }
  return tokens;
}

/**
 * Parses a single compound selector (e.g. "input.form-control:where(.btn, :focus):user-valid")
 */
export function parseCompoundSelector(str) {
  const parts = [];
  let i = 0;
  while (i < str.length) {
    if (str[i] === "#") {
      // ID
      i++;
      const start = i;
      while (i < str.length && /[a-zA-Z0-9_\-]/.test(str[i])) i++;
      parts.push({ type: "id", value: str.slice(start, i) });
    } else if (str[i] === ".") {
      // Class
      i++;
      const start = i;
      while (i < str.length && /[a-zA-Z0-9_\-]/.test(str[i])) i++;
      parts.push({ type: "class", value: str.slice(start, i) });
    } else if (str[i] === "[") {
      // Attribute
      i++;
      const start = i;
      while (i < str.length && str[i] !== "]") i++;
      const attrStr = str.slice(start, i);
      if (str[i] === "]") i++;
      const eqIdx = attrStr.indexOf("=");
      if (eqIdx >= 0) {
        const name = attrStr.slice(0, eqIdx).replace(/[~|^$*]$/, "").trim();
        const rawVal = attrStr.slice(eqIdx + 1).trim();
        const value = rawVal.replace(/^['"]|['"]$/g, "");
        parts.push({ type: "attribute", name, value, op: "=" });
      } else {
        parts.push({ type: "attribute", name: attrStr.trim() });
      }
    } else if (str.startsWith("::cue", i)) {
      // WebVTT cue pseudo-element
      i += 5;
      if (str[i] === "(") {
        i++;
        let depth = 1;
        const start = i;
        while (i < str.length && depth > 0) {
          if (str[i] === "(") depth++;
          else if (str[i] === ")") depth--;
          if (depth === 0) break;
          i++;
        }
        const inner = str.slice(start, i).trim();
        if (str[i] === ")") i++;
        parts.push({ type: "cue", argument: inner });
      } else {
        parts.push({ type: "cue" });
      }
    } else if (str[i] === ":") {
      // Pseudo-class
      i++;
      const start = i;
      while (i < str.length && /[a-zA-Z0-9_\-]/.test(str[i])) i++;
      const name = str.slice(start, i).toLowerCase();
      let argument = null;
      if (i < str.length && str[i] === "(") {
        i++;
        let depth = 1;
        const argStart = i;
        while (i < str.length && depth > 0) {
          if (str[i] === "(") depth++;
          else if (str[i] === ")") depth--;
          if (depth === 0) break;
          i++;
        }
        argument = str.slice(argStart, i).trim();
        if (str[i] === ")") i++;
      }
      parts.push({ type: "pseudo", name, argument });
    } else if (str[i] === "*") {
      i++;
      parts.push({ type: "universal" });
    } else {
      // Type / tag
      const start = i;
      while (i < str.length && /[a-zA-Z0-9_\-]/.test(str[i])) i++;
      const tag = str.slice(start, i).toLowerCase();
      if (tag) parts.push({ type: "tag", value: tag });
    }
  }
  return parts;
}

/**
 * Calculates specificity [a, b, c] for a selector.
 * Note: :where() always contributes [0, 0, 0]!
 */
export function specificity(selectorStr) {
  const list = splitSelectorList(selectorStr);
  let maxSpec = [0, 0, 0];
  for (const item of list) {
    const complex = parseComplexSelector(item);
    let spec = [0, 0, 0];
    for (const tok of complex) {
      for (const part of tok.compound) {
        if (part.type === "id") {
          spec[0]++;
        } else if (part.type === "class" || part.type === "attribute") {
          spec[1]++;
        } else if (part.type === "tag" || part.type === "cue") {
          spec[2]++;
        } else if (part.type === "pseudo") {
          if (part.name === "where") {
            // :where() has ZERO specificity!
          } else if (part.name === "is" || part.name === "not") {
            if (part.argument) {
              const innerSpec = specificity(part.argument);
              spec[0] += innerSpec[0];
              spec[1] += innerSpec[1];
              spec[2] += innerSpec[2];
            }
          } else {
            // standard pseudo-class (:user-valid, :user-invalid, :focus, etc.)
            spec[1]++;
          }
        }
      }
    }
    if (compareSpecificity(spec, maxSpec) > 0) {
      maxSpec = spec;
    }
  }
  return maxSpec;
}

export function compareSpecificity(s1, s2) {
  if (s1[0] !== s2[0]) return s1[0] - s2[0];
  if (s1[1] !== s2[1]) return s1[1] - s2[1];
  return s1[2] - s2[2];
}

/**
 * Tests if a node matches a single compound selector.
 */
function matchesCompound(node, parts) {
  if (!node) return false;
  for (const part of parts) {
    if (part.type === "tag") {
      if (node.type.toLowerCase() !== part.value) return false;
    } else if (part.type === "id") {
      if (node.props.id !== part.value) return false;
    } else if (part.type === "class") {
      const cls = node.props.class ?? node.props.className ?? "";
      const classes = String(cls).split(/\s+/);
      if (!classes.includes(part.value)) return false;
    } else if (part.type === "attribute") {
      if (!(part.name in node.props)) return false;
      if (part.op === "=" && String(node.props[part.name]) !== part.value) return false;
    } else if (part.type === "cue") {
      // Matches WebVTT cue or track elements
      const isCue = node.type === "cue" || node.type === "vtt-cue" || node.props.cue || node.props["data-cue"] || (node.parent && node.parent.type === "track");
      if (!isCue) return false;
      if (part.argument) {
        if (!matches(node, part.argument)) return false;
      }
    } else if (part.type === "pseudo") {
      if (part.name === "user-valid") {
        if (!node._userInteracted) return false;
        if (!checkValidity(node)) return false;
      } else if (part.name === "user-invalid") {
        if (!node._userInteracted) return false;
        if (checkValidity(node)) return false;
      } else if (part.name === "where") {
        // Forgiving selector list: evaluate each argument; if invalid, skip it!
        if (!part.argument) return false;
        const subList = splitSelectorList(part.argument);
        let matched = false;
        for (const sub of subList) {
          try {
            if (matches(node, sub)) {
              matched = true;
              break;
            }
          } catch {
            // Forgiving selector list ignores invalid selectors!
          }
        }
        if (!matched) return false;
      } else if (part.name === "is") {
        if (!part.argument) return false;
        const subList = splitSelectorList(part.argument);
        let matched = false;
        for (const sub of subList) {
          try {
            if (matches(node, sub)) {
              matched = true;
              break;
            }
          } catch {}
        }
        if (!matched) return false;
      } else if (part.name === "not") {
        if (part.argument && matches(node, part.argument)) return false;
      } else if (part.name === "focus") {
        if (!node._focused) return false;
      } else if (part.name === "disabled") {
        if (!node.props.disabled) return false;
      } else if (part.name === "enabled") {
        if (node.props.disabled) return false;
      } else if (part.name === "checked") {
        if (!node.props.checked && !node.props.selected) return false;
      } else if (part.name === "empty") {
        if (node.children && node.children.length > 0) return false;
        if (node.text && node.text.length > 0) return false;
      }
    }
  }
  return true;
}

/**
 * Tests if node matches complex selector tokens (from right to left).
 */
function matchesComplexTokens(node, tokens) {
  if (tokens.length === 0) return true;
  let currNode = node;
  let tokenIdx = tokens.length - 1;

  if (!matchesCompound(currNode, tokens[tokenIdx].compound)) return false;

  while (tokenIdx > 0) {
    const comb = tokens[tokenIdx].combinator;
    tokenIdx--;
    const prevCompound = tokens[tokenIdx].compound;

    if (comb === ">") {
      // Child combinator
      currNode = currNode.parent;
      if (!currNode || !matchesCompound(currNode, prevCompound)) return false;
    } else if (comb === " ") {
      // Descendant combinator
      let parent = currNode.parent;
      let found = false;
      while (parent) {
        if (matchesCompound(parent, prevCompound)) {
          currNode = parent;
          found = true;
          break;
        }
        parent = parent.parent;
      }
      if (!found) return false;
    } else if (comb === "+") {
      // Adjacent sibling
      if (!currNode.parent) return false;
      const idx = currNode.parent.children.indexOf(currNode);
      if (idx <= 0) return false;
      currNode = currNode.parent.children[idx - 1];
      if (!matchesCompound(currNode, prevCompound)) return false;
    } else if (comb === "~") {
      // Subsequent sibling
      if (!currNode.parent) return false;
      const idx = currNode.parent.children.indexOf(currNode);
      if (idx <= 0) return false;
      let found = false;
      for (let sIdx = idx - 1; sIdx >= 0; sIdx--) {
        const sib = currNode.parent.children[sIdx];
        if (matchesCompound(sib, prevCompound)) {
          currNode = sib;
          found = true;
          break;
        }
      }
      if (!found) return false;
    }
  }
  return true;
}

/**
 * Public match API: checks if node matches selectorStr.
 */
export function matches(node, selectorStr) {
  if (!node || !selectorStr) return false;
  const list = splitSelectorList(selectorStr);
  for (const item of list) {
    const tokens = parseComplexSelector(item);
    if (tokens.length > 0 && matchesComplexTokens(node, tokens)) {
      return true;
    }
  }
  return false;
}

/**
 * Compiles a list of style rules { selector, style } and sorts by specificity.
 */
export function compileStyleSheet(ruleList) {
  const compiled = [];
  let order = 0;
  for (const r of ruleList) {
    compiled.push({
      selector: r.selector,
      style: r.style,
      specificity: specificity(r.selector),
      order: order++,
    });
  }
  return compiled;
}

/**
 * Matches and merges style rules onto a node.
 */
export function applySelectorStyles(node, compiledRules) {
  const matching = [];
  for (const rule of compiledRules) {
    if (matches(node, rule.selector)) {
      matching.push(rule);
    }
  }
  matching.sort((a, b) => {
    const cmp = compareSpecificity(a.specificity, b.specificity);
    if (cmp !== 0) return cmp;
    return a.order - b.order;
  });

  const merged = {};
  for (const m of matching) {
    Object.assign(merged, m.style);
  }
  return merged;
}
