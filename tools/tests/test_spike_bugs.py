"""The spike's bugs replayed in the sim: every "Replayable now" scenario of
docs/evidence/spike-bugs.md, one test per bug id (the doc's replay column names
them as test_spike_bugs.py::test_replay[<id>]). Each sets the initial state,
drives inputs frame by frame, and asserts the outcome the table claims:
PREVENTED (the failure can't happen), CONTAINED (it happens, isolated, recorded
in telemetry, the rest runs on), or for MOVED rows the part the design does
bound, with the measured rest printed (pytest -s)."""
import os

import pytest
from lupa import lua51

from test_addon import TESTS, boot, errors

JOB_MS = 4  # ui/Map.lua: a layout's budget a frame


def shown(saved=None, seconds=3):
    """Booted, the map open and past its first-open grace (2 s)."""
    L, sim, ns = boot(saved)
    sim.Run(1)
    sim.Slash("/mma map")
    sim.Run(seconds)
    return L, sim, ns


def layer(ns, name):
    return next(x for x in ns.UI.Map.layers.values() if x.name == name)


def fresh(ns, lay):
    """The layer shows a layout at the camera's zoom on the map shown, covering the view."""
    m, c = ns.UI.Map, lay.front
    if c is None or c.zoom != m.cam.zoom or c.inst != m.inst:
        return False
    w, h = m.Size()
    cam, r = m.cam, c.region
    return (r[1] <= cam.cx - w / 2 / cam.zoom and r[3] >= cam.cx + w / 2 / cam.zoom
            and r[2] <= cam.cy - h / 2 / cam.zoom and r[4] >= cam.cy + h / 2 / cam.zoom)


def live(lay):
    """Regions in use on the layer's shown canvas."""
    return sum(p.n for p in lay.front.pools.values()) if lay.front is not None else 0


def errs(ns, name):
    e = next((e for e in ns.Runtime.errors.values() if e.name == name), None)
    return e.n if e is not None else 0


def ours(L, sim):
    """Measure our frame alone: wraps Runtime's OnUpdate (the one OnUpdate the addon set) to sum
    the Lua heap's growth and widget calls inside it. Returns a reader: (frames, KB, calls)."""
    return L.eval("""function(sim)
        local m = { n = 0, kb = 0, calls = 0 }
        for _, f in ipairs(sim.Frames()) do
            local s = sim.state[f].scripts.OnUpdate
            if s and f ~= Minimap then
                local fn = s.main
                s.main = function(...)
                    local k0, c0 = collectgarbage("count"), sim.callTotal or 0
                    fn(...)
                    m.n, m.kb, m.calls = m.n + 1, m.kb + collectgarbage("count") - k0, m.calls + (sim.callTotal or 0) - c0
                end
            end
        end
        return function() return m.n, m.kb, m.calls end
    end""")(sim)


# Each replay ------------------------------------------------------------------------------------

def replay_E1():
    """Data globals collide. PREVENTED: Data/ lives in the addon's namespace, so no data global is
    set for the spike to read, and a spike-shaped MagicMap_Borders loaded after us isn't read.
    A malformed row in our own data is CONTAINED: the borders layout fails, is recorded once, and
    is retried with a backoff (never per frame) while tiles and labels draw."""
    L, sim, ns = shown()
    G = L.globals()
    leaked = [k for k in L.eval("function() local t = {} for k in pairs(_G) do t[#t + 1] = k end return t end")().values()
              if isinstance(k, str) and (k.startswith("MagicMap_") or k.startswith("MagicMapAtlas_"))]
    assert leaked == [], leaked
    G.MagicMap_Borders = L.eval("{ [0] = { lines = { { 1, 12, 40, 0, 0, 31.0, 49.0, 32.0, 50.0 } }, labels = {} } }")
    view, borders = ns.UI.Map.view, layer(ns, "borders")
    sim.Wheel(view, 1)
    sim.Run(1)
    sim.Drag(view, 200, 0)
    sim.Run(1)
    assert not errors(sim, ns) and fresh(ns, borders) and live(borders) > 0

    # Our own data with the spike's row shape (an odd coordinate count): the E1 error itself.
    lines = ns.Data.Borders[0].lines
    lines[len(lines) + 1] = L.eval("{ 1, 12, 40, 0, 0, 31.9, 49.7, 32.0, 49.8 }")
    sim.Wheel(view, 1)
    sim.Run(1)
    n1 = errs(ns, "map: borders")
    sim.Run(3)  # 180 frames
    n2 = errs(ns, "map: borders")
    print(f"E1: malformed row: {n1} error(s) after 1 s, {n2} after 4 s (180 frames)")
    assert 1 <= n1 <= 2 and n2 - n1 <= 3, (n1, n2)  # backoff 0.5, 1, 2, 4 s: not per frame
    assert "bad argument" in next(e.err for e in ns.Runtime.errors.values() if e.name == "map: borders")
    for name in ("tiles", "labels"):
        assert fresh(ns, layer(ns, name)) and live(layer(ns, name)) > 0, name
    tel = G.MagicMapAtlasDB.telemetry
    kept = [e for e in tel.errors.values() if e.name == "map: borders"]
    assert len(kept) == 1 and kept[0].count == n2 and kept[0].stack
    assert len([m for m in tel.marks.values() if "map: borders" in (m.note or "")]) == 1


def replay_E7():
    """One error stops everything after it. CONTAINED: a layout job that errors is recorded once
    (with its stack), its layer isn't frozen (busy cleared, laid out again after a backoff), and a
    step failing every frame takes one stack, not one per failure."""
    L, sim, ns = shown()
    m, borders = ns.UI.Map, layer(ns, "borders")
    borders.build = L.eval("""function(orig)
        local failed
        return function(...)
            if not failed then failed = true; error("layout boom") end
            return orig(...)
        end
    end""")(borders.build)
    zoom = m.cam.zoom
    sim.Wheel(m.view, 1)
    sim.Run(1)
    assert m.cam.zoom != zoom
    assert [(e.name, e.n) for e in ns.Runtime.errors.values()] == [("map: borders", 1)]
    assert not borders.busy and fresh(ns, borders) and live(borders) > 0
    tel = L.globals().MagicMapAtlasDB.telemetry
    kept = next(e for e in tel.errors.values() if e.name == "map: borders")
    assert kept.count == 1 and "layout boom" in kept.msg and kept.stack
    assert any(e.k == "layout" and e.d.e == "failed" for e in ns.Runtime.TraceCopy().values())

    # A step failing every frame (the spike's E1 rate): one stack walk, not one a failure.
    stacks = L.eval("""function(R)
        local n, orig = { v = 0 }, debugstack
        debugstack = function(...) n.v = n.v + 1; return orig(...) end
        R.Step("model", "test.every-frame", function() error("again") end)
        return n
    end""")(ns.Runtime)
    sim.Run(3)
    fails = errs(ns, "test.every-frame")
    print(f"E7: a step failing every frame for 3 s: {fails} failures, {stacks.v} stack walks")
    assert fails >= 10 and stacks.v == 1
    assert fresh(ns, borders) and errs(ns, "map: borders") == 1


def replay_P1():
    """Borders fall behind a fast pan. MOVED: a layout job's cost per frame is bounded (its budget,
    under a client-like clock), but a whole-layer rebuild still lags a fling: coverage is measured
    and printed, and the layers must be fresh 1 s after stopping."""
    L, sim, ns = boot()
    sim.CountCalls()
    sim.Clock = L.eval("function(sim) return function() return os.clock() * 1000 + sim.callTotal * 0.003 end end")(sim)
    sim.Run(1)
    sim.Slash("/mma map")
    sim.Run(3)
    m = ns.UI.Map
    for lay in m.layers.values():  # the first open's layouts done: maxima from here
        ns.Runtime.Perf()[0]["map: " + lay.name].max = 0
    w, _ = m.Size()
    m.follow = False
    covered = {lay.name: 0 for lay in m.layers.values()}
    for _ in range(180):
        m.cam.cx = m.cam.cx + w * 1.5 / 60 / m.cam.zoom
        sim.Step()
        for lay in m.layers.values():
            covered[lay.name] += fresh(ns, lay)
    sim.Run(1)
    perf = ns.Runtime.Perf()[0]
    worst = {lay.name: round(perf["map: " + lay.name].max, 2) for lay in m.layers.values()}
    print(f"P1: frames covered of 180 at 1.5 views/s: {covered}; job max ms {worst}")
    assert all(fresh(ns, lay) for lay in m.layers.values())
    assert all(ms <= JOB_MS * 1.5 for ms in worst.values()), worst
    assert not errors(sim, ns)

    # A 20-step wheel-out, one step a frame: layouts started, against layers x settled zooms (1).
    start = len([e for e in ns.Runtime.TraceCopy().values() if e.k == "layout" and e.d.e == "start"])
    for _ in range(20):
        sim.Wheel(m.view, -1)
        sim.Step()
    sim.Run(2)
    started = len([e for e in ns.Runtime.TraceCopy().values() if e.k == "layout" and e.d.e == "start"]) - start
    print(f"P1: 20-step wheel-out: {started} layouts started for {len(m.layers)} layers")
    assert all(fresh(ns, lay) for lay in m.layers.values())


def replay_P2():
    """Cooperative budget overrun. MOVED: Yield checks the budget only where the job calls it, so
    a job yielding every 200 iterations overruns (and Perf's max shows it); one that yields every
    iteration keeps to budget + one iteration."""
    L, sim, ns = boot()
    sim.Run(1)
    run = L.eval("""function(sim, R, name, every)
        local tick = 0
        local clock = sim.Clock
        sim.Clock = function() return tick * 0.02 end -- 0.02 ms an iteration, nothing else costs
        local job = R.Job(name, function()
            for i = 1, 1e4 do
                tick = tick + 1
                if i % every == 0 then R.Yield() end
            end
        end, 1)
        for _ = 1, 400 do if job.done then break end sim.Step() end
        sim.Clock = clock
        return job.done, R.Perf()[name].max
    end""")
    done, coarse = run(sim, ns.Runtime, "test.coarse", 200)
    assert done and coarse > 1 + 0.1  # the risk: ~4 ms against a 1 ms budget
    done, fine = run(sim, ns.Runtime, "test.fine", 1)
    print(f"P2: job max {coarse:.2f} ms yielding every 200, {fine:.2f} ms yielding every 1 (budget 1)")
    assert done and fine <= 1 + 0.1


def replay_P3():
    """Per-frame garbage and idle work. MOVED (now measured): our frame's Lua allocation and widget
    calls, idle and dragging, inside Runtime's frame; and Runtime's frame stats report it."""
    L, sim, ns = shown()
    sim.CountCalls()
    read = ours(L, sim)
    run = L.eval("""function(sim, n, view)
        collectgarbage("collect"); collectgarbage("stop")
        if view then
            sim.MoveCursorTo(view); sim.buttonsDown.LeftButton = true
            sim.FireScript(view, "OnMouseDown", "LeftButton")
        end
        for _ = 1, n do
            if view then sim.cursorX = sim.cursorX + 1 end
            sim.Step()
        end
        if view then sim.buttonsDown.LeftButton = nil; sim.FireScript(view, "OnMouseUp", "LeftButton") end
        collectgarbage("restart")
    end""")
    # Setters on the map's widgets (re-applying unchanged state is the spike's P3); getters are cheap.
    sets = L.eval("""function(sim, root)
        local n = { v = 0 }
        local SETTERS = { "SetPoint", "SetAllPoints", "ClearAllPoints", "SetScale", "SetSize", "SetRotation",
            "SetAlpha", "SetDesaturated", "Show", "Hide", "SetShown", "SetText", "SetTexture", "SetColorTexture",
            "SetVertexColor", "SetStartPoint", "SetEndPoint", "SetThickness", "SetTexCoord" }
        local function walk(w)
            for _, name in ipairs(SETTERS) do
                local fn = w[name]
                if fn then w[name] = function(...) n.v = n.v + 1; return fn(...) end end
            end
            for _, c in ipairs(sim.state[w].children or {}) do walk(c) end
            for _, r in ipairs(sim.state[w].regions or {}) do walk(r) end
        end
        walk(root)
        return n
    end""")(sim, ns.UI.Map.frame)
    run(sim, 120, None)
    n, kb, calls = read()
    idle = (kb / n, sets.v / n)
    run(sim, 120, ns.UI.Map.view)
    n2, kb2, calls2 = read()
    drag = ((kb2 - kb) / (n2 - n), (calls2 - calls) / (n2 - n))
    print(f"P3: our frame idle {idle[0] * 1024:.0f} B, {idle[1]:.1f} setter calls on the map's widgets "
          f"({calls / n:.1f} widget calls in all, getters and the Minimap sensor's included); "
          f"dragging {drag[0] * 1024:.0f} B, {drag[1]:.1f} widget calls")
    assert idle[0] <= 0.1 and drag[0] <= 0.1  # KB a frame: no table a frame (the drag step's camera was ~0.2)
    assert idle[1] == 0  # standing still: the arrow and the canvases are left alone
    stats = ns.Runtime.FrameStats()
    print(f"P3: FrameStats: {stats.kbFrames} frames measured, p95 {stats.kbFrameP95} KB/frame, "
          f"max {stats.kbFrameMax} KB/frame, {stats.kbPerSec} KB/s")
    assert stats.kbFrames > 0 and stats.kbFrameP95 is not None and stats.kbPerSec is not None
    sim.FireEvent("PLAYER_LOGOUT")
    perf = L.globals().MagicMapAtlasDB.telemetry.sessions[1].perf
    assert perf.kbPerSec == stats.kbPerSec and perf.kbFrameP95 is not None
    assert not errors(sim, ns)


def replay_P6():
    """Where time went was invisible. CONTAINED: every script on a frame the addon made is a
    Runtime.Wrap closure (timed per name, isolated), after the map and every /mma command."""
    bare = lua51.LuaRuntime(encoding="latin-1", unpack_returned_tuples=True)
    bare.execute(f"assert(loadfile([[{os.path.join(TESTS, 'wowsim.lua')}]]))()")
    n0 = len(bare.eval("Sim.Frames()"))
    L, sim, ns = shown()
    for name in list(ns.Game.commands.values()):
        if name not in ("map",):
            sim.Slash("/mma " + name)
            sim.Step()
    frames = list(sim.Frames().values())[n0:]
    unwrapped = []
    for f in frames:
        for script, s in sim.state[f].scripts.items():
            for fn in [s.main, *s.hooks.values()]:
                if fn is not None and not ns.Runtime.Wrapped(fn):
                    unwrapped.append(f"{sim.state[f].name or sim.state[f].type}:{script}")
    print(f"P6: {len(frames)} addon frames checked")
    assert len(frames) > 5 and unwrapped == [], unwrapped
    assert not errors(sim, ns)


def replay_G5():
    """Wrong or missing data from runtime sources. PREVENTED: with no QuestieDB loaded, Atlas has
    the NPC services, item icons and quest objectives offline."""
    L, sim, ns = boot()
    A = ns.Atlas
    assert L.globals().QuestieDB is None and L.globals().QuestieLoader is None
    if A.Npc(295) is None:
        pytest.skip("no QuestieDB-derived data (tools/gen_questie.py)")
    assert "innkeeper" in list(A.Npc(295).services.values())  # Innkeeper Farley, Goldshire
    assert A.Item(750).icon is not None  # Tough Wolf Meat (quest 33's objective)
    o = A.Quest(33).objectives[1]
    assert (o.kind, o.id) == ("item", 750)


def replay_K5():
    """A restricted instance. PREVENTED (as a failure): with no position, inst comes from
    GetInstanceInfo; Model drops the old continent's position, the arrow hides, nothing errors."""
    L, sim, ns = shown()
    arrow = L.eval("""function(sim)
        for _, f in ipairs(sim.Frames()) do
            for _, r in ipairs(sim.state[f].regions or {}) do
                if sim.state[r].texture == "Interface\\\\Minimap\\\\MinimapArrow" then return r end
            end
        end
    end""")(sim)
    assert ns.Model.you.col is not None and arrow.IsShown(arrow)
    sim.restricted = True
    sim.player.inst = 389
    sim.FireEvent("PLAYER_ENTERING_WORLD", False, False)
    sim.Run(1)
    you = ns.Model.you
    print(f"K5: you.inst {you.inst}, col {you.col}, map inst {ns.UI.Map.inst}")
    assert you.inst == 389 and you.col is None and not arrow.IsShown(arrow)
    assert not errors(sim, ns), errors(sim, ns)


REPLAYS = {k[len("replay_"):]: v for k, v in globals().items() if k.startswith("replay_")}


@pytest.mark.parametrize("bug", sorted(REPLAYS))
def test_replay(bug):
    REPLAYS[bug]()
