-- /mm probe: can we read Blizzard's Minimap blips ourselves, and how cheaply
-- and exactly? An experiment, to come out once answered.
--
-- NodeSight showed the way: the Minimap answers a pretend mouse (the
-- controller's soft cursor) anywhere on it. With
-- Minimap:SetUsingSoftCursor(true), Minimap:UpdateMouseoverAtPoint(x, y)
-- (screen pixels) moves its hover point and C_TooltipInfo.GetMinimapMouseover()
-- returns the names of the blips under it, the same frame. Our own try
-- (c177f4b) left the soft cursor off and found nothing.
--
--   /mm probe basic   does it work here: soft cursor off vs on, the two ways
--                     to read it, same frame or next, what the data holds
--   /mm probe here    hover a blip with the real mouse, then type it: checks
--                     the coordinate convention against the real cursor
--   /mm probe sense   which Minimap states still answer (alpha 0, hidden,
--                     off screen, other sizes and zooms, masks, icon scale)
--   /mm probe shape   one blip's answer area: size, shape, what it scales
--                     with, and how exactly its middle can be found
--   /mm probe cost    microseconds per call, by Minimap size and zoom
--   /mm probe race    ways to find every blip: probes, time, misses, error
--   /mm probe drift   20 s of scans while you walk: how steady each blip is
--   /mm probe truth   party members' blips against their real positions
--   /mm probe all     basic, sense, shape, cost and race in a row
--   /mm probe stop    stop the running test
--
-- Each test (but here) closes the map so Blizzard's Minimap is home, puts
-- back everything it changes, and reopens the map. Findings go to chat and
-- to MagicMapDB.probe (in SavedVariables after a /reload). Stand still among
-- a few blips (Find Herbs, Find Minerals, or tracked NPCs in a town) with the
-- mouse off the minimap.

local ADDON, ns = ...

local SQUARE_MASK = "Interface\\Buttons\\WHITE8X8"
local ROUND_MASK = "Interface\\Masks\\CircleMaskScalable"
local PER_FRAME = 150 -- probes a scan tries each frame
local DIAG = 1 / math.sqrt(2)

local db
local job -- the test running: { co, lines, wait, section, reopen, snap }
local secrets = 0 -- answers withheld as secret values
local probes = 0 -- pretend mouse moves since the counter was last read
local soft = false
local g = {} -- the Minimap now: left, bottom (its units), scale, w, h, radius (yd), you (north, west)

---------------------------------------------------------------------------
-- Output
---------------------------------------------------------------------------

local function Line(show, fmt, ...)
	local text = select("#", ...) > 0 and fmt:format(...) or fmt
	if job then
		text = job.section and (job.section .. ": " .. text) or text
		job.lines[#job.lines + 1] = text
	end
	if show then ns.Print("probe " .. text) end
end
local function Say(...) Line(true, ...) end  -- to chat and kept
local function Note(...) Line(false, ...) end -- kept only

local function Yd(v) return v and string.format("%.2f", v) or "-" end

---------------------------------------------------------------------------
-- The pretend mouse
---------------------------------------------------------------------------

local function Soft(on)
	if soft ~= on then
		soft = on
		Minimap:SetUsingSoftCursor(on)
	end
end

-- Next frame (or `frames` on). The soft cursor is never left on across frames.
local function Wait(frames)
	Soft(false)
	coroutine.yield(frames or 1)
end

local function Measure()
	g.left, g.bottom = Minimap:GetLeft(), Minimap:GetBottom()
	g.scale = Minimap:GetEffectiveScale()
	g.w, g.h = Minimap:GetSize()
	local r = C_Minimap.GetViewRadius()
	g.radius = (r and not issecretvalue(r)) and r or nil
	g.north, g.west = UnitPosition("player")
	if g.north and issecretvalue(g.north) then g.north, g.west = nil, nil end
	return g.left ~= nil and g.radius ~= nil
end

local function Clean(text)
	text = text:gsub("|A.-|a", ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	return text:match("^%s*(.-)%s*$")
end

-- The names the Minimap gives for its hover point now: a list, or nil.
local function Read()
	local data = C_TooltipInfo.GetMinimapMouseover()
	if not data then return nil end
	if issecretvalue(data) or issecretvalue(data.lines) then
		secrets = secrets + 1
		return nil
	end
	local out
	for _, line in ipairs(data.lines or {}) do
		local text = line.leftText
		if text and issecretvalue(text) then
			secrets = secrets + 1
		elseif text then
			for part in text:gmatch("[^\n]+") do
				part = Clean(part)
				if part ~= "" then
					out = out or {}
					out[#out + 1] = part
				end
			end
		end
	end
	return out
end

local function Has(names, name)
	for _, n in ipairs(names or {}) do
		if n == name then return true end
	end
	return false
end

-- What answers at (x, y), Minimap units from its bottom left (may lie outside it).
local function At(x, y)
	if not g.left then return nil end
	probes = probes + 1
	Minimap:UpdateMouseoverAtPoint((g.left + x) * g.scale, (g.bottom + y) * g.scale)
	return Read()
end

---------------------------------------------------------------------------
-- Minimap units <-> the world. Tests keep it north up.
---------------------------------------------------------------------------

-- Yards east and north of you, and the world spot (yards; from the player's
-- spot as 0, 0 where the game withholds it).
local function ToWorld(x, y)
	local u = g.radius / (g.w / 2)
	local east, north = (x - g.w / 2) * u, (y - g.h / 2) * u
	return (g.north or 0) + north, (g.west or 0) - east, math.sqrt(east * east + north * north)
end

local function FromWorld(north, west)
	local u = g.radius / (g.w / 2)
	return g.w / 2 + ((g.west or 0) - west) / u, g.h / 2 + (north - (g.north or 0)) / u
end

local function NewBlip(name, x, y, cells)
	local north, west, yards = ToWorld(x, y)
	return { name = name, x = x, y = y, cells = cells, north = north, west = west, yards = yards }
end

local function Gap(a, b)
	return math.sqrt((a.north - b.north) ^ 2 + (a.west - b.west) ^ 2)
end

---------------------------------------------------------------------------
-- Finding blips
---------------------------------------------------------------------------

-- The groups of neighbouring cells (keys i * 4096 + j) in a set.
local AROUND = { -4097, -4096, -4095, -1, 1, 4095, 4096, 4097 }
local function Groups(set)
	local groups, seen = {}, {}
	for first in pairs(set) do
		if not seen[first] then
			seen[first] = true
			local stack, keys = { first }, {}
			while #stack > 0 do
				local k = table.remove(stack)
				keys[#keys + 1] = k
				for _, d in ipairs(AROUND) do
					if set[k + d] and not seen[k + d] then
						seen[k + d] = true
						stack[#stack + 1] = k + d
					end
				end
			end
			groups[#groups + 1] = keys
		end
	end
	return groups
end

-- Every name on a grid `step` units apart over the Minimap and `margin`
-- past its edges: a blip per group of neighbouring points with a name, at
-- the group's middle. Spread over frames.
local function Scan(step, margin, perFrame)
	margin, perFrame = margin or 0, perFrame or PER_FRAME
	local res = { step = step, probes = 0, ms = 0, outside = 0, frames = 1, blips = {} }
	if not Measure() then return res end
	local cells = {}
	local nx, ny = math.floor((g.w + 2 * margin) / step), math.floor((g.h + 2 * margin) / step)
	local n = 0
	Soft(true)
	for i = 0, nx do
		for j = 0, ny do
			local x, y = i * step - margin, j * step - margin
			local t = debugprofilestop()
			local names = At(x, y)
			res.ms = res.ms + debugprofilestop() - t
			if names then
				if x < 0 or y < 0 or x > g.w or y > g.h then res.outside = res.outside + 1 end
				for _, name in ipairs(names) do
					cells[name] = cells[name] or {}
					cells[name][i * 4096 + j] = true
				end
			end
			n = n + 1
			if n % perFrame == 0 then
				Wait(1)
				res.frames = res.frames + 1
				Measure()
				Soft(true)
			end
		end
	end
	Soft(false)
	res.probes = n
	for name, set in pairs(cells) do
		for _, keys in ipairs(Groups(set)) do
			local sx, sy = 0, 0
			for _, k in ipairs(keys) do sx, sy = sx + math.floor(k / 4096), sy + k % 4096 end
			res.blips[#res.blips + 1] = NewBlip(name, sx / #keys * step - margin, sy / #keys * step - margin, #keys)
		end
	end
	table.sort(res.blips, function(a, b) return a.yards < b.yards end)
	return res
end

-- How far from (x, y), inside the blip, it still answers going (dx, dy):
-- out in `stepOut` units until it stops, then halved in on `halvings` times.
-- nil if it still answers `reach` away.
local function Edge(name, x, y, dx, dy, reach, stepOut, halvings)
	local inside, outside, d = 0, nil, stepOut
	while d <= reach do
		if Has(At(x + dx * d, y + dy * d), name) then
			inside, d = d, d + stepOut
		else
			outside = d
			break
		end
	end
	if not outside then return nil end
	for _ = 1, halvings do
		local mid = (inside + outside) / 2
		if Has(At(x + dx * mid, y + dy * mid), name) then inside = mid else outside = mid end
	end
	return (inside + outside) / 2
end

-- A blip's middle from where it stops answering left and right, then down
-- and up (`passes` times, each from the last middle), its reach along the
-- axes, and with `diagonals` along them too. nil if it doesn't answer at x, y.
local function Refine(name, x, y, o)
	o = o or {}
	local passes, stepOut, halvings, reach = o.passes or 2, o.stepOut or 0.5, o.halvings or 8, o.reach or 60
	if not Has(At(x, y), name) then return nil end
	local axis
	for _ = 1, passes do
		local e, w = Edge(name, x, y, 1, 0, reach, stepOut, halvings), Edge(name, x, y, -1, 0, reach, stepOut, halvings)
		if not (e and w) then return nil end
		x = x + (e - w) / 2
		local n, s = Edge(name, x, y, 0, 1, reach, stepOut, halvings), Edge(name, x, y, 0, -1, reach, stepOut, halvings)
		if not (n and s) then return nil end
		y = y + (n - s) / 2
		axis = (e + w + n + s) / 4
	end
	local diag
	if o.diagonals then
		local sum = 0
		for _, d in ipairs({ { 1, 1 }, { -1, -1 }, { -1, 1 }, { 1, -1 } }) do
			local r = Edge(name, x, y, d[1] * DIAG, d[2] * DIAG, reach, stepOut, halvings)
			if not r then return x, y, axis end
			sum = sum + r
		end
		diag = sum / 4
	end
	return x, y, axis, diag
end

-- Each of a scan's blips put on its exact middle (a frame each).
local function RefineAll(blips, o)
	local out = {}
	for _, b in ipairs(blips) do
		Measure()
		Soft(true)
		local x, y, axis = Refine(b.name, b.x, b.y, o)
		if x then
			local r = NewBlip(b.name, x, y, b.cells)
			r.axis = axis
			out[#out + 1] = r
		end
		Wait(1)
	end
	return out
end

-- For each blip in `ref`, the nearest of the same name in `got` within
-- `most` yards: found, mean and worst gap (yd), and how many of `got`
-- matched nothing. `keep(b)` picks which of ref count.
local function Match(ref, got, most, keep)
	local used, found, sum, worst, total = {}, 0, 0, 0, 0
	for _, a in ipairs(ref) do
		if not keep or keep(a) then
			total = total + 1
			local best, gap
			for _, b in ipairs(got) do
				if not used[b] and b.name == a.name then
					local d = Gap(a, b)
					if d <= (most or 15) and (not gap or d < gap) then best, gap = b, d end
				end
			end
			if best then
				used[best] = true
				found, sum, worst = found + 1, sum + gap, math.max(worst, gap)
			end
		end
	end
	local extra = 0
	for _, b in ipairs(got) do
		if not used[b] then extra = extra + 1 end
	end
	return { found = found, total = total, mean = found > 0 and sum / found or nil, worst = found > 0 and worst or nil, extra = extra }
end

---------------------------------------------------------------------------
-- The Minimap's state, kept and put back
---------------------------------------------------------------------------

local function Snapshot()
	local m = Minimap
	local s = {
		parent = m:GetParent(), w = m:GetWidth(), h = m:GetHeight(), alpha = m:GetAlpha(), zoom = m:GetZoom(),
		shown = m:IsShown(), ground = C_Minimap.GetDrawGroundTextures(), unrotated = C_Minimap.IsRotateMinimapIgnored(),
		clusterAlpha = MinimapCluster:GetAlpha(), clusterShown = MinimapCluster:IsShown(), points = {},
	}
	for i = 1, m:GetNumPoints() do s.points[i] = { m:GetPoint(i) } end
	return s
end

local function Restore(s)
	local m = Minimap
	Soft(false)
	if m:GetParent() ~= s.parent then m:SetParent(s.parent) end
	m:ClearAllPoints()
	for _, p in ipairs(s.points) do m:SetPoint(unpack(p)) end
	m:SetSize(s.w, s.h)
	m:SetAlpha(s.alpha)
	if m:GetZoom() ~= s.zoom then m:SetZoom(s.zoom) end
	m:SetShown(s.shown)
	C_Minimap.SetDrawGroundTextures(s.ground)
	C_Minimap.SetIgnoreRotateMinimap(s.unrotated)
	MinimapCluster:SetAlpha(s.clusterAlpha)
	MinimapCluster:SetShown(s.clusterShown)
	if s.iconScaled then
		m:SetIconScale(1)
		s.iconScaled = nil
	end
	if s.masked then
		m:SetMaskTexture(ROUND_MASK)
		s.masked = nil
	end
end

-- Back as the test found it, and a few frames for the client to redraw.
local function Reset()
	Restore(job.snap)
	C_Minimap.SetIgnoreRotateMinimap(true)
	Wait(3)
end

-- Centred where it is (or at cx, cy, its own units from the screen's
-- bottom left), `size` units across.
local function Place(size, cx, cy)
	local x, y = Minimap:GetCenter()
	Minimap:ClearAllPoints()
	Minimap:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx or x, cy or y)
	if size then Minimap:SetSize(size, size) end
end

local function IconScale(s)
	job.snap.iconScaled = true
	Minimap:SetIconScale(s)
end

---------------------------------------------------------------------------
-- The tests
---------------------------------------------------------------------------

local tests = {}

local function Geometry()
	Measure()
	Say("Minimap %dx%d units, scale %.2f, zoom %d of %d, radius %s yd, rotate %s, %s",
		g.w, g.h, g.scale, Minimap:GetZoom(), Minimap:GetZoomLevels() - 1, Yd(g.radius),
		C_CVar.GetCVar("rotateMinimap"), g.north and "your position known" or "your position withheld")
end

-- A first scan, or nil (and why) when there's nothing to test with.
local function Baseline(step)
	local res = Scan(step or 4)
	if #res.blips == 0 then
		Say("no blips answered. Turn on Find Herbs / Find Minerals or town tracking and stand among a few.")
		return nil
	end
	return res
end

local function ListBlips(blips, most)
	for i, b in ipairs(blips) do
		if i > (most or 12) then
			Say("  ... and %d more", #blips - i + 1)
			break
		end
		Say("  %s: %s yd%s", b.name, Yd(b.yards), b.axis and (", reach " .. Yd(b.axis) .. " units") or "")
	end
end

-- TooltipData as text, a few levels deep.
local function Dump(v, depth)
	if issecretvalue(v) then return "<secret>" end
	if type(v) ~= "table" then return tostring(v) end
	if depth <= 0 then return "{...}" end
	local parts = {}
	for k, x in pairs(v) do parts[#parts + 1] = tostring(k) .. "=" .. Dump(x, depth - 1) end
	table.sort(parts)
	return "{" .. table.concat(parts, ", ") .. "}"
end

local probeTip
local function TipNames()
	probeTip = probeTip or CreateFrame("GameTooltip", "MagicMapProbeTip", nil, "GameTooltipTemplate")
	probeTip:SetOwner(UIParent, "ANCHOR_NONE")
	probeTip:SetMinimapMouseover()
	local out = {}
	for i = 1, probeTip:NumLines() do
		local fs = _G["MagicMapProbeTipTextLeft" .. i]
		local text = fs and fs:GetText()
		if text and not issecretvalue(text) then
			for part in text:gmatch("[^\n]+") do out[#out + 1] = Clean(part) end
		end
	end
	probeTip:Hide()
	return out
end

function tests.basic()
	Geometry()
	-- The soft cursor off: the pretend mouse should do nothing.
	Measure()
	local off = 0
	for i = 0, 20 do
		for j = 0, 20 do
			if At(i * g.w / 20, j * g.h / 20) then off = off + 1 end
		end
	end
	Say("soft cursor off: %d of 441 points answered (0 = it's needed)", off)
	local res = Baseline(4)
	if not res then return end
	Say("soft cursor on, grid 4: %d blips from %d probes over %d frames (%.2f ms probing)", #res.blips, res.probes, res.frames, res.ms)
	local exact = RefineAll(res.blips)
	ListBlips(exact)
	job.data.blips = exact
	-- The two ways to read it, and when the answer changes.
	local b = exact[1] or res.blips[1]
	Measure()
	Soft(true)
	local now = At(b.x, b.y)
	local tip = TipNames()
	local empty = At(-g.w, -g.h)
	Say("on %s, same frame: C_TooltipInfo %s; GameTooltip:SetMinimapMouseover %s; moved off: %s",
		b.name, Has(now, b.name) and "names it" or "doesn't", Has(tip, b.name) and "names it" or "doesn't",
		empty and "still answers" or "nothing")
	At(b.x, b.y)
	Wait(1)
	Measure()
	Soft(true)
	Say("a frame later, not moved again: %s", Has(Read(), b.name) and "still names it" or "nothing")
	local data = (At(b.x, b.y) and C_TooltipInfo.GetMinimapMouseover())
	Soft(false)
	Say("its TooltipData: %s", Dump(data, 4))
	Say("secret answers so far: %d", secrets)
end

-- The real mouse on a blip; reads it as the game does, then the pretend
-- mouse at the cursor in each coordinate convention.
function tests.here()
	Measure()
	Soft(false)
	local real = Read()
	if not real then
		Say("nothing under the mouse. Hover a blip on the minimap, then type /mm probe here (Enter keeps the mouse where it is).")
		return
	end
	Say("under the real mouse: %s", table.concat(real, ", "))
	Say("its TooltipData: %s", Dump(C_TooltipInfo.GetMinimapMouseover(), 4))
	local cx, cy = GetCursorPosition()
	local ui = UIParent:GetEffectiveScale()
	local ways = {
		{ "GetCursorPosition as is", cx, cy },
		{ "divided by UIParent's scale", cx / ui, cy / ui },
		{ "divided by the Minimap's scale", cx / g.scale, cy / g.scale },
		{ "relative to the Minimap", cx - g.left * g.scale, cy - g.bottom * g.scale },
	}
	Soft(true)
	for _, w in ipairs(ways) do
		Minimap:UpdateMouseoverAtPoint(w[2], w[3])
		local got = Read()
		Say("pretend mouse, %s (%.1f, %.1f): %s", w[1], w[2], w[3], got and table.concat(got, ", ") or "nothing")
	end
	Soft(false)
	Wait(1)
	local back = Read()
	Say("soft cursor off again, next frame: %s", back and table.concat(back, ", ") or "nothing")
end

-- Each a change to the Minimap; the test scans after each and compares
-- with the plain Minimap.
local CONDITIONS = {
	{ "Minimap alpha 0", function() Minimap:SetAlpha(0) end },
	{ "MinimapCluster alpha 0", function() MinimapCluster:SetAlpha(0) end },
	{ "ground textures off", function() C_Minimap.SetDrawGroundTextures(false) end },
	{ "square mask", function()
		job.snap.masked = true
		Minimap:SetMaskTexture(SQUARE_MASK)
	end },
	{ "icon scale 0.5", function() IconScale(0.5) end },
	{ "icon scale 2", function() IconScale(2) end },
	{ "twice the size", function() Place(Minimap:GetWidth() * 2) end },
	{ "half the size", function() Place(Minimap:GetWidth() / 2) end },
	{ "zoom widest", function() Minimap:SetZoom(0) end, wait = 10 },
	{ "zoom closest", function() Minimap:SetZoom(Minimap:GetZoomLevels() - 1) end, wait = 10 },
	{ "half off the screen's left edge", function()
		local _, y = Minimap:GetCenter()
		Place(nil, 0, y)
	end, halves = true },
	{ "all off screen", function()
		local _, y = Minimap:GetCenter()
		Place(nil, -2 * Minimap:GetWidth(), y)
	end },
	{ "hidden", function() Minimap:Hide() end },
	{ "MinimapCluster hidden", function() MinimapCluster:Hide() end },
	{ "a sensor: on UIParent, 64 units, alpha 0, no ground", function()
		local x, y = Minimap:GetCenter()
		local s = Minimap:GetEffectiveScale()
		Minimap:SetParent(UIParent)
		local k = s / Minimap:GetEffectiveScale()
		Place(64, x * k, y * k)
		Minimap:SetAlpha(0)
		C_Minimap.SetDrawGroundTextures(false)
	end },
}

function tests.sense()
	Geometry()
	local base = Baseline(4)
	if not base then return end
	local ref = RefineAll(base.blips)
	Say("plain: %d blips (%d probes); answers from outside its square: %d", #ref, base.probes, base.outside)
	local margin = Scan(6, Minimap:GetWidth() / 2)
	Say("plain, probed half its width past every edge: %d of %d answering points lay outside it", margin.outside, margin.probes)
	local radius = g.radius
	for _, c in ipairs(CONDITIONS) do
		c[2]()
		Wait(c.wait or 3)
		local ok = Measure()
		if not ok then
			Say("%s: no rect or radius to probe", c[1])
		else
			local res = Scan(4)
			local r = g.radius
			local exact = RefineAll(res.blips, { passes = 1, stepOut = 1, halvings = 8 })
			local m = Match(ref, exact, 15, function(b) return b.yards < r * 0.95 end)
			local corners = 0
			for _, b in ipairs(exact) do
				if b.yards > r then corners = corners + 1 end
			end
			Say("%s: %d of %d found (within its %s yd radius), %d new or merged, gap mean %s worst %s yd; %d past the round edge",
				c[1], m.found, m.total, Yd(r), m.extra, Yd(m.mean), Yd(m.worst), corners)
			if c.halves then
				local on = 0
				for _, b in ipairs(exact) do
					if (g.left + b.x) > 0 then on = on + 1 end
				end
				Say("  of those, %d on screen, %d off it", on, #exact - on)
			end
		end
		Reset()
	end
	Measure()
	Say("radius back to %s yd (was %s)", Yd(g.radius), Yd(radius))
end

-- The blip to study: the one named, else the nearest with no other of its
-- name close by.
local function Subject(blips, name)
	for _, b in ipairs(blips) do
		local alone = true
		for _, o in ipairs(blips) do
			if o ~= b and o.name == b.name and Gap(o, b) < 30 then alone = false end
		end
		if (name and b.name:lower() == name) or (not name and alone) then return b end
	end
end

-- Where a known blip is now, found again near where the world says it is.
local function Refind(b, o)
	Measure()
	Soft(true)
	local x, y = FromWorld(b.north, b.west)
	if not Has(At(x, y), b.name) then
		local best
		for dx = -20, 20, 2 do
			for dy = -20, 20, 2 do
				if Has(At(x + dx, y + dy), b.name) and (not best or dx * dx + dy * dy < best[3]) then
					best = { x + dx, y + dy, dx * dx + dy * dy }
				end
			end
		end
		if not best then return nil end
		x, y = best[1], best[2]
	end
	local rx, ry, axis, diag = Refine(b.name, x, y, o)
	if not rx then return nil end
	local r = NewBlip(b.name, rx, ry)
	r.axis, r.diag = axis, diag
	return r
end

function tests.shape(name)
	Geometry()
	local base = Baseline(4)
	if not base then return end
	local subject = Subject(RefineAll(base.blips), name)
	if not subject then
		Say("no blip by itself to study%s", name and (" named " .. name) or "")
		return
	end
	local w0 = g.w
	Say("studying %s, %s yd away", subject.name, Yd(subject.yards))
	local o = { passes = 2, stepOut = 0.5, halvings = 10, diagonals = true }
	local here = Refind(subject, o)
	if not here then
		Say("lost it")
		return
	end
	Say("at %d units: reach %s along the axes, %s on the diagonals (%.2f: 1.41 square, 1.00 round), %.3f of the width",
		w0, Yd(here.axis), Yd(here.diag), (here.diag or 0) / here.axis, here.axis / w0)
	-- Measured again: the same answer every time?
	local spread = 0
	for _ = 1, 3 do
		Wait(1)
		local again = Refind(subject, o)
		if again then spread = math.max(spread, Gap(again, here)) end
	end
	Say("measured 3 more times: within %s yd of the first", Yd(spread))
	-- At other sizes and icon scales.
	local configs = {
		{ "40 units", function() Place(40) end },
		{ "64 units", function() Place(64) end },
		{ "96 units", function() Place(96) end },
		{ "200 units", function() Place(200) end },
		{ "300 units", function() Place(300) end },
		{ "icon scale 0.5", function() IconScale(0.5) end },
		{ "icon scale 2", function() IconScale(2) end },
	}
	for _, c in ipairs(configs) do
		c[2]()
		Wait(3)
		local r = Refind(subject, o)
		if r then
			Say("%s: reach %s units (%.3f of the width, %s yd), middle %s yd from the first",
				c[1], Yd(r.axis), r.axis / g.w, Yd(r.axis * g.radius / (g.w / 2)), Yd(Gap(r, here)))
		else
			Say("%s: not found", c[1])
		end
		Reset()
	end
	-- Moved by a fraction of a pixel: does the middle move with it (no
	-- snapping to pixels), so the yards stay put?
	local worst = 0
	local x0, y0 = Minimap:GetCenter()
	for _, f in ipairs({ 0.125, 0.25, 0.375, 0.5, 0.625, 0.75 }) do
		Place(nil, x0 + f, y0 + f)
		Wait(2)
		local r = Refind(subject, o)
		if r then worst = math.max(worst, Gap(r, here)) end
		Reset()
	end
	Say("moved by fractions of a unit: middle within %s yd (one unit is %s yd)", Yd(worst), Yd(g.radius / (g.w / 2)))
end

-- Microseconds per call of fn, n times.
local function Bench(label, n, fn)
	local t = debugprofilestop()
	for i = 1, n do fn(i) end
	local us = (debugprofilestop() - t) * 1000 / n
	Say("%s: %.2f us", label, us)
	return us
end

-- A spot inside the Minimap where nothing answers.
local function EmptySpot()
	Measure()
	Soft(true)
	for i = 1, 20 do
		for j = 1, 20 do
			local x, y = i * g.w / 21, j * g.h / 21
			if not At(x, y) then return x, y end
		end
	end
end

-- The usual mix: points spread over the Minimap, n probes, us each.
local function Spread(label, n)
	Measure()
	Soft(true)
	local side = math.floor(math.sqrt(n))
	return Bench(label, side * side, function(i)
		At((i % side + 0.5) * g.w / side, (math.floor(i / side) + 0.5) * g.h / side)
	end)
end

function tests.cost()
	Geometry()
	local base = Baseline(6)
	if not base then return end
	local b = base.blips[1]
	local N = 500
	local ex, ey = EmptySpot()
	Measure()
	Soft(true)
	local sx, sy = (g.left + (ex or 0)) * g.scale, (g.bottom + (ey or 0)) * g.scale
	local bx, by = (g.left + b.x) * g.scale, (g.bottom + b.y) * g.scale
	Bench("UpdateMouseoverAtPoint, empty spot", N, function() Minimap:UpdateMouseoverAtPoint(sx, sy) end)
	Bench("UpdateMouseoverAtPoint, alternating two spots", N, function(i)
		if i % 2 == 0 then Minimap:UpdateMouseoverAtPoint(sx, sy) else Minimap:UpdateMouseoverAtPoint(bx, by) end
	end)
	Minimap:UpdateMouseoverAtPoint(sx, sy)
	Bench("GetMinimapMouseover, empty", N, function() C_TooltipInfo.GetMinimapMouseover() end)
	Minimap:UpdateMouseoverAtPoint(bx, by)
	Bench("GetMinimapMouseover, on a blip", N, function() C_TooltipInfo.GetMinimapMouseover() end)
	Bench("Read (and parse), on a blip", N, function() Read() end)
	Bench("move + read, empty", N, function()
		Minimap:UpdateMouseoverAtPoint(sx, sy)
		C_TooltipInfo.GetMinimapMouseover()
	end)
	Bench("move + read, on a blip", N, function()
		Minimap:UpdateMouseoverAtPoint(bx, by)
		C_TooltipInfo.GetMinimapMouseover()
	end)
	Bench("GameTooltip:SetMinimapMouseover, on a blip", 100, function() TipNames() end)
	Soft(false)
	Bench("SetUsingSoftCursor on + off", N, function()
		Minimap:SetUsingSoftCursor(true)
		Minimap:SetUsingSoftCursor(false)
	end)
	Wait(1)
	Say("blips around: %d", #base.blips)
	Spread("spread over it, as it is", 400)
	for _, c in ipairs({
		{ "64 units", function() Place(64) end },
		{ "400 units", function() Place(400) end },
		{ "zoom widest", function() Minimap:SetZoom(0) end, 10 },
		{ "zoom closest", function() Minimap:SetZoom(Minimap:GetZoomLevels() - 1) end, 10 },
		{ "alpha 0, no ground", function()
			Minimap:SetAlpha(0)
			C_Minimap.SetDrawGroundTextures(false)
		end },
	}) do
		c[2]()
		Wait(c[3] or 3)
		Spread("spread over it, " .. c[1], 400)
		Reset()
	end
end

-- Ways to find every blip, each against a slow, exact reference.
local STRATEGIES = {
	{ "grid 8, middles (NodeSight's first pass)", step = 8 },
	{ "grid 8 + edges", step = 8, refine = true },
	{ "grid 12 + edges", step = 12, refine = true },
	{ "grid 16 + edges", step = 16, refine = true },
	{ "64 units, grid 6 + edges", size = 64, step = 6, refine = true },
	{ "64 units, grid 10 + edges", size = 64, step = 10, refine = true },
	{ "40 units, grid 8 + edges", size = 40, step = 8, refine = true },
}
local QUICK = { passes = 1, stepOut = 2, halvings = 5 }

function tests.race()
	Geometry()
	local base = Baseline(3)
	if not base then return end
	local ref = RefineAll(base.blips, { passes = 2, stepOut = 0.5, halvings = 10 })
	Say("reference: %d blips (grid 3 + exact edges)", #ref)
	for _, s in ipairs(STRATEGIES) do
		if s.size then Place(s.size) end
		Wait(3)
		probes = 0
		local t = debugprofilestop()
		local res = Scan(s.step, 0, 100000) -- (in one go: its time is its cost)
		local got = res.blips
		if s.refine then
			got = {}
			Measure()
			Soft(true)
			for _, b in ipairs(res.blips) do
				local x, y = Refine(b.name, b.x, b.y, QUICK)
				if x then got[#got + 1] = NewBlip(b.name, x, y) end
			end
			Soft(false)
		end
		local ms = debugprofilestop() - t
		local r = g.radius
		local m = Match(ref, got, 15, function(b) return b.yards < r end)
		Say("%s: %d probes, %.2f ms; found %d of %d, %d extra; error mean %s, worst %s yd",
			s[1], probes, ms, m.found, m.total, m.extra, Yd(m.mean), Yd(m.worst))
		Reset()
	end
end

function tests.drift()
	Geometry()
	Say("20 seconds: walk around among the blips")
	local tracks = {}
	local stop = GetTime() + 20
	local scans = 0
	while GetTime() < stop do
		local res = Scan(8)
		Measure()
		Soft(true)
		for _, b in ipairs(res.blips) do
			local x, y = Refine(b.name, b.x, b.y, QUICK)
			if x then
				local p = NewBlip(b.name, x, y)
				local best, gap
				for _, t in ipairs(tracks) do
					if t.name == p.name then
						local d = Gap(t[1], p)
						if d < 10 and (not gap or d < gap) then best, gap = t, d end
					end
				end
				if not best then
					best = { name = p.name }
					tracks[#tracks + 1] = best
				end
				best[#best + 1] = p
			end
		end
		scans = scans + 1
		Wait(30)
	end
	local list = {}
	for _, t in ipairs(tracks) do
		if #t >= 3 then
			local sn, sw = 0, 0
			for _, p in ipairs(t) do sn, sw = sn + p.north, sw + p.west end
			local mid = { north = sn / #t, west = sw / #t }
			local sq, worst = 0, 0
			for _, p in ipairs(t) do
				local d = Gap(p, mid)
				sq, worst = sq + d * d, math.max(worst, d)
			end
			list[#list + 1] = { t.name, #t, math.sqrt(sq / #t), worst }
		end
	end
	table.sort(list, function(a, b) return a[3] < b[3] end)
	Say("%d scans, %d blips seen 3+ times", scans, #list)
	for _, e in ipairs(list) do Say("  %s: %d sightings, spread %s yd (worst %s)", e[1], e[2], Yd(e[3]), Yd(e[4])) end
	if not g.north then Say("(your position is withheld here, so moving makes these meaningless)") end
end

function tests.truth()
	Geometry()
	local units = {}
	for i = 1, 4 do units[#units + 1] = "party" .. i end
	for i = 1, 40 do units[#units + 1] = "raid" .. i end
	local res = Scan(4)
	local exact = RefineAll(res.blips)
	local n = 0
	for _, unit in ipairs(units) do
		local north, west = UnitPosition(unit)
		local name = UnitExists(unit) and UnitName(unit)
		if north and name and not issecretvalue(north) and not issecretvalue(name) and not UnitIsUnit(unit, "player") then
			n = n + 1
			local best
			for _, b in ipairs(exact) do
				if b.name == name then
					local d = Gap(b, { north = north, west = west })
					if not best or d < best then best = d end
				end
			end
			Say("%s: %s", name, best and (Yd(best) .. " yd from where the game says") or "no blip found")
		end
	end
	if n == 0 then Say("no party members with a position: group up with someone in sight and try again") end
end

tests.all = function()
	for _, name in ipairs({ "basic", "sense", "shape", "cost", "race" }) do
		job.section = name
		tests[name]()
		Reset()
	end
	job.section = nil
end

---------------------------------------------------------------------------
-- Running them, a little each frame
---------------------------------------------------------------------------

local runner = CreateFrame("Frame")
runner:Hide()

local function Finish(err)
	local j = job
	if err then Say("stopped: %s", err) end
	pcall(Restore, j.snap)
	Soft(false)
	if j.reopen then ns.frame:Show() end
	db.probe = db.probe or {}
	db.probe[j.name] = { at = date("%Y-%m-%d %H:%M:%S"), lines = j.lines }
	ns.Print(string.format("probe %s: done (%d lines kept in MagicMapDB.probe; /reload to write them out)", j.name, #j.lines))
	job = nil
	runner:Hide()
end

runner:SetScript("OnUpdate", function()
	if job.wait > 0 then
		job.wait = job.wait - 1
		return
	end
	local ok, frames = coroutine.resume(job.co)
	if not ok then
		Finish(tostring(frames))
	elseif coroutine.status(job.co) == "dead" then
		Finish()
	else
		job.wait = (frames or 1) - 1
	end
end)
runner:RegisterEvent("PLAYER_REGEN_DISABLED")
runner:SetScript("OnEvent", function()
	if job then Finish("combat") end
end)

ns.slash.probe = function(arg)
	local name, rest = strsplit(" ", arg or "", 2)
	if name == "stop" then
		if job then Finish("stopped by you") end
		return
	end
	if not tests[name] then
		ns.Print("/mm probe basic | here | sense | shape [name] | cost | race | drift | truth | all | stop")
		return
	end
	if job then return ns.Print("probe: " .. job.name .. " is running (/mm probe stop)") end
	if InCombatLockdown() then return ns.Print("probe: not in combat") end
	secrets, probes = 0, 0
	job = { name = name, lines = { "MagicMap probe " .. name .. ", " .. date("%Y-%m-%d %H:%M:%S") }, wait = 0, data = {} }
	job.co = coroutine.create(function()
		if name ~= "here" then
			if ns.frame:IsShown() then
				job.reopen = true
				ns.frame:Hide()
			end
			Wait(3)
		end
		job.snap = Snapshot()
		if name ~= "here" then
			C_Minimap.SetIgnoreRotateMinimap(true)
			Wait(3)
		end
		tests[name](rest)
	end)
	runner:Show()
end

ns.ProbeJob = function() return job end
ns.On("Loaded", function(savedDB) db = savedDB end)
