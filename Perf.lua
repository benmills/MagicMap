-- /mm perf: record a few seconds of real use and report how the map kept up
-- (frame times, the addon's own time, border builds, and frames where the
-- view had run past the drawn borders). For checking changes in the client,
-- where the simulated benchmarks (tools/bench.py) can't see the engine's cost.
local _, ns = ...

local DURATION = 10
local HITCH = 1 / 30 -- a frame slower than this is a visible hitch

local rec -- the recording in progress

local function Report()
	local r = rec
	rec, ns.perf = nil, nil
	if r.frames == 0 then return ns.Print("perf: no frames recorded (is the map open?)") end
	ns.Print(string.format("perf: %d frames in %.1f s, %.0f fps, worst frame %.0f ms, %d hitches (>%d ms)",
		r.frames, r.t, r.frames / r.t, r.worst * 1000, r.hitches, HITCH * 1000))
	ns.Print(string.format("  MagicMap: %.2f ms/frame on average, %.1f ms at most (borders %.2f ms/frame)",
		(r.ms + r.buildMs) / r.frames, r.peak, r.buildMs / r.frames))
	ns.Print(string.format("  borders: %d builds (%.0f ms each), %d extensions, %d frames (%.0f%%) showing past them",
		r.builds, r.builds > 0 and r.buildTotal / r.builds or 0, r.extends, r.gaps, 100 * r.gaps / r.frames))
end

local function Start()
	rec = { t = 0, frames = 0, worst = 0, hitches = 0, ms = 0, peak = 0, buildMs = 0,
		builds = 0, buildTotal = 0, extends = 0, gaps = 0 }
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

ns.slash.perf = function()
	if not debugprofilestop then return ns.Print("perf: this client has no profiling timer") end
	if rec then Report() else Start() end
end
