-- obs.explored (types/observation.lua table<AreaID, boolean>) and obs.exploredCells (per instance, rows of
-- cells), on change: what you've explored on the continent of the map shown (Game.shownInst) and of yours.
-- A sweep of the continent's map in cells CELL tiles a side, SAMPLES cells a frame (Layers.lua:75-76,
-- 1257-1269, 1334-1361): at each cell's centre, on its zone's map, the client says which areas are explored
-- there (C_MapExplorationInfo.GetExploredAreaIDsAtPosition). The cell is lit if it names any, dark if none
-- (Layers.lua:1347: what the shade darkens, per cell); the areas it names are explored, and the cell's own
-- (Atlas.AreaAt) checked (false until named). A lit cell isn't asked again. Handed over when a sweep ends:
-- new tables, what the last had and this one found (the old kept until then: Layers.lua:2245-2248; a row of
-- cells a new table only if it changed), each only if something in it changed. Swept again, the cells not
-- lit, after MAP_EXPLORATION_UPDATED: the one shown now, the others once shown. An instance's map (no
-- continent) has none.

local _, ns = ...
local Atlas, Game, Runtime = ns.Atlas, ns.Game, ns.Runtime

local CELL, SAMPLES = 0.2, 700 -- tiles (~107 yd); cells a frame (Layers.lua:75-76)
local NONE = {}

local explored, cells -- the last handed over: per area; per instance, its rows of cells ([j][i]: true, false)
local sweep -- the one going on: { inst, c0, r0, nc, nr, i, j, out, rows, old, row, areas, lit }
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
	local old = cells and cells[inst]
	sweep = { inst = inst, c0 = r.col0, r0 = r.row0, nc = math.ceil((r.col1 - r.col0) / CELL),
		nr = math.ceil((r.row1 - r.row0) / CELL), i = 0, j = 0, out = out, rows = {}, old = old or NONE,
		areas = explored == nil, lit = old == nil }
end

local function Sweep()
	local s = sweep
	local inst, out = s.inst, s.out
	for _ = 1, SAMPLES do
		if s.j == s.nr then break end
		local old = s.old[s.j + 1] or NONE
		local was = old[s.i + 1]
		if was ~= true then
			local col, row = s.c0 + (s.i + 0.5) * CELL, s.r0 + (s.j + 0.5) * CELL
			local a = Atlas.AreaAt(inst, col, row)
			local map = a and ZoneMap(inst, a)
			if map then
				at.x, at.y = Atlas.TileToMap(map, col, row)
				local ids = C_MapExplorationInfo.GetExploredAreaIDsAtPosition(map, at) -- (nil: none)
				for _, id in ipairs(ids or NONE) do
					if out[id] ~= true then out[id], s.areas = true, true end
				end
				if out[a] == nil then out[a], s.areas = false, true end
				local lit = ids ~= nil and #ids > 0
				if lit ~= was then
					if not s.row then -- (the row changed: a new one)
						s.row = {}
						for k, v in pairs(old) do s.row[k] = v end
					end
					s.row[s.i + 1], s.lit = lit, true
				end
			end
		end
		s.i = s.i + 1
		if s.i == s.nc then
			s.rows[s.j + 1] = s.row or s.old[s.j + 1]
			s.i, s.j, s.row = 0, s.j + 1, nil
		end
	end
	if s.j < s.nr then return end
	swept[inst], sweep = true, nil
	if s.areas then explored = out end
	if s.lit then
		local all = {}
		for k, v in pairs(cells or NONE) do all[k] = v end
		all[inst], cells = s.rows, all
	end
end

Game.Part("explored", function(obs)
	if not sweep then
		local inst = Due(Game.shownInst) or Due(obs.you.inst)
		if inst then Start(inst) end
	end
	if sweep then Sweep() end
	return explored
end)

Game.Part("exploredCells", function() return cells end)
