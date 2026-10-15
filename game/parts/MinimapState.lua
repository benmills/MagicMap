-- obs.minimap (types/observation.lua MM.ObsMinimap), per frame: the takeover's state
-- (game/Minimap.lua Game.minimap), sensing if the sensor read this frame (obs.blips).

local _, ns = ...
local Game = ns.Game

local minimap = {}

Game.Part("minimap", function(obs)
	local m = Game.minimap
	minimap.engaged, minimap.blocker, minimap.sensing = m.engaged, m.blocker, obs.blips ~= nil and m.still
	return minimap
end)
