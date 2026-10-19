"""Model's route (docs/v1-plan.md M3.1: model/Route.lua) on the simulated client: A* over Atlas.Walk in a
Runtime.Job, to your waypoint (test_target.TARGETS: Game's part as M3.2's hands it), its searches on a
clock that counts their Lua (R-P2's), so a 1 ms slice is a slice of work:

  test_route_dun_morogh: Kharanos to Anvilmar, around Dun Morogh's hills: found a slice a frame, each
    within its 1 ms but a node (the exit's "a 1 ms slice a frame, at most the slice and one node"), from you to
    the target.
  test_route_replan: found again only past 3 chunks off it, or once the target moves more than 2 (an
    area's nearest edge slides as you go); meanwhile the old one (F33).
  test_route_straight_partial: no walk data where the target is: you and it, straight; a plateau no way
    climbs, 9 tiles off: given up at 60,000 nodes, the way to as near as it got, then on straight.
  test_route_capped: that plateau's search from Goldshire, priced: ~1,050 slices, its KB; walking on (off
    its partial way, past RETRY_MOVED) searches it again only once you've come half the way it spanned (the
    lead's decision at the M3 review: the spike searched again each 3-chunk stray).
  test_route_gives_way: the big window zoomed in and out during that long search, priced: the search waits
    while the view moves (Focus.moving: a slice only in the frame a zoom starts, Model a frame behind), no
    frame over 8 ms; at rest it goes on.
"""
from test_addon import errors
from test_target import put, targets

KHARANOS, ANVILMAR = (32.91, 42.41), (31.28, 43.502)
GOLDSHIRE, LAKESHIRE = (31.95, 49.75), (36.09, 49.28)
CHUNK = 1 / 16  # tiles


def find(sim, ns, frames=100):
    """Steps till Model has a route (not straight while it's found): how many frames."""
    for n in range(1, frames + 1):
        sim.Step()
        if ns.Model.Route():
            return n
    raise AssertionError("no route in %d frames" % frames)


def points(r):
    return [r[i] for i in range(1, len(r) + 1)]


def test_route_dun_morogh():
    L, sim, ns, G = targets([], followed=0)
    me, same = sim.player, L.eval("rawequal")
    me.col, me.row = KHARANOS
    sim.Run(1)
    put(G, "waypoint", 0, *ANVILMAR)
    frames = find(sim, ns)
    p = ns.Runtime.Perf()[0]["model: route"]
    assert len(G.Jobs) == 1 and 10 < frames < 60 and p.n == frames - 1 and p.max <= 1.1
    r, t = ns.Model.Route(), ns.Model.Target()
    pts = points(r)
    assert same(pts[0], ns.Model.you) and same(pts[-1], t.pos) and len(pts) > 10 and not r.straight and not r.partial
    assert all(q.inst == 0 for q in pts)
    sim.Run(1)  # standing: the same way
    assert same(ns.Model.Route(), r) and len(G.Jobs) == 1
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_route_replan():
    L, sim, ns, G = targets([], followed=0)
    me, same, Route = sim.player, L.eval("rawequal"), ns.Model.Route
    sim.Run(1)
    put(G, "waypoint", 0, *LAKESHIRE)
    find(sim, ns)
    first = points(Route())
    me.row = GOLDSHIRE[1] - 2 * CHUNK  # 2 chunks north, off its first leg east: kept
    sim.Run(0.5)
    assert len(G.Jobs) == 1 and any(same(Route()[2], q) for q in first)
    me.row = GOLDSHIRE[1] - 3.5 * CHUNK  # past 3: found again, the old shown meanwhile
    shown = []
    while len(G.Jobs) < 2 or not G.Jobs[2].done:
        sim.Step()
        shown.append(Route())
    assert len(G.Jobs) == 2 and len(shown) > 2 and all(r and not r.straight for r in shown)
    sim.Step()
    again = points(Route())
    assert not any(same(again[1], q) for q in first)

    sim.Run(0.5)
    jobs = len(G.Jobs)
    put(G, "waypoint", 0, LAKESHIRE[0] + 2 * CHUNK, LAKESHIRE[1])  # the target 2 chunks on: kept
    sim.Run(0.5)
    assert len(G.Jobs) == jobs and same(points(Route())[-1], ns.Model.Target().pos)
    put(G, "waypoint", 0, LAKESHIRE[0] + 5 * CHUNK, LAKESHIRE[1])  # 3 more: found again, the old shown meanwhile
    shown = []
    while len(G.Jobs) == jobs or not G.Jobs[jobs + 1].done:
        sim.Step()
        shown.append(Route())
    assert len(G.Jobs) == jobs + 1 and len(shown) > 2 and all(r and not r.straight for r in shown)
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_route_straight_partial():
    L, sim, ns, G = targets([], followed=0)
    me, same = sim.player, L.eval("rawequal")
    sim.Run(1)
    put(G, "waypoint", 0, 20.0, 50.0)  # the sea west of Westfall: no terrain, nowhere to stand
    sim.Step()
    r = ns.Model.Route()
    assert r.straight and len(r) == 2 and same(r[1], ns.Model.you) and same(r[2], ns.Model.Target().pos)
    assert len(G.Jobs) == 0

    G.Counting = False  # (Lua free: the whole search in one resume)
    put(G, "waypoint", 0, 34.75, 38.75)  # a plateau in Dun Morogh's peaks, cliffs all round
    find(sim, ns)
    r = ns.Model.Route()
    assert 60000 < G.Jobs[1].yields < 61000  # a node a Yield, then the straightening's
    assert r.partial and not r.straight and r[len(r)].row == 38.75
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_route_capped():
    L, sim, ns, G = targets([], followed=0)
    me = sim.player
    sim.Run(1)
    put(G, "waypoint", 0, 34.75, 38.75)  # the plateau, 11.4 tiles off: no way there
    frames = 0
    while not (len(G.Jobs) and G.Jobs[1].done):
        sim.Step()
        frames += 1
    sim.Step()
    p = ns.Runtime.Perf()[0]["model: route"]
    print(f"a capped search: {frames} frames, {p.kb:.0f} KB, its slowest resume {p.max:.2f} ms, {p.kbMax:.0f} KB")
    assert 1000 < frames < 1100 and p.kb < 5000 and ns.Model.Route().partial
    walked = []
    for _ in range(11):  # toward it, 0.56 tiles a step (9 chunks: off its way, past RETRY_MOVED in two)
        me.col, me.row = me.col + 0.25, me.row - 0.5
        sim.Run(0.3)
        walked.append(len(G.Jobs))
    assert walked == [1] * 10 + [2], walked  # again past 5.7 tiles, half of its 11.4
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_route_gives_way():
    L, sim, ns, G = targets([], followed=0)
    sim.Press("M")
    sim.Run(6)  # past login's grace and the first open's
    view, P = ns.UI.Window.view, ns.Runtime.Perf
    sim.Price(True)
    put(G, "waypoint", 0, 34.75, 38.75)  # the plateau: ~1,000 slices
    sim.Run(0.5)
    n0, cycles = P()[0]["model: route"].n, 4
    for _ in range(cycles):
        for d in (-1, 1):
            for _ in range(4):
                sim.Wheel(view, d)
                sim.Step()
            sim.Run(0.1)  # (still moving: the zoom unsettled, its layouts not caught up)
    moving = P()[0]["model: route"].n - n0
    sim.Run(2)
    rest = P()[0]["model: route"].n - n0 - moving
    sim.Price(False)
    fs = ns.Runtime.FrameStats()
    print(f"zooming during the plateau's search: {moving} slices in {cycles * 2} zooms, {rest} in 2 s at rest; "
          f"zoom p95 {fs.byState.zoom.p95} max {fs.max}")
    assert not G.Jobs[1].done and moving <= cycles * 2 and rest > 60 and fs.max <= 8
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
