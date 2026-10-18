-- D3: each blip read as four, and blips duplicated while riding. A blip's answer square is
-- fixed in screen units, not Minimap units, and the client moves blips in steps as you
-- move, past the "same blip" radius. MOVED (measuring stays in Game's sensor): at a UI
-- scale other than 1 (so the two units differ), overlapping squares of one name read as
-- the blips they are, never their ghosts; riding through, no blip is ever known twice
-- (what's met on the move stands where a point hit it, rough, measured once you stop);
-- standing, every one is exact within 2 sweeps.
local T = ...
local sim, ns = T.Shown()
ns.Atlas.BlipService = function() return nil end -- (M1.2's accessor: none of these is a service)
UIParent:SetScale(0.64)
local A, p, Game = ns.Atlas, sim.player, ns.Game
local yd = 1 / A.TILE_YARDS
local c0, r0 = p.col, p.row
-- yd east, north of the start, out of reach of it: two Peacebloom whose squares overlap corner
-- to corner (four candidate middles, two of them ghosts), two Silverleaf side by side, a
-- mailbox, a vein.
local want = { { "Peacebloom", 320, 0 }, { "Peacebloom", 327, 7 }, { "Silverleaf", 350, 30 }, { "Silverleaf", 360, 30 },
	{ "Mailbox", 340, -40 }, { "Copper Vein", 300, 50 } }
local count, list = {}, {}
for i, b in ipairs(want) do
	local north, west = A.TileToWorld(c0 + b[2] * yd, r0 - b[3] * yd)
	list[i] = { b[1], north, west }
	count[b[1]] = (count[b[1]] or 0) + 1
end
sim.minimapBlips = list
local obs = Game.obs
local function Off(b, w) return math.sqrt(((b.pos.col - c0) / yd - w[2]) ^ 2 + ((r0 - b.pos.row) / yd - w[3]) ^ 2) end
local function Exact()
	if #obs.blips.list ~= #want then return false end
	for _, w in ipairs(want) do
		local n = 0
		for _, b in ipairs(obs.blips.list) do
			if b.name == w[1] and not b.rough and Off(b, w) < 0.5 then n = n + 1 end
		end
		if n ~= 1 then return false end
	end
	return true
end
local function Sweeps(n)
	local s = obs.blips.sweep
	for _ = 1, 1200 do
		if obs.blips.sweep >= s + n then return end
		sim.Step()
	end
	error("no sweep")
end
-- Ride east into them, stop among them, ride on through and back; every frame no name known
-- more often than it is.
local most, roughest = 0, 0
local function Ride(facing, seconds)
	p.facing, p.speed = facing, 14
	for _ = 1, seconds * 60 do
		sim.Step()
		local n = {}
		for _, b in ipairs(obs.blips.list) do
			n[b.name] = (n[b.name] or 0) + 1
			assert(n[b.name] <= count[b.name], "known twice: " .. b.name)
			local near
			for _, w in ipairs(want) do
				if w[1] == b.name then near = math.min(near or math.huge, Off(b, w)) end
			end
			if b.rough then roughest = math.max(roughest, near) else most = math.max(most, near) end
		end
	end
end
local function Stop()
	p.speed = 0
	sim.Run(0.5) -- SETTLE
	Sweeps(2)
	return Exact()
end
Ride(math.pi / 2, 12) -- 168 yd: met on the move
assert(roughest > 0, "met rough")
assert(Stop(), "stopped among them: each once, exact")
Ride(math.pi / 2, 15)
Ride(-math.pi / 2, 15)
T.Print("D3: riding, measured ones at most %.2f yd off, rough ones %.1f yd", most, roughest)
assert(most < 0.5 and roughest < 25)
assert(Stop(), "stopped again: each once, exact")
local errs = T.Errors(sim, ns)
assert(#errs == 0, table.concat(errs, "\n"))

-- A client whose square isn't ours (a patch) says so ("sensor" square, kept: each one a bug,
-- and marked). Smaller: lone squares refine ours past DRIFT. Bigger than a lone one reads: one
-- blip reads as four, so ours takes its size and the four are one. And the view radius changing
-- while a blip is measured (indoors at a door: the client's blips move on the Minimap) reads a
-- square of nothing: that refined ours below the client's, after which every blip read as
-- four, for good (session #5's 12 `sensor` events, at Tarren Mill); now that measure is dropped.
-- hit: the client's square; flip(n): whether the n-th answer turns indoors over.
local function Square(hit, flip)
	local sim2, ns2 = T.Shown()
	ns2.Atlas.BlipService = function() return nil end
	sim2.BLIP_HIT = hit
	local p2, out, at = sim2.player, {}, {}
	for i = 1, 10 do -- lone ones, around you
		local a = i * 2 * math.pi / 10
		at[i] = { 90 * math.sin(a), 90 * math.cos(a) }
		local north, west = A.TileToWorld(p2.col + at[i][1] * yd, p2.row - at[i][2] * yd)
		out[i] = { "Herb " .. i, north, west }
	end
	if flip then
		local probe, n = C_TooltipInfo.GetMinimapMouseover, 0
		C_TooltipInfo.GetMinimapMouseover = function()
			local d = probe()
			if d then
				n = n + 1
				if flip(n) then sim2.indoors = not sim2.indoors end
			end
			return d
		end
	end
	sim2.minimapBlips = out
	sim2.FireEvent("MINIMAP_UPDATE_TRACKING") -- (they show: tracking on)
	sim2.Run(10)
	local said, marks, exact = {}, 0, 0
	for _, e in ipairs(MagicMapAtlasDB.telemetry.sessions[#MagicMapAtlasDB.telemetry.sessions].kept) do
		if e.k == "sensor" then said[#said + 1] = e.d end
	end
	for _, m in ipairs(MagicMapAtlasDB.telemetry.marks) do marks = marks + (m.kind == "sensor" and 1 or 0) end
	local list = ns2.Game.obs.blips.list
	for i, w in ipairs(at) do
		for _, b in ipairs(list) do
			if b.name == "Herb " .. i and not b.rough and math.abs((b.pos.col - p2.col) / yd - w[1]) < 0.5
				and math.abs((p2.row - b.pos.row) / yd - w[2]) < 0.5 then exact = exact + 1 end
		end
	end
	assert(#T.Errors(sim2, ns2) == 0, table.concat(T.Errors(sim2, ns2), "\n"))
	return said, #list, exact, marks
end
local small, n, exact, marks = Square(5.6)
T.Print("D3: a square of 5.6: %d known of 10, %d exact, traced %s, %d marked", n, exact,
	small[1] and ("px " .. small[1].px) or "nothing", marks)
assert(#small == 1 and small[1].e == "square" and small[1].px < 6 and n == 10 and exact == 10 and marks == 1)
local big, four
big, four, exact, marks = Square(10.5)
T.Print("D3: a square of 10.5: %d known of 10, %d exact, traced %d (px %s, n %s), %d marked", four, exact, #big,
	big[1] and big[1].px or "-", big[1] and big[1].n or "-", marks)
assert(#big == 1 and big[1].e == "square" and big[1].n == 4 and math.abs(big[1].px - 10.5) < 0.1 and four == 10
	and exact == 10 and marks == 1)
local door
door, n, exact = Square(8.1, function(k) return k == 1 or k == 41 end) -- in at a door, then out
T.Print("D3: indoors and out mid-measure: %d known of 10, %d exact, traced %d", n, exact, #door)
assert(#door == 0 and n == 10 and exact == 10)
