-- M1: the route line misbehaved: it hopped sideways onto a crooked detour, flashed straight while
-- re-routing, and the target flickered between arrived and not at an area's edge. MOVED: Target and
-- Route are Model's (model/Target.lua, Route.lua), the spike's logic fed observations, so replayed
-- frame by frame here. Your waypoint at Lakeshire (obs.waypoint from a part of the replay's own, as
-- M3.2's hands it), the route's searches on a clock that counts their Lua (R-P2's), from Goldshire:
--   1. 2 chunks off the route, beside one of its legs: the line's first point is you, its second the
--      furthest of the route's points ahead in sight, not the one behind you; it isn't found again.
--   2. The quest you follow, its area's edge crossed back and forth every 0.2 s for 2 s: inside flips
--      at most once (a change counts once it has held 0.5 s).
--   3. The target 3 chunks on: the old route stays till the new one's found, no straight frame.
local T = ...
local sim, ns = T.Shown()
local A, Model, R = ns.Atlas, ns.Model, ns.Runtime
local CHUNK = 1 / 16

local waypoint = false
ns.Game.Part("waypoint", function() return waypoint end)
local jobs, counted, Job = {}, 0, R.Job
local clock = sim.Clock
sim.Clock = function() return clock() + counted * 0.00001 end
R.Job = function(name, fn, ...)
	if name ~= "model: route" then return Job(name, fn, ...) end
	local j = Job(name, function()
		debug.sethook(function() counted = counted + 100 end, "", 100)
		fn()
		debug.sethook()
	end, ...)
	jobs[#jobs + 1] = j
	return j
end

local me = sim.player
me.col, me.row = 31.95, 49.75
waypoint = { inst = 0, col = 36.09, row = 49.28 }
for _ = 1, 100 do
	sim.Step()
	if Model.Route() then break end
end
local first = {} -- the route's points ahead of where you started (its first, Model.you, left out)
for i = 2, #Model.Route() do first[i - 1] = Model.Route()[i] end
local function Index(p)
	for i, q in ipairs(first) do
		if q == p then return i end
	end
end

-- 1. Beside the leg from first[k] to first[k + 1], 2 chunks off it.
local k = 3
local a, b = first[k], first[k + 1]
local dx, dy = b.col - a.col, b.row - a.row
local len = math.sqrt(dx * dx + dy * dy)
me.col, me.row = (a.col + b.col) / 2 - dy / len * 2 * CHUNK, (a.row + b.row) / 2 + dx / len * 2 * CHUNK
sim.Run(0.5)
local way = Model.Route()
local m = Index(way[2])
T.Print("M1: 2 chunks beside leg %d-%d of %d: the line's second point the route's %d", k, k + 1, #first, m)
assert(way[1] == Model.you and m and m > k and #jobs == 1)

-- 2. The quest you follow (it comes before the waypoint): its area a circle about its pin, crossed
-- every 0.2 s.
local MAP, r = 1429, 0.05
local x, y = A.TileToMap(MAP, 31.8, 49.7)
sim.quests = { [52] = { title = "Protect the Frontier", level = 11, map = MAP, x = x, y = y, complete = false,
	objectives = { { type = "monster", text = "Prowler slain: 2/8", numFulfilled = 2, numRequired = 8, finished = false } } } }
sim.blobShapes[52] = { x, y, r }
sim.superTracked = 52
sim.FireEvent("QUEST_LOG_UPDATE")
local _, inCol, inRow = A.MapToTile(MAP, x + 0.95 * r, y)
local _, outCol, outRow = A.MapToTile(MAP, x + 1.05 * r, y)
me.col, me.row = outCol, outRow
sim.Run(1)
assert(Model.Target().kind == "quest" and Model.Target().inside == false)
local flips, was = 0, false
for i = 1, 10 do
	if i % 2 == 1 then me.col, me.row = inCol, inRow else me.col, me.row = outCol, outRow end
	for _ = 1, 12 do -- 0.2 s at 60 fps
		sim.Step()
		local inside = Model.Target().inside
		if inside ~= was then flips, was = flips + 1, inside end
	end
end
T.Print("M1: the area's edge crossed 10 times in 2 s: inside flipped %d times", flips)
assert(flips <= 1)

-- 3. Back to the waypoint; the target 3 chunks on.
sim.superTracked = 0
sim.FireEvent("SUPER_TRACKING_CHANGED")
me.col, me.row = 31.95, 49.75
sim.Run(1)
local n = #jobs
local old = Model.Route()
assert(old and not old.straight and old[#old] == Model.Target().pos)
waypoint = { inst = 0, col = 36.09 + 3 * CHUNK, row = 49.28 }
local frames = 0
repeat
	sim.Step()
	frames = frames + 1
	local now = Model.Route()
	assert(now and not now.straight, "a frame without the route")
until #jobs > n and jobs[n + 1].done
sim.Step()
local new = Model.Route()
T.Print("M1: the target 3 chunks on: the old route shown %d frames till the new one was found", frames)
assert(#jobs == n + 1 and frames > 2 and new[2] ~= old[2] and new[#new] == Model.Target().pos)
local errs = T.Errors(sim, ns)
assert(#errs == 0, table.concat(errs, "\n"))
