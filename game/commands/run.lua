-- run (types/view.lua MM.CmdRun): /mm <line> as typed (game/Slash.lua's Game.Run): the gear's Advanced
-- runs the slash commands' own code (GearMenu.lua:28). Not idempotent: each runs it once.

local _, ns = ...
local Game = ns.Game

Game.Handle("run", function(c) Game.Run(c.line) end)
