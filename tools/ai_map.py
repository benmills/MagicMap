#!/usr/bin/env python3
"""The map's AI repaints, from tools/ai_regions.json (each: the place, its recipe, the picture chosen). Candidates live in demo/aifix/<name>/
(ai_fix.py); "pick" is which one a person chose.

  ai_map.py run [names] local INSTALL PRODUCT    candidates for those without any (--force on ai_fix's terms: delete the folder)
  ai_map.py bake                                 the picks -> demo/ai/: one soft-edged picture a place, and ai.json
  ai_map.py ship local INSTALL PRODUCT           the picks -> the addon: Textures/Repaint*.blp, cut on the tile grid, Data/Repaint.lua, and
                                                 tools/ai_tiles.json: what each place was painted over (FileDataID, hash)
  ai_map.py check local INSTALL PRODUCT          those tiles against the install: exits 1 naming the places whose tiles changed
  ai_map.py stamp local INSTALL PRODUCT          check, and only if clean, Data/Repaint.lua's build becomes the install's

The addon draws them only on the build in Data/Repaint.lua (ui/Repaint.lua), so a new game build leaves the raw map until check and stamp, plus a
release, say the art still fits. demo/ai/ is gitignored, as all of demo's baked layers; Textures/Repaint* are committed (the package is what's committed).
"""
from __future__ import annotations

import argparse
import glob
import hashlib
import json
import os
import re
import subprocess
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import ai_fix as af
from mmtools.blp import write_blp_dxt5
from mmtools.formats import wdt_maid
from mmtools.luaout import data_head
from mmtools.maps import MAP_DB2, read_maps
from mmtools.sources import Source, add_source_args, source_from_args

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REGIONS = os.path.join(ROOT, "tools", "ai_regions.json")
GUARD = os.path.join(ROOT, "tools", "ai_tiles.json")
DATA = os.path.join(ROOT, "Data", "Repaint.lua")
TILES = os.path.join(ROOT, "Data", "Tiles.lua")
N = 6


def regions() -> list[dict]:
    return json.load(open(REGIONS))


def run(names: list[str], source: list[str]) -> None:
    rs = regions()
    for r in rs:
        if names and r["name"] not in names:
            continue
        args = [sys.executable, os.path.join(ROOT, "tools", "ai_fix.py"), *source, "--map", str(r["map"]), "--box", ",".join(map(str, r["box"])),
                "--name", r["name"], "--recipes", r["recipe"], "--grow", "2", "--max-pixels", str(af.LIMIT_PIXELS), "--quality", "high", "-n", str(N)]
        for a in r.get("add", ()):
            args += ["--add", a]
        for k in r.get("keep", ()):
            args += ["--keep", k]
        if "context" in r:
            args += ["--context", str(r["context"])]
        if "reach" in r:
            args += ["--reach", str(r["reach"])]
        if r.get("over"):
            o = next(x for x in rs if x["name"] == r["over"])
            args += ["--over", f"{o['name']}:{o['recipe']}_{o['pick']}"]
        subprocess.Popen(args).wait() if len(names) == 1 else procs.append(subprocess.Popen(args))
    for p in procs:
        p.wait()


procs: list = []


def patch(r: dict) -> tuple[np.ndarray, list]:
    """A place's picture as it goes on the map (RGBA, the window's size), and its window (results.json's: tiles)."""
    d = os.path.join(ROOT, "demo", "aifix", r["name"])
    window = np.asarray(Image.open(os.path.join(d, "window.png")).convert("RGB"))
    edit = np.asarray(Image.open(os.path.join(d, "broken.png")).convert("L")) > 127
    picture = Image.open(os.path.join(d, f"{r['recipe']}_{r['pick']}.raw.png")).convert("RGB").resize(window.shape[1::-1], Image.LANCZOS)
    return af.patch_rgba(window, np.asarray(picture), edit, seed=r["pick"] + 1), json.load(open(os.path.join(d, "results.json")))["_window"]


def bake() -> None:
    out = os.path.join(ROOT, "demo", "ai")
    os.makedirs(out, exist_ok=True)
    index = {}
    for r in regions():
        if r["pick"] is None:
            print(f"{r['name']}: nothing picked")
            continue
        rgba, w0 = patch(r)
        ys, xs = np.nonzero(rgba[..., 3])
        x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
        file = f"{r['name']}.webp"
        Image.fromarray(rgba[y0:y1, x0:x1]).save(os.path.join(out, file), quality=92, alpha_quality=100, method=6)
        index.setdefault(str(r["map"]), []).append({"file": file, "col": w0[0] + int(x0) / af.TILE, "row": w0[1] + int(y0) / af.TILE,
                                                    "w": int(x1 - x0) / af.TILE, "h": int(y1 - y0) / af.TILE})
        print(f"{file}: {x1 - x0}x{y1 - y0}, {os.path.getsize(os.path.join(out, file)) / 1e6:.1f} MB")
    with open(os.path.join(out, "ai.json"), "w") as f:
        json.dump(index, f, separators=(",", ":"))


def cells(rgba: np.ndarray, w0: list) -> dict[tuple[int, int], np.ndarray]:
    """The picture cut on the game's tile grid: {(col, row): TILE x TILE x 4}, for the tiles it shows on."""
    x, y = w0[0] * af.TILE, w0[1] * af.TILE
    assert x == int(x) and y == int(y), f"a window off the pixel grid: {w0}"
    x, y = int(x), int(y)
    h, w = rgba.shape[:2]
    out = {}
    for col in range(x // af.TILE, (x + w - 1) // af.TILE + 1):
        for row in range(y // af.TILE, (y + h - 1) // af.TILE + 1):
            X, Y = col * af.TILE, row * af.TILE
            x0, x1, y0, y1 = max(X, x), min(X + af.TILE, x + w), max(Y, y), min(Y + af.TILE, y + h)
            part = rgba[y0 - y:y1 - y, x0 - x:x1 - x]
            if part[..., 3].any():
                cell = np.zeros((af.TILE, af.TILE, 4), np.uint8)
                cell[y0 - Y:y1 - Y, x0 - X:x1 - X] = part
                out[col, row] = cell
    return out


def wdt_tiles(src: Source, insts: set[int]) -> dict[int, dict[int, int]]:
    """Each map's tiles in this source: {inst: {col * 64 + row: FileDataID}}."""
    data = src.read(MAP_DB2)
    if data is None:
        raise SystemExit("Map.db2 not available")
    out = {}
    for m in read_maps(data):
        if m.inst in insts:
            wdt = src.read(m.wdt)
            if wdt is None or wdt[:4] != b"REVM":
                raise SystemExit(f"map {m.inst}: no WDT in this source")
            out[m.inst] = {k: t.minimap for k, t in wdt_maid(wdt).items() if t.minimap}
    return out


def tile_hash(src: Source, fdid: int) -> str | None:
    b = src.read(fdid)
    return b and hashlib.sha256(b).hexdigest()[:16]


def data_build() -> str:
    return re.search(r'version = "([^"]+)"', open(TILES, encoding="utf-8").read(1000)).group(1)


def ship(src: Source) -> None:
    """Refuses an install other than the build Data/Tiles.lua (and so the art) came from: its hashes would be another's."""
    if src.version != data_build():
        raise SystemExit(f"the install is {src.version}, Data/Tiles.lua {data_build()}: the guard must record the tiles the art was painted on")
    rs = [r for r in regions() if r["pick"] is not None]
    tiles = wdt_tiles(src, {r["map"] for r in rs})
    tex = os.path.join(ROOT, "Textures")
    for old in glob.glob(os.path.join(tex, "Repaint*")):
        os.remove(old)
    guard, maps, taken = {}, {}, {}  # taken: (map, col, row) -> the highest sublevel on it so far
    size = 0
    for r in rs:
        rgba, w0 = patch(r)
        got = cells(rgba, w0)
        # Later places lie over earlier ones they share a tile with (the demo's order: the JSON's): an ARTWORK sublevel, 7 at most.
        sub = max((taken.get((r["map"], *k), -1) for k in got), default=-1) + 1
        assert sub <= 7, f"{r['name']}: too many places on one tile"
        placed = {}
        for (col, row), cell in sorted(got.items()):
            name = f"Repaint{r['name']}_{col}_{row}"
            blp = write_blp_dxt5(cell)
            with open(os.path.join(tex, name + ".blp"), "wb") as f:
                f.write(blp)
            size += len(blp)
            maps.setdefault(r["map"], []).append((col, row, name, sub))
            taken[r["map"], col, row] = sub
            fdid = tiles[r["map"]].get(col * 64 + row)
            h = fdid and tile_hash(src, fdid)
            if fdid and not h:
                raise SystemExit(f"{r['name']}: tile {col},{row} (FileDataID {fdid}) can't be read")
            placed[f"{col},{row}"] = [fdid, h]
        guard[r["name"]] = {"map": r["map"], "tiles": placed}
        print(f"{r['name']}: {len(got)} textures, sublevel {sub}", flush=True)
    with open(GUARD, "w", encoding="utf-8", newline="\n") as f:
        json.dump({"product": src.product, "build": src.version, "places": guard}, f, indent=1)
        f.write("\n")
    with open(DATA, "w", encoding="utf-8", newline="\n") as f:
        f.write(f"-- GENERATED by tools/ai_map.py ship from the picks in tools/ai_regions.json, painted on {src.product} {src.version}. Do not edit.\n")
        f.write("-- build = the game build they're drawn on, the client's GetBuildInfo version.build (ai_map.py stamp moves it, once the tiles under them check out)\n")
        f.write("-- maps[inst] = { col, row, file (under the addon's folder, no extension: a whole tile, 512 px), sublevel (later places over earlier), ... }\n")
        f.write(data_head("Repaint"))
        f.write(f'D.Repaint = {{ build = "{src.version}", maps = {{\n')
        for inst, pieces in maps.items():
            f.write(f"  [{inst}] = {{\n")
            for col, row, name, sub in pieces:
                f.write(f'    {col}, {row}, "Textures\\\\{name}", {sub},\n')
            f.write("  },\n")
        f.write("} }\n")
    print(f"{sum(len(p) for p in maps.values())} textures, {size / 1e6:.1f} MB; build {src.version}")


def check(src: Source) -> list[str]:
    """The places whose tiles aren't what they were painted on (printed, with what changed); [] if none. Pixels decide: a tile
    that only has a new FileDataID has the same bytes, so the art still fits: a note, for Data/Tiles.lua's regeneration."""
    places = json.load(open(GUARD))["places"]
    now = wdt_tiles(src, {p["map"] for p in places.values()})
    bad = []
    for name, p in places.items():
        why = []
        for cell, (fdid, h) in p["tiles"].items():
            col, row = map(int, cell.split(","))
            f = now[p["map"]].get(col * 64 + row)
            if f == fdid and fdid is None:
                continue
            h2 = f and tile_hash(src, f)
            if h2 != h:
                why.append(f"{cell}: {fdid} -> {f}" + (", same id, new pixels" if f == fdid else ""))
            elif f != fdid:
                print(f"note: {name} {cell}: same bytes under a new FileDataID, {fdid} -> {f}: Data/Tiles.lua wants regenerating")
        if why:
            bad.append(name)
            print(f"{name}: changed: {'; '.join(why)}")
    print(f"{src.product} {src.version}: {len(places) - len(bad)} of {len(places)} places' tiles unchanged" + (f"; repaint: {', '.join(bad)}" if bad else ""))
    return bad


def stamp(src: Source) -> list[str]:
    bad = check(src)
    if bad:
        print("not stamped: Data/Repaint.lua left as it was", file=sys.stderr)
        return bad
    text = open(DATA, encoding="utf-8", newline="").read()
    new, n = re.subn(r'(D\.Repaint = \{ build = ")[^"]*(")', lambda m: m.group(1) + src.version + m.group(2), text)
    assert n == 1, "Data/Repaint.lua: no build to stamp"
    with open(DATA, "w", encoding="utf-8", newline="") as f:
        f.write(new)
    print(f"stamped: Data/Repaint.lua is good for {src.version}")
    return []


def source(argv: list[str]) -> Source:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    add_source_args(ap)
    return source_from_args(ap, ap.parse_args(argv))


if __name__ == "__main__":
    if sys.argv[1] == "bake":
        bake()
    elif sys.argv[1] == "ship":
        ship(source(sys.argv[2:]))
    elif sys.argv[1] == "check":
        sys.exit(1 if check(source(sys.argv[2:])) else 0)
    elif sys.argv[1] == "stamp":
        sys.exit(1 if stamp(source(sys.argv[2:])) else 0)
    else:
        i = sys.argv.index("local") if "local" in sys.argv else sys.argv.index("wago")
        run(sys.argv[2:i], sys.argv[i:])
