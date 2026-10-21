-- /mm bench regions: what this client charges for the region calls the map
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
-- a frame to itself, so the run's frames cost no more than one such call; every region is clear
-- until the moved and alpha ops, whose 1000 lines are coloured as a border's (a canvas at alpha 0
-- hides them; shown, the 320x200 clipped box shows them a frame at a time). And what no call's time
-- can show, a cost the client defers to its drawing: the whole frame after the 1000 lines moved on a
-- shown canvas at alpha 0 (the engine's back canvas), against the same move on a hidden canvas and an
-- idle frame; and the engine's swap, the frame after SetAlpha(1) on lines moved at alpha 0 a frame
-- before (frame.swap: the final session's deciding number; frame.*: µs a frame, debugprofilestop
-- across the yield). And a minimum zoom crossed (ui/Engine.lua's pins): 500 pins moved and shown in one
-- frame, each by its own SetAlpha (reveal.each, the cut before the M1b review's second round: the draw's
-- 3.1 ms priced for the big window's ~440 rares) or by their frame's (reveal.frame, the engine's now),
-- the calls and the frame after them. And the path's lines (ui/Path.lua): 160 Lines on a shown canvas, each
-- moved while hidden then shown by its own Show (line.Show.moved: the sim prices a frame's Show after a move,
-- not a line's). And quest areas (ui/Areas.lua, game/Oracles.lua), when your map has
-- quests: up to 25 of them drawn on a QuestPOIFrame the big map's size, a DrawBlob each (poi.DrawBlob),
-- a frame's all (poi.draw: DrawNone and every DrawBlob, as ui/Areas.lua draws a frame), a hit test
-- (poi.UpdateMouseOverTooltip), and the frame after drawing them all (frame.poi).
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
local PINS = 500 -- a minimum zoom's pins (~440 rares in the big window at 60)
local PATH = 160 -- the path's lines a pool (ui/Path.lua MAX_PIECES)
local POI_QUESTS, POI_SIZE = 25, 1024 -- quests drawn (a hub's), px (a zone on the big map)
local BLOB = "Interface\\WorldMap\\UI-QuestBlob-" -- Inside / Outside (Layers.lua:786)
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
	-- then SetAlpha(1); masked textures. The lines coloured as a border's (ui/Borders.lua ZONE), so the
	-- client has something to draw.
	local live, masked, k = CANVASES[2], { n = 100, masked = true }, 0
	local c = live.frame
	c:SetAlpha(0)
	for i, l in ipairs(live.regions) do
		l:SetColorTexture(1, 0.9, 0.72, 0.6)
		if i % 100 == 0 then Yield() end
	end
	local function Moved(spec) k = 1 - k; Move(spec, k) end
	Time("canvas.Show.moved@1000live", REPS, function() c:Show() end, function() c:Hide(); Moved(live) end)
	Time("canvas.Show.moved.alpha0@1000live", REPS, function() c:Show() end,
		function() c:Hide(); c:SetAlpha(0); Moved(live) end)
	Time("canvas.SetAlpha.moved@1000live", REPS, function() c:SetAlpha(1) end,
		function() c:SetAlpha(0); Moved(live); coroutine.yield() end)
	c:SetAlpha(0)
	Frame("frame.idle", function() end)
	Frame("frame.moved.alpha0", function() Moved(live) end)
	Frame("frame.swap", function() c:SetAlpha(0); Moved(live); coroutine.yield(); c:SetAlpha(1) end)
	c:SetAlpha(0)
	c:Hide()
	Yield()
	Frame("frame.moved.hidden", function() Moved(live) end)
	local m = Canvas(masked)
	Time("canvas.Show.moved@100masked", REPS, function() m:Show() end, function() m:Hide(); Moved(masked) end)
	m:Hide()
	Yield()
	-- A minimum zoom crossed: the pins at alpha 0 a frame (each, or their frame), then moved and shown.
	local f, pins = CreateFrame("Frame", nil, root), {}
	f:SetAllPoints()
	for i = 1, PINS do
		local t = f:CreateTexture(nil, "OVERLAY")
		t:SetColorTexture(1, 0.8, 0.2, 1)
		t:SetSize(6, 6)
		pins[i] = t
		if i % 50 == 0 then Yield() end
	end
	local function Pins(alpha)
		k = 1 - k
		for i, t in ipairs(pins) do
			t:SetPoint("CENTER", root, "TOPLEFT", i % 25 * 12 + k, -math.floor(i / 25) * 10)
			if alpha then t:SetAlpha(alpha) end
		end
	end
	local function Each() for _, t in ipairs(pins) do t:SetAlpha(0) end; coroutine.yield() end
	local function Whole() f:SetAlpha(0); coroutine.yield() end
	Time("reveal.each@" .. PINS, REPS, function() Pins(1) end, Each)
	Time("reveal.frame@" .. PINS, REPS, function() Pins(); f:SetAlpha(1) end, function() for _, t in ipairs(pins) do t:SetAlpha(1) end; Whole() end)
	Frame("frame.reveal.each", function() Each(); Pins(1) end)
	Frame("frame.reveal.frame", function() Whole(); Pins(); f:SetAlpha(1) end)
	f:Hide()
	Yield()
	-- The path's lines: hidden, moved, each shown on its own (a layout's), on a canvas shown.
	local line = { frame = CreateFrame("Frame", nil, root), regions = {} }
	line.frame:SetSize(1, 1)
	line.frame:SetPoint("TOPLEFT")
	for i = 1, PATH do
		local l = Line(line.frame, i)
		l:SetColorTexture(1, 0.93, 0.76, 0.7)
		l:Hide()
		line.regions[i] = l
	end
	Yield()
	Time("line.Show.moved@" .. PATH, REPS, function() for _, l in ipairs(line.regions) do l:Show() end end,
		function() for _, l in ipairs(line.regions) do l:Hide() end; Moved(line) end)
	line.frame:Hide()
	Yield()
	-- Quest areas: your map's quests (the client's art and hit test), on a frame laid out a frame before.
	local map, ids = C_Map.GetBestMapForUnit("player"), {}
	for _, q in ipairs(map and C_QuestLog.GetQuestsOnMap(map) or {}) do
		if #ids < POI_QUESTS and not q.isMapIndicatorQuest then ids[#ids + 1] = q.questID end
	end
	if ids[1] then
		local poi, n = CreateFrame("QuestPOIFrame", nil, root), #ids
		poi:SetSize(POI_SIZE, POI_SIZE)
		poi:SetPoint("TOPLEFT")
		poi:EnableMouse(false)
		poi:SetFillTexture(BLOB .. "Inside")
		poi:SetBorderTexture(BLOB .. "Outside")
		poi:SetMapID(map)
		poi:GetRect()
		Yield()
		Time("poi.DrawBlob", REPS, function(i) poi:DrawBlob(ids[(i - 1) % n + 1], true) end,
			function(i) if (i - 1) % n == 0 then poi:DrawNone() end end)
		Time("poi.draw", REPS, function()
			poi:DrawNone()
			for _, id in ipairs(ids) do poi:DrawBlob(id, true) end
		end)
		Time("poi.UpdateMouseOverTooltip", REPS, function(i) poi:UpdateMouseOverTooltip(i % 5 * 0.2 + 0.1, i % 4 * 0.25 + 0.1) end)
		Frame("frame.poi", function()
			poi:DrawNone()
			for _, id in ipairs(ids) do poi:DrawBlob(id, true) end
		end)
		poi:DrawNone()
		poi:Hide()
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
