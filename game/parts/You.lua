-- obs.you (types/observation.lua MM.ObsYou), per frame: the same table, refilled.
-- Nil fields: not known (UnitPosition gives nothing in instances and on some
-- loading frames; inst comes from GetInstanceInfo, known there too); losing and
-- regaining the position is traced ("position").

local _, ns = ...
local Atlas, Game, Runtime = ns.Atlas, ns.Game, ns.Runtime

local you = {}
Game.obs.you = you -- there from load: a mark before the first frame reads it

Game.Part("you", function()
	local north, west = UnitPosition("player")
	local had = you.col
	you.inst, you.col, you.row = select(8, GetInstanceInfo()), nil, nil
	if north then you.col, you.row = Atlas.WorldToTile(north, west) end
	you.facing = GetPlayerFacing()
	if (had == nil) ~= (you.col == nil) and Runtime.frames > 1 then Runtime.Trace("position", you.col and "back" or "lost") end
	return you
end)
