#!/usr/bin/env python3
"""The one map's pictures (README.md), from a running demo's tiles (MAGICMAP_DEMO, default the hosted one):

  .venv/bin/python demo/bake_world.py world demo/sea/world.webp  # the whole map while its tiles load (after gen_sea.py --bake; again after OFFSET moves)
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
    """The whole map while its tiles load, as the page draws it: the far water's two swells, the land tiles, the ocean
    over them (sea/: tools/gen_sea.py --bake, read from beside out), and the AI repaints over that (ai/: tools/ai_map.py
    bake), so the repaired places look the same blurry as sharp."""
    P = 24  # px a tile; tiles.js draws it over [0, 0, the world's c1, r1]
    maps = json.loads(get("/api/maps"))
    _, _, W, H = maps["bounds"]
    here = os.path.dirname(os.path.abspath(out))
    sea = json.load(open(os.path.join(here, "sea.json")))
    swell = Image.open(os.path.join(here, sea["swell"]["file"])).convert("RGB")
    n = sea["swell"]["tiles"] * P
    swell = swell.resize((n, n), Image.LANCZOS)
    im = Image.new("RGB", (W * P, H * P))
    for x in range(0, W * P, n):
        for y in range(0, H * P, n):
            im.paste(swell, (x, y))
    if sea.get("over"):  # the broad swell at its alpha, as mapart.js draws it
        o = sea["over"]
        m = o["tiles"] * P
        broad = Image.open(os.path.join(here, o["file"])).convert("RGB").resize((m, m), Image.LANCZOS)
        layer = Image.new("RGB", im.size)
        for x in range(0, W * P, m):
            for y in range(0, H * P, m):
                layer.paste(broad, (x, y))
        im = Image.blend(im, layer, o["alpha"])
    land = [t for t in json.loads(get("/api/tiles"))["tiles"] if not t["sea"]]
    with ThreadPoolExecutor(4) as ex:
        for t, b in ex.map(lambda t: (t, get(f"/tiles/{t['inst']}/64/{t['src']}.webp")), land):
            if b:
                im.paste(Image.open(io.BytesIO(b)).convert("RGB").resize((P, P), Image.LANCZOS), ((t["key"] // 64) * P, (t["key"] % 64) * P))
    ocean = Image.open(os.path.join(here, sea["file"])).convert("RGBA").resize((sea["w"] * P, sea["h"] * P), Image.LANCZOS)
    im.paste(ocean, (sea["col"] * P, sea["row"] * P), ocean)
    ai = os.path.join(os.path.dirname(here), "ai")
    if os.path.isfile(os.path.join(ai, "ai.json")):
        at = {str(p["inst"]): p["offset"] for p in maps["parts"]}
        for inst, files in json.load(open(os.path.join(ai, "ai.json"))).items():
            for f in files if inst in at else ():
                pic = Image.open(os.path.join(ai, f["file"])).convert("RGBA")
                pic = pic.resize((max(1, round(f["w"] * P)), max(1, round(f["h"] * P))), Image.LANCZOS)
                im.paste(pic, (round((f["col"] + at[inst][0]) * P), round((f["row"] + at[inst][1]) * P)), pic)
    im.save(out, quality=80, method=6)


if __name__ == "__main__":
    {"world": world}[sys.argv[1]](sys.argv[2])
