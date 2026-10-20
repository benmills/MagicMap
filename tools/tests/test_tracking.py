"""Blizzard's duplicate tracking on the sim (docs/v1-plan.md M4.2, game/Tracking.lua): its flight master,
quest objective and point-of-interest tracking off while the takeover senses outdoors with our layer of
the same on, back on otherwise (the layer off within 2 s, the whole Minimap, the window hidden, logout),
SavedGame.trackingOff naming those Game turned off; after a crash, a session's leftovers come back at
the next login, or at MINIMAP_UPDATE_TRACKING once the client has sent its state. Game reads UI's View
(ADR 0003): its layers flight, quests and pois (ui/Sockets.lua), its renderer (ui/IndoorArt.lua)."""
from sim import TEST_UI
from test_addon import boot, errors

FLIGHT, QUESTS, POIS = 8, 65536, 8192  # Enum.MinimapTrackingFilter

def active(sim):
    """filter id (or spell name) -> active, every tracking type the client has."""
    return {t.filterID or t.name: t.active for t in sim.tracking.values()}


def off(L):
    return sorted(L.globals().MagicMap2DB.Game.trackingOff.keys())


def test_duplicates_off():
    """Off while sensing with our layer on; each back on as it stops being so; only Game's own turned back."""
    L, sim, ns = boot()
    was = active(sim)
    sim.Run(1)
    assert active(sim) == was and off(L) == [], "the window hidden: left as the user has them"

    sim.Slash("/mm toggle")
    sim.Step()
    assert ns.Game.minimap.engaged
    now = active(sim)
    assert not now[FLIGHT] and not now[QUESTS] and not now[POIS], "off the frame it engaged"
    assert {k: v for k, v in now.items() if k not in (FLIGHT, QUESTS)} == {k: v for k, v in was.items() if k not in (FLIGHT, QUESTS)}
    assert off(L) == [FLIGHT, QUESTS], "the user's own POI off: not Game's"

    ns.UI.Engine.SetLayer("flight", False)  # our flight masters off: Blizzard's back within 2 s (MinimapTakeover.lua:266)
    sim.Run(2.1)
    assert active(sim)[FLIGHT] and not active(sim)[QUESTS] and off(L) == [QUESTS]

    sim.indoors = True  # a hut, the small window: the whole Minimap (its floor plan), the user's tracking at once
    sim.Step()
    assert ns.UI.View().renderer == "blizzard" and active(sim)[QUESTS] and off(L) == []
    sim.indoors = False
    sim.Step()
    assert ns.UI.View().renderer == "ours" and not active(sim)[QUESTS] and off(L) == [QUESTS]

    sim.Slash("/mm toggle")  # the window hidden: released, back that frame
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
    sim.Slash("/mm toggle")
    sim.Run(1)
    left = off(L)
    assert left == [FLIGHT, QUESTS] and not active(sim)[FLIGHT] and not active(sim)[QUESTS]
    # The crash: the saved part as it stood, the client's tracking as it was.
    crashed = "".join(f"[{i}] = true, " for i in left)
    state = "".join(f"Sim.tracking[{i}].active = {str(t.active).lower()}; " for i, t in sim.tracking.items())
    saved = TEST_UI + f"; MagicMap2DB.Game = {{ _v = 1, trackingOff = {{ {crashed}}} }}; " + state

    L, sim, ns = boot(saved)
    assert active(sim)[FLIGHT] and active(sim)[QUESTS] and off(L) == [], "back at login"

    L, sim, ns = boot(saved + "Sim.later, Sim.tracking = Sim.tracking, {}")  # its state not sent yet
    sim.Run(1)
    assert off(L) == [FLIGHT, QUESTS], "kept until the client says"
    sim.tracking = sim.later
    sim.FireEvent("MINIMAP_UPDATE_TRACKING")
    assert active(sim)[FLIGHT] and active(sim)[QUESTS] and off(L) == []

    sim.Slash("/mm toggle")  # off again; a logout puts them back (the client saves both after)
    sim.Run(1)
    assert off(L) == [FLIGHT, QUESTS]
    sim.FireEvent("PLAYER_LOGOUT")
    assert active(sim)[FLIGHT] and active(sim)[QUESTS] and off(L) == []
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
