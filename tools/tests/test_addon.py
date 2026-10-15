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


def boot():
    """A simulated client with MagicMapAtlas loaded and logged in: (Lua, Sim, ns)."""
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

    # Runtime: timers, a budgeted job, and a failing step kept apart from the rest.
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
    assert [(e.name, e.n) for e in ns.Runtime.errors.values()] == [("test.fails", 60)]
    del ns.Runtime.errors[1]
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
