"""The wheel's zoom (ui/Motion.lua; the spike's Core.lua:13-17, 965-980, 1420-1438) on the
simulated client: a tick chases its target in log space at 14/s and lands on it, quick ticks
stack, the tile under the cursor stays put (the buttons': the view's centre), the range is
16..800, and Camera.Settled / Camera.Velocity say when it's moving.

  .venv/bin/python -m pytest tools/tests/test_zoom.py -s   # prints the priced draw while zooming
"""
import functools
import math

import pytest

from test_addon import boot, errors

LAYERS = ("map: tiles", "map: borders", "map: labels", "map: blips", "map: rares")


def shown():
    L, sim, ns = boot()
    sim.Slash("/mma toggle")
    sim.Run(3)
    return L, sim, ns


def test_zoom_chase():
    L, sim, ns = shown()
    c, w, m, maths = ns.UI.Camera, ns.UI.Window, ns.UI.Motion, ns.Atlas.Camera
    assert c.Settled() and c.Velocity() == (0, 0)

    # Following: about you. Two quick ticks stack; each frame closes 1 - e^(-14/60) of the log distance.
    start, cx, cy = c.cam.zoom, c.cam.cx, c.cam.cy
    sim.Wheel(w.view, 1)
    sim.Wheel(w.view, 1)
    goal = start * 1.3 * 1.3
    assert c.cam.zoom == start and not c.Settled()
    zooms = []
    while c.cam.zoom != goal and len(zooms) < 30:  # landing within 0.002 log of it: ~0.4 s
        sim.Step()
        zooms.append(c.cam.zoom)
    assert math.log(goal / zooms[0]) == pytest.approx(math.log(goal / start) * math.exp(-14 / 60))
    assert zooms == sorted(zooms) and zooms[-1] == goal, zooms  # no overshoot
    assert (c.cam.cx, c.cam.cy) == (cx, cy) and c.Velocity() == (0, 0)
    sim.Run(0.1)
    assert not c.Settled()  # the zoom unchanged for 0.15 s
    sim.Run(0.1)
    assert c.Settled()

    # Free: about the cursor, the tile under it kept there every frame; the centre moves meanwhile.
    m.SetFollow(False)
    sim.MoveCursorTo(w.view, 0.2, 0.3)
    x, y = w.Cursor()
    width, height = w.Size()
    under = maths.ScreenToTile(c.cam, width, height, x, y)
    sim.FireScript(w.view, "OnMouseWheel", -1)
    moved = False
    for _ in range(40):
        sim.Step()
        col, row = maths.ScreenToTile(c.cam, width, height, x, y)
        assert abs(col - under[0]) < 1e-9 and abs(row - under[1]) < 1e-9
        moved = moved or c.Velocity() != (0, 0)
    assert moved and c.cam.zoom == goal / 1.3 and c.Velocity() == (0, 0)

    # The + button (ui/Controls.lua): one step, about the view's centre.
    cx, cy, zoom = c.cam.cx, c.cam.cy, c.cam.zoom
    sim.Click(ns.UI.Controls.zoomIn)
    sim.Run(1)
    assert c.cam.zoom == pytest.approx(zoom * 1.3) and (c.cam.cx, c.cam.cy) == pytest.approx((cx, cy))

    # The range: 16..800 px per tile.
    for d, end in ((1, 800), (-1, 16)):
        for _ in range(30):
            sim.Wheel(w.view, d)
        sim.Run(1)
        assert c.cam.zoom == end

    # Reopened after you moved (a flight path, a hearth): the camera catches up with you, at no speed.
    m.SetFollow(True)
    sim.Run(0.5)
    sim.Slash("/mma toggle")
    sim.player.col = sim.player.col + 1.5
    sim.Run(0.5)
    sim.Slash("/mma toggle")
    for _ in range(3):
        sim.Step()
        assert c.Velocity() == (0, 0)
    assert c.cam.cx == ns.Model.you.col
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


@functools.cache
def wheel_priced():
    """The wheel in and out a few times on the priced clock: Runtime's perf (each name's slowest call
    meanwhile), and how many Focus Model was sent."""
    L, sim, ns = shown()
    w, perf = ns.UI.Window, ns.Runtime.Perf()[0]
    sends = L.eval("""function(Model)
        local n, focus = { v = 0 }, Model.Focus
        Model.Focus = function(f) n.v = n.v + 1; return focus(f) end
        return n
    end""")(ns.Model)
    sim.Price(True)
    for name in ("map: draw", "map: motion", *LAYERS):
        perf[name].max = 0
    for d, n in ((1, 3), (-1, 6), (1, 2)):
        for _ in range(n):
            sim.Wheel(w.view, d)
        sim.Run(0.5)
    print(f"zooming: map: draw max {perf['map: draw'].max:.2f} ms, map: motion max {perf['map: motion'].max:.3f} ms, "
          f"{sends.v} Focus sent; layouts' slowest frame: "
          + ", ".join(f"{name[5:]} {perf[name].max:.1f} ms" for name in LAYERS))
    return perf, sends.v


def test_zoom_motion_priced():
    """Zooming, Motion's own step stays within a call's budget (2 ms), and Model hears the focus where
    the view rests, not each frame of the chase."""
    perf, sends = wheel_priced()
    assert perf["map: motion"].max <= 2 and sends <= 6


def test_zoom_draw_priced():
    """Zooming keeps the draw step within a call's budget (2 ms) on the priced clock (a canvas's
    SetScale is ~8 us however many regions it holds: /mma bench regions)."""
    perf, _ = wheel_priced()
    assert perf["map: draw"].max <= 2


@pytest.mark.xfail(strict=True, reason="M1.3: every frame of the chase lays all 5 layers out again, and each swap "
                   "shows its whole canvas at once (priced: borders ~93 ms, tiles ~25, rares ~13; in game 116, 24, 13 ms)")
def test_zoom_layouts_priced():
    """Zooming keeps each layer's layout within a job's resume budget (2x its 4 ms) on the priced clock,
    its swap included."""
    perf, _ = wheel_priced()
    assert all(perf[name].max <= 8 for name in LAYERS), {name: perf[name].max for name in LAYERS}
