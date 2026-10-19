-- /mma <name> [args]: Game.Slash(name, help, fn) registers fn(args); /mma alone is the
-- name "" (UI's: the map shown or hidden, Core.lua:1700); an unknown name lists them.
-- Runtime's own: perf load, errors (`perf`, `perf top`, `perf mem` are the spike's, M4.6). A name may be
-- two words ("check art"): it wins over its first word's.

local _, ns = ...
local Game, Runtime = ns.Game, ns.Runtime

local commands = {}
Game.commands = {} -- names, in registration order

function Game.Slash(name, help, fn)
	if not commands[name] then Game.commands[#Game.commands + 1] = name end
	commands[name] = { help = help, fn = Runtime.Wrap("/mma " .. name, fn) }
end

SLASH_MAGICMAPATLAS1 = "/mma"
SlashCmdList.MAGICMAPATLAS = function(msg)
	local name, args = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
	local sub, rest = args:match("^(%S+)%s*(.-)$")
	local c = sub and commands[(name .. " " .. sub):lower()]
	if c then return c.fn(rest) end
	c = commands[name:lower()]
	if c then return c.fn(args) end
	Game.Print("commands:")
	for _, n in ipairs(Game.commands) do print("  /mma" .. (n ~= "" and " " .. n or "") .. " - " .. commands[n].help) end
end

Game.Slash("perf load", "[text]: load cost, and time per step / event / timer / job (ms); text: every name with it", function(match)
	local b = Runtime.boot
	Game.Print(string.format("Atlas loaded in %.0f ms, %.0f KB; Lua memory now %.0f KB",
		b.loaded.t - b.t0, b.loaded.mem - b.mem0, collectgarbage("count")))
	if b.login then Game.Print(string.format("login %.0f ms after load start", b.login.t - b.t0)) end
	local perf, frames = Runtime.Perf()
	local list = {}
	for name, p in pairs(perf) do
		if p.n > 0 and (match == "" or name:find(match, 1, true)) then list[#list + 1] = { name, p } end
	end
	table.sort(list, function(a, c) return a[2].ms > c[2].ms end)
	local f = Runtime.FrameStats()
	Game.Print(string.format("our cost a frame (outside graces, %d frames): p50 %.2f p95 %.2f p99 %.2f max %.1f ms, %d over %d ms",
		f.frames, f.p50, f.p95, f.p99, f.max, f.overruns, Runtime.FRAME_MS))
	Game.Print(string.format("%d frames; busiest:", frames))
	for i = 1, match == "" and math.min(15, #list) or #list do
		local name, p = list[i][1], list[i][2]
		local each = p.ms / math.max(frames, 1) -- /: never 0 (at least 1)
		print(string.format("  %s  %.3f ms/frame, %d calls, max %.2f ms%s", name, each, p.n, p.max,
			p.over > 0 and string.format(", %d over budget", p.over) or ""))
	end
end)

Game.Slash("errors", "errors caught so far (each printed once when it happened)", function()
	Game.Print(#Runtime.errors .. " failing")
	for _, e in ipairs(Runtime.errors) do print(string.format("  %s (x%d): %s", e.name, e.n, e.err)) end
end)
