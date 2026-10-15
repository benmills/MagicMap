"""The map window (ui/Window.lua, ui/Engine.lua and the layers) on the simulated client: /mma map
shows your continent around you, its layouts finish within their jobs, wheel
and drag move the camera, and nothing errors."""
from test_addon import boot, errors


def stats(e):
    live, made = e.Stats()
    return dict(live.items()), dict(made.items())


def test_map():
    L, sim, ns = boot()
    e, c, w = ns.UI.Engine, ns.UI.Camera, ns.UI.Window
    sim.Slash("/mma map")
    assert w.frame.IsShown(w.frame)
    sim.Run(1)
    assert c.inst == 0 and abs(c.cam.cx - 31.95) < 1e-6 and abs(c.cam.cy - 49.75) < 1e-6
    for layer in e.layers.values():
        assert layer.front and not layer.busy, layer.name
    live, _ = stats(e)
    assert live["tex"] > 10 and live["line"] > 10 and live["font"] > 0, live

    # Wheel in about the cursor (following: about you), drag pans and stops following.
    zoom = c.cam.zoom
    sim.Wheel(w.view, 1)
    assert c.cam.zoom > zoom and abs(c.cam.cx - 31.95) < 1e-6
    sim.Drag(w.view, 120, -80)
    assert not c.follow and c.cam.cx < 31.95 - 0.5
    sim.Run(1)
    for layer in e.layers.values():
        assert layer.front.zoom == c.cam.zoom, layer.name

    # Out to the whole continent, and back to you on a right click.
    for _ in range(20):
        sim.Wheel(w.view, -1)
        sim.Step()
    sim.Run(2)
    assert c.cam.zoom == 4
    live, _ = stats(e)
    assert live["font"] > 0, live
    sim.Click(w.view, "RightButton")
    assert c.follow
    sim.Slash("/mma mapstats")
    sim.Slash("/mma map")
    assert not w.frame.IsShown(w.frame)
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_rares():
    """A pin kind added afterwards: Known("rares") (Atlas's rare spawns, the shown map only) drawn by its layer."""
    import pytest
    L, sim, ns = boot()
    if not ns.Data.Npcs:
        pytest.skip("no QuestieDB-derived data (tools/gen_questie.py)")
    e = ns.UI.Engine
    sim.Slash("/mma map")
    sim.Run(2)
    got = list(ns.Model.Known("rares")[0].values())
    assert got and all(r.kind == "rares" and r.pos.inst == 0 and not r.live for r in got)
    front = e.layers[[l.name for l in e.layers.values()].index("rares") + 1].front
    atlases = {sim.state[front.pools.pin[i]].atlas for i in range(1, front.pools.pin.n + 1)}
    assert atlases and atlases <= {"vignettekill", "vignettekillelite"}, atlases
    sim.Slash("/mma layer rares")
    assert e.LayerOn("rares") is False and e.toggles.rares is False
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
