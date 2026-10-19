"""The map window (ui/Window.lua, ui/Engine.lua and the layers) on the simulated client: /mma toggle
shows your continent around you, its layouts finish within their jobs, wheel
and drag move the camera, and nothing errors."""
from test_addon import boot, errors


def stats(e):
    live, made = e.Stats()
    return dict(live.items()), dict(made.items())


def test_map():
    L, sim, ns = boot()
    e, c, w = ns.UI.Engine, ns.UI.Camera, ns.UI.Window
    sim.Slash("/mma toggle")
    assert w.frame.IsShown(w.frame)
    sim.Run(1)
    assert c.inst == 0 and abs(c.cam.cx - 31.95) < 1e-6 and abs(c.cam.cy - 49.75) < 1e-6
    for layer in e.layers.values():
        assert layer.front and not layer.busy, layer.name
    live, _ = stats(e)
    assert live["tex"] > 10 and live["line"] > 10 and live["font"] > 0, live

    # Wheel in about the cursor (following: about you; the zoom chases its target), drag pans and stops following.
    zoom = c.cam.zoom
    sim.Wheel(w.view, 1)
    sim.Run(0.5)
    assert c.cam.zoom > zoom and abs(c.cam.cx - 31.95) < 1e-6
    sim.Drag(w.view, 120, -80)
    assert not c.follow and c.cam.cx < 31.95 - 0.5
    sim.Run(1)
    for layer in e.layers.values():
        assert layer.front.zoom == c.cam.zoom, layer.name

    # Out to the whole continent (the zoom-out button's ticks, a frame apart, as a fast wheel's),
    # and back to you on a right click.
    for _ in range(20):
        ns.UI.Motion.ZoomStep(-1)
        sim.Step()
    sim.Run(2)
    assert c.cam.zoom == 16
    live, _ = stats(e)
    assert live["font"] > 0, live
    sim.Click(w.view, "RightButton")  # the map's menu: Follow me glides back to you, then follows
    items = [e for e in sim.MenuItems("button").values() if e.text == "Follow me"]
    assert len(items) == 1
    items[0].onSelect()
    sim.Run(1)
    assert c.follow
    sim.Click(w.view, "RightButton")  # following: nothing to offer
    assert sim.menu is None
    sim.Slash("/mma mapstats")
    sim.Slash("/mma toggle")
    assert not w.frame.IsShown(w.frame)
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_rares():
    """A pin kind added afterwards: Known("rares") (Atlas's rare spawns, the shown map only) drawn by its layer,
    from zoom 60 in (none further out: Landmarks.lua:15)."""
    import pytest
    L, sim, ns = boot()
    if not ns.Data.Npcs:
        pytest.skip("no QuestieDB-derived data (tools/gen_questie.py)")
    e = ns.UI.Engine
    layer = e.layers[[l.name for l in e.layers.values()].index("rares") + 1]
    sim.Slash("/mma toggle")
    sim.Run(2)
    got = list(ns.Model.Known("rares")[0].values())
    assert got and all(r.kind == "rares" and r.pos.inst == 0 and not r.live for r in got)
    front = layer.front
    atlases = {sim.state[front.pools.pin[i]].atlas for i in range(1, front.pools.pin.n + 1)}
    assert atlases and atlases <= {"vignettekill", "vignettekillelite"}, atlases
    for zoom, drawn in ((59, False), (60, True)):
        ns.UI.Motion.SetZoom(zoom)
        sim.Run(1)
        pins = layer.front.pools.pin
        assert layer.front.zoom == zoom and bool(pins and pins.n) == drawn, zoom
    sim.Slash("/mma layer rares")
    assert e.LayerOn("rares") is False and e.toggles.rares is False
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
