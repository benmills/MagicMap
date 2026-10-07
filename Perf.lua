-- /mm perf: record a few seconds of real use and report how the map kept up
-- (frame times, the addon's own time, border builds, and frames where the
-- view had run past the drawn borders). For checking changes in the client,
-- where the simulated benchmarks (tools/bench.py) can't see the engine's cost.
local ADDON, ns = ...

local DURATION = 10
local HITCH = 1 / 30 -- a frame slower than this is a visible hitch

local rec -- the recording in progress

---------------------------------------------------------------------------
-- The client's own numbers, where it has them: its addon profiler
-- (C_AddOnProfiler, Retail-engine clients) times everything an addon runs,
-- events and every frame's scripts, so it's fair against other addons; and
-- each addon's memory.
---------------------------------------------------------------------------

local function Profiler()
	local P, M = C_AddOnProfiler, Enum and Enum.AddOnProfilerMetric
	if not (P and M and P.GetAddOnMetric) then return nil end
	if P.IsEnabled and not P.IsEnabled() then return nil end
	return P, M
end

-- Up to k { name, value } for the busiest addons, from GetTopKAddOnsForMetric.
local function TopAddOns(P, metric, k)
	if not P.GetTopKAddOnsForMetric then return {} end
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

-- KB per addon, biggest first: { { name, kb }, ... }.
local function Memory()
	local update = UpdateAddOnMemoryUsage or (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage)
	local get = GetAddOnMemoryUsage or (C_AddOns and C_AddOns.GetAddOnMemoryUsage)
	local count = C_AddOns and C_AddOns.GetNumAddOns or GetNumAddOns
	local info = C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo
	if not (update and get and count and info) then return nil end
	update()
	local out = {}
	for i = 1, count() do
		local name = info(i)
		local kb = name and get(i) or 0
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

-- Where the time went, busiest first: ms per frame, and calls and the
-- slowest one where that says more.
local function Where(r)
	local list, total = {}, 0
	for name, b in pairs(r.buckets) do
		list[#list + 1] = { name, b[1], b[2], b[3] }
		total = total + b[1]
	end
	table.sort(list, function(a, b) return a[2] > b[2] end)
	ns.Print(string.format("  all of MagicMap's scripts and events: %.3f ms/frame. Where:", total / r.frames))
	for i = 1, math.min(10, #list) do
		local e = list[i]
		local calls = (e[3] ~= r.frames) and string.format(", %d calls", e[3]) or ""
		ns.Print(string.format("    %s  %.3f ms/frame (max %.1f ms%s)", e[1], e[2] / r.frames, e[4], calls))
	end
end

-- /mm perf mem: MagicMap's memory before and after a full garbage
-- collection (what's left is live; the rest was garbage waiting for the
-- collector), and the objects behind it.
local function MemoryCheck()
	local update = UpdateAddOnMemoryUsage or (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage)
	local get = GetAddOnMemoryUsage or (C_AddOns and C_AddOns.GetAddOnMemoryUsage)
	if update and get then
		update()
		local before = get(ADDON)
		collectgarbage("collect")
		update()
		local after = get(ADDON)
		ns.Print(string.format("perf mem: MagicMap %.0f KB, %.0f KB after a full collection (%.0f KB was garbage)",
			before, after, before - after))
	end
	local counts = ns.PoolCounts and ns.PoolCounts({}) or {}
	local parts = {}
	for kind, c in pairs(counts) do parts[#parts + 1] = string.format("%d %s (%d in use)", c.made, kind, c.used) end
	table.sort(parts)
	if ns.TileCounts then
		local active, spare = ns.TileCounts()
		parts[#parts + 1] = string.format("%d tiles drawn, %d spare", active, spare)
	end
	ns.Print("  objects: " .. table.concat(parts, ", "))
end

-- /mm perf top: how MagicMap compares with your other addons, right now.
local function Compare()
	local P, M = Profiler()
	if P then
		local recent, peak = Metric(P, ADDON, M.RecentAverageTime), Metric(P, ADDON, M.PeakTime)
		local overall = P.GetOverallMetric and select(2, pcall(P.GetOverallMetric, M.RecentAverageTime))
		ns.Print(string.format("  client profiler: MagicMap %.3f ms/frame recently, peak %.1f ms%s",
			recent or 0, peak or 0, type(overall) == "number" and string.format("; all addons %.3f ms/frame", overall) or ""))
		local top = TopAddOns(P, M.RecentAverageTime, 6)
		if #top > 0 then ns.Print("  busiest addons: " .. Ranked(top, "%s %.3f", 6)) end
	else
		ns.Print("  client profiler: not available on this client")
	end
	local mem = Memory()
	if mem then
		local mine
		for i, e in ipairs(mem) do
			if e[1] == ADDON then mine = i end
		end
		ns.Print(string.format("  memory: MagicMap %s (#%s of %d); biggest: %s",
			mine and string.format("%.0f KB", mem[mine][2]) or "?", mine or "?", #mem, Ranked(mem, "%s %.0f KB", 6)))
	end
end

local function Report()
	local r = rec
	rec, ns.perf = nil, nil
	if r.frames == 0 then return ns.Print("perf: no frames recorded (is the map open?)") end
	ns.Print(string.format("perf: %d frames in %.1f s, %.0f fps, worst frame %.0f ms, %d hitches (>%d ms)",
		r.frames, r.t, r.frames / r.t, r.worst * 1000, r.hitches, HITCH * 1000))
	-- (The map's own frame script and border builder only: the client's profiler below counts everything.)
	ns.Print(string.format("  map script: %.2f ms/frame on average, %.1f ms at most (borders %.2f ms/frame)",
		(r.ms + r.buildMs) / r.frames, r.peak, r.buildMs / r.frames))
	ns.Print(string.format("  borders: %d builds (%.0f ms each), %d extensions, %d frames (%.0f%%) showing past them",
		r.builds, r.builds > 0 and r.buildTotal / r.builds or 0, r.extends, r.gaps, 100 * r.gaps / r.frames))
	Where(r)
	Compare()
end

local function Start()
	rec = { t = 0, frames = 0, worst = 0, hitches = 0, ms = 0, peak = 0, buildMs = 0,
		builds = 0, buildTotal = 0, extends = 0, gaps = 0, buckets = {} }
	-- Core and Layers report into this while it's set.
	ns.perf = {
		Frame = function(elapsed, ms)
			rec.t, rec.frames = rec.t + elapsed, rec.frames + 1
			rec.worst = math.max(rec.worst, elapsed)
			if elapsed > HITCH then rec.hitches = rec.hitches + 1 end
			rec.ms, rec.peak = rec.ms + ms, math.max(rec.peak, ms)
			local g = ns.GeometryInfo()
			if g.zoom and not g.covers then rec.gaps = rec.gaps + 1 end
			if rec.t >= DURATION then Report() end
		end,
		Slice = function(ms) rec.buildMs = rec.buildMs + ms end,
		-- Every timed entry point (Profile.lua): { ms, calls, max } by name.
		Spent = function(name, ms)
			if not rec then return end -- the recording ended inside this call
			local b = rec.buckets[name]
			if not b then
				b = { 0, 0, 0 }
				rec.buckets[name] = b
			end
			b[1], b[2] = b[1] + ms, b[2] + 1
			if ms > b[3] then b[3] = ms end
		end,
		Built = function(b)
			if b.extend then
				rec.extends = rec.extends + 1
			else
				rec.builds, rec.buildTotal = rec.builds + 1, rec.buildTotal + b.ms
			end
		end,
	}
	ns.Print(string.format("perf: recording %d s; pan and zoom around (/mm perf again to stop early)", DURATION))
end

ns.slash.perf = function(arg)
	if arg == "mem" then return MemoryCheck() end
	if arg == "top" then
		ns.Print("perf: MagicMap against your other addons, right now")
		return Compare()
	end
	if not debugprofilestop then return ns.Print("perf: this client has no profiling timer") end
	if rec then Report() else Start() end
end
