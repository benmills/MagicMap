-- obs.you (types/observation.lua MM.ObsYou), per frame: the same table, refilled.
-- Nil fields: not known (UnitPosition gives nothing in instances and on some
-- loading frames; inst comes from GetInstanceInfo, known there too; uiMap is nil
-- where no map has you); losing and regaining the position is traced ("position").
-- uiMap is read again only after the events that change it (as HereBeDragons does).

local _, ns = ...
local Atlas, Game, Runtime = ns.Atlas, ns.Game, ns.Runtime

local FACTION = { Alliance = "A", Horde = "H" } -- UnitFactionGroup's; "Neutral" or nothing: nil

local you = {}
Game.obs.you = you -- there from load: a mark before the first frame reads it

local moved = true -- to another map, maybe: read uiMap
local function Moved() moved = true end
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS" }) do
	Runtime.On(event, "game.you map", Moved)
end

Game.Part("you", function()
	local north, west = UnitPosition("player")
	local had = you.col
	you.inst, you.col, you.row = select(8, GetInstanceInfo()), nil, nil
	if north then you.col, you.row = Atlas.WorldToTile(north, west) end
	you.facing = GetPlayerFacing()
	if moved then you.uiMap, moved = C_Map.GetBestMapForUnit("player"), false end
	you.level, you.faction = UnitLevel("player"), FACTION[UnitFactionGroup("player")]
	you.dead, you.ghost, you.combat = UnitIsDeadOrGhost("player"), UnitIsGhost("player"), InCombatLockdown()
	if (had == nil) ~= (you.col == nil) and Runtime.frames > 1 then Runtime.Trace("position", you.col and "back" or "lost") end
	return you
end)
