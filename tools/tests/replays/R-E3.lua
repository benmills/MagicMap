-- E3: route finding failed in the Barrens and the line fell back straight: line of sight divided by
-- a column or row count of 0 (plain Lua gives inf, WoW's raises). MOVED, bounded by tools/lint_div.py
-- and the strict runs (MM_STRICT=1: the sim's x/0 raises, as the client's); model/Route.lua's Sight
-- now compares the next boundary multiplied out, no divide. Replayed: your waypoint on your own row,
-- then on your own column, in the Elwynn plain and in the Barrens (obs.waypoint from a part of the
-- replay's own, as M3.2's hands it): a route each time, not straight, every number in it finite.
local T = ...
local sim, ns = T.Shown()
local Model = ns.Model

local waypoint = false
ns.Game.Part("waypoint", function() return waypoint end)
local function Finite(v) return v == v and v ~= math.huge and v ~= -math.huge end

local me, each = sim.player, {}
for _, c in ipairs({
	{ "Elwynn, a row", 0, 31.95, 49.75, 33.2, 49.75 },
	{ "Elwynn, a column", 0, 31.95, 49.75, 31.95, 50.6 },
	{ "the Barrens, a row", 1, 36.97, 32.9, 38.4, 32.9 },
	{ "the Barrens, a column", 1, 36.97, 32.9, 36.97, 34.4 },
}) do
	me.inst, me.col, me.row = c[2], c[3], c[4]
	sim.Run(0.5) -- (the view follows you there)
	waypoint = { inst = c[2], col = c[5], row = c[6] }
	local way
	for _ = 1, 60 do
		sim.Step()
		way = Model.Route()
		if way then break end
	end
	assert(way and not way.straight, c[1] .. ": no route")
	for _, p in ipairs(way) do assert(Finite(p.col) and Finite(p.row), c[1] .. ": a number not finite") end
	each[#each + 1] = string.format("%s %d points", c[1], #way)
	waypoint = false
end
T.Print("E3: a route to your own row and column: %s", table.concat(each, ", "))
local errs = T.Errors(sim, ns)
assert(#errs == 0, table.concat(errs, "\n"))
