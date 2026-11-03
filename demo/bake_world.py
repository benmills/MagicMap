#!/usr/bin/env python3
"""The combined map's pictures (see README.md): isle OUT, world OUT, feather SEA_DIR. Reads the tiles from the live demo."""
import io, json, os, sys, time, urllib.request
from concurrent.futures import ThreadPoolExecutor

import numpy as np
from PIL import Image

URL = "https://magic-map-outdoor.exe.xyz"


def get(path):
    for t in range(6):
        try:
            return urllib.request.urlopen(urllib.request.Request(URL + path, headers={"User-Agent": "mm"}), timeout=30).read()
        except Exception:
            time.sleep(2 ** t)  # (the host 503s in bursts)
    return None


def isle(out):
    P, c0, r0, w, h = 256, 25, 22, 9, 8
    im = np.zeros((h * P, w * P, 4), np.uint8)
    for t in json.loads(get("/api/tiles?inst=2991"))["tiles"]:
        c, r = t["key"] // 64, t["key"] % 64
        if t["sea"] or not (c0 <= c < c0 + w and r0 <= r < r0 + h):
            continue
        a = np.asarray(Image.open(io.BytesIO(get(f"/tiles/2991/{t['key']}.webp"))).convert("RGB").resize((P, P), Image.LANCZOS))
        k = np.clip((a.max(-1).astype(float) - 26) / 38, 0, 1)
        k = k * k * (3 - 2 * k)
        im[(r - r0) * P:(r - r0 + 1) * P, (c - c0) * P:(c - c0 + 1) * P] = np.dstack([a, k * 255]).astype(np.uint8)
    Image.fromarray(im).save(out, quality=88, method=6)


def world(out):
    P, W, H = 24, 92, 64
    im = Image.new("RGB", (W * P, H * P))
    land = [t for t in json.loads(get("/api/tiles?inst=1"))["tiles"] if not t["sea"]]
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
