"""The wheel's zoom (ui/Motion.lua; the spike's Core.lua:13-17, 965-980, 1420-1438) on the
simulated client: a tick chases its target in log space at 14/s and lands on it, quick ticks
stack, the tile under the cursor stays put (the buttons': the view's centre), the range is
16..800, and Camera.Settled / Camera.Velocity say when it's moving. The wheel's ticks are rationed
by time (M1.8b): a trackpad's flick is a gesture, not a tick an event.

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

    # Following: about you. Two quick ticks stack (a wheel's and the + button's: two wheel events at once
    # are a burst, test_wheel_burst); each frame closes 1 - e^(-14/60) of the log distance.
    start, cx, cy = c.cam.zoom, c.cam.cx, c.cam.cy
    sim.Wheel(w.view, 1)
    m.ZoomStep(1)
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

    # The range: 16..800 px per tile (the buttons' ticks: the wheel's are rationed).
    for d, end in ((1, 800), (-1, 16)):
        for _ in range(30):
            m.ZoomStep(d)
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


def test_wheel_burst():
    """M1.8b: a trackpad or Magic Mouse flick sends an event every frame (the M0 gate's `wheel` mark: 40 or
    more in 0.45 s), each a tick in the spike, so one flick ran to the clamp. It counts by its time, 2 ticks
    a second after the first, and a gesture (a flick and its inertia) 3 at most: a smooth chase that lands.
    A lone notch, and notches apart, stay the spike's tick (the user: 4 a second, uncapped, too sensitive)."""
    L, sim, ns = shown()
    c, w, m = ns.UI.Camera, ns.UI.Window, ns.UI.Motion
    tick = math.log(1.3)

    def ticks(a, b):
        return math.log(b / a) / tick

    # A lone notch: x1.3, as the spike's.
    start = c.cam.zoom
    sim.Wheel(w.view, 1)
    sim.Run(1)
    assert c.cam.zoom == start * 1.3

    # The flick: 40 events in 0.45 s, one a frame. ~1.9 ticks, not 40 (the clamp); each frame's move a
    # share of the chase's, never a tick; then the chase lands where it was headed and settles.
    start, zooms = c.cam.zoom, []
    for _ in range(40):
        sim.Wheel(w.view, 1)
        sim.Step(0.45 / 40)
        zooms.append(c.cam.zoom)
    goal = m.Goal()[0]
    while c.cam.zoom != goal and len(zooms) < 100:
        sim.Step()
        zooms.append(c.cam.zoom)
    moves = [ticks(a, b) for a, b in zip([start] + zooms, zooms)]
    print(f"flick: {ticks(start, goal):.2f} ticks, the most a frame {max(moves):.3f}")
    assert 1.8 < ticks(start, goal) <= 2 and c.cam.zoom == goal
    assert min(moves) >= 0 and max(moves) < 0.25, moves
    sim.Run(0.3)
    assert c.Settled() and c.Velocity() == (0, 0)

    # Scrolling on (an event a frame, from rest): 2 ticks a second after the first, to 3 in all; a pause
    # of 0.15 s and it's a gesture anew.
    for seconds, most in ((0.5, 1 + 2 * 29 / 60), (2, 3)):
        start = c.cam.zoom
        for _ in range(int(seconds * 60)):
            sim.Wheel(w.view, -1)
            sim.Step()
        sim.Run(1)
        assert ticks(c.cam.zoom, start) == pytest.approx(most)

    # A wheel mouse's notches 0.5 s apart: each the spike's whole tick, stacked.
    start = c.cam.zoom
    for _ in range(4):
        sim.Wheel(w.view, 1)
        sim.Run(0.5)
    sim.Run(1)
    assert ticks(start, c.cam.zoom) == pytest.approx(4)

    # Two notches in one frame, from rest: one tick, the bucket's (the spike stacked them to x1.69).
    start = c.cam.zoom
    sim.Wheel(w.view, 1)
    sim.Wheel(w.view, 1)
    sim.Run(1)
    assert ticks(start, c.cam.zoom) == pytest.approx(1)
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


@functools.cache
def wheel_priced():
    """Zooming in and out a few times on the priced clock (n ticks at once: the buttons', as the M0 gate
    priced it; the wheel's are rationed): Runtime's perf (each name's slowest call meanwhile), and how
    many Focus Model was sent."""
    L, sim, ns = shown()
    m, perf = ns.UI.Motion, ns.Runtime.Perf()[0]
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
            m.ZoomStep(d)
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


def test_zoom_layouts_priced():
    """Zooming keeps each layer's layout within a job's resume budget (2x its 4 ms) on the priced clock,
    its swap included (before M1.3, 93 ms borders, 25 tiles, 13 rares: each swap showed its whole canvas)."""
    perf, _ = wheel_priced()
    assert all(perf[name].max <= 8 for name in LAYERS), {name: perf[name].max for name in LAYERS}
