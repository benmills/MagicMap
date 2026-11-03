#!/usr/bin/env python3
"""A web demo of the Atlas library on its own: Atlas runs in Lua (lupa) over
its bundled data; this serves its answers as JSON, and index.html only draws
them. One map: Kalimdor, the Eastern Kingdoms and Zephras Isle placed on a world
(OFFSET); requests and replies speak its tile coordinates. See README.md.

  .venv/bin/python demo/server.py [port]      # then open http://localhost:8000

  /api/maps                          the world: its bounds, zones, and parts (each map's inst, offset, bounds)
  /api/tiles                         per tile: its world key, its map's inst and key (src), whether it's open sea
  /api/labels                        Atlas.Labels: ranked name anchors (continent, zone, town, subzone, poi)
  /api/at?col=&row=                  TileToWorld, ZoneAt, Walk.Cell at that chunk
  /api/fit?uiMapID=&w=&h=            MapRect and Camera.Fit (or c0=&r0=&c1=&r1=: a box)
  /api/walk?c0=&r0=&c1=&r1=          Walk.Cell over a chunk range, one hex digit each
  /api/pins?c0=&r0=&c1=&r1=&zoom=&layers=
                                     FlightPoints, POIs, Dungeons, SpawnsIn (by NPC flags, quests,
                                     rank, object kind) in a box; groups=1 returns compact groups and omitted count
  /api/npc|object|item|quest|flight|dungeon?id=
                                     one entity, its links named (QuestSources for a quest)
  /api/find?q=                       Atlas.Find over npc, quest, object, item
"""
from __future__ import annotations

import gzip
import io
import json
import math
import os
import sys
import threading
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

DEMO = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(DEMO), "tools"))

from atlas_lua import load_atlas  # noqa: E402
from lupa.lua51 import LuaError  # noqa: E402
from asset_manifest import inventory  # noqa: E402
import review_api  # noqa: E402  the map review (/api/lint, /api/review)
from static_assets import COMPRESSIBLE, accepts_gzip, compressed_file  # noqa: E402

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


WORLD, WORLD_NAME = 1, "Azeroth"
# Each map's place on the world, in tiles (world = map + offset). The Eastern Kingdoms' is from Blizzard's own world map
# (UiMap 947, Azeroth: UiMapAssignment places both continents on it at one scale): (+44.9..45.0, -9.3..-9.1) from
# Kalimdor across the Eastern Kingdoms, rounded. Zephras Isle has no place there: ours, between them near the bottom.
# Rows stay in 0..63, so a world tile's key still reads col * 64 + row. The page reads these from /api/maps.
OFFSET = {1: (0, 0), 0: (45, -9), 2991: (28, 24)}
BOUNDS = {i: tuple(v + OFFSET[i][k % 2] for k, v in enumerate(Atlas.TileBounds(i))) for i in OFFSET}  # world, c0 r0 c1 r1
CITIES = {"Stormwind City": "Stormwind", "Stormwind": "Stormwind", "Ironforge": "Ironforge", "The Undercity": "Undercity",
          "Orgrimmar": "Orgrimmar", "Thunder Bluff": "Thunder Bluff", "Darnassus": "Darnassus"}
CITIES_AS_TOWNS = {"Ironforge", "The Undercity"}
CITY_SIZE = 1.5  # (a zone label's: the side of the area, in tiles)
assert all(0 <= b[1] and b[3] <= 64 for b in BOUNDS.values())


def to_world(inst, col, row):
    dx, dy = OFFSET[inst]
    return col + dx, row + dy


def to_real(col, row):
    """The real map under a world position, and the position on it: the isle's box, else the nearer continent's."""
    c0, r0, c1, r1 = BOUNDS[2991]
    if c0 <= col < c1 and r0 <= row < r1:
        inst = 2991
    else:
        inst = 1 if col < (BOUNDS[1][2] + BOUNDS[0][0]) / 2 else 0
    dx, dy = OFFSET[inst]
    return inst, col - dx, row - dy


def world_key(inst, key):
    dx, dy = OFFSET[inst]
    return (key // 64 + dx) * 64 + key % 64 + dy


def on_world(p):
    """A thing with an inst, col and row, moved onto the world if its map is on it."""
    if p.get("inst") in OFFSET:
        if "col" in p:
            p["col"], p["row"] = to_world(p["inst"], p["col"], p["row"])
        p["inst"] = WORLD
    return p


def real_maps():
    return [dict(m, uiMapID=Atlas.Continent(m["inst"]), zones=py(Atlas.Zones(m["inst"])) or []) for m in py(Atlas.Maps())]


def real_at(inst, col, row):
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
        if r.inst not in OFFSET:
            raise ValueError("not on the world")
        cx, cy, zoom = Atlas.Camera.Fit(r.col0, r.row0, r.col1, r.row1, w, h, None, 16, 2048)
        cx, cy = to_world(r.inst, cx, cy)
        return {"cam": {"cx": cx, "cy": cy, "zoom": zoom}}
    # a box of spawns: at least 0.6 tiles (~320 yards) across, so one spawn isn't zoomed in on all the way
    c0, r0, c1, r1 = (float(q[k]) for k in ("c0", "r0", "c1", "r1"))
    cx, cy, zoom = Atlas.Camera.Fit(c0, r0, c1, r1, w, h, 0.8, 16, 1024, 0.6)
    return {"cam": {"cx": cx, "cy": cy, "zoom": zoom}}


def walk(q):
    c0, r0, c1, r1 = (int(q[k]) for k in ("c0", "r0", "c1", "r1"))
    n = Atlas.Walk.CHUNKS

    def cell(gc, gr):  # (a world chunk: its map's)
        inst, col, row = to_real(gc / n, gr / n)
        dx, dy = OFFSET[inst]
        return Atlas.Walk.Cell(inst, gc - dx * n, gr - dy * n)
    if c1 < c0 or r1 < r0 or (c1-c0)*(r1-r0) > 40000:
        raise ValueError("walk grid is limited to 40000 cells")
    rows = []
    for gr in range(r0, r1):
        s = []
        for gc in range(c0, c1):
            cls, east, south = cell(gc, gr)
            s.append("%x" % (cls + 4 * east + 8 * south))
        rows.append("".join(s))
    return {"c0": c0, "r0": r0, "rows": rows}


MAP_NAMES = {m["inst"]: m["name"] for m in py(Atlas.Maps())}
GET = {"npc": Atlas.Npc, "object": Atlas.Object, "item": Atlas.Item, "quest": Atlas.Quest}

# Which spawns each pin layer shows (Lua, so SpawnsIn's filter stays in Lua).
FILTERS = L.eval("""function(Atlas)
  local function Has(flags, bit) return math.floor(flags / bit) % 2 == 1 end
  local SERVICE = { 128, 256, 4096, 8192, 2048, 16, 16384 } -- model/Services.lua; flights have their own layer
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
SERVICES = ["innkeeper", "banker", "auctioneer", "stablemaster", "battlemaster", "trainer", "repair"]
SPAWN_LAYERS = {"service": [("npc", "service")], "quest": [("npc", "questNpc"), ("object", "questObject")],
                "rare": [("npc", "rare")], "mail": [("object", "mail")], "herb": [("object", "herb")],
                "ore": [("object", "ore")]}
PIN_CAP = 1200  # members per layer; explicit omitted count for the grouped browser response
GROUP_RANGE, GROUP_REACH = 24, 3  # ui/Cluster.lua; grouping runs only on settled requests


def group_pins(found, zoom):
    """Greedy neighbouring pins, bounded to three ranges from a stable seed.

    Tile buckets avoid an all-pairs pass. Removing a claimed member from its
    bucket also keeps a dense stack of identical positions cheap to collect.
    Returned membership remains unchanged while the browser pans or animates.
    """
    cell = GROUP_RANGE / zoom
    buckets = {}
    found = sorted(found, key=lambda p: p["key"])
    for i, p in enumerate(found):
        key = (math.floor(p["col"] / cell), math.floor(p["row"] / cell))
        buckets.setdefault(key, {})[i] = p
    taken, out = set(), []
    for i, seed in enumerate(found):
        if i in taken:
            continue
        taken.add(i)
        key = (math.floor(seed["col"] / cell), math.floor(seed["row"] / cell))
        buckets[key].pop(i)
        members = [seed]
        for p in members:
            cx, cy = math.floor(p["col"] / cell), math.floor(p["row"] / cell)
            for dc in (-1, 0, 1):
                for dr in (-1, 0, 1):
                    bucket = buckets.get((cx + dc, cy + dr), {})
                    for j, q in list(bucket.items()):
                        if ((q["col"] - p["col"]) ** 2 + (q["row"] - p["row"]) ** 2 < cell ** 2
                            and (q["col"] - seed["col"]) ** 2 + (q["row"] - seed["row"]) ** 2 < (cell * GROUP_REACH) ** 2):
                            taken.add(j)
                            del bucket[j]
                            members.append(q)
        if len(members) == 1:
            out.append(seed)
        else:
            out.append({"kind": "group", "key": seed["key"], "layer": seed["layer"],
                        "col": sum(p["col"] for p in members) / len(members),
                        "row": sum(p["row"] for p in members) / len(members),
                        "count": len(members), "members": members})
    return out


def real_pins(q):
    inst, zoom = int(q["inst"]), float(q["zoom"])
    c0, r0, c1, r1 = (float(q[k]) for k in ("c0", "r0", "c1", "r1"))
    if (not all(math.isfinite(v) for v in (zoom, c0, r0, c1, r1))
        or not 0 < zoom <= 4096 or c1 < c0 or r1 < r0):
        raise ValueError("invalid pin viewport")
    layers = list(dict.fromkeys(q["layers"].split(",")))
    if any(layer not in SPAWN_LAYERS and layer not in ("flight", "poi", "dungeon") for layer in layers):
        raise ValueError("unknown pin layer")
    # Atlas tile keys have 64 rows. A far-away/tilted viewport must never turn
    # SpawnsIn's tile loop into an unbounded scan, including direct API calls.
    c0, r0, c1, r1 = max(0, c0), max(0, r0), min(64, c1), min(64, r1)
    out, omitted = [], 0
    if c1 < c0 or r1 < r0:
        return out, omitted
    inside = lambda p: c0 <= p["col"] <= c1 and r0 <= p["row"] <= r1  # noqa: E731
    for layer in layers:
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
        if layer == "service":
            for p in found:
                services = py(Atlas.Npc(p["id"]).services)
                p["mark"] = next(s for s in SERVICES if s in services)
        found.sort(key=lambda p: (p["kind"], p["id"], p["col"], p["row"]))
        seen = set()
        for p in found:
            key = f'{layer}:{p["kind"]}:{p["id"]}:{p["col"]}:{p["row"]}'
            if key in seen:
                continue
            seen.add(key)
            if len(seen) > PIN_CAP:
                omitted += 1
                continue
            pin = {"layer": layer, "kind": p["kind"], "id": p["id"], "col": p["col"], "row": p["row"],
                   "mark": p.get("mark"), "key": key}
            if p["kind"] == "npc":  # its faction's glow, a rare's rank
                e = Atlas.Npc(p["id"])
                pin["name"] = e.name
                pin["faction"] = e.faction
                if layer == "rare":
                    pin["mark"] = e.rank
            elif p["kind"] == "object":
                pin["name"] = Atlas.Object(p["id"]).name
            else:  # a POI's card is drawn from its pin
                pin.update(name=p["name"], faction=p.get("faction"), description=p.get("description"), icon=p.get("icon"))
            out.append(pin)
    return out, omitted


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
    spawns, world_points = [], []
    for inst, pts in sorted(e.spawns.items()):
        p = list(pts.values())
        points = [p[i:i + 2] for i in range(0, len(p), 2)]
        if inst in OFFSET:
            world_points += [list(to_world(inst, *x)) for x in points]
        else:
            spawns.append({"inst": inst, "map": MAP_NAMES.get(inst, f"#{inst}"), "points": points})
    if world_points:
        spawns.insert(0, {"inst": WORLD, "map": WORLD_NAME, "points": world_points})
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


FLIGHTS = {p["id"]: on_world(dict(p, inst=m)) for m in OFFSET for p in py(Atlas.FlightPoints(m))}


def flight(q):
    id = int(q["id"])
    f = FLIGHTS[id]
    area = f.get("areaID") and Atlas.Area(f["areaID"])
    dest = [dict(FLIGHTS[p.to], cost=p.cost, kind="flight") for p in Atlas.TaxiPaths().values() if p["from"] == id]
    dest.sort(key=lambda d: d["name"])
    return dict(f, kind="flight", area=area and area.name, destinations=dest)


def dungeon(q):
    d = py(Atlas.Dungeon(int(q["id"])))
    return on_world(dict(d, dungeonKind=d["kind"], kind="dungeon"))


def find(q):
    out = []
    term = q["q"].strip().casefold()
    if len(term) < 2:
        return out
    for m in real_maps():
        if m["inst"] not in OFFSET:
            continue
        if term in m["name"].casefold():
            out.append(dict(kind="place", id=m["uiMapID"], inst=WORLD, name=m["name"], detail="Map"))
        for z in m["zones"]:
            if term in z["name"].casefold():
                out.append(dict(kind="place", id=z["uiMapID"], inst=WORLD, name=z["name"], detail=m["name"]))
    for inst in OFFSET:
        for p in py(Atlas.POIs(inst)):
            if term in p["name"].casefold():
                out.append(on_world(dict(p, kind="poi", inst=inst, detail=MAP_NAMES[inst])))
    for f in FLIGHTS.values():
        if term in f["name"].casefold():
            out.append(dict(kind="flight", id=f["id"], inst=f["inst"], name=f["name"], detail="Flight point"))
    out = out[:40]
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


def assets(q):
    product, version = Atlas.Data.Tiles.product, Atlas.Data.Tiles.version
    out = inventory(DEMO, WORLD, product, version)
    out["tiles"] = sorted(world_key(i, k) for i in OFFSET for k in inventory(DEMO, i, product, version)["tiles"])
    out["terrain"] = {"available": False, "reason": "3D isn't available on the combined map."}
    return out


# The world the page shows (it reads the offsets from here); real_* are the Atlas's, one real map at a time.
def maps(q):
    ms = {m["inst"]: m for m in real_maps()}
    zones = sorted((z for i in OFFSET for z in ms[i]["zones"]), key=lambda z: z["name"])
    bounds = [min(b[0] for b in BOUNDS.values()), min(b[1] for b in BOUNDS.values()),
              max(b[2] for b in BOUNDS.values()), max(b[3] for b in BOUNDS.values())]
    parts = [{"inst": i, "name": ms[i]["name"], "offset": OFFSET[i], "bounds": BOUNDS[i]} for i in OFFSET]
    return dict(ms[WORLD], inst=WORLD, name=WORLD_NAME, bounds=bounds, zones=zones, parts=parts)


def tiles(q):
    return {"tiles": [{"key": world_key(i, t["key"]), "sea": t["sea"], "inst": i, "src": t["key"]}
                      for i in OFFSET for t in ({"key": k, "sea": not Atlas.Drawn(i, k)} for k in Atlas.Tiles(i).keys())]}


def labels(q):
    out, cities = [], []
    for inst in OFFSET:
        for l in py(Atlas.Labels(inst)):  # { text, col, row, tier, rank, areaID?, poiID?, size? }, rank order
            l["col"], l["row"] = to_world(inst, l["col"], l["row"])
            town = l["tier"] == "town"
            if l["text"] in CITIES:  # every capital named as a zone is, from afar: Ironforge and the Undercity are only towns
                if town and l["text"] in CITIES_AS_TOWNS:
                    cities.append(dict(l, tier="zone", size=CITY_SIZE, text=CITIES[l["text"]]))
                elif l["tier"] == "zone":
                    cities.append(dict(l, text=CITIES[l["text"]]))
                continue
            out.append(l)
    continents = [l for l in out if l["tier"] == "continent"]
    rest = sorted((l for l in out if l["tier"] != "continent"), key=lambda l: l["rank"])
    return {"labels": [dict(l, rank=i + 1) for i, l in enumerate(continents + cities + rest)]}


def at(q):
    inst, col, row = to_real(float(q["col"]), float(q["row"]))
    return real_at(inst, col, row)


def pins(q):
    c0, r0, c1, r1 = (float(q[k]) for k in ("c0", "r0", "c1", "r1"))
    out, omitted = [], 0
    grouped = q.get("groups") == "1"
    for inst, (dx, dy) in OFFSET.items():
        found, n = real_pins(dict(q, inst=inst, c0=c0 - dx, r0=r0 - dy, c1=c1 - dx, r1=r1 - dy))
        omitted += n
        for p in found:
            p["col"], p["row"] = p["col"] + dx, p["row"] + dy
            p["key"] = f'{inst}:{p["key"]}'
            out.append(p)
    if grouped:
        # A modest zoom band keeps membership steady through small zoom changes.
        zoom = float(q["zoom"])
        return {"pins": group_pins(out, 1.25 ** math.floor(math.log(zoom, 1.25) + 0.5)), "omitted": omitted}
    return out


API = {"assets": assets, "maps": maps, "tiles": tiles, "labels": labels,
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

    def send_head(self):
        path = self.translate_path(self.path)
        if os.path.isdir(path):
            path = os.path.join(path, 'index.html')
        if os.path.splitext(path)[1] in COMPRESSIBLE and accepts_gzip(self.headers.get('Accept-Encoding', '')):
            try:
                stat = os.stat(path)
                if 1024 < stat.st_size <= 8 * 1024 * 1024 and os.path.isfile(path):
                    body = compressed_file(path, stat.st_mtime_ns, stat.st_size)
                    self.send_response(200)
                    self.send_header('Content-Type', self.guess_type(path))
                    self.send_header('Content-Encoding', 'gzip')
                    self.send_header('Content-Length', str(len(body)))
                    self.send_header('Last-Modified', self.date_time_string(stat.st_mtime))
                    self.end_headers()
                    return io.BytesIO(body)
            except OSError:
                pass  # Normal static-file handling supplies the appropriate 404.
        return super().send_head()

    def review(self, method, body=b""):
        got = review_api.handle(method, urlparse(self.path).path, body, self.headers)
        if not got:
            return False
        status, body = got
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        return True

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        self.close_connection = n > review_api.MAX_BODY  # the rest is unread
        if not self.review("POST", self.rfile.read(min(n, review_api.MAX_BODY + 1))):
            self.send_error(404)

    def do_GET(self):
        u = urlparse(self.path)
        if self.review("GET"):
            return
        if u.path.startswith("/api/"):
            q = {k: v[0] for k, v in parse_qs(u.query).items()}
            status = 200
            try:
                endpoint = API.get(u.path[5:])
                if endpoint is None:
                    raise LookupError("Unknown endpoint")
                for k in ("col", "row", "zoom", "w", "h", "c0", "r0", "c1", "r1"):
                    if k in q and (not math.isfinite(float(q[k])) or abs(float(q[k])) > 1e6):
                        raise ValueError("invalid coordinate or dimension")
                for k in ("w", "h"):
                    if k in q and float(q[k]) <= 0:
                        raise ValueError("invalid viewport size")
                with atlas_lock:
                    body = json.dumps(endpoint(q), allow_nan=False).encode()
            except LookupError:
                status, body = 404, b'{"error":"Not found"}'
            except (ValueError, TypeError, AttributeError, LuaError):
                status, body = 400, b'{"error":"Invalid request"}'
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Vary", "Accept-Encoding")
            if len(body) > 1024 and accepts_gzip(self.headers.get("Accept-Encoding", "")):
                body = gzip.compress(body, 6)
                self.send_header("Content-Encoding", "gzip")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            try:
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError):
                pass  # a superseded view may close the connection
        else:
            super().do_GET()

    def send_response(self, code, message=None):
        self.code = code
        super().send_response(code, message)

    def end_headers(self):
        path = urlparse(self.path).path
        if os.path.splitext(path)[1] in COMPRESSIBLE or path.endswith('/'):
            self.send_header('Vary', 'Accept-Encoding')
        if self.path.startswith(("/tiles/", "/terrain/", "/objects/")) and not self.path.endswith("manifest.json") and self.code == 200:
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
