"""The addon's Lua: compile + globals check (tools/luacheck.py over the TOC),
and a headless smoke test on the simulated WoW Forever client
(tools/tests/wowsim.lua): load the TOC's files in order (gitignored
QuestieDB-derived data may be missing: what exists), log in, run ~60
frames and every /mma command, and expect no Lua error anywhere."""
import subprocess
import sys

import luacheck
from sim import TEST_UI, TESTS, errors, load as boot  # noqa: F401 (the tests' boot, shared with tools/sim.py)


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
            for i = 1, 5e4 do x = x + i; Sim.Spend(0.0002); R.Yield() end -- 10 ms of work
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
    # ONLY (Runtime.On: game/; UI.View: game/Apply.lua), writes to another system (but its hooks), UI's Model
    # fields, named frames (a comment's isn't one), a QuestPOIFrame outside POI_FILES
    poi = 'CreateFrame("QuestPOIFrame", nil, c)\n'
    ui = luacheck.ns_problems("ui/X.lua", 'local R = ns.Runtime\nR.On("PLAYER_LOGIN", "x", f)\nns.Runtime.Trace = f\n'
                              'ns.Model.Observe({}, {})\nns.Model.Known("blips")\n'
                              'CreateFrame("Frame", "Foo", UIParent) -- CreateFrame("Frame", "Bar")\n' + poi, set())
    assert [p.split(": ", 1)[0] for p in ui] == ["ui/X.lua:2", "ui/X.lua:4", "ui/X.lua:3", "ui/X.lua:6", "ui/X.lua:7"], ui
    assert luacheck.ns_problems("ui/Areas.lua", poi, set()) == [] and luacheck.ns_problems("game/Oracles.lua", poi, set()) == []
    game = luacheck.ns_problems("game/X.lua", 'local R = ns.Runtime\nfunction R.Trace() end\nR.onTrace = f\n'
                                'R.onError = f\nns.UI.View()\nR.On("E", "x", f)\n', set())
    assert [p.split(": ", 1)[0] for p in game] == ["game/X.lua:5", "game/X.lua:2"], game
    assert luacheck.ns_problems("game/Apply.lua", "local ok, view = pcall(ns.UI.View)", set()) == []
    # NOT_IN: Game's parts and commands register no apply step (they read Game.shownInst)
    part = 'local Game = ns.Game\nGame.Apply("x", f)\nlocal i = Game.shownInst\n'
    assert [p.split(": ", 1)[0] for p in luacheck.ns_problems("game/parts/X.lua", part, set())] == ["game/parts/X.lua:2"]
    assert luacheck.ns_problems("game/X.lua", part, set()) == []


def test_open_fields_nil():
    """A View and an Observation with only their required fields (every OPEN one nil:
    types/view.lua, observation.lua) run whole frames: Game applies, Model merges, UI draws."""
    L, sim, ns = boot()
    sim.Slash("/mma toggle")
    sim.Run(1)
    got = L.eval("""function(ns)
        local UI, Model, got = ns.UI, ns.Model, {}
        local w = UI.View().window
        local view = { v = 1, frame = 0, minimap = "ours", renderer = "ours", inst = 0, layers = { blips = true },
            sockets = {}, button = true, window = { shown = true, big = false, place = w.place, still = true,
            strata = w.strata, level = w.level, homeAlpha = 1 } }
        got.View, got.Observe = UI.View, Model.Observe
        UI.View = function() return view end
        Model.Observe = function(obs, oracles)
            local y = obs.you
            got.Observe({ frame = obs.frame, t = obs.t, hooked = {},
                you = { inst = y.inst, col = y.col, row = y.row, facing = y.facing } }, oracles)
        end
        return got
    end""")(ns)
    sim.Run(1)
    sim.Slash("/mma mark bare")
    assert ns.Game.minimap.engaged
    marks = L.globals().MagicMapAtlasDB.telemetry.marks
    assert marks[len(marks)].note == "bare" and marks[len(marks)].state.map is None  # no diag
    kinds = ["blips", "rares", "quests", "offers", "places", "group", "corpse", "waypoint", "vignettes", "services"]
    for kind in kinds:
        items, rev = ns.Model.Known(kind)
        assert isinstance(rev, (int, float)), kind
        for k in items.values():
            assert k.kind == kind and isinstance(k.key, str) and isinstance(k.name, str) and k.live in (True, False)
            assert k.pos.inst is not None and k.pos.col is not None and k.pos.row is not None
    target, route = ns.Model.Target(), ns.Model.Route()
    assert target in (None, False) or target.pos.col is not None
    assert route is None or all(p.col is not None for p in route.values())
    ns.UI.View, ns.Model.Observe = got.View, got.Observe
    sim.Run(0.5)
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


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
            Sim.Spend(10)
            R.Yield(); R.Yield()
        end)
        R.Step("ui", "test.slow", function()
            if not got.spin then return end
            got.spin, got.s2 = nil, string.rep("y", 4 * 1024)
            Sim.Spend(12)
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
    w = ns.UI.Window
    w.Toggle()
    sim.Run(3)
    sim.Wheel(w.view, 4)
    sim.Run(1)
    sim.Drag(w.view, 200, 0)
    # a drag's last frame drawn slowly (100 ms: the next OnUpdate's elapsed, once the drag ended): the drag's
    sim.MoveCursorTo(w.view)
    sim.buttonsDown.LeftButton = True
    sim.FireScript(w.view, "OnMouseDown", "LeftButton")
    for _ in range(10):
        sim.cursorX = sim.cursorX + 20
        sim.Step()
    sim.buttonsDown.LeftButton = None
    sim.FireScript(w.view, "OnMouseUp", "LeftButton")
    sim.Step(0.1)
    sim.Step()
    w.Toggle()
    sim.Run(0.5)
    stats = R.FrameStats()
    by = stats.byState
    assert all(by[s].frames > 0 for s in ("closed", "small", "zoom", "drag")), dict(by)
    assert sum(by[s].frames for s in ("closed", "small", "zoom", "drag")) == stats.frames
    # and the client's whole frame in each (the sim's: 1/60 s)
    assert all(16.5 <= by[s].client.p50 <= 17 and by[s].client.max >= 16.6 for s in ("closed", "small", "zoom", "drag"))
    assert by.drag.client.max >= 100 and by.small.client.max < 20
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_failures():
    """docs/runtime.md: each frame-loop failure driven in the sim, and its guarantee held."""
    L, sim, ns = boot("""MagicMapAtlasDB = { telemetry = "corrupt", old = { _v = 1, n = "x" }, new = { _v = 9, keep = 1 }, bad = { x = 1 },
        UI = { _v = 1, shown = false, follow = false, inst = 0, center = 5, zoom = 96 }, Game = { _v = 1, buttonAngle = "north" },
        validation = { _v = 1, on = "yes" } }""")
    R, G = ns.Runtime, L.globals()
    got = L.eval("""function(R, Game)
        local got = { steps = 0, every = 0, added = 0, load = {} }
        -- saved data: not a table (reset, above), older (defaults by type), newer (left alone)
        Game.Load("old", function(s) got.load.old = s end, { version = 2, defaults = { n = 0, list = {} } })
        Game.Load("new", function(s) got.load.new = s end, { version = 2, defaults = { n = 0 } })
        Game.Load("bad", function() error("loader") end, { version = 1, migrate = function() error("migrate") end })
        R.Step("model", "test.fails", function() error("boom") end)
        R.Step("ui", "test.slow", function()
            if got.spin then got.spin = nil; Sim.Spend(12) end
            if got.spinGc then got.spinGc, got.junk = nil, nil; collectgarbage("collect"); Sim.Spend(12) end
        end)
        got.junk = {}
        for i = 1, 50000 do got.junk[i] = { i } end
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
        return got
    end""")(R, ns.Game)
    sim.Run(6)  # past login's grace (inside a grace nothing overruns)
    assert got.load.old.n == 0 and got.load.old.list is not None and got.load.old._v == 2
    assert G.MagicMapAtlasDB.new.keep == 1 and G.MagicMapAtlasDB.new._v == 9 and got.load.new.n == 0
    assert G.MagicMapAtlasDB.telemetry.sessions[1].id == 1 and G.MagicMapAtlasDB.bad.x is None  # migrate failed: reset
    # a key without a default, of another type: dropped (UI's center, then saved again where the view is;
    # Game's buttonAngle); the loaders ran whole (no "load UI" error: the expected set below)
    db, kind = G.MagicMapAtlasDB, L.eval("type")
    assert kind(db.UI.center) == "table" and db.UI.inst == 0 and db.Game.buttonAngle is None and db.validation.on is False
    # erroring step: the rest ran every frame; recorded once (one entry, one stack, one mark), then throttled
    assert got.steps == 360 and got.added == 359
    fails = next(e for e in R.errors.values() if e.name == "test.fails")
    assert 10 <= fails.n <= 17
    tel = G.MagicMapAtlasDB.telemetry
    assert len([e for e in tel.errors.values() if e.name == "test.fails"]) == 1
    assert len([m for m in tel.marks.values() if m.note and "test.fails" in m.note]) == 1
    # stuck job cancelled and reported; a job that never yields overran
    hog = L.eval("""function(R)
        return R.Job("test.hog", function() Sim.Spend(6) end, 1)
    end""")(R)
    sim.Step()
    assert got.stuck.done and "cancelled" in got.stuck.err and any(e.name == "test.stuck" for e in R.errors.values())
    assert hog.done and R.Perf()[0]["test.hog"].over == 1
    # overrunning step: counted, and the frame traced as a spike naming it
    got.spin = True
    sim.Step()
    assert R.Perf()[0]["test.slow"].over == 1
    spike = [e for e in R.TraceCopy().values() if e.k == "spike"][-1]
    assert spike.d.top == "test.slow" and R.FrameStats().overruns >= 1
    # over budget while the collector freed more than the call made (its step, paid for everyone's
    # garbage): counted apart, not an overrun of its own
    got.spinGc = True
    sim.Step()
    assert R.Perf()[0]["test.slow"].over == 1 and R.Perf()[0]["test.slow"].gc == 1
    assert R.FrameStats().slowGc[1].name == "test.slow"
    # an event fired mid-frame waits for the frame's end
    got.fire = True
    sim.Step()
    assert got.eventInFrame is False
    # a hitch: an Every fires once, not a burst
    n = got.every
    sim.Step(2.0)
    assert got.every == n + 1
    # nil position (instance), map shown: last known kept, stale; then back
    ns.UI.Window.Toggle()
    sim.Run(0.5)
    sim.restricted = True
    sim.FireEvent("PLAYER_ENTERING_WORLD", False, False)
    sim.Run(1)
    you = ns.Model.you
    assert you.stale and you.inst == 0 and you.col is not None
    sim.restricted = False
    sim.Run(0.2)
    assert not you.stale
    # a failing part (you, 0.2 s): obs.you all unknown, so Model keeps its last belief (stale) and
    # telemetry runs on, and reporting stays on
    ghost = G.UnitIsGhost
    G.UnitIsGhost = L.eval("function() error('boom') end")
    sim.Run(0.2)
    assert you.stale and you.col is not None and ns.Game.obs.you.col is None
    G.UnitIsGhost = ghost
    sim.Run(1.2)  # (failing on, a wrapped call is tried once a second)
    assert R.onError is not None and ns.Game.obs.you.col is not None and not you.stale
    assert any(e.name == "game.part you" for e in tel.errors.values())
    # error reporting that itself fails: switched off, no recursion
    R.onError = L.eval("function() error('report') end")
    R.Step("model", "test.fails2", L.eval("function() error('again') end"))
    sim.Step()
    assert R.onError is None
    # telemetry: the session's perf, written at logout
    sim.FireEvent("PLAYER_LOGOUT")
    perf = tel.sessions[1].perf
    assert perf.frames > 0 and 0 < perf.p50 <= perf.p95 <= perf.p99 <= perf.max and perf.overruns >= 1
    # (loadMs: Data's load is Lua alone, which the counted clock doesn't charge: 0 here, recorded)
    assert perf.errors >= 3 and perf.errorsPerHour > 0 and perf.loadMs == 0 and perf.ourKB > 0
    assert perf.grace.login > 0 and perf.grace.map > 0 and perf.grace.loading is not None
    expected = {"test.fails", "test.fails2", "test.stuck", "load bad", "load bad (migrate)", "game.part you"}
    assert {e.name for e in R.errors.values()} == expected
    assert not list(sim.errors.values()), "\n\n".join(sim.errors.values())
