"""Trace the original-map GIF silhouettes into SVG geometry (see the emitted module's @moduledoc).

Usage (from liveview/): python3 -m venv .venv && .venv/bin/pip install pillow numpy
                        .venv/bin/python scripts/trace_original_map.py . && mix format

Reads `<tech>0.gif` (black silhouette on transparency) for each of the 42 areas from the
legacy ASP.NET project's `Web/wwwroot/maps/original/` (the LiveView app no longer ships those
sprites — this script is the only consumer left),
places it on the 800x480 board at the coordinates from MapInfo, and emits:
  - one SVG path per area (all islands, holes preserved, smoothed)
  - a label point per area (approximate pole of inaccessibility)
  - sea lanes: for every adjacency whose masks do not touch, the closest boundary
    points between the two areas (with a world-wrap special case)
  - region outlines: union of each region's masks, traced
"""
import re, sys, json, math
import numpy as np
from PIL import Image

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."   # liveview dir
OUT = f"{ROOT}/lib/global_combat_web/live/game_live/original_map_geometry.ex"
OUT_HEEX = f"{ROOT}/lib/global_combat_web/live/game_live/world_map/original_map_defs.html.heex"
W, H = 800, 480

src = open(f"{ROOT}/lib/global_combat/engine/map_info.ex").read()
render = re.findall(r'\{(\d+), "(\w+)", (\d+), (\d+), (\d+), (\d+)\}', src.split('@original_render [')[1].split(']')[0])
areas_block = src.split('@original_areas [')[1].split(']\n')[0]
topo = re.findall(r'\{(\d+), "([^"]+)", (\d+), \[([\d, ]+)\]\}', areas_block)
links = {int(n): [int(x) for x in l.split(',')] for n, _, _, l in topo}
region_of = {int(n): int(r) for n, _, r, _ in topo}

def mask_for(tech, x, y, w, h):
    im = Image.open(f"{ROOT}/../Web/wwwroot/maps/original/{tech}0.gif").convert("RGBA")
    a = np.array(im)[:, :, 3] > 0
    if a.shape != (h, w):
        raise SystemExit(f"{tech}: gif {a.shape} != render {(h, w)}")
    m = np.zeros((H, W), bool)
    m[y:y+h, x:x+w] = a
    return m

# ---------- boundary tracing ----------
def loops_from_mask(m):
    """Return list of closed loops (lists of (x,y) pixel-corner points), clockwise
    for outer boundaries, counter-clockwise for holes."""
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
                pick = None
                for cand in outs:
                    d = (cand[0]-cur[0], cand[1]-cur[1])
                    if d == right:
                        pick = cand; break
                if pick is None: pick = outs[0]
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
    # anchor at index 0 and the farthest point from it
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
            continue   # drop stray specks of dithering
        pts = chaikin(loop, smooth)
        pts = rdp(pts, eps)
        p = poly_path(pts)
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

masks, paths, labels = {}, {}, {}
for n, tech, x, y, w, h in render:
    n = int(n)
    m = mask_for(tech, int(x), int(y), int(w), int(h))
    masks[n] = m
    paths[n] = trace(m)
    labels[n] = pole(m)
    print(f"{n:2d} {tech:12s} px={int(m.sum()):5d} pathlen={len(paths[n]):5d} label={labels[n]}", file=sys.stderr)

# sea lanes. Silhouettes that share a land border in the artwork can still sit a few
# pixels apart (anti-aliased coastlines), which would draw a 3-unit stub nobody can see
# under the dash pattern; anything closer than MIN_LANE is treated as touching.
MIN_LANE = 9
lanes = []
seen = set()
for a, neighbours in links.items():
    for b in neighbours:
        key = tuple(sorted((a, b)))
        if key in seen: continue
        seen.add(key)
        if (dilate(masks[a], 2) & masks[b]).any():
            continue  # land border
        A, B = boundary_pts(masks[a]), boundary_pts(masks[b])
        d = np.hypot(A[:, None, 0] - B[None, :, 0], A[:, None, 1] - B[None, :, 1])
        i, j = np.unravel_index(np.argmin(d), d.shape)
        if d[i, j] < MIN_LANE:
            continue  # coastlines touch, bar a pixel of anti-aliasing
        if d[i, j] > 300:  # world wrap (Alaska <-> Pevek)
            la, lb = labels[a], labels[b]
            # each half runs from its own area's nearest edge point out to the board edge
            ia = int(np.argmin(A[:, 0])) if la[0] < W/2 else int(np.argmax(A[:, 0]))
            ib = int(np.argmin(B[:, 0])) if lb[0] < W/2 else int(np.argmax(B[:, 0]))
            pa, pb = A[ia], B[ib]
            lanes.append({"from": a, "to": b, "wrap": True,
                          "segments": [[[round(float(pa[0]),1), round(float(pa[1]),1)], [0 if pa[0] < W/2 else W, round(float(pa[1]),1)]],
                                       [[round(float(pb[0]),1), round(float(pb[1]),1)], [0 if pb[0] < W/2 else W, round(float(pb[1]),1)]]]})
        else:
            lanes.append({"from": a, "to": b, "wrap": False,
                          "segments": [[[round(float(A[i,0]),1), round(float(A[i,1]),1)], [round(float(B[j,0]),1), round(float(B[j,1]),1)]]]})
print(f"sea lanes: {len(lanes)}", file=sys.stderr)

regions = {}
for region in sorted(set(region_of.values())):
    union = np.zeros((H, W), bool)
    for n, area_region in region_of.items():
        if area_region == region: union |= masks[n]
    regions[region] = trace(dilate(union, 1), min_area=20, eps=0.9, smooth=2)


# ---------- emit the Elixir label module + the static HEEx <defs> ----------
def ex_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

lines = []
lines.append("defmodule GlobalCombatWeb.GameLive.OriginalMapGeometry do")
lines.append('  @moduledoc """')
lines.append("  Per-area label anchors for the `:original` world map's SVG board — GENERATED by")
lines.append("  `scripts/trace_original_map.py` together with its sibling")
lines.append("  `world_map/original_map_defs.html.heex` (the territory outlines, sea lanes and")
lines.append("  region borders as static SVG `<defs>`). Do not edit either by hand.")
lines.append("")
lines.append("  Everything is traced from the legacy ASP.NET project's `Web/wwwroot/maps/original/")
lines.append("  <tech>0.gif` silhouettes (the LiveView app no longer ships those sprites) placed at")
lines.append("  their `MapInfo.render_info/2` offsets, so the shapes and the")
lines.append("  800x480 coordinate space are exactly the sprite board's; only the rendering changes")
lines.append("  (vector fills styled by CSS instead of nine pre-colored GIFs per territory). Sea")
lines.append("  lanes come from `MapInfo` adjacency — any two linked areas whose silhouettes are")
lines.append("  more than a few pixels apart get a lane between their closest coast points (Alaska")
lines.append("  <-> Pevek wraps off the board edges). Region borders are the traced union of each")
lines.append("  region's areas.")
lines.append("")
lines.append("  A label anchor is the approximate pole of inaccessibility (last pixels to survive")
lines.append("  repeated erosion), so army counts land inside the widest part of a territory —")
lines.append("  not at the bounding-box center, which for Alaska or Indonesia falls in the sea.")
lines.append("")
lines.append("  Regenerate (from `liveview/`):")
lines.append("")
lines.append("      python3 -m venv .venv && .venv/bin/pip install pillow numpy")
lines.append("      .venv/bin/python scripts/trace_original_map.py . && mix format")
lines.append('  """')
lines.append("")
lines.append(f"  @view_box \"0 0 {W} {H}\"")
lines.append("")
lines.append('  @doc "SVG `viewBox` the defs template and the anchors below are expressed in."')
lines.append("  def view_box, do: @view_box")
lines.append("")
lines.append("  @labels %{")
for n, tech, *_ in render:
    lx, ly = labels[int(n)]
    lines.append(f"    {int(n)} => {{{lx}, {ly}}},")
lines[-1] = lines[-1].rstrip(",")
lines.append("  }")
lines.append("")
lines.append('  @doc "`{x, y}` army-count anchor for area `number`."')
lines.append("  def label(number), do: Map.fetch!(@labels, number)")
lines.append("end")
open(OUT, "w").write("\n".join(lines) + "\n")

h = []
h.append("<%!-- GENERATED by scripts/trace_original_map.py — see OriginalMapGeometry's @moduledoc. --%>")
h.append("<defs>")
# Paint helpers the board's CSS references by id (app.css `.world-map-*`): a faint
# engraved-sea hatch and the fog-of-war diagonal hatch. Colours come from CSS
# custom properties via inline `style` (SVG presentation attributes cannot read
# `var()`), so they still follow the active theme.
h.append('  <pattern id="gc-sea-hatch" width="4" height="4" patternUnits="userSpaceOnUse">')
h.append('    <line x1="0" y1="2" x2="4" y2="2" stroke="currentColor" stroke-opacity="0.07" stroke-width="0.6" />')
h.append("  </pattern>")
h.append('  <pattern id="gc-fog" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">')
h.append('    <rect width="6" height="6" style="fill: var(--map-fog-a)" />')
h.append('    <line x1="0" y1="0" x2="0" y2="6" style="stroke: var(--map-fog-b)" stroke-width="3" />')
h.append("  </pattern>")
for n, tech, *_ in render:
    h.append(f'  <path id="gc-area-{int(n)}" data-tech-name="{tech}" d="{paths[int(n)]}" />')
h.append('  <g id="gc-sea-lanes">')
for lane in lanes:
    for (x1, y1), (x2, y2) in lane["segments"]:
        h.append(f'    <line data-lane="{lane["from"]}-{lane["to"]}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" />')
h.append("  </g>")
h.append('  <g id="gc-region-outlines">')
for r, p in regions.items():
    h.append(f'    <path data-region="{r}" d="{p}" />')
h.append("  </g>")
h.append("</defs>")
open(OUT_HEEX, "w").write("\n".join(h) + "\n")
print(f"wrote {OUT} and {OUT_HEEX} ({sum(len(x) for x in h)} bytes of defs)", file=sys.stderr)
