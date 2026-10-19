-- obs.explored (types/observation.lua table<AreaID, boolean>), on change: per area, whether you've
-- explored it, on the continent of the map shown (Game.shownInst) and of yours. A sweep of the
-- continent's map in cells CELL tiles a side, SAMPLES cells a frame (Layers.lua:75-76, 1257-1269, 1334-1361): at each
-- cell's centre, on its zone's map, the client says which areas are explored there
-- (C_MapExplorationInfo.GetExploredAreaIDsAtPosition); those it names are, and the cell's own
-- (Atlas.AreaAt) is if it names any, or not if none (Layers.lua:1347). An area found explored isn't
-- asked about again. Handed over when a sweep ends: a new table, what the last had and this one found
-- (the old kept until then: Layers.lua:2245-2248), only if something changed. Swept again, for the
-- areas not explored yet, after MAP_EXPLORATION_UPDATED: the one shown now, the others once shown.
-- An instance's map (no continent) has none.

local _, ns = ...
local Atlas, Game, Runtime = ns.Atlas, ns.Game, ns.Runtime

local CELL, SAMPLES = 0.2, 700 -- tiles (~107 yd); cells a frame (Layers.lua:75-76)
local NONE = {}

local explored -- the last handed over
local sweep -- the one going on: { inst, c0, r0, nc, nr, i, j, out, changed }
local swept = {} -- inst -> true: swept; false: again (MAP_EXPLORATION_UPDATED)
local zoneMaps = {} -- areaID -> its zone's uiMap | false
local at = CreateVector2D(0, 0) -- (one position, refilled: a table a sample otherwise)

Runtime.On("MAP_EXPLORATION_UPDATED", "game.explored", function()
	for inst in pairs(swept) do swept[inst] = false end
end)

local function ZoneMap(inst, a)
	local m = zoneMaps[a]
	if m == nil then
		local area = Atlas.Area(a)
		local id = area and Atlas.Area(area.zone).uiMap
		local r = id and Atlas.MapRect(id)
		m = r and r.inst == inst and id or false
		zoneMaps[a] = m
	end
	return m
end

local function Due(inst)
	return inst and not swept[inst] and Atlas.Continent(inst) and inst
end

local function Start(inst)
	local r = Atlas.MapRect(Atlas.Continent(inst))
	local out = {}
	for a, v in pairs(explored or NONE) do out[a] = v end
	sweep = { inst = inst, c0 = r.col0, r0 = r.row0, nc = math.ceil((r.col1 - r.col0) / CELL),
		nr = math.ceil((r.row1 - r.row0) / CELL), i = 0, j = 0, out = out, changed = explored == nil }
end

local function Sweep()
	local s = sweep
	local inst, out = s.inst, s.out
	for _ = 1, SAMPLES do
		if s.j == s.nr then break end
		local col, row = s.c0 + (s.i + 0.5) * CELL, s.r0 + (s.j + 0.5) * CELL
		local a = Atlas.AreaAt(inst, col, row)
		local map = a and out[a] ~= true and ZoneMap(inst, a)
		if map then
			at.x, at.y = Atlas.TileToMap(map, col, row)
			local ids = C_MapExplorationInfo.GetExploredAreaIDsAtPosition(map, at) -- (nil: none)
			for _, id in ipairs(ids or NONE) do
				if out[id] ~= true then out[id], s.changed = true, true end
			end
			local lit = ids ~= nil and #ids > 0
			if (lit and out[a] ~= true) or out[a] == nil then out[a], s.changed = lit, true end
		end
		s.i = s.i + 1
		if s.i == s.nc then s.i, s.j = 0, s.j + 1 end
	end
	if s.j < s.nr then return end
	swept[inst], sweep = true, nil
	if s.changed then explored = out end
end

Game.Part("explored", function(obs)
	if not sweep then
		local inst = Due(Game.shownInst) or Due(obs.you.inst)
		if inst then Start(inst) end
	end
	if sweep then Sweep() end
	return explored
end)
