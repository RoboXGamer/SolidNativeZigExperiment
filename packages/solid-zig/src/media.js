/**
 * CSS Media Queries evaluator for Solid Native Zig.
 * Implements @media (scripting: none | initial-only | enabled)
 * per CSS Media Queries 5.
 */

let globalScriptingState = "enabled"; // "none" | "initial-only" | "enabled"

export function setScriptingState(state) {
  if (["none", "initial-only", "enabled"].includes(state)) {
    globalScriptingState = state;
  }
}

export function getScriptingState() {
  return globalScriptingState;
}

export function evaluateMediaQuery(queryString, env = {}) {
  let q = queryString.trim();
  if (q.startsWith("@media")) {
    q = q.slice(6).trim();
  }

  let negated = false;
  if (/^not\s+/i.test(q)) {
    negated = true;
    q = q.replace(/^not\s+/i, "").trim();
  }

  // Strip wrapping parentheses
  if (q.startsWith("(") && q.endsWith(")")) {
    q = q.slice(1, -1).trim();
  }

  const scripting = env.scripting || globalScriptingState;

  // Check for scripting media feature
  if (/^scripting/i.test(q)) {
    const colonIdx = q.indexOf(":");
    let res = false;
    if (colonIdx >= 0) {
      const val = q.slice(colonIdx + 1).trim().toLowerCase();
      res = (val === scripting);
    } else {
      // (scripting) boolean query: true if scripting is available/enabled (not "none")
      res = (scripting !== "none");
    }
    return negated ? !res : res;
  }

  // Handle generic media types: "all", "screen"
  if (q.toLowerCase() === "all" || q.toLowerCase() === "screen") {
    return !negated;
  }
  if (q.toLowerCase() === "print") {
    return negated;
  }

  return negated ? true : false;
}

export function matchMedia(query) {
  const listeners = new Set();
  const mql = {
    get matches() {
      return evaluateMediaQuery(query);
    },
    media: query,
    addEventListener(type, listener) {
      if (type === "change" && typeof listener === "function") {
        listeners.add(listener);
      }
    },
    removeEventListener(type, listener) {
      if (type === "change") {
        listeners.delete(listener);
      }
    },
    addListener(listener) {
      this.addEventListener("change", listener);
    },
    removeListener(listener) {
      this.removeEventListener("change", listener);
    },
    dispatchEvent(event) {
      for (const fn of listeners) {
        fn(event);
      }
      return true;
    },
  };
  return mql;
}
