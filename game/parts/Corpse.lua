-- obs.corpse (types/observation.lua MM.Pos|false), on change: yours, where the client has it on your
-- continent's map or else a zone's of it, the first that has it (Layers.lua:451-457, 506-522); false:
-- none known. Read again on PLAYER_DEAD, PLAYER_ALIVE and PLAYER_UNGHOST (Layers.lua:2229-2231) and on
-- another instance; and while you're a ghost with none known, every POLL s: the client knows where it
-- is only a while after you release, and says nothing then (spike-bugs G4; Layers.lua:500-503,
-- 2236-2242). A new table only when it moved.

local _, ns = ...
local Atlas, Game, Runtime = ns.Atlas, ns.Game, ns.Runtime

local POLL = 1 -- s (Layers.lua:503)

local pos = false -- the last handed over
local dirty, read, due = true, nil, 0 -- read: the instance last read; due: the next poll

local function Again() dirty = true end
for _, event in ipairs({ "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do
	Runtime.On(event, "game.corpse", Again)
end

local function Read(inst)
	local map = Atlas.Continent(inst) -- (none: an instance's own map)
	local p = map and C_DeathInfo.GetCorpseMapPosition(map)
	for _, z in ipairs(Atlas.Zones(inst)) do
		if p then break end
		map = z.uiMapID
		p = C_DeathInfo.GetCorpseMapPosition(map)
	end
	if not p then return false end
	local i, col, row = Atlas.MapToTile(map, p.x, p.y)
	if pos and pos.inst == i and pos.col == col and pos.row == row then return pos end
	return { inst = i, col = col, row = row }
end

Game.Part("corpse", function(obs)
	local you = obs.you
	if dirty or you.inst ~= read or you.ghost and not pos and obs.t >= due then
		dirty, read, due = false, you.inst, obs.t + POLL
		pos = Read(you.inst)
	end
	return pos
end)
