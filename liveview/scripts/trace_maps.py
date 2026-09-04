"""Trace the legacy map GIF silhouettes into SVG geometry for GameLive.WorldMap.

For each map (`original`, `elements`) this reads `<tech>0.gif` (black silhouette on
transparency) for every area from the legacy ASP.NET project's `Web/wwwroot/maps/<map>/`
(the LiveView app no longer ships those sprites — this script is the only consumer left),
places it on the legacy 800x480 board at the coordinates from `MapInfo.render_info/2`, and
emits:

  - one SVG path per area (all islands, holes preserved, smoothed)
  - a label anchor per area (approximate pole of inaccessibility)
  - links: for every adjacency whose silhouettes do not touch, a line between the two
    closest boundary points (sea lanes on the world map, the arrow routes on elements;
    Alaska <-> Pevek wraps off the board edges)
  - region outlines: union of each region's masks, traced
  - a viewBox per map (the world map fills the legacy board; elements is cropped to its art)

Outputs `lib/global_combat_web/live/game_live/map_geometry.ex` (labels, elements, viewBoxes)
and one static HEEx `<defs>` template per map under `lib/global_combat_web/live/game_live/world_map/`.

Usage (from liveview/): python3 -m venv .venv && .venv/bin/pip install pillow numpy
                        .venv/bin/python scripts/trace_maps.py . && mix format
"""
import re, sys
import numpy as np
from PIL import Image

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."   # liveview dir
OUT_EX = f"{ROOT}/lib/global_combat_web/live/game_live/map_geometry.ex"
OUT_HEEX = f"{ROOT}/lib/global_combat_web/live/game_live/world_map/{{map}}_map_defs.html.heex"
W, H = 800, 480   # the legacy board every MapInfo offset is expressed in
MIN_LINK = 9      # closer than this and two silhouettes are touching (anti-aliased land border)
WRAP_LINK = 300   # farther than this and the link wraps off the board edges (Alaska <-> Pevek)

src = open(f"{ROOT}/lib/global_combat/engine/map_info.ex").read()

def parse_map(name):
    render = re.findall(r'\{(\d+), "(\w+)", (\d+), (\d+), (\d+), (\d+)\}',
                        src.split(f"@{name}_render [")[1].split("]")[0])
    topo = re.findall(r'\{(\d+), "([^"]+)", (\d+), \[([\d, ]+)\]\}',
                      src.split(f"@{name}_areas [")[1].split("]\n")[0])
    links = {int(n): [int(x) for x in l.split(",")] for n, _, _, l in topo}
    region_of = {int(n): int(r) for n, _, r, _ in topo}
    return render, links, region_of

def mask_for(map_name, tech, x, y, w, h):
    im = Image.open(f"{ROOT}/../Web/wwwroot/maps/{map_name}/{tech}0.gif").convert("RGBA")
    a = np.array(im)[:, :, 3] > 0
    if a.shape != (h, w):
        raise SystemExit(f"{map_name}/{tech}: gif {a.shape} != render {(h, w)}")
    m = np.zeros((H, W), bool)
    m[y:y+h, x:x+w] = a
    return m

# ---------- boundary tracing ----------
def loops_from_mask(m):
    """Closed loops of (x, y) pixel-corner points: clockwise for outer boundaries,
    counter-clockwise for holes."""
    padded = np.pad(m, 1)
    edges = {}  # start -> list of ends
    ys, xs = np.nonzero(padded)
    def add(a, b):
        edges.setdefault(a, []).append(b)
    for r, c in zip(ys, xs):
        x, y = c - 1, r - 1
        if not padded[r-1, c]: add((x, y), (x+1, y))       # top: left->right
        if not padded[r, c+1]: add((x+1, y), (x+1, y+1))   # right: top->bottom
        if not padded[r+1, c]: add((x+1, y+1), (x, y+1))   # bottom: right->left
        if not padded[r, c-1]: add((x, y+1), (x, y))       # left: bottom->top
    loops = []
    while edges:
        start = next(iter(edges))
        loop = [start]
        cur = start
        prev_dir = None
        while True:
            outs = edges[cur]
            if len(outs) == 1 or prev_dir is None:
                nxt = outs.pop()
            else:
                # saddle corner: prefer the right turn to keep loops from merging
                dx, dy = prev_dir
                right = (-dy, dx)
                pick = next((c for c in outs if (c[0]-cur[0], c[1]-cur[1]) == right), outs[0])
                outs.remove(pick); nxt = pick
            if not outs: del edges[cur]
            prev_dir = (nxt[0]-cur[0], nxt[1]-cur[1])
            cur = nxt
            if cur == start: break
            loop.append(cur)
        loops.append(loop)
    return loops

def signed_area(pts):
    s = 0
    for i in range(len(pts)):
        x1, y1 = pts[i]; x2, y2 = pts[(i+1) % len(pts)]
        s += x1*y2 - x2*y1
    return s / 2

def chaikin(pts, iters=2):
    for _ in range(iters):
        out = []
        n = len(pts)
        for i in range(n):
            p, q = pts[i], pts[(i+1) % n]
            out.append((0.75*p[0]+0.25*q[0], 0.75*p[1]+0.25*q[1]))
            out.append((0.25*p[0]+0.75*q[0], 0.25*p[1]+0.75*q[1]))
        pts = out
    return pts

def rdp(pts, eps):
    """Ramer-Douglas-Peucker on a closed loop (split at two far-apart anchors)."""
    if len(pts) < 4: return pts
    def _rdp(seg):
        if len(seg) < 3: return seg
        a, b = np.array(seg[0]), np.array(seg[-1])
        ab = b - a; L = np.hypot(*ab) or 1e-9
        d = [abs((p[0]-a[0])*ab[1] - (p[1]-a[1])*ab[0]) / L for p in seg[1:-1]]
        i = int(np.argmax(d)) + 1
        if d[i-1] > eps:
            return _rdp(seg[:i+1])[:-1] + _rdp(seg[i:])
        return [seg[0], seg[-1]]
    a = np.array(pts[0])
    far = int(np.argmax([np.hypot(p[0]-a[0], p[1]-a[1]) for p in pts]))
    first = _rdp(pts[:far+1])
    second = _rdp(pts[far:] + [pts[0]])
    return first[:-1] + second[:-1]

def poly_path(pts):
    """Closed polyline path string, 1 decimal. Chaikin smoothing above already rounds the
    pixel staircase off, so straight segments between the survivors render smooth at any
    board size while costing a third of what cubic curves would."""
    if len(pts) < 3:
        return None
    f = lambda v: f"{v:.1f}".replace(".0", "")
    return "M" + "L".join(f"{f(x)} {f(y)}" for x, y in pts) + "Z"

def trace(m, min_area=3.0, eps=0.8, smooth=2):
    parts = []
    for loop in loops_from_mask(m):
        if abs(signed_area(loop)) < min_area:
            continue   # stray specks of dithering
        p = poly_path(rdp(chaikin(loop, smooth), eps))
        if p: parts.append(p)
    return "".join(parts)

def pole(m):
    """Erode until (nearly) gone; centroid of the last survivors."""
    cur = m.copy()
    last = cur
    while cur.any():
        last = cur
        padded = np.pad(cur, 1)
        cur = padded[1:-1,1:-1] & padded[:-2,1:-1] & padded[2:,1:-1] & padded[1:-1,:-2] & padded[1:-1,2:]
    ys, xs = np.nonzero(last)
    return (round(float(xs.mean()) + 0.5, 1), round(float(ys.mean()) + 0.5, 1))

def dilate(m, r=1):
    padded = np.pad(m, r)
    out = np.zeros_like(m)
    for dy in range(-r, r+1):
        for dx in range(-r, r+1):
            out |= padded[r+dy:r+dy+H, r+dx:r+dx+W]
    return out

def boundary_pts(m):
    inner = m & dilate(~m, 1)
    ys, xs = np.nonzero(inner)
    return np.stack([xs + 0.5, ys + 0.5], 1)

def rp(v): return round(float(v), 1)

# The elements map's tech names carry the element in their first letter (f/w/a/e; the
# corners are c<element>, the bridges b<smoke|mud>). WorldMap styles a per-element
# texture off this; the world map has none.
ELEMENTS = {"f": "fire", "w": "water", "a": "wind", "e": "earth"}
def element_of(map_name, tech):
    if map_name != "elements": return None
    key = tech[1] if tech[0] == "c" else tech[0]
    return ELEMENTS.get(key)

def build(map_name):
    render, links, region_of = parse_map(map_name)
    masks, paths, labels, elements = {}, {}, {}, {}
    for n, tech, x, y, w, h in render:
        n = int(n)
        m = mask_for(map_name, tech, int(x), int(y), int(w), int(h))
        masks[n] = m
        paths[n] = trace(m)
        labels[n] = pole(m)
        elements[n] = element_of(map_name, tech)
        print(f"{map_name} {n:2d} {tech:12s} px={int(m.sum()):5d} pathlen={len(paths[n]):5d}", file=sys.stderr)

    # links between areas whose silhouettes don't touch
    link_lines = []
    seen = set()
    for a, neighbours in links.items():
        for b in neighbours:
            key = tuple(sorted((a, b)))
            if key in seen: continue
            seen.add(key)
            if (dilate(masks[a], 2) & masks[b]).any():
                continue
            A, B = boundary_pts(masks[a]), boundary_pts(masks[b])
            d = np.hypot(A[:, None, 0] - B[None, :, 0], A[:, None, 1] - B[None, :, 1])
            i, j = np.unravel_index(np.argmin(d), d.shape)
            if d[i, j] < MIN_LINK:
                continue  # touching, bar a pixel of anti-aliasing
            if d[i, j] > WRAP_LINK:
                la, lb = labels[a], labels[b]
                ia = int(np.argmin(A[:, 0])) if la[0] < W/2 else int(np.argmax(A[:, 0]))
                ib = int(np.argmin(B[:, 0])) if lb[0] < W/2 else int(np.argmax(B[:, 0]))
                pa, pb = A[ia], B[ib]
                link_lines.append((a, b, [[(rp(pa[0]), rp(pa[1])), (0 if pa[0] < W/2 else W, rp(pa[1]))],
                                          [(rp(pb[0]), rp(pb[1])), (0 if pb[0] < W/2 else W, rp(pb[1]))]]))
            else:
                link_lines.append((a, b, [[(rp(A[i,0]), rp(A[i,1])), (rp(B[j,0]), rp(B[j,1]))]]))
    print(f"{map_name}: {len(link_lines)} links", file=sys.stderr)

    regions = {}
    for region in sorted(set(region_of.values())):
        union = np.zeros((H, W), bool)
        for n, area_region in region_of.items():
            if area_region == region: union |= masks[n]
        regions[region] = trace(dilate(union, 1), min_area=20, eps=0.9, smooth=2)

    if map_name == "original":
        view_box = (0, 0, W, H)   # the world map fills the legacy board edge to edge
    else:
        ys, xs = np.nonzero(np.any([m for m in masks.values()], axis=0))
        pad = 16
        x0, y0 = max(int(xs.min()) - pad, 0), max(int(ys.min()) - pad, 0)
        x1, y1 = min(int(xs.max()) + pad, W), min(int(ys.max()) + pad, H)
        view_box = (x0, y0, x1 - x0, y1 - y0)

    return dict(render=render, paths=paths, labels=labels, elements=elements,
                links=link_lines, regions=regions, view_box=view_box)

maps = {name: build(name) for name in ("original", "elements")}

# ---------- emit ----------
def ex_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

lines = []
lines.append("defmodule GlobalCombatWeb.GameLive.MapGeometry do")
lines.append('  @moduledoc """')
lines.append("  Per-map SVG metadata for `GameLive.WorldMap` — GENERATED by `scripts/trace_maps.py`")
lines.append("  together with the `world_map/<map>_map_defs.html.heex` templates (territory")
lines.append("  outlines, links and region borders as static SVG `<defs>`). Do not edit by hand.")
lines.append("")
lines.append("  Everything is traced from the legacy ASP.NET project's `Web/wwwroot/maps/<map>/")
lines.append("  <tech>0.gif` silhouettes (the LiveView app no longer ships those sprites) placed at")
lines.append("  their `MapInfo.render_info/2` offsets, so the shapes and the legacy 800x480 board")
lines.append("  coordinates are exactly the sprite board's; only the rendering changes (vector fills")
lines.append("  styled by CSS instead of nine pre-colored GIFs per territory). Links come from")
lines.append("  `MapInfo` adjacency — any two linked areas whose silhouettes are more than a few")
lines.append("  pixels apart get a line between their closest boundary points (sea lanes on the world")
lines.append("  map, where Alaska <-> Pevek wraps off the board edges; the arrow routes on elements).")
lines.append("  Region borders are the traced union of each region's areas.")
lines.append("")
lines.append("  A label anchor is the approximate pole of inaccessibility (last pixels to survive")
lines.append("  repeated erosion), so army counts land inside the widest part of a territory —")
lines.append("  not at the bounding-box center, which for Alaska or Indonesia falls in the sea.")
lines.append("")
lines.append("  Regenerate (from `liveview/`):")
lines.append("")
lines.append("      python3 -m venv .venv && .venv/bin/pip install pillow numpy")
lines.append("      .venv/bin/python scripts/trace_maps.py . && mix format")
lines.append('  """')
lines.append("")
lines.append("  @view_boxes %{")
for name, mp in maps.items():
    x, y, w, h = mp["view_box"]
    lines.append(f"    {name}: \"{x} {y} {w} {h}\",")
lines[-1] = lines[-1].rstrip(",")
lines.append("  }")
lines.append("")
lines.append('  @doc "SVG `viewBox` for `map_name` — the world map fills the legacy 800x480 board, elements is cropped to its art."')
lines.append("  def view_box(map_name), do: Map.fetch!(@view_boxes, map_name)")
lines.append("")
lines.append("  @labels %{")
for name, mp in maps.items():
    lines.append(f"    {name}: %{{")
    for n, *_ in mp["render"]:
        lx, ly = mp["labels"][int(n)]
        lines.append(f"      {int(n)} => {{{lx}, {ly}}},")
    lines[-1] = lines[-1].rstrip(",")
    lines.append("    },")
lines[-1] = lines[-1].rstrip(",")
lines.append("  }")
lines.append("")
lines.append('  @doc "`{x, y}` army-count anchor for area `number` on `map_name`."')
lines.append("  def label(map_name, number), do: @labels |> Map.fetch!(map_name) |> Map.fetch!(number)")
lines.append("")
lines.append("  @elements %{")
for n, tech, *_ in maps["elements"]["render"]:
    el = maps["elements"]["elements"][int(n)]
    lines.append(f"    {int(n)} => {':' + el if el else 'nil'},")
lines[-1] = lines[-1].rstrip(",")
lines.append("  }")
lines.append("")
lines.append('  @doc "The element (`:fire | :water | :wind | :earth`) an elements-map area belongs to, `nil` for the bridges and for every world-map area."')
lines.append("  def element(:elements, number), do: Map.fetch!(@elements, number)")
lines.append("  def element(_map_name, _number), do: nil")
lines.append("end")
open(OUT_EX, "w").write("\n".join(lines) + "\n")

for name, mp in maps.items():
    h = []
    h.append("<%!-- GENERATED by scripts/trace_maps.py — see MapGeometry's @moduledoc. --%>")
    h.append("<defs>")
    # Paint helpers the board's CSS references by id (app.css `.world-map-*`): a faint
    # engraved hatch for the ground, the fog-of-war diagonal hatch, and (elements only)
    # one texture per element. Colours come from CSS custom properties via inline `style`
    # (SVG presentation attributes cannot read `var()`), so they follow the active theme.
    h.append('  <pattern id="gc-sea-hatch" width="4" height="4" patternUnits="userSpaceOnUse">')
    h.append('    <line x1="0" y1="2" x2="4" y2="2" stroke="currentColor" stroke-opacity="0.07" stroke-width="0.6" />')
    h.append("  </pattern>")
    h.append('  <pattern id="gc-fog" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">')
    h.append('    <rect width="6" height="6" style="fill: var(--map-fog-a)" />')
    h.append('    <line x1="0" y1="0" x2="0" y2="6" style="stroke: var(--map-fog-b)" stroke-width="3" />')
    h.append("  </pattern>")
    if name == "elements":
        h.append('  <pattern id="gc-tex-fire" width="8" height="8" patternUnits="userSpaceOnUse">')
        h.append('    <path d="M0 8 L3 2 L4 5 L6 0 L8 8" fill="none" stroke="currentColor" stroke-width="0.9" />')
        h.append("  </pattern>")
        h.append('  <pattern id="gc-tex-water" width="10" height="6" patternUnits="userSpaceOnUse">')
        h.append('    <path d="M0 3 Q2.5 0 5 3 T10 3" fill="none" stroke="currentColor" stroke-width="0.9" />')
        h.append("  </pattern>")
        h.append('  <pattern id="gc-tex-wind" width="12" height="8" patternUnits="userSpaceOnUse">')
        h.append('    <path d="M0 6 Q4 6 6 3 Q8 0 12 1" fill="none" stroke="currentColor" stroke-width="0.9" />')
        h.append("  </pattern>")
        h.append('  <pattern id="gc-tex-earth" width="6" height="6" patternUnits="userSpaceOnUse">')
        h.append('    <circle cx="1.5" cy="1.5" r="0.9" fill="currentColor" />')
        h.append('    <circle cx="4.5" cy="4.5" r="0.9" fill="currentColor" />')
        h.append("  </pattern>")
    for n, tech, *_ in mp["render"]:
        h.append(f'  <path id="gc-area-{int(n)}" data-tech-name="{tech}" d="{mp["paths"][int(n)]}" />')
    h.append('  <g id="gc-links">')
    for a, b, segs in mp["links"]:
        for (x1, y1), (x2, y2) in segs:
            h.append(f'    <line data-link="{a}-{b}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" />')
    h.append("  </g>")
    h.append('  <g id="gc-region-outlines">')
    for r, p in mp["regions"].items():
        h.append(f'    <path data-region="{r}" d="{p}" />')
    h.append("  </g>")
    h.append("</defs>")
    open(OUT_HEEX.format(map=name), "w").write("\n".join(h) + "\n")
    print(f"wrote {OUT_HEEX.format(map=name)} ({sum(len(x) for x in h)} bytes)", file=sys.stderr)
print(f"wrote {OUT_EX}", file=sys.stderr)
