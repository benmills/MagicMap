"""The wheel's zoom (ui/Motion.lua; the spike's Core.lua:13-17, 965-980, 1420-1438) on the
simulated client: a tick chases its target in log space at 14/s and lands on it, quick ticks
stack, the tile under the cursor stays put (the buttons': the view's centre), the range is
16..800, and Camera.Settled / Camera.Velocity say when it's moving. Every wheel event is a tick, as the
spike's (test_feel.py holds the camera to the spike's frame by frame).

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

    # Following: about you. Two quick ticks stack (a wheel's and the + button's); each frame closes
    # 1 - e^(-14/60) of the log distance.
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

    # The range: 16..800 px per tile.
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


def test_wheel():
    """Every wheel event is a tick by its sign, stacked onto the target, as the spike's (Core.lua:1422-1441): a lone
    notch x1.3, two in a frame x1.69, a trackpad's 40 events in 0.45 s 40 ticks (to the clamp). M1.8b rationed them
    by time (a bucket of 1 tick refilling 2 a second, 3 a gesture), and a fast scroll did next to nothing: the user's
    play-test of M1 (M1b). The `wheel` cam trace says what the device sent each frame: the events' deltas summed
    (delta), how many (n), s from the event before them (dt)."""
    L, sim, ns = shown()
    c, w = ns.UI.Camera, ns.UI.Window

    def ticks(a, b):
        return math.log(b / a) / math.log(1.3)

    def wheel_traces():
        return [e.d for e in ns.Runtime.TraceCopy().values() if e.k == "cam" and e.d.e == "wheel" and e.d.n]

    start = c.cam.zoom
    sim.Wheel(w.view, 1)
    sim.Run(1)
    assert c.cam.zoom == pytest.approx(start * 1.3)
    assert [(t.delta, t.n) for t in wheel_traces()] == [(1, 1)]

    # Two in a frame, one of them small: a tick each.
    start = c.cam.zoom
    sim.Wheel(w.view, 1)
    sim.Wheel(w.view, 0.25)
    sim.Run(1)
    assert ticks(start, c.cam.zoom) == pytest.approx(2)
    t = wheel_traces()[-1]
    assert (t.delta, t.n, t.dt) == (1.25, 2, 1)

    # A trackpad's flick out: an event a frame, each a tick.
    for _ in range(40):
        sim.Wheel(w.view, -1)
        sim.Step(0.45 / 40)
    sim.Run(1)
    assert c.cam.zoom == 16 and c.Settled()
    assert [(t.delta, t.n, t.dt) for t in wheel_traces()[-40:]] == [(-1, 1, 1)] + [(-1, 1, 0.011)] * 39
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


@functools.cache
def wheel_priced():
    """Zooming in and out a few times on the priced clock (n ticks at once, as the M0 gate priced it):
    Runtime's perf (each name's slowest call meanwhile), and how many Focus Model was sent."""
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


def test_script_a_priced():
    """Script (a)'s shape on the priced clock (docs/playtest.md a2-a7: the wheel 16 -> 800 -> 16 twice, flings,
    a follow walk, the big window's pans): a third of its frames move, each running a layout slice (4-5 ms),
    so the session's p95 would be ~2 ms. The budgets by map state (docs/runtime.md): at rest p95 <= 1 ms and
    p99 <= 5 ms, moving p95 <= 5 ms, none over 8."""
    L, sim, ns = shown()
    L.execute("""local sim, ns = ...
        local view, M = ns.UI.Window.view, ns.UI.Motion
        sim.Price(true)
        sim.Run(12) -- past the graces
        local function Wheel(d, n, gap) for _ = 1, n do sim.Wheel(view, d); sim.Run(gap) end end
        local function Drag(dx, dy, frames)
            sim.MoveCursorTo(view)
            sim.buttonsDown.LeftButton = true
            sim.FireScript(view, "OnMouseDown", "LeftButton")
            for _ = 1, frames do sim.cursorX, sim.cursorY = sim.cursorX + dx, sim.cursorY + dy; sim.Step() end
            sim.buttonsDown.LeftButton = nil
            sim.FireScript(view, "OnMouseUp", "LeftButton")
        end
        for _ = 1, 2 do M.SetZoom(16); sim.Run(1); Wheel(1, 30, 0.3); Wheel(-1, 30, 0.3) end
        M.SetZoom(200); sim.Run(1)
        for i = 1, 6 do Drag(i % 2 == 0 and 30 or -30, 10, 20); sim.Run(1.5) end
        M.SetFollow(true); sim.Run(1)
        sim.player.facing, sim.player.speed = 3 * math.pi / 2, 7 -- east
        sim.Run(30)
        sim.player.speed = 0
        sim.Press("M"); sim.Run(1.5)
        M.SetFollow(false)
        for _, z in ipairs({ 100, 200 }) do
            M.SetZoom(z); sim.Run(1)
            for i = 1, 6 do Drag(i % 2 == 0 and 25 or -25, i % 3 == 0 and 15 or -10, 30); sim.Run(1) end
            Wheel(1, 4, 0.4); Wheel(-1, 4, 0.4)
        end
        sim.Press("M"); sim.Run(2)
        sim.Price(false)""", sim, ns)
    fs = ns.Runtime.FrameStats()
    by = {k: v for k, v in fs.byState.items()}
    print(f"script (a), priced: {fs.frames} frames, p95 {fs.p95} p99 {fs.p99} max {fs.max}; "
          + ", ".join(f"{k} {v.frames} p95 {v.p95} p99 {v.p99}" for k, v in sorted(by.items())))
    rest, moving = [by[k] for k in ("small", "big") if k in by], [by[k] for k in ("zoom", "drag") if k in by]
    assert len(rest) == 2 and len(moving) == 2
    assert max(v.p95 for v in rest) <= 1 and max(v.p99 for v in rest) <= 5 and max(v.p95 for v in moving) <= 5
    assert fs.max <= 8 and not errors(sim, ns), errors(sim, ns)
