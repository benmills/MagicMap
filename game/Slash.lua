-- /mm <name> [args]: Game.Slash(name, help, fn) registers fn(args); /mm alone is the
-- name "" (UI's: the map shown or hidden, Core.lua:1700). A name may be two words ("check art"): it
-- wins over its first word's. An unknown name, or zone alone, answers with the spike's usage line
-- (Core.lua:1752); the rebuild's diagnostics (check, bench, shot, layer, mapstats, minimap, errors,
-- perf load...) stand outside it: /mm help lists every name. Game.Run(line) is the same as typing it
-- (the gear's Advanced: game/commands/run.lua).
-- Here: the spike's tiles, landmarks, perf, perf top, perf mem (Core.lua, Landmarks.lua, Perf.lua); and
-- Runtime's own, perf load and errors.

local ADDON, ns = ...
local Atlas, Game, Runtime = ns.Atlas, ns.Game, ns.Runtime

local USAGE = "/mm [toggle] | follow | map <id|name> | zone <name> | icon | tiles | tint | layers | landmarks"
	.. " | blips | indoor | perf | debug | reset" -- Core.lua:1752
local ARG = { zone = true } -- names that take an argument: alone, the usage line (Core.lua:1721)

local commands = {}
Game.commands = {} -- names, in registration order

function Game.Slash(name, help, fn)
	if not commands[name] then Game.commands[#Game.commands + 1] = name end
	commands[name] = { help = help, fn = Runtime.Wrap("/mm " .. name, fn) }
end

function Game.Run(msg)
	local name, args = strtrim(msg):match("^(%S*)%s*(.-)$")
	local sub, rest = args:match("^(%S+)%s*(.-)$")
	local c = sub and commands[(name .. " " .. sub):lower()]
	if c then return c.fn(rest) end
	name = name:lower()
	c = commands[name]
	if c and not (ARG[name] and args == "") then return c.fn(args) end
	Game.Say(USAGE)
end

SLASH_MAGICMAP1 = "/mm"
SLASH_MAGICMAP2 = "/magicmap" -- Core.lua:1696-1698
SlashCmdList.MAGICMAP = Game.Run

Game.Slash("help", "every command, with what it does", function()
	Game.Print("commands:")
	for _, n in ipairs(Game.commands) do print("  /mm" .. (n ~= "" and " " .. n or "") .. " - " .. commands[n].help) end
end)

-- /mm tiles (Core.lua:1738-1743): the tile set, and each map's tiles.
Game.Slash("tiles", "the tile set, and each map's tiles", function()
	local names = {}
	for _, m in ipairs(Atlas.Maps()) do
		local n = 0
		for _ in pairs(Atlas.Tiles(m.inst)) do n = n + 1 end
		names[#names + 1] = m.name .. " (" .. n .. ")"
	end
	local product, version = Atlas.TileSet()
	Game.Say("tile set: " .. tostring(product) .. " " .. tostring(version) .. ". Maps: " .. table.concat(names, ", "))
end)

-- /mm landmarks (Landmarks.lua:175-183): the rares you've seen, every map's (Model's saved part, as Game
-- loaded it).
Game.Slash("landmarks", "how many rares are remembered", function()
	local total = 0
	for _, rares in pairs(Game.db.Model.rares) do
		for _ in pairs(rares) do total = total + 1 end
	end
	Game.Say(total .. " rares remembered" .. (total > 0 and "" or ". Target one, or pass one the game shows, and it'll appear on the map."))
end)

---------------------------------------------------------------------------
-- /mm perf, perf top, perf mem (Perf.lua)
---------------------------------------------------------------------------

local DURATION = 10 -- s (Perf.lua:7)

-- The client's addon profiler and each addon's memory: fair against other addons (Perf.lua:12-72). The
-- profiler's answers are read as the spike read them (their shapes unproven in Forever).
local function TopAddOns(P, metric, k)
	local ok, results = pcall(P.GetTopKAddOnsForMetric, metric, k)
	local out = {}
	for _, r in ipairs(ok and type(results) == "table" and results or {}) do
		local name = type(r) == "table" and (r.addOnName or r.name) or nil
		local value = type(r) == "table" and (r.value or r.metricValue) or nil
		if name and value then out[#out + 1] = { name, value } end
	end
	return out
end

local function Metric(P, name, metric)
	local ok, v = pcall(P.GetAddOnMetric, name, metric)
	return ok and type(v) == "number" and v or nil
end

-- KB per addon, biggest first: { { name, kb }, ... }. UpdateAddOnMemoryUsage walks every addon: in a grace.
local function Memory()
	Runtime.Grace("gc", 0.1)
	UpdateAddOnMemoryUsage()
	local out = {}
	for i = 1, C_AddOns.GetNumAddOns() do
		local name = C_AddOns.GetAddOnInfo(i)
		local kb = name and GetAddOnMemoryUsage(i) or 0
		if kb > 0 then out[#out + 1] = { name, kb } end
	end
	table.sort(out, function(a, b) return a[2] > b[2] end)
	return out
end

local function Ranked(list, fmt, n)
	local parts = {}
	for i = 1, math.min(n, #list) do
		local e = list[i]
		local s = string.format(fmt, e[1], e[2])
		parts[#parts + 1] = e[1] == ADDON and ("|cffffd100" .. s .. "|r") or s
	end
	return table.concat(parts, ", ")
end

-- How we compare with your other addons, right now (Perf.lua:124-144).
local function Compare()
	local P, M = C_AddOnProfiler, Enum.AddOnProfilerMetric
	if P.IsEnabled() then
		local recent, peak = Metric(P, ADDON, M.RecentAverageTime), Metric(P, ADDON, M.PeakTime)
		local overall = select(2, pcall(P.GetOverallMetric, M.RecentAverageTime))
		Game.Say(string.format("  client profiler: %s %.3f ms/frame recently, peak %.1f ms%s", ADDON, recent or 0,
			peak or 0, type(overall) == "number" and string.format("; all addons %.3f ms/frame", overall) or ""))
		local top = TopAddOns(P, M.RecentAverageTime, 6)
		if #top > 0 then Game.Say("  busiest addons: " .. Ranked(top, "%s %.3f", 6)) end
	else
		Game.Say("  client profiler: off")
	end
	local mem, mine = Memory(), nil
	for i, e in ipairs(mem) do
		if e[1] == ADDON then mine = i end
	end
	Game.Say(string.format("  memory: %s %s (#%s of %d); biggest: %s", ADDON,
		mine and string.format("%.0f KB", mem[mine][2]) or "?", mine or "?", #mem, Ranked(mem, "%s %.0f KB", 6)))
end

-- Where the time went, busiest first: ms a frame, and calls and the slowest where that says more (Perf.lua:
-- 74-101). Every call Runtime wraps, by its name (the spike's map parts are names of their own here).
local function Where(r)
	local list, total = {}, 0
	for name, c in pairs(r.calls) do
		list[#list + 1] = { name, c }
		total = total + c.ms
	end
	table.sort(list, function(a, b) return a[2].ms > b[2].ms end)
	Game.Say(string.format("  all of %s's scripts and events: %.3f ms/frame. Where:", ADDON, total / r.frames)) -- /: never 0 (frames > 0: Report)
	for i = 1, math.min(8, #list) do
		local name, c = list[i][1], list[i][2]
		Game.Say(string.format("    %s  %.3f ms/frame (max %.1f ms%s)", name, c.ms / r.frames, c.max, -- /: never 0 (frames > 0)
			c.n ~= r.frames and string.format(", %d calls", c.n) or ""))
	end
end

-- The map's gauge (ui/Engine.lua) at the recording's start: its borders' counts are since load.
local before

-- The recording, reported (Perf.lua:146-159): the client's frames, our cost in them (the borders' layouts
-- part of it), the borders' layouts (builds at a new zoom, pans at the zoom shown: the spike's extensions)
-- and the frames the view ran past them, where the time went, and the comparison.
local function Report(r)
	if r.frames == 0 then return Game.Say("perf: no frames recorded (is the map open?)") end
	local m, b = Runtime.gauges.map(), before
	Game.Say(string.format("perf: %d frames in %.1f s, %.0f fps, worst frame %.0f ms, %d hitches (>%d ms)",
		r.frames, r.t, r.frames / r.t, r.worst * 1000, r.hitches, Runtime.HITCH * 1000)) -- /: never 0 (a frame's elapsed > 0)
	local borders = r.calls["map: borders"]
	Game.Say(string.format("  map script: %.2f ms/frame on average, %.1f ms at most (borders %.2f ms/frame)",
		r.ms / r.frames, r.peak, borders and borders.ms / r.frames or 0)) -- /: never 0 (frames > 0)
	local builds, past = m.builds - b.builds, m.past - b.past
	Game.Say(string.format("  borders: %d builds (%.0f ms each), %d extensions, %d frames (%.0f%%) showing past them",
		builds, builds > 0 and (m.buildMs - b.buildMs) / builds or 0, m.pans - b.pans, past, 100 * past / r.frames)) -- /: never 0 (builds > 0, frames > 0)
	Where(r)
	Compare()
end

Game.Slash("perf", "record 10 s of play, then how the map kept up (again: stop early)", function()
	if Runtime.recording then return Runtime.RecordEnd() end
	before = Runtime.gauges.map()
	Runtime.Record(DURATION, "perf: report", Report)
	Game.Say(string.format("perf: recording %d s; pan and zoom around (/mm perf again to stop early)", DURATION))
end)

Game.Slash("perf top", "how we compare with your other addons, right now", function()
	Game.Say("perf: " .. ADDON .. " against your other addons, right now")
	Compare()
end)

-- Our memory before and after a full collection (what's left is live; the rest was garbage), and the
-- map's regions behind it (Perf.lua:103-122).
Game.Slash("perf mem", "our memory, and after a full collection; the map's regions", function()
	Runtime.Grace("gc", 0.1)
	UpdateAddOnMemoryUsage()
	local was = GetAddOnMemoryUsage(ADDON)
	collectgarbage("collect")
	UpdateAddOnMemoryUsage()
	local now = GetAddOnMemoryUsage(ADDON)
	Game.Say(string.format("perf mem: %s %.0f KB, %.0f KB after a full collection (%.0f KB was garbage)",
		ADDON, was, now, was - now))
	local m, parts = Runtime.gauges.map(), {}
	for kind, c in pairs(m.objects) do parts[#parts + 1] = string.format("%d %s (%d in use)", c.made, kind, c.used) end
	table.sort(parts)
	parts[#parts + 1] = string.format("%d tiles drawn, %d spare", m.tiles, m.spare)
	Game.Say("  objects: " .. table.concat(parts, ", "))
end)

---------------------------------------------------------------------------
-- Runtime's own
---------------------------------------------------------------------------

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
