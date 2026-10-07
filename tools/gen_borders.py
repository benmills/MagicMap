#!/usr/bin/env python3
"""Generate Data/Borders.lua: exact zone and subzone borders, plus
label anchors, from the game's own terrain.

Every ADT tile is split into 16x16 chunks (~33 yards) and each chunk (MCNK)
records its AreaTable ID: the game's own definition of where zones and
subzones are. AreaTable's parent links give each area's zone. We trace the
chunk edges where the zone (or, within a zone, the subzone) changes, skip
edges out in deep sea on both sides (so borders stop at the coast), chain the
edges into polylines and simplify them. Label anchors are the land chunk
deepest inside each area (farthest from its edge).

  python3 tools/gen_borders.py local "/Applications/World of Warcraft" wow_classic_beta \\
      -o Data/Borders.lua

Output is deterministic: the same game data always gives the same file.
"""
from __future__ import annotations

import argparse
import math
import sys
from collections import deque

from mmtools.formats import adt_chunks, wdt_maid
from mmtools.maps import AREATABLE_DB2, MAP_DB2, read_area_parents, read_maps
from mmtools.sources import Source, add_source_args, source_from_args

SEA_LEVEL = -2       # chunks whose highest point is below this are open sea (zone borders stop)
SHORE_LEVEL = 0.5    # ...below this, water: no subzone borders out there
MIN_SUBZONE_EDGE_CELLS = 4  # subzones smaller than this (land chunks) get no outline
SIMPLIFY = 0.4       # Douglas-Peucker tolerance, in chunks
MIN_SUBZONE_CELLS = 6  # subzones smaller than this get no label

# Chunk cells are keyed gc * 1024 + gr (global chunk column, row); chunk
# corners (border vertices) vx * 1100 + vy.
CELL, VERT = 1024, 1100


def log(msg: str) -> None:
    print(msg, file=sys.stderr)


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


def read_terrain(src: Source, adts: dict[int, int]):
    """Per chunk cell: area ID, and whether it's open sea / water."""
    area, sea, wet = {}, set(), set()
    src.prefetch(adts.values())
    for key in sorted(adts):
        buf = src.read(adts[key])
        if buf is None:
            continue
        col, row = key // 64, key % 64
        for ch in adt_chunks(buf):
            c = (col * 16 + ch.ix) * CELL + (row * 16 + ch.iy)
            area[c] = ch.area
            top = ch.max_height
            if top < SEA_LEVEL:
                sea.add(c)
            if top < SHORE_LEVEL:
                wet.add(c)
    return area, sea, wet


def neighbours(c: int):
    return (c - CELL, c + CELL, c - 1, c + 1)


def trace_map(area: dict, sea: set, wet: set, areas: Areas, tol: float):
    zone, sub = {}, {}
    for c, a in area.items():
        if a:
            zone[c] = areas.zone_of(a)
            sub[c] = areas.sub_of(a)
    sub_land, zone_land, zone_all = {}, {}, {}
    for c in sub:
        zone_all[zone[c]] = zone_all.get(zone[c], 0) + 1
        if c in wet:
            continue
        sub_land[sub[c]] = sub_land.get(sub[c], 0) + 1
        zone_land[zone[c]] = zone_land.get(zone[c], 0) + 1
    # "Zones" that are mostly water (e.g. The Great Sea, even with a few
    # islets) aren't zones on a map.
    sea_zone = {z for z, n in zone_all.items() if zone_land.get(z, 0) < 10 or zone_land[z] < n * 0.25}
    zone = {c: z for c, z in zone.items() if z not in sea_zone}

    # --- edges between chunks ----------------------------------------------
    edges = []  # (kind, v1, v2, (a, b))
    for c in sorted(area):
        gc, gr = divmod(c, CELL)
        for dc, dr in ((1, 0), (0, 1)):
            n = (gc + dc) * CELL + gr + dr
            if n not in area or (c in sea and n in sea):
                continue
            za, zb = zone.get(c, 0), zone.get(n, 0)
            if za and zb and za != zb:
                kind, a, b = 1, za, zb
            elif za and za == zb and sub.get(c, 0) != sub.get(n, 0):
                # Subzones: only on land, and only for areas big enough to matter.
                if c in wet or n in wet:
                    continue
                if sub_land.get(sub[c], 0) < MIN_SUBZONE_EDGE_CELLS or sub_land.get(sub[n], 0) < MIN_SUBZONE_EDGE_CELLS:
                    continue
                kind, a, b = 2, sub[c], sub[n]
            else:
                continue
            if a > b:
                a, b = b, a
            if dc:  # vertical edge
                v1, v2 = (gc + 1) * VERT + gr, (gc + 1) * VERT + gr + 1
            else:   # horizontal edge
                v1, v2 = gc * VERT + gr + 1, (gc + 1) * VERT + gr + 1
            edges.append((kind, v1, v2, (a, b)))

    adj, degree = {}, {}
    for i, (_, v1, v2, _) in enumerate(edges):
        adj.setdefault(v1, []).append(i)
        adj.setdefault(v2, []).append(i)
        degree[v1] = degree.get(v1, 0) + 1
        degree[v2] = degree.get(v2, 0) + 1

    # --- chain edges of one kind + one area pair into polylines ------------
    used = [False] * len(edges)
    lines = []

    def same_line(i: int, kind: int, pair) -> bool:
        return edges[i][0] == kind and edges[i][3] == pair

    def walk(start: int, ei: int) -> None:
        kind, _, _, pair = edges[ei]
        pts, node = [start], start
        while ei is not None and not used[ei]:
            used[ei] = True
            _, v1, v2, _ = edges[ei]
            node = v2 if v1 == node else v1
            pts.append(node)
            same = [i for i in adj[node] if same_line(i, kind, pair)]
            nxt = [i for i in same if not used[i]]
            if not (len(same) == 2 and len(nxt) == 1):
                break
            ei = nxt[0]
        # A true dead end (nothing else meets it) fades out instead of stopping.
        fade_start = 1 if degree[start] == 1 else 0
        fade_end = 1 if degree[node] == 1 else 0
        xy = simplify([divmod(v, VERT) for v in pts], tol)
        lines.append((kind, pair[0], pair[1], fade_start, fade_end, xy))

    for v in sorted(adj):
        for ei in adj[v]:
            if used[ei]:
                continue
            kind, _, _, pair = edges[ei]
            if sum(1 for i in adj[v] if same_line(i, kind, pair)) != 2:
                walk(v, ei)
    for ei, e in enumerate(edges):  # closed loops
        if not used[ei]:
            walk(e[1], ei)

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

    lines.sort(key=lambda l: l[0])  # stable: zones first, then subzones
    return lines, labels


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    add_source_args(parser)
    parser.add_argument("-o", "--output", help="output file (default: stdout)")
    parser.add_argument("--min-tiles", type=int, default=20, help="skip maps with fewer terrain tiles (default 20)")
    parser.add_argument("--simplify", type=float, default=SIMPLIFY, help=argparse.SUPPRESS)
    ns = parser.parse_args()
    src = source_from_args(parser, ns)

    src.prefetch([MAP_DB2, AREATABLE_DB2])
    map_db2, area_db2 = src.read(MAP_DB2), src.read(AREATABLE_DB2)
    if map_db2 is None or area_db2 is None:
        raise SystemExit("Map.db2 / AreaTable.db2 not available")
    areas = Areas(read_area_parents(area_db2))
    maps = [m for m in read_maps(map_db2) if m.kind is None]
    src.prefetch(m.wdt for m in maps)

    out = open(ns.output, "w", encoding="utf-8", newline="\n") if ns.output else sys.stdout
    w = out.write
    w(f"-- GENERATED by tools/gen_borders.py from the {src.product} {src.version} terrain (ADT chunk areas). Do not edit.\n")
    w("-- lines: { kind (1 zone, 2 subzone), areaA, areaB, fadeStart, fadeEnd, x1, y1, x2, y2, ... } in tile units\n")
    w("-- labels: { areaID, col, row, weight (land chunks), kind }\n")
    w("MagicMap_Borders = {\n")
    for m in sorted(maps, key=lambda m: m.inst):
        wdt = src.read(m.wdt)
        if wdt is None:
            continue
        adts = {k: t.root_adt for k, t in wdt_maid(wdt).items() if t.root_adt}
        if len(adts) < ns.min_tiles:
            continue
        area, sea, wet = read_terrain(src, adts)
        if not area:
            continue
        lines, labels = trace_map(area, sea, wet, areas, ns.simplify)
        log("%s: [%d] %s: %d zone lines, %d subzone lines, %d labels" % (
            src.product, m.inst, m.name, sum(1 for l in lines if l[0] == 1),
            sum(1 for l in lines if l[0] == 2), len(labels)))
        name = m.name.replace("\n", " ")
        w(f"  [{m.inst}] = {{ -- {name}\n    lines = {{\n")
        for kind, a, b, fs, fe, xy in lines:
            pts = ", ".join("%.2f, %.2f" % (x / 16, y / 16) for x, y in xy)
            w(f"      {{ {kind}, {a}, {b}, {fs}, {fe}, {pts} }},\n")
        w("    },\n    labels = {\n")
        for label in labels:
            w("      { %d, %.2f, %.2f, %d, %d },\n" % label)
        w("    },\n  },\n")
    w("}\n")
    if out is not sys.stdout:
        out.close()


if __name__ == "__main__":
    main()
