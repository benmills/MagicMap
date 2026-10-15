-- Observe phase: one observation a frame, handed to Model.Observe(obs, oracles)
-- (types/observation.lua). Nil fields: not known (UnitPosition gives nothing in
-- instances and on some loading frames; inst comes from GetInstanceInfo, known
-- there too); losing and regaining the position is traced ("position").
-- Events are only buffered by their handlers; this step reads, so Model sees one
-- consistent snapshot a frame (docs/runtime.md "Events").
-- Model's saved part is handed to it here too: Game.Load("Model", Model.Load, Model.SAVED).

local _, ns = ...
local Atlas, Game, Runtime, Model = ns.Atlas, ns.Game, ns.Runtime, ns.Model

local you, minimap, hooked = {}, {}, {}
local obs = { you = you, minimap = minimap, hooked = hooked }
local oracles = { Inside = function() return nil end } -- (no quest areas yet: Model estimates)
Game.obs = obs -- the last one handed over (Telemetry's state, the recorder)

Game.Load("Model", Model.Load, Model.SAVED)

Runtime.Step("observe", "game.observe", function()
	local north, west = UnitPosition("player")
	local had = you.col
	you.inst, you.col, you.row = select(8, GetInstanceInfo()), nil, nil
	if north then you.col, you.row = Atlas.WorldToTile(north, west) end
	you.facing = GetPlayerFacing()
	if (had == nil) ~= (you.col == nil) and Runtime.frames > 1 then Runtime.Trace("position", you.col and "back" or "lost") end
	obs.frame, obs.t, obs.epoch = Runtime.frames, GetTime(), time()
	obs.blips = Game.Blips()
	local m = Game.minimap
	minimap.engaged, minimap.blocker, minimap.sensing = m.engaged, m.blocker, obs.blips ~= nil and m.still
	Model.Observe(obs, oracles)
end)
