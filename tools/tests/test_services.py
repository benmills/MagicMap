"""Town services and the remembered blips on the simulated client (docs/v1-plan.md M4.3; parity F21, S51).

  test_services: Known("services"), QuestieDB's NPCs with a service (made-up rows: CI has none), friendly to you,
    each its tracking icon and title, once the map has shown at zoom 60, not at 59 (Blips.lua:479); a tracking
    type off hides its kind (Trainer both kinds of trainer: Blips.lua:561-570) and the remembered of it too; a
    remembered one where a service of its name is isn't listed (Blips.lua:644-650). Drawn on the blips layer from
    zoom 60 with their title and "Not in sight", but within the sensor's word around you (Blips.lua:625-650).
  test_services_data: with QuestieDB's data, Goldshire's innkeeper at the Lion's Pride Inn.

obs.tracking is Game's (M4.1's game/parts/Tracking.lua): until it's here, the test's own part reads it so.
"""
import pytest

from sim import START, YD
from test_addon import boot, errors

# name, subName, faction, npcFlags, yards east and north of where you log in (START)
NPCS = {1001: ("Innkeeper Farley", "Innkeeper", "A", 128 + 2, 400, 10),
        1002: ("Lyria Du Lac", "Warrior Trainer", "A", 16, 30, 0),
        1003: ("Kurran Steele", "Herbalism Trainer", "AH", 16, -30, 0),
        1004: ("Smith Argus", "Weaponsmith", "A", 4 + 16384, 0, -40),
        1005: ("Horde Banker", "Banker", "H", 256, 0, 30),
        1006: ("Brog Hamfist", "General Supplies", "A", 4, 10, 10)}
STUB = """local Atlas, rows, c, r, yd = ...
local npcs = {}
for id, x in pairs(rows) do
    npcs[id] = { id = id, name = x[1], subName = x[2], faction = x[3], flags = x[4], col = c + x[5] * yd, row = r - x[6] * yd }
end
Atlas.Npc = function(id) return npcs[id] end
Atlas.ServiceSpawns = function(inst, step)
    local index = {}
    for id, n in pairs(npcs) do
        local svc = false
        for _, b in ipairs({ 16, 128, 256, 2048, 4096, 8192, 16384 }) do
            if n.flags % (b * 2) >= b then svc = true end
        end
        if inst == 0 and svc then
            local key = math.floor(n.col) * 64 + math.floor(n.row)
            index[key] = index[key] or {}
            local b = index[key]
            b[#b + 1], b[#b + 2], b[#b + 3] = id, n.col, n.row
        end
    end
    return index
end"""
SAVED = """MagicMap2DB = { UI = { _v = 1, shown = false, zoom = 59, window = { left = 600, top = 800, w = 720, h = 520 } },
    Model = { _v = 1, rares = {}, blips = { [0] = {
        ["Mailbox:2045:3183"] = { name = "Mailbox", icon = 136459, col = 31.95 + 300 * %(yd)r, row = 49.75, t = 1 },
        ["Innkeeper Farley:2093:3183"] = { name = "Innkeeper Farley", icon = 136458, col = 31.95 + 410 * %(yd)r,
            row = 49.75 - 10 * %(yd)r, t = 1 } } } } }"""


def names(ns, kind):
    return sorted(e.name for e in ns.Model.Known(kind)[0].values())


def drawn(ns):
    """The blips layer's pins shown (their minimum zoom's frame too): name, title."""
    lay = ns.UI.Blips
    p = lay.front and lay.front.pools.pin
    pins = [p[i] for i in range(1, p.n + 1)] if p else []
    return sorted((o.entry.name, o.entry.text) for o in pins if o.on.GetAlpha(o.on) > 0)


def test_services():
    L, sim, ns = boot(SAVED % {"yd": YD})
    G = L.globals()
    L.execute(STUB, ns.Atlas, L.table_from({k: L.table_from(v) for k, v in NPCS.items()}), START[0], START[1], YD)
    for name, texture, f in (("Find Trainers", 136463, 16), ("Repair", 136465, 512)):
        G.Sim.tracking[len(G.Sim.tracking) + 1] = L.table_from({"name": name, "texture": texture, "active": True,
                                                                "filterID": f})
    sim.Slash("/mm toggle")
    sim.Run(3)
    assert ns.UI.Camera.cam.zoom == 59 and names(ns, "services") == []  # not gathered below town scale
    assert names(ns, "remembered") == ["Innkeeper Farley", "Mailbox"] and drawn(ns) == []
    ns.UI.Motion.SetZoom(60)
    sim.Run(4)  # (the blips layer asks for them: gathered in a job)
    got = {e.name: e for e in ns.Model.Known("services")[0].values()}
    assert sorted(got) == ["Innkeeper Farley", "Kurran Steele", "Lyria Du Lac", "Smith Argus"]  # friendly, a service
    assert {k: (e.icon.texture, e.service, e.text, e.npc, e.live, e.kind) for k, e in got.items()} == {
        "Innkeeper Farley": (136458, "innkeeper", "Innkeeper", 1001, False, "services"),
        "Lyria Du Lac": (136455, "classtrainer", "Warrior Trainer", 1002, False, "services"),
        "Kurran Steele": (136463, "trainer", "Herbalism Trainer", 1003, False, "services"),
        "Smith Argus": (136465, "repair", "Weaponsmith", 1004, False, "services")}
    assert names(ns, "remembered") == ["Mailbox"]  # the innkeeper: Atlas's service of the name is 10 yd off
    # Drawn on the blips layer from zoom 60, but those within the sensor's word around you (Blips.lua:628-650).
    assert drawn(ns) == [("Innkeeper Farley", "Innkeeper"), ("Mailbox", None)]
    # Tracking off: its kind hidden, the remembered of it too; Trainer: both kinds of trainer.
    for name in ("Innkeeper", "Find Trainers", "Mailbox"):
        i = next(i for i, t in G.Sim.tracking.items() if t.name == name)
        G.C_Minimap.SetTracking(i, False)
    sim.Run(0.5)
    assert names(ns, "services") == ["Smith Argus"] and names(ns, "remembered") == [] and drawn(ns) == []
    i = next(i for i, t in G.Sim.tracking.items() if t.name == "Find Trainers")
    G.C_Minimap.SetTracking(i, True)
    sim.Run(0.5)
    assert names(ns, "services") == ["Kurran Steele", "Lyria Du Lac", "Smith Argus"]
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_services_data():
    L, sim, ns = boot(SAVED % {"yd": YD})
    if not ns.Data.Npcs:
        pytest.skip("no QuestieDB-derived data (tools/gen_questie.py)")
    sim.Slash("/mm toggle")
    ns.UI.Motion.SetZoom(60)
    sim.Run(1)
    ns.Model.Known("services")
    sim.Run(4)
    farley = [e for e in ns.Model.Known("services")[0].values() if e.name == "Innkeeper Farley"]
    assert len(farley) == 1 and farley[0].icon.texture == 136458 and farley[0].service == "innkeeper"
    assert abs(farley[0].pos.col - START[0]) < 0.1 and abs(farley[0].pos.row - START[1]) < 0.1
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
