-- Commands (types/view.lua, ADR 0003): UI calls Game.Command(cmd) from anywhere;
-- Game queues it and carries the queue out, in order, in its input step. Each
-- is wrapped: one that fails is reported and dropped, never retried.
-- Kinds so far: slash (register /mma <name>), load (Game.Load on UI's behalf).
-- Sent while the addon loads: carried out at PLAYER_LOGIN, before the first frame.

local _, ns = ...
local Game, Runtime = ns.Game, ns.Runtime

local queue = {}

local DO = {
	slash = function(c) Game.Slash(c.name, c.help, c.fn) end,
	load = function(c) Game.Load(c.owner, c.fn, c.spec) end,
}

function Game.Command(cmd) queue[#queue + 1] = cmd end

local Do = Runtime.Wrap("game: command", function(cmd)
	local fn = DO[cmd.kind]
	if not fn then error("unknown command " .. tostring(cmd.kind)) end
	fn(cmd)
end, false)

local function Run()
	if not queue[1] then return end
	local q = queue
	queue = {}
	for _, cmd in ipairs(q) do Do(cmd) end
end

Runtime.Step("input", "game.commands", Run, { budgetMs = false })
-- Those sent while loading are carried out at login, before the first frame
-- (so /mma map works as soon as you're in).
Runtime.On("PLAYER_LOGIN", "game.commands login", Run)
