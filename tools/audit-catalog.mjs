// Documentation inventory only: fetch pinned WebDX data; never run app code.
import { createHash } from "node:crypto";
import { mkdir, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
const url = "https://unpkg.com/web-features@3.45.0/data.json";
const response = await fetch(url);
if (!response.ok) throw Error(`WebDX data: ${response.status}`);
const raw = await response.text();
const data = JSON.parse(raw);
const cutoff = "2024-12-31";
const catalog = [];
const chromeExtras = [];
for (const [id, feature] of Object.entries(data.features)) {
  if (feature.kind !== "feature") continue;
  const keys = (feature.compat_features || []).filter(key => key.startsWith("css."));
  if (!keys.length) continue;
  const status = key => feature.status.by_compat_key?.[key] || feature.status;
  const baseline = keys.filter(key => status(key).baseline_low_date && status(key).baseline_low_date <= cutoff);
  const chromeOnly = keys.filter(key => !baseline.includes(key) && /^\d+(?:\.\d+)?$/.test(String(status(key).support?.chrome)) && Number(status(key).support.chrome) <= 131);
  const row = selected => ({ id, name: feature.name, featureBaselineDate: feature.status.baseline_low_date ?? null,
    groups: feature.group || [], spec: feature.spec || [],
    keys: selected.map(key => ({ key, baselineDate: status(key).baseline_low_date ?? null, chrome: status(key).support?.chrome ?? null })) });
  if (baseline.length) catalog.push(row(baseline));
  if (chromeOnly.length) chromeExtras.push(row(chromeOnly));
}
catalog.sort((a, b) => a.id.localeCompare(b.id));
chromeExtras.sort((a, b) => a.id.localeCompare(b.id));
const metadata = { source: url, packageVersion: "3.45.0", retrieved: "2026-11-11", cutoff,
  sourceSha256: createHash("sha256").update(raw).digest("hex"),
  method: "WebDX kind=feature records with css.* compatibility keys; include each key whose own baseline_low_date is at most cutoff, falling back to group status only when no per-key status exists. Chrome supplement uses numeric support.chrome <=131 for remaining keys. Not a WPT pass rate or a complete Chrome BCD export." };
const directory = new URL("../docs/audit/", import.meta.url);
await mkdir(directory, { recursive: true });
await writeFile(new URL("baseline-2024-css.json", directory), JSON.stringify({ ...metadata, features: catalog }, null, 2) + "\n");
await writeFile(new URL("chrome-131-css-supplement.json", directory), JSON.stringify({ ...metadata, features: chromeExtras }, null, 2) + "\n");
console.log(JSON.stringify({ baselineFeatures: catalog.length, baselineKeys: catalog.reduce((sum, row) => sum + row.keys.length, 0), chromeSupplementFeatures: chromeExtras.length,
  names: catalog.map(row => row.id), directory: fileURLToPath(directory) }, null, 2));
