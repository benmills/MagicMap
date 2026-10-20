#!/usr/bin/env python3
"""Generate Data/Interiors.lua: the buildings with indoor minimap pictures, for the map indoors
(docs/decisions/0008-interiors.md; the prototype: docs/evidence/indoors/).

For every open-world map Data/Tiles.lua lists, every building (WMO) placed on it (obj0 MODF,
deduped by unique ID) whose rooms have pictures in WMOMinimapTexture: its placement and box, and
per room with pictures its floor (MOGI box zmin, zmax), subzone name (WMOAreaTable by WMO ID and
the room file's MOGP group ID), the rooms it has portals to (MOGP's MOPR refs), its floor mask
(4-yd cells in the building's own coordinates, from the pictures' alpha) and its pictures.

  python3 tools/gen_interiors.py [local "/Applications/World of Warcraft" wow_classic_beta] \\
      -o Data/Interiors.lua

The pictures' masks and the rooms' MOGP headers and floors are cached per build ($MAGICMAP_CACHE or ~/.cache/magicmap). Deterministic.
"""
from __future__ import annotations

import argparse
import io
import math
import os
import pickle
import re
import sys
from collections import defaultdict

from PIL import Image

from mmtools.db2 import read_wdc5
from mmtools.formats import adt_chunks, adt_modf, wdt_maid, wmo_group, wmo_root
from mmtools.log import log
from mmtools.luaout import data_head, lua_str, run_letters
from mmtools.maps import MAP_DB2, read_maps
from mmtools.sources import add_source_args, source_from_args

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_SOURCE = ["local", "/Applications/World of Warcraft", "wow_classic_beta"]
WMO_MINIMAP_TEXTURE_DB2 = 1323241  # rows: room, block x, 256 + block y, picture; the WMO ID in the relation
WMO_AREA_TABLE_DB2 = 1355528       # WMO ID, group ID -> name
TILE = 1600 / 3
CELL = 4                           # yards a floor-mask cell
BLOCK = 128                        # yards a picture block (256 px, 2 px a yard)
DEEP = 10                          # yards a room's floor below the terrain: underground
OVER = 3                           # cells two rooms' masks share: they overlap
CITY_AREA = 3000                   # square yards of floor: a city building, not a house
CAPITALS = (1453, 1454, 1455, 1456, 1457, 1458)  # Stormwind City, Orgrimmar, Ironforge, Thunder Bluff, Darnassus, Undercity


def open_world_insts(path: str) -> set[int]:
    """The maps Data/Tiles.lua lists that aren't instances."""
    with open(path, encoding="utf-8") as f:
        return {int(m.group(1)) for m in re.finditer(r"^  \[(\d+)\] = \{ name = .*$", f.read(), re.M)
                if "kind =" not in m.group(0)}


def city_rects(path: str) -> dict:
    """{uiMap: (name, inst, (col0, row0, col1, row1))} for the capitals, from Data/UiMaps.lua."""
    with open(path, encoding="utf-8") as f:
        text = f.read()
    out = {}
    for ui in CAPITALS:
        m = re.search(r'^  \[%d\] = \{ "([^"]*)", \d+, \d+, (\d+), ([-\d.]+), ([-\d.]+), ([-\d.]+), ([-\d.]+),' % ui, text, re.M)
        out[ui] = (m.group(1), int(m.group(2)), tuple(float(m.group(k)) for k in range(3, 7)))
    return out


def place(m, lx: float, ly: float):
    """The building's own (x, y) on the floor -> file space (x, z): noggit's, as the prototype."""
    t = math.radians(m.rot[1] - 90)
    s = m.scale / 1024
    return (m.pos[0] + s * (lx * math.cos(t) - ly * math.sin(t)),
            m.pos[2] + s * (-lx * math.sin(t) - ly * math.cos(t)))


def picture_cells(blp: bytes):
    """(w, h, cells): a picture's size and its alpha > 0 as 4-yd cells (8 px), rows from its
    bottom up (the picture's bottom-left corner is its block's corner), one byte a cell."""
    a = Image.open(io.BytesIO(blp)).convert("RGBA").getchannel("A")
    w, h = a.size
    a = a.transpose(Image.Transpose.FLIP_TOP_BOTTOM).point(lambda v: 255 if v else 0)
    pad = Image.new("L", (-(-w // 8) * 8, -(-h // 8) * 8), 0)
    pad.paste(a, (0, 0))
    r = pad.reduce(8)
    return w, h, r.width, bytes(1 if v else 0 for v in r.tobytes())


def fmt(v: float, nd: int) -> str:
    s = f"{v:.{nd}f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    add_source_args(parser)
    parser.add_argument("-o", "--output", help="output file (default: stdout)")
    parser.add_argument("--uimaps", default=os.path.join(ROOT, "Data", "UiMaps.lua"), help="the capitals' rects")
    parser.add_argument("--tiles", default=os.path.join(ROOT, "Data", "Tiles.lua"), help="tile set whose maps to cover")
    argv = sys.argv[1:]
    if not argv or argv[0] not in ("local", "wago"):
        argv = DEFAULT_SOURCE + argv
    ns = parser.parse_args(argv)
    src = source_from_args(parser, ns)

    cache_path = os.path.join(os.environ.get("MAGICMAP_CACHE") or os.path.expanduser("~/.cache/magicmap"),
                              f"interiors-{src.version}.pkl")
    cache = {}
    if os.path.exists(cache_path):
        with open(cache_path, "rb") as f:
            cache = pickle.load(f)

    pics_of = defaultdict(list)  # wmo ID -> (room, bx, by, fid)
    for r in read_wdc5(src.read(WMO_MINIMAP_TEXTURE_DB2), relation=True):
        pics_of[r[-1]].append((r[1], r[2], r[3] - 256, r[4]))
    area = {(r[3], r[5]): r[1] for r in read_wdc5(src.read(WMO_AREA_TABLE_DB2), string_fields=(0,)) if r[1]}

    covered = open_world_insts(ns.tiles)
    maps = sorted((m for m in read_maps(src.read(MAP_DB2)) if m.kind is None and m.inst in covered),
                  key=lambda m: m.inst)
    roots = {}  # fid -> WmoRoot, or None

    rects = city_rects(ns.uimaps)
    out = open(ns.output, "w", encoding="utf-8", newline="\n") if ns.output else sys.stdout
    w = out.write
    w(f"-- GENERATED by tools/gen_interiors.py from the {src.product} {src.version} ADTs, WMOs and"
      " WMOMinimapTexture. Do not edit.\n")
    w("-- [inst] = { tiles = { [col * 64 + row] = { building key... } }: the buildings whose box touches the tile;\n")
    w("--   buildings = { [key] = { c0, r0, c1, r1, packed } }: key the placement's unique ID, its box in tile space,\n")
    w("--   packed a Lua table literal (atlas/Interiors.lua decodes it): { fid, wmoID, col, row, yaw, k, rooms }:\n")
    w("--   the placement (col, row) and turn (radians) with k = mask cells a tile unit; rooms[group] =\n")
    w("--   { zmin, zmax, area, { linked group... }, x0, y0, cols, rows, mask, { fid, ox, oy, ux, uy, vx, vy, ... },\n")
    w("--   floor, underground, { overlapped group... } }: mask cols x rows 4-yd cells from (x0, y0) cells in the\n")
    w("--   building's own coordinates, rows upward, 'a' none 'b' floor, runs as the letter and a count; pictures in\n")
    w("--   tile units, pixel (u, v) at o + u*U + v*V; floor its real floor in world height; underground: that more\n")
    w("--   than 10 yd below the terrain at the mask's centre, or open to the sky with a third of its mask under the\n")
    w("--   building's floors > 10 yd higher; overlapped: its rooms sharing >= 3 mask cells;\n")
    w("--   cities = { [uiMap] = { { key... }, { [key] = { [room] = { key, room, ... } } } } }: a capital's buildings and,\n")
    w("--   per room, the other buildings' rooms it shares >= 3 4-yd cells with (tile space)\n")
    w(data_head("Interiors"))
    w("D.Interiors = {\n")
    totals = [0, 0, 0]
    for mi in maps:
        wdt = src.read(mi.wdt)
        if wdt is None:
            continue
        maid = wdt_maid(wdt)
        terrain = {}  # tile key -> {(ix, iy): (z, heights)}

        def ground(x, z):
            """The terrain's height at file-space (x, z): MCVT's outer vertices, bilinear; None: no tile."""
            col, row = int(x // TILE), int(z // TILE)
            key = col * 64 + row
            if key not in terrain:
                t = maid.get(key)
                b = t and t.root_adt and src.read(t.root_adt)
                terrain[key] = {(c.ix, c.iy): (c.z, c.heights) for c in adt_chunks(b)} if b else {}
            fx, fz = (x / TILE - col) * 16, (z / TILE - row) * 16
            ch = terrain[key].get((int(fx), int(fz)))
            if not ch or ch[1] is None:
                return ch and ch[0]
            qx, qy = min(int((fx - int(fx)) * 8), 7), min(int((fz - int(fz)) * 8), 7)
            u, v = (fx - int(fx)) * 8 - qx, (fz - int(fz)) * 8 - qy
            h = ch[1]
            a, b = h[qy * 17 + qx], h[qy * 17 + qx + 1]
            c, d = h[(qy + 1) * 17 + qx], h[(qy + 1) * 17 + qx + 1]
            return ch[0] + (a * (1 - u) + b * u) * (1 - v) + (c * (1 - u) + d * u) * v

        placed = {}
        for key, t in sorted(maid.items()):
            b = t.obj0 and src.read(t.obj0)
            for m in adt_modf(b) if b else ():
                placed.setdefault(m.uid, m)
        buildings, tiles = {}, defaultdict(list)
        info = {}  # uid -> (box, {group: (underground, its floor's 4-yd cells in tile space)}, floor area)
        for uid, m in sorted(placed.items()):
            if m.fid not in roots:
                b = src.read(m.fid)
                roots[m.fid] = wmo_root(b) if b and b[:4] == b"REVM" else None
            root = roots[m.fid]
            if root is None or root.wmo_id not in pics_of:
                continue
            s = m.scale / 1024
            by_room = defaultdict(list)
            for room, bx, by, fid in pics_of[root.wmo_id]:
                if room < len(root.groups):
                    by_room[room].append((bx, by, fid))
            rooms, own, under, sq = {}, {}, {}, 0  # own: group -> its floor's cells in the building's frame
            for gi in sorted(by_room):
                g = root.groups[gi]
                gf = root.group_fids[gi]
                if ("room", gf) not in cache:
                    gb = src.read(gf)
                    cache["room", gf] = wmo_group(gb) if gb else None
                grp = cache["room", gf]
                cols = math.ceil((g.mx[0] - g.mn[0]) / CELL)
                nrows = math.ceil((g.mx[1] - g.mn[1]) / CELL)
                grid = bytearray(cols * nrows)
                pics = []
                for bx, by, fid in sorted(by_room[gi]):
                    if fid not in cache:
                        cache[fid] = picture_cells(src.read(fid))
                    pw, ph, rw, cells = cache[fid]
                    for i, v in enumerate(cells):
                        c, r = BLOCK // CELL * bx + i % rw, BLOCK // CELL * by + i // rw
                        if v and 0 <= c < cols and 0 <= r < nrows:
                            grid[r * cols + c] = 1
                    x0, y0 = g.mn[0] + BLOCK * bx, g.mn[1] + BLOCK * by
                    o, u, v = (place(m, x0 + px / 2, y0 + (ph - py) / 2) for px, py in ((0, 0), (pw, 0), (0, ph)))
                    pics.append("%d,%s,%s,%s,%s,%s,%s" % (
                        fid, fmt(o[0] / TILE, 5), fmt(o[1] / TILE, 5), fmt((u[0] - o[0]) / TILE, 5),
                        fmt((u[1] - o[1]) / TILE, 5), fmt((v[0] - o[0]) / TILE, 5), fmt((v[1] - o[1]) / TILE, 5)))
                links = []
                if grp:
                    links = sorted({root.portal_refs[k][1] for k in range(grp.portal_start, grp.portal_start + grp.portal_count)
                                    if root.portal_refs[k][1] in by_room} - {gi})
                name = area.get((root.wmo_id, grp.group_id)) if grp else None
                mask = run_letters(["b" if v else "a" for v in grid])
                # The floor cells' centres in the building's own yards; the real floor in world height (yaw only).
                x0c, y0c = g.mn[0] / CELL, g.mn[1] / CELL
                pts = [((x0c + i % cols + 0.5) * CELL, (y0c + i // cols + 0.5) * CELL) for i, v in enumerate(grid) if v]
                own[gi] = {(math.floor(x / CELL), math.floor(y / CELL)) for x, y in pts}
                sq += len(pts) * CELL * CELL * s * s
                floor = m.pos[1] + s * (grp.floor if grp and grp.floor is not None else g.mn[2])
                cx, cy = ((sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts)) if pts else
                          ((g.mn[0] + g.mx[0]) / 2, (g.mn[1] + g.mx[1]) / 2))
                top = ground(*place(m, cx, cy))
                under[gi] = (top is not None and top - floor > DEEP,
                             {tuple(math.floor(q / CELL) for q in place(m, x, y)) for x, y in pts})
                rooms[gi] = (floor, g.flags & 0x40, "[%d]={%s,%s,%s,{%s},%s,%s,%d,%d,%s,{%s},%s," % (
                    gi, fmt(g.mn[2], 1), fmt(g.mx[2], 1), lua_str(name) if name else "nil", ",".join(map(str, links)),
                    fmt(g.mn[0] / CELL, 3), fmt(g.mn[1] / CELL, 3), cols, nrows, lua_str(mask), ",".join(pics), fmt(floor, 1)))
                totals[1] += 1
                totals[2] += len(pics)
            # Open to the sky and a third of its floor under the building's floors > 10 yd higher: underground too
            # (a city WMO's terrain is a placeholder under it: Orgrimmar's Cleft of Shadow under its streets).
            for gi, (floor, sky, _) in rooms.items():
                hid = set().union(*(own[gi] & own[gj] for gj in rooms if rooms[gj][0] > floor + DEEP))
                if sky and own[gi] and 3 * len(hid) >= len(own[gi]):
                    under[gi] = (True, under[gi][1])
            rooms = {gi: "%s%s," % (r[2], "true" if under[gi][0] else "false") for gi, r in rooms.items()}
            over = {gi: [gj for gj in own if gj != gi and len(own[gi] & own[gj]) >= OVER] for gi in own}
            packed = "{%d,%d,%s,%s,%s,%s,{%s}}" % (
                m.fid, root.wmo_id, fmt(m.pos[0] / TILE, 6), fmt(m.pos[2] / TILE, 6),
                fmt(math.radians(m.rot[1] - 90), 6), fmt(TILE / (s * CELL), 4),
                ",".join("%s{%s}}" % (rooms[gi], ",".join(map(str, over[gi]))) for gi in sorted(rooms)))
            c0, r0, c1, r1 = m.mn[0] / TILE, m.mn[2] / TILE, m.mx[0] / TILE, m.mx[2] / TILE
            buildings[uid] = "{%s,%s,%s,%s,%s}" % (fmt(c0, 4), fmt(r0, 4), fmt(c1, 4), fmt(r1, 4), lua_str(packed))
            info[uid] = ((c0, r0, c1, r1), under, sq)
            for col in range(math.floor(c0), math.floor(c1) + 1):
                for row in range(math.floor(r0), math.floor(r1) + 1):
                    tiles[col * 64 + row].append(uid)
        if not buildings:
            continue
        totals[0] += len(buildings)
        log(f"{src.product} {src.version}: [{mi.inst}] {mi.name}: {len(buildings)} buildings")
        w(f"  [{mi.inst}] = {{ -- {mi.name}\n    tiles = {{\n")
        for key in sorted(tiles):
            w(f"      [{key}] = {{ {', '.join(map(str, tiles[key]))} }},\n")
        w("    },\n    buildings = {\n")
        for uid in sorted(buildings):
            w(f"      [{uid}] = {buildings[uid]},\n")
        w("    },\n")
        cities = [(ui, name, rect) for ui, (name, inst, rect) in sorted(rects.items()) if inst == mi.inst]
        w("    cities = {\n" if cities else "")
        for ui, name, (x0, y0, x1, y1) in cities:
            # The capital's buildings: their box over its rect, and underground or not a house.
            keys = [uid for uid, ((c0, r0, c1, r1), under, sq) in sorted(info.items())
                    if c0 <= x1 and c1 >= x0 and r0 <= y1 and r1 >= y0 and (sq >= CITY_AREA or any(d for d, _ in under.values()))]
            at = defaultdict(list)  # tile-space cell -> (key, room)...
            for uid in keys:
                for gi, (_, cells) in info[uid][1].items():
                    for c in cells:
                        at[c].append((uid, gi))
            shared = defaultdict(lambda: defaultdict(int))  # (key, room) -> (key, room) -> cells
            for here in at.values():
                for a in here:
                    for b in here:
                        if a[0] != b[0]:
                            shared[a][b] += 1
            over = defaultdict(dict)
            for a, bs in sorted(shared.items()):
                hit = sorted(b for b, n in bs.items() if n >= OVER)
                if hit:
                    over[a[0]][a[1]] = hit
            log(f"  {ui} {name}: {len(keys)} buildings: " + ", ".join(
                "%d (fid %d, %d rooms, %d sq yd%s)" % (k, placed[k].fid, len(info[k][1]), info[k][2],
                                                      ", underground" if any(d for d, _ in info[k][1].values()) else "")
                for k in keys))
            w(f"      [{ui}] = {{ -- {name}\n        {{ {', '.join(map(str, keys))} }},\n        {{\n")
            for uid in sorted(over):
                w("          [%d] = { %s },\n" % (uid, ", ".join(
                    "[%d] = { %s }" % (gi, ", ".join("%d, %d" % b for b in bs)) for gi, bs in sorted(over[uid].items()))))
            w("        },\n      },\n")
        w("    },\n" if cities else "")
        w("  },\n")
    w("}\n")
    if out is not sys.stdout:
        out.close()
        log("%d buildings, %d rooms, %d pictures, %d KB" % (*totals, os.path.getsize(ns.output) // 1024))
    os.makedirs(os.path.dirname(cache_path), exist_ok=True)
    with open(cache_path + ".tmp", "wb") as f:
        pickle.dump(cache, f)
    os.replace(cache_path + ".tmp", cache_path)


if __name__ == "__main__":
    main()
