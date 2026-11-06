-- button (types/view.lua MM.CmdButton): click one of the Minimap's buttons (MM.ObsButton.id) as its own click does,
-- from the gear's Minimap buttons submenu (game/MinimapButtons.lua Game.ClickButton). Not idempotent: each clicks once.

local _, ns = ...
local Game = ns.Game

Game.Handle("button", function(c) Game.ClickButton(c.id, c.button) end)
