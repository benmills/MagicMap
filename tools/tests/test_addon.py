"""The addon's Lua: compile + globals check (tools/luacheck.py over the TOC),
and a headless smoke test on the simulated WoW Forever client
(tools/tests/wowsim.lua): load the TOC's files in order (gitignored
QuestieDB-derived data may be missing: what exists), log in, run ~60
frames and every /mma command, and expect no Lua error anywhere."""
import os
import subprocess
import sys

from lupa import lua51

import luacheck

TESTS = os.path.dirname(os.path.abspath(__file__))


def boot(saved=None):
    """A simulated client with MagicMapAtlas loaded and logged in: (Lua, Sim, ns).
    saved: Lua source for the SavedVariables (MagicMapAtlasDB = ...) found at load."""
    L = lua51.LuaRuntime(encoding="latin-1", unpack_returned_tuples=True)
    sim = L.eval("function(path) return assert(loadfile(path))() end")(os.path.join(TESTS, "wowsim.lua"))
    ns = L.table()
    load = L.eval("""function(path, ns)
        local chunk, err = loadfile(path)
        if not chunk then error(err, 0) end
        return Sim.Call("loading " .. path:match("[^/]+/[^/]+$"), chunk, "MagicMapAtlas", ns)
    end""")
    for f in luacheck.toc_files():  # what exists (test_luacheck flags what's missing)
        if os.path.exists(os.path.join(luacheck.ROOT, f)):
            load(os.path.join(luacheck.ROOT, f), ns)
    if saved:
        L.execute(saved)
    sim.FireEvent("ADDON_LOADED", "MagicMapAtlas")
    sim.FireEvent("PLAYER_LOGIN")
    sim.FireEvent("PLAYER_ENTERING_WORLD", True, False)
    return L, sim, ns


def errors(sim, ns):
    out = [str(e) for e in sim.errors.values()]
    out += [f"{e.name}: {e.err}" for e in ns.Runtime.errors.values()]
    return out


def test_luacheck():
    result = subprocess.run([sys.executable, luacheck.__file__], capture_output=True, text=True)
    assert result.returncode == 0, result.stdout


def test_smoke():
    L, sim, ns = boot()
    sim.Run(1)  # 60 frames
    you = ns.Model.you
    assert you.inst == 0 and abs(you.col - 31.95) < 1e-6 and abs(you.row - 49.75) < 1e-6
    sim.Slash("/mma")
    for name in list(ns.Game.commands.values()):
        sim.Slash("/mma " + name)
        sim.Step()
    assert ns.Runtime.Perf()[0]["game.observe"].n >= 60

    # Runtime: timers, a budgeted job, and a failing step kept apart from the rest (throttled after 10).
    got = L.eval("""function(R)
        local got = { every = 0, steps = 0 }
        R.After(0.1, "test.after", function() got.after = true end)
        R.Every(0.1, "test.every", function() got.every = got.every + 1 end)
        got.job = R.Job("test.job", function()
            local x = 0
            for i = 1, 5e4 do x = x + i; R.Yield() end
            got.sum = x
        end, 1)
        R.Step("model", "test.fails", function() error("boom") end)
        R.Step("apply", "test.after-fail", function() got.steps = got.steps + 1 end)
        return got
    end""")(ns.Runtime)
    sim.Run(1)
    assert got.after and 8 <= got.every <= 11 and got.steps == 60
    assert got.job.done and got.sum == 5e4 * (5e4 + 1) / 2 and ns.Runtime.Perf()[0]["test.job"].n > 1
    assert [(e.name, e.n) for e in ns.Runtime.errors.values()] == [("test.fails", 10)]
    # Telemetry: kept with its stack, and its first occurrence took an "error" mark with the trace.
    tel = L.globals().MagicMapAtlasDB.telemetry
    err = next(e for e in tel.errors.values() if e.name == "test.fails")
    assert err.count == 10 and "boom" in err.msg and "Runtime.lua" in err.stack
    mark = next(m for m in tel.marks.values() if m.kind == "error" and "test.fails" in m.note)
    assert mark.state.map and len(mark.trace) > 0 and mark.trace[len(mark.trace)].k == "error"
    del ns.Runtime.errors[1]
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_boundaries(capsys):
    """luacheck's boundary rules fire (the default run checks the real files)."""
    refs = luacheck.ns_refs('local G, A = ns.Game, ns.Atlas -- ns.UI.Map\nG.Load(1); A:X(); s = "ns.Model.x"\nns.UI.View.y')
    assert sorted(refs) == [("Atlas", "X", 2), ("Game", "Load", 2), ("UI", "View", 3)]
    acc = {"ui/X.lua": [("get", "CreateFrame", 1), ("get", "C_Map", 2), ("get", "MagicMapAtlasDB", 3)],
           "model/X.lua": [("get", "print", 1)], "game/X.lua": [("get", "MagicMapAtlasDB", 1)]}
    assert luacheck.check_boundaries(acc) == 3
    out = capsys.readouterr().out
    assert "ui/X.lua:2" in out and "ui/X.lua:3" in out and "model/X.lua:1" in out and "game/X" not in out


def test_attribution():
    """docs/runtime.md "Attribution": KB per name, a job's gap, the worst frames, frames by map state."""
    L, sim, ns = boot()
    R = ns.Runtime
    sim.Run(6)  # past login's grace
    got = L.eval("""function(R)
        local got = {}
        collectgarbage("stop") -- exact KB: nothing freed meanwhile
        R.Job("test.alloc", function() got.s = string.rep("x", 100 * 1024) end)
        R.Job("test.gap", function()
            R.Yield()
            local t = debugprofilestop(); while debugprofilestop() - t < 10 do end
            R.Yield(); R.Yield()
        end)
        R.Step("ui", "test.slow", function()
            if not got.spin then return end
            got.spin, got.s2 = nil, string.rep("y", 4 * 1024)
            local t = debugprofilestop(); while debugprofilestop() - t < 12 do end
        end)
        return got
    end""")(R)
    sim.Run(0.5)
    got.spin = True
    sim.Step()
    spun = R.frames
    for i in range(12):
        R.Trace("test", i)
        sim.Step()
    L.eval('collectgarbage("restart")')
    stats = R.FrameStats()
    # a job making 100 KB tops alloc; the frame's spike names its slowest call and its top allocator
    top = stats.alloc[1]
    assert top.name == "test.alloc" and top.kbMax >= 100 and top.calls == 1 and len(stats.alloc) <= 5
    spike = next(e for e in R.TraceCopy().values() if e.k == "spike" and e.f == spun)
    assert spike.d.top == "test.slow" and spike.d.alloc == "test.slow" and spike.d.allocKb >= 4
    # 10 ms between two Yields: one gap, traced once, with the stack where it yielded
    assert [(g.job, g.n) for g in stats.gaps.values()] == [("test.gap", 1)]
    gap = stats.gaps[1]
    assert gap.ms >= 10 and "string" in gap.stack
    assert len([e for e in R.TraceCopy().values() if e.k == "gap" and e.d.job == "test.gap"]) == 1
    # the worst frame, with the (up to) 10 events to its end, the spike last, and the 10 after
    worst = stats.ledger[1]
    assert len(stats.ledger) == 5 and worst.frame == spun and worst.top == "test.slow"
    ks = [(e.k, e.d) for e in worst.events.values()]
    assert ks[-11][0] == "spike" and ks[-10:] == [("test", i) for i in range(10)] and len(ks) <= 20
    # frames by map state
    m = ns.UI.Map
    m.Toggle()
    sim.Run(3)
    sim.Wheel(m.view, 4)
    sim.Run(1)
    sim.Drag(m.view, 200, 0)
    m.Toggle()
    sim.Run(0.5)
    stats = R.FrameStats()
    by = stats.byState
    assert all(by[s].frames > 0 for s in ("closed", "small", "zoom", "drag")), dict(by)
    assert sum(by[s].frames for s in ("closed", "small", "zoom", "drag")) == stats.frames
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_failures():
    """docs/runtime.md: each frame-loop failure driven in the sim, and its guarantee held."""
    L, sim, ns = boot("""MagicMapAtlasDB = { telemetry = "corrupt", old = { _v = 1, n = "x" }, new = { _v = 9, keep = 1 }, bad = { x = 1 } }""")
    R, G = ns.Runtime, L.globals()
    got = L.eval("""function(R, Game)
        local got = { steps = 0, every = 0, added = 0, load = {} }
        -- saved data: not a table (reset, above), older (defaults by type), newer (left alone)
        Game.Load("old", function(s) got.load.old = s end, { version = 2, defaults = { n = 0, list = {} } })
        Game.Load("new", function(s) got.load.new = s end, { version = 2, defaults = { n = 0 } })
        Game.Load("bad", function() error("loader") end, { version = 1, migrate = function() error("migrate") end })
        R.Step("model", "test.fails", function() error("boom") end)
        R.Step("ui", "test.slow", function()
            if got.spin then got.spin = nil; local t = debugprofilestop(); while debugprofilestop() - t < 12 do end end
        end)
        R.Step("apply", "test.runs", function() got.steps = got.steps + 1 end)
        R.Step("input", "test.adder", function()
            if got.adder then return end
            got.adder = true
            R.Step("input", "test.added", function() got.added = got.added + 1 end)
        end)
        R.On("TEST_EVENT", "test.event", function() got.eventInFrame = got.inStep end)
        R.Step("model", "test.fires", function()
            if not got.fire then return end
            got.fire, got.inStep = nil, true
            Sim.FireEvent("TEST_EVENT")
            got.inStep = false
        end)
        R.Every(0.1, "test.every", function() got.every = got.every + 1 end)
        got.stuck = R.Job("test.stuck", function() while true do coroutine.yield() end end, 1, 30)
        got.hog = R.Job("test.hog", function() local t = debugprofilestop(); while debugprofilestop() - t < 6 do end end, 1)
        return got
    end""")(R, ns.Game)
    sim.Run(6)  # past login's grace
    assert got.load.old.n == 0 and got.load.old.list is not None and got.load.old._v == 2
    assert G.MagicMapAtlasDB.new.keep == 1 and G.MagicMapAtlasDB.new._v == 9 and got.load.new.n == 0
    assert G.MagicMapAtlasDB.telemetry.sessions[1].id == 1 and G.MagicMapAtlasDB.bad.x is None  # migrate failed: reset
    # erroring step: the rest ran every frame; recorded once (one entry, one stack, one mark), then throttled
    assert got.steps == 360 and got.added == 359
    fails = next(e for e in R.errors.values() if e.name == "test.fails")
    assert 10 <= fails.n <= 17
    tel = G.MagicMapAtlasDB.telemetry
    assert len([e for e in tel.errors.values() if e.name == "test.fails"]) == 1
    assert len([m for m in tel.marks.values() if m.note and "test.fails" in m.note]) == 1
    # stuck job cancelled and reported; a job that never yields overran
    assert got.stuck.done and "cancelled" in got.stuck.err and any(e.name == "test.stuck" for e in R.errors.values())
    assert got.hog.done and R.Perf()[0]["test.hog"].over == 1
    # overrunning step: counted, and the frame traced as a spike naming it
    got.spin = True
    sim.Step()
    assert R.Perf()[0]["test.slow"].over == 1
    spike = [e for e in R.TraceCopy().values() if e.k == "spike"][-1]
    assert spike.d.top == "test.slow" and R.FrameStats().overruns >= 1
    # an event fired mid-frame waits for the frame's end
    got.fire = True
    sim.Step()
    assert got.eventInFrame is False
    # a hitch: an Every fires once, not a burst
    n = got.every
    sim.Step(2.0)
    assert got.every == n + 1
    # nil position (instance), map shown: last known kept, stale; then back
    ns.UI.Map.Toggle()
    sim.Run(0.5)
    sim.restricted = True
    sim.FireEvent("PLAYER_ENTERING_WORLD", False, False)
    sim.Run(1)
    you = ns.Model.you
    assert you.stale and you.inst == 0 and you.col is not None
    sim.restricted = False
    sim.Run(0.2)
    assert not you.stale
    # error reporting that itself fails: switched off, no recursion
    R.onError = L.eval("function() error('report') end")
    R.Step("model", "test.fails2", L.eval("function() error('again') end"))
    sim.Step()
    assert R.onError is None
    # telemetry: the session's perf, written at logout
    sim.FireEvent("PLAYER_LOGOUT")
    perf = tel.sessions[1].perf
    assert perf.frames > 0 and 0 < perf.p50 <= perf.p95 <= perf.p99 <= perf.max and perf.overruns >= 1
    assert perf.errors >= 3 and perf.errorsPerHour > 0 and perf.loadMs > 0 and perf.ourKB > 0
    assert perf.grace.login > 0 and perf.grace.map > 0 and perf.grace.loading is not None
    expected = {"test.fails", "test.fails2", "test.stuck", "load bad", "load bad (migrate)"}
    assert {e.name for e in R.errors.values()} == expected
    assert not list(sim.errors.values()), "\n\n".join(sim.errors.values())
