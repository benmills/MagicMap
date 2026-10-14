#!/usr/bin/env python3
"""A web demo of the Atlas library on its own: Atlas runs in Lua (lupa) over
its bundled data; this serves its answers as JSON, and index.html only draws
them.

  .venv/bin/python demo/server.py [port]      # then open http://localhost:8000

  /api/maps                          Atlas.Maps, with Continent and Zones per inst
  /api/tiles?inst=                   TileBounds, and TileInfo per tile (tint, sea, water)
  /api/borders?inst=                 Borders lines, zone labels named by ZoneAt
  /api/at?inst=&col=&row=            TileToWorld, ZoneAt, Walk.Cell at that chunk
  /api/fit?uiMapID=&w=&h=            MapRect and Camera.Fit
  /api/walk?inst=&c0=&r0=&c1=&r1=    Walk.Cell over a chunk range, one hex digit each
"""
from __future__ import annotations

import gzip
import json
import os
import sys
import threading
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

DEMO = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(DEMO), "tools"))

from atlas_lua import load_atlas  # noqa: E402

L, Atlas = load_atlas()
lua_type = L.globals().type


def py(v):
    """A Lua value as JSON-ready Python: tables with keys 1..n become lists."""
    if lua_type(v) != "table":
        return v
    d = dict(v.items())
    if d and all(isinstance(k, int) for k in d) and sorted(d) == list(range(1, len(d) + 1)):
        return [py(d[i]) for i in range(1, len(d) + 1)]
    return {str(k): py(x) for k, x in d.items()}


def maps(q):
    out = []
    for m in py(Atlas.Maps()):
        inst = m["inst"]
        out.append(dict(m, uiMapID=Atlas.Continent(inst), zones=py(Atlas.Zones(inst)) or []))
    return out


def tiles(q):
    inst = int(q["inst"])
    out = []
    for key in Atlas.Tiles(inst).keys():
        t = Atlas.TileInfo(inst, key)
        out.append({"key": key, "tint": py(t.tint), "sea": t.sea, "water": t.water})
    return {"bounds": list(Atlas.TileBounds(inst)), "tiles": out}


def borders(q):
    inst = int(q["inst"])
    b = Atlas.Borders(inst)
    best = {}  # zone name -> its heaviest zone label
    for _, col, row, weight, kind in (py(x) for x in b.labels.values()):
        z = kind == 1 and Atlas.ZoneAt(inst, col, row)
        if z and weight > best.get(z.name, (0,))[0]:
            best[z.name] = (weight, col, row)
    labels = [{"name": n, "col": c, "row": r} for n, (_, c, r) in best.items()]
    # kind, then the points (skip areaA, areaB, fadeStart, fadeEnd)
    lines = [[x[0]] + x[5:] for x in (py(line) for line in b.lines.values())]
    return {"lines": lines, "labels": labels}


def at(q):
    inst, col, row = int(q["inst"]), float(q["col"]), float(q["row"])
    north, west = Atlas.TileToWorld(col, row)
    n = Atlas.Walk.CHUNKS
    gc, gr = int(col * n // 1), int(row * n // 1)
    cls, east, south = Atlas.Walk.Cell(inst, gc, gr)
    z = Atlas.ZoneAt(inst, col, row)
    return {"north": north, "west": west, "zone": py(z), "chunk": [gc, gr],
            "walk": {"class": cls, "east": east, "south": south}}


def fit(q):
    r = Atlas.MapRect(int(q["uiMapID"]))
    cx, cy, zoom = Atlas.Camera.Fit(r.col0, r.row0, r.col1, r.row1, float(q["w"]), float(q["h"]), None, 16, 2048)
    return {"inst": r.inst, "rect": py(r), "cam": {"cx": cx, "cy": cy, "zoom": zoom}}


def walk(q):
    inst, c0, r0, c1, r1 = (int(q[k]) for k in ("inst", "c0", "r0", "c1", "r1"))
    cell = Atlas.Walk.Cell
    rows = []
    for gr in range(r0, r1):
        s = []
        for gc in range(c0, c1):
            cls, east, south = cell(inst, gc, gr)
            s.append("%x" % (cls + 4 * east + 8 * south))
        rows.append("".join(s))
    return {"c0": c0, "r0": r0, "rows": rows}


API = {"maps": maps, "tiles": tiles, "borders": borders, "at": at, "fit": fit, "walk": walk}


# Tiles load many at once (a phone asks for dozens per pan), so requests run on
# threads; the one Lua runtime isn't thread-safe, so Atlas calls take turns.
atlas_lock = threading.Lock()


class Handler(SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"  # keep-alive: one connection for a screenful of tiles

    def __init__(self, *args, **kw):
        super().__init__(*args, directory=DEMO, **kw)

    def do_GET(self):
        u = urlparse(self.path)
        if u.path.startswith("/api/"):
            q = {k: v[0] for k, v in parse_qs(u.query).items()}
            with atlas_lock:
                body = json.dumps(API[u.path[5:]](q)).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            if len(body) > 1024 and "gzip" in self.headers.get("Accept-Encoding", ""):
                body = gzip.compress(body, 6)
                self.send_header("Content-Encoding", "gzip")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            super().do_GET()

    def send_response(self, code, message=None):
        self.code = code
        super().send_response(code, message)

    def end_headers(self):
        if self.path.startswith("/tiles/") and self.code == 200:
            self.send_header("Cache-Control", "public, max-age=86400")
        super().end_headers()

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    print(f"Atlas demo on http://localhost:{port}")
    ThreadingHTTPServer(("", port), Handler).serve_forever()
