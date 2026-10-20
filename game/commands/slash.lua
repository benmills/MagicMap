-- slash (types/view.lua MM.CmdSlash): register /mm <name> (game/Slash.lua).

local _, ns = ...
local Game = ns.Game

Game.Handle("slash", function(c) Game.Slash(c.name, c.help, c.fn) end)
