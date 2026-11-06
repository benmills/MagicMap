-- obs.buttons (types/observation.lua MM.ObsButton[]), on change: the Minimap's buttons, the addons' and Blizzard's
-- the takeover hides (game/MinimapButtons.lua Game.MinimapButtons): the gear's Minimap buttons submenu.

local _, ns = ...
local Game = ns.Game

Game.Part("buttons", Game.MinimapButtons)
