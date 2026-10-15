"""Camera feel (ui/Motion.lua) on the simulated client, the spike's values: a press moving
under 5 px and up within 0.35 s is a click, past 5 px a drag (it pans and stops following);
left alone 6 s after a pan, unhovered and small, the map glides back to following you; a
flight (0.55 s, EaseOutCubic, log-space zoom) zooming in keeps its target on a line toward the
centre and ends exactly there; Focus carries the rect in view."""
from test_addon import boot, errors


def shown():
    L, sim, ns = boot()
    sim.Slash("/mma toggle")
    sim.Run(3)
    return L, sim, ns


def press(sim, view):
    sim.MoveCursorTo(view)
    sim.buttonsDown["LeftButton"] = True
    sim.FireScript(view, "OnMouseDown", "LeftButton")


def release(sim, m):
    sim.buttonsDown["LeftButton"] = None
    return m.Release()


def test_click_drag_idle():
    L, sim, ns = shown()
    c, w, m = ns.UI.Camera, ns.UI.Window, ns.UI.Motion
    cx, cy, zoom = c.cam.cx, c.cam.cy, c.cam.zoom

    # Under 5 px and quick: a click. The map stays put, still following.
    press(sim, w.view)
    sim.cursorX, sim.cursorY = sim.cursorX + 4, sim.cursorY - 5
    sim.Run(0.2)
    assert (c.cam.cx, c.cam.cy) == (cx, cy) and c.follow and not m.Dragging()
    assert release(sim, m) is True
    press(sim, w.view)  # still, but held over 0.35 s: not a click
    sim.Run(0.4)
    assert release(sim, m) is False and c.follow

    # Past 5 px: a drag. Follow off, and the map catches up with the cursor.
    press(sim, w.view)
    sim.cursorX = sim.cursorX + 6
    sim.Step()
    assert m.Dragging() and not c.follow and c.cam.cx == cx - 6 / zoom and c.cam.cy == cy
    assert release(sim, m) is False

    # Hovered, it stays where you left it.
    sim.Run(8)
    assert not c.follow and c.cam.cx == cx - 6 / zoom

    # Left alone (cursor off the window) 6 s after the last touch: it glides back, then follows.
    sim.cursorX, sim.cursorY = 5, 5
    press(sim, w.view)
    sim.cursorX = sim.cursorX + 6
    sim.Step()
    release(sim, m)
    sim.cursorX, sim.cursorY = 5, 5
    sim.Run(5.8)
    assert not c.follow and not c.moving
    sim.Run(0.3)
    assert not c.follow and c.moving and m.Goal()[1:] == (cx, cy)  # flying back to you
    sim.Run(0.6)
    assert c.follow and (c.cam.cx, c.cam.cy) == (cx, cy)

    # Not while big (grown as M does: ui/BigMap.lua).
    ns.UI.BigMap.Toggle()
    sim.Run(0.5)
    assert ns.UI.View().window.big and c.follow
    press(sim, w.view)
    sim.cursorX = sim.cursorX + 6
    sim.Step()
    release(sim, m)
    sim.cursorX, sim.cursorY = 5, 5
    sim.Run(8)
    assert not c.follow
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_flight():
    L, sim, ns = shown()
    c, w, m, maths = ns.UI.Camera, ns.UI.Window, ns.UI.Motion, ns.Atlas.Camera
    width, height = w.Size()
    m.SetFollow(False)
    done = L.eval("{ n = 0 }")
    on_done = L.eval("function(done) return function() done.n = done.n + 1 end end")(done)

    # Zooming in, the target "comes to you": its offset on screen keeps its direction, shrinking.
    tx, ty, tz = c.cam.cx + 2, c.cam.cy - 1, c.cam.zoom * 4
    m.FlyTo(tx, ty, tz, None, on_done)
    last = None
    for _ in range(32):  # 0.55 s is 33 frames
        sim.Step()
        x, y = maths.TileToScreen(c.cam, width, height, tx, ty)
        dx, dy = x - width / 2, y - height / 2
        assert abs(dx * 1 + dy * 2) < 1e-6 and dx > 0  # on the line toward the centre: (2, -1) tiles
        assert last is None or dx < last
        last = dx
    assert done.n == 0 and not c.Settled()
    sim.Step()
    assert (c.cam.cx, c.cam.cy, c.cam.zoom) == (tx, ty, tz) and done.n == 1
    sim.Run(0.2)
    assert c.Settled() and done.n == 1

    # Out, to fit a rect (a zone) at 0.92 of the view, following off.
    m.SetFollow(True)
    m.FlyToRect(28, 46, 36, 52)
    sim.Run(0.6)
    fit = min(width / 8, height / 6) * 0.92
    assert (c.cam.cx, c.cam.cy) == (32, 49) and abs(c.cam.zoom - fit) < 1e-9 and not c.follow
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_focus_rect():
    L, sim, ns = shown()
    c, w, m = ns.UI.Camera, ns.UI.Window, ns.UI.Motion
    width, height = w.Size()

    def contains_view(r):
        x0, y0 = ns.Atlas.Camera.ScreenToTile(c.cam, width, height, 0, 0)
        x1, y1 = ns.Atlas.Camera.ScreenToTile(c.cam, width, height, width, height)
        return r.inst == c.inst and r.c0 <= x0 and r.r0 <= y0 and r.c1 >= x1 and r.r1 >= y1 and r.c1 - x1 < 1 / 16

    same = L.eval("rawequal")
    focus = ns.Model.focus
    assert focus.inst == 0 and focus.zoom == c.cam.zoom and contains_view(focus.rect)
    # A drag keeps the rect it started with; once it rests, the rect in view.
    press(sim, w.view)
    for _ in range(30):
        sim.cursorX = sim.cursorX + 10
        sim.Step()
    assert same(ns.Model.focus.rect, focus.rect) and not contains_view(focus.rect)
    release(sim, m)
    sim.Step()
    assert contains_view(ns.Model.focus.rect)
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
