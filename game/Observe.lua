-- Observe phase: where you are, in Atlas's tile space, handed to Model.
-- Nil fields: not known (UnitPosition gives nothing in instances).

local _, ns = ...
local Atlas, Runtime = ns.Atlas, ns.Runtime

local you = {}
local obs = { you = you }

Runtime.Step("observe", "game.observe", function()
	local north, west, _, inst = UnitPosition("player")
	you.inst, you.col, you.row = inst, nil, nil
	if north then you.col, you.row = Atlas.WorldToTile(north, west) end
	you.facing = GetPlayerFacing()
	ns.Model.Observe(obs)
end)
