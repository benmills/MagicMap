"""Blizzard's duplicate tracking on the sim (docs/v1-plan.md M4.2, game/Tracking.lua): its flight master,
quest objective and point-of-interest tracking off while the takeover senses outdoors with our layer of
the same on, back on otherwise (the layer off within 2 s, the whole Minimap, the window hidden, logout),
SavedGame.trackingOff naming those Game turned off; after a crash, a session's leftovers come back at
the next login, or at MINIMAP_UPDATE_TRACKING once the client has sent its state. Game is fed Views
(ADR 0003): UI's own, its layers and renderer ours (UI publishes flight, quests and pois at M4.4)."""
from sim import TEST_UI
from test_addon import boot, errors

FLIGHT, QUESTS, POIS = 8, 65536, 8192  # Enum.MinimapTrackingFilter

# UI's View, but its layers and renderer the test's (Game reads the same table each frame: types/view.lua).
FEED = """function(ns, layers)
    local mine = setmetatable({ layers = layers, renderer = "ours" }, { __index = ns.UI.View() })
    ns.UI.View = function() return mine end
    return mine
end"""


def feed(L, ns, **layers):
    return L.eval(FEED)(ns, L.table_from(layers))


def active(sim):
    """filter id (or spell name) -> active, every tracking type the client has."""
    return {t.filterID or t.name: t.active for t in sim.tracking.values()}


def off(L):
    return sorted(L.globals().MagicMapAtlasDB.Game.trackingOff.keys())


def test_duplicates_off():
    """Off while sensing with our layer on; each back on as it stops being so; only Game's own turned back."""
    L, sim, ns = boot()
    view = feed(L, ns, blips=True, flight=True, quests=True, pois=True)
    was = active(sim)
    sim.Run(1)
    assert active(sim) == was and off(L) == [], "the window hidden: left as the user has them"

    sim.Slash("/mma toggle")
    sim.Step()
    assert ns.Game.minimap.engaged
    now = active(sim)
    assert not now[FLIGHT] and not now[QUESTS] and not now[POIS], "off the frame it engaged"
    assert {k: v for k, v in now.items() if k not in (FLIGHT, QUESTS)} == {k: v for k, v in was.items() if k not in (FLIGHT, QUESTS)}
    assert off(L) == [FLIGHT, QUESTS], "the user's own POI off: not Game's"

    view.layers.flight = None  # our flight masters off: Blizzard's back within 2 s (MinimapTakeover.lua:266)
    sim.Run(2.1)
    assert active(sim)[FLIGHT] and not active(sim)[QUESTS] and off(L) == [QUESTS]

    view.renderer = "blizzard"  # the whole Minimap (its floor plan): the user's tracking, at once
    sim.Step()
    assert active(sim)[QUESTS] and off(L) == []
    view.renderer = "ours"
    sim.Step()
    assert not active(sim)[QUESTS] and off(L) == [QUESTS]

    sim.Slash("/mma toggle")  # the window hidden: released, back that frame
    sim.Step()
    assert not ns.Game.minimap.engaged and active(sim) == was and off(L) == []
    sim.Run(3)
    assert active(sim) == was, "released: left be"
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_restored_after_crash():
    """A session turns them off and the client goes down (nothing put back): the next login turns them
    back on; and where the client hasn't sent its state at login, at MINIMAP_UPDATE_TRACKING once it has.
    A logout puts them back itself."""
    L, sim, ns = boot()
    feed(L, ns, flight=True, quests=True)
    sim.Slash("/mma toggle")
    sim.Run(1)
    left = off(L)
    assert left == [FLIGHT, QUESTS] and not active(sim)[FLIGHT] and not active(sim)[QUESTS]
    # The crash: the saved part as it stood, the client's tracking as it was.
    crashed = "".join(f"[{i}] = true, " for i in left)
    state = "".join(f"Sim.tracking[{i}].active = {str(t.active).lower()}; " for i, t in sim.tracking.items())
    saved = TEST_UI + f"; MagicMapAtlasDB.Game = {{ _v = 1, trackingOff = {{ {crashed}}} }}; " + state

    L, sim, ns = boot(saved)
    assert active(sim)[FLIGHT] and active(sim)[QUESTS] and off(L) == [], "back at login"

    L, sim, ns = boot(saved + "Sim.later, Sim.tracking = Sim.tracking, {}")  # its state not sent yet
    sim.Run(1)
    assert off(L) == [FLIGHT, QUESTS], "kept until the client says"
    sim.tracking = sim.later
    sim.FireEvent("MINIMAP_UPDATE_TRACKING")
    assert active(sim)[FLIGHT] and active(sim)[QUESTS] and off(L) == []

    feed(L, ns, flight=True, quests=True)  # off again; a logout puts them back (the client saves both after)
    sim.Slash("/mma toggle")
    sim.Run(1)
    assert off(L) == [FLIGHT, QUESTS]
    sim.FireEvent("PLAYER_LOGOUT")
    assert active(sim)[FLIGHT] and active(sim)[QUESTS] and off(L) == []
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
