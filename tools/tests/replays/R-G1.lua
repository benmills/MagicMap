-- G1: indoors was decided wrongly, six fixes in a row: surface terrain in the Cleft of Shadow,
-- Blizzard's grey patchy Minimap in Orgrimmar, Undercity NPCs strewn over the ruins, a whole zone's
-- painting in a Sun Rock hut (each signal the wrong question). Game-side now (ADR 0008): one signal,
-- obs.minimap.indoors from the Minimap's view radius (not IsIndoors(): Undercity and Ironforge are
-- mountable; Orgrimmar too, no exception), and obs.interior, the building and room you're in where
-- some building's floor mask covers you (game/parts/Interior.lua): no world map art, no whole Minimap.
-- Game keeps the sensor: unseen, its blips read. Each change of either leaves one "indoor" trace; /mm
-- indoor prints it. UI: in a building, its rooms' pictures over the tiles veiled (ui/Interiors.lua);
-- elsewhere the layer draws nothing.
local T = ...
local sim, ns = T.Shown()
local Game, Model = ns.Game, ns.Model
local M = Enum.UIMapType

sim.maps[1454] = { "Orgrimmar", M.Zone, 1414, 1, 38.901, 27.736, 41.531, 29.49 }
sim.maps[1458] = { "Undercity", M.Zone, 1415, 0, 30.363, 28.479, 32.162, 29.679 }
sim.maps[1412] = { "Mulgore", M.Zone, 1414, 1, 27.352, 31.5, 38.891, 39.191 }
sim.maps[291] = { "The Deadmines", M.Dungeon, nil, 36, 30, 30, 36, 36 }

local traces, onTrace = {}, ns.Runtime.onTrace
ns.Runtime.onTrace = function(k, d)
	if k == "indoor" then traces[#traces + 1] = d end
	return onTrace(k, d)
end

local PLACES = { -- what, inst, col, row, can't mount, floor plan, subzone; indoors, room (false: no building)
	{ "outdoors in Elwynn", 0, 31.95, 49.75, false, false, "Goldshire", false, false },
	{ "Orgrimmar: mountable, a floor plan, a building", 1, 40.2, 28.6, false, true, "", true, 137 },
	{ "a hut in Mulgore", 1, 32, 35, true, false, "", true, false },
	{ "a dungeon floor", 36, 32.5, 32.5, true, false, "", true, false },
	{ "Ironforge's Forge: mountable, a floor plan", 0, 33.997, 41.063, false, true, "The Great Forge", true, 65 },
	{ "back out in Elwynn", 0, 31.95, 49.75, false, false, "Goldshire", false, false },
}
sim.Slash("/mm indoor")
for i, p in ipairs(PLACES) do
	local what = p[1]
	sim.player.inst, sim.player.col, sim.player.row, sim.indoors, sim.floorPlan, sim.subzone = p[2], p[3], p[4], p[5], p[6], p[7]
	sim.FireEvent("ZONE_CHANGED_NEW_AREA")
	local n = #traces
	sim.Run(3) -- (past the 2 s a building is kept with no mask under you)
	local o, m = Model.interior, Game.minimap
	local layer = ns.UI.Interiors
	local c = layer.on and layer.front
	local pics = c and c.alpha == 1 and c.pools.pic and c.pools.pic.n or 0
	T.Print("G1: %s: indoors %s, building %s, room %s; %d picture(s) drawn; %d trace(s)", what,
		tostring(Model.minimap.indoors), o and tostring(o.building) or "none", o and tostring(o.room) or "-", pics, #traces - n)
	assert(Model.minimap.indoors == p[8] and (o and o.room or false) == p[9], what)
	assert((pics > 0) == (p[9] ~= false), what .. ": the pictures")
	assert(m.engaged and m.sensor and Minimap:GetAlpha() == 0 and not C_Minimap.GetDrawGroundTextures(), what .. ": the sensor's")
	local changes = (i > 1 and PLACES[i - 1][8] ~= p[8] and 1 or 0) + ((i > 1 and PLACES[i - 1][9] or false) ~= p[9] and 1 or 0)
	assert(#traces - n == changes or i == 1, what .. ": one trace a change")
	assert(sim.prints[#sim.prints]:find(p[9] and "indoor: building %d+, room " .. p[9] .. " %(.*%), candidates {" .. p[9] .. "}"
		or "indoor: no building; Minimap " .. (p[8] and "indoors" or "outdoors")) or #traces == n, what .. ": printed")
end
sim.Slash("/mm indoor")
assert(sim.prints[#sim.prints]:find("indoor: quiet", 1, true))
assert(#T.Errors(sim, ns) == 0, table.concat(T.Errors(sim, ns), "\n\n"))
