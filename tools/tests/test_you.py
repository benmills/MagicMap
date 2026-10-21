"""The you part's round trip (docs/v1-plan.md M1.10): what the client says of you
(game/parts/You.lua) reaches Model.you each frame, nil where it gives nothing."""
from test_addon import boot, errors


def fields(you):
    return (you.uiMap, you.level, you.faction, you.dead, you.ghost, you.combat)


def test_you_round_trip():
    L, sim, ns = boot()
    sim.Run(0.2)
    you = ns.Model.you
    assert fields(you) == (1429, 5, "A", False, False, False)  # Elwynn Forest

    # Level up, Horde, dead then released, in combat: the next frame has it.
    sim.units.player.level, sim.faction, sim.units.player.dead, sim.inCombat = 6, "Horde", True, True
    sim.Step()
    assert fields(you) == (1429, 6, "H", True, False, True)
    sim.ghost = True
    sim.Step()
    assert you.ghost is True

    # Into Westfall: uiMap follows on the client's zone event, and is read again a second later (an
    # event can come before the zone changes); in a micro map (Fargodeep Mine), every second.
    sim.FireEvent("ZONE_CHANGED_NEW_AREA")
    sim.Step()
    sim.player.col, sim.player.row = 29.0, 52.0
    sim.Step()
    assert you.uiMap == 1429
    sim.Run(1.1)
    assert you.uiMap == 1436
    sim.player.col, sim.player.row, sim.indoors = 31.8, 50.3, True
    sim.FireEvent("ZONE_CHANGED_INDOORS")
    sim.Run(1.5)  # (past the event's second read)
    assert you.uiMap == 1601
    sim.player.col, sim.player.row, sim.indoors = 29.0, 52.0, False  # out, no event
    sim.Run(1.1)
    assert you.uiMap == 1436

    # An instance with no map of its own: no uiMap, no position; the rest still known.
    sim.restricted, sim.player.inst, sim.faction = True, 36, "Neutral"
    sim.FireEvent("PLAYER_ENTERING_WORLD", False, False)
    sim.Run(0.2)
    assert fields(you) == (None, 6, None, True, True, True) and you.inst == 36
    assert ns.Game.obs.you.col is None and you.stale
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
