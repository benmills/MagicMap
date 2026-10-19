#!/usr/bin/env python3
"""Generate Data/Borders.lua: zone borders, zone outlines and label anchors,
from the game's own terrain.

Every ADT tile is split into 16x16 chunks (~33 yards) and each chunk (MCNK)
records its AreaTable ID: the game's own definition of where zones and
subzones are. AreaTable's parent links give each area's zone. We trace the
chunk edges around each zone's land (chunks above the shore line), chain them
into polylines between junctions, and smooth each chain (its ends stay put, so
neighbours still meet, three at a junction) into a curve. Zone-to-zone chains
are the borders, at levels of detail (the coarser ones drawn zoomed out:
atlas/Borders.lua); where one reaches the shore it runs on a little over water,
to fade out there. Each zone's chains also close into its outline. Within a
zone, the edges between two subzones on land, each big enough to matter, are
the subzone borders, chained and smoothed the same way, at two levels. (The
spike melts their 33-yard steps with Douglas-Peucker at 0.035 tiles and
Chaikin corner cutting, Layers.lua:1424-1425, 1503-1519; smoothed as the zone
borders are, they come out rounder in half its points.) Label anchors are the
land chunk deepest inside each zone and subzone (farthest from its edge).

  python3 tools/gen_borders.py local "/Applications/World of Warcraft" wow_classic_beta \\
      -o Data/Borders.lua

Output is deterministic: the same game data always gives the same file.
"""
from __future__ import annotations

import argparse
import math
import sys
from collections import deque

from mmtools.formats import adt_chunks, adt_liquids, wdt_maid
from mmtools.log import log
from mmtools.luaout import data_head
from mmtools.maps import AREATABLE_DB2, MAP_DB2, read_area_parents, read_maps
from mmtools.sources import Source, add_source_args, source_from_args

SEA_LEVEL = -2       # chunks whose highest point is below this are open sea (no labels there)
SHORE_LEVEL = 0.5    # ...below this, water (and so is a chunk mostly under the sea): borders and
                     # outlines stop at the shore
SEA_SURFACE = 3      # liquid whose surface is within this of 0 is the sea
SIGMA = 2.0          # smoothing, in chunks
NEAR = 0.003         # Douglas-Peucker tolerance of the borders, in tiles; and of the levels drawn
LEVELS = (           # below a zoom (px per tile), each within about 1.5 px there (atlas/Borders.lua):
    ("z12", 0.15),   # the bands for the furthest out (docs/v1-plan.md M1.4)
    ("z30", 0.05),
    ("far", 0.03),   # below 50
    ("z100", 0.015),
    ("z200", 0.0075),  # (subzones' too: drawn from zoom 140)
)
COAST = 0.01         # Douglas-Peucker tolerance of outlines along the coast (and land of no zone)
TAIL = 4             # chunk edges a border runs on over water, fading out
DEAD_END = 0.1       # tiles a border fades over where it stops on land (no zone beyond)
MIN_RING = 12        # outline rings enclosing fewer chunks (islets, ponds) are dropped
MIN_SUBZONE_CELLS = 6  # subzones smaller than this get no label
MIN_SUBZONE_EDGE_CELLS = 4  # ...nor a border, under this many land chunks (the spike's gen_borders.py)

# Chunk cells are keyed gc * 1024 + gr (global chunk column, row); chunk
# corners (border vertices) vx * 1100 + vy.
CELL, VERT = 1024, 1100


class Areas:
    def __init__(self, parents: dict[int, int]):
        self.parent = parents

    def zone_of(self, a: int) -> int:
        """The root ancestor."""
        for _ in range(10):
            if not self.parent.get(a):
                break
            a = self.parent[a]
        return a

    def sub_of(self, a: int) -> int:
        """The zone's child on the path from a up to its zone."""
        for _ in range(10):
            p = self.parent.get(a)
            if not (p and self.parent.get(p)):
                break
            a = p
        return a


def simplify(pts: list[tuple[int, int]], tol: float) -> list[tuple[int, int]]:
    """Douglas-Peucker."""
    n = len(pts)
    if n <= 2:
        return pts
    keep = {0, n - 1}
    stack = [(0, n - 1)]
    while stack:
        i, j = stack.pop()
        (ax, ay), (bx, by) = pts[i], pts[j]
        dx, dy = bx - ax, by - ay
        length = math.sqrt(dx * dx + dy * dy)
        worst, worst_d = None, tol
        for k in range(i + 1, j):
            px, py = pts[k]
            if length < 1e-9:
                d = math.sqrt((px - ax) ** 2 + (py - ay) ** 2)
            else:
                d = abs(dy * px - dx * py + bx * ay - by * ax) / length
            if d > worst_d:
                worst, worst_d = k, d
        if worst is not None:
            keep.add(worst)
            stack.append((i, worst))
            stack.append((worst, j))
    return [pts[k] for k in sorted(keep)]


def under_sea(ch, liquids) -> bool:
    """Is most of the chunk under sea-level water? (Its highest point can still
    be a cliff top: a chunk off a cliffy coast is sea, not land.)"""
    if ch.max_height < SHORE_LEVEL:
        return True
    h = ch.heights
    sea = [liq for liq in liquids if abs(liq.surface) < SEA_SURFACE]
    if h is None or not sea:
        return False
    n = 0
    for qy in range(8):
        for qx in range(8):
            ground = ch.z + (h[qy * 17 + qx] + h[qy * 17 + qx + 1] + h[(qy + 1) * 17 + qx]
                             + h[(qy + 1) * 17 + qx + 1] + h[qy * 17 + 9 + qx]) / 5
            n += any(liq.covers(qx, qy) and liq.surface > ground for liq in sea)
    return n * 2 >= 64


def read_terrain(src: Source, adts: dict[int, int]):
    """Per chunk cell: area ID, and whether it's open sea / below the shore line /
    under the sea."""
    area, sea, wet, water = {}, set(), set(), set()
    src.prefetch(adts.values())
    for key in sorted(adts):
        buf = src.read(adts[key])
        if buf is None:
            continue
        col, row = key // 64, key % 64
        liquids = {}
        for liq in adt_liquids(buf):
            liquids.setdefault((liq.ix, liq.iy), []).append(liq)
        for ch in adt_chunks(buf):
            c = (col * 16 + ch.ix) * CELL + (row * 16 + ch.iy)
            area[c] = ch.area
            top = ch.max_height
            if top < SEA_LEVEL:
                sea.add(c)
            if top < SHORE_LEVEL:
                wet.add(c)
            if under_sea(ch, liquids.get((ch.ix, ch.iy), ())):
                water.add(c)
    return area, sea, wet, water


def neighbours(c: int):
    return (c - CELL, c + CELL, c - 1, c + 1)


def smooth(pts: list, closed: bool) -> list:
    """Gaussian smoothing (SIGMA chunks) of a chain of unit chunk edges: the
    33-yard steps melt into curves. An open chain's ends stay put (reflected
    through them), so chains still meet where they did."""
    n = len(pts) - 1
    if closed:
        pts = pts[:-1]
    r = min(int(3 * SIGMA), n)
    w = [math.exp(-k * k / (2 * SIGMA * SIGMA)) for k in range(-r, r + 1)]
    total = sum(w)

    def at(j):
        if closed:
            return pts[j % len(pts)]
        if j < 0:
            return 2 * pts[0][0] - pts[-j][0], 2 * pts[0][1] - pts[-j][1]
        if j > n:
            return 2 * pts[n][0] - pts[2 * n - j][0], 2 * pts[n][1] - pts[2 * n - j][1]
        return pts[j]

    out = []
    for i in range(len(pts)):
        x = y = 0.0
        for k in range(-r, r + 1):
            px, py = at(i + k)
            x += w[k + r] * px
            y += w[k + r] * py
        out.append((x / total, y / total))
    if closed:
        out.append(out[0])
    else:
        out[0], out[-1] = pts[0], pts[n]  # exact, not just nearly
    return out


def length(pts: list) -> float:
    return sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(pts, pts[1:]))


def chains(edges: dict):
    """Chain edges {(v1, v2): pair} into polylines of one pair each, broken
    wherever anything else meets them. Yields (pair, [vertex, ...], closed)."""
    adj = {}
    for e in edges:
        adj.setdefault(e[0], []).append(e)
        adj.setdefault(e[1], []).append(e)
    used = set()

    def walk(start, e):
        pair, pts, node = edges[e], [start], start
        while e is not None and e not in used:
            used.add(e)
            node = e[1] if e[0] == node else e[0]
            pts.append(node)
            nxt = [x for x in adj[node] if x not in used and edges[x] == pair]
            e = nxt[0] if len(adj[node]) == 2 and nxt else None
        return pair, pts, node == start and len(adj[start]) == 2

    for v in sorted(adj):
        if len(adj[v]) != 2 or edges[adj[v][0]] != edges[adj[v][1]]:
            for e in sorted(adj[v]):
                if e not in used:
                    yield walk(v, e)
    for e in sorted(edges):  # closed loops: no junction on them
        if e not in used:
            yield walk(e[0], e)


def edge_of(c: int, n: int):
    """The chunk edge between neighbouring cells c and n, as (vertex, vertex)."""
    (gc, gr), (nc, nr) = divmod(c, CELL), divmod(n, CELL)
    x, y = max(gc, nc), max(gr, nr)
    if nc != gc:  # vertical edge
        return (x * VERT + y, x * VERT + y + 1)
    return (x * VERT + y, (x + 1) * VERT + y)


def ring_area(pts: list) -> float:
    return abs(sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(pts, pts[1:]))) / 2


def trace_map(area: dict, sea: set, wet: set, water: set, areas: Areas):
    zone, sub = {}, {}
    for c, a in area.items():
        if a:
            zone[c] = areas.zone_of(a)
            sub[c] = areas.sub_of(a)
    zone_land, zone_all = {}, {}
    for c in sub:
        zone_all[zone[c]] = zone_all.get(zone[c], 0) + 1
        if c not in wet:
            zone_land[zone[c]] = zone_land.get(zone[c], 0) + 1
    # "Zones" that are mostly water (e.g. The Great Sea, even with a few
    # islets) aren't zones on a map.
    sea_zone = {z for z, n in zone_all.items() if zone_land.get(z, 0) < 10 or zone_land[z] < n * 0.25}
    zone = {c: z for c, z in zone.items() if z not in sea_zone}

    # --- every edge of every zone's land (to another zone, or 0: water, no zone)
    land = {c: z for c, z in zone.items() if c not in water}
    edges = {}
    for c in sorted(land):
        for n in neighbours(c):
            if land.get(n, 0) != land[c]:
                edges[edge_of(c, n)] = tuple(sorted((land[c], land.get(n, 0))))
    # ...and zone borders out over water, for the ends that run on and fade out
    wet_edges = {}
    for c in sorted(zone):
        for n in (c + CELL, c + 1):
            if n in zone and zone[n] != zone[c] and (c not in land or n not in land):
                wet_edges[edge_of(c, n)] = tuple(sorted((zone[c], zone[n])))
    wet_adj = {}
    for e in wet_edges:
        wet_adj.setdefault(e[0], []).append(e)
        wet_adj.setdefault(e[1], []).append(e)
    vert = lambda v: divmod(v, VERT)  # noqa: E731

    def tail(v, pair):
        """The border of pair running on from shore vertex v over water."""
        pts, seen = [v], set()
        for _ in range(TAIL):
            nxt = [e for e in wet_adj.get(v, ()) if wet_edges[e] == pair and e not in seen]
            if len(nxt) != 1:
                break
            seen.add(nxt[0])
            v = nxt[0][1] if nxt[0][0] == v else nxt[0][0]
            pts.append(v)
        return [vert(p) for p in pts]

    def coast(v):  # does land of no zone (or water) touch vertex v?
        x, y = divmod(v, VERT)
        return any(land.get((x - dx) * CELL + y - dy, 0) == 0 for dx in (0, 1) for dy in (0, 1))

    lines, rims = [], {}  # rims: zone -> its outline chains
    for pair, vs, closed in chains(edges):
        pts = smooth([vert(v) for v in vs], closed)
        rim = simplify(pts, (COAST if not pair[0] else NEAR) * 16)
        for z in pair:
            if z:
                rims.setdefault(z, []).append(rim)
        if not pair[0]:
            continue
        ends = []
        for v in (vs[0], vs[-1]):
            t = tail(v, pair) if not closed and coast(v) else []
            t = smooth(t, False) if len(t) > 1 else []
            ends.append((t, length(t) / 16 if t else DEAD_END if not closed and coast(v) else 0))
        (t0, f0), (t1, f1) = ends
        lod = []
        for tol in (NEAR, *(t for _, t in LEVELS)):
            def part(p):
                return simplify(p, tol * 16)
            xy = part(t0[::-1])[:-1] + part(pts) + part(t1)[1:] if t0 else part(pts) + part(t1)[1:]
            lod.append(xy)
        lines.append((pair[0], pair[1], f0, f1, *lod))

    # --- subzone borders: two subzones of one zone meeting on land, each big enough to matter
    sub_land = {}
    for c, s in sub.items():
        if c not in wet:
            sub_land[s] = sub_land.get(s, 0) + 1
    sub_edges = {}
    for c in sorted(zone):
        for n in (c + CELL, c + 1):
            if zone.get(n) != zone[c] or sub[n] == sub[c] or c in wet or n in wet:
                continue
            if min(sub_land.get(sub[c], 0), sub_land.get(sub[n], 0)) < MIN_SUBZONE_EDGE_CELLS:
                continue
            sub_edges[edge_of(c, n)] = tuple(sorted((sub[c], sub[n])))
    subs = []
    for pair, vs, closed in chains(sub_edges):
        pts = smooth([vert(v) for v in vs], closed)
        subs.append((pair[0], pair[1], simplify(pts, NEAR * 16), simplify(pts, dict(LEVELS)["z200"] * 16)))

    # --- each zone's land as closed rings, from the same chains --------------
    outlines = {}
    for z in sorted(rims):
        todo, by_end = list(rims[z]), {}
        for i, p in enumerate(todo):
            by_end.setdefault(p[0], []).append(i)
            by_end.setdefault(p[-1], []).append(i)
        used, rings = set(), []
        for i in range(len(todo)):
            if i in used:
                continue
            used.add(i)
            ring = list(todo[i])
            while ring[-1] != ring[0]:
                j = next(j for j in by_end[ring[-1]] if j not in used)
                used.add(j)
                p = todo[j] if todo[j][0] == ring[-1] else todo[j][::-1]
                ring += p[1:]
            if ring_area(ring) >= MIN_RING:
                rings.append(ring[:-1])
        if rings:
            outlines[z] = rings

    # --- label anchors: deepest land chunk of each zone / subzone ------------
    labels = []
    for kind, ids in ((1, zone), (2, sub)):
        dist, queue, count = {}, deque(), {}
        for c in sorted(ids):
            if c in sea:
                continue
            count[ids[c]] = count.get(ids[c], 0) + 1
            if any(n not in ids or n in sea or ids[n] != ids[c] for n in neighbours(c)):
                dist[c] = 0
                queue.append(c)
        while queue:
            c = queue.popleft()
            for n in neighbours(c):
                if n in dist or n not in ids or n in sea or ids[n] != ids[c]:
                    continue
                dist[n] = dist[c] + 1
                queue.append(n)
        best = {}
        for c in sorted(dist):  # ties: the lowest cell key wins
            i = ids[c]
            if i not in best or dist[c] > dist[best[i]]:
                best[i] = c
        for i in sorted(best):
            if kind == 2 and (count[i] < MIN_SUBZONE_CELLS or i == areas.zone_of(i)):
                continue
            c = best[i]
            labels.append((i, (c // CELL + 0.5) / 16, (c % CELL + 0.5) / 16, count[i], kind))

    return lines, subs, outlines, labels


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    add_source_args(parser)
    parser.add_argument("-o", "--output", help="output file (default: stdout)")
    parser.add_argument("--min-tiles", type=int, default=20, help="skip maps with fewer terrain tiles (default 20)")
    ns = parser.parse_args()
    src = source_from_args(parser, ns)

    src.prefetch([MAP_DB2, AREATABLE_DB2])
    map_db2, area_db2 = src.read(MAP_DB2), src.read(AREATABLE_DB2)
    if map_db2 is None or area_db2 is None:
        raise SystemExit("Map.db2 / AreaTable.db2 not available")
    areas = Areas(read_area_parents(area_db2))
    maps = [m for m in read_maps(map_db2) if m.kind is None]
    src.prefetch(m.wdt for m in maps)

    def flat(xy):
        return ", ".join("%.3f, %.3f" % (x / 16, y / 16) for x, y in xy)

    out = open(ns.output, "w", encoding="utf-8", newline="\n") if ns.output else sys.stdout
    w = out.write
    w(f"-- GENERATED by tools/gen_borders.py from the {src.product} {src.version} terrain (ADT chunk areas). Do not edit.\n")
    w("-- lines: zone borders, smoothed: { areaA, areaB, fadeStart, fadeEnd, x1, y1, x2, y2, ... } in tile units,\n")
    w(f"--   within {NEAR} tiles; fadeStart/fadeEnd: tiles over which that end fades out (over water), 0 none\n")
    w("-- " + ", ".join(f"{k} within {t}" for k, t in LEVELS) + ": the same, for zoomed out (atlas/Borders.lua)\n")
    w(f"-- sub: subzone borders, on land, smoothed: {{ areaA, areaB, x1, y1, ... }}, within {NEAR} tiles; subz200: within"
      f" {dict(LEVELS)['z200']}\n")
    w(f"-- outlines: [zone areaID] = {{ ring, ... }}, ring = {{ x1, y1, x2, y2, ... }} closed, its land (even-odd)\n")
    w("-- labels: { areaID, col, row, weight (land chunks), kind }\n")
    w(data_head("Borders"))
    w("D.Borders = {\n")
    for m in sorted(maps, key=lambda m: m.inst):
        wdt = src.read(m.wdt)
        if wdt is None:
            continue
        adts = {k: t.root_adt for k, t in wdt_maid(wdt).items() if t.root_adt}
        if len(adts) < ns.min_tiles:
            continue
        area, sea, wet, water = read_terrain(src, adts)
        if not area:
            continue
        lines, subs, outlines, labels = trace_map(area, sea, wet, water, areas)
        log("%s: [%d] %s: %d border lines (%s points), %d subzone (%s points), %d zone outlines, %d labels" % (
            src.product, m.inst, m.name, len(lines), " / ".join(str(sum(len(l[k]) for l in lines)) for k in range(4, 5 + len(LEVELS))),
            len(subs), " / ".join(str(sum(len(s[k]) for s in subs)) for k in (2, 3)), len(outlines), len(labels)))
        name = m.name.replace("\n", " ")
        w(f"  [{m.inst}] = {{ -- {name}\n")
        for key, lod in (("lines", 4), *((k, 5 + i) for i, (k, _) in enumerate(LEVELS))):
            w(f"    {key} = {{\n")
            for line in lines:
                w("      { %d, %d, %.3f, %.3f, %s },\n" % (line[0], line[1], line[2], line[3], flat(line[lod])))
            w("    },\n")
        for key, lod in (("sub", 2), ("subz200", 3)):
            w(f"    {key} = {{\n")
            for sub in subs:
                w("      { %d, %d, %s },\n" % (sub[0], sub[1], flat(sub[lod])))
            w("    },\n")
        w("    outlines = {\n")
        for z, rings in outlines.items():
            w(f"      [{z}] = {{\n")
            for ring in rings:
                w(f"        {{ {flat(ring)} }},\n")
            w("      },\n")
        w("    },\n    labels = {\n")
        for label in labels:
            w("      { %d, %.2f, %.2f, %d, %d },\n" % label)
        w("    },\n  },\n")
    w("}\n")
    if out is not sys.stdout:
        out.close()


if __name__ == "__main__":
    main()
