# Solid → Zig adapter

Solid 2.0.0-rc.21's universal renderer targets a retained host tree. The adapter
normalizes style objects, batches changed nodes, acknowledges native commits,
and dispatches input by stable node ID. Solid's own client runtime supplies its
reactivity, stores, lifecycle actions, contexts, lazy modules and control flow.

The root Vite configuration aliases `@zig-ui/solid` and
`@zig-ui/solid/renderer` to this package's source. With the package linked in a
consumer, configure `@solidjs/vite-plugin` with
`{ solid: { generate: "universal", moduleName: "@zig-ui/solid/renderer" } }`.
Use TypeScript `jsx: "preserve"` and `jsxImportSource: "@zig-ui/solid"` for the
native JSX declarations. Browser DOM type declarations do not describe these
elements. JSX styles are the supported native subset rather than full CSS.

```jsx
import { createSignal } from "solid-js";
import { mountApp } from "@zig-ui/solid";

function App() {
  const [name, setName] = createSignal("");
  return <column style={{ gap: 12, padding: 24 }}>
    <input value={name()} onInput={event => setName(event.target.value)} />
    <label>Hello {name()}</label>
  </column>;
}

mountApp(App);
```

The development module host loads the application dependency graph compiled by
Vite. It supports static imports, re-exports, literal dynamic imports, cached
module exports and hot lifecycle data. Solid Refresh owns component proxies;
local component state can reset on replacement according to Solid semantics.
Unaccepted helper changes propagate to importers; deleted modules are pruned.
Node built-ins, arbitrary computed module specifiers and browser DOM packages
require additional host integrations.

This package remains private while its API and native integration are being
developed. The latest integration edits have not yet been runtime-validated.
