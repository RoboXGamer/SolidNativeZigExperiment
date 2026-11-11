// Prepare and publish the explicitly authorized Baseline 2024 GitHub backlog.
// Uses the authenticated gh CLI; no tokens are read or printed by this script.
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { mkdir, readFile, writeFile, appendFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
const exec = promisify(execFile);
const root = new URL("../", import.meta.url);
const output = new URL("docs/issues/", root);
const repo = "RoboXGamer/SolidNativeZigExperiment";
const web = `https://github.com/${repo}`;
const sourcePin = "8873c312668b3223789848056abb68aca6e00183";
const auditPin = "c4a9b4a3567424a2601af21634e37cc2a2c46631";
const auditURL = `${web}/blob/${auditPin}/docs/compatibility-audit-2026-11-11.md`;
const source = (path, line = 1) => `${web}/blob/${sourcePin}/${path}#L${line}`;
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const gh = async args => {
  try { const r = await exec("gh", args, { cwd: fileURLToPath(root), maxBuffer: 24 * 1024 * 1024, windowsHide: true }); return { ok: true, ...r }; }
  catch (r) { return { ok: false, stdout: String(r.stdout || ""), stderr: String(r.stderr || r.message || "gh failed") }; }
};
const catalog = JSON.parse(await readFile(new URL("docs/audit/baseline-2024-css.json", root), "utf8"));
if (catalog.features.length !== 288) throw Error("Expected the approved 288-feature inventory");
const inventory = await readFile(new URL("docs/audit/baseline-feature-inventory.md", root), "utf8");
const historical = new Map([...inventory.matchAll(/^\| ([a-z0-9-]+) \| .*? \| \d+ \| (.*?) \|$/gm)].map(match => [match[1], match[2]]));
const ids = new Set(catalog.features.map(f => f.id));
const profiles = {
  layout: {
    name: "Layout and box sizing", dependencies: ["box-sizing", "width-height", "min-max-width-height", "display", "logical-properties"],
    files: [["modules/ui_core/style.zig",1],["modules/ui_core/scene.zig",136],["modules/ui_core/layout_block.zig",19],["modules/ui_core/layout_flex.zig",122],["packages/solid-zig/src/native.js",77]],
    work: ["Define typed specified/computed/used values and available-space dependencies for this group's keys; preserve zero, auto, percentages and invalid declarations distinctly.","Apply the feature in the appropriate block/flex/grid/leaf sizing or box-generation path; propagate final sizes, baselines and overflow instead of adding a transport-only field.","Keep one content/padding/border/margin ownership contract and cover nesting, constraints, writing direction and layout-mode interactions."],
    acceptance: ["Encode exact rectangle/used-size fixtures for the eligible values, zero/auto, conflicting min/max, definite/indefinite containing blocks and nested boxes.","Compare supported block/flex/grid cases with the specification and suitable Taffy fixtures; use the frozen browser oracle for behavior Taffy does not own."] },
  typography: {
    name: "Fonts and text layout", dependencies: ["font-family", "font-size", "line-height", "white-space", "writing-mode"],
    files: [["modules/ui_core/text.zig",32],["modules/ui_core/scene.zig",136],["modules/ui_core/layout_flex.zig",65],["src/windows.zig",32]],
    work: ["Represent and compute this feature's eligible font/text values, including inheritance, font/run dependencies and invalid-value handling.","Integrate the behavior with real font selection/metrics, shaping or positioned line runs as required; measuring a string or storing a field alone does not implement typography.","Share the same resolved text/runs between intrinsic sizing, layout, painting, hit/selection geometry and invalidation."],
    acceptance: ["Cover mixed fonts/sizes, hard breaks, wrapping/whitespace, non-ASCII text and horizontal/vertical/bidirectional contexts where applicable.","Use deterministic fonts and explicit expected run/line/baseline geometry, with browser fixtures for the eligible keys and fallback/error cases."] },
  styling: {
    name: "Style parsing, cascade and computed values", dependencies: ["selectors", "inherit-value", "initial-value", "custom-properties"],
    files: [["packages/solid-zig/src/native.js",33],["packages/solid-zig/src/native.d.ts",15],["modules/ui_core/style.zig",1]],
    work: ["Add correct syntax/value validation and a computed-style contract for the eligible keys; reject unsupported or invalid grammar instead of silently coercing it.","Implement cascade, inheritance, specificity or dependency resolution where this feature needs them, while retaining JSX style objects as a supported authoring API.","Wire computed changes into the affected native style/layout/paint consumers and invalidate dependent values; an accepted property name is not a completed CSS feature."],
    acceptance: ["Cover valid and invalid declarations, shorthand/longhand precedence where relevant, inherited/default values and reactive updates.","Add applicable browser/WPT cases for the pinned compatibility keys and interactions with related computed values."] },
  selectors: {
    name: "Selectors and pseudo-element/state matching", dependencies: ["selectors", "is", "not", "where"],
    files: [["packages/solid-zig/src/renderer.js",5],["packages/solid-zig/src/native.js",194],["modules/ui_core/tree.zig",4],["modules/ui_core/style.zig",1]],
    work: ["Implement parsing, matching, specificity and scoping rules for this group's eligible selectors or pseudo-elements.","Provide the required semantic attributes/tree relationships/state or generated boxes; the retained renderer tree is not already a DOM/selector engine.","Invalidate matches after relevant tree, attribute, interaction or inherited-style changes and route generated output through native layout/paint."],
    acceptance: ["Include positive/negative matching, nested scopes, specificity/cascade and dynamic state/tree mutation cases.","For generated/pseudo content, verify box creation, painting, hit/accessibility consequences and disposal rather than testing only string matching."] },
  painting: {
    name: "Native painting and compositing", dependencies: ["box-sizing", "color", "background", "border-radius", "z-index"],
    files: [["src/windows.zig",17],["src/windows.zig",52],["modules/ui_core/geometry.zig",13],["packages/solid-zig/src/native.js",131]],
    work: ["Parse and compute the eligible style values, color/image/effect inputs and reference-box rules required by this group.","Implement actual native paint/compositor behavior, including clipping, ordering and affected bounds; do not substitute an approximate rectangle for a specified effect.","Keep painting, layout overflow, hit regions, device-scale rounding, resource lifetime and reactive invalidation consistent."],
    acceptance: ["Add deterministic visual/geometry fixtures for eligible values, transparent/empty/error cases, clipping and nesting.","Verify the feature at multiple box sizes/device scales and relevant stacking/transform contexts against frozen browser reference output."] },
  motion: {
    name: "Animation, transforms and effects", dependencies: ["transforms2d", "transform-box", "transitions", "animations-css"],
    files: [["src/windows.zig",52],["src/windows.zig",241],["modules/solid_bridge/quickjs_bridge.c",65],["modules/ui_core/style.zig",1]],
    work: ["Define the eligible specified/computed values and the feature's timing, interpolation, composition or transform/reference-box semantics.","Apply it through the native animation/paint/compositor system and coordinate layout/overflow/hit testing when geometry changes.","Handle start/update/cancel/finish, resource ownership and event-driven scheduling; a timeout-based requestAnimationFrame shim alone is not CSS motion support."],
    acceptance: ["Use a controlled clock to verify initial/intermediate/final and canceled/reversed/updated states where applicable.","Cover nesting, transform origins, composition/easing, reduced-motion interactions and comparison with the pinned browser behavior."] },
  responsive: {
    name: "Queries, units and contextual style dependencies", dependencies: ["media-queries", "width-height", "font-size", "logical-properties"],
    files: [["packages/solid-zig/src/native.js",33],["modules/ui_core/style.zig",1],["modules/ui_core/scene.zig",171],["src/windows.zig",300]],
    work: ["Represent the eligible query/length/context values as typed data; preserve suffixes and mathematical dimensions instead of parseFloat coercion.","Supply real viewport/font/container/environment inputs required by this feature and resolve definite/indefinite or missing contexts explicitly.","Track context dependencies so resize, font/root-font, writing-mode, preferences or container changes trigger the correct style and layout update."],
    acceptance: ["Cover exact boundaries, valid/invalid syntax, context changes, zoom/device-scale and relevant indefinite/missing-context behavior.","Verify the eligible values and query predicates against a frozen browser fixture without claiming unavailable host metrics are working."] },
  scrolling: {
    name: "Overflow, scrolling and interaction geometry", dependencies: ["overflow", "overflow-clip", "box-sizing", "scrollbar-gutter"],
    files: [["modules/ui_core/scene.zig",230],["modules/ui_core/scene.zig",253],["src/windows.zig",245],["src/windows.zig",265]],
    work: ["Implement the eligible overflow/scroll values with the correct scroll-container, clipping, axis and formatting-context semantics.","Compute propagated scrollable overflow, viewport/content/gutter geometry and input/programmatic behavior required by the feature.","Coordinate nested scrolling, focus/caret visibility, painting/hit clipping, retained identity and layout invalidation."],
    acceptance: ["Cover no-overflow, overflowing descendants, horizontal/vertical axes, nested edges/chaining and resized or mutated content.","Verify eligible behavior with focus/keyboard/pointer/programmatic cases where applicable and exact browser geometry/state references."] },
  platform: {
    name: "Semantic/native formatting integration", dependencies: ["display", "selectors", "writing-mode", "color"],
    files: [["packages/solid-zig/src/native.d.ts",89],["packages/solid-zig/src/renderer.js",6],["packages/solid-zig/src/native.js",93],["src/windows.zig",52]],
    work: ["Define the semantic data and native formatting/control/platform integration needed for the eligible CSS hooks, without assuming arbitrary JSX tags already implement HTML/SVG/MathML behavior.","Connect the feature to computed styling, appropriate box/paint generation and any interaction/accessibility/platform state it requires.","Preserve Solid ownership/identity and specify unsupported platform cases explicitly; implement the pinned CSS slice rather than automatically expanding to the entire surrounding Web API."],
    acceptance: ["Cover the eligible CSS hook in its real semantic context, not just a synthetic generic container.","Add native and frozen-browser cases for nesting, value/state changes, cleanup, accessibility and relevant platform/print/media contexts."] }
};
function family(f) {
  const group = new Set(f.groups), id = f.id;
  if(group.has("media-queries") || group.has("container-queries") || group.has("units") || group.has("environment-variables") || /^(calc|exp-functions|trig-functions|min-max-clamp|round-mod-rem)/.test(id)) return "responsive";
  if(group.has("selectors") || /^(before-after|first-letter|first-line|placeholder|backdrop|target-text|file-selector-button)$/.test(id)) return "selectors";
  if(["fonts","font-features","font-synthesis","text","text-wrap","white-space","ruby"].some(g=>group.has(g)) || /^(font-|line-|letter-spacing|word-|text-|vertical-align|tab-size|hyphens|hyphenate|dominant-baseline)/.test(id)) return "typography";
  if(["animation","transitions","transforms"].some(g=>group.has(g)) || /^(motion-path|animation|transition|.*easing)/.test(id)) return "motion";
  if(group.has("scrolling") || /^(overflow|scroll|overscroll|touch-action|pointer-events)/.test(id)) return "scrolling";
  if(["background","color-types","clipping-shapes-masking","blend-mode","gradients","borders-outlines","image-formats","image-scaling","images"].some(g=>group.has(g)) || /^(color|opacity|filter|backdrop-filter|borders|border-|box-shadow|outline|paint-order)/.test(id)) return "painting";
  if(["layout","positioning","grid","flexbox","multi-column","containment"].some(g=>group.has(g)) || /^(display|width-height|min-max-width-height|min-max-content|box-sizing|margin|padding|logical-properties|writing-mode|layout-direction-override|float-clear|table|z-index|zoom|position|visibility|object-fit|object-position|fit-content)/.test(id)) return "layout";
  if(["html","html-elements","web-components","custom-elements","forms","svg","mathml","print","lists","counters","text-fragments"].some(g=>group.has(g))) return "platform";
  return "styling";
}
const special = {
  "box-sizing": "Finish the shared box contract and content-/border-box adjustments across both axes and every supported formatting path (BOX-04/05/06); coordinate with the active box/sizing milestone.",
  "width-height": "Remove numeric zero/auto conflation, resolve containing-block percentages/definiteness, and propagate final sizes (BOX-01/05/07/09); coordinate with the active box/sizing milestone.",
  "min-max-width-height": "Preserve explicit zero/none, make minimums win conflicting maximums, and ensure parents consume final constrained sizes (BOX-01/06).",
  "margin": "Separate negative -1px from auto, preserve zero longhands and percentages, and count outer margins exactly once (BOX-02/03/04); block collapsing still needs collapse sets (BLOCK-04/05).",
  "padding": "Honor zero-over-shorthand, percentage inline-size basis and validated nonnegative values; author padding must override control defaults (BOX-02/09).",
  "aspect-ratio": "Replace the zero-height shortcut with bidirectional preferred-size transfer and min/max/box-sizing integration (BOX-07).",
  "display": "Implement actual box generation/dispatch: none suppresses visual/input boxes, contents flattens without losing ancestry, and unsupported contexts must not silently fall back to flex (BOX-08).",
  "display-contents": "Flatten the layout box while preserving Solid node identity, event ancestry, semantics and inherited style. Remove only the element's own box, not its descendants.",
  "display-flow-root": "Create an independent block formatting context with the required float/margin behavior; overflow:clip is not a substitute (BLOCK-06).",
  "flexbox": "Correct fractional flex factors, raw-basis/hypothetical/target separation and freezing, automatic minima, nowrap cross sizing, post-flex remeasurement, baseline synthesis and semantic focus order (FLEX-01..07).",
  "flexbox-gap": "Support row-gap/column-gap independently, shorthand and percentage/definiteness behavior; renderer sentinel nodes must not consume gaps (SOLID-01).",
  "grid": "Replace fixed/fr column packing with track sizing, explicit/implicit rows/columns, placement/spans, intrinsic contributions, auto-flow and alignment; coordinate follow-up subgrid separately (GRID-01/02).",
  "font-size": "Use consistent computed font size in measurement and painting; the current backend rounds one path and truncates the other (TEXT-02).",
  "line-height": "Use font ascent/descent/leading and positioned line boxes; nominal font_size and a fixed 0.8em ascent are not complete line metrics (TEXT-01/04).",
  "border-radius": "Implement all four corners, elliptical/percentage radii and overlap scaling with matching clip/hit geometry; current paint uses one radius for all corners (PAINT-03).",
  "borders": "Implement actual side styles/colors/widths and inside edge geometry; centered line strokes and the uniform rounded color branch are insufficient (PAINT-02).",
  "box-shadow": "Replace the five-token rectangle approximation with valid CSS shadow syntax, blur, inset and multiple layers and correct paint bounds (PAINT-04).",
  "color": "Extend six-digit hex to the eligible CSS color/inheritance values; do not conceal unsupported declarations behind fallback paint (PAINT-01).",
  "background-color": "Resolve eligible colors including transparency/current color interactions correctly, then paint within the proper background reference/clip box (PAINT-01).",
  "overflow": "Implement independent axes, hidden/clip/scroll/auto semantics, propagated descendant overflow, focus visibility and nested scroll behavior (BLOCK-06, SCROLL-01/02).",
  "overflow-clip": "Clip without inventing a scroll container or BFC; the current overflow != visible block-context shortcut is incorrect (BLOCK-06).",
  "logical-properties": "Map inline/block preferred/min/max dimensions and logical edges for writing modes/directions; preserve declaration precedence when physical/logical properties mix.",
  "layout-direction-override": "Provide real CSS ltr/rtl/bidi-related semantics; the legacy style.direction field currently carries flex-axis values, which is a different concept.",
  "writing-mode": "Map inline/block axes and edges for horizontal/vertical modes consistently across sizing, text, controls and paint, including the necessary text-layout dependencies.",
  "text-wrap": "Build actual width-dependent line construction and paint runs; Text.wrap is disconnected and only returns summary counts (TEXT-03/04).",
  "text-wrap-balance": "Implement balancing as a line-construction strategy on real shaped runs; greedy word counts alone cannot implement balanced text.",
  "white-space": "Preserve/collapse spaces, tabs and hard breaks per the eligible values and feed matching intrinsic and line-box layout (TEXT-03/04).",
  "align-content-block": "Apply block content alignment after the used block size is known; the existing alignContent branches are flex-only.",
  "float-clear": "Add a float formatting context, float placement/avoidance and clearance with margin-collapse integration (BLOCK-06), not just style fields.",
  "subgrid": "Adopt parent track sizing/line relationships for subgridded axes; this depends on real grid tracks and placement, not column packing.",
  "appearance": "Use real native/control semantics before applying appearance rules. The demo's button dropdown is not a select/option control (SELECT-01).",
  "vertical-form-controls": "Integrate writing modes with semantic controls and input/popup geometry; implementing generic rotated containers is insufficient.",
  "outlines": "Coordinate with the outline feature record to avoid two independent engines; this catalog group exists separately and its eligible keys still need an explicit disposition.",
  "outline": "Implement eligible outline width/style/color geometry and interactions; the current painter only draws a basic rectangle. Coordinate the related outlines record.",
  "min-max-content": "Expose correct intrinsic sizing values through the style bridge and constrained layout; internal ASCII-word helper functions are not CSS value support (FLEX-03, TEXT-03).",
  "position": "Add the eligible position values and real containing-block/inset/static-position behavior; currently only custom in-flow placement exists.",
  "physical-properties": "Implement the eligible physical edge/size properties with real typed values and box semantics; some matching field names are already transported, but insets and full computed behavior are missing.",
  "static-positioning": "Make normal-flow/static-position rules part of a defined CSS formatting contract, including interactions with containing blocks and out-of-flow positioning.",
  "cursor": "Wire computed cursor values to native pointer state/hit regions, including resource lifetime for cursor images where the eligible keys require them.",
  "user-action-pseudos": "Introduce semantic hover/active/focus state and selector invalidation. The current internal focused ID does not provide CSS pseudo-class behavior.",
  "content-visibility": "Implement layout/paint containment and visibility skipping with preserved intrinsic-size/semantic behavior rather than simply deleting the subtree.",
  "will-change": "Implement eligible hint syntax and a resource/compositing policy that preserves rendering semantics, with limits and cleanup; storing the hint alone is insufficient.",
};
const dependencyURL = id => `${web}/issues?q=${encodeURIComponent(`is:issue in:title "(${id})"`)}`;
function issueFor(f) {
  const area = family(f), profile = profiles[area];
  const note = historical.get(f.id) || "Absent: no implemented end-to-end CSS feature path was identified in the pinned source audit.";
  const partial = !note.startsWith("Absent:");
  const marker = `<!-- solid-native-css-baseline:2024:${f.id} -->`;
  const dependencies = profile.dependencies.filter(id => id !== f.id && ids.has(id));
  const keyTable = f.keys.map(({key,baselineDate,chrome})=>`| \`${key}\` | ${baselineDate} | ${chrome ?? "not recorded"} |`).join("\n");
  const body = `${marker}
## Goal

Implement **${f.name}** in the native Solid/Zig style/rendering system for the exact Baseline-through-2024 CSS slice below. This issue tracks WebDX feature ID \`${f.id}\`; it is not a claim that the feature is already supported or tested.

## Scope and current evidence

- Cutoff: **2024-12-31**, cumulative Baseline newly available, including older features.
- Pinned inventory: \`web-features@${catalog.packageVersion}\`; **${f.keys.length} eligible CSS compatibility key${f.keys.length===1?"":"s"}**.
- Historical audit status at [\`8873c31\`](${web}/commit/${sourcePin}): **${partial?"partial native analogue":"missing feature path"}**. ${note}
- Area: **${profile.name}**. WebDX groups: ${f.groups.length?f.groups.map(g=>`\`${g}\``).join(", "):"not assigned"}.
- The audit is a source assessment, not an executed conformance result. Reassess newer changes, especially ongoing box/sizing work, before implementing or closing this ticket. A later partial commit is not by itself completion evidence.

## Required work

${special[f.id]?`- [ ] ${special[f.id]}\n`:""}${profile.work.map(s=>`- [ ] ${s}`).join("\n")}
- [ ] Cover every eligible compatibility key listed below, including its values/contexts. Keep later-than-2024 additions and Chrome-only extras outside this ticket unless explicitly approved.
- [ ] Preserve Solid's official universal renderer and native Zig backend; document any required host services and unavailable dependencies explicitly.

## Foundations and coordination

${dependencies.map(id=>`- Coordinate with [\`${id}\`](${dependencyURL(id)}).`).join("\n")}

These are related foundation tickets, not a claim that the dependency graph is acyclic or already implemented. Share interfaces/fixtures instead of duplicating style engines. If an eligible key needs a larger semantic subsystem, name it and keep that key open; do not silently drop it. Duplicate/historical WebDX group overlaps need an explicit per-key disposition before either ticket is closed.

## Acceptance criteria

${profile.acceptance.map(s=>`- [ ] ${s}`).join("\n")}
- [ ] Record the applicable specification/WPT fixture IDs, the frozen browser/platform/font/DPI context where relevant, and exact expected results for this feature's eligible keys.
- [ ] Verify the real authoring/bridge/native-consumer path and reactive changes/disposal; a field, export, parser-only assertion or demo screenshot alone is insufficient.
- [ ] Update the feature status with implementing commit(s), executed checks and remaining limitations. Never mark source-only fixtures as passed. Respect any active testing pause and distinguish implementation from runtime verification.

## Eligible CSS compatibility keys

This table is the pinned ticket denominator, not a list of tests already passed. The group itself may have later additions; only the individually eligible keys are included.

| Compatibility key | Baseline newly available | Chrome support metadata |
| --- | --- | --- |
${keyTable}

## References and code entry points

${f.spec.map(url=>`- [Specification](${url})`).join("\n")}
- [Pinned feature inventory](${web}/blob/${auditPin}/docs/audit/baseline-2024-css.json)
- [Compatibility audit and named findings](${auditURL})
- [Scored source-review checklist](${web}/blob/${auditPin}/docs/audit/coverage-checklist.md)
${profile.files.map(([path,line])=>`- [${path}:${line}](${source(path,line)})`).join("\n")}

Specification links can evolve; use the ticket's pinned key/date boundary and an appropriate historical oracle. Native layout references such as Taffy cover only their own algorithms; they do not certify CSS parsing, text shaping, painting, controls or accessibility.
`;
  return {id:f.id,title:`[CSS 2024] ${f.name} (${f.id})`,area,status:partial?"partial":"missing",dependencies,marker,labels:["enhancement","css","baseline-2024",partial?"css:partial":"css:missing",`area:${area}`],body};
}
await mkdir(output,{recursive:true});
const plan = catalog.features.map(issueFor);
if(new Set(plan.map(i=>i.id)).size!==288 || new Set(plan.map(i=>i.title)).size!==288) throw Error("Issue plan is not unique");
if(plan.filter(i=>i.status==="partial").length!==22) throw Error("Historical status classification drift");
if(plan.some(i=>Buffer.byteLength(i.body,"utf8")>60000)) throw Error("Issue body too large");
await writeFile(new URL("manifest.json",output),JSON.stringify({repo,auditPin,sourcePin,cutoff:catalog.cutoff,sourceSha256:catalog.sourceSha256,issues:plan},null,2)+"\n");
await writeFile(new URL("sample-box-sizing.md",output),plan.find(i=>i.id==="box-sizing").body);
await writeFile(new URL("sample-selectors.md",output),plan.find(i=>i.id==="selectors").body);

async function existingIssues() {
  const r=await gh(["issue","list","--repo",repo,"--state","all","--limit","1000","--json","number,title,body,url,state,labels"]);
  if(!r.ok)throw Error(`Cannot reconcile existing issues: ${r.stderr}`);
  const byId=new Map();
  for(const issue of JSON.parse(r.stdout)){
    const match=issue.body?.match(/<!-- solid-native-css-baseline:2024:([a-z0-9-]+) -->/);
    if(match){if(byId.has(match[1]))throw Error(`Duplicate published marker ${match[1]}`);byId.set(match[1],issue);}
  }
  return byId;
}
async function saveIndex(published) {
  const sorted=plan.filter(i=>published.has(i.id)).map(i=>({id:i.id,area:i.area,historicalStatus:i.status,number:published.get(i.id).number,url:published.get(i.id).url,title:i.title}));
  await writeFile(new URL("published.json",output),JSON.stringify({repo,totalPlanned:288,published:sorted.length,issues:sorted},null,2)+"\n");
  let md=`# Baseline 2024 GitHub issue index\n\nRepository: [${repo}](${web}). Pinned audit: \`8873c31\`; audit documentation pin: \`c4a9b4a\`. ${sorted.length}/288 distinct feature groups published. Historical missing/partial labels refer to that pinned audit, not a claim that later work has been reviewed.\n\nEach issue includes the exact eligible CSS keys/dates, specification links, current audit evidence, code entry points, foundation coordination and acceptance criteria. Chrome-only supplement groups are excluded.\n\nGenerated with \`node tools/css-issues.mjs\` (prepare), \`node tools/css-issues.mjs --publish\` (idempotent publish/resume) and \`node tools/css-issues.mjs --verify\` (read-only reconciliation). Application testing is not run by this tool.\n\n| Feature | Issue | Area | Historical status |\n| --- | --- | --- | --- |\n`;
  for(const i of sorted)md+=`| ${i.id} | [#${i.number}](${i.url}) | ${i.area} | ${i.historicalStatus} |\n`;
  await writeFile(new URL("README.md",output),md);
}
if(!process.argv.includes("--publish") && !process.argv.includes("--verify")){
  console.log(JSON.stringify({prepared:plan.length,partial:plan.filter(i=>i.status==="partial").length,missing:plan.filter(i=>i.status==="missing").length,maxBodyBytes:Math.max(...plan.map(i=>Buffer.byteLength(i.body))),areas:Object.fromEntries(Object.keys(profiles).map(area=>[area,plan.filter(i=>i.area===area).length]))},null,2));
} else {
  let published=await existingIssues();
  await saveIndex(published);
  if(process.argv.includes("--verify")){
    const missing=plan.filter(i=>!published.has(i.id)).map(i=>i.id);
    const errors=[];
    const labelErrors=[];
    for(const item of plan){const live=published.get(item.id);if(live && (live.title!==item.title || live.body.replace(/\r\n/g,"\n").trim()!==item.body.trim()))errors.push(item.id);}
    for(const item of plan){const live=published.get(item.id);if(live && item.labels.some(name=>!live.labels.some(label=>label.name===name)))labelErrors.push(item.id);}
    console.log(JSON.stringify({published:published.size,expected:288,open:[...published.values()].filter(i=>i.state==="OPEN").length,missing,bodyMismatches:errors,labelMismatches:labelErrors},null,2));
    if(missing.length || errors.length || labelErrors.length)process.exitCode=1;
  } else {
    const labels={css:["1d76db","CSS feature compatibility backlog"],"baseline-2024":["0052cc","Cumulative CSS Baseline through 2024-12-31"],"css:missing":["b60205","No feature path in pinned source audit"],"css:partial":["fbca04","Partial analogue in pinned source audit"]};
    for(const [area,p] of Object.entries(profiles))labels[`area:${area}`]=["c5def5",p.name];
    const current=await gh(["label","list","--repo",repo,"--limit","100","--json","name"]);
    if(!current.ok)throw Error(current.stderr);
    const names=new Set(JSON.parse(current.stdout).map(i=>i.name));
    for(const [name,[color,description]] of Object.entries(labels))if(!names.has(name)){
      const r=await gh(["label","create",name,"--repo",repo,"--color",color,"--description",description]);
      if(!r.ok)throw Error(`Label ${name}: ${r.stderr}`);
      await sleep(1200);
    }
    console.log(`Starting/resuming at ${published.size}/288; sequential gh API requests with pacing.`);
    for(const item of plan){
      if(published.has(item.id))continue;
      let complete=false;
      for(let attempt=0;attempt<7 && !complete;attempt++){
        const payload=new URL("request.json",output);
        await writeFile(payload,JSON.stringify({title:item.title,body:item.body,labels:item.labels}),"utf8");
        const r=await gh(["api","--method","POST",`repos/${repo}/issues`,"--include","--input",fileURLToPath(payload)]);
        if(r.ok){
          const separator=r.stdout.search(/\r?\n\r?\n/);
          const json=JSON.parse(separator<0?r.stdout:r.stdout.slice(separator).trim());
          published.set(item.id,{number:json.number,url:json.html_url,title:json.title,body:json.body});
          await appendFile(new URL("publication-log.jsonl",output),JSON.stringify({id:item.id,number:json.number,url:json.html_url,at:new Date().toISOString()})+"\n");
          await saveIndex(published);
          console.log(`${published.size}/288 #${json.number} ${item.id}`);
          complete=true;
          await sleep(1200);
        } else {
          // Reconcile uncertain outcomes before retrying any creation request.
          published=await existingIssues();
          if(published.has(item.id)){await saveIndex(published);complete=true;console.log(`Reconciled ${item.id} after uncertain response`);break;}
          const diagnostic=(r.stdout+"\n"+r.stderr).slice(-2500);
          const retry=diagnostic.match(/retry-after:\s*(\d+)/i);
          const transient=/rate limit|secondary|abuse|HTTP (?:403|429|500|502|503|504)|timed out|connection|EOF/i.test(diagnostic);
          if(!transient)throw Error(`Creation failed for ${item.id}: ${diagnostic}`);
          const wait=retry?Number(retry[1])*1000:Math.min(60000*2**attempt,300000);
          console.log(`Rate/transient response for ${item.id}; waiting ${Math.ceil(wait/1000)}s before reconciled retry (${attempt+1}/7). ${diagnostic.slice(-400)}`);
          await sleep(wait);
        }
      }
      if(!complete)throw Error(`Could not publish ${item.id}; rerun --publish to resume without duplicates.`);
    }
    await saveIndex(published);
    console.log(`Published ${published.size}/288. Run --verify for independent remote reconciliation.`);
  }
}
