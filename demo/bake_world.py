#!/usr/bin/env python3
"""The one map's pictures (README.md), from a running demo's tiles (MAGICMAP_DEMO, default the hosted one):

  .venv/bin/python demo/bake_world.py isle demo/sea/isle.webp    # Zephras Isle over the ocean, its near-black gone
  .venv/bin/python demo/bake_world.py world demo/sea/world.webp  # the whole map while its tiles load: again after OFFSET moves
  .venv/bin/python demo/bake_world.py feather demo/sea           # the ocean pictures' edges into deep water: once after each gen_sea.py --bake
"""
import io, json, os, sys, time, urllib.request
from concurrent.futures import ThreadPoolExecutor

import numpy as np
from PIL import Image

URL = os.environ.get("MAGICMAP_DEMO", "https://magic-map-outdoor.exe.xyz").rstrip("/")


def get(path):
    for t in range(6):
        try:
            return urllib.request.urlopen(urllib.request.Request(URL + path, headers={"User-Agent": "mm"}), timeout=30).read()
        except Exception:
            time.sleep(2 ** t)  # (the host 503s in bursts)
    return None


def isle(out):
    P = 256
    c0, r0, c1, r1 = next(p for p in json.loads(get("/api/maps"))["parts"] if p["inst"] == 2991)["bounds"]  # (mapart.js draws it there)
    w, h = c1 - c0, r1 - r0
    im = np.zeros((h * P, w * P, 4), np.uint8)
    for t in json.loads(get("/api/tiles"))["tiles"]:
        c, r = t["key"] // 64, t["key"] % 64
        if t["inst"] != 2991 or t["sea"]:
            continue
        a = np.asarray(Image.open(io.BytesIO(get(f"/tiles/2991/{t['src']}.webp"))).convert("RGB").resize((P, P), Image.LANCZOS))
        k = np.clip((a.max(-1).astype(float) - 26) / 38, 0, 1)
        k = k * k * (3 - 2 * k)
        im[(r - r0) * P:(r - r0 + 1) * P, (c - c0) * P:(c - c0 + 1) * P] = np.dstack([a, k * 255]).astype(np.uint8)
    Image.fromarray(im).save(out, quality=88, method=6)


def world(out):
    P = 24  # px a tile; tiles.js draws it over [0, 0, the world's c1, r1]
    _, _, W, H = json.loads(get("/api/maps"))["bounds"]
    im = Image.new("RGB", (W * P, H * P))
    land = [t for t in json.loads(get("/api/tiles"))["tiles"] if not t["sea"]]
    with ThreadPoolExecutor(4) as ex:
        for t, b in ex.map(lambda t: (t, get(f"/tiles/{t['inst']}/64/{t['src']}.webp")), land):
            if b:
                im.paste(Image.open(io.BytesIO(b)).convert("RGB").resize((P, P), Image.LANCZOS), ((t["key"] // 64) * P, (t["key"] % 64) * P))
    im.save(out, quality=80, method=6)


def feather(sea):
    d = json.load(open(os.path.join(sea, "sea.json")))
    deep = np.array(d["deep"], float)
    for o in d["maps"].values():
        path = os.path.join(sea, o["file"])
        a = np.asarray(Image.open(path).convert("RGBA")).astype(float)
        h, w = a.shape[:2]
        e = np.minimum.outer(np.minimum(np.arange(h), h - 1 - np.arange(h)), np.minimum(np.arange(w), w - 1 - np.arange(w))) / (w / o["w"])
        t = np.clip(e / 3, 0, 1)  # three tiles in
        t = (t * t * (3 - 2 * t))[..., None]
        a[..., :3] = a[..., :3] * t + deep * (1 - t)
        Image.fromarray(a.astype(np.uint8)).save(path, quality=90, alpha_quality=100, method=6)


if __name__ == "__main__":
    {"isle": isle, "world": world, "feather": feather}[sys.argv[1]](sys.argv[2])
