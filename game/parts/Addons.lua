-- obs.addons (types/observation.lua MM.ObsAddon[]), on change: other addons whose
-- HereBeDragons pins Game can borrow (game/AddonPins.lua Game.Addons); a new list
-- only when one comes or goes or gains or loses its world or minimap pins.

local _, ns = ...
local Game = ns.Game

Game.Part("addons", Game.Addons)
