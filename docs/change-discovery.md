# Retained JavaScript change discovery

The bridge retains dirty identities independently of the native commit boundary.
Renderer writes mark an identity and its ancestor paths; they do not invalidate
every computed style or fingerprint the whole tree. Hover and active update only
the symmetric difference of their ancestry paths. Focus updates its old and new
identities. Input, popover and select state use the same mutation path.

## Selector dependencies

Stylesheet selectors are compiled once and indexed by a mandatory ID, class or
tag in their rightmost compound. Selectors without a mandatory key use a universal
bucket. Conditional rules and cascade-layer order are retained until stylesheet
or environment invalidation. Candidate selection never replaces full matching.

Matching records the identities and dependency kinds actually read, including
failed tests, unsuccessful ancestor searches and sibling-list reads. Hover,
active and focus have separate dependencies from properties. Property reads are
conservatively grouped per identity: changing one property can retest selectors
which read another property on that same identity. A class added to a node also
revisits its candidate buckets, so initially absent candidates can become active.
Logical pseudos retain reads from their nested matches, including failures.

Inline nested styles use the separate structural selector engine. Its parent,
sibling-list and property reads are tracked in a separate subscription channel.
This covers existing nth-child/of-type filtering, logical pseudos and supported
combinators without overwriting stylesheet dependencies. Removed/disposed
subtrees release their outgoing subscriptions; reinsertion rebuilds them.

The CSS file compiler still rejects `:has()`, structural pseudos and logical
pseudos outside its supported selector grammar. The programmatic stylesheet
matcher supports logical pseudos, but does not support `:has()` or nth selectors.
The inline nested matcher supports structural pseudos, but does not support
`:has()`. This change preserves these boundaries; it adds no CSS conformance
claim for selectors those engines reject.

## Inheritance, snapshots and packets

Stylesheet computation stops before matching when its dirty flag and retained
inputs permit reuse. Effective inherited values, resolved custom properties and
root font size have a separate version. A changed inheritance version revisits
direct children; propagation stops where the effective inherited signature is
unchanged. Explicit `inherit`/`var()` declarations conservatively depend on the
parent's computed version, so a parent change can revisit those direct dependent
children even when a particular referenced value did not change.

Snapshots retain their own version, dirty child identities and the context passed
to children. An ancestor whose own values did not change only refreshes affected
child references. Equal inherited values stop further snapshot recomputation.
Authored ownership masks remain part of native phase inputs even when the visible
value equals an inherited value. There is no recursive own-state/subtree JSON
fingerprint pass. Diagnostic `uiSnapshot()` still serializes the requested tree.

Topology mutations journal the moved/added/removed subtree roots. The identity
index visits those subtrees and checks their final attachment, including several
mutations before collection. Bridge collection flattens changed snapshots only;
it does not recursively walk retained snapshots to rediscover differences.
Phase comparison reads the schema fields and constructs only changed phase
projections. Those values and the serialized retry packet are retained.

Pending records are an overlay on acknowledged records. New mutations before an
acknowledgement are compared to the acknowledged state, removals stay pending,
and restoring acknowledged values cancels the corresponding delta. Native
acknowledgement applies the overlay; it does not clear newer renderer dirtiness.

## Deliberately conservative work

- Initial mount, stylesheet HMR/removal, environment/media/preferences changes,
  font/property registry changes, and the explicit unscoped `markTreeChanged()`
  escape hatch can recompute the whole tree.
- Select, details, slot and slot-host state can affect generated/distributed children.
  Preparation conservatively revisits the affected control subtree. This is
  bounded to that control or slot host, rather than to every host node. Slot
  distribution is rebuilt when its host is revisited, including reassignment.
- Reparenting revisits the moved subtree to rebuild ancestry dependencies.
  Retained child arrays are copied at changed ancestors; array indexing/order
  comparisons can still scale with a wide affected parent's child count.
- Standalone `snapshot(node)` calls outside the mounted root recompute their
  requested subtree, preserving support for plain mutable diagnostic/test nodes.
  Mounted mutations use renderer APIs, host dispatch, or `markTreeChanged()`;
  arbitrary unannounced writes to raw mounted objects are not observable.

## Regression evidence

`pnpm run test:hover` includes frozen native phase fixtures, cached-versus-cold
CSS parity and `tests/change-discovery.mjs`. The latter exercises hover/active/
focus ancestry, failed descendant and sibling matches, logical and inline
structural selectors, class/classList/id changes, inherited/custom properties,
input edits, insertion/reorder/reparent/removal/reinsertion, HMR, async Solid
effects, authored ownership and unacknowledged retry/coalescing/restoration.

The work-count fixture expands an unrelated branch from 32 to 512 elements
(each with a text child), with 256 unrelated selector buckets. Warm target
switching performs the same 8 preparation visits, 4 CSS computations, 10 compiled
candidate-selector tests, 4 snapshot computations and 4 bridge visits, with no membership visits.
Insertion performs 5 preparation visits, 2 CSS computations, 1 compiled selector test,
2 snapshot computations, 2 bridge visits and 1 membership visit at both sizes.
An unchanged transaction performs none of those operations. Counters count actual
preparation/computation/discovery visits, not shallow retained-array copies.

Run `node tools/profile-tictactoe-hover.mjs` for the actual optimized QuickJS
interpreter in the Zig Debug host. The fixture records work counts outside the
timed interval. Native timing results and exclusions are recorded in
`tictactoe-rendering-investigation.md`.
