-- The blip sensor (ported from the spike's Blips.lua, the minimum): Blizzard's
-- Minimap, placed by the apply step (game/Minimap.lua) as an unseen square
-- under our window, answers a pretend mouse (Minimap:SetUsingSoftCursor) with
-- the names of the blips under it, whether or not it's drawn. Each blip answers
-- inside a square HALF_PX screen units each way from its middle (measured in
-- game: 7.84 Minimap units at scale 1.02), so a grid a little under a square's
-- width apart sweeps the Minimap, PER_FRAME points a frame. A point naming
-- something no known blip explains gets that blip's middle from its square's
-- edges, halved in on. One a whole sweep didn't name is gone.
--
-- It reads only where the last Apply placed the Minimap, and only while that
-- placement holds still (Game.minimap.still); otherwise the sweep starts over.
-- Game.Blips() runs one slice and returns obs.blips (types/observation.lua
-- MM.ObsBlips), or nil while it doesn't run: the blips part (game/parts/Blips.lua).
-- Each sweep that ends traces "blips" (docs/telemetry.md: counted in session stats).

local _, ns = ...
local Atlas, Game, Runtime = ns.Atlas, ns.Game, ns.Runtime

local HALF_PX = 8.0  -- screen units a blip answers each way from its middle
local GRID = 0.95    -- grid spacing, of a square's width: no blip fits between its points
local PER_FRAME = 24 -- grid points a frame
local MAX_LOCATES = 2 -- new blips measured a frame (about 40 probes each)
local HALVINGS = 8
local REST = 0.5     -- s between sweeps while you stand still
local SETTLE = 0.5   -- s still before a measure counts as exact (the client moves blips in steps as you walk)
local YD = 1 / Atlas.TILE_YARDS
local SAME, LAG = 6 * YD, 8 * YD -- a measure this close to a known one of its name is that one (moving: LAG)

local blips = {}     -- { name, pos = { inst, col, row }, rough, icon, seen }
local out = { list = blips, sweep = 0, reach = 0 } -- obs.blips
local grid, gridW, gridH = {}, nil, nil
local HALF, sweepId, at, rest = nil, 1, 1, nil
local g = {}         -- this frame: left, bottom, scale, w, h, u (tiles a Minimap unit), inst, col, row, moving
Game.blipsRev = 0    -- goes up with every change to what the sensor knows (the recorder's cue)

local function Changed() Game.blipsRev = Game.blipsRev + 1 end

-- What tracking icon a blip's name is: a tracking type of that name (Mailbox), or an
-- NPC Atlas knows with a service Blizzard tracks. nil: none (a gold dot).
local SERVICE = { innkeeper = 136458, banker = 136453, auctioneer = 136452, stablemaster = 136466,
	battlemaster = 136454, trainer = 136463, repair = 136465 }
local icons = {}
local function Icon(name)
	local icon = icons[name]
	if icon ~= nil then return icon or nil end
	for i = 1, C_Minimap.GetNumTrackingTypes() or 0 do
		local info = C_Minimap.GetTrackingInfo(i)
		if info and info.name == name then icon = info.texture end
	end
	local ok, ids = pcall(Atlas.NpcsByName, name) -- (no NPC data: none)
	local npc = not icon and ok and ids[1] and Atlas.Npc(ids[1])
	for _, s in ipairs(npc and npc.services or {}) do icon = icon or SERVICE[s] end
	icons[name] = icon or false
	return icon
end

-- Probing ----------------------------------------------------------------------

local names = {}
-- The names at (x, y), Minimap units from its bottom left: a reused list.
local function At(x, y)
	Minimap:UpdateMouseoverAtPoint((g.left + x) * g.scale, (g.bottom + y) * g.scale)
	wipe(names)
	local data = C_TooltipInfo.GetMinimapMouseover()
	if not data or issecretvalue(data) or issecretvalue(data.lines) then return names end
	for _, line in ipairs(data.lines or {}) do
		local text = line.leftText
		if text and not issecretvalue(text) then
			for part in text:gmatch("[^\n]+") do
				part = strtrim((part:gsub("|A.-|a", ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
				if part ~= "" then names[#names + 1] = part end
			end
		end
	end
	return names
end

local function Answers(x, y, name)
	for _, n in ipairs(At(x, y)) do
		if n == name then return true end
	end
	return false
end

-- From (x, y), where `name` answers, how far it keeps answering going (dx, dy).
local function Edge(name, x, y, dx, dy)
	local inside, outside = 0, nil
	for k = 1, 4 do
		local d = k * 2 * HALF
		if not Answers(x + dx * d, y + dy * d, name) then outside = d; break end
		inside = d
	end
	if not outside then return nil end
	for _ = 1, HALVINGS do
		local mid = (inside + outside) / 2
		if Answers(x + dx * mid, y + dy * mid, name) then inside = mid else outside = mid end
	end
	return (inside + outside) / 2
end

-- One square's middle, or where squares of a name overlap, the two at its ends.
local function Middles(lo, hi)
	if hi - lo <= 2.3 * HALF then return { (lo + hi) / 2 } end
	return { lo + HALF, hi - HALF }
end

-- The middles of the blips named `name` whose squares hold (x, y); with overlaps,
-- only candidates whose four corners all answer (the rest are ghosts).
local function Locate(name, x, y)
	local r, l = Edge(name, x, y, 1, 0), Edge(name, x, y, -1, 0)
	local t, b = Edge(name, x, y, 0, 1), Edge(name, x, y, 0, -1)
	if not (r and l and t and b) then return {} end
	local xs, ys, found = Middles(x - l, x + r), Middles(y - b, y + t), {}
	local check, e = #xs * #ys > 1, 0.75 * HALF
	for _, mx in ipairs(xs) do
		for _, my in ipairs(ys) do
			if not check or (Answers(mx - e, my - e, name) and Answers(mx + e, my - e, name)
				and Answers(mx - e, my + e, name) and Answers(mx + e, my + e, name)) then
				found[#found + 1] = { mx, my }
			end
		end
	end
	return found
end

-- Minimap units <-> tile space (north up, you in the middle) ---------------------

local function Local(pos)
	return g.w / 2 + (pos.col - g.col) / g.u, g.h / 2 - (pos.row - g.row) / g.u -- /: never 0 (g.u > 0 while sweeping)
end

-- Sweeping -------------------------------------------------------------------------

-- Marks every known blip of `name` whose square holds (x, y) as seen; false if none
-- does (or the one there was measured on the move and we're still now: measure it again).
local function Explain(name, x, y)
	local any = false
	for _, b in ipairs(blips) do
		if b.name == name and b.pos.inst == g.inst then
			local bx, by = Local(b.pos)
			local slack = HALF + 0.5 + (g.moving and LAG / g.u or 0) -- /: never 0 (g.u > 0 while sweeping)
			if math.abs(x - bx) <= slack and math.abs(y - by) <= slack then
				b.seen = sweepId
				any = any or not (b.rough and not g.moving)
			end
		end
	end
	return any
end

local function Add(name, x, y)
	local col, row = g.col + (x - g.w / 2) * g.u, g.row - (y - g.h / 2) * g.u
	for _, b in ipairs(blips) do
		local same = (g.moving or b.rough) and math.max(LAG, HALF * g.u) or SAME
		local p = b.pos
		if b.name == name and p.inst == g.inst and (p.col - col) ^ 2 + (p.row - row) ^ 2 < same * same then
			b.seen = sweepId
			if not g.moving or b.rough then p.col, p.row, b.rough = col, row, g.moving; Changed() end
			return
		end
	end
	blips[#blips + 1] = { name = name, pos = { inst = g.inst, col = col, row = row }, rough = g.moving,
		icon = Icon(name), seen = sweepId }
	Changed()
end

local locates, found = 0, {}
local function Visit(x, y)
	local here = At(x, y)
	if #here == 0 then return end
	wipe(found)
	for i, n in ipairs(here) do found[i] = n end
	for _, name in ipairs(found) do
		if not Explain(name, x, y) and locates < MAX_LOCATES then
			locates = locates + 1
			for _, m in ipairs(Locate(name, x, y)) do Add(name, m[1], m[2]) end
		end
	end
end

-- A whole sweep done: what none of its points named is gone.
local function EndSweep()
	for i = #blips, 1, -1 do
		if blips[i].seen ~= sweepId then table.remove(blips, i) end
	end
	sweepId = sweepId + 1
	local r = C_Minimap.GetViewRadius()
	out.sweep, out.reach = out.sweep + 1, r * YD
	out.center = { inst = g.inst, col = g.col, row = g.row }
	rest = { t = GetTime() + REST, col = g.col, row = g.row }
	Changed()
	Runtime.Trace("blips", { sweep = out.sweep, blips = #blips, yd = math.floor(r + 0.5) })
end

-- A sweep cut short starts over, so none mixes two places or placements.
local function Restart()
	if at ~= 1 then at, sweepId = 1, sweepId + 1 end
end

-- Where the last Apply placed the Minimap (Game.minimap), and you.
local function Measure(m)
	local r = C_Minimap.GetViewRadius()
	local north, west = UnitPosition("player")
	local inst = select(8, GetInstanceInfo())
	if not (m.left and r and north) or issecretvalue(r) or issecretvalue(north) then return false end
	local col, row = Atlas.WorldToTile(north, west)
	local now = GetTime()
	if col ~= g.col or row ~= g.row then g.movedAt = now end
	if inst ~= g.inst then Restart() end
	g.left, g.bottom, g.scale, g.w, g.h = m.left, m.bottom, m.scale, m.size, m.size
	g.u, g.inst, g.col, g.row = r * YD / (m.size / 2), inst, col, row -- /: never 0 (m.size: SENSOR_PX / a scale)
	g.moving = now - (g.movedAt or 0) < SETTLE
	return true
end

local function Sweep()
	for _ = 1, PER_FRAME do
		local p = grid[at]
		Visit(p[1], p[2])
		at = at + 1
		if at > #grid then at = 1; EndSweep(); return end
	end
end

-- One slice; obs.blips, or nil while the sensor can't run.
function Game.Blips()
	local m = Game.minimap
	if not (m.engaged and m.sensor) or InCombatLockdown() or not Measure(m) then
		Restart()
		return nil
	end
	if not m.still or g.u == 0 then Restart(); return out end -- radius 0: a new zoom still applying (E3/E6)
	HALF = HALF_PX / g.scale -- /: never 0 (an effective scale is > 0)
	if g.w ~= gridW or g.h ~= gridH then
		wipe(grid)
		local step = GRID * 2 * HALF
		for x = step / 2, g.w, step do
			for y = step / 2, g.h, step do grid[#grid + 1] = { x, y } end
		end
		gridW, gridH, at = g.w, g.h, 1
	end
	if at == 1 and rest and GetTime() < rest.t and g.col == rest.col and g.row == rest.row then return out end
	locates = 0
	Minimap:SetUsingSoftCursor(true)
	local ok, err = pcall(Sweep)
	Minimap:SetUsingSoftCursor(false) -- (whatever happened: never left on)
	if not ok then error(err, 0) end
	return out
end

