#!/usr/bin/env python3
"""Generate Data/Anchors.lua: a spot for each zone's and subzone's name, from the game's own terrain.

Every ADT tile is split into 16x16 chunks (~33 yards) and each chunk (MCNK)
records its AreaTable ID: the game's own definition of where zones and
subzones are. AreaTable's parent links give each area's zone. An anchor is the
land chunk deepest inside its zone or subzone (farthest from its edge).

  python3 tools/gen_anchors.py local "/Applications/World of Warcraft" wow_classic_beta \\
      -o Data/Anchors.lua

Output is deterministic: the same game data always gives the same file.
"""
from __future__ import annotations

import argparse
import sys
from collections import deque

from mmtools.formats import adt_chunks, wdt_maid
from mmtools.log import log
from mmtools.luaout import data_head
from mmtools.maps import AREATABLE_DB2, MAP_DB2, read_area_parents, read_maps
from mmtools.sources import Source, add_source_args, source_from_args

SEA_LEVEL = -2       # chunks whose highest point is below this are open sea (no anchors there)
SHORE_LEVEL = 0.5    # ...below this, water: not land, to a zone's size
FRAGMENT = 64        # zones with fewer land chunks on a map join the neighbour they meet most
MIN_SUBZONE_CELLS = 6  # subzones smaller than this get no anchor

# Chunk cells are keyed gc * 1024 + gr (global chunk column, row).
CELL = 1024


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


def read_terrain(src: Source, adts: dict[int, int]):
    """Per chunk cell: area ID, and whether it's open sea / below the shore line."""
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


def anchors_of(area: dict, sea: set, wet: set, areas: Areas) -> list:
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
    # A stray piece of an area (The Great Sea's on Kalimdor's coast, between Durotar and Azshara) is no place
    # on this map: its chunks join the zone they meet most.
    for z in sorted(z for z, n in zone_land.items() if n < FRAGMENT and z not in sea_zone):
        mine = [c for c, y in zone.items() if y == z]
        near = {}
        for c in mine:
            for n in neighbours(c):
                y = zone.get(n)
                if y is not None and y != z:
                    near[y] = near.get(y, 0) + 1
        if near:
            to = max(sorted(near), key=near.get)
            log(f"  zone {z}: {len(mine)} chunks ({zone_land[z]} land) join zone {to}")
            for c in mine:
                zone[c] = to

    # The deepest land chunk of each zone / subzone.
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
    return labels


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

    out = open(ns.output, "w", encoding="utf-8", newline="\n") if ns.output else sys.stdout
    w = out.write
    w(f"-- GENERATED by tools/gen_anchors.py from the {src.product} {src.version} terrain (ADT chunk areas). Do not edit.\n")
    w("-- [inst] = { { areaID, col, row, weight (land chunks), kind (1: a zone, 2: a subzone) }, ... }\n")
    w(data_head("Anchors"))
    w("D.Anchors = {\n")
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
        labels = anchors_of(area, sea, wet, areas)
        log("%s: [%d] %s: %d anchors" % (src.product, m.inst, m.name, len(labels)))
        name = m.name.replace("\n", " ")
        w(f"  [{m.inst}] = {{ -- {name}\n")
        for label in labels:
            w("    { %d, %.2f, %.2f, %d, %d },\n" % label)
        w("  },\n")
    w("}\n")
    if out is not sys.stdout:
        out.close()


if __name__ == "__main__":
    main()
