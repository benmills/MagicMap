-- /mma bench regions: what this client charges for the region calls the map
-- makes, in us a call, so the engine's choices (park, swap, scale) and the
-- sim's prices come from the client, not guesses. Made N at a time: textures,
-- lines, font strings; anchored: SetPoint, SetStartPoint; parked: SetParent
-- onto a hidden frame and back; a canvas's own calls (SetPoint, SetScale,
-- SetAlpha, Hide, Show) over 100 live, 1000 live and 1000 hidden child Lines
-- (the borders' kind: the play-test's ~20 us a region, hidden pooled Lines
-- still paying). Each call is timed alone in a Job, its frames graced ("bench"),
-- and a canvas-wide call (setup, timed, or between ops) gets a frame to itself, so
-- the run's frames cost no more than one such call; every region is clear, so nothing shows.
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

-- A canvas as the map's (1x1, regions placed from its TOPLEFT), built on the first run.
local function Canvas(spec)
	if spec.frame then return spec.frame end
	local c = CreateFrame("Frame", nil, root)
	c:SetSize(1, 1)
	c:SetPoint("TOPLEFT")
	for i = 1, spec.n do
		local l = Line(c, i)
		if spec.hidden then l:Hide() end
		Yield()
	end
	spec.frame = c
	return c
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
