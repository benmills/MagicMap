#!/usr/bin/env python3
"""A web demo of the Atlas library on its own: Atlas runs in Lua (lupa) over
its bundled data; this serves its answers as JSON, and index.html only draws
them. One map: Kalimdor, the Eastern Kingdoms and Zephras Isle placed on a world
(OFFSET); requests and replies speak its tile coordinates. See README.md.

  .venv/bin/python demo/server.py [port]      # then open http://localhost:8000

  /api/maps                          the world: its bounds, zones, and parts (each map's inst, offset, bounds)
  /api/tiles                         per tile: its world key, its map's inst and key (src), whether it's open sea
  /api/labels                        Atlas.Labels: ranked name anchors (continent, zone, town, subzone, poi)
  /api/at?col=&row=                  TileToWorld, ZoneAt, Walk.Cell at that chunk
  /api/fit?uiMapID=&w=&h=            MapRect and Camera.Fit (or c0=&r0=&c1=&r1=: a box)
  /api/walk?c0=&r0=&c1=&r1=&v=       the walk over a chunk range: 3.1's cells (one hex digit each) and regions; v2's
                                     chunks, parts and edges (walk())
  /api/route?c0=&r0=&c1=&r1=&v=      Atlas.Route.Find from (c0, r0) to (c1, r1), with its trace (nodes closed, its path,
                                     its turns) as world points, one shape for both walks (route())
                                     v=311: 3.1.1's walk (demo/walk311/); v=31: main's before v2 (demo/walk31/);
                                     v=2 (the default): the tree's
  /api/cases?sides=311,2             the Routes page: walk_cases.json's grid cases, each run live on each side
  /api/pins?c0=&r0=&c1=&r1=&zoom=&layers=
                                     FlightPoints, POIs, Dungeons, SpawnsIn (by NPC flags, quests,
                                     rank, object kind) in a box; groups=1 returns compact groups and omitted count
  /api/npc|object|item|quest|flight|dungeon?id=
                                     one entity, its links named (QuestSources for a quest)
  /api/find?q=                       Atlas.Find over npc, quest, object, item
"""
from __future__ import annotations

import gzip
import io
import json
import math
import os
import sys
import threading
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

DEMO = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(DEMO), "tools"))

from atlas_lua import ROOT, files, load_atlas  # noqa: E402
from lupa import lua51  # noqa: E402
from lupa.lua51 import LuaError  # noqa: E402
from asset_manifest import inventory  # noqa: E402
from static_assets import COMPRESSIBLE, accepts_gzip, compressed_file  # noqa: E402

# The walks the pathing debug and the Routes page compare: "2" is the tree's own walk (atlas/Walk.lua, atlas/Route.lua
# over Data/Walk*.lua: v2); "31" is main's before v2, frozen in demo/walk31/ (those four files as at 5eedf63); "311" is
# the released 3.1.1's (tag v3.1.1, 13f5be7), frozen in demo/walk311/: its Walk.lua and Data/Walk.lua (no regions, no
# links) and its search as f95cb2f moved it, unchanged, from model/Route.lua into atlas/Route.lua.
WALK31 = os.path.join(DEMO, "walk31")
WALK31_FILES = ("Data/Walk.lua", "Data/WalkRegions.lua", "atlas/Walk.lua", "atlas/Route.lua")
WALK311 = os.path.join(DEMO, "walk311")
WALK311_FILES = ("Data/Walk.lua", "atlas/Walk.lua", "atlas/Route.lua")
SIDE_NAMES = {"311": "3.1.1", "31": "main", "2": "v2"}


def load_frozen(L, folder, rels):
    """A frozen walk in its own ns of the same Lua runtime: its data files, then Walk and Route (Route reads only
    Atlas.Walk, Walk only ns.Data). Its Atlas has nothing else."""
    load = L.eval("function(src, name) local f, err = loadstring(src, name) if not f then error(err) end return f end")
    ns = L.table()
    for rel in rels:
        with open(os.path.join(folder, rel), "rb") as f:
            load(f.read(), "@demo/%s/%s" % (os.path.basename(folder), rel))("MagicMap", ns)
    return ns.Atlas


def load_tree_with_walk31():
    """The tree's Atlas with 3.1's walk in place of its own (and none of its other Data/Walk* files): for when the
    tree's own walk doesn't load (mid-rewrite)."""
    L = lua51.LuaRuntime(unpack_returned_tuples=True)
    load = L.eval("function(src, name) local f, err = loadstring(src, name) if not f then error(err) end return f end")
    ns = L.table()
    for rel in files():
        path = os.path.join(WALK31, rel) if rel in WALK31_FILES else os.path.join(ROOT, rel)
        if rel.startswith("Data/Walk") and rel not in WALK31_FILES or rel.startswith("Data/") and not os.path.exists(path):
            continue
        with open(path, "rb") as f:
            load(f.read(), "@" + rel)("MagicMap", ns)
    return L, ns.Atlas


try:
    L, Atlas = load_atlas()
    TREE_WALK_ERROR = None
except LuaError as e:  # the tree's walk mid-rewrite: everything else from the tree, the walk 3.1's
    TREE_WALK_ERROR = str(e).splitlines()[0]
    print("The tree's Atlas didn't load (%s): serving it with 3.1's walk" % TREE_WALK_ERROR, file=sys.stderr)
    L, Atlas = load_tree_with_walk31()
lua_type = L.globals().type
Atlas31 = load_frozen(L, WALK31, WALK31_FILES)
Atlas311 = load_frozen(L, WALK311, WALK311_FILES)
# v2's API (spec: Walk.Snap -> node id, Walk.Pos, Walk.Edges): without it (the tree's walk not v2's, or not loading),
# "2" runs the tree's walk through 3.1's API, or main's.
WALK2_API = TREE_WALK_ERROR is None and Atlas.Walk is not None and Atlas.Walk.Pos is not None
SIDES = {"311": Atlas311, "31": Atlas31, "2": Atlas if TREE_WALK_ERROR is None else Atlas31}


def py(v):
    """A Lua value as JSON-ready Python: tables with keys 1..n become lists."""
    if lua_type(v) != "table":
        return v
    d = dict(v.items())
    if not d:
        return []
    if all(isinstance(k, int) for k in d) and sorted(d) == list(range(1, len(d) + 1)):
        return [py(d[i]) for i in range(1, len(d) + 1)]
    return {str(k): py(x) for k, x in d.items()}


WORLD, WORLD_NAME = 1, "Azeroth"
# Each map's place on the world, in tiles (world = map + offset). The Eastern Kingdoms' is from Blizzard's own world map
# (UiMap 947, Azeroth: UiMapAssignment places both continents on it at one scale): (+44.9..45.0, -9.3..-9.1) from
# Kalimdor across the Eastern Kingdoms, rounded. Zephras Isle has no place there: where Forever's own world map draws it,
# between them just north of the Maelstrom (fitted to six zones' places on that map: within ~10 px of 1836 but one).
# Rows stay in 0..63, so a world tile's key still reads col * 64 + row. The page reads these from /api/maps.
OFFSET = {1: (0, 0), 0: (45, -9), 2991: (29, -6)}
BOUNDS = {i: tuple(v + OFFSET[i][k % 2] for k, v in enumerate(Atlas.TileBounds(i))) for i in OFFSET}  # world, c0 r0 c1 r1
CITIES = {"Stormwind City": "Stormwind", "Stormwind": "Stormwind", "Ironforge": "Ironforge", "The Undercity": "Undercity",
          "Orgrimmar": "Orgrimmar", "Thunder Bluff": "Thunder Bluff", "Darnassus": "Darnassus"}
CITIES_AS_TOWNS = {"Ironforge", "The Undercity"}
CITY_SIZE = 1.5  # (a zone label's: the side of the area, in tiles)
assert all(0 <= b[1] and b[3] <= 64 for b in BOUNDS.values())


def to_world(inst, col, row):
    dx, dy = OFFSET[inst]
    return col + dx, row + dy


def to_real(col, row):
    """The real map under a world position, and the position on it: the isle's box, else the nearer continent's."""
    c0, r0, c1, r1 = BOUNDS[2991]
    if c0 <= col < c1 and r0 <= row < r1:
        inst = 2991
    else:
        inst = 1 if col < (BOUNDS[1][2] + BOUNDS[0][0]) / 2 else 0
    dx, dy = OFFSET[inst]
    return inst, col - dx, row - dy


def world_key(inst, key):
    dx, dy = OFFSET[inst]
    return (key // 64 + dx) * 64 + key % 64 + dy


def on_world(p):
    """A thing with an inst, col and row, moved onto the world if its map is on it."""
    if p.get("inst") in OFFSET:
        if "col" in p:
            p["col"], p["row"] = to_world(p["inst"], p["col"], p["row"])
        p["inst"] = WORLD
    return p


def real_maps():
    return [dict(m, uiMapID=Atlas.Continent(m["inst"]), zones=py(Atlas.Zones(m["inst"])) or []) for m in py(Atlas.Maps())]


def real_at(inst, col, row):
    north, west = Atlas.TileToWorld(col, row)
    n = Atlas31.Walk.CHUNKS
    gc, gr = int(col * n // 1), int(row * n // 1)
    cls, east, south = Atlas31.Walk.Cell(inst, gc, gr)  # (3.1's grid: the chunk's class and crossings)
    z = Atlas.ZoneAt(inst, col, row)
    out = {"north": north, "west": west, "zone": py(z), "chunk": [gc, gr],
           "walk": {"class": cls, "east": east, "south": south}}
    if WALK2_API:  # v2's: the chunk's class and part count, and the part a point here snaps to
        try:
            W = Atlas.Walk
            cls2, parts = W.Cell(inst, gc, gr)
            node = W.Snap(inst, col, row)
            out["walk2"] = {"class": cls2, "parts": parts, "node": node,
                            "region": W.Region(inst, node) if node is not None else None}
        except LuaError as e:
            out["walk2"] = {"error": str(e).splitlines()[0]}
    id = Atlas.AreaAt(inst, col, row)
    if id:
        a = Atlas.Area(id)
        zone = Atlas.Area(a.zone)
        out["area"] = {"zone": zone.name, "subzone": a.parent and a.name,
                       "levels": list(Atlas.ZoneLevels(a.zone) or ()), "faction": a.faction or zone.faction}
    return out


def fit(q):
    w, h = float(q["w"]), float(q["h"])
    if "uiMapID" in q:
        r = Atlas.MapRect(int(q["uiMapID"]))
        if r.inst not in OFFSET:
            raise ValueError("not on the world")
        cx, cy, zoom = Atlas.Camera.Fit(r.col0, r.row0, r.col1, r.row1, w, h, None, 16, 2048)
        cx, cy = to_world(r.inst, cx, cy)
        return {"cam": {"cx": cx, "cy": cy, "zoom": zoom}}
    # a box of spawns: at least 0.6 tiles (~320 yards) across, so one spawn isn't zoomed in on all the way
    c0, r0, c1, r1 = (float(q[k]) for k in ("c0", "r0", "c1", "r1"))
    cx, cy, zoom = Atlas.Camera.Fit(c0, r0, c1, r1, w, h, 0.8, 16, 1024, 0.6)
    return {"cam": {"cx": cx, "cy": cy, "zoom": zoom}}


def side(q):
    """Which walk a request asks for: v=311 (3.1.1's, demo/walk311), 31 (main's before v2, demo/walk31) or 2 (the
    tree's, the default)."""
    v = q.get("v", "2")
    if v not in SIDES:
        raise ValueError("v is 311, 31 or 2")
    return v, SIDES[v], v == "2" and WALK2_API


def rnd(x, y):
    return [round(x, 5), round(y, 5)]


def link_rows(W, inst):
    """A map's hand links as Data has them, either format: 3.1's { ac, ar, bc, br, cost, name } or v2's
    { ac, ar, ap, bc, br, bp, cost, name, oneway }. -> [(ac, ar, ap, bc, br, bp, cost, name, oneway)], chunks real."""
    if W.Links is None:  # (3.1.1: none)
        return []
    got = W.Links(inst)
    data = got[1] if isinstance(got, tuple) else got
    out = []
    for i in range(1, len(data) + 1 if data else 1):
        k = data[i]
        if isinstance(k[6], str):
            out.append((k[1], k[2], None, k[3], k[4], None, k[5], k[6], False))
        else:
            out.append((k[1], k[2], k[3], k[4], k[5], k[6], k[7], k[8], bool(k[9])))
    return out


def walk(q):
    """The walk over a world chunk range, on the side v asks for (31 or 2, the default).
    3.1's API: each chunk's value (class + 4 east + 8 south) as a hex digit, its region (1 the map's biggest, 0 nowhere
    to stand), and the map's links that meet the range. v2's (the tree's atlas has Walk.Pos): each chunk's class (its
    biggest part's) and part count as digits, its parts (nodes: [id, col, row, class, region, p, gc, gr], position on
    the world) and their edges ([col0, row0, col1, row1, cost, oneway], from Walk.Edges; past 12,000 chunks none)."""
    c0, r0, c1, r1 = (int(q[k]) for k in ("c0", "r0", "c1", "r1"))
    if c1 < c0 or r1 < r0 or (c1-c0)*(r1-r0) > 40000:
        raise ValueError("walk grid is limited to 40000 cells")
    v, A, v2 = side(q)
    try:
        return walk_side(v, A, v2, c0, r0, c1, r1)
    except LuaError as e:  # (the tree's walk mid-rewrite: say so, the page shows it)
        return {"v": v, "error": "The %s walk failed: %s" % (SIDE_NAMES[v], str(e).splitlines()[0])}


def walk_side(v, A, v2, c0, r0, c1, r1):
    W, n = A.Walk, A.Walk.CHUNKS
    out = {"v": v, "api": "2" if v2 else "3.1", "c0": c0, "r0": r0}
    if v2:
        out.update(walk_v2(W, c0, r0, c1, r1))
    else:
        rows, regions = [], []
        for gr in range(r0, r1):
            s, reg = [], []
            for gc in range(c0, c1):
                inst, _, _ = to_real(gc / n, gr / n)
                dx, dy = OFFSET[inst]
                cls, east, south = W.Cell(inst, gc - dx * n, gr - dy * n)
                s.append("%x" % (cls + 4 * east + 8 * south))
                reg.append((W.Region(inst, gc - dx * n, gr - dy * n) if W.Region else 1) or 0)  # (3.1.1: no regions)
            rows.append("".join(s))
            regions.append(reg)
        out.update(rows=rows, regions=regions)
    links = []
    for inst in OFFSET:
        dx, dy = OFFSET[inst]
        for ac, ar, ap, bc, br, bp, cost, name, oneway in link_rows(W, inst):
            ac, ar, bc, br = ac + dx * n, ar + dy * n, bc + dx * n, br + dy * n
            if max(ac, bc) >= c0 - 1 and min(ac, bc) <= c1 and max(ar, br) >= r0 - 1 and min(ar, br) <= r1:
                links.append({"a": [ac, ar], "b": [bc, br], "cost": cost, "name": name, "oneway": oneway,
                              "ap": ap, "bp": bp})
    out["links"] = links
    return out


GRAPH_CELLS = 12000  # chunks: v2's parts graph only this close in (a wide view's would be megabytes of JSON)


def walk_v2(W, c0, r0, c1, r1):
    n, PART = W.CHUNKS, 8192  # node id = gc * 8192 + gr * 8 + p
    graph = (c1 - c0) * (r1 - r0) <= GRAPH_CELLS
    rows, parts, nodes, edges = [], [], [], []
    fwd, back = L.table(), L.table()

    def inside(id, dx, dy):
        return c0 <= id // PART + dx * n < c1 and r0 <= id % PART // 8 + dy * n < r1
    for gr in range(r0, r1):
        s, ps = [], []
        for gc in range(c0, c1):
            inst, _, _ = to_real(gc / n, gr / n)
            dx, dy = OFFSET[inst]
            rc, rr = gc - dx * n, gr - dy * n
            cls, count = W.Cell(inst, rc, rr)
            s.append("%x" % (cls or 0))
            ps.append("%x" % (count or 0))
            if not graph:
                continue
            for p in range(count or 0):
                id = rc * PART + rr * 8 + p
                col, row = W.Pos(inst, id)
                if col is None:
                    continue
                x, y = rnd(col + dx, row + dy)
                nodes.append([id, x, y, W.Class(inst, id) if W.Class else cls, W.Region(inst, id) or 0, p, gc, gr])
                k, m = W.Edges(inst, id, fwd) or 0, W.Edges(inst, id, back, True) or 0
                outs = {fwd[2 * j - 1]: fwd[2 * j] for j in range(1, k + 1)}
                ins = {back[2 * j - 1]: back[2 * j] for j in range(1, m + 1)}
                for u, cost in outs.items():
                    two = u in ins
                    if two and u < id and inside(u, dx, dy):
                        continue  # (a two-way edge inside the range: drawn once, from its smaller end)
                    uc, ur = W.Pos(inst, u)
                    edges.append([x, y, *rnd(uc + dx, ur + dy), round(cost, 3), 0 if two else 1])
                for u, cost in ins.items():  # one way in from outside the range: drawn here, not there
                    if u not in outs and not inside(u, dx, dy):
                        uc, ur = W.Pos(inst, u)
                        edges.append([*rnd(uc + dx, ur + dy), x, y, round(cost, 3), 1])
        rows.append("".join(s))
        parts.append("".join(ps))
    return {"rows": rows, "parts": parts, "graph": graph, "nodes": nodes, "edges": edges,
            "nodeFields": ["id", "col", "row", "class", "region", "p", "gc", "gr"],
            "edgeFields": ["col0", "row0", "col1", "row1", "cost", "oneway"]}


def route(q):
    """The addon's own route search (atlas/Route.lua, as model/Route.lua runs it, whole) between two world points, on
    the side v asks for (31: 3.1's, demo/walk31; 2: the tree's, the default), with a trace, in one shape for both:
    the way and its numbers; the nodes closed, the node path and its turns as world points (3.1's chunks at their
    centres, v2's parts at Walk.Pos)."""
    v, A, v2 = side(q)
    a, b = to_real(float(q["c0"]), float(q["r0"])), to_real(float(q["c1"]), float(q["r1"]))
    if a[0] != b[0]:
        return {"v": v, "error": "Both ends must be on the same map: a route never leaves one."}
    try:
        return (route_v2 if v2 else route_31)(v, A, a[0], a, b)
    except LuaError as e:
        return {"v": v, "error": "The %s search failed: %s" % (SIDE_NAMES[v], str(e).splitlines()[0])}


def route_common(v, api, A, inst, a, b, pts, partial, capped, ms, trace):
    way = [rnd(*to_world(inst, p.col, p.row)) for p in (pts[i] for i in range(1, len(pts) + 1))] if pts else []
    yards = sum(math.hypot(x1 - x0, y1 - y0) for (x0, y0), (x1, y1) in zip(way, way[1:])) * Atlas.TILE_YARDS
    straight = math.hypot(b[1] - a[1], b[2] - a[2]) * Atlas.TILE_YARDS
    nodes = trace.nodes
    return {"v": v, "label": SIDE_NAMES[v], "api": api, "map": MAP_NAMES.get(inst), "way": way, "found": pts is not None,
            "partial": bool(partial), "capped": bool(capped),
            "nodes": (len(nodes) if lua_type(nodes) == "table" else nodes) or 0,
            "maxNodes": A.Route.MAX_NODES, "ms": round(ms, 1), "yards": yards, "straight": straight,
            "ratio": round(yards / straight, 4) if pts is not None and straight > 0 else None,
            "regions": list(trace.regions.values()) if trace.regions else None}


def route_31(v, A, inst, a, b):
    """3.1's API: Walk.Snap(inst, gc, gr) -> gc, gr; Route.Find(inst, c1, r1, sc, sr, gc, gr, c2, r2, yield, trace)."""
    W, n, span = A.Walk, A.Walk.CHUNKS, A.Route.SPAN
    dx, dy = OFFSET[inst]
    sc, sr = W.Snap(inst, math.floor(a[1] * n), math.floor(a[2] * n))
    gc, gr = W.Snap(inst, math.floor(b[1] * n), math.floor(b[2] * n))
    if sc is None or gc is None:
        return {"v": v, "error": "Nowhere to stand within 4 chunks of %s: the addon would draw a straight line."
                % ("the start" if sc is None else "the end")}
    trace = L.table()
    t = time.perf_counter()
    pts, partial, capped = A.Route.Find(inst, a[1], a[2], sc, sr, gc, gr, b[1], b[2], None, trace)
    ms = (time.perf_counter() - t) * 1000

    def centre(c, r):
        return rnd((c + 0.5) / n + dx, (r + 0.5) / n + dy)

    def points(ids):
        return [centre(ids[i] // span, ids[i] % span) for i in range(1, len(ids) + 1)] if ids else []
    box = trace.box or {1: sc, 2: sr, 3: gc, 4: gr}  # (no search: different regions and nowhere near in yours)
    out = route_common(v, "3.1", A, inst, a, b, pts, partial, capped, ms, trace)
    out.update(snapped=[centre(sc, sr), centre(gc, gr)],
               box=[box[1] / n + dx, box[2] / n + dy, (box[3] + 1) / n + dx, (box[4] + 1) / n + dy],
               closed=points(trace.closed), raw=points(trace.raw), turns=points(trace.turns),
               instead=centre(trace.goal[1], trace.goal[2]) if trace.goal else None,
               abstract=None, nodes2=None, closed2=None)
    return out


def route_v2(v, A, inst, a, b):
    """v2's API (docs/walk.md): Walk.Snap(inst, col, row) -> node id; Route.Find(inst, c1, r1, s, g,
    c2, r2, yield, trace); Walk.Pos(inst, id) -> col, row."""
    W, n = A.Walk, A.Walk.CHUNKS
    dx, dy = OFFSET[inst]
    s, g = W.Snap(inst, a[1], a[2]), W.Snap(inst, b[1], b[2])
    if s is None or g is None:
        return {"v": v, "error": "Nowhere to stand within 4 chunks of %s: the addon would draw a straight line."
                % ("the start" if s is None else "the end")}
    trace = L.table()
    t = time.perf_counter()
    pts, partial, capped = A.Route.Find(inst, a[1], a[2], s, g, b[1], b[2], None, trace)
    ms = (time.perf_counter() - t) * 1000

    def pos(id):
        col, row = W.Pos(inst, id)
        return rnd(col + dx, row + dy)

    def points(ids):
        return [pos(ids[i]) for i in range(1, len(ids) + 1)] if lua_type(ids) == "table" else []
    box = None
    if lua_type(trace.box) == "table" and trace.box[4] is not None:  # (chunks, as 3.1's)
        bx = trace.box
        box = [bx[1] / n + dx, bx[2] / n + dy, (bx[3] + 1) / n + dx, (bx[4] + 1) / n + dy]
    goal, nodes2 = trace.goal, trace.nodes2
    out = route_common(v, "2", A, inst, a, b, pts, partial, capped, ms, trace)
    out.update(snapped=[pos(s), pos(g)], box=box,
               closed=points(trace.closed), raw=points(trace.raw), turns=points(trace.turns),
               instead=pos(goal) if isinstance(goal, (int, float)) else None,
               abstract=points(trace.abstract) if trace.abstract else None,
               nodes2=(len(nodes2) if lua_type(nodes2) == "table" else nodes2),
               closed2=points(trace.closed2) if lua_type(trace.closed2) == "table" else None)
    return out


CASES = os.path.join(DEMO, "walk_cases.json")
CASE_KEYS = ("v", "label", "error", "found", "partial", "capped", "yards", "straight", "ratio", "nodes", "nodes2", "ms",
             "way", "snapped", "regions", "instead")


def cases(q):
    """The Routes page (routes.html): walk_cases.json's cases marked "grid", each run now on each side asked for
    (sides=311,2 by default: the released 3.1.1 and v2), and back the other way where "back" says so. Ends on the
    world (moved by the map's offset unless the file's "space" is "world"); per run the route's numbers and its line."""
    sides = q.get("sides", "311,2").split(",")
    if not sides or any(v not in SIDES for v in sides):
        raise ValueError("unknown side")
    with open(CASES, encoding="utf-8") as f:
        doc = json.load(f)
    out = []
    for c in doc.get("cases", []):
        if not c.get("grid") and q.get("all") != "1":
            continue
        dx, dy = (0, 0) if doc.get("space") == "world" else OFFSET[c["inst"]]
        a, b = [c["a"][0] + dx, c["a"][1] + dy], [c["b"][0] + dx, c["b"][1] + dy]
        runs = []
        for way, (p, t) in [("ab", (a, b))] + ([("ba", (b, a))] if c.get("back") else []):
            for v in sides:
                r = route({"v": v, "c0": str(p[0]), "r0": str(p[1]), "c1": str(t[0]), "r1": str(t[1])})
                runs.append(dict({k: r.get(k) for k in CASE_KEYS}, dir=way))
        out.append({k: c.get(k) for k in ("name", "zone", "note", "should", "inst", "back")} | {"a": a, "b": b, "runs": runs})
    return {"sides": [{"v": v, "label": SIDE_NAMES[v]} for v in sides], "cases": out}


MAP_NAMES = {m["inst"]: m["name"] for m in py(Atlas.Maps())}
GET = {"npc": Atlas.Npc, "object": Atlas.Object, "item": Atlas.Item, "quest": Atlas.Quest}

# Which spawns each pin layer shows (Lua, so SpawnsIn's filter stays in Lua).
FILTERS = L.eval("""function(Atlas)
  local function Has(flags, bit) return math.floor(flags / bit) % 2 == 1 end
  local SERVICE = { 128, 256, 4096, 8192, 2048, 16, 16384 } -- model/Services.lua; flights have their own layer
  return {
    service = function(id)
      local f = Atlas.Npc(id).flags
      for _, b in ipairs(SERVICE) do if Has(f, b) then return true end end
      return false
    end,
    questNpc = function(id) return #Atlas.Npc(id).questStarts > 0 end,
    questObject = function(id) return #Atlas.Object(id).questStarts > 0 end,
    rare = function(id) local r = Atlas.Npc(id).rank return r == 2 or r == 4 end,
    mail = function(id) return Atlas.Object(id).kind == "mailbox" end,
    herb = function(id) return Atlas.Object(id).kind == "herb" end,
    ore = function(id) return Atlas.Object(id).kind == "ore" end,
  }
end""")(Atlas)
SERVICES = ["innkeeper", "banker", "auctioneer", "stablemaster", "battlemaster", "trainer", "repair"]
SPAWN_LAYERS = {"service": [("npc", "service")], "quest": [("npc", "questNpc"), ("object", "questObject")],
                "rare": [("npc", "rare")], "mail": [("object", "mail")], "herb": [("object", "herb")],
                "ore": [("object", "ore")]}
PIN_CAP = 1200  # members per layer; explicit omitted count for the grouped browser response
GROUP_RANGE, GROUP_REACH = 24, 3  # ui/Cluster.lua; grouping runs only on settled requests


def group_pins(found, zoom):
    """Greedy neighbouring pins, bounded to three ranges from a stable seed.

    Tile buckets avoid an all-pairs pass. Removing a claimed member from its
    bucket also keeps a dense stack of identical positions cheap to collect.
    Returned membership remains unchanged while the browser pans or animates.
    """
    cell = GROUP_RANGE / zoom
    buckets = {}
    found = sorted(found, key=lambda p: p["key"])
    for i, p in enumerate(found):
        key = (math.floor(p["col"] / cell), math.floor(p["row"] / cell))
        buckets.setdefault(key, {})[i] = p
    taken, out = set(), []
    for i, seed in enumerate(found):
        if i in taken:
            continue
        taken.add(i)
        key = (math.floor(seed["col"] / cell), math.floor(seed["row"] / cell))
        buckets[key].pop(i)
        members = [seed]
        for p in members:
            cx, cy = math.floor(p["col"] / cell), math.floor(p["row"] / cell)
            for dc in (-1, 0, 1):
                for dr in (-1, 0, 1):
                    bucket = buckets.get((cx + dc, cy + dr), {})
                    for j, q in list(bucket.items()):
                        if ((q["col"] - p["col"]) ** 2 + (q["row"] - p["row"]) ** 2 < cell ** 2
                            and (q["col"] - seed["col"]) ** 2 + (q["row"] - seed["row"]) ** 2 < (cell * GROUP_REACH) ** 2):
                            taken.add(j)
                            del bucket[j]
                            members.append(q)
        if len(members) == 1:
            out.append(seed)
        else:
            out.append({"kind": "group", "key": seed["key"], "layer": seed["layer"],
                        "col": sum(p["col"] for p in members) / len(members),
                        "row": sum(p["row"] for p in members) / len(members),
                        "count": len(members), "members": members})
    return out


def real_pins(q):
    inst, zoom = int(q["inst"]), float(q["zoom"])
    c0, r0, c1, r1 = (float(q[k]) for k in ("c0", "r0", "c1", "r1"))
    if (not all(math.isfinite(v) for v in (zoom, c0, r0, c1, r1))
        or not 0 < zoom <= 4096 or c1 < c0 or r1 < r0):
        raise ValueError("invalid pin viewport")
    layers = list(dict.fromkeys(q["layers"].split(",")))
    if any(layer not in SPAWN_LAYERS and layer not in ("flight", "poi", "dungeon") for layer in layers):
        raise ValueError("unknown pin layer")
    # Atlas tile keys have 64 rows. A far-away/tilted viewport must never turn
    # SpawnsIn's tile loop into an unbounded scan, including direct API calls.
    c0, r0, c1, r1 = max(0, c0), max(0, r0), min(64, c1), min(64, r1)
    out, omitted = [], 0
    if c1 < c0 or r1 < r0:
        return out, omitted
    inside = lambda p: c0 <= p["col"] <= c1 and r0 <= p["row"] <= r1  # noqa: E731
    for layer in layers:
        found = []
        if layer == "flight":
            found = [dict(p, kind="flight") for p in py(Atlas.FlightPoints(inst)) if inside(p)]
        elif layer == "poi":
            found = [dict(p, kind="poi") for p in py(Atlas.POIs(inst)) if inside(p)]
        elif layer == "dungeon":
            found = [{"kind": "dungeon", "id": d["id"], "name": d["name"], "col": d["col"], "row": d["row"],
                      "mark": d["kind"]} for d in py(Atlas.Dungeons(inst)) if inside(d)]
        else:
            for kind, f in SPAWN_LAYERS[layer]:
                for s in Atlas.SpawnsIn(kind, inst, c0, r0, c1, r1, FILTERS[f]).values():
                    found.append({"kind": kind, "id": s.id, "col": s.col, "row": s.row})
        if layer == "service":
            for p in found:
                services = py(Atlas.Npc(p["id"]).services)
                p["mark"] = next(s for s in SERVICES if s in services)
        found.sort(key=lambda p: (p["kind"], p["id"], p["col"], p["row"]))
        seen = set()
        for p in found:
            key = f'{layer}:{p["kind"]}:{p["id"]}:{p["col"]}:{p["row"]}'
            if key in seen:
                continue
            seen.add(key)
            if len(seen) > PIN_CAP:
                omitted += 1
                continue
            pin = {"layer": layer, "kind": p["kind"], "id": p["id"], "col": p["col"], "row": p["row"],
                   "mark": p.get("mark"), "key": key}
            if p["kind"] == "npc":  # its faction's glow, a rare's rank
                e = Atlas.Npc(p["id"])
                pin["name"] = e.name
                pin["faction"] = e.faction
                if layer == "rare":
                    pin["mark"] = e.rank
            elif p["kind"] == "object":
                pin["name"] = Atlas.Object(p["id"]).name
            else:  # a POI's card is drawn from its pin
                pin.update(name=p["name"], faction=p.get("faction"), description=p.get("description"), icon=p.get("icon"))
            out.append(pin)
    return out, omitted


def ref(kind, id):
    e = GET[kind](id)
    r = {"kind": kind, "id": id, "name": e.name if e else f"#{id}"}
    if kind == "quest" and e:
        r["level"] = e.level
    return r


def refs(kind, ids):
    return [ref(kind, i) for i in ids.values()]


def where(e):
    """Spawns per inst as [col, row] pairs, and the dungeons it's inside."""
    spawns, world_points = [], []
    for inst, pts in sorted(e.spawns.items()):
        p = list(pts.values())
        points = [p[i:i + 2] for i in range(0, len(p), 2)]
        if inst in OFFSET:
            world_points += [list(to_world(inst, *x)) for x in points]
        else:
            spawns.append({"inst": inst, "map": MAP_NAMES.get(inst, f"#{inst}"), "points": points})
    if world_points:
        spawns.insert(0, {"inst": WORLD, "map": WORLD_NAME, "points": world_points})
    inside = [{"id": i, "name": (Atlas.Dungeon(i) or {"name": MAP_NAMES.get(i, f"#{i}")})["name"]}
              for i in e.instances.values()]
    return {"spawns": spawns, "instances": inside}


def npc(q):
    n = Atlas.Npc(int(q["id"]))
    return dict(where(n), kind="npc", id=n.id, name=n.name, subName=n.subName, minLevel=n.minLevel,
                maxLevel=n.maxLevel, rank=n.rank, faction=n.faction, services=py(n.services),
                questStarts=refs("quest", n.questStarts), questEnds=refs("quest", n.questEnds))


def object(q):
    o = Atlas.Object(int(q["id"]))
    return dict(where(o), kind="object", id=o.id, name=o.name, objectKind=o.kind,
                questStarts=refs("quest", o.questStarts), questEnds=refs("quest", o.questEnds))


def item(q):
    i = Atlas.Item(int(q["id"]))
    return {"kind": "item", "id": i.id, "name": i.name, "requiredLevel": i.requiredLevel,
            "startQuest": i.startQuest and ref("quest", i.startQuest),
            "npcDrops": refs("npc", i.npcDrops), "objectDrops": refs("object", i.objectDrops),
            "vendors": refs("npc", i.vendors), "itemDrops": refs("item", i.itemDrops)}


def quest(q):
    id = int(q["id"])
    x = Atlas.Quest(id)
    zone = x.zone and Atlas.Area(x.zone)
    objectives = [{"kind": o.kind, "id": o.id, "text": o.text, "name": o.name,
                   "sources": [ref(s.kind, s.id) for s in o.sources.values()]}
                  for o in Atlas.QuestSources(id).values()]
    t = x.triggerEnd
    return {"kind": "quest", "id": id, "name": x.name, "level": x.level, "requiredLevel": x.requiredLevel,
            "faction": x.faction, "zone": zone and zone.name, "objectivesText": py(x.objectivesText),
            "startedBy": refs("npc", x.startedBy.npcs) + refs("object", x.startedBy.objects)
            + refs("item", x.startedBy["items"]),
            "finishedBy": refs("npc", x.finishedBy.npcs) + refs("object", x.finishedBy.objects),
            "objectives": objectives, "triggerEnd": t and dict(where(t), text=t.text)}


FLIGHTS = {p["id"]: on_world(dict(p, inst=m)) for m in OFFSET for p in py(Atlas.FlightPoints(m))}


def flight(q):
    id = int(q["id"])
    f = FLIGHTS[id]
    area = f.get("areaID") and Atlas.Area(f["areaID"])
    dest = [dict(FLIGHTS[p.to], cost=p.cost, kind="flight") for p in Atlas.TaxiPaths().values() if p["from"] == id]
    dest.sort(key=lambda d: d["name"])
    return dict(f, kind="flight", area=area and area.name, destinations=dest)


def dungeon(q):
    d = py(Atlas.Dungeon(int(q["id"])))
    return on_world(dict(d, dungeonKind=d["kind"], kind="dungeon"))


def find(q):
    out = []
    term = q["q"].strip().casefold()
    if len(term) < 2:
        return out
    for m in real_maps():
        if m["inst"] not in OFFSET:
            continue
        if term in m["name"].casefold():
            out.append(dict(kind="place", id=m["uiMapID"], inst=WORLD, name=m["name"], detail="Map"))
        for z in m["zones"]:
            if term in z["name"].casefold():
                out.append(dict(kind="place", id=z["uiMapID"], inst=WORLD, name=z["name"], detail=m["name"]))
    for inst in OFFSET:
        for p in py(Atlas.POIs(inst)):
            if term in p["name"].casefold():
                out.append(on_world(dict(p, kind="poi", inst=inst, detail=MAP_NAMES[inst])))
    for f in FLIGHTS.values():
        if term in f["name"].casefold():
            out.append(dict(kind="flight", id=f["id"], inst=f["inst"], name=f["name"], detail="Flight point"))
    out = out[:40]
    for kind in ("npc", "quest", "object", "item"):
        for id in Atlas.Find(kind, q["q"], 8).values():
            e, r = GET[kind](id), ref(kind, id)
            if kind == "npc":
                r["detail"] = " ".join(x for x in (e.subName and f"<{e.subName}>", e.minLevel and f"lv {e.minLevel}") if x)
            elif kind == "quest":
                r["detail"] = f"lv {e.level}" if e.level else ""
            elif kind == "object":
                r["detail"] = e.kind or ""
            out.append(r)
    return out


def stamp(inst):
    """What the inventory of a map's assets depends on: its folders' and manifests' times (a file added or a manifest
    restamped moves one)."""
    out = []
    for kind in ("tiles", "terrain", "objects"):
        for p in (os.path.join(DEMO, kind, str(inst)), os.path.join(DEMO, kind, str(inst), "manifest.json")):
            try:
                out.append(os.stat(p).st_mtime_ns)
            except OSError:
                out.append(None)
    return tuple(out)


_assets = [None, None]  # the stamps it was worked out at, the answer


def assets(q):
    """Every map's assets on the world, kept until one of them changes (the 3D manifests are read and checked: a
    quarter of a second)."""
    product, version = Atlas.Data.Tiles.product, Atlas.Data.Tiles.version
    key = (tuple(stamp(i) for i in OFFSET), product, version)
    if _assets[0] == key:
        return _assets[1]
    each = {i: inventory(DEMO, i, product, version) for i in OFFSET}
    out = dict(each[WORLD], tiles=sorted(world_key(i, k) for i in OFFSET for k in each[i]["tiles"]),
               blocks=[i for i in OFFSET if each[i]["blocks"]])  # the maps with blocks of quick copies
    for kind in ("terrain", "objects"):
        out[kind] = world_assets(kind, {i: m[kind] for i, m in each.items()})
    _assets[:] = [key, out]
    return out


def world_assets(kind, per_map):
    """Each map's 3D manifest on the world: its tiles at world keys (inst and src: where its files are), its parts'
    offsets and previews. Maps without them are left out; the page translates their meshes by the offset."""
    ok = {i: m for i, m in per_map.items() if m["available"]}
    if not ok:
        return per_map[WORLD]
    tiles = [dict(t, key=world_key(i, t["key"]), inst=i, src=t["key"]) for i, m in ok.items() for t in m["data"]["tiles"]]
    parts = [{"inst": i, "offset": OFFSET[i], "preview": world_preview(i, m["data"].get("preview"))} for i, m in ok.items()]
    expected = sum(m["data"].get("expectedTiles", len(m["data"]["tiles"])) for m in ok.values())
    missing = [MAP_NAMES[i] for i in per_map if i not in ok]
    return {"available": True, "data": {"tiles": tiles, "parts": parts, "expectedTiles": expected},
            "reason": f'{len(tiles)}/{expected} tiles · {next(iter(ok.values()))["reason"].split(" · ")[-1]}'
                      + (f' · none for {", ".join(missing)}' if missing else '')}


def world_preview(inst, p):
    if not p:
        return p
    dx, dy = OFFSET[inst]
    b = p["bounds"]
    return dict(p, bounds=[b[0] + dx, b[1] + dy, b[2] + dx, b[3] + dy],
                tiles=[dict(t, key=world_key(inst, t["key"])) for t in p["tiles"]])


# The world the page shows (it reads the offsets from here); real_* are the Atlas's, one real map at a time.
# The drawn land's extent on the world (c0, r0, c1, r1): what the first view frames.
LAND = (lambda keys: [min(c for c, _ in keys), min(r for _, r in keys), max(c for c, _ in keys) + 1, max(r for _, r in keys) + 1])(
    [to_world(i, k // 64, k % 64) for i in OFFSET for k in Atlas.Tiles(i).keys() if Atlas.Drawn(i, k)])


def maps(q):
    ms = {m["inst"]: m for m in real_maps()}
    zones = sorted((z for i in OFFSET for z in ms[i]["zones"]), key=lambda z: z["name"])
    bounds = [min(b[0] for b in BOUNDS.values()), min(b[1] for b in BOUNDS.values()),
              max(b[2] for b in BOUNDS.values()), max(b[3] for b in BOUNDS.values())]
    parts = [{"inst": i, "name": ms[i]["name"], "offset": OFFSET[i], "bounds": BOUNDS[i]} for i in OFFSET]
    return dict(ms[WORLD], inst=WORLD, name=WORLD_NAME, bounds=bounds, land=LAND, zones=zones, parts=parts)


TILES = {"tiles": [{"key": world_key(i, t["key"]), "sea": t["sea"], "inst": i, "src": t["key"]}
                   for i in OFFSET for t in ({"key": k, "sea": not Atlas.Drawn(i, k)} for k in Atlas.Tiles(i).keys())]}


def tiles(q):
    return TILES  # (the data's: worked out once)


def labels(q):
    out, cities = [], []
    for inst in OFFSET:
        for l in py(Atlas.Labels(inst)):  # { text, col, row, tier, rank, areaID?, poiID?, size? }, rank order
            l["col"], l["row"] = to_world(inst, l["col"], l["row"])
            town = l["tier"] == "town"
            if l["text"] in CITIES:  # every capital named as a zone is, from afar: Ironforge and the Undercity are only towns
                if town and l["text"] in CITIES_AS_TOWNS:
                    cities.append(dict(l, tier="zone", size=CITY_SIZE, text=CITIES[l["text"]]))
                elif l["tier"] == "zone":
                    cities.append(dict(l, text=CITIES[l["text"]]))
                continue
            out.append(l)
    continents = [l for l in out if l["tier"] == "continent"]
    rest = sorted((l for l in out if l["tier"] != "continent"), key=lambda l: l["rank"])
    return {"labels": [dict(l, rank=i + 1) for i, l in enumerate(continents + cities + rest)]}


def at(q):
    inst, col, row = to_real(float(q["col"]), float(q["row"]))
    return real_at(inst, col, row)


def pins(q):
    c0, r0, c1, r1 = (float(q[k]) for k in ("c0", "r0", "c1", "r1"))
    out, omitted = [], 0
    grouped = q.get("groups") == "1"
    for inst, (dx, dy) in OFFSET.items():
        found, n = real_pins(dict(q, inst=inst, c0=c0 - dx, r0=r0 - dy, c1=c1 - dx, r1=r1 - dy))
        omitted += n
        for p in found:
            p["col"], p["row"] = p["col"] + dx, p["row"] + dy
            p["key"] = f'{inst}:{p["key"]}'
            out.append(p)
    if grouped:
        # A modest zoom band keeps membership steady through small zoom changes.
        zoom = float(q["zoom"])
        return {"pins": group_pins(out, 1.25 ** math.floor(math.log(zoom, 1.25) + 0.5)), "omitted": omitted}
    return out


API = {"assets": assets, "maps": maps, "tiles": tiles, "labels": labels,
       "at": at, "fit": fit, "walk": walk, "route": route, "cases": cases, "pins": pins, "npc": npc, "object": object, "item": item, "quest": quest,
       "flight": flight, "dungeon": dungeon, "find": find}


# Tiles load many at once (a phone asks for dozens per pan), so requests run on
# threads; the one Lua runtime isn't thread-safe, so Atlas calls take turns.
atlas_lock = threading.Lock()


class Handler(SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"  # keep-alive: one connection for a screenful of tiles
    extensions_map = {**SimpleHTTPRequestHandler.extensions_map, ".webp": "image/webp"}  # older Pythons lack it

    def __init__(self, *args, **kw):
        super().__init__(*args, directory=DEMO, **kw)

    def send_head(self):
        path = self.translate_path(self.path)
        if os.path.isdir(path):
            path = os.path.join(path, 'index.html')
        if os.path.splitext(path)[1] in COMPRESSIBLE and accepts_gzip(self.headers.get('Accept-Encoding', '')):
            try:
                stat = os.stat(path)
                if 1024 < stat.st_size <= 8 * 1024 * 1024 and os.path.isfile(path):
                    body = compressed_file(path, stat.st_mtime_ns, stat.st_size)
                    self.send_response(200)
                    self.send_header('Content-Type', self.guess_type(path))
                    self.send_header('Content-Encoding', 'gzip')
                    self.send_header('Content-Length', str(len(body)))
                    self.send_header('Last-Modified', self.date_time_string(stat.st_mtime))
                    self.end_headers()
                    return io.BytesIO(body)
            except OSError:
                pass  # Normal static-file handling supplies the appropriate 404.
        return super().send_head()

    def do_GET(self):
        u = urlparse(self.path)
        if u.path.startswith("/api/"):
            q = {k: v[0] for k, v in parse_qs(u.query).items()}
            status = 200
            try:
                endpoint = API.get(u.path[5:])
                if endpoint is None:
                    raise LookupError("Unknown endpoint")
                for k in ("col", "row", "zoom", "w", "h", "c0", "r0", "c1", "r1"):
                    if k in q and (not math.isfinite(float(q[k])) or abs(float(q[k])) > 1e6):
                        raise ValueError("invalid coordinate or dimension")
                for k in ("w", "h"):
                    if k in q and float(q[k]) <= 0:
                        raise ValueError("invalid viewport size")
                with atlas_lock:
                    body = json.dumps(endpoint(q), allow_nan=False).encode()
            except LookupError:
                status, body = 404, b'{"error":"Not found"}'
            except (ValueError, TypeError, AttributeError, LuaError):
                status, body = 400, b'{"error":"Invalid request"}'
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Vary", "Accept-Encoding")
            if len(body) > 1024 and accepts_gzip(self.headers.get("Accept-Encoding", "")):
                body = gzip.compress(body, 6)
                self.send_header("Content-Encoding", "gzip")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            try:
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError):
                pass  # a superseded view may close the connection
        else:
            super().do_GET()

    def send_response(self, code, message=None):
        self.code = code
        super().send_response(code, message)

    def end_headers(self):
        path = urlparse(self.path).path
        if os.path.splitext(path)[1] in COMPRESSIBLE or path.endswith('/'):
            self.send_header('Vary', 'Accept-Encoding')
        if self.path.startswith("/tiles/") and "?v=" in self.path and self.code == 200:  # (its build in the address)
            self.send_header("Cache-Control", "public, max-age=31536000, immutable")
        elif self.path.startswith(("/tiles/", "/terrain/", "/objects/")) and not self.path.endswith("manifest.json") and self.code == 200:
            self.send_header("Cache-Control", "public, max-age=86400")
        else:  # the page and its scripts: always the current ones
            self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    assets({}), labels({})  # (worked out before the first visitor asks: they're the first view's)
    print(f"Atlas demo on http://localhost:{port}")
    # A screenful of tiles comes as a burst of new connections from the host's proxy: the stock backlog of 5 dropped
    # the rest, each retried by TCP a second later (a 1.1 s tail on a third of the tiles).
    ThreadingHTTPServer.request_queue_size = 512
    ThreadingHTTPServer.daemon_threads = True
    ThreadingHTTPServer(("", port), Handler).serve_forever()
