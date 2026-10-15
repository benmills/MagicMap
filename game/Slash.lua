-- /mma <name> [args]: Game.Slash(name, help, fn) registers fn(args);
-- /mma alone lists them. Runtime's own: perf, errors.

local _, ns = ...
local Game, Runtime = ns.Game, ns.Runtime

local commands = {}
Game.commands = {} -- names, in registration order

function Game.Slash(name, help, fn)
	commands[name] = { help = help, fn = Runtime.Wrap("/mma " .. name, fn) }
	Game.commands[#Game.commands + 1] = name
end

SLASH_MAGICMAPATLAS1 = "/mma"
SlashCmdList.MAGICMAPATLAS = function(msg)
	local name, args = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
	local c = commands[name:lower()]
	if c then return c.fn(args) end
	Game.Print("commands:")
	for _, n in ipairs(Game.commands) do print("  /mma " .. n .. " - " .. commands[n].help) end
end

Game.Slash("perf", "load cost, and time per step / event / timer / job (ms)", function()
	local b = Runtime.boot
	Game.Print(string.format("Atlas loaded in %.0f ms, %.0f KB; Lua memory now %.0f KB",
		b.loaded.t - b.t0, b.loaded.mem - b.mem0, collectgarbage("count")))
	if b.login then Game.Print(string.format("login %.0f ms after load start", b.login.t - b.t0)) end
	local perf, frames = Runtime.Perf()
	local list = {}
	for name, p in pairs(perf) do
		if p.n > 0 then list[#list + 1] = { name, p } end
	end
	table.sort(list, function(a, c) return a[2].ms > c[2].ms end)
	Game.Print(string.format("%d frames; busiest:", frames))
	for i = 1, math.min(15, #list) do
		local name, p = list[i][1], list[i][2]
		print(string.format("  %s  %.3f ms/frame, %d calls, max %.2f ms", name, p.ms / math.max(frames, 1), p.n, p.max))
	end
end)

Game.Slash("errors", "errors caught so far (each printed once when it happened)", function()
	Game.Print(#Runtime.errors .. " failing")
	for _, e in ipairs(Runtime.errors) do print(string.format("  %s (x%d): %s", e.name, e.n, e.err)) end
end)
