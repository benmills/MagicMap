#!/usr/bin/env python3
"""The one map's pictures (README.md), from a running demo's tiles (MAGICMAP_DEMO, default the hosted one):

  .venv/bin/python demo/bake_world.py world demo/sea/world.webp  # the whole map while its tiles load: again after OFFSET moves
"""
import io, json, os, sys, time, urllib.request
from concurrent.futures import ThreadPoolExecutor

from PIL import Image

URL = os.environ.get("MAGICMAP_DEMO", "https://magic-map-outdoor.exe.xyz").rstrip("/")


def get(path):
    for t in range(6):
        try:
            return urllib.request.urlopen(urllib.request.Request(URL + path, headers={"User-Agent": "mm"}), timeout=30).read()
        except Exception:
            time.sleep(2 ** t)  # (the host 503s in bursts)
    return None


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


if __name__ == "__main__":
    {"world": world}[sys.argv[1]](sys.argv[2])
