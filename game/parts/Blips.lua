-- obs.blips (types/observation.lua MM.ObsBlips), per frame: a slice of the sensor's
-- looks (game/Blips.lua Game.Blips), after obs.you; nil while the sensor can't run.

local _, ns = ...
local Game = ns.Game

Game.Part("blips", Game.Blips)
