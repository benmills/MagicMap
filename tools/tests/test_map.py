"""The map window (ui/Map.lua and its layers) on the simulated client: /mma map
shows your continent around you, its layouts finish within their jobs, wheel
and drag move the camera, and nothing errors."""
from test_addon import boot, errors


def stats(m):
    live, made = m.Stats()
    return dict(live.items()), dict(made.items())


def test_map():
    L, sim, ns = boot()
    m = ns.UI.Map
    sim.Slash("/mma map")
    assert m.frame.IsShown(m.frame)
    sim.Run(1)
    assert m.inst == 0 and abs(m.cam.cx - 31.95) < 1e-6 and abs(m.cam.cy - 49.75) < 1e-6
    for layer in m.layers.values():
        assert layer.front and not layer.busy, layer.name
    live, _ = stats(m)
    assert live["tex"] > 10 and live["line"] > 10 and live["font"] > 0, live

    # Wheel in about the cursor (following: about you), drag pans and stops following.
    zoom = m.cam.zoom
    sim.Wheel(m.view, 1)
    assert m.cam.zoom > zoom and abs(m.cam.cx - 31.95) < 1e-6
    sim.Drag(m.view, 120, -80)
    assert not m.follow and m.cam.cx < 31.95 - 0.5
    sim.Run(1)
    for layer in m.layers.values():
        assert layer.front.zoom == m.cam.zoom, layer.name

    # Out to the whole continent, and back to you on a right click.
    for _ in range(20):
        sim.Wheel(m.view, -1)
        sim.Step()
    sim.Run(2)
    assert m.cam.zoom == 4
    live, _ = stats(m)
    assert live["font"] > 0, live
    sim.Click(m.view, "RightButton")
    assert m.follow
    sim.Slash("/mma mapstats")
    sim.Slash("/mma map")
    assert not m.frame.IsShown(m.frame)
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_rares():
    """A pin kind added afterwards: Known("rares") (Atlas's rare spawns, the shown map only) drawn by its layer."""
    import pytest
    L, sim, ns = boot()
    if not ns.Data.Npcs:
        pytest.skip("no QuestieDB-derived data (tools/gen_questie.py)")
    m = ns.UI.Map
    sim.Slash("/mma map")
    sim.Run(2)
    got = list(ns.Model.Known("rares")[0].values())
    assert got and all(r.kind == "rares" and r.pos.inst == 0 and not r.live for r in got)
    front = m.layers[[l.name for l in m.layers.values()].index("rares") + 1].front
    atlases = {sim.state[front.pools.pin[i]].atlas for i in range(1, front.pools.pin.n + 1)}
    assert atlases and atlases <= {"vignettekill", "vignettekillelite"}, atlases
    sim.Slash("/mma layer rares")
    assert m.LayerOn("rares") is False and m.toggles.rares is False
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
