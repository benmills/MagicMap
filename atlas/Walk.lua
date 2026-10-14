-- The walk grid (Data/Walk.lua): terrain chunks, 16 per tile side (~33 yards),
-- each standable or not and crossable east and south. Global chunk
-- (gc, gr) = tile (col, row) * 16.

local _, ns = ...
local Atlas = ns.Atlas or {}; ns.Atlas = Atlas
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
		local enc = MagicMap_Walk and MagicMap_Walk[inst] and MagicMap_Walk[inst][key]
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
