-- /mma bench regions: what this client charges for the region calls the map
-- makes, in us a call, so the engine's choices (park, swap, scale) and the
-- sim's prices come from the client, not guesses. Made N at a time: textures,
-- lines, font strings; anchored: SetPoint, SetStartPoint; parked: SetParent
-- onto a hidden frame and back; a canvas's own calls (SetPoint, SetScale,
-- SetAlpha, Hide, Show) over 100 live, 1000 live and 1000 hidden child Lines
-- (the borders' kind: the play-test's ~20 us a region, hidden pooled Lines
-- still paying); and the swap's question (ui/Engine.lua, docs/runtime.md "The map's engine"):
-- Show after the 1000 live lines moved while hidden (the M0 gate's 35-50 us a line), the same
-- at alpha 0, SetAlpha(1) after they moved while shown at alpha 0 (the engine's swap), and Show
-- after 100 masked textures moved (a tile's art and its coast fade). Each call is timed alone in
-- a Job, its frames graced ("bench"), and a canvas-wide call (setup, timed, or between ops) gets
-- a frame to itself, so the run's frames cost no more than one such call; every region is clear,
-- so nothing shows. And what no call's time can show, a cost the client defers to its drawing: the
-- whole frame after the 1000 lines moved on a shown canvas at alpha 0 (the engine's back canvas),
-- against the same move on a hidden canvas and an idle frame (frame.*: µs a frame, debugprofilestop
-- across the yield).
-- Bench.result = { build, t, ops = { [op] = { n, ms, us } } } (Telemetry keeps it per build).

local _, ns = ...
local Game, Runtime = ns.Game, ns.Runtime

local Bench = {}
Game.Bench = Bench

local N, REPS = 100, 20 -- regions made, anchored and parked; timed calls per canvas op
local CANVASES = { { at = "100live", n = 100 }, { at = "1000live", n = 1000 }, { at = "1000hidden", n = 1000, hidden = true } }
local JOB_MS, JOB_FRAMES = 4, 3600
local now = debugprofilestop

-- A clipped window mid-screen, as the map's view; the park, hidden.
local root = CreateFrame("Frame", nil, UIParent)
root:SetSize(320, 200)
root:SetPoint("CENTER")
root:SetClipsChildren(true)
root:Hide()
local park = CreateFrame("Frame", nil, UIParent)
park:Hide()

local function R(v, k) return math.floor(v * k + 0.5) / k end -- /: never 0 (k: a literal at each call)
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask" -- a mask the client has (ui/Art.lua), as a tile's coast fade

local result, order, job -- the run's, committed at its end

local function Yield()
	Runtime.Grace("bench", 0.1)
	Runtime.Yield()
end

-- op: fn(i) for i = 1..n, each call timed alone; setup(i) before it, untimed, in its own stretch.
local function Time(op, n, fn, setup)
	local ms = 0
	for i = 1, n do
		if setup then setup(i); Yield() end
		local t = now()
		fn(i)
		ms = ms + now() - t
		Yield()
	end
	result.ops[op] = { n = n, ms = R(ms, 1000), us = R(ms * 1000 / n, 100) } -- /: never 0 (n: N or REPS)
	order[#order + 1] = op
end

-- op: the whole frame after setup() (untimed): from just before the job gives the frame back to
-- its next resume, the client's drawing included.
local function Frame(op, setup)
	local ms = 0
	for _ = 1, REPS do
		Runtime.Grace("bench", 0.1)
		setup()
		local t = now()
		coroutine.yield()
		ms = ms + now() - t
		Yield()
	end
	result.ops[op] = { n = REPS, ms = R(ms, 1000), us = R(ms * 1000 / REPS, 100) } -- /: never 0 (REPS: a literal)
	order[#order + 1] = op
end

-- A border's hairline on canvas c.
local function Line(c, i)
	local l = c:CreateLine(nil, "ARTWORK")
	l:SetColorTexture(1, 1, 1, 0)
	l:SetThickness(1)
	local x, y = i % 40 * 8, -math.floor(i / 40) * 8
	l:SetStartPoint("TOPLEFT", c, x, y)
	l:SetEndPoint("TOPLEFT", c, x + 6, y - 3)
	return l
end

-- A tile's art with its coast fade, clear.
local function Masked(c, i)
	local t = c:CreateTexture(nil, "ARTWORK")
	t:SetColorTexture(1, 1, 1, 0)
	t:SetSize(8, 8)
	t:SetPoint("TOPLEFT", c, "TOPLEFT", i % 10 * 9, -math.floor(i / 10) * 9)
	t.mask = c:CreateMaskTexture()
	t.mask:SetTexture(MASK, "CLAMP", "CLAMP")
	t.mask:SetAllPoints(t)
	t:AddMaskTexture(t.mask)
	return t
end

-- A canvas as the map's (1x1, regions placed from its TOPLEFT), built on the first run: spec.n Lines
-- (spec.masked: textures with masks), spec.regions.
local function Canvas(spec)
	if spec.frame then return spec.frame end
	local c = CreateFrame("Frame", nil, root)
	c:SetSize(1, 1)
	c:SetPoint("TOPLEFT")
	spec.regions = {}
	for i = 1, spec.n do
		local r = spec.masked and Masked(c, i) or Line(c, i)
		if spec.hidden then r:Hide() end
		spec.regions[i] = r
		Yield()
	end
	spec.frame = c
	return c
end

-- Every region of a canvas anchored k px further right (k: 0 or 1, in turn), untimed.
local function Move(spec, k)
	local c = spec.frame
	for i, r in ipairs(spec.regions) do
		if spec.masked then
			r:SetPoint("TOPLEFT", c, "TOPLEFT", i % 10 * 9 + k, -math.floor(i / 10) * 9)
		else
			local x, y = i % 40 * 8 + k, -math.floor(i / 40) * 8
			r:SetStartPoint("TOPLEFT", c, x, y)
			r:SetEndPoint("TOPLEFT", c, x + 6, y - 3)
		end
	end
end

local function Run()
	root:Show()
	local made = CreateFrame("Frame", nil, root)
	made:SetSize(1, 1)
	made:SetPoint("TOPLEFT")
	local tex, lines = {}, {}
	Time("CreateTexture", N, function(i) tex[i] = made:CreateTexture(nil, "ARTWORK") end)
	Time("CreateLine", N, function(i) lines[i] = made:CreateLine(nil, "ARTWORK") end)
	Time("CreateFontString", N, function() made:CreateFontString(nil, "OVERLAY") end)
	Time("SetPoint", N, function(i) tex[i]:SetPoint("TOPLEFT", made, "TOPLEFT", i, -i) end)
	Time("SetStartPoint", N, function(i) lines[i]:SetStartPoint("TOPLEFT", made, i, -i) end)
	Time("SetParent.park", N, function(i) lines[i]:SetParent(park) end)
	Time("SetParent.unpark", N, function(i) lines[i]:SetParent(made) end)
	made:Hide()
	for _, spec in ipairs(CANVASES) do
		local c, at = Canvas(spec), "@" .. spec.at
		c:Show()
		Yield()
		Time("canvas.SetPoint" .. at, REPS, function(i) c:SetPoint("TOPLEFT", -i, i) end)
		Time("canvas.SetScale" .. at, REPS, function(i) c:SetScale(i % 2 == 0 and 1 or 1.25) end)
		Time("canvas.SetAlpha" .. at, REPS, function(i) c:SetAlpha(i % 2 == 0 and 1 or 0) end)
		Time("canvas.Hide" .. at, REPS, function() c:Hide() end, function() c:Show() end)
		Time("canvas.Show" .. at, REPS, function() c:Show() end, function() c:Hide() end)
		c:Hide()
		Yield()
	end
	-- Shown after moving: at alpha 1, at alpha 0, and moved while shown at alpha 0 (a frame drawn between)
	-- then SetAlpha(1); masked textures.
	local live, masked, k = CANVASES[2], { n = 100, masked = true }, 0
	local c = live.frame
	local function Moved(spec) k = 1 - k; Move(spec, k) end
	Time("canvas.Show.moved@1000live", REPS, function() c:Show() end, function() c:Hide(); Moved(live) end)
	Time("canvas.Show.moved.alpha0@1000live", REPS, function() c:Show() end,
		function() c:Hide(); c:SetAlpha(0); Moved(live) end)
	Time("canvas.SetAlpha.moved@1000live", REPS, function() c:SetAlpha(1) end,
		function() c:SetAlpha(0); Moved(live); coroutine.yield() end)
	c:SetAlpha(0)
	Frame("frame.idle", function() end)
	Frame("frame.moved.alpha0", function() Moved(live) end)
	c:Hide()
	Yield()
	Frame("frame.moved.hidden", function() Moved(live) end)
	local m = Canvas(masked)
	Time("canvas.Show.moved@100masked", REPS, function() m:Show() end, function() m:Hide(); Moved(masked) end)
	m:Hide()
	Yield()
	-- root stays shown: all under it is hidden, and hiding it would walk every region (hidden ones still pay).
end

local function Report()
	Game.Print("bench regions (" .. result.build .. "), us a call:")
	for _, op in ipairs(order) do
		local o, n = result.ops[op], tonumber(op:match("@(%d+)"))
		local each = n and string.format("  (%.3f a child)", o.us / n) or "" -- /: never 0 (n: 100 or 1000, CANVASES)
		print(string.format("  %-28s %9.2f%s", op, o.us, each))
	end
end

Game.Slash("bench", "regions: time the region calls the map makes (us a call; a few seconds)", function(args)
	if args ~= "regions" then return Game.Print("bench regions: time the region calls the map makes") end
	if job and not job.done then return Game.Print("bench: still running") end
	local v, build = GetBuildInfo()
	result, order = { build = v .. "." .. build, t = time(), ops = {} }, {}
	job = Runtime.Job("bench: regions", function()
		Run()
		Bench.result = result
		Report()
	end, JOB_MS, JOB_FRAMES)
end)
