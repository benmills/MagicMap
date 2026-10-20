"""The map window (ui/Window.lua, ui/Engine.lua and the layers) on the simulated client: /mm toggle
shows your continent around you, its layouts finish within their jobs, wheel
and drag move the camera, and nothing errors."""
from sim import TEST_UI
from test_addon import boot, errors


def stats(e):
    live, made = e.Stats()
    return dict(live.items()), dict(made.items())


def test_map():
    L, sim, ns = boot()
    e, c, w = ns.UI.Engine, ns.UI.Camera, ns.UI.Window
    sim.Slash("/mm toggle")
    assert w.frame.IsShown(w.frame)
    sim.Run(1)
    assert c.inst == 0 and abs(c.cam.cx - 31.95) < 1e-6 and abs(c.cam.cy - 49.75) < 1e-6
    for layer in e.layers.values():  # (one off by default: none)
        assert (layer.front and not layer.busy) if layer.on else not layer.front, layer.name
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
        assert not layer.on or layer.front.zoom == c.cam.zoom, layer.name

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
    sim.Click(w.view, "RightButton")  # following: no Follow me (small: no zone info; tools/tests/test_interact.py)
    assert [e.text for e in sim.MenuItems().values()] == ["Waypoint here"]
    sim.Slash("/mm mapstats")
    sim.Slash("/mm toggle")
    assert not w.frame.IsShown(w.frame)
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_rares():
    """A pin kind added afterwards: Known("rares") (the rares you've seen: Model's saved part, the shown map's)
    drawn by its layer, from zoom 60 in (none further out: Landmarks.lua:15); laid out from a drift below it but
    zooming out, so a zoom crossing 60 shows or hides them that frame (Layers.lua:404-416); the tooltip's "Seen here
    <Mon DD>" (Landmarks.lua:61)."""
    seen = ", ".join(f"['npc:{i}'] = {{ name = 'Rare {i}', npcID = {i}, col = {31.9 + i / 50}, row = 49.7, t = 1792077412 }}"
                     for i in range(1, 4))
    # Grouping off: Goldshire's places and quests stand by these rares, and the layer's own pins are the test.
    L, sim, ns = boot(TEST_UI + "\nMagicMap2DB.UI = MagicMap2DB.UI or {}; MagicMap2DB.UI.cluster = false"
                      + f"\nMagicMap2DB.Model = {{ _v = 1, blips = {{}}, rares = {{ [0] = {{ {seen} }}, "
                      "[1] = { ['at:2048:2048'] = { name = 'Far', col = 32, row = 32, t = 1792077412 } } } }")
    e = ns.UI.Engine
    layer = e.layers[[l.name for l in e.layers.values()].index("rares") + 1]
    sim.Slash("/mm toggle")
    sim.Run(2)
    got = list(ns.Model.Known("rares")[0].values())
    assert sorted(r.name for r in got) == ["Rare 1", "Rare 2", "Rare 3"]
    assert all(r.kind == "rares" and r.pos.inst == 0 and not r.live and r.text == "Rare" and r.t == 1792077412 for r in got)
    front = layer.front
    icons = {(sim.state[front.pools.pin[i].icon].texture, sim.state[front.pools.pin[i].icon].width)
             for i in range(1, front.pools.pin.n + 1)}
    assert icons == {(137008, 15)}, icons  # the spike's rare icon at 15 (Landmarks.lua:15, 60-63; ui/Pins.lua's pins)
    def shown():
        pins = layer.front.pools.pin
        lit = lambda o: sim.state[o].alpha > 0 and sim.state[sim.state[o].parent].alpha > 0  # (its minimum zoom's frame)
        return sum(1 for i in range(1, (pins.n if pins else 0) + 1) if lit(pins[i]))

    for zoom, drawn in ((59, False), (60, True), (47, False)):
        ns.UI.Motion.SetZoom(zoom)
        sim.Run(1)
        assert layer.front.zoom == zoom and bool(shown()) == drawn, zoom
    assert not layer.front.pools.pin.n  # (47: none laid out)
    ns.UI.Motion.SetZoom(59)
    sim.Run(1)
    ns.UI.Motion.ZoomStep(1)  # 59 to 76.7: shown the frame it passes 60, before any layout
    while ns.UI.Camera.cam.zoom < 60:
        assert not shown()
        sim.Step()
    assert shown() and layer.front.zoom == 59
    # Hovered: its name, "Rare" and the day you saw it (Landmarks.lua:61).
    sim.Run(1)
    L.execute("""local sim, ns, col, row = ...
        local view, cam = ns.UI.Window.view, ns.UI.Camera.cam
        local w, h = ns.UI.Window.Size()
        local x, y = ns.Atlas.Camera.TileToScreen(cam, w, h, col, row)
        local s = view:GetEffectiveScale()
        Sim.cursorX, Sim.cursorY = (view:GetLeft() + x) * s, (view:GetTop() - y) * s""", sim, ns, 31.92, 49.7)
    sim.FireScript(ns.UI.Window.view, "OnEnter", False)
    sim.Step()
    tip = L.globals().GameTooltip
    lines = [sim.state[tip.GetLeftLine(tip, i)].text for i in range(1, tip.NumLines(tip) + 1)]
    assert lines == ["Rare 1", "Rare", "|cff808080Seen here Oct 15|r"], lines
    sim.Slash("/mm layer rares")
    assert e.LayerOn("rares") is False and e.toggles.rares is False
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
