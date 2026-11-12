let preferences = { colorScheme: "light", contrast: "no-preference", reducedMotion: "no-preference" };
export function getPreferences() { return {...preferences}; }
export function setPreferences(value) { Object.assign(preferences,value); }
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
  const preference = q.match(/^\(prefers-(color-scheme|contrast|reduced-motion)\s*:\s*([^)]*)\)$/i);
  if (preference) { const key = {"color-scheme":"colorScheme",contrast:"contrast","reduced-motion":"reducedMotion"}[preference[1].toLowerCase()]; return (env[key] ?? preferences[key]) === preference[2].trim().toLowerCase(); }
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

  if (/^update(?:\s*:|$)/i.test(q)) { const value = q.includes(":") ? q.slice(q.indexOf(":") + 1).trim().toLowerCase() : null; const actual = env.update || "fast"; const result = value ? value === actual : actual !== "none"; return negated ? !result : result; }
  if (/resolution|device-pixel-ratio/i.test(q)) { const result = resolutionMedia(q, env).matches; return negated ? !result : result; }
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

export function matchMedia(query, context = {}) {
  const listeners = new Set();
  const mql = {
    get matches() {
      return evaluateMediaQuery(query, context);
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
