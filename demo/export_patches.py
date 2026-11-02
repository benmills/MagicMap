#!/usr/bin/env python3
"""Export the sea tiles' water for the web demo (demo/mapart.js): demo/patches/patches.json from Data/Patches.lua
({ "<inst>": [[col, row, png], ...] }) and the pictures as png.

  .venv/bin/python demo/export_patches.py
"""
from __future__ import annotations

import argparse
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

from lupa import lua51  # noqa: E402
from PIL import Image  # noqa: E402

from mmtools.luaout import load_data  # noqa: E402


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-o", "--out", default=os.path.join(ROOT, "demo", "patches"))
    ns = ap.parse_args()
    P = load_data(lua51.LuaRuntime(), os.path.join(ROOT, "Data", "Patches.lua")).Data.Patches
    os.makedirs(ns.out, exist_ok=True)
    out = {}
    for inst, ps in P.items():
        for key, name in ps.items():
            png = name.split("\\")[-1] + ".png"
            Image.open(os.path.join(ROOT, name.replace("\\", "/") + ".tga")).save(os.path.join(ns.out, png))
            out.setdefault(str(inst), []).append([key // 64, key % 64, png])
    with open(os.path.join(ns.out, "patches.json"), "w") as f:
        json.dump(out, f, separators=(",", ":"))
    print(f"{ns.out}: " + ", ".join(f"[{k}] {len(v)}" for k, v in out.items()))


if __name__ == "__main__":
    main()
