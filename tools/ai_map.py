#!/usr/bin/env python3
"""The map's AI repaints, from tools/ai_regions.json (each: the place, its recipe, the picture chosen). Candidates live in demo/aifix/<name>/
(ai_fix.py); "pick" is which one a person chose.

  ai_map.py run [names] local INSTALL PRODUCT    candidates for those without any (--force on ai_fix's terms: delete the folder)
  ai_map.py bake                                 the picks -> demo/ai/: one soft-edged picture a place, and ai.json

Blizzard's art is in them: gitignored, as all of demo's baked layers.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import ai_fix as af

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REGIONS = os.path.join(ROOT, "tools", "ai_regions.json")
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


def bake() -> None:
    out = os.path.join(ROOT, "demo", "ai")
    os.makedirs(out, exist_ok=True)
    index = {}
    for r in regions():
        if r["pick"] is None:
            print(f"{r['name']}: nothing picked")
            continue
        d = os.path.join(ROOT, "demo", "aifix", r["name"])
        window = np.asarray(Image.open(os.path.join(d, "window.png")).convert("RGB"))
        edit = np.asarray(Image.open(os.path.join(d, "broken.png")).convert("L")) > 127
        picture = Image.open(os.path.join(d, f"{r['recipe']}_{r['pick']}.raw.png")).convert("RGB").resize(window.shape[1::-1], Image.LANCZOS)
        rgba = af.patch_rgba(window, np.asarray(picture), edit, seed=r["pick"] + 1)
        ys, xs = np.nonzero(rgba[..., 3])
        x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
        w0 = json.load(open(os.path.join(d, "results.json")))["_window"]
        file = f"{r['name']}.webp"
        Image.fromarray(rgba[y0:y1, x0:x1]).save(os.path.join(out, file), quality=92, alpha_quality=100, method=6)
        index.setdefault(str(r["map"]), []).append({"file": file, "col": w0[0] + int(x0) / af.TILE, "row": w0[1] + int(y0) / af.TILE,
                                                    "w": int(x1 - x0) / af.TILE, "h": int(y1 - y0) / af.TILE})
        print(f"{file}: {x1 - x0}x{y1 - y0}, {os.path.getsize(os.path.join(out, file)) / 1e6:.1f} MB")
    with open(os.path.join(out, "ai.json"), "w") as f:
        json.dump(index, f, separators=(",", ":"))


if __name__ == "__main__":
    if sys.argv[1] == "bake":
        bake()
    else:
        i = sys.argv.index("local") if "local" in sys.argv else sys.argv.index("wago")
        run(sys.argv[2:i], sys.argv[i:])
