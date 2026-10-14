#!/usr/bin/env python3
"""Generate Data/Npcs.lua, Data/Objects.lua, Data/Items.lua and Data/Quests.lua
from the user's installed QuestieDB (baked mode), projected into tile space
through Data/UiMaps.lua. See docs/atlas-data.md for the layouts.

QuestieDB declares no license: these files are gitignored, never commit them.

  .venv/bin/python tools/gen_questie.py \\
      "/Applications/World of Warcraft/_classic_beta_/Interface/AddOns/QuestieDB" [-o Data]

QuestieDB_<flavor>.toc holds the data as `## X-<Ent>-<key>: <base64>` lines
(`~N~` = value split over keys <key>-1..<key>-N). X-<Ent>-IDS is
base64 -> zlib -> CBOR (the id list); per id, X-<Ent>-<id>-S is a CBOR map of
scalar fields plus "p", a bitmask of which table fields exist (bit f-1 ->
field f), each in X-<Ent>-<id>-<f> (base64 -> CBOR). Strings are CBOR byte
strings (UTF-8). Lua tables keyed 1..n arrive as CBOR arrays with null holes.

Spawns are `{ [areaID] = { {x, y, phase?}, ... } }` in 0..100 of the uiMap
QuestieDB assigns to that area (support/<flavor>/Zones/areaIdToUiMapId.lua,
override on top); {-1, -1} or a dungeon area means inside that dungeon,
resolved to its instance ID through instanceIdToAreaId.lua and dungeons.lua.
"""
from __future__ import annotations

import argparse
import base64
import os
import re
import struct
import zlib
from collections import Counter

import lupa.lua51 as lupa

from mmtools.log import log

CONTRACT = "4"
FLAVOR = "Forever"
TILE_YARDS = 1600 / 3

# Field indices per entity (QuestieDB contract 4).
NPC = dict(name=1, minLevel=4, maxLevel=5, rank=6, spawns=7, zone=9, questStarts=10, questEnds=11,
           factionID=12, friendly=13, subName=14, flags=15)
OBJECT = dict(name=1, questStarts=2, questEnds=3, spawns=4, zone=5, factionID=6)
ITEM = dict(name=1, npcDrops=2, objectDrops=3, itemDrops=4, startQuest=5, requiredLevel=10,
            cls=12, subClass=13, vendors=14)
QUEST = dict(name=1, startedBy=2, finishedBy=3, requiredLevel=4, questLevel=5, races=6, classes=7,
             objectivesText=8, triggerEnd=9, objectives=10, preQuestGroup=12, preQuestSingle=13,
             exclusiveTo=16, zoneOrSort=17, nextQuest=22, breadcrumbFor=27)

OBJECTIVE_KINDS = {1: "monster", 2: "object", 3: "item", 4: "reputation", 5: "killcredit", 6: "spell"}

# ChrRaces masks (src/corrections/enum/expansions.lua, Forever): bits 32/33 are Skyborne.
ALLIANCE_RACES = 1 | 4 | 8 | 64 | (1 << 32)   # Human, Dwarf, Night Elf, Gnome, Skyborne Alliance
HORDE_RACES = 2 | 16 | 32 | 128 | (1 << 33)   # Orc, Undead, Tauren, Troll, Skyborne Horde

HERBS = {"Peacebloom", "Silverleaf", "Earthroot", "Mageroyal", "Briarthorn", "Stranglekelp", "Bruiseweed",
         "Wild Steelbloom", "Grave Moss", "Kingsblood", "Liferoot", "Fadeleaf", "Goldthorn", "Khadgar's Whisker",
         "Wintersbite", "Firebloom", "Purple Lotus", "Arthas' Tears", "Sungrass", "Blindweed", "Ghost Mushroom",
         "Gromsblood", "Golden Sansam", "Dreamfoil", "Mountain Silversage", "Plaguebloom", "Icecap", "Black Lotus",
         "Swiftthistle", "Bloodthistle"}


# --- QuestieDB baked store -------------------------------------------------------------------------------

def cbor_loads(b: bytes):
    pos = 0

    def length(ai):
        nonlocal pos
        if ai < 24:
            return ai
        if ai == 31:
            return None
        n = {24: 1, 25: 2, 26: 4, 27: 8}[ai]
        v = int.from_bytes(b[pos:pos + n], "big")
        pos += n
        return v

    def item():
        nonlocal pos
        ib = b[pos]
        pos += 1
        mt, ai = ib >> 5, ib & 31
        if mt == 0:
            return length(ai)
        if mt == 1:
            return -1 - length(ai)
        if mt in (2, 3):
            n = length(ai)
            if n is None:
                parts = []
                while b[pos] != 0xFF:
                    parts.append(item())
                pos += 1
                return "".join(parts)
            raw = b[pos:pos + n]
            pos += n
            return raw.decode("utf-8")
        if mt == 4:
            n = length(ai)
            out = []
            if n is None:
                while b[pos] != 0xFF:
                    out.append(item())
                pos += 1
            else:
                out = [item() for _ in range(n)]
            return out
        if mt == 5:
            n = length(ai)
            out = {}
            if n is None:
                while b[pos] != 0xFF:
                    k = item()
                    out[k] = item()
                pos += 1
            else:
                for _ in range(n):
                    k = item()
                    out[k] = item()
            return out
        if mt == 6:
            length(ai)
            return item()
        if ai == 20:
            return False
        if ai == 21:
            return True
        if ai in (22, 23):
            return None
        fmt, n = {25: (">e", 2), 26: (">f", 4), 27: (">d", 8)}[ai]
        v = struct.unpack(fmt, b[pos:pos + n])[0]
        pos += n
        return v

    return item()


def as_map(v) -> dict:
    """A Lua table keyed 1..n arrives as a CBOR array; view it as a 1-based map without holes."""
    if isinstance(v, list):
        return {k: x for k, x in enumerate(v, 1) if x is not None}
    return v


class Store:
    LINE = re.compile(r"^## ([^:]+): ?(.*)$")

    def __init__(self, toc: str):
        self.kv = {}
        with open(toc, encoding="utf-8") as f:
            for line in f:
                m = self.LINE.match(line.rstrip("\r\n"))
                if m:
                    self.kv[m.group(1)] = m.group(2)

    def get(self, key: str):
        v = self.kv.get(key)
        if v is None:
            return None
        m = re.fullmatch(r"~(\d+)~", v)
        if m:
            return "".join(self.kv[f"{key}-{i}"] for i in range(1, int(m.group(1)) + 1))
        return v

    def blob(self, key: str, compressed: bool = False):
        raw = base64.b64decode(self.get(key))
        return cbor_loads(zlib.decompress(raw) if compressed else raw)

    def ids(self, ent: str) -> list[int]:
        return sorted(self.blob(f"X-{ent}-IDS", True))

    def row(self, ent: str, i: int) -> dict:
        """Scalars and every present table field of one entity, keyed by field index."""
        r = as_map(self.blob(f"X-{ent}-{i}-S"))
        p = r.pop("p", 0)
        f = 1
        while p >> (f - 1):
            if p >> (f - 1) & 1:
                r[f] = self.blob(f"X-{ent}-{i}-{f}")
            f += 1
        return r


# --- QuestieDB zone support data (Lua) --------------------------------------------------------------------

def load_zones(root: str, flavor: str):
    """areaID -> uiMapID, and dungeon areaID (incl. alternatives and subzones) -> instanceID."""
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        Modules = { ZoneDB = { private = {} }, Expansions = { Current = 1, Tbc = 2, Wotlk = 3, Cata = 4, MoP = 5 } }
        QuestieLoader = { ImportModule = function(_, name) return Modules[name] end }
        UnitFactionGroup = function() return "Alliance" end
    """)
    run = lua.eval("function(src, name, ns) return assert(loadstring(src, '@' .. name))(nil, ns) end")

    def load(rel):
        with open(os.path.join(root, rel), encoding="utf-8") as f:
            run(f.read(), rel, ns)

    ns = lua.table(Enum=lua.table())
    load("src/corrections/enum/zones.lua")
    zone_db = lua.globals().Modules.ZoneDB
    zone_db.zoneIDs = ns.Enum.zoneIDs
    for rel in ("areaIdToUiMapId.lua", "instanceIdToAreaId.lua", "dungeons.lua", "subZoneToParentZone.lua"):
        load(f"support/{flavor}/Zones/{rel}")
    evaluate = lua.eval("function(s) return assert(loadstring(s))() end")
    area_ui = dict(evaluate(zone_db.private.areaIdToUiMapId).items())
    area_ui.update(evaluate(zone_db.private.areaIdToUiMapIdOverride).items())

    area_inst = {}
    dungeons = zone_db.private.dungeons
    for inst, area in zone_db.instanceIdToAreaId.items():
        area_inst[area] = inst
        entry = dungeons[area]
        if entry is not None and entry[2] is not None:
            for alt in entry[2].values():
                area_inst[alt] = inst
    parents = dict(evaluate(zone_db.private.subZoneToParentZone).items())
    parents.update(evaluate(zone_db.private.subZoneToParentZoneOverride).items())
    for sub, parent in parents.items():
        if parent in area_inst and sub not in area_inst:
            area_inst[sub] = area_inst[parent]
    return area_ui, area_inst


def load_uimaps(path: str) -> dict[int, tuple]:
    """uiMapID -> (inst, col0, row0, col1, row1) for maps with a rect."""
    lua = lupa.LuaRuntime()
    with open(path, encoding="utf-8") as f:
        lua.execute(f.read())
    out = {}
    for mid, r in lua.globals().MagicMap_UiMaps.items():
        if r[5] is not None:
            out[mid] = (r[4], r[5], r[6], r[7], r[8])
    return out


# --- Projection -------------------------------------------------------------------------------------------

class Projector:
    def __init__(self, area_ui, area_inst, uimaps):
        self.area_ui, self.area_inst, self.uimaps = area_ui, area_inst, uimaps
        self.stats = Counter()
        self.unmapped = Counter()

    def __call__(self, spawns):
        """QuestieDB spawns -> ({inst: [c, r, ...]}, [instIDs])."""
        points, instances = {}, set()
        for area, pts in sorted(as_map(spawns or {}).items()):
            for p in pts:
                if p is None:
                    continue
                x, y = p[0], p[1]
                if area in self.area_inst and (x == -1 and y == -1 or self.area_ui.get(area) not in self.uimaps):
                    instances.add(self.area_inst[area])
                    self.stats["instance"] += 1
                    continue
                rect = self.uimaps.get(self.area_ui.get(area))
                if rect is None or x < 0:
                    self.stats["unmapped"] += 1
                    self.unmapped[area] += 1
                    continue
                inst, c0, r0, c1, r1 = rect
                points.setdefault(inst, []).extend((c0 + (c1 - c0) * x / 100, r0 + (r1 - r0) * y / 100))
                self.stats["point"] += 1
        return points or None, sorted(instances) or None


# --- Lua output -------------------------------------------------------------------------------------------

def lua_val(v) -> str:
    if v is None:
        return "nil"
    if v is True:
        return "true"
    if v is False:
        return "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        s = f"{v:.3f}".rstrip("0").rstrip(".")
        return "0" if s == "-0" else s
    if isinstance(v, str):
        return '"' + "".join(ESC.get(ch, ch) for ch in v) + '"'
    if isinstance(v, dict):
        return "{" + ",".join(f"[{k}]={lua_val(x)}" for k, x in sorted(v.items())) + "}"
    v = list(v)
    while v and v[-1] is None:
        v.pop()
    return "{" + ",".join(lua_val(x) for x in v) + "}"


ESC = {"\\": "\\\\", '"': '\\"', "\n": "\\n", "\r": "\\r", "\0": "\\0"}


def ids(v):
    """An ID list, nil when empty."""
    out = [x for x in (v or ()) if x is not None]
    return out or None


def write(path, global_name, header, rows, meta):
    with open(path, "w", encoding="utf-8") as f:
        f.write(f"-- GENERATED by tools/gen_questie.py from QuestieDB {meta['version']} "
                f"(X-Contract-Version {meta['contract']}, X-Flavor {meta['flavor']}, "
                f"X-BUILD-COMMIT {meta['commit']}) with Data/UiMaps.lua. Do not edit.\n")
        f.write("-- QuestieDB declares no license: gitignored, do not commit or publish.\n")
        for line in header:
            f.write(f"-- {line}\n")
        f.write(f"{global_name} = {{\n")
        for i, row in rows:
            f.write(f"[{i}]={lua_val(row)},\n")
        f.write("}\n")
    log(f"{path}: {len(rows)} rows, {os.path.getsize(path) / 1e6:.1f} MB")


# --- Entities ---------------------------------------------------------------------------------------------

def object_kind(name):
    if name == "Mailbox":
        return "mailbox"
    if name in HERBS:
        return "herb"
    if name.endswith(" Vein") or name.endswith(" Deposit"):
        return "ore"
    return None


def quest_faction(races):
    a, h = bool(races & ALLIANCE_RACES), bool(races & HORDE_RACES)
    return "A" if a and not h else "H" if h and not a else None


def objectives(raw):
    out = []
    for group, entries in sorted(as_map(raw or {}).items()):
        kind = OBJECTIVE_KINDS[group]
        if group == 4:                       # reputation: one {factionID, value}
            out.append([kind, entries[0]])
            continue
        for e in entries:
            if e is None:
                continue
            if group == 5:                   # killcredit: {{npcIDs}, rootNpcID, text}
                out.append([kind, e[1], e[2] if len(e) > 2 else None])
            else:                            # {id, text, ...}
                out.append([kind, e[0], e[1] if len(e) > 1 else None])
    return out or None


def by_slot(v, n):
    """A 1..n table of ID lists (CBOR array or map) as n ID lists, nil when all empty."""
    m = as_map(v or {})
    out = [ids(m.get(k)) for k in range(1, n + 1)]
    return out if any(out) else None


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("questiedb", help="the QuestieDB addon directory")
    parser.add_argument("-o", "--output", default="Data", help="output directory (default Data)")
    parser.add_argument("--uimaps", default="Data/UiMaps.lua")
    ns = parser.parse_args()

    store = Store(os.path.join(ns.questiedb, f"QuestieDB_{FLAVOR}.toc"))
    meta = dict(version=store.kv["Version"], contract=store.kv["X-Contract-Version"],
                flavor=store.kv["X-Flavor"], commit=store.kv["X-BUILD-COMMIT"])
    if meta["contract"] != CONTRACT or meta["flavor"] != FLAVOR:
        raise SystemExit(f"QuestieDB contract {meta['contract']} flavor {meta['flavor']}: "
                         f"expected contract {CONTRACT} flavor {FLAVOR}")
    log(f"QuestieDB {meta['version']} contract {meta['contract']} {meta['flavor']}")
    project = Projector(*load_zones(ns.questiedb, FLAVOR), load_uimaps(ns.uimaps))
    out = lambda name: os.path.join(ns.output, name)  # noqa: E731

    rows = []
    for i in store.ids("Npc"):
        r = store.row("Npc", i)
        pts, insts = project(r.get(NPC["spawns"]))
        rows.append((i, [r.get(NPC["name"]), r.get(NPC["subName"]), r.get(NPC["minLevel"]), r.get(NPC["maxLevel"]),
                         r.get(NPC["rank"]) or None, r.get(NPC["friendly"]) or None, r.get(NPC["flags"]) or None,
                         ids(r.get(NPC["questStarts"])), ids(r.get(NPC["questEnds"])), pts, insts]))
    write(out("Npcs.lua"), "MagicMap_Npcs", [
        "[npcID] = { name, subName, minLevel, maxLevel, rank, faction, flags, questStarts, questEnds, spawns, instances }",
        "rank: 1 elite, 2 rare elite, 3 boss, 4 rare. faction: \"A\" | \"H\" | \"AH\" (friendly to). flags: npcFlags.",
        "spawns: { [inst] = { col, row, ... } } tile space. instances: instIDs of dungeons it spawns inside.",
    ], rows, meta)

    rows = []
    for i in store.ids("Object"):
        r = store.row("Object", i)
        pts, insts = project(r.get(OBJECT["spawns"]))
        name = r.get(OBJECT["name"])
        rows.append((i, [name, object_kind(name or ""), ids(r.get(OBJECT["questStarts"])), ids(r.get(OBJECT["questEnds"])),
                         pts, insts]))
    write(out("Objects.lua"), "MagicMap_Objects", [
        "[objectID] = { name, kind, questStarts, questEnds, spawns, instances }",
        "kind: \"mailbox\" | \"herb\" | \"ore\" | nil. spawns: { [inst] = { col, row, ... } } tile space.",
    ], rows, meta)
    mailboxes = sum(1 for _, r in rows if r[1] == "mailbox" and r[4])

    rows = []
    for i in store.ids("Item"):
        r = store.row("Item", i)
        rows.append((i, [r.get(ITEM["name"]), ids(r.get(ITEM["npcDrops"])), ids(r.get(ITEM["objectDrops"])),
                         ids(r.get(ITEM["itemDrops"])), ids(r.get(ITEM["vendors"])), r.get(ITEM["startQuest"]) or None,
                         r.get(ITEM["cls"]), r.get(ITEM["subClass"]), r.get(ITEM["requiredLevel"]) or None]))
    write(out("Items.lua"), "MagicMap_Items", [
        "[itemID] = { name, npcDrops, objectDrops, itemDrops, vendors, startQuest, class, subClass, requiredLevel }",
    ], rows, meta)

    rows = []
    for i in store.ids("Quest"):
        r = store.row("Quest", i)
        races = r.get(QUEST["races"]) or 0
        zs = r.get(QUEST["zoneOrSort"]) or 0
        trigger = None
        if r.get(QUEST["triggerEnd"]):
            t = as_map(r[QUEST["triggerEnd"]])
            trigger = [t.get(1), project(t.get(2))[0]]
        rows.append((i, [r.get(QUEST["name"]), r.get(QUEST["questLevel"]), r.get(QUEST["requiredLevel"]),
                         quest_faction(races), races or None, r.get(QUEST["classes"]) or None,
                         by_slot(r.get(QUEST["startedBy"]), 3), by_slot(r.get(QUEST["finishedBy"]), 2),
                         objectives(r.get(QUEST["objectives"])), ids(r.get(QUEST["objectivesText"])),
                         zs if zs > 0 else None, -zs if zs < 0 else None,
                         ids(r.get(QUEST["preQuestSingle"])), ids(r.get(QUEST["preQuestGroup"])),
                         ids(r.get(QUEST["exclusiveTo"])), r.get(QUEST["nextQuest"]) or None,
                         r.get(QUEST["breadcrumbFor"]) or None, trigger]))
    write(out("Quests.lua"), "MagicMap_Quests", [
        "[questID] = { name, level, requiredLevel, faction, races, classes, startedBy, finishedBy, objectives,",
        "  objectivesText, zone, sort, preQuestSingle, preQuestGroup, exclusiveTo, nextQuest, breadcrumbFor, triggerEnd }",
        "faction: \"A\" | \"H\" from requiredRaces (Alliance-only / Horde-only), else nil.",
        "startedBy = { npcs, objects, items }, finishedBy = { npcs, objects }.",
        "objectives: { { kind, id, text }, ... }, kind monster | object | item | reputation | killcredit | spell.",
        "zone: areaID (zoneOrSort > 0); sort: QuestSort (-zoneOrSort). triggerEnd = { text, spawns }.",
    ], rows, meta)

    log(f"spawn points: {dict(project.stats)}; mailboxes with spawns: {mailboxes}")
    log(f"unmapped areas (area: points): {dict(project.unmapped.most_common(20))}")


if __name__ == "__main__":
    main()
