-- load (types/view.lua MM.CmdLoad): UI's saved part, Game.Load on its behalf (game/Game.lua).

local _, ns = ...
local Game = ns.Game

Game.Handle("load", function(c) Game.Load(c.owner, c.fn, c.spec) end)
