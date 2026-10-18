"""The spike's bugs replayed in the sim: every "Replayable now" scenario of
docs/evidence/spike-bugs.md, one file per bug id, tools/tests/replays/R-<id>.lua
(the doc's replay column names them as test_spike_bugs.py::test_replay[<id>]).
Each sets the initial state, drives inputs frame by frame, and asserts the
outcome the table claims: PREVENTED (the failure can't happen), CONTAINED (it
happens, isolated, recorded in telemetry, the rest runs on), or for MOVED rows
the part the design does bound, with the measured rest printed (pytest -s).

This file collects them: each R-<id>.lua is a Lua chunk called with T, the
harness below, in a Lua of its own. A new replay is a new file."""
import glob
import os

import pytest
from lupa import lua51

import luacheck
from test_addon import TEST_UI, TESTS

REPLAYS = os.path.join(TESTS, "replays")

# T.Boot / T.Shown: test_addon.boot / a shown map, in the replay's own Lua; the rest, the
# helpers the replays share. T.Print writes to the test's output (the sim's print is chat).
HARNESS = r"""
local tests, files, say, skip, TEST_UI = ...
local T = { Print = function(...) say(string.format(...)) end, Skip = skip, TEST_UI = TEST_UI }

-- A simulated client with MagicMapAtlas loaded and logged in: Sim, ns.
-- saved: Lua source for the SavedVariables (MagicMapAtlasDB = ...) found at load (default
-- T.TEST_UI: test_addon.py's window, hidden at login).
-- T.simFrames: the client's own frames, made before ours. On the counted clock (Sim.Counted).
function T.Boot(saved)
	local sim = assert(loadfile(tests .. "/wowsim.lua"))()
	sim.Counted()
	T.simFrames = #sim.Frames()
	local ns = {}
	for _, path in ipairs(files) do -- what exists (test_luacheck flags what's missing)
		local chunk, err = loadfile(path)
		if not chunk then error(err, 0) end
		sim.Call("loading " .. path:match("[^/]+/[^/]+$"), chunk, "MagicMapAtlas", ns)
	end
	assert(loadstring(saved or TEST_UI))()
	sim.FireEvent("ADDON_LOADED", "MagicMapAtlas")
	sim.FireEvent("PLAYER_LOGIN")
	sim.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	local step = sim.onStep
	sim.onStep = function(elapsed)
		step(elapsed)
		T.Invariants(sim, ns)
	end
	return sim, ns
end

-- What holds after every frame of every replay (checked as the next one starts): no protected
-- call made in combat (spike-bugs K2), and no Blizzard Minimap art showing while the takeover
-- has the Minimap (its cluster hidden, or faded while combat keeps it shown).
function T.Invariants(sim, ns)
	local c = sim.protectedCalls[1]
	assert(c == nil, c and ("a protected call in combat: " .. c.call .. c.stack))
	assert(not (ns.Game.minimap.engaged and MinimapCluster:IsVisible() and MinimapCluster:GetEffectiveAlpha() > 0),
		"Blizzard's minimap cluster showing while engaged")
end

-- Booted, the map open and past its first-open grace (2 s).
function T.Shown(saved, seconds)
	local sim, ns = T.Boot(saved)
	sim.Run(1)
	sim.Slash("/mma toggle")
	sim.Run(seconds or 3)
	return sim, ns
end

-- The sim's errors and Runtime's, as strings.
function T.Errors(sim, ns)
	local out = {}
	for _, e in pairs(sim.errors) do out[#out + 1] = tostring(e) end
	for _, e in pairs(ns.Runtime.errors) do out[#out + 1] = e.name .. ": " .. tostring(e.err) end
	return out
end

function T.Layer(ns, name)
	for _, l in ipairs(ns.UI.Engine.layers) do
		if l.name == name then return l end
	end
end

-- The layer shows a layout at the camera's zoom on the map shown, covering the view.
function T.Fresh(ns, lay)
	local m, c = ns.UI.Camera, lay.front
	if c == nil or c.zoom ~= m.cam.zoom or c.inst ~= m.inst then return false end
	local w, h = ns.UI.Window.Size()
	local cam, r = m.cam, c.region
	return r[1] <= cam.cx - w / 2 / cam.zoom and r[3] >= cam.cx + w / 2 / cam.zoom
		and r[2] <= cam.cy - h / 2 / cam.zoom and r[4] >= cam.cy + h / 2 / cam.zoom
end

-- Regions in use on the layer's shown canvas.
function T.Live(lay)
	local n = 0
	if lay.front ~= nil then
		for _, p in pairs(lay.front.pools) do n = n + p.n end
	end
	return n
end

-- Times Runtime caught an error from name.
function T.Errs(ns, name)
	for _, e in pairs(ns.Runtime.errors) do
		if e.name == name then return e.n end
	end
	return 0
end

-- Measure our frame alone: wraps Runtime's OnUpdate (the one OnUpdate the addon set) to sum
-- the Lua heap's growth and widget calls inside it. Returns a reader: frames, KB, calls, and
-- the last frame's KB and ms (debugprofilestop's: the sim's clock).
function T.Ours(sim)
	local m = { n = 0, kb = 0, calls = 0, last = 0, ms = 0 }
	for _, f in ipairs(sim.Frames()) do
		local s = sim.state[f].scripts.OnUpdate
		if s and f ~= Minimap then
			local fn = s.main
			s.main = function(...)
				local k0, c0, t0 = collectgarbage("count"), sim.callTotal, debugprofilestop()
				fn(...)
				m.ms, m.last = debugprofilestop() - t0, collectgarbage("count") - k0
				m.n, m.kb, m.calls = m.n + 1, m.kb + m.last, m.calls + sim.callTotal - c0
			end
		end
	end
	return function() return m.n, m.kb, m.calls, m.last, m.ms end
end

return T
"""


# Replays a price measured in game fails (docs/evidence/perf-m0.md), each until the package named flips it.
XFAIL = {"P3": "M1.5b: every probe makes ~0.35 KB of garbage, answer or not, in game too (here idle 3.5 KB a "
               "frame, the client's p95 34-40 KB): the sensor must probe less"}


def ids():
    return [pytest.param(b, marks=pytest.mark.xfail(strict=True, reason=XFAIL[b])) if b in XFAIL else b
            for b in sorted(os.path.basename(p)[len("R-"):-len(".lua")] for p in glob.glob(os.path.join(REPLAYS, "R-*.lua")))]


@pytest.mark.parametrize("bug", ids())
def test_replay(bug):
    L = lua51.LuaRuntime(encoding="latin-1", unpack_returned_tuples=True)
    files = [os.path.join(luacheck.ROOT, f) for f in luacheck.toc_files() if os.path.exists(os.path.join(luacheck.ROOT, f))]
    T = L.execute(HARNESS, TESTS, L.table_from(files), print, pytest.skip, TEST_UI)
    L.eval("function(path, T) return assert(loadfile(path))(T) end")(os.path.join(REPLAYS, f"R-{bug}.lua"), T)
