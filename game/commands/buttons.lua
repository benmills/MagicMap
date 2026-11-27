-- buttons (types/view.lua MM.CmdButtons): look for the Minimap's buttons again (game/MinimapButtons.lua
-- Game.ScanButtons): obs.buttons is fresh from the next observe step. Sent as the pointer reaches the AddOns
-- button (ui/Controls.lua), before its menu can open. Idempotent.

local _, ns = ...
local Game = ns.Game

Game.Handle("buttons", function() Game.ScanButtons() end)
