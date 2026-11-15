import { bundleAsync } from "lightningcss";
import postcss from "postcss";
import { createRequire } from "node:module";
import { readFile } from "node:fs/promises";
import { dirname, resolve, isAbsolute, extname } from "node:path";
const require = createRequire(import.meta.url);
const { shorthandProperties } = require("cssstyle/lib/normalize.js");
const definitions = require("cssstyle/lib/generated/propertyDefinitions.js");
const { CSSStyleDeclaration } = require("cssstyle");
function declarations(decl) {
  const targets = leaves(decl.prop);
  if (
    targets.length > 1 &&
    !/var\(/.test(decl.value) &&
    !["initial", "inherit", "unset", "revert", "revert-layer"].includes(
      decl.value,
    )
  ) {
    const style = new CSSStyleDeclaration();
    style.setProperty(decl.prop, decl.value);
    return targets
      .map((property) => ({
        property,
        value: style.getPropertyValue(property),
        important: !!decl.important,
        leaves: [property],
      }))
      .filter((d) => d.value);
  }
  return [
    {
      property: decl.prop,
      value: decl.value,
      important: !!decl.important,
      leaves: targets,
    },
  ];
}

function leaves(property) {
  if (property === "all")
    return [...definitions.keys()].filter(
      (p) =>
        !p.startsWith("-") &&
        !["all", "direction", "unicode-bidi"].includes(p) &&
        !shorthandProperties.has(p),
    );
  const entry = shorthandProperties.get(property);
  return entry ? [...entry.shorthandFor.keys()].flatMap(leaves) : [property];
}

// Lightning owns stylesheet syntax, @import ordering and URL source locations.
// PostCSS reads its normalized output so native consumers receive CSS strings,
// not a dependency on Lightning's version-specific typed value representation.
export async function compileCss(filename, root, watch = () => {}) {
  if (/\.module\.css$/i.test(filename))
    throw Error(
      "Native CSS Modules are not supported; import a normal .css file",
    );
  const result = await bundleAsync({
    filename,
    minify: false,
    analyzeDependencies: true,
    resolver: {
      read: async (file) => {
        watch(file);
        return readFile(file, "utf8");
      },
      resolve: (specifier, from) => {
        if (/^(https?:)?\/\//i.test(specifier))
          throw Error(
            "Remote CSS @import is unsupported; use a local stylesheet",
          );
        return specifier.startsWith("/")
          ? resolve(root, "." + specifier)
          : resolve(dirname(from), specifier);
      },
    },
  });
  let css = result.code.toString();
  for (const dep of result.dependencies || []) {
    if (dep.type !== "url") continue;
    let url = dep.url;
    if (/^(?:https?:)?\/\//i.test(url))
      throw Error(
        "Remote CSS assets are unsupported; use local url() resources",
      );
    if (!/^(?:data:|https?:|#)/i.test(url)) {
      const clean = decodeURIComponent(url.split(/[?#]/)[0]);
      const path =
        isAbsolute(clean) && !clean.startsWith("/")
          ? clean
          : clean.startsWith("/")
            ? resolve(root, "public", "." + clean)
            : resolve(dirname(dep.loc.filePath), clean);
      watch(path);
      const data = await readFile(path);
      const extension = extname(path).toLowerCase();
      const mime =
        {
          ".png": "image/png",
          ".jpg": "image/jpeg",
          ".jpeg": "image/jpeg",
          ".svg": "image/svg+xml",
          ".webp": "image/webp",
          ".gif": "image/gif",
          ".ttf": "font/ttf",
          ".woff2": "font/woff2",
          ".cur": "image/x-icon",
        }[extension] || "application/octet-stream";
      // Embed bytes, making dev and production independent of HTTP and cwd.
      url = `data:${mime};base64,${data.toString("base64")}`;
    }
    css = css.replaceAll(dep.placeholder, url);
  }
  function rules(nodes) {
    return nodes
      .filter((n) => n.type !== "comment")
      .map((n) => {
        if (n.type === "rule") {
          if (
            !/^(?:(?:[a-zA-Z_][\w-]*|\*|[.#][\w-]+|:(?:root|hover|focus|active|disabled|enabled|checked|empty))|[\s>+~,])+$/.test(
              n.selector,
            )
          )
            throw Error(`Unsupported native CSS selector: ${n.selector}`);
          return {
            selector: n.selector,
            declarations: n.nodes
              .filter((d) => d.type === "decl")
              .flatMap(declarations),
          };
        }
        if (
          n.type === "atrule" &&
          ["media", "supports", "layer"].includes(n.name)
        )
          return {
            condition: n.name,
            query: n.params,
            rules: rules(n.nodes || []),
          };
        throw Error(
          `Native stylesheet rule is not supported: ${n.toString().slice(0, 100)}`,
        );
      });
  }
  return rules(postcss.parse(css, { from: filename }).nodes);
}
