-- Commands (types/view.lua, ADR 0003): UI calls Game.Command(cmd) from anywhere;
-- Game queues it and carries the queue out, in order, in its input step, and again
-- in its apply step, so one a ui step sends is carried out that frame (a quest
-- tooltip's portraits show with it: QuestInfo.lua:187, 365-368). Each is wrapped:
-- one that fails is reported and dropped, never retried.
-- Game.Handle(kind, fn): fn(cmd) carries out that kind; one file a kind in
-- game/commands/ (slash: register /mma <name>; load: Game.Load on UI's behalf).
-- Sent while the addon loads: carried out at PLAYER_LOGIN, before the first frame.

local _, ns = ...
local Game, Runtime = ns.Game, ns.Runtime

local queue, handlers = {}, {}

function Game.Command(cmd) queue[#queue + 1] = cmd end

function Game.Handle(kind, fn) handlers[kind] = fn end

local Do = Runtime.Wrap("game: command", function(cmd)
	local fn = handlers[cmd.kind]
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
Runtime.Step("apply", "game.commands sent in the frame", Run, { budgetMs = false })
-- Those sent while loading are carried out at login, before the first frame
-- (so /mma toggle works as soon as you're in).
Runtime.On("PLAYER_LOGIN", "game.commands login", Run)
