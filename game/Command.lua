-- Commands (types/view.lua, ADR 0003): UI calls Game.Command(cmd) from anywhere;
-- Game queues it and carries the queue out, in order, in its input step, and again
-- in its apply step, so one a ui step sends is carried out that frame. Each is wrapped:
-- one that fails is reported and dropped, never retried.
-- Game.Handle(kind, fn): fn(cmd) carries out that kind; one file a kind in
-- game/commands/ (slash: register /mm <name>; load: Game.Load on UI's behalf).
-- Sent while the addon loads: carried out at PLAYER_LOGIN, before the first frame.
-- Game.AfterCombat(key, what, fn): for a Command that runs another addon's code or opens one of Blizzard's panels.
-- In combat the client refuses an addon's code some calls on any frame (SetPassThroughButtons: Blizzard's map makes
-- it on every pin it hands out, pin addons on theirs) and blames the addon whose code began the call chain, with its
-- "blocked from an action only available to the Blizzard UI" prompt: us, whoever's code made the call. So fn() runs
-- now out of combat; in combat it waits for PLAYER_REGEN_ENABLED (a later one of the same key in its place) and
-- chat says so: "<what> when combat ends."

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

local waiting, order = {}, {} -- key -> fn; the keys, first asked first
function Game.AfterCombat(key, what, fn)
	if not InCombatLockdown() then return fn() end
	if not waiting[key] then order[#order + 1] = key end
	waiting[key] = fn
	Game.Say(what .. " when combat ends.")
end
local Late = Runtime.Wrap("game: command after combat", function(fn) fn() end, false)
Runtime.On("PLAYER_REGEN_ENABLED", "game.commands after combat", function()
	local keys, fns = order, waiting
	order, waiting = {}, {}
	for _, key in ipairs(keys) do Late(fns[key]) end
end)

Runtime.Step("input", "game.commands", Run, { budgetMs = false })
Runtime.Step("apply", "game.commands sent in the frame", Run, { budgetMs = false })
-- Those sent while loading are carried out at login, before the first frame
-- (so /mm toggle works as soon as you're in).
Runtime.On("PLAYER_LOGIN", "game.commands login", Run)
