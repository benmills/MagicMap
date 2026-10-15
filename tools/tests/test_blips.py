"""The walking skeleton through all five pieces, on Minimap blips:

  test_blips_end_to_end (the sim): Game takes the Minimap per View (an unseen sensor
  under the window), senses its blips, Model merges them (Known("blips")), UI draws
  them and publishes View, Game releases the Minimap on "blizzard"; then a /reload
  (boot with the first boot's SavedVariables) brings back Model's remembered blips
  and UI's layer toggles.

  test_blips_replay (Model alone, plain Lua): the recorded observation stream
  (fixtures/blips_stream.lua, from this scenario with /mma record) replayed into
  Model: one entry per blip across sweeps, a remembered one a sweep missed is
  forgotten, one walked away from is kept and survives a reload of Model's saved part.

  .venv/bin/python tools/tests/test_blips.py   # records the scenario again into the fixture
"""
import math
import os
import sys

TESTS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(TESTS))  # (run as a script: luacheck, for test_addon)

from lupa import lua51  # noqa: E402

from test_addon import boot, errors  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(TESTS))
FIXTURE = os.path.join(TESTS, "fixtures", "blips_stream.lua")
YD = 3 / 1600  # a yard in tiles
START = (31.95, 49.75)
# name, yards east and north of the start
BLIPS = [("Mailbox", 40, 20), ("Mailbox", -50, -70), ("Peacebloom", -60, 30)]
MAILBOX = 136459  # the sim's Mailbox tracking texture


def lua_tools(L):
    return L.eval("function(path) return assert(loadfile(path))() end")(os.path.join(TESTS, "replay.lua"))


def put_blips(L, sim, ns, blips):
    """Sim.minimapBlips (yards) from (name, yards east, yards north) of the start."""
    L.eval("""function(Sim, Atlas, list, c, r, yd)
        local out = {}
        for i = 1, #list do
            local b = list[i]
            local north, west = Atlas.TileToWorld(c + b[2] * yd, r - b[3] * yd)
            out[i] = { b[1], north, west }
        end
        Sim.minimapBlips = out
    end""")(sim, ns.Atlas, L.table_from([L.table_from(b) for b in blips]), START[0], START[1], YD)


def blips(ns):
    return [dict(name=b.name, live=b.live, col=b.pos.col, row=b.pos.row, icon=b.icon and b.icon.texture)
            for b in ns.Model.Known("blips")[0].values()]


def near(b, east, north, yd=3):
    return math.hypot((b["col"] - START[0]) / YD - east, (START[1] - b["row"]) / YD - north) < yd


def scenario(L, sim, ns, check=lambda *_: None):
    """Stand among the blips with the map shown; one mailbox goes; walk 600 yd east and back off."""
    put_blips(L, sim, ns, BLIPS)
    sim.Slash("/mma record on")
    sim.Slash("/mma map")
    sim.Run(3)
    check("still")
    put_blips(L, sim, ns, BLIPS[:1] + BLIPS[2:])  # the second mailbox: gone (as if mismeasured)
    sim.Run(2)
    check("gone")
    sim.player.facing, sim.player.speed = math.pi / 2, 14  # east (the sim's facing), mounted
    for _ in range(45):
        sim.Run(1)
        check("walking")
    sim.player.speed = 0
    sim.Run(1)
    check("away")
    sim.Slash("/mma record off")


def test_blips_end_to_end():
    L, sim, ns = boot()
    G, Game, UI = L.globals(), ns.Game, ns.UI
    same = L.eval("function(a, b) return a == b end")
    seen = {}

    def check(stage):
        got = blips(ns)
        mailboxes = [b for b in got if b["name"] == "Mailbox"]
        if stage == "still":
            # Game: the Minimap taken per View, an unseen sensor under the window, still, sensing.
            m, mm = Game.minimap, G.Minimap
            assert m.engaged and m.sensor and m.still and Game.obs.minimap.sensing
            assert same(mm.GetParent(mm), G.UIParent) and mm.GetAlpha(mm) == 0 and not G.MinimapCluster.IsShown(G.MinimapCluster)
            assert not same(sim.minimapButton.GetParent(sim.minimapButton), mm)  # what hung on it waits on the stand-in
            v = UI.View()
            assert v.v == 1 and v.minimap == "ours" and v.window.shown and v.window.still and v.layers.blips
            p = v.window.place
            cx, cy = mm.GetCenter(mm)
            assert abs(cx - (p.left + p.w / 2)) < 1 and abs(cy - (p.top - p.h / 2)) < 1
            assert v.diag().map.shown
            # Model: each blip once, live, where it is; the mailboxes with the game's tracking icon.
            assert sorted(b["name"] for b in got) == ["Mailbox", "Mailbox", "Peacebloom"], got
            for name, east, north in BLIPS:
                assert any(b["name"] == name and b["live"] and near(b, east, north) for b in got), (name, got)
            assert all(b["icon"] == MAILBOX for b in mailboxes)
            assert next(b for b in got if b["name"] == "Peacebloom")["icon"] is None
            assert len(list(G.MagicMapAtlasDB.Model.blips[0].keys())) == 2  # mailboxes remembered (they have an icon)
            # UI: drawn, the icon or a gold dot.
            sim.Run(0.2)
            front = UI.Blips.front
            pins = [front.pools.pin[i] for i in range(1, front.pools.pin.n + 1)]
            textures = sorted(str(sim.state[t].texture) for t in pins)
            assert textures == [str(MAILBOX), str(MAILBOX), "Interface\\COMMON\\Indicator-Yellow"], textures
        elif stage == "gone":
            assert len(mailboxes) == 1 and near(mailboxes[0], 40, 20), got  # forgotten: a sweep missed it
            assert len(list(G.MagicMapAtlasDB.Model.blips[0].keys())) == 1
        elif stage == "walking":
            assert len(mailboxes) == 1, got  # one entry across sweeps, measured on the move or not
            seen["remembered"] = seen.get("remembered") or not mailboxes[0]["live"]
        elif stage == "away":
            assert [b["name"] for b in got] == ["Mailbox"] and not got[0]["live"] and near(got[0], 40, 20), got

    scenario(L, sim, ns, check)
    assert seen["remembered"]
    assert len(G.MagicMapAtlasDB.recording.obs) > 20

    # A UI-only toggle, saved; and Blizzard's minimap back: everything put back.
    sim.Slash("/mma layer labels")
    sim.Slash("/mma minimap blizzard")
    sim.Step()
    mm = G.Minimap
    assert not Game.minimap.engaged and Game.Blips() is None and UI.View().minimap == "blizzard"
    assert same(mm.GetParent(mm), G.MinimapCluster) and mm.GetAlpha(mm) == 1 and G.MinimapCluster.IsShown(G.MinimapCluster)
    assert same(sim.minimapButton.GetParent(sim.minimapButton), mm) and mm.GetWidth(mm) == 140
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))

    # /reload: the SavedVariables written at logout, read by a fresh client.
    sim.FireEvent("PLAYER_LOGOUT")
    saved = "MagicMapAtlasDB = " + lua_tools(L).Dump(G.MagicMapAtlasDB)
    L2, sim2, ns2 = boot(saved)
    sim2.Run(0.5)
    got = blips(ns2)
    assert [b["name"] for b in got] == ["Mailbox"] and not got[0]["live"] and near(got[0], 40, 20), got
    assert ns2.UI.Map.LayerOn("labels") is False and ns2.UI.Map.LayerOn("blips") is True
    assert ns2.UI.View().minimap == "blizzard"
    assert not errors(sim2, ns2), "\n\n".join(errors(sim2, ns2))


def test_blips_replay():
    L = lua51.LuaRuntime(unpack_returned_tuples=True)
    tools = lua_tools(L)
    stream = L.eval("function(path) return assert(loadfile(path))() end")(FIXTURE)
    model = tools.Model(ROOT)
    saved = L.eval("{ _v = 1, rares = {}, blips = {} }")
    model.Load(saved)
    oracles = L.table()
    second = None  # the mailbox that goes: remembered, then forgotten
    for i in range(1, len(stream) + 1):
        model.Observe(stream[i], oracles)
        got = blips(type("ns", (), {"Model": model}))
        mailboxes = [b for b in got if b["name"] == "Mailbox"]
        assert len([b for b in mailboxes if near(b, 40, 20, 10)]) <= 1, got  # dedupe across sweeps
        if any(near(b, -50, -70) for b in mailboxes):
            second = second or "remembered"
        elif second:
            second = "forgotten"
    assert second == "forgotten"
    got = blips(type("ns", (), {"Model": model}))
    assert [b["name"] for b in got] == ["Mailbox"] and not got[0]["live"] and near(got[0], 40, 20), got
    # Persistence: its saved part, in a fresh Model.
    entry = next(iter(saved.blips[0].values()))
    assert entry.name == "Mailbox" and entry.icon == MAILBOX and entry.t > 0 and len(list(saved.blips[0].keys())) == 1
    fresh = tools.Model(ROOT)
    fresh.Load(L.execute("return " + tools.Dump(saved)))
    again = blips(type("ns", (), {"Model": fresh}))
    assert [(b["name"], b["live"]) for b in again] == [("Mailbox", False)] and near(again[0], 40, 20)


def record():
    """The scenario with /mma record on, its stream written to the fixture."""
    L, sim, ns = boot()
    scenario(L, sim, ns)
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
    obs = L.globals().MagicMapAtlasDB.recording.obs
    with open(FIXTURE, "w") as f:
        f.write("-- Recorded by tools/tests/test_blips.py (record()): /mma record over its scenario in the sim.\n")
        f.write("return " + lua_tools(L).Dump(obs) + "\n")
    print(f"{FIXTURE}: {len(obs)} observations")


if __name__ == "__main__":
    record()
