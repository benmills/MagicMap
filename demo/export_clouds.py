#!/usr/bin/env python3
"""Export the clouds for the web demo (demo/clouds.js): demo/clouds/clouds.json from Data/Clouds.lua
({ "<inst>": [col, row, width, turn, ...] }) and demo/clouds/puff.png, the game's puff, cut from its atlas
texture in the local install (Blizzard's art: demo/clouds/ is gitignored, as demo/tiles/ is).

  .venv/bin/python demo/export_clouds.py
  .venv/bin/python demo/export_clouds.py --wow "/Applications/World of Warcraft" --product wow_classic_beta
"""
from __future__ import annotations

import argparse
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

from lupa import lua51  # noqa: E402

from gen_clouds import blp_rgba  # noqa: E402
from mmtools.luaout import load_data  # noqa: E402
from mmtools.sources import open_source  # noqa: E402


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--wow", default="/Applications/World of Warcraft")
    ap.add_argument("--product", default="wow_classic_beta")
    ap.add_argument("-o", "--out", default=os.path.join(ROOT, "demo", "clouds"))
    ns = ap.parse_args()
    lua = lua51.LuaRuntime()
    C = load_data(lua, os.path.join(ROOT, "Data", "Clouds.lua")).Data.Clouds
    p = C.puff
    out = {str(inst): [round(float(v), 3) for v in C[inst].values()] for inst in (0, 1) if C[inst]}
    os.makedirs(ns.out, exist_ok=True)
    with open(os.path.join(ns.out, "clouds.json"), "w") as f:
        json.dump(out, f, separators=(",", ":"))
    src = open_source("local", ns.product, install=ns.wow)
    blp_rgba(src.read(p.file)).crop((p.l, p.t, p.r, p.b)).save(os.path.join(ns.out, "puff.png"))
    print(f"{ns.out}: " + ", ".join(f"[{k}] {len(v) // 4} clouds" for k, v in out.items()) + f"; puff {p.r - p.l}x{p.b - p.t}")


if __name__ == "__main__":
    main()
