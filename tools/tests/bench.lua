-- Benchmarks for tools/bench.py: each drives the map the way a player would
-- while bench.py records, per frame, the addon's Lua time, the widget calls
-- it made, and whether zone borders covered the whole view.

local Sim, ns = ...
local benches = {}

local function Drag(dx, dy, frames)
	Sim.Drag(ns.viewport, dx, dy, frames)
end

-- Walking (well, riding) through Elwynn with the map following you.
benches.follow_ride = function()
	ns.SetZoom(256)
	Sim.player.speed, Sim.player.facing = 30, 0.6
	Sim.Run(15)
	Sim.player.speed = 0
end

-- Flinging the map around at street-to-zone zoom.
benches.fast_pan = function()
	ns.SetZoom(160)
	Sim.Run(1)
	for i = 1, 12 do
		local dir = (i % 4)
		local dx = ({ 600, 0, -600, 0 })[dir + 1]
		local dy = ({ 0, 400, 0, -400 })[dir + 1]
		Drag(dx, dy, 12) -- 600 px in a fifth of a second
		Sim.Run(0.1)
	end
	Sim.Run(1)
end

-- Panning across the whole continent, zoomed out.
benches.continent_pan = function()
	ns.SetZoom(20)
	Sim.Run(1)
	for i = 1, 8 do
		Drag(i % 2 == 0 and 500 or -500, i % 3 == 0 and 300 or -200, 20)
		Sim.Run(0.2)
	end
	Sim.Run(1)
end

-- Wheel all the way out and back in.
benches.wheel_zoom = function()
	ns.SetZoom(512)
	Sim.Run(1)
	for _ = 1, 25 do Sim.Wheel(ns.viewport, -1); Sim.Run(0.08) end
	Sim.Run(1)
	for _ = 1, 25 do Sim.Wheel(ns.viewport, 1); Sim.Run(0.08) end
	Sim.Run(1)
end

-- Minimap mode, as it's mostly used: a party of four, path mode toward a
-- waypoint. The map is always open here, so even standing still counts.
local function MinimapSetup()
	Sim.Click(ns.modeButton)
	Sim.Run(1)
	for i = 1, 4 do
		Sim.units["party" .. i] = { name = "Friend" .. i, class = "PRIEST", level = 6,
			col = Sim.player.col + 0.03 * i, row = Sim.player.row - 0.02 * i }
	end
	Sim.group = { "party1", "party2", "party3", "party4" }
	ns.SetWaypointAt(Sim.player.col + 0.6, Sim.player.row + 0.3)
	ns.SetPath(true)
	Sim.Run(2)
end

benches.minimap_still = function()
	MinimapSetup()
	Sim.Run(10)
end

benches.minimap_ride = function()
	MinimapSetup()
	Sim.player.speed, Sim.player.facing = 14, 0.6
	Sim.Run(10)
	Sim.player.speed = 0
end

return benches
