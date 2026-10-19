-- The blip sensor (the spike's Blips.lua, its sensing half): Blizzard's Minimap,
-- placed by the apply step (game/Minimap.lua) as an unseen square under our
-- window, answers a pretend mouse (Minimap:SetUsingSoftCursor) with the names of
-- the blips under it, whether or not it's drawn. Each blip answers inside a
-- square `px` screen units each way from its middle (measured in game: SQUARE;
-- refined as lone squares are measured).
--
-- Every probe makes ~0.35 KB of the client's garbage, answer or not (and costs ~2 us:
-- docs/evidence/perf-m0.md), so it probes little: a look every REST s, at points of a
-- lattice fixed in the world, a little under a square's width apart (no blip fits between
-- them), within the Minimap's reach:
--   new       the points that came into reach since the last look (after a restart, all);
--   standing  those looked at while you moved since you last stood (the client's blips lag
--             you as you move), the slow pass's next (STALE a look, all of them in ~40 s: what
--             spawns), and known blips no point named, where they are (every rough one, CONFIRM
--             measured ones in turn): still there, measured, found around it (moved a little), or gone.
-- So ~6 probes a second walking, at most STALE + CONFIRM (16) standing, and ~50 a blip measured:
-- R-P3's 0.1 KB a frame (~17 a second), not only the 50 KB/s budget (~140).
-- A frame probes until BUDGET ms are spent and the look (a coroutine) goes on the next.
-- A point naming something no known blip explains (as often as the answer names it: one a
-- blip) gets that blip's middle from its square's edges, halved in on, standing still (a
-- measure spans frames: it counts only if you haven't moved, and a lone square's middle
-- answers too); while you move the point stands for it (rough) until you stop. A look
-- standing throughout is a sweep (what Model forgets by).
--
-- It reads only where the last Apply placed the Minimap, while that placement
-- holds still (Game.minimap.still) and the Minimap is there: shown, north up, at
-- its place, its view radius as last frame (indoors at a door it changes: a measure
-- across it read a square of nothing and refined ours below the client's, session #5's
-- `sensor` events); otherwise the look starts over (a measure in progress with it),
-- the next looks at every point, and what it knew is kept, as in combat. Unable to
-- read for BLIND s (something fights Apply) it traces "sensor" { e = "blind", why };
-- the refined square straying past DRIFT of SQUARE traces { e = "square", px }, and
-- one blip read as four (a square too big to read as lone: refining can't grow ours)
-- makes ours its size and the four one, traced { e = "square", px, n = 4 } (docs/telemetry.md).
-- Game.Blips() runs one slice and returns obs.blips (types/observation.lua
-- MM.ObsBlips), or nil while it doesn't run: the blips part (game/parts/Blips.lua).
-- Each sweep traces "blips" (docs/telemetry.md: counted in session stats). You and your group
-- aren't sensed (their own dots: the spike's Blips.lua:449-458, 653-657): not measured as they move.

local _, ns = ...
local Atlas, Game, Runtime = ns.Atlas, ns.Game, ns.Runtime

local SQUARE = 8.0   -- screen units a blip answers each way from its middle (7.84 Minimap units at scale 1.02)
local DRIFT = 0.25   -- of SQUARE: a measured square further off is traced
local GRID = 0.85    -- lattice spacing, of a square's width: no blip fits between its points, nor slips by lagging a little
local CORNER = 1.42 / 2 / GRID -- a square's corner from its middle, of the spacing
local BUDGET = 0.5   -- ms of probing a frame: a look spans frames when it must, the rest well under p95 1 ms
local HALVINGS = 8
local REST = 1       -- s between looks
local STALE = 8      -- points of the slow pass a look standing (all of them in ~40 s)
local CONFIRM = 8    -- measured blips looked at where they are a look standing, in turn (a gathered herb goes)
local SETTLE = 0.5   -- s still before measuring (the client moves blips in steps as you walk)
local BLIND = 1      -- s unable to read before it's traced
local YD = 1 / Atlas.TILE_YARDS
local SAME, LAG = 6 * YD, 8 * YD -- a measure this close to a known one of its name is that one; the client's lag moving

local blips = {}     -- { name, pos = { inst, col, row }, rough, icon, seen, gone }
local center = {}
local out = { list = blips, sweep = 0, reach = 0 } -- obs.blips (its center refilled each sweep)
local lat = {}       -- the lattice: s (tiles apart), R (radius looked over), made for px, r; the last look's
                     -- circle cc, cr, its radius cR, and the last standing one's sc, sr, sR (nil: none since a restart)
local px, drifted = SQUARE, false
local look, busy, rest, frames, probes, stale = 0, false, 0, 0, 0, 0 -- look: the last look's id (a blip's seen); busy: one in progress
local co, t0         -- the looks (a coroutine: it yields once the frame's budget is spent); this slice's start
local measuring      -- movedAt when a measure began: it counts only if you haven't moved since
local blindAt, blindSaid
local g = { movedAt = -SETTLE } -- this frame: left, bottom, scale, w, h, half, r, u (tiles a Minimap unit), inst, col, row, moving
local NONE = {}
Game.blipsRev = 0    -- goes up with every change to what the sensor knows (the recorder's cue)

local function Changed() Game.blipsRev = Game.blipsRev + 1 end
local function R2(v) return math.floor(v * 100 + 0.5) / 100 end
local function Remove(i) blips[i].gone = true; table.remove(blips, i); Changed() end

-- What tracking icon a blip's name is: a tracking type of that name (Mailbox), or a
-- service Atlas knows the name by (Data.BlipServices; a class trainer by its title: Blips.lua:375-403);
-- a gathering node's, an atlas (Blips.lua:423-426). nil, nil: none (a gold dot).
local SERVICE = { innkeeper = 136458, banker = 136453, auctioneer = 136452, stablemaster = 136466,
	battlemaster = 136454, trainer = 136463, classtrainer = 136455, repair = 136465, mailbox = 136459 }
local GATHER = { herb = "Professions_Tracking_Herb", ore = "Professions_Tracking_Ore" }
local icons, atlases = {}, {}
local function Icon(name)
	local icon = icons[name]
	if icon == nil then
		for i = 1, C_Minimap.GetNumTrackingTypes() or 0 do
			local info = C_Minimap.GetTrackingInfo(i)
			if info and info.name == name then icon = info.texture end
		end
		local service = Atlas.BlipService(name)
		icon = icon or SERVICE[service] or false
		icons[name], atlases[name] = icon, GATHER[service] or false
	end
	return icon or nil, atlases[name] or nil
end

-- Names not sensed: you and your group, each look.
local skip = {}
local function Skip()
	wipe(skip)
	local me = UnitName("player")
	if me then skip[me] = true end
	local unit = IsInRaid() and "raid" or "party"
	for i = 1, GetNumGroupMembers() do
		local n = UnitName(unit .. i)
		if n and not issecretvalue(n) then skip[n] = true end
	end
end

-- Probing ----------------------------------------------------------------------

-- A tooltip line's names (one a row, markup stripped), each text parsed once: the same few come back.
local parsed, nParsed = {}, 0
local function Names(text)
	local list = parsed[text]
	if list then return list end
	list = {}
	for part in text:gmatch("[^\n]+") do
		part = strtrim((part:gsub("|A.-|a", ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
		if part ~= "" then list[#list + 1] = part end
	end
	if nParsed >= 200 then wipe(parsed); nParsed = 0 end
	parsed[text], nParsed = list, nParsed + 1
	return list
end

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
	for _, line in ipairs(data.lines or NONE) do
		local text = line.leftText
		if text and not issecretvalue(text) then
			for _, n in ipairs(Names(text)) do names[#names + 1] = n end
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

-- A lone square's size, measured: ours refined toward it.
local function Square(measured)
	px = px + (measured - px) / 4
	g.half = px / g.scale -- /: never 0 (an effective scale is > 0)
	local off = math.abs(px - SQUARE) > DRIFT * SQUARE
	if off and not drifted then Runtime.Trace("sensor", { e = "square", px = R2(px) }) end
	drifted = off
end

-- One blip read as four: the client's square is bigger than ours (one reads as lone only
-- up to 1.15 ours, so refining can't grow it): ours becomes its size.
local function Adopt(measured)
	px, drifted = measured, math.abs(measured - SQUARE) > DRIFT * SQUARE
	g.half = px / g.scale -- /: never 0 (an effective scale is > 0)
	Runtime.Trace("sensor", { e = "square", px = R2(px), n = 4 })
end

-- The middles of the blips named `name` whose squares hold (x, y); with overlaps,
-- only candidates whose four corners all answer (the rest are ghosts). NONE if you moved
-- meanwhile, or a lone square's middle doesn't answer (it went, or the client moved it).
local function Locate(name, x, y)
	local r, l = Edge(name, x, y, 1, 0), Edge(name, x, y, -1, 0)
	local t, b = Edge(name, x, y, 0, 1), Edge(name, x, y, 0, -1)
	if measuring ~= g.movedAt or not (r and l and t and b) then return NONE end
	local half, wide, tall = g.half, l + r, t + b
	local square = math.abs(wide - tall) < 0.1 * half
	local xs, ys, found = Middles(x - l, x + r), Middles(y - b, y + t), {}
	if #xs * #ys == 1 then
		if not Answers(xs[1], ys[1], name) then return NONE end
		if square then Square((wide + tall) / 4 * g.scale) end
		found[1] = { xs[1], ys[1] }
	else
		local e = 0.75 * half
		for _, mx in ipairs(xs) do
			for _, my in ipairs(ys) do
				if Answers(mx - e, my - e, name) and Answers(mx + e, my - e, name)
					and Answers(mx - e, my + e, name) and Answers(mx + e, my + e, name) then
					found[#found + 1] = { mx, my }
				end
			end
		end
	end
	if measuring ~= g.movedAt then return NONE end
	-- Four in a square span: likelier one square bigger than ours than four blips.
	if #found == 4 and square then
		Adopt((wide + tall) / 4 * g.scale)
		return { { x + (r - l) / 2, y + (t - b) / 2 } }
	end
	return found
end

-- Minimap units <-> tile space (north up, you in the middle) ---------------------

local function Local(col, row)
	return g.w / 2 + (col - g.col) / g.u, g.h / 2 - (row - g.row) / g.u -- /: never 0 (g.u > 0 while looking)
end

local function Tile(x, y) return g.col + (x - g.w / 2) * g.u, g.row - (y - g.h / 2) * g.u end

-- Looking ----------------------------------------------------------------------------

-- Whether known blip b of `name` has a square holding (x, y). A rough one stands where a
-- point hit it, up to a square off its middle.
local function Holds(b, name, x, y)
	if b.name ~= name or b.pos.inst ~= g.inst then return false end
	local bx, by = Local(b.pos.col, b.pos.row)
	local lag = LAG / g.u -- /: never 0 (g.u > 0 while looking)
	local slack = b.rough and 2 * g.half + 0.5 + lag or g.half + 0.5 + (g.moving and lag or 0)
	return math.abs(x - bx) <= slack and math.abs(y - by) <= slack
end

-- Marks every known blip of `name` whose square holds (x, y) as seen; false if fewer
-- than k (the times the answer named it: one a blip) do, or standing still only rough ones
-- do (measure it). Still, a rough one where a measured one is was that one, seen on the move: it goes.
local function Explain(name, x, y, k)
	local exact, rough = 0, 0
	for _, b in ipairs(blips) do
		if Holds(b, name, x, y) then
			b.seen = look
			if b.rough then rough = rough + 1 else exact = exact + 1 end
		end
	end
	if exact > 0 and rough > 0 and not g.moving then
		for i = #blips, 1, -1 do
			if blips[i].rough and Holds(blips[i], name, x, y) then Remove(i) end
		end
	end
	return exact >= k or g.moving and exact + rough >= k
end

-- A middle measured standing still: rough ones of its name it explains go, and the one
-- there (within SAME) moves to it, else it's new.
local function Put(name, x, y)
	local col, row = Tile(x, y)
	local slack, hit = g.half + 0.5 + LAG / g.u, nil -- /: never 0 (g.u > 0 while looking)
	for i = #blips, 1, -1 do
		local b = blips[i]
		local p = b.pos
		if b.name == name and p.inst == g.inst then
			local bx, by = Local(p.col, p.row)
			if b.rough and math.abs(x - bx) <= slack and math.abs(y - by) <= slack then
				Remove(i)
			elseif not b.rough and (p.col - col) ^ 2 + (p.row - row) ^ 2 < SAME * SAME then
				hit = b
			end
		end
	end
	if hit then
		hit.seen, hit.pos.col, hit.pos.row = look, col, row
	else
		local icon, atlas = Icon(name)
		blips[#blips + 1] = { name = name, pos = { inst = g.inst, col = col, row = row }, rough = false,
			icon = icon, atlas = atlas, seen = look }
	end
	Changed()
end

-- Moving: the point that hit it stands for it until you stop.
local function Rough(name, x, y)
	local col, row = Tile(x, y)
	local icon, atlas = Icon(name)
	blips[#blips + 1] = { name = name, pos = { inst = g.inst, col = col, row = row }, rough = true,
		icon = icon, atlas = atlas, seen = look }
	Changed()
end

local found = {}
local function Visit(x, y)
	local here = At(x, y)
	if #here == 0 then return end
	wipe(found)
	for i, n in ipairs(here) do found[i] = n end
	for i, name in ipairs(found) do
		local k, first = 0, true
		for j, n in ipairs(found) do
			if n == name then k, first = k + 1, first and j >= i end
		end
		if first and not skip[name] and not Explain(name, x, y, k) then
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

-- The lattice: points s tiles apart, fixed in the world (one looked at stays looked at as
-- you move), within R of you; made anew when our square or the view radius changes (s in
-- tiles doesn't change with the UI scale: px and r only). Our square changed, every point is
-- looked at again. The radius changed (a door), the circles looked over stand: a look found
-- every blip in reach then, on its own lattice, so only the ring past them is new (out of a door);
-- in at one, they shrink to the new reach (Beyond forgets what's past it), and nothing is (each
-- door in a city was a whole look, ~300 probes: ~100 KB of the client's garbage).
local function Lattice()
	local same = lat.px and math.abs(px - lat.px) <= 0.05 * lat.px
	if lat.r == g.r and same then return end
	if not same and lat.cc then Runtime.Trace("restart", { why = "square", probes = probes }) end
	if not same then lat.cc, lat.sc = nil, nil end
	lat.s, lat.px, lat.r = GRID * 2 * g.half * g.u, px, g.r
	lat.R = g.r * YD - CORNER * lat.s - LAG -- a point within it answers for any blip whose square holds it
	lat.cR, lat.sR = lat.cR and math.min(lat.cR, lat.R), lat.sR and math.min(lat.sR, lat.R)
end

-- The lattice's points to look at: the new ones (outside the last look's circle) and,
-- standing, those looked at moving (outside the last standing look's); then standing, the
-- slow pass's next, STALE a look with what the rest took.
local function Look(standing)
	local s, R, col, row = lat.s, lat.R, g.col, g.row
	local cc, cr, cR, sc, sr, sR = lat.cc, lat.cr, lat.cR, lat.sc, lat.sr, lat.sR
	local j0, j1 = math.ceil((row - R) / s), math.floor((row + R) / s) -- /: never 0 (s > 0: a square at a radius)
	local i0, i1 = math.ceil((col - R) / s), math.floor((col + R) / s) -- /: never 0 (s > 0: a square at a radius)
	local spent = 0
	for j = j0, j1 do
		for i = i0, i1 do
			local pc, pr = i * s, j * s
			if (pc - col) ^ 2 + (pr - row) ^ 2 <= R * R and (not cc or (pc - cc) ^ 2 + (pr - cr) ^ 2 > cR * cR
				or standing and (not sc or (pc - sc) ^ 2 + (pr - sr) ^ 2 > sR * sR)) then
				spent = spent + 1
				Visit(Local(pc, pr))
			end
		end
	end
	lat.cc, lat.cr, lat.cR = col, row, R
	if not standing or spent >= STALE then return end
	local n, from, to = 0, stale, stale + STALE - spent
	for j = j0, j1 do
		for i = i0, i1 do
			local pc, pr = i * s, j * s
			if (pc - col) ^ 2 + (pr - row) ^ 2 <= R * R then
				n = n + 1
				if n > from and n <= to then Visit(Local(pc, pr)) end
			end
		end
	end
	stale = to < n and to or 0
end

-- Out of reach or on another map: no look sees it.
local function Beyond()
	local R = g.r * YD + LAG
	for i = #blips, 1, -1 do
		local p = blips[i].pos
		if p.inst ~= g.inst or (p.col - g.col) ^ 2 + (p.row - g.row) ^ 2 > R * R then Remove(i) end
	end
end

local function Drop(b)
	for i = #blips, 1, -1 do
		if blips[i] == b then Remove(i); return end
	end
end

-- Standing: known blips no point named this look, looked at where they are (every rough one,
-- CONFIRM measured ones in turn): a measured one still there (its middle answers), a rough
-- one measured; else looked for around it (moved a little: found anew), or gone.
local NEAR = { -1, 0, 1, 0, 0, -1, 0, 1, -1, -1, 1, -1, -1, 1, 1, 1 } -- around a point, in squares' halves
local todo, turn = {}, 0
local function Confirm()
	wipe(todo)
	local n, exact = #blips, 0
	for k = 1, n do
		local b = blips[(turn + k) % n + 1]
		if b.seen ~= look and (b.rough or exact < CONFIRM) then
			todo[#todo + 1] = b
			exact = exact + (b.rough and 0 or 1)
		end
	end
	turn = turn + CONFIRM
	for _, b in ipairs(todo) do
		if g.moving then return end
		if not b.gone and b.seen ~= look then
			local x, y = Local(b.pos.col, b.pos.row)
			if not b.rough and Answers(x, y, b.name) then
				b.seen = look
			else
				if b.rough then Visit(x, y) else Drop(b) end
				for k = 1, #NEAR, 2 do
					if b.seen == look or b.gone and b.rough then break end
					Visit(x + NEAR[k] * g.half, y + NEAR[k + 1] * g.half)
				end
				if not b.gone and b.seen ~= look then Drop(b) end
			end
		end
	end
end

-- A look standing throughout done: a sweep.
local function EndSweep()
	out.sweep, out.reach = out.sweep + 1, lat.R - CORNER * lat.s - LAG
	center.inst, center.col, center.row = g.inst, g.col, g.row
	out.center = center
	lat.sc, lat.sr, lat.sR = lat.cc, lat.cr, lat.cR
	Changed()
	Runtime.Trace("blips", { sweep = out.sweep, blips = #blips, yd = math.floor(g.r + 0.5), frames = frames, probes = probes })
	frames, probes = 0, 0
end

local function Run()
	while true do
		busy, look = true, look + 1
		Skip()
		Lattice()
		local standing, movedAt = not g.moving, g.movedAt
		Look(standing)
		Beyond()
		if standing then Confirm() end
		if standing and movedAt == g.movedAt then EndSweep() end
		busy, rest = false, GetTime() + REST
		coroutine.yield()
	end
end

-- A look cut short starts over (a measure in progress with it), so none mixes two places
-- or placements; anew (the map, or what it could miss meanwhile changed: unable to read), the next
-- looks at every point. Only moved (a grow, a shrink) or a new radius (Lattice), the points mean the
-- same. One that drops a look or the circles looked over is traced "restart" { why, probes (the
-- look's so far) }: counted by why in the session's stats.
local function Restart(anew, why)
	if busy or anew and lat.cc then Runtime.Trace("restart", { why = why, probes = probes }) end
	if busy then busy, co, frames, probes = false, nil, 0, 0 end
	measuring = nil
	if anew then lat.cc, lat.sc = nil, nil end
end

-- Where the last Apply placed the Minimap (Game.minimap), and you.
local function Measure(m)
	local r = C_Minimap.GetViewRadius()
	local north, west = UnitPosition("player")
	local inst = select(8, GetInstanceInfo())
	if not (m.left and r and north) or issecretvalue(r) or issecretvalue(north) then return false end
	local col, row = Atlas.WorldToTile(north, west)
	local now = GetTime()
	if g.col and (col ~= g.col or row ~= g.row) then g.movedAt = now end
	if inst ~= g.inst then Restart(true, "map") elseif r ~= g.r then Restart(not g.r, "radius") end
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
		Restart(true, "off"); Watch(nil)
		return nil
	end
	local paused = InCombatLockdown() or not UIParent:IsVisible() -- (the UI hidden: Alt-Z)
	local blind = not paused and Blind(m)
	Watch(blind)
	if paused or blind then Restart(true, blind or InCombatLockdown() and "combat" or "alt-z"); return out end
	if not m.still or g.r == 0 then Restart(false, g.r == 0 and "zoom" or "moved"); return out end -- (radius 0: a new zoom applying, E3/E6)
	if not busy and GetTime() < rest then return out end
	t0, frames = debugprofilestop(), frames + 1
	co = co or coroutine.create(Run)
	Minimap:SetUsingSoftCursor(true)
	local ok, err = coroutine.resume(co)
	Minimap:SetUsingSoftCursor(false) -- (whatever happened: never left on)
	if not ok then Restart(true, "error"); co = nil; error(err, 0) end -- (a new look next time)
	return out
end

-- What the Minimap tracks changed (herbs on, say): every point looked at again.
Runtime.On("MINIMAP_UPDATE_TRACKING", "game.blips tracking", function()
	if lat.cc then Runtime.Trace("restart", { why = "tracking", probes = probes }) end
	lat.cc, lat.sc = nil, nil
end)

-- /mma blips (Blips.lua:677-683): what the sensor knows, each in yards east and north of you (Blips.lua:210-212).
Game.Slash("blips", "what the blip sensor knows, and where from you", function()
	local you, y = Game.obs.you, Atlas.TILE_YARDS
	Game.Say(("blips: %d known, answer square %.2f screen units each way"):format(#blips, px))
	for _, b in ipairs(blips) do
		Game.Say(("  %s %+.1fE %+.1fN%s"):format(b.name, (b.pos.col - you.col) * y, (you.row - b.pos.row) * y,
			b.rough and " (rough)" or ""))
	end
end)
