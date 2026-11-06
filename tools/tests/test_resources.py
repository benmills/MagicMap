"""Resources (#18) on the simulated client.

  test_keep_tracking: the tracker kept on (ui/Resources.lua, game/Keep.lua) comes back on with no clicks after death
  (not while dead or in combat), a loading screen and a /reload; one you turn off stays off till the game next drops
  it; one you pick yourself becomes the one kept; the gear's "Keep tracking" row picks one, or Off; a call the client
  turns down is tried five times, then left.

  test_resource_badges: herb and ore pins wear their difficulty (by your skill against the node's: red, orange,
  yellow, green, grey) top left and their letter bottom left; none for a node whose skill isn't known; each badge
  off in Settings > Resources.
"""
from sim import TEST_UI, put_blips
from test_addon import boot, errors
from test_blips import lua_tools
from test_gear import gear, items, sub

MINERALS = 2580


def tracking(L, sim):
    """{ name: active } of the client's tracking types."""
    return {t.name: t.active for t in sim.tracking.values()}


def drop(sim, name):
    """The game drops a tracker (no MINIMAP_UPDATE_TRACKING of ours: the client's own)."""
    for t in sim.tracking.values():
        if t.name == name:
            t.active = False
    sim.FireEvent("MINIMAP_UPDATE_TRACKING")


def test_keep_tracking():
    L, sim, ns = boot(TEST_UI)
    G = L.globals()
    L.execute("table.insert(Sim.tracking, 3, { name = 'Find Minerals', spellID = 2580, active = false, texture = 136025 })")
    sim.FireEvent("MINIMAP_UPDATE_TRACKING")
    sim.Run(1)
    Feel = ns.UI.Feel
    assert Feel.Get("resources.keep") == "auto" and ns.UI.Resources.Keep() == 2383  # Find Herbs: the first gathering one

    # Death drops it: not cast while dead, back once alive.
    sim.units.player.dead = True
    drop(sim, "Find Herbs")
    sim.FireEvent("PLAYER_DEAD")
    sim.Run(2)
    assert tracking(L, sim)["Find Herbs"] is False and not sim.trackingCalls
    sim.units.player.dead = False
    sim.FireEvent("PLAYER_ALIVE")
    sim.Run(1)
    assert tracking(L, sim)["Find Herbs"] is True and sim.trackingCalls == 1

    # A loading screen in combat: waits for the fight's end.
    drop(sim, "Find Herbs")
    sim.inCombat = True
    sim.FireEvent("PLAYER_ENTERING_WORLD", False, False)
    sim.Run(2)
    assert tracking(L, sim)["Find Herbs"] is False
    sim.inCombat = False
    sim.Run(1)
    assert tracking(L, sim)["Find Herbs"] is True

    # Turned off yourself: stays off (no drop since).
    for i, t in sim.tracking.items():
        if t.name == "Find Herbs":
            G.C_Minimap.SetTracking(i, False)
    sim.Run(20)
    assert tracking(L, sim)["Find Herbs"] is False

    # Another picked yourself (Blizzard's menu): the one kept now; a death brings it back, not Find Herbs.
    for i, t in sim.tracking.items():
        if t.name == "Find Minerals":
            G.C_Minimap.SetTracking(i, True)
    sim.Run(1)
    assert Feel.Get("resources.keep") == str(MINERALS) and ns.UI.Resources.Keep() == MINERALS
    drop(sim, "Find Minerals")
    sim.FireEvent("PLAYER_DEAD")
    sim.FireEvent("PLAYER_ALIVE")
    sim.Run(1)
    assert tracking(L, sim)["Find Minerals"] is True and tracking(L, sim)["Find Herbs"] is False

    # The gear's row: the one kept, a radio each tracker and Off.
    root, _ = gear(sim, ns)
    keep = sub(root, "Keep tracking: Find Minerals")
    assert items(keep) == [("radio", "Find Herbs"), ("radio", "Find Minerals"), ("radio", "Off")]
    radios = list(keep["items"].values())
    assert [r.isSelected() for r in radios] == [False, True, False]
    sim.Pick(radios[0])  # Find Herbs: auto's own, saved as auto; turned on at once
    sim.Run(1)
    assert Feel.Get("resources.keep") == "auto" and tracking(L, sim)["Find Herbs"] is True
    sim.Pick(radios[2])  # Off: none kept, nothing turned on after a drop
    drop(sim, "Find Herbs")
    sim.FireEvent("PLAYER_ENTERING_WORLD", False, False)
    sim.Run(2)
    assert Feel.Get("resources.keep") == "off" and tracking(L, sim)["Find Herbs"] is False

    # A /reload keeps the choice and turns it back on.
    Feel.Set("resources.keep", "auto")
    sim.FireEvent("PLAYER_LOGOUT")
    L, sim, ns = boot("MagicMap2DB = " + lua_tools(L).Dump(G.MagicMap2DB), reload=True)
    for t in sim.tracking.values():
        t.active = False
    sim.Run(1)
    assert tracking(L, sim)["Find Herbs"] is True

    # One the client turns down: five tries, further apart each time, then left till the next drop.
    sim.trackingRefused = True
    drop(sim, "Find Herbs")
    sim.FireEvent("PLAYER_ALIVE")
    calls = sim.trackingCalls or 0
    sim.Run(120)
    assert sim.trackingCalls - calls == 5
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


BADGES = """function(ns)
    local out = {}
    for _, lay in pairs(ns.UI.Engine.layers) do
        if lay.name == "blips" then
            local p = lay.front and lay.front.pools.pin
            for i = 1, p and p.n or 0 do
                local o = p[i]
                if o.entry and o:IsShown() then
                    local dot = o.dot and o.dot.vis and string.format("%.2f,%.2f,%.2f", o.dot.r, o.dot.g, o.dot.b) or false
                    out[o.entry.name] = { dot = dot, letter = o.letter and o.letter.vis and o.letter.text or false }
                end
            end
        end
    end
    return out
end"""
RED, ORANGE, YELLOW, GREEN, GREY = "1.00,0.10,0.10", "1.00,0.50,0.25", "1.00,1.00,0.00", "0.25,0.75,0.25", "0.50,0.50,0.50"


def test_resource_badges():
    L, sim, ns = boot("MagicMap2DB = { UI = { _v = 1 } }")
    L.execute("Sim.professions = { { name = 'Herbalism', rank = 60, line = 182 }, { name = 'Mining', rank = 240, line = 186, bonus = 10 } }")
    sim.FireEvent("SKILL_LINES_CHANGED")
    put_blips(L, sim, ns, [("Peacebloom", -40, 20), ("Mageroyal", 40, 20), ("Earthroot", 0, 45), ("Kingsblood", 0, -45),
                           ("Copper Vein", -40, -30), ("Rich Thorium Vein", 40, -30), ("Small Thorium Vein", 70, 0),
                           ("Hive Thistle", -70, 0)])
    sim.Slash("/mm toggle")
    sim.Run(8)
    got = {k: dict(v) for k, v in L.eval(BADGES)(ns).items()}
    assert got == {
        "Peacebloom": {"dot": GREEN, "letter": "P"},  # 60: 1 + 50 or more, under 1 + 100
        "Mageroyal": {"dot": ORANGE, "letter": "M"},  # 50 to 74
        "Earthroot": {"dot": YELLOW, "letter": "E"},  # 15 + 25 to 15 + 49
        "Kingsblood": {"dot": RED, "letter": "K"},  # under 125
        "Copper Vein": {"dot": GREY, "letter": "C"},  # Mining 250 with its bonus: past 1 + 100
        "Rich Thorium Vein": {"dot": RED, "letter": "T"},  # under 275
        "Small Thorium Vein": {"dot": ORANGE, "letter": "T"},  # 245 to 269
        "Hive Thistle": {"dot": False, "letter": "H"},  # Forever's own: its skill not known
    }, got

    Feel = ns.UI.Feel
    Feel.Set("resources.difficulty", False)
    sim.Run(1)
    got = {k: dict(v) for k, v in L.eval(BADGES)(ns).items()}
    assert all(v["dot"] is False for v in got.values()) and got["Peacebloom"]["letter"] == "P"
    Feel.Set("resources.letter", False)
    sim.Run(1)
    got = {k: dict(v) for k, v in L.eval(BADGES)(ns).items()}
    assert all(v == {"dot": False, "letter": False} for v in got.values()), got
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
