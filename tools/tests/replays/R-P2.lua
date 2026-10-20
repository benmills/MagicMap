-- P2: cooperative budget overrun. MOVED: Yield checks the budget only where the job calls it, so
-- a job yielding every 200 iterations overruns (and Perf's max shows it); one that yields every
-- iteration keeps to budget + one iteration. Then every Atlas first use, as Atlas yields it, and
-- Model's route search (v1).
local T = ...
local sim, ns = T.Boot()
sim.Run(1)
local R = ns.Runtime
local function Run(name, every)
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
end
local done, coarse = Run("test.coarse", 200)
assert(done and coarse > 1 + 0.1) -- the risk: ~4 ms against a 1 ms budget
local fine
done, fine = Run("test.fine", 1)
T.Print("P2: job max %.2f ms yielding every 200, %.2f ms yielding every 1 (budget 1)", coarse, fine)
assert(done and fine <= 1 + 0.1)

-- The M1 exit's "every Atlas first use in a 1 ms Job <= 2 ms" (docs/structure.md "Atlas first use"):
-- each whole-table index built fresh in a Runtime.Job of budget 1, Runtime.Yield its step, on a clock
-- that counts Lua's VM instructions in the job (debug.sethook: the same count every run; NS ms each,
-- 100 M a second, about this machine's Lua and the client's): no resume over 2 ms. Without
-- QuestieDB's data (CI) only the areas' (ZoneLevels); model/Services.lua's job (ServiceSpawns' first use) runs at 1 ms too.
local NS, EVERY = 0.00001, 100
local Atlas, counted = ns.Atlas, 0
local function Count() counted = counted + EVERY end
local function First(name, use)
	local clock = sim.Clock
	sim.Clock = function() return counted * NS end
	local job = R.Job(name, function()
		debug.sethook(Count, "", EVERY)
		use(R.Yield)
		debug.sethook()
	end, 1)
	for _ = 1, 600 do if job.done then break end sim.Step() end
	sim.Clock = clock
	local p = R.Perf()[name]
	assert(job.done and not job.err, name .. ": " .. tostring(job.err))
	return p.max, job.resumes
end
local uses = {
	{ "ZoneLevels", function(step) Atlas.ZoneLevels(12, step) end },
}
if Atlas.Data.Npcs then
	for _, u in ipairs({
		{ "Rares", function(step) Atlas.Rares(0, step) end },
		{ "ServiceSpawns", function(step) Atlas.ServiceSpawns(0, step) end },
		{ "Find npc", function(step) Atlas.Find("npc", "kobold", 10, step) end },
		{ "Find object", function(step) Atlas.Find("object", "chest", 10, step) end },
		{ "Find item", function(step) Atlas.Find("item", "linen", 10, step) end },
		{ "Find quest", function(step) Atlas.Find("quest", "kobold", 10, step) end },
	}) do uses[#uses + 1] = u end
else
	T.Print("P2: no QuestieDB-derived data: only ZoneLevels' first use")
end
local each = {}
for _, u in ipairs(uses) do
	local max, frames = First("test.first " .. u[1], u[2])
	each[#each + 1] = string.format("%s %.2f ms (%d frames)", u[1], max, frames)
	assert(max <= 2, u[1] .. ": " .. max .. " ms")
end
T.Print("P2: Atlas first uses in a 1 ms job, slowest resume: %s", table.concat(each, ", "))

-- v1, the route (model/Route.lua): A* in a Runtime.Job of SLICE_MS (1), Runtime.Yield a node, on the
-- same clock: Goldshire (31.95, 49.75) to Lakeshire, your waypoint (a part of the replay's own, as
-- M3.2's hands it), found within 60 frames, no resume over 1.2 ms.
local waypoint = false
ns.Game.Part("waypoint", function() return waypoint end)
local Job, route = R.Job, nil
R.Job = function(name, fn, ...)
	if name ~= "model: route" then return Job(name, fn, ...) end
	route = Job(name, function()
		debug.sethook(Count, "", EVERY)
		fn()
		debug.sethook()
	end, ...)
	return route
end
local clock = sim.Clock
sim.Clock = function() return clock() + counted * NS end
sim.Slash("/mm toggle")
sim.Run(1)
waypoint = { inst = 0, col = 36.09, row = 49.28 }
local frames = 0
repeat
	sim.Step()
	frames = frames + 1
until ns.Model.Route() or frames == 60
local p = R.Perf()["model: route"]
T.Print("P2: the route Goldshire to Lakeshire in %d frames, its slowest resume %.2f ms (budget 1)", frames, p.max)
assert(ns.Model.Route() and not ns.Model.Route().straight and route.done and p.max <= 1.2)
R.Job, sim.Clock = Job, clock
