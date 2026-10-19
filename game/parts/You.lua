-- obs.you (types/observation.lua MM.ObsYou), per frame: the same table, refilled (by a frame this part
-- fails, one all unknown: `you` is always present, and Model keeps its last belief, stale).
-- Nil fields: not known (UnitPosition gives nothing in instances and on some
-- loading frames; inst comes from GetInstanceInfo, known there too; uiMap is nil
-- where no map has you); losing and regaining the position is traced ("position").
-- uiMap and the zone's names are read again only after the events that change them, and AGAIN
-- later (an event can come before the zone changes), and every AGAIN in a micro map (a dungeon's
-- levels don't reliably fire them), as HereBeDragons does (HereBeDragons-2.0.lua:372-418).

local _, ns = ...
local Atlas, Game, Runtime = ns.Atlas, ns.Game, ns.Runtime

local FACTION = { Alliance = "A", Horde = "H" } -- UnitFactionGroup's; "Neutral" or nothing: nil
local MICRO = 5 -- Enum.UIMapType.Micro
local AGAIN = 1 -- s

local you, UNKNOWN = {}, {}
Game.obs.you = you -- there from load: a mark before the first frame reads it

local moved, again = true, nil -- to another map, maybe: read uiMap; a read due in AGAIN
local function Again()
	again, moved = nil, true
end
local function Soon()
	if not again then again = Runtime.After(AGAIN, "game.you map again", Again) end
end
local function Moved()
	moved = true
	Soon()
end
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
	"NEW_WMO_CHUNK" }) do
	Runtime.On(event, "game.you map", Moved)
end

Game.Part("you", function()
	local north, west = UnitPosition("player")
	local had = you.col
	you.inst, you.col, you.row = select(8, GetInstanceInfo()), nil, nil
	if north then you.col, you.row = Atlas.WorldToTile(north, west) end
	you.facing = GetPlayerFacing()
	if moved then
		local zone, sub = GetZoneText(), GetSubZoneText()
		you.uiMap, you.zone, you.subzone, moved = C_Map.GetBestMapForUnit("player"), zone ~= "" and zone or nil,
			sub ~= "" and sub or nil, false
		local info = you.uiMap and C_Map.GetMapInfo(you.uiMap) -- (Atlas keeps no micro maps)
		if info and info.mapType == MICRO then Soon() end
	end
	you.level, you.faction = UnitLevel("player"), FACTION[UnitFactionGroup("player")]
	you.dead, you.ghost, you.combat = UnitIsDeadOrGhost("player"), UnitIsGhost("player"), InCombatLockdown()
	if (had == nil) ~= (you.col == nil) and Runtime.frames > 1 then Runtime.Trace("position", you.col and "back" or "lost") end
	return you
end, UNKNOWN)
