-- The blip sensor (the spike's Blips.lua, its sensing half): Blizzard's Minimap,
-- placed by the apply step (game/Minimap.lua) as an unseen square under our
-- window, answers a pretend mouse (Minimap:SetUsingSoftCursor) with the names of
-- the blips under it, whether or not it's drawn. Each blip answers inside a
-- square `px` screen units each way from its middle (measured in game: SQUARE;
-- refined as lone squares are measured), so a grid a little under a square's
-- width apart sweeps the Minimap. A probe costs the client ~0.1 ms, so a frame
-- probes until BUDGET ms are spent and the sweep (a coroutine) goes on the next.
-- A point naming something no known blip explains gets that blip's middle from
-- its square's edges, halved in on: measured only while you stand still (a
-- measure spans frames); while you move the point stands for it (rough) until
-- you stop. One a whole sweep didn't name is gone. A sweep starts REST after the
-- last one ended.
--
-- It reads only where the last Apply placed the Minimap, while that placement
-- holds still (Game.minimap.still) and the Minimap is there: shown, north up, at
-- its place; otherwise the sweep starts over (a measure in progress with it) and
-- what it knew is kept, as in combat. Unable to read for BLIND s (something
-- fights Apply) it traces "sensor" { e = "blind", why }; the refined square
-- straying past DRIFT of SQUARE traces { e = "square", px }, and one too big to
-- read as lone (a blip measured as four) { e = "square", px, n = 4 } (docs/telemetry.md).
-- Game.Blips() runs one slice and returns obs.blips (types/observation.lua
-- MM.ObsBlips), or nil while it doesn't run: the blips part (game/parts/Blips.lua).
-- Each sweep that ends traces "blips" (docs/telemetry.md: counted in session stats).

local _, ns = ...
local Atlas, Game, Runtime = ns.Atlas, ns.Game, ns.Runtime

local SQUARE = 8.0   -- screen units a blip answers each way from its middle (7.84 Minimap units at scale 1.02)
local DRIFT = 0.25   -- of SQUARE: a measured square further off is traced
local GRID = 0.95    -- grid spacing, of a square's width: no blip fits between its points
local BUDGET = 0.5   -- ms of probing a frame: a sweep spans many frames, so with the rest well under p95 1 ms
local HALVINGS = 8
local REST = 0.5     -- s between sweeps (each answer is a new table for the client to collect)
local SETTLE = 0.5   -- s still before measuring (the client moves blips in steps as you walk)
local BLIND = 1      -- s unable to read before it's traced
local YD = 1 / Atlas.TILE_YARDS
local SAME, LAG = 6 * YD, 8 * YD -- a measure this close to a known one of its name is that one; the client's lag moving

local blips = {}     -- { name, pos = { inst, col, row }, rough, icon, seen }
local center = {}
local out = { list = blips, sweep = 0, reach = 0 } -- obs.blips (its center refilled each sweep)
local grid, gridW, gridH, gridHalf = {}, nil, nil, nil -- x, y, x, y... (Minimap units)
local px, drifted = SQUARE, false
local sweepId, at, rest, frames, probes = 1, 0, 0, 0, 0 -- at: the point being visited, 0 between sweeps
local co, t0         -- the sweep (it yields once the frame's budget is spent); this slice's start
local measuring      -- movedAt when a measure began: it counts only if you haven't moved since
local blindAt, blindSaid
local g = { movedAt = 0 } -- this frame: left, bottom, scale, w, h, half, r, u (tiles a Minimap unit), inst, col, row, moving
Game.blipsRev = 0    -- goes up with every change to what the sensor knows (the recorder's cue)

local function Changed() Game.blipsRev = Game.blipsRev + 1 end
local function R2(v) return math.floor(v * 100 + 0.5) / 100 end

-- What tracking icon a blip's name is: a tracking type of that name (Mailbox), or a
-- service Atlas knows the name by (Data.BlipServices). nil: none (a gold dot).
local SERVICE = { innkeeper = 136458, banker = 136453, auctioneer = 136452, stablemaster = 136466,
	battlemaster = 136454, trainer = 136463, repair = 136465, mailbox = 136459 }
local icons = {}
local function Icon(name)
	local icon = icons[name]
	if icon ~= nil then return icon or nil end
	for i = 1, C_Minimap.GetNumTrackingTypes() or 0 do
		local info = C_Minimap.GetTrackingInfo(i)
		if info and info.name == name then icon = info.texture end
	end
	icon = icon or SERVICE[Atlas.BlipService(name)]
	icons[name] = icon or false
	return icon
end

-- Probing ----------------------------------------------------------------------

local names = {}
-- The names at (x, y), Minimap units from its bottom left: a reused list. Past the
-- frame's budget it waits for the next frame first; a measure you've moved during reads nothing.
local function At(x, y)
	if debugprofilestop() - t0 >= BUDGET then coroutine.yield() end
	wipe(names)
	if measuring and measuring ~= g.movedAt then return names end
	probes = probes + 1
	Minimap:UpdateMouseoverAtPoint((g.left + x) * g.scale, (g.bottom + y) * g.scale)
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
		local d = k * 2 * g.half
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
	if hi - lo <= 2.3 * g.half then return { (lo + hi) / 2 } end
	return { lo + g.half, hi - g.half }
end

-- A lone square's size, measured: the client's square refined toward it.
local function Square(measured)
	px = px + (measured - px) / 4
	local off = math.abs(px - SQUARE) > DRIFT * SQUARE
	if off and not drifted then Runtime.Trace("sensor", { e = "square", px = R2(px) }) end
	drifted = off
end

local NONE = {}
-- The middles of the blips named `name` whose squares hold (x, y); with overlaps,
-- only candidates whose four corners all answer (the rest are ghosts). NONE if you moved meanwhile.
local function Locate(name, x, y)
	local r, l = Edge(name, x, y, 1, 0), Edge(name, x, y, -1, 0)
	local t, b = Edge(name, x, y, 0, 1), Edge(name, x, y, 0, -1)
	if measuring ~= g.movedAt or not (r and l and t and b) then return NONE end
	local half, wide, tall = g.half, l + r, t + b
	if wide <= 2.3 * half and tall <= 2.3 * half and math.abs(wide - tall) < 0.1 * half then
		Square((wide + tall) / 4 * g.scale)
	end
	local xs, ys, found = Middles(x - l, x + r), Middles(y - b, y + t), {}
	local check, e = #xs * #ys > 1, 0.75 * half
	for _, mx in ipairs(xs) do
		for _, my in ipairs(ys) do
			if not check or (Answers(mx - e, my - e, name) and Answers(mx + e, my - e, name)
				and Answers(mx - e, my + e, name) and Answers(mx + e, my + e, name)) then
				found[#found + 1] = { mx, my }
			end
		end
	end
	if measuring ~= g.movedAt then return NONE end
	-- Four in a square span: likelier one square bigger than ours (too big to read as lone) than four blips.
	if #found == 4 and math.abs(wide - tall) < 0.1 * half then
		Runtime.Trace("sensor", { e = "square", px = R2((wide + tall) / 4 * g.scale), n = 4 })
	end
	return found
end

-- Minimap units <-> tile space (north up, you in the middle) ---------------------

local function Local(pos)
	return g.w / 2 + (pos.col - g.col) / g.u, g.h / 2 - (pos.row - g.row) / g.u -- /: never 0 (g.u > 0 while sweeping)
end

local function Tile(x, y) return g.col + (x - g.w / 2) * g.u, g.row - (y - g.h / 2) * g.u end

-- Sweeping -------------------------------------------------------------------------

-- Whether known blip b of `name` has a square holding (x, y). A rough one stands where a
-- point hit it, up to a square off its middle.
local function Holds(b, name, x, y)
	if b.name ~= name or b.pos.inst ~= g.inst then return false end
	local bx, by = Local(b.pos)
	local lag = LAG / g.u -- /: never 0 (g.u > 0 while sweeping)
	local slack = b.rough and 2 * g.half + 0.5 + lag or g.half + 0.5 + (g.moving and lag or 0)
	return math.abs(x - bx) <= slack and math.abs(y - by) <= slack
end

-- Marks every known blip of `name` whose square holds (x, y) as seen; false if none
-- does, or standing still only rough ones do (measure it). Still, a rough one where a
-- measured one is was that one, seen on the move: it goes.
local function Explain(name, x, y)
	local exact, rough = false, false
	for _, b in ipairs(blips) do
		if Holds(b, name, x, y) then
			b.seen = sweepId
			if b.rough then rough = true else exact = true end
		end
	end
	if exact and rough and not g.moving then
		for i = #blips, 1, -1 do
			if blips[i].rough and Holds(blips[i], name, x, y) then table.remove(blips, i); Changed() end
		end
	end
	return exact or rough and g.moving
end

-- A middle measured standing still: rough ones of its name it explains go, and the one
-- there (within SAME) moves to it, else it's new.
local function Put(name, x, y)
	local col, row = Tile(x, y)
	local slack, hit = g.half + 0.5 + LAG / g.u, nil -- /: never 0 (g.u > 0 while sweeping)
	for i = #blips, 1, -1 do
		local b = blips[i]
		local p = b.pos
		if b.name == name and p.inst == g.inst then
			local bx, by = Local(p)
			if b.rough and math.abs(x - bx) <= slack and math.abs(y - by) <= slack then
				table.remove(blips, i)
			elseif not b.rough and (p.col - col) ^ 2 + (p.row - row) ^ 2 < SAME * SAME then
				hit = b
			end
		end
	end
	if hit then
		hit.seen, hit.pos.col, hit.pos.row = sweepId, col, row
	else
		blips[#blips + 1] = { name = name, pos = { inst = g.inst, col = col, row = row }, rough = false,
			icon = Icon(name), seen = sweepId }
	end
	Changed()
end

-- Moving: the point that hit it stands for it until you stop.
local function Rough(name, x, y)
	local col, row = Tile(x, y)
	blips[#blips + 1] = { name = name, pos = { inst = g.inst, col = col, row = row }, rough = true,
		icon = Icon(name), seen = sweepId }
	Changed()
end

local found = {}
local function Visit(x, y)
	local here = At(x, y)
	if #here == 0 then return end
	wipe(found)
	for i, n in ipairs(here) do found[i] = n end
	for _, name in ipairs(found) do
		if not Explain(name, x, y) then
			if g.moving then
				Rough(name, x, y)
			else
				measuring = g.movedAt
				for _, m in ipairs(Locate(name, x, y)) do Put(name, m[1], m[2]) end
				measuring = nil
			end
		end
	end
end

-- A whole sweep done: what none of its points named is gone.
local function EndSweep()
	for i = #blips, 1, -1 do
		if blips[i].seen ~= sweepId then table.remove(blips, i) end
	end
	sweepId = sweepId + 1
	out.sweep, out.reach = out.sweep + 1, g.r * YD
	center.inst, center.col, center.row = g.inst, g.col, g.row
	out.center = center
	rest = GetTime() + REST
	Changed()
	Runtime.Trace("blips", { sweep = out.sweep, blips = #blips, yd = math.floor(g.r + 0.5), frames = frames, probes = probes })
	frames, probes = 0, 0
end

local function Grid()
	if g.w == gridW and g.h == gridH and math.abs(g.half - gridHalf) <= 0.05 * gridHalf then return end
	wipe(grid)
	local step = GRID * 2 * g.half
	for x = step / 2, g.w, step do
		for y = step / 2, g.h, step do grid[#grid + 1], grid[#grid + 2] = x, y end
	end
	gridW, gridH, gridHalf = g.w, g.h, g.half
end

local function Run()
	while true do
		Grid()
		for i = 1, #grid, 2 do
			at = i
			Visit(grid[i], grid[i + 1])
		end
		at = 0
		EndSweep()
		coroutine.yield()
	end
end

-- A sweep cut short starts over (a measure in progress with it), so none mixes two places or placements.
local function Restart()
	if at ~= 0 then at, sweepId, co, frames, probes = 0, sweepId + 1, nil, 0, 0 end
	measuring = nil
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
	g.left, g.bottom, g.scale, g.w, g.h, g.r = m.left, m.bottom, m.scale, m.size, m.size, r
	g.u, g.inst, g.col, g.row = r * YD / (m.size / 2), inst, col, row -- /: never 0 (m.size: SENSOR_PX / a scale)
	g.half = px / m.scale -- /: never 0 (an effective scale is > 0)
	g.moving = now - g.movedAt < SETTLE
	return true
end

-- Why the Minimap can't be read where Apply placed it (nil: it can). Apply puts each right
-- every frame (game/Minimap.lua), so only something fighting it lasts.
local function Blind(m)
	if not Minimap:IsVisible() then return "hidden" end
	if not C_Minimap.IsRotateMinimapIgnored() then return "rotated" end
	local l, b, w = Minimap:GetRect()
	if not l or Minimap:GetEffectiveScale() ~= m.scale or math.abs(l - m.left) >= 1 or math.abs(b - m.bottom) >= 1
		or math.abs(w - m.size) >= 1 then
		return "moved"
	end
end

local function Watch(why)
	if not why then blindAt, blindSaid = nil, false; return end
	blindAt = blindAt or GetTime()
	if not blindSaid and GetTime() - blindAt >= BLIND then
		blindSaid = true
		Runtime.Trace("sensor", { e = "blind", why = why })
	end
end

-- One slice; obs.blips, or nil while the sensor can't run.
function Game.Blips()
	local m = Game.minimap
	if not (m.engaged and m.sensor) or not Measure(m) then
		Restart(); Watch(nil)
		return nil
	end
	local paused = InCombatLockdown() or not UIParent:IsVisible() -- (the UI hidden: Alt-Z)
	local blind = not paused and Blind(m)
	Watch(blind)
	if paused or blind or not m.still or g.r == 0 then Restart(); return out end -- (radius 0: a new zoom applying, E3/E6)
	if at == 0 and GetTime() < rest then return out end
	t0, frames = debugprofilestop(), frames + 1
	co = co or coroutine.create(Run)
	Minimap:SetUsingSoftCursor(true)
	local ok, err = coroutine.resume(co)
	Minimap:SetUsingSoftCursor(false) -- (whatever happened: never left on)
	if not ok then Restart(); co = nil; error(err, 0) end -- (a new sweep next time)
	return out
end
