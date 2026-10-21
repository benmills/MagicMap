"""Game's quest pieces, round trips on the sim (docs/v1-plan.md M2.2): what the client says of your
quests and of quests to pick up reaches obs.quests and obs.offers (game/parts/Quests.lua,
Offers.lua), and the follow and tooltip Commands (game/commands/) come back in the client and in
the next observation. And the fixture streams M2.3 and M2.4 replay through Model alone
(fixtures/streams/quests.lua, offers.lua) are these parts' output, recorded from the sim.

  .venv/bin/python tools/tests/test_quest_parts.py   # records the two stories again into the fixtures
"""
import os
import re
import sys

TESTS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(TESTS))  # (run as a script)

from sim import py  # noqa: E402
from test_addon import boot, errors  # noqa: E402
from test_blips import lua_tools  # noqa: E402

STREAMS = os.path.join(TESTS, "fixtures", "streams")
ELWYNN, WESTFALL, DUROTAR, STORMWIND = 1429, 1436, 1411, 1453

# The sim's quest log from Lua: Log{ { id, title, level, col, row (its pin on Elwynn), complete?,
# objectives = { { type, text, have, need, finished } }, map? } }; Offers{ [map] = { { id, name,
# col, row, line?, hidden?, taken? } } }. A deterministic time() (the sim's is the wall clock's).
SETUP = """
local Sim, Atlas = ...
time = function() return 1792077412 + math.floor(Sim.time) end
function Log(list)
	local quests = {}
	for _, q in ipairs(list) do
		local map = q.map or 1429
		local x, y = Atlas.TileToMap(map, q.col, q.row)
		local objectives = {}
		for i, o in ipairs(q.objectives or {}) do
			objectives[i] = { type = o[1], text = o[2], numFulfilled = o[3], numRequired = o[4], finished = o[5] }
		end
		quests[q.id] = { title = q.title, level = q.level, map = map, x = x, y = y, complete = q.complete == true,
			objectives = objectives }
	end
	Sim.quests = quests
end
function Offers(maps)
	local offers = {}
	for map, list in pairs(maps) do
		offers[map] = {}
		for i, o in ipairs(list) do
			local x, y = Atlas.TileToMap(map, o.col, o.row)
			offers[map][i] = { questID = o.id, questName = o.name, questLineName = o.line or "", questLineID = 1, x = x, y = y,
				isHidden = o.hidden == true, inProgress = o.taken == true, startMapID = map }
		end
	end
	Sim.offers = offers
end
Sim.asks = {}
local ask = C_QuestLine.RequestQuestLinesForMap
C_QuestLine.RequestQuestLinesForMap = function(id)
	Sim.asks[id] = (Sim.asks[id] or 0) + 1
	return ask(id)
end
"""

# QuestieDB's item objectives for the stories' quests, as Atlas.Quest has them (stubbed: the same
# with or without the gitignored Data/Quests.lua).
ITEMS = {60: [772], 47: [773], 176: [1931]}


def client():
    L, sim, ns = boot()
    sim.Slash("/mm toggle")  # the map shown: Game reads quests and offers only then
    L.execute(SETUP, sim, ns.Atlas)
    real = ns.Atlas.Quest
    ns.Atlas.Quest = L.eval("""function(items, real) return function(id)
        local list = items[id]
        if not list then return real(id) end
        local objectives = {}
        for i, item in ipairs(list) do objectives[i] = { kind = "item", id = item } end
        return { id = id, objectives = objectives, finishedBy = { npcs = {}, objects = {} } }
    end end""")(L.table_from({k: L.table_from(v) for k, v in ITEMS.items()}), real)
    return L, sim, ns, L.globals()


def run_to(sim, ns, frame):
    while ns.Runtime.frames < frame:
        sim.Step()


def by_id(part, key="id"):
    return {q[key]: q for q in py(part)}


# The stories: a quest log in Goldshire at level 8 (fixtures/streams/quests.lua), and quests to pick
# up around it (offers.lua). Each step: (frame, what happens before it, record it).
def quest(id, title, level, col, row, objectives=(), complete=False):
    return dict(id=id, title=title, level=level, col=col, row=row, complete=complete, objectives=list(objectives))


CANDLES = quest(60, "Kobold Candles", 7, 31.775, 50.39, [("item", "Large Candle: 3/8", 3, 8, False)])
GOLD = quest(47, "Gold Dust Exchange", 7, 31.8, 50.3, [("item", "Gold Dust: 0/10", 0, 10, False)])
MINE = quest(62, "The Fargodeep Mine", 7, 31.74, 50.42, [("event", "Scout through the Fargodeep Mine", 0, 1, False)])
FRONTIER = quest(52, "Protect the Frontier", 10, 33.95, 49.95, [("monster", "Prowler slain: 2/8", 2, 8, False),
                                                                  ("monster", "Young Forest Bear slain: 0/5", 0, 5, False)])
HOGGER = quest(176, "Wanted:  \"Hogger\"", 11, 30.749, 50.919, [("item", "Huge Gnoll Claw: 0/1", 0, 1, False)])
LOVERS = quest(106, "Young Lovers", 6, 31.063, 50.619, complete=True)
CLEANUP = quest(7, "Kobold Camp Cleanup", 2, 32.305, 48.66, [("monster", "Kobold Vermin slain: 10/10", 10, 10, True)], True)
JASPER = quest(76, "The Jasperlode Mine", 10, 33.2, 48.98, [("event", "Scout through the Jasperlode Mine", 0, 1, False)])
CANDLES4 = dict(CANDLES, objectives=[("item", "Large Candle: 4/8", 4, 8, False)])
MINE_DONE = dict(MINE, col=31.862, row=49.748, complete=True,  # its pin moves to the turn-in
                 objectives=[("event", "Scout through the Fargodeep Mine", 1, 1, True)])
# Replay.Oracles' areas (tile-space circles): the game's objective areas; Hogger has none.
AREAS = {60: (31.775, 50.39, 0.08), 47: (31.8, 50.32, 0.1), 62: (31.74, 50.42, 0.05), 52: (33.95, 49.95, 0.25),
         76: (33.2, 48.98, 0.05)}


def quests_story(L, sim, ns, G):
    """Kobold Candles is followed and goes 3/8 to 4/8; the follow moves to The Fargodeep Mine (a
    follow Command), which completes (its pin moves to the turn-in) and is handed in, and The
    Jasperlode Mine is taken; then the log is abandoned (known and empty)."""
    def log(*quests):
        return lambda: G.Log(L.table_from([L.table_from(dict(q, objectives=L.table_from(
            [L.table_from(o) for o in q["objectives"]]))) for q in quests]))

    def event():
        sim.FireEvent("QUEST_LOG_UPDATE")

    def follow():
        ns.Game.Command(L.table_from({"kind": "follow", "quest": 62}))

    def handed_in():
        log(CANDLES4, GOLD, FRONTIER, HOGGER, LOVERS, CLEANUP, JASPER)()
        sim.superTracked = 0  # (the client lets go of a quest that leaves the log)
        event()

    sim.units.player.level, sim.superTracked = 8, 60
    log(CANDLES, GOLD, MINE, FRONTIER, HOGGER, LOVERS, CLEANUP)()
    return [
        (1, None, (31.95, 49.75)), (60, None, (31.91, 49.9)),
        (150, lambda: (log(CANDLES4, GOLD, MINE, FRONTIER, HOGGER, LOVERS, CLEANUP)(), event()), None),
        (180, None, (31.82, 50.2)), (240, None, (31.8, 50.3)),
        (360, follow, (31.77, 50.38)),  # (the same frame's obs has it)
        (500, lambda: (log(CANDLES4, GOLD, MINE_DONE, FRONTIER, HOGGER, LOVERS, CLEANUP)(), event()), None),
        (540, None, (31.74, 50.42)),
        (690, handed_in, None), (720, None, (31.86, 49.76)), (840, None, (31.86, 49.76)),
        (860, lambda: (log()(), event()), None), (900, None, (31.86, 49.76)),
    ]


def offer(id, name, col, row, line=None, hidden=False, taken=False):
    return dict(id=id, name=name, col=col, row=row, line=line, hidden=hidden, taken=taken)


PRINCESS, NECKLACE = offer(88, "Princess Must Die!", 31.377, 50.553), offer(85, "Lost Necklace", 31.366, 50.543)
LINEN, FISHY = offer(83, "Red Linen Goods", 34.292, 49.872), offer(40, "A Fishy Peril", 31.863, 49.806, "The Lost Guards")
PIE, STEW = offer(22, "Goretusk Liver Pie", 30.046, 50.96), offer(36, "Westfall Stew", 30.27, 50.48)
HEIRLOOM = offer(64, "The Forgotten Heirloom", 30.278, 50.472, hidden=True)  # trivial: the client hides it


def offers_story(L, sim, ns, G):
    """Every zone of the map shown is asked at once and answered a little later (known empty till
    then); A Fishy Peril is taken (in progress: gone); tracking hidden quests shows The Forgotten
    Heirloom; then the client wants every zone asked again, and has none left (known and empty)."""
    def offers(elwynn, westfall):
        return lambda: G.Offers(L.table_from({ELWYNN: L.table_from([L.table_from(o) for o in elwynn]),
                                              WESTFALL: L.table_from([L.table_from(o) for o in westfall])}))

    def taken():
        offers([PRINCESS, NECKLACE, LINEN, dict(FISHY, taken=True)], [PIE, STEW, HEIRLOOM])()
        sim.quests[40] = L.table_from({"title": FISHY["name"], "level": 8, "map": ELWYNN, "x": 0.4, "y": 0.6,
                                       "complete": False, "objectives": L.table()})
        sim.FireEvent("QUEST_LOG_UPDATE")  # (and QUEST_ACCEPTED: the sim's)

    def hidden_on():
        sim.trackingHidden = True
        sim.FireEvent("MINIMAP_UPDATE_TRACKING")

    def none_left():
        offers([], [])()
        sim.FireEvent("QUESTLINE_UPDATE", True)

    sim.units.player.level = 8
    offers([PRINCESS, NECKLACE, LINEN, FISHY], [PIE, STEW, HEIRLOOM])()
    return [
        (1, None, (31.95, 49.75)), (30, None, (31.95, 49.75)), (90, None, (31.9, 49.79)),
        (120, taken, None), (150, None, (31.87, 49.8)),
        (210, hidden_on, None), (240, None, (31.87, 49.8)), (300, None, (31.87, 49.8)),
        (360, none_left, None), (420, None, (31.87, 49.8)),
    ]


RECORD = """
local Sim, Game, name, rec = ...
local function R3(v) return v and math.floor(v * 1000 + 0.5) / 1000 end
local function Copy(v)
	if type(v) == "number" then return R3(v) end
	if type(v) ~= "table" then return v end
	local t = {}
	for k, x in pairs(v) do t[k] = Copy(x) end
	return t
end
local o = Game.obs
local part = o[name]
if part ~= nil and not rawequal(part, rec.last) then rec.parts[#rec.parts + 1], rec.last = Copy(part), part end
rec.out[#rec.out + 1] = { frame = o.frame, t = R3(o.t), epoch = o.epoch, hooked = {}, you = Copy(o.you),
	[name] = part ~= nil and "@P" .. #rec.parts .. "@" or nil }
"""


def record(story, name):
    """The story played on the sim, the part's observation kept at each recorded frame (positions,
    times to 3 decimals, as /mm record keeps them): the stream as Lua source, each table the part
    handed over written once (P[i]) and shared by the frames it was handed in, and its parts."""
    L, sim, ns, G = client()
    rec, keep = L.table_from({"parts": L.table(), "out": L.table()}), L.eval("loadstring")(RECORD)
    for frame, before, at in story(L, sim, ns, G):
        run_to(sim, ns, frame - 1)
        if before:
            before()
        if at:
            sim.player.col, sim.player.row, sim.player.facing = at[0], at[1], 3.4
        sim.Step()
        if at:
            keep(sim, ns.Game, name, rec)
    assert not errors(sim, ns), errors(sim, ns)
    dump = lua_tools(L).Dump
    stream = re.sub(r'"@P(\d+)@"', r"P[\1]", dump(rec.out))
    if name == "quests":
        stream = stream[:-1] + "\tareas = {\n" + "".join(
            f"\t\t[{id}] = {{ inst = 0, col = {c}, row = {r}, r = {rad} }},\n" for id, (c, r, rad) in sorted(AREAS.items())) + "\t},\n}"
    return py(rec.parts), HEAD[name] + "local P = " + dump(rec.parts) + "\n\nreturn " + stream + "\n"


HEAD = {
    "quests": """-- Fixture stream (types/observation.lua MM.ObsQuest[]): your quest log in Goldshire, Elwynn Forest, at
-- level 8, for Model alone (tools/tests/replay.lua). Recorded from the sim by tools/tests/test_quest_parts.py
-- (quests_story): game/parts/Quests.lua's output. Kobold Candles is followed and goes 3/8 to 4/8; the follow
-- moves to The Fargodeep Mine (a follow Command), which completes (its pin moves to the turn-in, no area)
-- and is handed in, and The Jasperlode Mine is taken; then the log is abandoned (known and empty).
-- `areas`: the objective areas Replay.Oracles answers Inside from (circles in tile space); Hogger has
-- none, nor do quests ready to turn in.
-- On-change parts keep their table while nothing changes: a new table is a change.
""",
    "offers": """-- Fixture stream (types/observation.lua MM.ObsOffer[]): quests to pick up on the map shown (Elwynn's
-- and Westfall's: every zone of it), for Model alone (tools/tests/replay.lua). Recorded from the sim by
-- tools/tests/test_quest_parts.py (offers_story): game/parts/Offers.lua's output. Asked, not answered
-- yet (known empty); answered; A Fishy Peril is taken (in progress: gone); tracking hidden quests shows
-- The Forgotten Heirloom; then the client asks for every zone again and has none (known and empty).
-- On-change parts keep their table while nothing changes: a new table is a change.
""",
}


def test_quests_round_trip():
    L, sim, ns, G = client()
    held = L.eval("rawequal")  # the same table: nothing new
    sim.Run(0.1)
    quests = by_id(ns.Game.obs.quests)
    candles, mine = quests[60], quests[62]  # the sim's log: Kobold Candles 3/8, The Fargodeep Mine to turn in
    assert (candles["title"], candles["level"], candles["trivial"], candles["complete"], candles["followed"],
            candles["areaMap"]) == ("Kobold Candles", 7, False, False, False, ELWYNN)
    assert candles["objectives"] == [{"type": "item", "text": "Large Candle: 3/8", "have": 3, "need": 8,
                                      "finished": False, "itemID": 772}]
    pin = candles["pin"]
    assert pin["inst"] == 0 and [round(v, 9) for v in ns.Atlas.TileToMap(ELWYNN, pin["col"], pin["row"])] == [0.35, 0.55]
    assert mine["complete"] and "areaMap" not in mine and mine["objectives"][0]["type"] == "event"

    # On several maps, the smallest's (its area is there): Kobold Candles on Dun Morogh (bigger, read
    # first), Elwynn and Stormwind City (smaller, read after); map indicators skipped; levels and grey.
    L.execute("""local on = C_QuestLog.GetQuestsOnMap
        C_QuestLog.GetQuestsOnMap = function(id)
            local out = on(id)
            if id == 1426 or id == 1453 then out[#out + 1] = { questID = 60, x = 0.2, y = 0.3, isMapIndicatorQuest = false } end
            if id == 1436 then out[#out + 1] = { questID = 9, x = 0.5, y = 0.5, isMapIndicatorQuest = true } end
            return out
        end""")
    sim.quests[61] = L.table_from({"title": "Shipment to Stormwind", "level": 1, "map": WESTFALL, "x": 0.5, "y": 0.5,
                                   "complete": False, "objectives": L.table()})
    before = ns.Game.obs.quests
    sim.FireEvent("QUEST_LOG_UPDATE")
    sim.FireEvent("QUEST_POI_UPDATE")
    sim.Run(0.25)
    assert held(ns.Game.obs.quests, before)  # coalesced: read 0.3 s after the first
    sim.Run(0.1)
    quests = by_id(ns.Game.obs.quests)
    assert sorted(quests) == [60, 61, 62]
    pin = quests[60]["pin"]
    assert quests[60]["areaMap"] == STORMWIND and quests[61]["areaMap"] == WESTFALL
    assert [round(v, 9) for v in ns.Atlas.TileToMap(STORMWIND, pin["col"], pin["row"])] == [0.2, 0.3]
    assert quests[61]["level"] == 1 and not quests[61]["trivial"] and not quests[61]["objectives"]

    # Read again with nothing changed: the same table. A level up: Shipment to Stormwind is grey now.
    same = ns.Game.obs.quests
    sim.FireEvent("QUEST_LOG_UPDATE")
    sim.Run(0.5)
    assert held(ns.Game.obs.quests, same)
    sim.units.player.level = 7
    sim.FireEvent("PLAYER_LEVEL_UP", 7)
    sim.Run(0.5)
    assert by_id(ns.Game.obs.quests)[61]["trivial"]

    # Follow: the client super-tracks and watches it, and the same frame's obs has it; false: none.
    ns.Game.Command(L.table_from({"kind": "follow", "quest": 60}))
    sim.Step()
    assert (sim.superTracked, sim.watched, by_id(ns.Game.obs.quests)[60]["followed"]) == (60, 60, True)
    followed = ns.Game.obs.quests
    ns.Game.Command(L.table_from({"kind": "follow", "quest": 60}))  # again: nothing new
    sim.Step()
    assert held(ns.Game.obs.quests, followed)
    ns.Game.Command(L.table_from({"kind": "follow", "quest": False}))
    sim.Step()
    assert sim.superTracked == 0 and not any(q["followed"] for q in py(ns.Game.obs.quests))
    sim.superTracked = 62  # Blizzard's tracker: the next frame
    sim.Step()
    assert by_id(ns.Game.obs.quests)[62]["followed"]

    # The map hidden: not read (no garbage nor work for it); what came meanwhile read once it shows.
    sim.Slash("/mm toggle")
    sim.quests[63] = L.table_from({"title": "Wine Shop Advert", "level": 1, "map": ELWYNN, "x": 0.4, "y": 0.6,
                                   "complete": False, "objectives": L.table()})
    sim.FireEvent("QUEST_LOG_UPDATE")
    sim.Run(1)
    assert 63 not in by_id(ns.Game.obs.quests)
    sim.Slash("/mm toggle")
    sim.Run(0.1)
    assert 63 in by_id(ns.Game.obs.quests)

    # Another continent shown: its zones' quests too (and yours still).
    sim.quests[840] = L.table_from({"title": "Your Place in the World", "level": 1, "map": DUROTAR, "x": 0.5, "y": 0.5,
                                    "complete": False, "objectives": L.table()})
    sim.Run(0.2)
    assert 840 not in by_id(ns.Game.obs.quests)
    ns.UI.Motion.SetFollow(False)
    ns.UI.Motion.FitMap(1)
    sim.Run(0.1)
    assert sorted(by_id(ns.Game.obs.quests)) == [60, 61, 62, 63, 840]
    assert not errors(sim, ns), errors(sim, ns)


def test_offers_round_trip():
    L, sim, ns, G = client()
    held = L.eval("rawequal")
    asks = sim.asks
    G.Offers(L.table_from({
        ELWYNN: L.table_from([L.table_from(o) for o in (PRINCESS, FISHY, dict(LINEN, hidden=True), dict(NECKLACE, taken=True))]),
        WESTFALL: L.table_from([L.table_from(o) for o in (PIE, dict(PRINCESS, col=30.3, row=50.5))]),  # on Westfall too
        DUROTAR: L.table_from([L.table_from(offer(4641, "Your Place in the World", 41.0, 32.0))])}))
    sim.Step()
    zones = [z.uiMapID for z in ns.Atlas.Zones(0).values()]
    assert not py(ns.Game.obs.offers) and dict(asks) == {z: 1 for z in zones}  # asked, not answered yet
    sim.Run(0.5)
    offers = by_id(ns.Game.obs.offers, "questID")
    assert sorted(offers) == [22, 40, 88]  # hidden and in progress skipped, Princess once
    assert offers[40]["line"] == "The Lost Guards" and "line" not in offers[88]
    pos = offers[88]["pos"]
    assert pos["inst"] == 0 and abs(pos["col"] - PRINCESS["col"]) < 1e-9 and abs(pos["row"] - PRINCESS["row"]) < 1e-9
    assert dict(asks) == {z: 1 for z in zones}  # once a map

    # Tracking hidden quests (the client's MINIMAP_UPDATE_TRACKING): the hidden one too; nothing new: the same table.
    sim.trackingHidden = True
    sim.FireEvent("MINIMAP_UPDATE_TRACKING")
    sim.Run(0.4)
    assert sorted(by_id(ns.Game.obs.offers, "questID")) == [22, 40, 83, 88]
    same = ns.Game.obs.offers
    sim.FireEvent("QUEST_LOG_UPDATE")
    sim.FireEvent("QUESTLINE_UPDATE", False)
    sim.Run(0.4)
    assert held(ns.Game.obs.offers, same) and dict(asks) == {z: 1 for z in zones}
    sim.FireEvent("QUESTLINE_UPDATE", True)  # the client wants every map asked again
    sim.Run(0.4)
    assert dict(asks) == {z: 2 for z in zones}

    # Kalimdor shown: its zones', asked then, and none of Elwynn's.
    sim.Run(0.2)
    ns.UI.Motion.SetFollow(False)
    ns.UI.Motion.FitMap(1)
    sim.Run(0.5)
    assert sorted(by_id(ns.Game.obs.offers, "questID")) == [4641] and asks[DUROTAR] == 1
    assert not errors(sim, ns), errors(sim, ns)


def test_tooltip_round_trip():
    L, sim, ns, G = client()
    tip, state, same = G.GameTooltip, sim.state, L.eval("rawequal")
    owner = G.CreateFrame("Frame", None, G.UIParent)
    owner.SetSize(owner, 20, 20)
    owner.SetPoint(owner, "CENTER")

    def portraits():
        return {v.portrait for v in state.values() if v.portrait}

    # Portraits drawn from the units met: mouseover, target, nameplates; creatures only, each once.
    units = sim.units
    units.mouseover = L.table_from({"name": "Kobold Vermin", "guid": "Creature-0-1-0-1-6-0000000001"})
    units.target = L.table_from({"name": "Kobold Worker", "guid": "Creature-0-1-0-1-257-0000000002"})
    units.nameplate1 = L.table_from({"name": "Ally", "guid": "Player-1-00000002"})
    units.nameplate2 = L.table_from({"name": "Kobold Vermin", "guid": "Creature-0-1-0-1-6-0000000003"})
    sim.FireEvent("UPDATE_MOUSEOVER_UNIT")
    sim.FireEvent("PLAYER_TARGET_CHANGED")
    sim.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
    sim.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate2")
    assert portraits() == {"Creature-0-1-0-1-6-0000000001", "Creature-0-1-0-1-257-0000000002"}

    # UI's tooltip, a mob line each: the met one's portrait over a dark disc in place of its icon.
    sword = "|T135274:14:14:0:0:64:64:5:59:5:59|t"
    tip.SetOwner(tip, owner, "ANCHOR_RIGHT")
    for line in ("Kobold Candles", "    " + sword + " |cffffffffKobold Vermin|r 1-2", "    " + sword + " |cffffffffKobold Miner|r 3"):
        tip.AddLine(tip, line)
    tip.Show(tip)
    for npc, line in ((6, 2), (475, 3)):
        ns.Game.Command(L.table_from({"kind": "tooltip", "owner": owner, "npc": npc, "line": line}))
    sim.Step()
    vermin, miner = tip.GetLeftLine(tip, 2), tip.GetLeftLine(tip, 3)
    assert vermin.GetText(vermin).startswith("    |TInterface\\CharacterFrame\\TempPortraitAlphaMask:14:14:")
    assert vermin.GetText(vermin).endswith("|t |cffffffffKobold Vermin|r 1-2")
    assert miner.GetText(miner) == "    " + sword + " |cffffffffKobold Miner|r 3"  # not met: UI's icon stays
    tex = next(k for k, v in state.items() if v.portrait == "Creature-0-1-0-1-6-0000000001")
    point = tex.GetPoint(tex, 1)
    assert tex.IsVisible(tex) and same(tex.GetParent(tex), tip) and point[0] == "LEFT" and same(point[1], vermin)
    probe = G.UIParent.CreateFontString(G.UIParent)
    probe.SetFont(probe, *vermin.GetFont(vermin))
    probe.SetText(probe, "    ")
    assert point[3] == probe.GetStringWidth(probe)
    tip.SetOwner(tip, owner, "ANCHOR_RIGHT")  # cleared: taken back
    assert not tex.IsShown(tex)

    # A member's tooltip: name in its class colour, level and class, dead; owner false hides it.
    sim.group = L.table_from(["party1"])
    units.party1 = L.table_from({"name": "Ally", "class": "PRIEST", "level": 12, "dead": True, "guid": "Player-1-00000002"})
    ns.Game.Command(L.table_from({"kind": "tooltip", "owner": owner, "anchor": "ANCHOR_RIGHT", "member": "Player-1-00000002"}))
    sim.Step()
    lines = [tip.GetLeftLine(tip, i).GetText(tip.GetLeftLine(tip, i)) for i in range(1, tip.NumLines(tip) + 1)]
    assert tip.IsShown(tip) and tip.IsOwned(tip, owner) and lines == ["Ally", "Level 12 PRIEST", "|cff808080Dead|r"]
    ns.Game.Command(L.table_from({"kind": "tooltip", "owner": False}))
    sim.Step()
    assert not tip.IsShown(tip)

    # At most 300 a session.
    L.execute("""for i = 1, 310 do
        Sim.units.nameplate3 = { guid = "Creature-0-1-0-1-" .. (1000 + i) .. "-0000000004" }
        Sim.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate3")
    end""")
    assert len(portraits()) == 300
    assert not errors(sim, ns), errors(sim, ns)


def test_streams_are_part_output():
    """fixtures/streams/quests.lua and offers.lua are what the parts hand over, recorded from the sim."""
    for name, story in (("quests", quests_story), ("offers", offers_story)):
        parts, source = record(story, name)
        with open(os.path.join(STREAMS, name + ".lua")) as f:
            assert f.read() == source, f"{name}: run tools/tests/test_quest_parts.py to record it again"
        assert len(parts) >= 4, name


if __name__ == "__main__":
    for name, story in (("quests", quests_story), ("offers", offers_story)):
        parts, source = record(story, name)
        with open(os.path.join(STREAMS, name + ".lua"), "w") as f:
            f.write(source)
        print(f"{name}: {len(parts)} tables handed over")
