# /// script
# dependencies = []
# ///
"""Generate reference inputs and fetch the font for capture_positioning_edge.mjs."""
import json
import urllib.request

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "modules/ui_core/fixtures/positioning-browser.json"


def box(node_id, style, *children):
    return {"id": node_id, "style": {"display": "block", **style}, "children": list(children)}


def root(*children, **style):
    return box(1, {"position": "relative", "width": 200, "height": 120, "fontSize": 10, "lineHeight": "10px", **style}, *children)


def cases():
    for edge in ("left", "right"):
        text = box(2, {"position": "absolute", edge: 130, "top": 0})
        text["text"] = "aaaa aaaa aaaa"
        yield f"shrink-to-fit-{edge}", root(text)
    for width in (160, 240):
        yield f"reactive-resize-{width}", root(box(2, {"position": "absolute", "left": "calc(10% + 2px)", "right": 10, "top": "10%", "bottom": 5}), width=width)
    yield "nested-containing-block", root(box(2, {"position": "relative", "width": 100, "height": 60, "padding": 10, "borderWidth": 5, "borderStyle": "solid"}, box(3, {"height": 20}, box(4, {"position": "absolute", "right": 10, "bottom": 5, "width": 20, "height": 15}))))
    yield "min-wins-max", root(box(2, {"position": "absolute", "inset": 0, "width": 30, "minWidth": 60, "maxWidth": 40, "height": 10}))
    for direction in ("ltr", "rtl"):
        yield f"absolute-overconstraint-{direction}", root(box(2, {"position": "absolute", "left": 10, "right": 20, "top": 5, "width": 50, "height": 15}), direction=direction)
        yield f"negative-auto-margins-{direction}", root(box(2, {"position": "absolute", "inset": 10, "width": 220, "height": 140, "margin": "auto"}), direction=direction)
        for value in ("inline-start", "inline-end"):
            yield f"float-clear-{direction}-{value}", root(box(2, {"float": value, "width": 40, "height": 30}), box(3, {"float": value, "width": 50, "height": 20}), box(4, {"clear": value, "height": 10}), direction=direction)
        yield f"opposite-floats-{direction}", root(box(2, {"float": "inline-start", "width": 40, "height": 30}), box(3, {"float": "inline-end", "width": 50, "height": 20}), box(4, {"clear": "both", "height": 10}), direction=direction)
    yield "float-wrap", root(box(2, {"float": "left", "width": 140, "height": 30}), box(3, {"float": "right", "width": 100, "height": 20}), box(4, {"clear": "both", "height": 10}))
    yield "float-inline-exclusion", root(box(2, {"float": "left", "width": 40, "height": 30}), box(3, {"display": "inline-block", "width": 50, "height": 20}), box(4, {"clear": "both", "height": 10}))
    yield "float-bfc-avoidance", root(box(2, {"float": "left", "width": 40, "height": 30}), box(3, {"display": "flow-root", "height": 10}))
    yield "float-bfc-clearance", root(box(2, {"float": "left", "width": 140, "height": 30}), box(3, {"display": "flow-root", "width": 100, "height": 10}))
    yield "float-flow-root-height", root(box(2, {"float": "left", "width": 40, "height": 30}), display="flow-root", height="auto")
    yield "block-static-relative-sibling", root(box(2, {"position": "relative", "top": 30, "height": 20, "marginBottom": 12}), box(3, {"position": "absolute", "width": 15, "height": 10}), padding=10)
    yield "inline-static", root(box(2, {"display": "inline-block", "width": 40, "height": 10, "verticalAlign": "top"}), box(3, {"position": "absolute", "display": "inline", "width": 15, "height": 10}))
    yield "grid-area", root(box(2, {"position": "absolute", "gridColumn": "2 / 3", "gridRow": "2 / 3", "inset": 0}), display="grid", gridTemplateColumns="80px 120px", gridTemplateRows="40px 80px")
    yield "fixed-perspective", root(box(2, {"perspective": "400px", "padding": 10, "width": 100, "height": 80}, box(3, {"height": 50}, box(4, {"position": "fixed", "left": 5, "top": 7, "width": 10, "height": 10}))), padding=20)
    yield "fixed-viewport", root(box(2, {"position": "fixed", "left": 15, "top": 10, "width": 40, "height": 20}), padding=20)
    for mode in ("horizontal-tb", "vertical-rl", "vertical-lr", "sideways-rl", "sideways-lr"):
        for direction in ("ltr", "rtl"):
            for value in ("inline-start", "inline-end"):
                yield f"vertical-float-clear-{mode}-{direction}-{value}", root(box(2, {"float": value, "width": 40, "height": 30}), box(3, {"clear": value, "width": 10, "height": 20}), writingMode=mode, direction=direction)
            yield f"logical-insets-{mode}-{direction}", root(box(2, {"position": "absolute", "insetInlineStart": 10, "insetBlockStart": 20, "width": 30, "height": 15}), writingMode=mode, direction=direction)
            yield f"logical-corners-{mode}-{direction}", root(box(2, {"position": "absolute", "inset": 0, "width": 80, "height": 60, "borderStartStartRadius": "11px 7px", "borderStartEndRadius": "13px 9px", "borderEndStartRadius": "17px 12px", "borderEndEndRadius": "19px 14px"}), writingMode=mode, direction=direction)


def main():
    OUT.parent.mkdir(parents=True, exist_ok=True)
    font = OUT.parent / "Ahem.ttf"
    if not font.exists():
        with urllib.request.urlopen("https://wpt.live/fonts/Ahem.ttf", timeout=30) as response:
            font.write_bytes(response.read())
    source = OUT.with_name("positioning-source.json")
    source.write_text(json.dumps([{"name": name, "tree": tree} for name, tree in cases()], indent=2) + "\n", encoding="utf-8")
    print(f"Prepared browser input cases in {source}")


if __name__ == "__main__":
    main()
