#!/usr/bin/env python3
"""Generate Data/WalkRegions.lua: which terrain chunks a walk can join up, and the hand-placed links that join
them where the terrain alone can't (tools/walk_links.json: tunnels, bridges, lifts; buildings aren't terrain).

From Data/Walk.lua (no game data needed): chunks are joined as Atlas.Walk.CanMove joins them (the 4 straight
ways: a diagonal needs one of them anyway) and by the links; each group of joined chunks is a region, numbered
by size (1: the map's biggest). A route between two regions doesn't exist: the search can say so at once, and go
to the nearest place in yours instead (atlas/Route.lua).

  python3 tools/gen_walk_regions.py -o Data/WalkRegions.lua

Each link in walk_links.json: {"inst", "name", "a": [col, row], "b": [col, row]} in tile coordinates, each end
moved to the nearest chunk you can stand on (as Atlas.Walk.Snap: within 4). Its cost is the walk between the ends
(at least the straight distance, so A*'s estimate stays below it).

Output is deterministic: the same Data/Walk.lua and links always give the same file.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import re
import sys

from mmtools.luaout import data_head

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
CHUNKS = 16
SNAP = 4
EAST, SOUTH = 4, 8


def read_walk(path: str) -> dict[int, dict[tuple[int, int], int]]:
    """{inst: {(gc, gr): value}} from Data/Walk.lua."""
    maps: dict[int, dict[tuple[int, int], int]] = {}
    inst = None
    with open(path, encoding="utf-8") as f:
        for line in f:
            m = re.match(r"\s*\[(\d+)\] = \{ --", line)
            if m:
                inst = int(m.group(1))
                maps[inst] = {}
                continue
            m = re.match(r'\s*\[(\d+)\] = "(.*)",', line)
            if m and inst is not None:
                key = int(m.group(1))
                cells = "".join(l * int(n or 1) for l, n in re.findall(r"([a-zA-Z])(\d*)", m.group(2)))
                col, row = key // 64, key % 64
                g = maps[inst]
                for i, ch in enumerate(cells):
                    g[(col * CHUNKS + i % CHUNKS, row * CHUNKS + i // CHUNKS)] = ord(ch) - 97
    return maps


def snap(g, gc: int, gr: int):
    """The nearest chunk you can stand on to (gc, gr), within SNAP (Atlas.Walk.Snap's order)."""
    if g.get((gc, gr), 0) & 3:
        return gc, gr
    for r in range(1, SNAP + 1):
        best = None
        for dc in range(-r, r + 1):
            for dr in range(-r, r + 1):
                if max(abs(dc), abs(dr)) == r and g.get((gc + dc, gr + dr), 0) & 3:
                    d = dc * dc + dr * dr
                    if best is None or d < best[0]:
                        best = (d, gc + dc, gr + dr)
        if best:
            return best[1], best[2]
    return None


def links_for(g, inst: int, links: list[dict]) -> list[tuple]:
    """(ac, ar, bc, br, cost, name) for the map's links, their ends snapped; a link with an end on nothing fails."""
    out = []
    for k in links:
        if k["inst"] != inst:
            continue
        ends = []
        for c, r in (k["a"], k["b"]):
            s = snap(g, math.floor(c * CHUNKS), math.floor(r * CHUNKS))
            if s is None:
                raise SystemExit(f"walk_links.json: {k['name']}: nowhere to stand near {c}, {r}")
            ends.append(s)
        (ac, ar), (bc, br) = ends
        cost = round(max(k.get("cost", 0), math.hypot(bc - ac, br - ar)), 2)
        out.append((ac, ar, bc, br, cost, k["name"]))
    return out


def regions(g, links) -> dict[tuple[int, int], int]:
    """{chunk: region} for every chunk you can stand on, regions numbered 1.. by size (then by first chunk)."""
    extra: dict[tuple[int, int], list] = {}
    for ac, ar, bc, br, _, _ in links:
        extra.setdefault((ac, ar), []).append((bc, br))
        extra.setdefault((bc, br), []).append((ac, ar))

    def open_(c):
        return g.get(c, 0) & 3

    def around(c):
        x, y = c
        v = g[c]
        if v & EAST and open_((x + 1, y)):
            yield (x + 1, y)
        if v & SOUTH and open_((x, y + 1)):
            yield (x, y + 1)
        if g.get((x - 1, y), 0) & EAST and open_((x - 1, y)):
            yield (x - 1, y)
        if g.get((x, y - 1), 0) & SOUTH and open_((x, y - 1)):
            yield (x, y - 1)
        yield from extra.get(c, ())

    seen: dict[tuple[int, int], int] = {}
    groups = []
    for c in sorted(g):
        if not open_(c) or c in seen:
            continue
        k = len(groups)
        seen[c] = k
        todo, members = [c], []
        while todo:
            p = todo.pop()
            members.append(p)
            for q in around(p):
                if q not in seen:
                    seen[q] = k
                    todo.append(q)
        groups.append((len(members), min(members), k))
    order = {k: i + 1 for i, (_, _, k) in enumerate(sorted(groups, key=lambda t: (-t[0], t[1])))}
    return {c: order[k] for c, k in seen.items()}


def encode_tile(reg, col: int, row: int) -> str:
    """The tile's 256 chunks (iy * 16 + ix) as region numbers (0: nowhere to stand), runs as "<n>x<count>": "1x200,0x3,57"."""
    vals = [reg.get((col * CHUNKS + i % CHUNKS, row * CHUNKS + i // CHUNKS), 0) for i in range(256)]
    out, i = [], 0
    while i < 256:
        j = i
        while j < 256 and vals[j] == vals[i]:
            j += 1
        out.append(f"{vals[i]}x{j - i}" if j - i > 1 else str(vals[i]))
        i = j
    return ",".join(out)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--walk", default=os.path.join(ROOT, "Data", "Walk.lua"))
    parser.add_argument("--links", default=os.path.join(TOOLS, "walk_links.json"))
    parser.add_argument("-o", "--output", help="output file (default: stdout)")
    ns = parser.parse_args()
    maps = read_walk(ns.walk)
    with open(ns.links, encoding="utf-8") as f:
        links = json.load(f)["links"]
    out = open(ns.output, "w", encoding="utf-8", newline="\n") if ns.output else sys.stdout
    w = out.write
    w("-- GENERATED by tools/gen_walk_regions.py from Data/Walk.lua and tools/walk_links.json. Do not edit.\n")
    w("-- WalkLinks[inst] = { { ac, ar, bc, br, cost, name }, ... }: chunks (global column, row) a walk joins where the\n")
    w("--   terrain doesn't (tunnels, bridges, lifts), both ways, cost in chunks walked.\n")
    w("-- WalkRegions[inst][col * 64 + row] = the tile's 16x16 chunks (iy * 16 + ix): the region each is in (1: the\n")
    w("--   map's biggest; 0: nowhere to stand), a number, or runs as \"<region>x<count>\" between commas.\n")
    w(data_head("WalkRegions"))
    w("D.WalkLinks = {\n")
    per = {inst: links_for(g, inst, links) for inst, g in sorted(maps.items())}
    for inst, ls in per.items():
        if ls:
            w(f"  [{inst}] = {{\n")
            for ac, ar, bc, br, cost, name in ls:
                w(f"    {{ {ac}, {ar}, {bc}, {br}, {cost:g}, {json.dumps(name)} }},\n")
            w("  },\n")
    w("}\n")
    w("D.WalkRegions = {\n")
    for inst, g in sorted(maps.items()):
        reg = regions(g, per[inst])
        w(f"  [{inst}] = {{\n")
        for key in sorted({(c // CHUNKS) * 64 + r // CHUNKS for c, r in g}):
            enc = encode_tile(reg, key // 64, key % 64)
            w(f"    [{key}] = {enc.split('x')[0]},\n" if enc.endswith("x256") else f"    [{key}] = \"{enc}\",\n")
        w("  },\n")
    w("}\n")
    if out is not sys.stdout:
        out.close()


if __name__ == "__main__":
    main()
