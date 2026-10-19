-- The walk grid (Data/Walk.lua): terrain chunks, 16 per tile side (~33 yards),
-- each standable or not and crossable east and south. Global chunk
-- (gc, gr) = tile (col, row) * 16.

local _, ns = ...
local Atlas = ns.Atlas or {}; ns.Atlas = Atlas
local Data = ns.Data -- the generated datasets (Data/*.lua; atlas/Coords.lua)
local Walk = {}
Atlas.Walk = Walk

local CHUNKS = 16
Walk.CHUNKS = CHUNKS
local BLOCKED = 0
local SNAP = 4 -- chunks to look around a spot you can't stand on (a bridge, a building) for one you can

local expanded = {} -- [inst][tile key] = its 256 chunk letters, run-length decoded

local function Tile(inst, key)
	local cache = expanded[inst]
	if not cache then
		cache = {}
		expanded[inst] = cache
	end
	local s = cache[key]
	if s == nil then
		local enc = Data.Walk and Data.Walk[inst] and Data.Walk[inst][key]
		if enc then
			local parts = {}
			for letter, n in enc:gmatch("(%a)(%d*)") do parts[#parts + 1] = letter:rep(tonumber(n) or 1) end
			s = table.concat(parts)
		end
		s = s or false
		cache[key] = s
	end
	return s
end

-- A chunk's value: class + 4 (can cross east) + 8 (south); 0 off the terrain.
local function Value(inst, gc, gr)
	if gc < 0 or gr < 0 then return 0 end
	local s = Tile(inst, math.floor(gc / CHUNKS) * 64 + math.floor(gr / CHUNKS))
	if not s then return 0 end
	return s:byte((gr % CHUNKS) * CHUNKS + gc % CHUNKS + 1) - 97
end

local function Class(v) return v % 4 end
local function East(v) return v % 8 >= 4 end
local function South(v) return v >= 8 end

-- class (0 blocked, 1 land, 2 water, 3 magma/slime), can cross east, can cross south.
function Walk.Cell(inst, gc, gr)
	local v = Value(inst, gc, gr)
	return Class(v), East(v), South(v)
end

-- One chunk over by (dx, dy), each -1, 0 or 1 (one of them 0).
local function Step(inst, gc, gr, dx, dy)
	if dx == 1 then return East(Value(inst, gc, gr)) end
	if dx == -1 then return East(Value(inst, gc - 1, gr)) end
	if dy == 1 then return South(Value(inst, gc, gr)) end
	return South(Value(inst, gc, gr - 1))
end

local function Open(inst, gc, gr) return Class(Value(inst, gc, gr)) ~= BLOCKED end

-- (dx, dy) any of the 8 ways: diagonals by either way round.
function Walk.CanMove(inst, gc, gr, dx, dy)
	if dx == 0 or dy == 0 then return Step(inst, gc, gr, dx, dy) and Open(inst, gc + dx, gr + dy) end
	if not Open(inst, gc + dx, gr + dy) then return false end
	return (Step(inst, gc, gr, dx, 0) and Open(inst, gc + dx, gr) and Step(inst, gc + dx, gr, 0, dy))
		or (Step(inst, gc, gr, 0, dy) and Open(inst, gc, gr + dy) and Step(inst, gc, gr + dy, dx, 0))
end

-- The 8 ways out of chunk (gc, gr), in DIRS's order: into out[d], the class of the chunk that way if
-- CanMove goes there, else false. The 3x3 around it read once (a route search's every node): a row of it
-- in one byte read where it's inside one tile.
local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
Walk.DIRS = DIRS
local function Way(open, a1, b1, c1, a2, b2, c2) return open and (a1 and b1 and c1 or a2 and b2 and c2) or false end
function Walk.Around(inst, gc, gr, out)
	local nw, n, ne, w, v, e, sw, s, se -- the values at (gc - 1, gr - 1) .. (gc + 1, gr + 1), rows north to south
	local lc, lr = gc % CHUNKS, gr % CHUNKS
	if gc >= 1 and gr >= 1 and lc >= 1 and lc <= CHUNKS - 2 and lr >= 1 and lr <= CHUNKS - 2 then
		local t = Tile(inst, math.floor(gc / CHUNKS) * 64 + math.floor(gr / CHUNKS))
		if not t then
			for d = 1, 8 do out[d] = false end
			return out
		end
		local i = lr * CHUNKS + lc -- (gc - 1, gr)'s byte
		nw, n, ne = t:byte(i - CHUNKS, i - CHUNKS + 2)
		w, v, e = t:byte(i, i + 2)
		sw, s, se = t:byte(i + CHUNKS, i + CHUNKS + 2)
		nw, n, ne, w, v, e, sw, s, se = nw - 97, n - 97, ne - 97, w - 97, v - 97, e - 97, sw - 97, s - 97, se - 97
	else
		nw, n, ne = Value(inst, gc - 1, gr - 1), Value(inst, gc, gr - 1), Value(inst, gc + 1, gr - 1)
		w, v, e = Value(inst, gc - 1, gr), Value(inst, gc, gr), Value(inst, gc + 1, gr)
		sw, s, se = Value(inst, gc - 1, gr + 1), Value(inst, gc, gr + 1), Value(inst, gc + 1, gr + 1)
	end
	-- CanMove's rules, on the 3x3: Step east from x is East(x), west East(the one west); south South(x),
	-- north South(the one north); Open is a class but BLOCKED.
	local kn, kw, ke, ks = n % 4, w % 4, e % 4, s % 4
	out[1] = East(v) and ke ~= BLOCKED and ke
	out[2] = East(w) and kw ~= BLOCKED and kw
	out[3] = South(v) and ks ~= BLOCKED and ks
	out[4] = South(n) and kn ~= BLOCKED and kn
	local k = se % 4
	out[5] = Way(k ~= BLOCKED, East(v), ke ~= BLOCKED, South(e), South(v), ks ~= BLOCKED, East(s)) and k
	k = ne % 4
	out[6] = Way(k ~= BLOCKED, East(v), ke ~= BLOCKED, South(ne), South(n), kn ~= BLOCKED, East(n)) and k
	k = sw % 4
	out[7] = Way(k ~= BLOCKED, East(w), kw ~= BLOCKED, South(w), South(v), ks ~= BLOCKED, East(sw)) and k
	k = nw % 4
	out[8] = Way(k ~= BLOCKED, East(w), kw ~= BLOCKED, South(nw), South(n), kn ~= BLOCKED, East(nw)) and k
	return out
end

-- The nearest chunk you can stand on to (gc, gr), within SNAP.
function Walk.Snap(inst, gc, gr)
	if Open(inst, gc, gr) then return gc, gr end
	for r = 1, SNAP do
		local best, bc, br
		for dc = -r, r do
			for dr = -r, r do
				if math.max(math.abs(dc), math.abs(dr)) == r and Open(inst, gc + dc, gr + dr) then
					local d = dc * dc + dr * dr
					if not best or d < best then best, bc, br = d, gc + dc, gr + dr end
				end
			end
		end
		if best then return bc, br end
	end
	return nil
end
