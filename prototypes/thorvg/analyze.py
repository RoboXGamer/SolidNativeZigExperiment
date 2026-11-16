# /// script
# dependencies = ["pillow==12.0.0"]
# ///
"""Convert native readback artifacts; report backend differences without hiding them."""
from pathlib import Path
import csv
import hashlib
import json
from PIL import Image, ImageChops

def main():
    base = Path(__file__).parent / "artifacts"
    binaries = Path(__file__).parent / ".build"
    built = [binaries/"probe.exe",binaries/"abi-smoke.exe",binaries/"glfw3.dll",binaries/"tvg/src/libthorvg-1.a"]
    info={p.name:{"bytes":p.stat().st_size,"sha256":hashlib.sha256(p.read_bytes()).hexdigest()} for p in built if p.exists()}
    (base/"build-info.json").write_text(json.dumps(info,indent=2)+"\n",encoding="utf-8")
    for file in base.glob("*.ppm"):
        image = Image.open(file)
        image.save(file.with_suffix(".png"))
    sw = Image.open(base / "sw-full.png").convert("RGB")
    gl = Image.open(base / "gl-full.png").convert("RGB")
    for point in [(60,470),(200,470),(200,475),(30,300),(375,300),(200,125)]:
        print(point, "software", sw.getpixel(point), "GL", gl.getpixel(point))
    diff = ImageChops.difference(sw,gl)
    pixels = list(diff.getdata())
    print("CPU/GL max RGB error", max(max(p) for p in pixels))
    print("CPU/GL pixels error > 8", sum(max(p)>8 for p in pixels))
    diff.save(base / "cpu-gl-difference.png")
    comparisons = {
        "cpu_gl_max_rgb_error": max(max(p) for p in pixels),
        "cpu_gl_pixels_error_gt8": sum(max(p)>8 for p in pixels),
        "viewport": [800,600],
        "cpu_full_smart_identical": Image.open(base/"sw-full.png").tobytes() == Image.open(base/"sw-smart.png").tobytes(),
    }
    (base/"image-analysis.json").write_text(json.dumps(comparisons,indent=2)+"\n",encoding="utf-8")
    (base/"image-sha256.json").write_text(json.dumps({p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(base.glob("*.png"))},indent=2)+"\n",encoding="utf-8")
    if not (base/"samples.csv").exists():
        return
    rows=list(csv.DictReader((base/"timings.csv").open()))
    measured=list(csv.DictReader((base/"samples.csv").open()))
    log=(base/"run.txt").read_text(encoding="utf-8-sig")
    validation={"matrix_rows":len(rows),"raw_samples":len(measured),"warmups_per_row":20,"samples_per_row":100,"pass_assertions":sum(line.startswith("PASS ") for line in log.splitlines()),"fail_assertions":sum(line.startswith("FAIL ") for line in log.splitlines()),"successful_exit_marker":"ASSERTION_FAILURES=0" in log}
    assert len(rows)==144 and len(measured)==14400, validation
    assert validation["fail_assertions"]==0 and validation["successful_exit_marker"], validation
    for r in rows:
        group=[x for x in measured if all(x[k]==r[k] for k in ["backend","mode","shadow","boards","workload"])]
        assert len(group)==100
        ordered=sorted(float(x["ms"]) for x in group)
        assert abs(ordered[50]-float(r["p50_ms"]))<0.0002
        assert abs(ordered[94]-float(r["p95_ms"]))<0.0002
    (base/"validation.json").write_text(json.dumps(validation,indent=2)+"\n",encoding="utf-8")
    table=["# Complete measured matrix", "", "Milliseconds; 20 warmups + 100 measured samples per row. Includes mutations/update/draw/sync; GL also glFinish. See README for exclusions.", "", "| Backend | Mode | Shadow | Boards | Paints | Workload | Mean | p50 | p95 | Max | Probe damage px |", "|---|---|---|---:|---:|---|---:|---:|---:|---:|---:|"]
    for r in rows:
        table.append("| "+" | ".join([r[k] for k in ["backend","mode","shadow","boards","paint_objects","workload"]]+[f"{float(r[k]):.4f}" for k in ["mean_ms","p50_ms","p95_ms","max_ms"]]+[r["probe_dirty_area"]])+" |")
    (base/"matrix.md").write_text("\n".join(table)+"\n",encoding="utf-8")
    selected=[]
    for boards in ["1","64"]:
        keys=[("sw","smart-request","cached-bitmap","hover","SW sparse, cached shadow"),("sw","smart-request","cached-bitmap","forced-full-hover","SW forced full, cached shadow"),("sw-upload","smart-request","cached-bitmap","hover-plus-full-upload","SW sparse + full upload"),("gl","none","cached-bitmap","hover","GL retained, cached shadow"),("sw","smart-request","live-bounded","hover","SW sparse, live bounded shadow")]
        group=[]
        for backend,mode,shadow,workload,label in keys:
            matches=[r for r in rows if (r["backend"],r["mode"],r["shadow"],r["workload"],r["boards"])==(backend,mode,shadow,workload,boards)]
            if matches: group.append((label,float(matches[0]["p50_ms"]),float(matches[0]["p95_ms"])))
        selected.append((boards,group))
    summary=["# Selected matched results", "", "1280 x 800, 20 warmups, 100 samples, milliseconds. All GL frames clear and wait for completion. The same cached shadow is used by the first four cases.", "", "| Boards | Case | p50 ms | p95 ms |", "|---:|---|---:|---:|"]
    for boards,group in selected:
        for label,median,p95 in group:
            summary.append(f"| {boards} | {label} | {median:.4f} | {p95:.4f} |")
    (base/"selected.md").write_text("\n".join(summary)+"\n",encoding="utf-8")
    html=['<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>body{font:14px var(--font-sans);color:var(--foreground)}h3{font-size:15px;margin:20px 0 10px}.row{display:grid;grid-template-columns:minmax(150px,240px) 1fr 90px;gap:8px;align-items:center;margin:9px 0}.track{height:18px;background:var(--secondary);border-radius:3px}.bar{height:18px;background:var(--chart-1);border-radius:3px}.number{font-family:var(--font-mono);font-size:12px}.note{font-size:12px;color:var(--muted-foreground)}@media(max-width:500px){.row{grid-template-columns:150px 1fr 75px}}</style></head><body>']
    html.append('<div class="note">ThorVG 1.1.3 · Intel GL 3.3 · 1280 × 800 · scalar SW · p50 bars, p95 in parentheses · ms</div>')
    for boards,group in selected:
        html.append(f'<h3>{boards} board(s)</h3>')
        top=max((v for _,v,_ in group),default=1)
        for label,median,p95 in group:
            html.append(f'<div class="row"><span>{label}</span><div class="track"><div class="bar" style="width:{median/top*100:.2f}%"></div></div><span class="number">{median:.2f} ({p95:.2f})</span></div>')
    html.append('<p class="note">100 samples after 20 warmups. GL includes forced completion; no swap, vsync, JS, layout, text rebuild or OS input. Live effects can defeat sparse redraw. Synthetic retained workload; no claim about end-to-end hover.</p>')
    html.append('</body></html>')
    (base/"comparison.html").write_text("\n".join(html),encoding="utf-8")

if __name__ == "__main__":
    main()
