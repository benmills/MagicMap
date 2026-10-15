#!/usr/bin/env python3
"""Generate Data/Labels.lua: every map name as a ranked anchor (what it is, where it
sits, how much it matters), from the other Data files. Static facts only: how big,
when and whether a name is drawn is the UI's to decide (it places them in rank
order, dropping ones that collide). It was Atlas.Labels' work at first use, the
play-test's 56 ms first open (docs/v1-plan.md §2, M1.1).

  .venv/bin/python tools/gen_labels.py -o Data/Labels.lua

Tiers, most important first:
  continent  the continent's name, at the land's visual centre
  zone       Data/Borders.lua labels of kind 1, by land area
  town       AreaPOI towns and cities (Places.lua), capitals first
  subzone    Data/Borders.lua labels of kind 2, by land area
  poi        AreaPOI landmarks
A town and the subzone label of the same name at the same spot are one name: the
town (at its POI, where its pin is). A landmark that duplicates a subzone label is
skipped. POIs with a description are events or world-PvP states, not places, so
they're left out.

Output is deterministic: the same Data files always give the same file.
"""
from __future__ import annotations

import argparse
import math
import os
import sys

import lupa.lua51 as lupa

from mmtools.log import log
from mmtools.luaout import data_head, load_data, lua_str

DATA = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Data")
INPUTS = ("Tiles", "Walk", "UiMaps", "Areas", "Borders", "Places")

CHUNKS = 16           # walk chunks per tile side (atlas/Walk.lua)
WATER = 2             # walk class: deep water
SAME_SPOT = 0.5       # tiles (~270 yd): a POI this near a subzone label of its name is that label
CENTRE_SAMPLES = 4    # land samples per tile side when finding the continent's visual centre
TIERS = {"continent": 1, "zone": 2, "town": 3, "subzone": 4, "poi": 5}
TOWN_ICON = {4: 1, 5: 2}  # AreaPOI icons: 4 town, 5 capital; 6 a place, 2 a lake
POI_ICON = {2, 6}
WORLD, CONTINENT = 1, 2   # Enum.UIMapType


def array(t) -> list:
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else []


def num(v: float, places: int = 3) -> str:
    s = f"{v:.{places}f}".rstrip("0").rstrip(".")
    return "0" if s == "-0" else s


class Walk:
    """Data/Walk.lua's chunk classes for one inst (atlas/Walk.lua Cell)."""

    def __init__(self, tiles):
        self.tiles = {}
        for key, enc in tiles.items():
            parts, i = [], 0
            while i < len(enc):
                j = i + 1
                while j < len(enc) and enc[j].isdigit():
                    j += 1
                parts.append(enc[i] * int(enc[i + 1:j] or 1))
                i = j
            self.tiles[key] = "".join(parts)

    def cls(self, gc: int, gr: int) -> int:
        if gc < 0 or gr < 0:
            return 0
        s = self.tiles.get(gc // CHUNKS * 64 + gr // CHUNKS)
        return (ord(s[gr % CHUNKS * CHUNKS + gc % CHUNKS]) - 97) % 4 if s else 0


def visual_centre(bounds, tiles, walk: Walk) -> tuple[float, float]:
    """The land's visual centre: the land sample farthest from water or the map's
    edge (a pole of inaccessibility, by a two-pass chamfer distance transform)."""
    c0, r0, c1, r1 = bounds
    S = CENTRE_SAMPLES
    w, h = (c1 - c0) * S, (r1 - r0) * S
    d = [0.0] * (w * h)
    for y in range(h):
        for x in range(w):
            col, row = c0 + (x + 0.5) / S, r0 + (y + 0.5) / S
            land = (math.floor(col) * 64 + math.floor(row) in tiles
                    and walk.cls(math.floor(col * CHUNKS), math.floor(row * CHUNKS)) != WATER)
            d[y * w + x] = math.inf if land else 0.0

    def relax(x, y, dx, dy, cost):
        nx, ny = x + dx, y + dy
        v = 0.0 if nx < 0 or ny < 0 or nx >= w or ny >= h else d[ny * w + nx]
        if v + cost < d[y * w + x]:
            d[y * w + x] = v + cost

    diag = math.sqrt(2)
    for y in range(h):
        for x in range(w):
            relax(x, y, -1, 0, 1); relax(x, y, 0, -1, 1); relax(x, y, -1, -1, diag); relax(x, y, 1, -1, diag)
    best, bx, by = -1.0, 0, 0
    for y in range(h - 1, -1, -1):
        for x in range(w - 1, -1, -1):
            relax(x, y, 1, 0, 1); relax(x, y, 0, 1, 1); relax(x, y, 1, 1, diag); relax(x, y, -1, 1, diag)
            if d[y * w + x] > best:
                best, bx, by = d[y * w + x], x, y
    return c0 + (bx + 0.5) / S, r0 + (by + 0.5) / S


def continents(uimaps) -> dict[int, int]:
    """inst -> its continent's uiMapID: the one hanging off a world map (atlas/UiMaps.lua)."""
    out = {}
    for mid in sorted(uimaps.keys()):
        m = uimaps[mid]
        inst = m[4] if m[5] is not None else None
        if inst is not None and m[2] == CONTINENT:
            p = uimaps[m[3]] if m[3] is not None else None
            if p is not None and p[2] == WORLD:
                out[inst] = mid
    return out


def tile_bounds(tiles) -> tuple[int, int, int, int] | None:
    if not tiles:
        return None
    c0, r0, c1, r1 = 64, 64, 0, 0
    for key in tiles:
        col, row = key // 64, key % 64
        c0, r0, c1, r1 = min(c0, col), min(r0, row), max(c1, col + 1), max(r1, row + 1)
    return (c0, r0, c1, r1) if c1 > c0 else None


def labels(inst, D, conts) -> list[dict]:
    """The inst's names in rank order: { text, col, row, tier, size?, areaID?, poiID? }."""
    out, subzones, land = [], [], 0
    b = D.Borders[inst]
    for l in array(b.labels if b is not None else None):
        area, col, row, weight, kind = l[1], l[2], l[3], l[4], l[5]
        if kind == 1:
            land += weight
        a = dict(text=D.Areas[area][1], col=col, row=row, tier="zone" if kind == 1 else "subzone",
                 areaID=area, size=math.sqrt(weight) / CHUNKS, score=weight)
        out.append(a)
        if kind == 2:
            subzones.append(a)

    def subzone(name, col, row):
        for s in subzones:
            if s["text"] == name and (s["col"] - col) ** 2 + (s["row"] - row) ** 2 < SAME_SPOT ** 2:
                return s

    pois = D.Places.pois
    for pid in sorted(pois.keys()):
        p = pois[pid]
        name, description, icon, importance, p_inst, col, row, area = (p[i] for i in range(1, 9))
        if p_inst != inst or description is not None:
            continue
        town = TOWN_ICON.get(icon)
        if town is None and icon in POI_ICON and importance >= 2:
            town = 0
        same = subzone(name, col, row)
        if town is not None:
            a = same or dict(text=name, col=col, row=row, areaID=area)
            a.update(tier="town", poiID=pid, score=importance * 10 + town, col=col, row=row)
            if not same:
                out.append(a)
        elif icon in POI_ICON and not same:
            out.append(dict(text=name, col=col, row=row, tier="poi", areaID=area, poiID=pid, score=0))

    m = D.Tiles.maps[inst]
    bounds = tile_bounds(m.tiles if m is not None else None)
    if inst in conts and bounds:
        col, row = visual_centre(bounds, set(m.tiles.keys()), Walk(D.Walk[inst]))
        out.append(dict(text=D.UiMaps[conts[inst]][1], col=col, row=row, tier="continent",
                        size=math.sqrt(land) / CHUNKS, score=0))
    out.sort(key=lambda a: (TIERS[a["tier"]], -a["score"], a["text"]))  # str order = UTF-8 byte order, as Lua's
    return out


def lua_row(a: dict) -> str:
    vals = [lua_str(a["text"]), num(a["col"]), num(a["row"]), lua_str(a["tier"]),
            num(a["size"], 4) if a.get("size") is not None else "nil",  # (size * 16)^2 rounds to the land chunks
            str(a["areaID"]) if a.get("areaID") is not None else "nil",
            str(a["poiID"]) if a.get("poiID") is not None else "nil"]
    while vals[-1] == "nil":
        vals.pop()
    return "{ " + ", ".join(vals) + " }"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--data", default=DATA, help="the Data folder read (default: the repo's)")
    parser.add_argument("-o", "--output", help="output file (default: stdout)")
    args = parser.parse_args()

    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    ns = lua.table()
    for name in INPUTS:
        load_data(lua, os.path.join(args.data, name + ".lua"), ns)
    D = ns.Data
    conts = continents(D.UiMaps)
    insts = set(D.Borders.keys()) | set(conts) | {p[5] for p in D.Places.pois.values()}

    out = open(args.output, "w", encoding="utf-8", newline="\n") if args.output else sys.stdout
    w = out.write
    w(f"-- GENERATED by tools/gen_labels.py from Data/{', '.join(INPUTS[:-1])} and {INPUTS[-1]} "
      f"({D.Tiles.product} {D.Tiles.version}). Do not edit.\n")
    w("-- [inst] = { { text, col, row, tier, size, areaID, poiID }, ... } in rank order (1 first)\n")
    w("--   tier: continent, zone, town, subzone, poi; size: the land named (continent, zone, subzone)\n")
    w("--   as the side of a square, in tiles\n")
    w(data_head("Labels"))
    w("D.Labels = {\n")
    for inst in sorted(insts):
        rows = labels(inst, D, conts)
        if not rows:
            continue
        m = D.Tiles.maps[inst]
        log("[%d] %s: %d labels" % (inst, m.name if m is not None else "?", len(rows)))
        w(f"  [{inst}] = {{" + (f" -- {m.name}" if m is not None else "") + "\n")
        w("".join(f"    {lua_row(a)},\n" for a in rows))
        w("  },\n")
    w("}\n")
    if out is not sys.stdout:
        out.close()


if __name__ == "__main__":
    main()
