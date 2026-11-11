// Builds documentation from source-review judgments. Does not import/run the UI.
import { readFile, writeFile } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { fileURLToPath } from "node:url";
const root = new URL("../", import.meta.url);
const output = new URL("docs/audit/", root);
const categories = [
  ["box", "Box model and sizing", [
    [0,"Distinct auto, zero and indefinite sizes","Zero is currently the unspecified sentinel; BOX-01."],
    [.5,"Definite width and height","Numeric values reach layout; box and clamp semantics are incomplete; BOX-04/05/06."],
    [.5,"Minimum and maximum constraints","Present, but inconsistent precedence and parent accounting; BOX-06."],
    [.5,"Content-box and border-box","Horizontal block width has an adjustment; flex and height paths lack a common rule; BOX-05."],
    [.5,"Padding and border side resolution","Positive sides work; explicit zero and control defaults fail CSS semantics; BOX-02."],
    [.5,"Margin shorthand, negative and auto values","Some paths work; -1 collides with auto and zero overrides are lost; BOX-02/03."],
    [0,"Single ownership of outer margins","Node margins are also deducted/added inside that node; BOX-04."],
    [.5,"Aspect-ratio sizing","Only fills a numerically zero height, without size-transfer rules; BOX-07."],
    [0,"Percentages, relative units and intrinsic size keywords","Missing typed length resolution; BOX-09."],
    [0,"Logical sizes and edges","No writing-mode/direction-dependent edge resolution."]]],
  ["flex", "Flex layout", [
    [1,"Numeric axes, reverse directions and stable order","Dedicated code paths exist; this is narrow source presence, not CSS certification."],
    [.5,"Line collection and wrap-reverse","Wrap exists; indefinite sizing and one-line reverse need correction; FLEX-04."],
    [.5,"Flex basis and hypothetical sizes","Basis variants exist but raw and hypothetical sizes are conflated; FLEX-02/07."],
    [.5,"Flexible-length distribution and freezing","Proportional distribution exists; factors below one and violation handling differ; FLEX-01/02."],
    [.5,"Automatic minima and scaled shrinking","Approximation exists; explicit zero minimum and box contributions are wrong; BOX-01, FLEX-03."],
    [.5,"Justification and auto margins","Common positive-space branches exist; safe/unsafe and overflow cases are missing."],
    [.5,"Cross alignment and line sizing","No post-flex remeasurement; nowrap wrongly depends on align-content; FLEX-04/05."],
    [.5,"First/last and nested baselines","Only direct text has a baseline; containers return zero; TEXT-01."],
    [0,"Intrinsic/indefinite container sizing and reflow","Available-space modes and a real measure/layout feedback pass are missing."],
    [0,"RTL/logical axes, absolute items and independent row/column gaps","Missing layout infrastructure."]]],
  ["block", "Block layout", [
    [.5,"In-flow vertical stacking","Implemented, but consumed size and actual final layout can diverge; BLOCK-01/02."],
    [.5,"Used-width equation and box sizing","Partial width adjustment; explicit overflow and auto margins are incorrect; BLOCK-03."],
    [.5,"Content-driven block height","naturalHeight exists but consults flexDirection, not block flow; BLOCK-01."],
    [.5,"Adjoining/empty/parent margin collapse","Pairwise collapse and empty blocks exist, but collapse sets/top propagation are incomplete; BLOCK-04/05."],
    [.5,"Formatting-context isolation","overflow != visible is used as a shortcut; clip and other BFC triggers differ; BLOCK-06."],
    [0,"Floats, clearance and float avoidance","No float context or clear properties."],
    [0,"Inline formatting and shrink-to-fit inline-block","No line boxes or inline formatting context."],
    [0,"Replaced elements and intrinsic ratios","No image/replaced-element measurement contract."],
    [0,"Block align-content and full display semantics","No block alignment; flow-root/contents/none dispatch absent; BOX-08."],
    [0,"Logical flow, percentages and fragmentation","Not implemented."]]],
  ["text", "Text metrics and typography", [
    [1,"Backend measurement interface and basic run widths","MeasureFn is real and Raylib supplies widths."],
    [.5,"UTF-8 run measurement and paint agreement","Chunking preserves codepoint boundaries, but width and font-size rounding differ; TEXT-02."],
    [.5,"Line height and ascent","Interface exists; backend ascent is 0.8em and line height is nominal size; TEXT-01."],
    [.5,"Min/max-content contributions","Basic words/lines are measured; CSS breaking/intrinsic rules are incomplete; TEXT-03."],
    [0,"Width-dependent wrapping in layout and painting","wrap() returns only a summary and is not called by layout/paint; TEXT-04."],
    [0,"Whitespace, hard line breaks and line boxes","No integrated whitespace/break handling; TEXT-03/04."],
    [0,"Font families, fallback, weight/style and loading","Raylib default font only; no CSS font selection."],
    [0,"Shaping, ligatures, Unicode breaking and grapheme maps","No shaping stack."],
    [0,"Bidirectional/vertical text and baseline families","Not implemented."],
    [0,"Alignment, spacing, decoration, ellipsis and text effects","Not implemented as CSS typography."]]],
  ["grid", "Grid layout", [
    [.5,"Explicit fixed columns","Simple row-major column loop, not the grid sizing algorithm; GRID-01."],
    [.5,"Fractional columns","Remaining-space split without intrinsic track minima; GRID-02."],
    [.5,"Implicit row heights and uniform gaps","Natural child heights only; final constraints/margins not fed back; GRID-02."],
    [0,"Explicit/implicit row and column sizing functions","No gridTemplateRows/gridAutoRows/gridAutoColumns."],
    [0,"Placement, spans, names and areas","Missing."],
    [0,"Intrinsic track sizing and spanning-item contributions","Missing."],
    [0,"repeat/minmax/auto-fit/auto-fill","Missing."],
    [0,"Grid item and track alignment","Missing."],
    [0,"Subgrid","Missing."],
    [0,"Dense auto-flow, absolute items and logical axes","Missing."]]],
  ["paint", "Box painting and colors", [
    [.5,"Solid background painting","Present; no CSS background layers or clipping rules."],
    [.5,"CSS color values","Only six-digit hex; PAINT-01."],
    [.5,"Per-side borders","Uniform rounded branch loses side colors; strokes are centered on edges; PAINT-02."],
    [.5,"Per-corner and elliptical radii","Only top-left/uniform radius influences all corners; PAINT-03."],
    [.5,"Outlines","Basic rectangular outline; no CSS style/offset/radius semantics."],
    [.5,"Shadows","Offset/spread rectangle exists, blur is explicitly discarded; PAINT-04."],
    [0,"Images, gradients and layered backgrounds","Missing."],
    [0,"Opacity, stacking contexts and compositing","Missing."],
    [0,"Transforms and effects","Missing."],
    [0,"Masks, shapes and rounded descendant clipping","Missing."]]],
  ["overflow", "Overflow and scrolling", [
    [.5,"Ancestor overflow clipping","Rectangular ancestor intersection is present."],
    [.5,"Clip-aware hit testing","Rectangular test exists; no rounded/transformed hit regions."],
    [.5,"Vertical wheel scrolling","Offsets exist; no horizontal or programmatic API."],
    [.5,"Scrollable overflow extent","Direct-child bottoms only; nested visible overflow can be lost; SCROLL-01."],
    [0,"Independent overflow axes and clip/hidden semantics","Missing per-axis model; BFC shortcut is incorrect; BLOCK-06."],
    [0,"Scrollbars and gutter reservation","Missing."],
    [0,"Focus/caret scroll-into-view","Missing."],
    [0,"Nested chaining and overscroll","Deepest target always wins even at its edge; SCROLL-02."],
    [0,"Smooth scrolling and scroll snap","Missing."],
    [0,"Rounded/complex overflow clips and scroll-linked state","Missing."]]],
  ["input", "Single-line input and focus", [
    [1,"UTF-8 codepoint insertion/deletion and arrows","TextEdit provides the narrow codepoint-level operations."],
    [1,"Keyboard selection and clipboard shortcuts","Shift selection and Ctrl+A/C/X/V paths exist."],
    [.5,"Value and event integration","Input bridge exists; richer form/input contracts are missing; INPUT-01."],
    [.5,"Tab focus and button activation","Tab/Shift+Tab/Enter exist; DOM order, Space and focus events are incomplete; INPUT-02."],
    [0,"Pointer caret positioning and drag selection","Click focuses at end; no selection dragging."],
    [0,"IME composition and candidate placement","Missing."],
    [0,"Grapheme/bidi-aware editing","Codepoint-level only."],
    [0,"Form types, validation and submission/reset","Missing."],
    [0,"Undo/redo and editing history","Missing."],
    [0,"Accessibility and native text services","Missing."]]],
  ["select", "Select / option control", [
    [0,"select/option/optgroup JSX and native contract","No typed intrinsic or native behavior; SELECT-01."],
    [0,"Value, option identity and controlled selection","Only input.value crosses the bridge."],
    [0,"Popup/overlay placement and clipping escape","Demo expands an in-flow column of buttons."],
    [0,"Arrow/Home/End/Page navigation and commit/cancel","Missing."],
    [0,"Type-ahead search","Missing."],
    [0,"Disabled options/groups and empty states","Missing."],
    [0,"Focus transfer, outside click and Escape handling","Missing."],
    [0,"Input/change event semantics","No change event or select dispatch."],
    [0,"multiple/size and listbox selection","Missing."],
    [0,"Accessible labels, platform semantics and form integration","Missing."]]],
  ["language", "CSS language and style resolution", [
    [0,"CSS tokenizer, parser and error recovery","Only a hand-written style object projection exists."],
    [0,"Stylesheets, selectors and specificity","class/id are not used by styling."],
    [0,"Cascade origins, layers and important","Missing."],
    [0,"Computed styles, defaults and inheritance","Only color/fontSize are manually inherited; not the computed-style algorithm."],
    [0,"Custom properties and var resolution","Missing."],
    [0,"Typed lengths, percentages, math and unit conversion","Missing."],
    [0,"Shorthand expansion and invalid declaration handling","Small permissive parsers are not CSS grammar; BOX-09/FLEX-07."],
    [0,"Pseudo-classes and pseudo-elements","Missing."],
    [0,"At-rules and conditional/style imports","Missing."],
    [0,"CSSOM/semantic inspection and invalidation dependencies","Missing."]]],
  ["position", "Positioning and stacking", [
    [.5,"Normal-flow static placement","Custom flow exists; not full CSS positioning."],
    [0,"Relative offsets","Missing."],[0,"Absolute positioning","Missing."],
    [0,"Fixed positioning","Missing."],[0,"Sticky positioning","Missing."],
    [0,"Containing blocks and inset resolution","Missing."],[0,"z-index and stacking contexts","Missing."],
    [0,"Out-of-flow overflow contributions","Missing."],[0,"Logical/RTL offsets","Missing."],
    [0,"Transformed containing blocks and hit testing","Missing."]]],
  ["responsive", "Responsive and conditional styling", [
    [0,"Media queries","Missing."],[0,"Container size queries","Missing."],
    [0,"Container units","Missing."],[0,"Viewport unit families","Missing."],
    [0,"Font-relative units","Missing."],[0,"Resolution and absolute unit conversion","Missing."],
    [0,"prefers-color-scheme/contrast/reduced-motion","Missing."],[0,"Feature queries","Missing."],
    [0,"Logical properties and writing-mode remapping","Missing."],[0,"Query/viewport dependency invalidation","Missing."]]],
  ["motion", "Motion, transforms and effects", [
    [0,"2D transforms","Missing."],[0,"3D transforms/perspective","Missing."],
    [0,"Transform origins and reference boxes","Missing."],[0,"CSS transitions","Missing."],
    [0,"Keyframes and animation composition","Missing."],[0,"Easing functions","Missing."],
    [0,"starting-style and discrete transitions","Missing."],[0,"Filters/backdrop filters","Missing."],
    [0,"Opacity/blend/isolation layers","Missing."],[0,"Motion paths and compositor synchronization","Missing."]]],
  ["other", "Other Baseline CSS formatting families", [
    [0,"Tables and border collapse","Missing."],[0,"Lists, counters and markers","Missing."],
    [0,"Multicolumn and fragmentation","Missing."],[0,"Ruby and text emphasis","Missing."],
    [0,"SVG CSS integration","Missing."],[0,"MathML CSS integration","Missing."],
    [0,"Paged media and print layout","Missing."],[0,"Shapes and float exclusions","Missing."],
    [0,"Containment/content-visibility behavior","Missing."],[0,"Generated/replaced content styling","Missing."]]],
  ["solid", "Solid native integration", [
    [1,"Pinned client runtime rather than server/no-op build","Uses solid-js and @solidjs/universal rc.21."],
    [1,"Official universal renderer mutation contract","createRenderer supplies insertion/reconciliation/disposal."],
    [1,"Requested upstream primitive API mapping","All 36 requested names are supplied by upstream; this is not native semantic validation."],
    [.5,"Timer/microtask-driven native publication","Host pump and wakeups exist; no audited end-to-end publication matrix; HOST-01."],
    [.5,"Loading/Reveal/Errored native frame behavior","Upstream implementations present; probes mostly cover synchronous branches."],
    [.5,"Lazy modules with Vite application HMR","Literal imports/module graph exist; recovery and ESM limitations remain; HMR-01/02."],
    [.5,"Owner cleanup and external-source lifecycle","Upstream owns disposal; demo async tasks lack cancellation; DEMO-01."],
    [.5,"Contexts/stores/projections across component boundaries","Upstream APIs exist; provider/store-native integration cases missing."],
    [.5,"Stable identity, refs and event targeting","IDs and refs exist; no semantic id/label/focus contract; INPUT-02."],
    [0,"Non-layout markers and correct conditional geometry","Empty universal sentinels enter native layout; SOLID-01."]]],
  ["host", "Bridge, event loop and development host", [
    [1,"QuickJS evaluation and job pumping","C host exists, no app execution performed in this audit."],
    [.5,"Runtime ownership and shutdown","Single process-global runtime; no per-instance configuration."],
    [.5,"Deadline wakeups and platform event integration","Windows timer worker exists; error paths/other platforms incomplete; HOST-02."],
    [1,"Retained IDs and staged tree validation","Tree.apply stages and validates graphs before committing."],
    [.5,"Native apply/layout acknowledgement transaction","Acknowledgement precedes layout success; HOST-01."],
    [.5,"Incremental invalidation and allocation strategy","Changed-node transport, but full JS traversal, map clone and full changed-tree layout; HOST-03."],
    [.5,"Module graph, accepts and hot lifecycle","Implemented custom host; not full Vite/ESM semantics; HMR-01/02."],
    [.5,"Errors and last-good recovery","Compile publication is guarded; module execution is not transactional; HMR-01."],
    [.5,"Reusable/public packaging","Build helpers exist; private JS package/no standalone Zig manifests; HOST-04."],
    [0,"Multiple windows/runtimes and platform services","Not implemented."]]],
  ["a11y", "Accessibility and semantic UI", [
    [0,"Accessible role/name/value tree","Missing."],[0,"Windows UI Automation providers","Missing."],
    [0,"Label/control association","Missing."],[0,"Semantic disabled/readOnly/required states","Only limited JS input guards exist; no semantic tree."],
    [0,"Focus/blur events and focus management","Internal integer focus is not an accessibility system."],
    [0,"Keyboard widget conventions","Only generic Tab/Enter and text keys."],[0,"Screen-reader announcements/live regions","Missing."],
    [0,"Selection/range accessibility","Missing."],[0,"Contrast/forced-colors integration","Missing."],
    [0,"Platform scaling/accessibility verification","No audited contract or evidence."]]],
];

const baseline = JSON.parse(await readFile(new URL("baseline-2024-css.json", output), "utf8"));
const supplement = JSON.parse(await readFile(new URL("chrome-131-css-supplement.json", output), "utf8"));
const partial = {
  "aspect-ratio":"Zero-height fallback only; BOX-07.", "background-color":"Six-digit hex solids only; PAINT-01.",
  "border-radius":"Uniform/top-left radius only; PAINT-03.", "borders":"Numeric side widths/colors, incomplete paint; PAINT-02.",
  "box-shadow":"Approximate rectangle; no blur; PAINT-04.", "box-sizing":"Horizontal block adjustment only; BOX-05.",
  "color":"Six-digit hex color and manual inheritance only; PAINT-01.", "display":"Custom block/flex dispatch; none/inline semantics missing; BOX-08.",
  "flexbox":"Substantial subset with algorithm defects; FLEX-01 through FLEX-07.", "flexbox-gap":"One numeric gap; no independent axes or percentages.",
  "font-size":"Numeric font size only; TEXT-01/02.", "grid":"Basic fixed/fr columns; GRID-01/02.",
  "margin":"Numeric/auto subset with sentinel and ownership defects; BOX-02/03/04.",
  "min-max-width-height":"Positive numeric clamp only; BOX-01/06.", "outline":"Basic rectangle, not CSS outlines.",
  "outlines":"Basic rectangle, not CSS outlines.", "overflow":"Rectangular clip and vertical wheel subset; SCROLL-01/02.",
  "overflow-clip":"Rectangular clip, incorrect block-context implication; BLOCK-06.",
  "padding":"Numeric subset; explicit zero/control defaults are wrong; BOX-02.",
  "physical-properties":"Some physical size/edge style names only; no logical mapping or inset support.",
  "static-positioning":"Custom normal flow only, not the full CSS box tree.", "width-height":"Positive numeric dimensions only; BOX-01/05."
};
const esc = value => String(value).replaceAll("&","&amp;").replaceAll("<","&lt;").replaceAll(">","&gt;").replaceAll('"',"&quot;");
const evaluated = categories.map(([id,name,rows]) => ({ id,name,points: rows.reduce((sum,row)=>sum+row[0],0),possible: rows.length,
  percent: 100*rows.reduce((sum,row)=>sum+row[0],0)/rows.length,
  requirements: rows.map(([score,name,note],i)=>({id:`${id.toUpperCase()}-R${String(i+1).padStart(2,"0")}`,score,name,note})) }));
const assessment = { auditedCommit:"8873c31", date:"2026-11-11", method:"Static source-review planning coverage. Each named obligation: 0 missing/incomplete foundation, 0.5 partial, 1 narrowly implemented. Equal weights within each subsystem only. No application tests/builds executed. Percentages are NOT WPT pass rates, correctness probabilities, schedule estimates or full CSS conformance.", categories:evaluated,
  baseline:{features:baseline.features.length,keys:baseline.features.reduce((sum,f)=>sum+f.keys.length,0),partialAnalogues:baseline.features.filter(f=>partial[f.id]).length,confirmedConformant:null},
  primitiveNames:(await readFile(new URL("tests/features.js",root),"utf8")).match(/const required = "([^"]+)"/)[1].split(" ") };
await writeFile(new URL("assessment.json",output),JSON.stringify(assessment,null,2)+"\n");
let checklist = "# Static source-review coverage checklist\n\nAudited commit: `8873c31`. Generated by `tools/audit-report.mjs`. These are planning judgments, not executed tests. 0 = missing, 0.5 = partial, 1 = narrowly present. A 1 does not certify surrounding CSS interactions. Subsystem percentages are not added or averaged into a browser conformance score. Each subsystem has ten explicitly named obligations.\n\n";
for(const c of evaluated){checklist+=`## ${c.name}: ${c.percent}% (${c.points}/${c.possible})\n\n| ID | Points | Obligation | Source review |\n| --- | ---: | --- | --- |\n`;
  for(const r of c.requirements)checklist+=`| ${r.id} | ${r.score} | ${r.name} | ${r.note} |\n`;
  checklist+="\n";}
await writeFile(new URL("coverage-checklist.md",output),checklist);
let inventory = `# CSS feature inventory through 2024\n\nPinned WebDX web-features ${baseline.packageVersion}; cutoff ${baseline.cutoff}; source SHA-256 \`${baseline.sourceSha256}\`.\n\n${assessment.baseline.features} feature groups and ${assessment.baseline.keys} CSS compatibility keys meet this extraction rule. ${assessment.baseline.partialAnalogues} groups have a partial native analogue; the rest have no implemented end-to-end CSS feature path. **No group is certified conformant.** A native analogue is not support for CSS syntax, all values, or all interactions. 288 groups are not 288 equally sized specification obligations.\n\nA group may have subfeatures added after 2024; the JSON includes only keys individually available by the cutoff. Groups whose overall date is later are included only for their older keys. Counts include CSS hooks of HTML/SVG/MathML features. Deprecated catalog records are retained so omissions are explicit, not silently counted as modern requirements.\n\nRegenerate the data using \`node tools/audit-catalog.mjs\`, then the report using \`node tools/audit-report.mjs\`. Neither command runs application code. Data model: [WebDX](https://github.com/web-platform-dx/web-features/tree/main/docs); raw pinned data: [web-features@3.45.0](https://unpkg.com/web-features@3.45.0/data.json).\n\n| Feature ID | Name | Target CSS keys | Source status |\n| --- | --- | ---: | --- |\n`;
for(const feature of baseline.features)inventory+=`| ${feature.id} | ${feature.name.replaceAll("|","/")} | ${feature.keys.length} | ${partial[feature.id] || "Absent: no complete CSS feature implementation path."} |\n`;
inventory+="\n## Chrome 131 supplement\n\nThis is separate from cross-browser Baseline: numeric Chrome support <=131 for additional keys in the same WebDX dataset. It is a discovery supplement, not a complete export of historical Chromium BCD/WPT or experimental/prefixed features. Those require a separately frozen oracle. Chrome 131 shipped in November 2024; 132 shipped in January 2025. See the official [131](https://developer.chrome.com/release-notes/131) and [132](https://developer.chrome.com/release-notes/132) release notes.\n\n| Feature ID | Name | Additional CSS keys |\n| --- | --- | ---: |\n";
for(const feature of supplement.features)inventory+=`| ${feature.id} | ${feature.name.replaceAll("|","/")} | ${feature.keys.length} |\n`;
await writeFile(new URL("baseline-feature-inventory.md",output),inventory);

const files = execFileSync("git",["ls-tree","-r","--name-only","8873c31"],{cwd:fileURLToPath(root),encoding:"utf8"}).trim().split(/\r?\n/)
  .filter(path=>!path.startsWith(".agents/") && !path.endsWith("pnpm-lock.yaml"));
const manifest=[];
for(const path of files){const bytes=execFileSync("git",["show",`8873c31:${path}`],{cwd:fileURLToPath(root)});manifest.push({path,sha256:createHash("sha256").update(bytes).digest("hex"),bytes:bytes.length});}
await writeFile(new URL("source-manifest.json",output),JSON.stringify({commit:"8873c31",scope:"Tracked first-party files at the audit base, excluding unrelated .agents deletion and generated dependency lockfile. No dependency/vendor/generated bundle content claimed as exhaustively reviewed.",files:manifest},null,2)+"\n");

const chartIds=["box","flex","block","text","grid","paint","overflow","input","select","language","solid"];
const charts=evaluated.filter(c=>chartIds.includes(c.id));
const html=`<!doctype html><html><head><meta charset="utf-8"><style>
:root{color-scheme:dark light}body{margin:0;font-family:var(--font-sans,system-ui);color:var(--foreground)}p{color:var(--muted-foreground);line-height:1.45} .row{display:grid;grid-template-columns:minmax(120px,1fr) 2fr 44px;gap:12px;align-items:center;margin:13px 0;font-size:13px}.track{height:10px;background:var(--secondary);border-radius:5px;overflow:hidden}.bar{height:10px;background:var(--chart-1);border-radius:5px}.value{text-align:right;font-variant-numeric:tabular-nums}small{color:var(--muted-foreground)}button{font:inherit;color:var(--foreground);background:var(--secondary);border:1px solid var(--border);border-radius:var(--radius);padding:6px 10px;cursor:pointer}#detail{padding:12px;background:var(--card);border-radius:var(--radius);line-height:1.5;font-size:13px}ul{padding-left:20px}@media(max-width:420px){.row{grid-template-columns:110px 1fr 36px;gap:7px}}
</style></head><body><p>Static implementation coverage at <code>8873c31</code>. Ten named obligations per subsystem; 0 / half / full source credit. These are planning estimates, not browser test results.</p>
${charts.map(c=>`<div class="row"><span>${esc(c.name)}</span><div class="track" role="meter" aria-label="${esc(c.name)}" aria-valuenow="${c.percent}" aria-valuemin="0" aria-valuemax="100"><div class="bar" style="width:${c.percent}%"></div></div><span class="value">${c.percent}%</span></div>`).join("")}
<p><strong>${assessment.baseline.partialAnalogues}/${assessment.baseline.features}</strong> catalog groups have partial native analogues. Full CSS conformance: <strong>unmeasured</strong>. Select control: absent.</p>
<label for="area">Inspect checklist: </label><select id="area">${evaluated.map(c=>`<option value="${c.id}">${esc(c.name)}</option>`).join("")}</select><div id="detail"></div>
<script>const data=${JSON.stringify(evaluated).replaceAll("<","\\u003c")};const area=document.getElementById('area');const detail=document.getElementById('detail');function show(){const c=data.find(c=>c.id===area.value);detail.replaceChildren();const ul=document.createElement('ul');for(const r of c.requirements){const li=document.createElement('li');li.textContent=r.score+' / 1 — '+r.name+': '+r.note;ul.append(li)}detail.append(ul)}area.addEventListener('change',show);show();</script></body></html>`;
await writeFile(new URL("coverage.html",output),html);
// Check documentation references only; this does not execute application code.
const report=await readFile(new URL("docs/compatibility-audit-2026-11-11.md",root),"utf8");
let localLinks=0;
for(const match of report.matchAll(/\]\((C:\/[^)]+)\)/g)){
  const target=match[1].match(/^(.*?)(?::(\d+))?$/);
  const content=await readFile(target[1],"utf8");
  if(target[2] && Number(target[2])>content.split("\n").length)throw Error(`Invalid documentation line reference: ${match[1]}`);
  localLinks++;
}
const findings=new Set([...report.matchAll(/\| ([A-Z]+-\d+) \|/g)].map(match=>match[1]));
console.log(JSON.stringify({categories:evaluated.map(({name,percent})=>({name,percent})),baseline:assessment.baseline,requestedPrimitiveNames:assessment.primitiveNames.length,sourceFiles:manifest.length,documentationLinks:localLinks,findings:findings.size,scoredObligations:evaluated.reduce((n,c)=>n+c.requirements.length,0)},null,2));
