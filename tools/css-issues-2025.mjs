// Prepare/publish only CSS keys that first reached Baseline during 2025.
// Independent of the 2024 publisher: distinct files, markers and labels.
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile, appendFile, open, unlink } from "node:fs/promises";
import { fileURLToPath } from "node:url";
const exec = promisify(execFile);
const root = new URL("../", import.meta.url);
const directory = new URL("docs/issues-2025/", root);
const repo = "RoboXGamer/SolidNativeZigExperiment";
const web = `https://github.com/${repo}`;
const start = "2025-01-01", end = "2025-12-31";
const dataURL = "https://unpkg.com/web-features@3.45.0/data.json";
const baseline = JSON.parse(await readFile(new URL("docs/audit/baseline-2024-css.json", root), "utf8"));
const oldIds = new Set(baseline.features.map(f => f.id));
const oldKeys = new Set(baseline.features.flatMap(f => f.keys.map(k => k.key)));
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
async function gh(args) {
  try { return {ok:true,...await exec("gh",args,{cwd:fileURLToPath(root),windowsHide:true,maxBuffer:32*1024*1024})}; }
  catch(error) { return {ok:false,stdout:String(error.stdout||""),stderr:String(error.stderr||error.message)}; }
}
async function loadCatalog() {
  try { const cached=JSON.parse(await readFile(new URL("catalog.json",directory),"utf8"));
    if(cached.source!==dataURL || cached.sourceSha256!==baseline.sourceSha256 || cached.start!==start || cached.end!==end)throw Error("Cached 2025 catalog metadata differs from pinned source");
    return cached;
  } catch(error) { if(error.code!=="ENOENT")throw error; }
  const response=await fetch(dataURL);
  if(!response.ok)throw Error(`WebDX data: ${response.status}`);
  const raw=await response.text();
  const hash=createHash("sha256").update(raw).digest("hex");
  if(hash!==baseline.sourceSha256)throw Error("Pinned WebDX source checksum differs from the 2024 catalog");
  const data=JSON.parse(raw), features=[];
  for(const [id,f] of Object.entries(data.features)){
    if(f.kind!=="feature")continue;
    const keys=(f.compat_features||[]).filter(key=>key.startsWith("css.")).flatMap(key=>{
      const status=f.status.by_compat_key?.[key]||f.status;
      const date=status.baseline_low_date;
      return date && date>=start && date<=end ? [{key,baselineDate:date,chrome:status.support?.chrome??null}] : [];
    });
    if(keys.length)features.push({id,name:f.name,groups:f.group||[],spec:f.spec||[],keys,extends2024Group:oldIds.has(id)});
  }
  features.sort((a,b)=>a.id.localeCompare(b.id));
  const catalog={source:dataURL,sourceSha256:hash,packageVersion:"3.45.0",start,end,features};
  await writeFile(new URL("catalog.json",directory),JSON.stringify(catalog,null,2)+"\n");
  return catalog;
}
function area(f) {
  const g=new Set(f.groups), keys=f.keys.map(k=>k.key).join(" "), id=f.id;
  if(/^(starting-style|transform-box|will-change)$/.test(id)||["animation","transitions","transforms"].some(x=>g.has(x)))return "motion";
  if(["media-queries","container-queries","units","environment-variables"].some(x=>g.has(x))||/viewport|calc|trig|round-mod-rem|supports/.test(id))return "responsive";
  if(g.has("selectors")||keys.includes("css.selectors."))return "selectors";
  if(["fonts","font-features","font-synthesis","text","text-wrap","white-space","ruby"].some(x=>g.has(x))||/^font-|^text-|^line-|^word-/.test(id))return "typography";
  if(g.has("scrolling")||/^overflow|^scroll|^overscroll/.test(id))return "scrolling";
  if(["background","color-types","clipping-shapes-masking","blend-mode","gradients","borders-outlines","images"].some(x=>g.has(x))||/color|background|shadow|mask|shape|filter/.test(id))return "painting";
  if(["layout","positioning","grid","flexbox","containment","multi-column"].some(x=>g.has(x))||/display|sizing|position|aspect-ratio|width|height|margin|padding|logical/.test(id))return "layout";
  if(["html","html-elements","forms","svg","mathml","web-components","custom-elements","print"].some(x=>g.has(x)))return "platform";
  return "styling";
}
const contracts={
  layout:["Resolve typed specified/computed/used sizes and applicable containing-block/definiteness rules.","Integrate with box generation and the affected block/flex/grid/leaf path; propagate final geometry rather than adding transport-only fields.","Cover exact nested/constraint/zero/auto/percentage and logical-axis cases with specification/browser fixtures."],
  typography:["Implement eligible font/text computation and actual run/line/shaping behavior, including font and inherited-style dependencies.","Use the same resolved runs and metrics for intrinsic sizing, layout, painting and selection/hit geometry.","Cover deterministic fonts, line/break boundaries and multilingual/writing-mode cases with exact expected results."],
  painting:["Implement eligible values and actual native paint/compositor behavior, with correct reference boxes and resource ownership.","Keep paint bounds, clipping/stacking, overflow and hit geometry consistent; do not substitute a simple rectangle for the specified effect.","Cover nested/translucent/clipped/resized and relevant device-scale cases against deterministic browser output."],
  motion:["Implement the eligible value/timing/interpolation/composition or transform semantics on the native rendering path.","Coordinate start/update/cancel/finish, paint/layout/hit regions and event-driven scheduling rather than treating a timeout shim as CSS motion support.","Use controlled-clock, nested, interrupted/reversed and reduced-motion cases against the appropriate browser behavior."],
  selectors:["Implement eligible selector/pseudo syntax, matching, specificity and scoping rules.","Provide the semantic state/tree relationships or generated boxes and invalidate matches after relevant changes.","Cover positive/negative matches, specificity, mutation/state transitions and native output/disposal."],
  responsive:["Represent the eligible contextual units/query/math syntax as typed values; never discard suffixes with parseFloat.","Supply real viewport/font/container/environment dependencies and re-evaluate after relevant context changes.","Cover exact boundaries, missing/indefinite contexts, valid/invalid syntax and reactive changes against a frozen browser fixture."],
  scrolling:["Implement eligible axis, overflow/scroll-container, clipping and formatting-context semantics.","Integrate propagated descendant overflow, scroll geometry, focus/input/programmatic behavior and nested scrolling.","Cover overflowing/no-overflow, nested edges, resizing and focus/pointer/keyboard cases with exact expected state/geometry."],
  platform:["Implement the eligible CSS hook in its required semantic native control/HTML/SVG/MathML/print context, not merely an arbitrary JSX container.","Integrate computed styling, box/paint generation and necessary platform/input/accessibility state while preserving Solid ownership.","Cover actual context, nesting/state changes and lifecycle; limit the ticket to these CSS keys rather than automatically claiming the entire surrounding Web API."],
  styling:["Implement valid syntax, typed specified/computed values, invalid-value handling and applicable cascade/inheritance rules.","Connect the computed result to the real native layout/paint/semantic consumer with dependency invalidation.","Cover authoring/bridge/native behavior, precedence/defaults and reactive changes against the pinned keys and specification."],
};
await mkdir(directory,{recursive:true});
const catalog=await loadCatalog();
if(!catalog.features.length)throw Error("No 2025 CSS additions found");
for(const f of catalog.features)for(const k of f.keys)if(oldKeys.has(k.key))throw Error(`2024 scope duplicated: ${k.key}`);
const search=(year,id)=>`${web}/issues?q=${encodeURIComponent(`is:issue in:title "[CSS ${year}]" "(${id})"`)}`;
const plan=catalog.features.map(f=>{
  const group=area(f), marker=`<!-- solid-native-css-baseline:2025:${f.id} -->`;
  return {id:f.id,area:group,marker,title:`[CSS 2025 additions] ${f.name} (${f.id})`,labels:["enhancement","css","baseline-2025","css:needs-audit",`area:${group}`],body:`${marker}
## Goal and exact scope

Implement **${f.name}** (WebDX ID \`${f.id}\`) for **only the ${f.keys.length} CSS compatibility key${f.keys.length===1?"":"s"} that first reached Baseline between ${start} and ${end}**. Earlier keys belong to the 2024 backlog; 2026+, limited-availability and Chrome-only additions are excluded.

${f.extends2024Group?`This extends a group already represented in the [2024 ticket](${search(2024,f.id)}). Coordinate implementation, but do not repeat or close that ticket's older requirements here.`:"This feature group has no entry in the pinned 2024 CSS inventory."}

## Current implementation status

**Needs a current source audit.** The previous audit targeted 2024 and does not establish completion or exact missing/partial behavior for these newer keys. Check the latest implementation and box/sizing changes; record concrete supported paths and gaps before claiming support. Merely exporting a value or accepting a style field is insufficient.

## Required work and acceptance

${contracts[group].map(s=>`- [ ] ${s}`).join("\n")}
- [ ] Cover every eligible key/value/context in the table, with invalid and negative cases where applicable.
- [ ] Name related 2024 foundation tickets and concrete external dependencies; keep unavailable behavior explicitly open rather than silently dropping it.
- [ ] Record applicable specification/WPT fixture IDs and a fixed browser/platform/font/DPI oracle where relevant.
- [ ] Exercise the native authoring -> bridge -> computed style -> layout/paint/state path, including changes and disposal.
- [ ] Record implementing commits and actual executed verification. Respect any active testing pause; unexecuted fixtures are not passing results.

## Eligible 2025 additions

| Compatibility key | Baseline newly available | Chrome metadata |
| --- | --- | --- |
${f.keys.map(k=>`| \`${k.key}\` | ${k.baselineDate} | ${k.chrome??"not recorded"} |`).join("\n")}

## References

${f.spec.map(s=>`- [Specification](${s})`).join("\n")}
- [Pinned WebDX source: web-features@3.45.0](${dataURL}) (SHA-256: \`${catalog.sourceSha256}\`).
- [2024 foundation backlog](${web}/issues?q=is%3Aissue%20label%3Abaseline-2024).
- [Source audit and named architectural gaps](${web}/blob/c4a9b4a3567424a2601af21634e37cc2a2c46631/docs/compatibility-audit-2026-11-11.md).
- [Native layout core](${web}/tree/master/modules/ui_core), [Solid adapter](${web}/tree/master/packages/solid-zig), [Raylib backend](${web}/blob/master/src/windows.zig).

Area: **${group}**. WebDX groups: ${f.groups.map(g=>`\`${g}\``).join(", ")||"unassigned"}. Current specification pages may include newer additions; this table is the ticket's date-limited denominator, not a claim of measured conformance.
`};
});
if(new Set(plan.map(i=>i.id)).size!==plan.length||new Set(plan.map(i=>i.title)).size!==plan.length)throw Error("Duplicate issue plan");
if(plan.some(i=>Buffer.byteLength(i.body)>60000))throw Error("Issue body exceeds safe size");
await writeFile(new URL("manifest.json",directory),JSON.stringify({repo,start,end,issues:plan},null,2)+"\n");

async function remoteIssues(){
  const r=await gh(["issue","list","--repo",repo,"--state","all","--limit","1000","--json","number,title,body,url,state,labels"]);
  if(!r.ok)throw Error(r.stderr);
  return JSON.parse(r.stdout);
}
function byYear(issues,year){
  const found=new Map(), regex=new RegExp(`<!-- solid-native-css-baseline:${year}:([a-z0-9-]+) -->`);
  for(const issue of issues){const m=issue.body?.match(regex);if(m){if(found.has(m[1]))throw Error(`Duplicate ${year} issue marker: ${m[1]}`);found.set(m[1],issue);}}
  return found;
}
async function save(found){
  const published=plan.filter(i=>found.has(i.id)).map(i=>({id:i.id,number:found.get(i.id).number,url:found.get(i.id).url}));
  await writeFile(new URL("published.json",directory),JSON.stringify({repo,total:plan.length,published:published.length,issues:published},null,2)+"\n");
  await writeFile(new URL("README.md",directory),`# Baseline 2025 CSS additions\n\n${plan.length} issue groups, ${catalog.features.reduce((n,f)=>n+f.keys.length,0)} CSS keys first Baseline during 2025. ${catalog.features.filter(f=>f.extends2024Group).length} groups extend older 2024 groups with **different keys**. No 2024 key is repeated. Current source status is unassessed, not presumed complete.\n\nPrepare: \`node tools/css-issues-2025.mjs\`. Publish after the 288-ticket 2024 batch: \`node tools/css-issues-2025.mjs --publish\`. Verify: \`node tools/css-issues-2025.mjs --verify\`. Publishing is paced, checks existing markers and can be rerun to resume. Output is isolated from docs/issues.\n\nPublished ${published.length}/${plan.length}.\n\n| Feature | Issue |\n| --- | --- |\n${published.map(i=>`| ${i.id} | [#${i.number}](${i.url}) |`).join("\n")}\n`);
}
const publishing=process.argv.includes("--publish"), verifying=process.argv.includes("--verify");
if(!publishing&&!verifying){
  // Preparation never queries/mutates GitHub and never resets live progress.
  let found=new Map();
  try{const saved=JSON.parse(await readFile(new URL("published.json",directory),"utf8"));found=new Map(saved.issues.map(i=>[i.id,i]));}catch(e){if(e.code!=="ENOENT")throw e;}
  await save(found);
  console.log(JSON.stringify({prepared:plan.length,newGroupNames:catalog.features.filter(f=>!f.extends2024Group).length,extending2024Groups:catalog.features.filter(f=>f.extends2024Group).length,eligible2025Keys:catalog.features.reduce((n,f)=>n+f.keys.length,0),duplicate2024Keys:0,publishedNow:0},null,2));
} else if(verifying){
  const found=byYear(await remoteIssues(),2025);await save(found);
  const missing=plan.filter(i=>!found.has(i.id)).map(i=>i.id),mismatches=[];
  for(const i of plan){const live=found.get(i.id);if(live&&(live.title!==i.title||live.body.replace(/\r\n/g,"\n").trim()!==i.body.trim()||i.labels.some(label=>!live.labels.some(x=>x.name===label))))mismatches.push(i.id);}
  console.log(JSON.stringify({expected:plan.length,published:found.size,missing,mismatches},null,2));
  if(missing.length||mismatches.length)process.exitCode=1;
} else {
  // A separate per-year lock prevents concurrent 2025 publication.
  const lockURL=new URL("publisher.lock",directory);
  let lock;
  try{lock=await open(lockURL,"wx");await lock.writeFile(JSON.stringify({pid:process.pid}));}
  catch(e){if(e.code!=="EEXIST")throw e;const previous=JSON.parse(await readFile(lockURL,"utf8"));let live=true;try{process.kill(previous.pid,0);}catch(error){if(error.code==="ESRCH")live=false;else throw error;}if(live)throw Error(`2025 publisher already running (PID ${previous.pid})`);await unlink(lockURL);lock=await open(lockURL,"wx");await lock.writeFile(JSON.stringify({pid:process.pid}));}
  try{
    const all=await remoteIssues(), old=byYear(all,2024);let found=byYear(all,2025);
    const missing2024=baseline.features.filter(f=>!old.has(f.id));
    if(missing2024.length)throw Error(`Finish the 2024 publisher first: ${old.size}/288 present (${missing2024.length} missing).`);
    await save(found);
    const labels={css:["1d76db","CSS feature compatibility backlog"],"baseline-2025":["0052cc","CSS additions newly Baseline during calendar 2025"],"css:needs-audit":["d4c5f9","Needs source assessment for the stated feature/date scope"]};
    for(const a of new Set(plan.map(i=>i.area)))labels[`area:${a}`]=["c5def5",`CSS ${a} integration`];
    const r=await gh(["label","list","--repo",repo,"--limit","100","--json","name"]);if(!r.ok)throw Error(r.stderr);
    const names=new Set(JSON.parse(r.stdout).map(i=>i.name));
    for(const [name,[color,description]]of Object.entries(labels))if(!names.has(name)){const r=await gh(["label","create",name,"--repo",repo,"--color",color,"--description",description]);if(!r.ok)throw Error(r.stderr);await pause(1200);}
    console.log(`Publishing 2025 additions: ${found.size}/${plan.length} already exist.`);
    for(const item of plan){
      if(found.has(item.id))continue;
      let done=false;
      for(let attempt=0;attempt<7&&!done;attempt++){
        const request=new URL("request.json",directory);await writeFile(request,JSON.stringify({title:item.title,body:item.body,labels:item.labels}),"utf8");
        const r=await gh(["api","--method","POST",`repos/${repo}/issues`,"--include","--input",fileURLToPath(request)]);
        if(r.ok){const offset=r.stdout.search(/\r?\n\r?\n/),live=JSON.parse(offset<0?r.stdout:r.stdout.slice(offset).trim());const issue={number:live.number,url:live.html_url};found.set(item.id,issue);await appendFile(new URL("publication-log.jsonl",directory),JSON.stringify({id:item.id,...issue,at:new Date().toISOString()})+"\n");await save(found);console.log(`${found.size}/${plan.length} #${issue.number} ${item.id}`);done=true;await pause(1200);}
        else{found=byYear(await remoteIssues(),2025);if(found.has(item.id)){await save(found);done=true;break;}const message=(r.stdout+"\n"+r.stderr).slice(-2000);if(!/rate limit|secondary|abuse|HTTP (?:403|429|500|502|503|504)|timed out|connection|EOF/i.test(message))throw Error(message);const retry=message.match(/retry-after:\s*(\d+)/i),delay=retry?Number(retry[1])*1000:Math.min(60000*2**attempt,300000);console.log(`Transient/rate response; waiting ${Math.ceil(delay/1000)}s before reconciled retry.`);await pause(delay);}
      }
      if(!done)throw Error(`Could not publish ${item.id}; rerun --publish to resume.`);
    }
    console.log(`Published ${found.size}/${plan.length} 2025 addition issues. Run --verify afterward.`);
  } finally {await lock.close();await unlink(lockURL);}
}
