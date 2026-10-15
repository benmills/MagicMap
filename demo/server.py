#!/usr/bin/env python3
"""A web demo of the Atlas library on its own: Atlas runs in Lua (lupa) over
its bundled data; this serves its answers as JSON, and index.html only draws
them.

  .venv/bin/python demo/server.py [port]      # then open http://localhost:8000

  /api/maps                          Atlas.Maps, with Continent and Zones per inst
  /api/tiles?inst=                   TileInfo per tile (tint, sea)
  /api/sea?inst=                     Sea: tint rect, far colour, gain, variants; SeaFeather's code per coast tile
  /api/borders?inst=                 Borders lines and far (zone borders, two levels of detail)
  /api/zone-outline?inst=&zone=      ZoneOutline: a zone's land as rings
  /api/labels?inst=                  Atlas.Labels: ranked name anchors (continent, zone, town, subzone, poi)
  /api/at?inst=&col=&row=            TileToWorld, ZoneAt, Walk.Cell at that chunk
  /api/fit?uiMapID=&w=&h=            MapRect and Camera.Fit
  /api/walk?inst=&c0=&r0=&c1=&r1=    Walk.Cell over a chunk range, one hex digit each
  /api/pins?inst=&c0=&r0=&c1=&r1=&zoom=&layers=
                                     FlightPoints, POIs, Dungeons, SpawnsIn (by NPC flags, quests,
                                     rank, object kind) in a box, thinned to one per layer per cell
  /api/npc|object|item|quest|flight|dungeon?id=
                                     one entity, its links named (QuestSources for a quest)
  /api/find?q=                       Atlas.Find over npc, quest, object, item
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
    if not d:
        return []
    if all(isinstance(k, int) for k in d) and sorted(d) == list(range(1, len(d) + 1)):
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
        out.append({"key": key, "tint": py(t.tint), "sea": t.sea})
    return {"tiles": out}


def sea(q):
    inst = int(q["inst"])
    m = Atlas.Sea(inst)
    if not m:
        return None
    coast = {}
    for key in Atlas.Tiles(inst).keys():
        path = Atlas.SeaFeather(inst, key)
        if path:
            coast[key] = int(path.rsplit("_", 1)[1][:-4])  # feather_<code>.tga
    return {"rect": py(m.rect), "far": py(m.far), "gain": m.gain, "variants": len(m.textures), "coast": coast}


def borders(q):
    # both levels of detail, { areaA, areaB, fadeStart, fadeEnd, x1, y1, ... } each; the page picks
    # by zoom as Atlas.BorderLines does
    b = Atlas.Borders(int(q["inst"]))
    return {"lines": py(b.lines), "far": py(b.far), "farZoom": Atlas.BORDER_FAR_ZOOM}


def zone_outline(q):
    return {"rings": py(Atlas.ZoneOutline(int(q["inst"]), int(q["zone"]))) or []}


def labels(q):
    # Atlas.Labels: { text, col, row, tier, rank, areaID?, poiID?, size? }, rank order
    return {"labels": py(Atlas.Labels(int(q["inst"])))}


def at(q):
    inst, col, row = int(q["inst"]), float(q["col"]), float(q["row"])
    north, west = Atlas.TileToWorld(col, row)
    n = Atlas.Walk.CHUNKS
    gc, gr = int(col * n // 1), int(row * n // 1)
    cls, east, south = Atlas.Walk.Cell(inst, gc, gr)
    z = Atlas.ZoneAt(inst, col, row)
    out = {"north": north, "west": west, "zone": py(z), "chunk": [gc, gr],
           "walk": {"class": cls, "east": east, "south": south}}
    id = Atlas.AreaAt(inst, col, row)
    if id:
        a = Atlas.Area(id)
        zone = Atlas.Area(a.zone)
        out["area"] = {"zone": zone.name, "subzone": a.parent and a.name,
                       "levels": list(Atlas.ZoneLevels(a.zone) or ()), "faction": a.faction or zone.faction}
    return out


def fit(q):
    w, h = float(q["w"]), float(q["h"])
    if "uiMapID" in q:
        r = Atlas.MapRect(int(q["uiMapID"]))
        cx, cy, zoom = Atlas.Camera.Fit(r.col0, r.row0, r.col1, r.row1, w, h, None, 16, 2048)
        return {"inst": r.inst, "rect": py(r), "cam": {"cx": cx, "cy": cy, "zoom": zoom}}
    # a box of spawns: at least ~300 yards across, so one spawn isn't zoomed in on all the way
    c0, r0, c1, r1 = (float(q[k]) for k in ("c0", "r0", "c1", "r1"))
    pc, pr = max(0.6 - (c1 - c0), 0) / 2, max(0.6 - (r1 - r0), 0) / 2
    cx, cy, zoom = Atlas.Camera.Fit(c0 - pc, r0 - pr, c1 + pc, r1 + pr, w, h, 0.8, 16, 1024)
    return {"cam": {"cx": cx, "cy": cy, "zoom": zoom}}


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


MAP_NAMES = {m["inst"]: m["name"] for m in py(Atlas.Maps())}
GET = {"npc": Atlas.Npc, "object": Atlas.Object, "item": Atlas.Item, "quest": Atlas.Quest}

# Which spawns each pin layer shows (Lua, so SpawnsIn's filter stays in Lua).
FILTERS = L.eval("""function(Atlas)
  local function Has(flags, bit) return math.floor(flags / bit) % 2 == 1 end
  local SERVICE = { 128, 256, 4096, 8, 8192, 16, 16384 } -- inn, bank, auction, flight, stable, trainer, repair
  return {
    service = function(id)
      local f = Atlas.Npc(id).flags
      for _, b in ipairs(SERVICE) do if Has(f, b) then return true end end
      return false
    end,
    questNpc = function(id) return #Atlas.Npc(id).questStarts > 0 end,
    questObject = function(id) return #Atlas.Object(id).questStarts > 0 end,
    rare = function(id) local r = Atlas.Npc(id).rank return r == 2 or r == 4 end,
    mail = function(id) return Atlas.Object(id).kind == "mailbox" end,
    herb = function(id) return Atlas.Object(id).kind == "herb" end,
    ore = function(id) return Atlas.Object(id).kind == "ore" end,
  }
end""")(Atlas)
SERVICES = ["innkeeper", "flightmaster", "banker", "auctioneer", "stablemaster", "trainer", "repair"]
SPAWN_LAYERS = {"service": [("npc", "service")], "quest": [("npc", "questNpc"), ("object", "questObject")],
                "rare": [("npc", "rare")], "mail": [("object", "mail")], "herb": [("object", "herb")],
                "ore": [("object", "ore")]}
PIN_CELL, PIN_CAP = 22, 400  # px per thinning cell; most pins per layer


def pins(q):
    inst, zoom = int(q["inst"]), float(q["zoom"])
    c0, r0, c1, r1 = (float(q[k]) for k in ("c0", "r0", "c1", "r1"))
    inside = lambda p: c0 <= p["col"] <= c1 and r0 <= p["row"] <= r1  # noqa: E731
    out, cell = [], PIN_CELL / zoom
    for layer in q["layers"].split(","):
        found = []
        if layer == "flight":
            found = [dict(p, kind="flight") for p in py(Atlas.FlightPoints(inst)) if inside(p)]
        elif layer == "poi":
            found = [dict(p, kind="poi") for p in py(Atlas.POIs(inst)) if inside(p)]
        elif layer == "dungeon":
            found = [{"kind": "dungeon", "id": d["id"], "name": d["name"], "col": d["col"], "row": d["row"],
                      "mark": d["kind"]} for d in py(Atlas.Dungeons(inst)) if inside(d)]
        else:
            for kind, f in SPAWN_LAYERS[layer]:
                for s in Atlas.SpawnsIn(kind, inst, c0, r0, c1, r1, FILTERS[f]).values():
                    found.append({"kind": kind, "id": s.id, "col": s.col, "row": s.row})
        if layer == "service":  # the most useful service wins a crowded cell
            for p in found:
                services = py(Atlas.Npc(p["id"]).services)
                p["mark"] = next(s for s in SERVICES if s in services)
            found.sort(key=lambda p: SERVICES.index(p["mark"]))
        seen = set()
        for p in found:
            key = (int(p["col"] // cell), int(p["row"] // cell))
            if key in seen:
                continue
            seen.add(key)
            pin = {"layer": layer, "kind": p["kind"], "id": p["id"], "col": p["col"], "row": p["row"],
                   "mark": p.get("mark")}
            if p["kind"] == "npc":  # its faction's glow, a rare's rank
                e = Atlas.Npc(p["id"])
                pin["faction"] = e.faction
                if layer == "rare":
                    pin["mark"] = e.rank
            elif p["kind"] != "object":  # a POI's card is drawn from its pin
                pin.update(name=p["name"], faction=p.get("faction"), description=p.get("description"), icon=p.get("icon"))
            out.append(pin)
            if len(seen) >= PIN_CAP:
                break
    return out


def ref(kind, id):
    e = GET[kind](id)
    r = {"kind": kind, "id": id, "name": e.name if e else f"#{id}"}
    if kind == "quest" and e:
        r["level"] = e.level
    return r


def refs(kind, ids):
    return [ref(kind, i) for i in ids.values()]


def where(e):
    """Spawns per inst as [col, row] pairs, and the dungeons it's inside."""
    spawns = []
    for inst, pts in sorted(e.spawns.items()):
        p = list(pts.values())
        spawns.append({"inst": inst, "map": MAP_NAMES.get(inst, f"#{inst}"),
                       "points": [p[i:i + 2] for i in range(0, len(p), 2)]})
    inside = [{"id": i, "name": (Atlas.Dungeon(i) or {"name": MAP_NAMES.get(i, f"#{i}")})["name"]}
              for i in e.instances.values()]
    return {"spawns": spawns, "instances": inside}


def npc(q):
    n = Atlas.Npc(int(q["id"]))
    return dict(where(n), kind="npc", id=n.id, name=n.name, subName=n.subName, minLevel=n.minLevel,
                maxLevel=n.maxLevel, rank=n.rank, faction=n.faction, services=py(n.services),
                questStarts=refs("quest", n.questStarts), questEnds=refs("quest", n.questEnds))


def object(q):
    o = Atlas.Object(int(q["id"]))
    return dict(where(o), kind="object", id=o.id, name=o.name, objectKind=o.kind,
                questStarts=refs("quest", o.questStarts), questEnds=refs("quest", o.questEnds))


def item(q):
    i = Atlas.Item(int(q["id"]))
    return {"kind": "item", "id": i.id, "name": i.name, "requiredLevel": i.requiredLevel,
            "startQuest": i.startQuest and ref("quest", i.startQuest),
            "npcDrops": refs("npc", i.npcDrops), "objectDrops": refs("object", i.objectDrops),
            "vendors": refs("npc", i.vendors), "itemDrops": refs("item", i.itemDrops)}


def quest(q):
    id = int(q["id"])
    x = Atlas.Quest(id)
    zone = x.zone and Atlas.Area(x.zone)
    objectives = [{"kind": o.kind, "id": o.id, "text": o.text, "name": o.name,
                   "sources": [ref(s.kind, s.id) for s in o.sources.values()]}
                  for o in Atlas.QuestSources(id).values()]
    t = x.triggerEnd
    return {"kind": "quest", "id": id, "name": x.name, "level": x.level, "requiredLevel": x.requiredLevel,
            "faction": x.faction, "zone": zone and zone.name, "objectivesText": py(x.objectivesText),
            "startedBy": refs("npc", x.startedBy.npcs) + refs("object", x.startedBy.objects)
            + refs("item", x.startedBy["items"]),
            "finishedBy": refs("npc", x.finishedBy.npcs) + refs("object", x.finishedBy.objects),
            "objectives": objectives, "triggerEnd": t and dict(where(t), text=t.text)}


FLIGHTS = {p["id"]: dict(p, inst=m) for m in MAP_NAMES for p in py(Atlas.FlightPoints(m))}


def flight(q):
    id = int(q["id"])
    f = FLIGHTS[id]
    area = f.get("areaID") and Atlas.Area(f["areaID"])
    dest = [dict(FLIGHTS[p.to], cost=p.cost, kind="flight") for p in Atlas.TaxiPaths().values() if p["from"] == id]
    dest.sort(key=lambda d: d["name"])
    return dict(f, kind="flight", area=area and area.name, destinations=dest)


def dungeon(q):
    d = py(Atlas.Dungeon(int(q["id"])))
    return dict(d, dungeonKind=d["kind"], kind="dungeon")


def find(q):
    out = []
    for kind in ("npc", "quest", "object", "item"):
        for id in Atlas.Find(kind, q["q"], 8).values():
            e, r = GET[kind](id), ref(kind, id)
            if kind == "npc":
                r["detail"] = " ".join(x for x in (e.subName and f"<{e.subName}>", e.minLevel and f"lv {e.minLevel}") if x)
            elif kind == "quest":
                r["detail"] = f"lv {e.level}" if e.level else ""
            elif kind == "object":
                r["detail"] = e.kind or ""
            out.append(r)
    return out


API = {"maps": maps, "tiles": tiles, "sea": sea, "borders": borders, "zone-outline": zone_outline, "labels": labels,
       "at": at, "fit": fit, "walk": walk, "pins": pins, "npc": npc, "object": object, "item": item, "quest": quest,
       "flight": flight, "dungeon": dungeon, "find": find}


# Tiles load many at once (a phone asks for dozens per pan), so requests run on
# threads; the one Lua runtime isn't thread-safe, so Atlas calls take turns.
atlas_lock = threading.Lock()


class Handler(SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"  # keep-alive: one connection for a screenful of tiles
    extensions_map = {**SimpleHTTPRequestHandler.extensions_map, ".webp": "image/webp"}  # older Pythons lack it

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
        else:  # the page and its scripts: always the current ones
            self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    print(f"Atlas demo on http://localhost:{port}")
    ThreadingHTTPServer(("", port), Handler).serve_forever()
