-- The walk graph (Data/Walk.lua, WalkParts.lua, WalkRegions.lua; the contract: promo/pathing/walk-v2-spec.md):
-- a node is a part, the ground you can stand on inside one terrain chunk (16 a tile side, ~33 yd) that its own
-- moves join, at most 7 a chunk. Node id = gc * SPAN + gr * PARTS + p (global chunk column, row = tile col, row
-- * 16 + the chunk's; p the part). Most chunks are simple: one part at the chunk's centre, both ways or not at all
-- to its east and south neighbours (a letter in Walk.lua); the rest are records in WalkParts.lua, read where
-- they lie: a tile's first touch (inside a search's 1 ms slice) is its letters run-length expanded and its
-- records' offsets listed, no more.

local _, ns = ...
local Atlas = ns.Atlas or {}; ns.Atlas = Atlas
local Data = ns.Data -- the generated datasets (Data/*.lua; atlas/Coords.lua)
local Walk = {}
Atlas.Walk = Walk

local floor, sqrt = math.floor, math.sqrt
local CHUNKS = 16
local SPAN, PARTS = 8192, 8 -- node id = gc * SPAN + gr * PARTS + p
local SNAP = 4 -- chunks to look around a spot you can't stand on (a bridge, a building) for a part you can
local COST = { 1, 3, 25 } -- by class (1 land, 2 water, 3 magma/slime): a chunk's width crossed costs this many
Walk.CHUNKS, Walk.SPAN, Walk.PARTS, Walk.COST = CHUNKS, SPAN, PARTS, COST
local SMALL = 97 -- ('a'): a simple chunk's letter is 'a' + value; a complex one's 'A' + its biggest part's class
local POW4 = { [0] = 1, 4, 16 }
local POW2 = { [0] = 1, 2, 4, 8, 16, 32, 64 }

---------------------------------------------------------------------------------------------------
-- Tiles, read lazily: T.s the 256 chunk letters (iy * 16 + ix), T[i] chunk i's record's offset in T.ps (its
-- WalkParts string), T.ds its drop links (WalkDrops: 8 chars each, in chunk then part order).

local tiles = {} -- [inst][key] = T, or false (no walk data)

local function Expand(enc)
	if not enc:find("%d") then return enc end
	return (enc:gsub("(%a)(%d+)", string.rep))
end

local function Tile(inst, key)
	local c = tiles[inst]
	if not c then
		c = {}
		tiles[inst] = c
	end
	local T = c[key]
	if T ~= nil then return T end
	T = false
	local w = Data.Walk and Data.Walk[inst]
	local enc = w and w[key]
	if enc then
		local s = Expand(enc)
		T = { s = s }
		local P = Data.WalkParts and Data.WalkParts[inst]
		local ps = P and P[key]
		if ps then -- (none: its complex chunks have no parts here, as if blocked)
			T.ps = ps
			local o, at = 1, s:find("%u")
			while at do
				T[at - 1] = o
				o = o + 2 + (ps:byte(o) - 48) * 64 + ps:byte(o + 1) - 48
				at = s:find("%u", at + 1)
			end
		end
		local D = Data.WalkDrops and Data.WalkDrops[inst]
		T.ds = D and D[key] -- (sorted by chunk, then part: looked up by halving, no index built)
	end
	c[key] = T
	return T
end

-- Chunk (gc, gr): its tile, its index there, its letter's byte; nil off the walk data. (The last tile kept at
-- hand: most are the one before's.)
local lastInst, lastKey, lastT
local function Chunk(inst, gc, gr)
	if gc < 0 or gr < 0 then return nil end
	local key = floor(gc / CHUNKS) * 64 + floor(gr / CHUNKS)
	local T
	if key == lastKey and inst == lastInst then
		T = lastT
	else
		T = Tile(inst, key)
		lastInst, lastKey, lastT = inst, key, T
	end
	if not T then return nil end
	local i = gr % CHUNKS * CHUNKS + gc % CHUNKS
	return T, i, T.s:byte(i + 1)
end

-- A complex chunk's record: its offset, part count, and the east and south neighbours' part counts.
local function Head(T, i)
	local o = T[i]
	if not o then return nil end
	local ps = T.ps
	local h = ps:byte(o + 2) - 48
	return o, h % 8, floor(h / 8), ps:byte(o + 3) - 48
end

local function Count(T, i, b)
	if b >= SMALL then return (b - SMALL) % 4 > 0 and 1 or 0 end
	local o = T[i]
	return o and (T.ps:byte(o + 2) - 48) % 8 or 0
end

local function PartClass(T, i, b, p)
	if b >= SMALL then return (b - SMALL) % 4 end
	return (T.ps:byte(T[i] + 5 + 2 * p) - 48) % 4
end

-- Part p's position, in global chunks.
local function Where(T, i, b, p, gc, gr)
	if b >= SMALL then return gc + 0.5, gr + 0.5 end
	local ps, o = T.ps, T[i] + 4 + 2 * p
	if ps:byte(o + 1) - 48 >= 4 then return gc + 0.5, gr + 0.5 end
	local q = ps:byte(o) - 48
	return gc + (q % 8 + 0.5) / 8, gr + (floor(q / 8) + 0.5) / 8
end

-- Which part a position in quad (qx, qy) of a complex chunk of n >= 2 parts snaps to: 1..n, or 0 none.
local function Label(T, i, qx, qy)
	local o, n, nE, nS = Head(T, i)
	local ps, k = T.ps, o + 4 + 2 * n + floor((n * nE + 2) / 3) + floor((n * nS + 2) / 3) + floor((n * (n - 1) + 5) / 6)
	local at, pos = qy * 8 + qx, 0
	while pos < 64 do
		local v = ps:byte(k) - 48
		pos = pos + floor(v / 8) + 1
		if at < pos then return v % 8 end
		k = k + 1
	end
	return 0
end

-- Is there an edge between parts i and j of a complex chunk of n parts (i -> j; one way)?
local function Intra(ps, o, n, nE, nS, i, j)
	local k = i * (n - 1) + (j < i and j or j - 1)
	local v = ps:byte(o + 4 + 2 * n + floor((n * nE + 2) / 3) + floor((n * nS + 2) / 3) + floor(k / 6)) - 48
	return floor(v / POW2[k % 6]) % 2 == 1 -- /: never 0 (powers of 2)
end

-- Across a chunk side: the relation is the E (east) or S of the west or north one of the two, chunk i of tile T
-- (letter byte b). Our part p is its (flip false) or its neighbour's (flip true: we're its east or south). The
-- other's parts q with an edge from p (rev: to p), into buf[1..]; their count.
local function AcrossAt(T, i, b, p, east, flip, rev, buf)
	if not T then return 0 end
	if b >= SMALL then -- both ways to the other's only part, or none
		local v = b - SMALL
		if p == 0 and (east and v % 8 >= 4 or not east and v >= 8) then
			buf[1] = 0
			return 1
		end
		return 0
	end
	local o, n, nE, nS = Head(T, i)
	if not o then return 0 end
	local ps, base, m = T.ps, o + 4 + 2 * n, nE
	if not east then base, m = base + floor((n * nE + 2) / 3), nS end
	local want = (rev ~= flip) and 2 or 1 -- bit 0: the record's part -> the neighbour's; bit 1: back
	local k = 0
	if flip then -- we're the neighbour's part p: entries (j, p)
		if p >= m then return 0 end
		for j = 0, n - 1 do
			local e = j * m + p
			if floor((ps:byte(base + floor(e / 3)) - 48) / POW4[e % 3] / want) % 2 == 1 then -- /: never 0 (powers of 2)
				k = k + 1
				buf[k] = j
			end
		end
	else -- entries (p, j)
		if p >= n then return 0 end
		for j = 0, m - 1 do
			local e = p * m + j
			if floor((ps:byte(base + floor(e / 3)) - 48) / POW4[e % 3] / want) % 2 == 1 then -- /: never 0 (powers of 2)
				k = k + 1
				buf[k] = j
			end
		end
	end
	return k
end

-- The same, from part p of chunk (gc, gr) to chunk (gc + dx, gr + dy) (dx or dy 0).
local function Across(inst, gc, gr, p, dx, dy, rev, buf)
	local flip = dx < 0 or dy < 0
	local T, i, b = Chunk(inst, flip and gc + dx or gc, flip and gr + dy or gr)
	return AcrossAt(T, i, b, p, dx ~= 0, flip, rev and true or false, buf)
end

local function Split(id)
	local gc = floor(id / SPAN)
	local rest = id - gc * SPAN
	local gr = floor(rest / PARTS)
	return gc, gr, rest - gr * PARTS
end
Walk.Split = Split

---------------------------------------------------------------------------------------------------
-- Nodes.

-- The node at tile position (col, row): the part under it (the chunk's label map; a chunk of one part, that one),
-- else the nearest part by position in the chunks up to SNAP away (a square); nil if none.
function Walk.Snap(inst, col, row)
	local x, y = col * CHUNKS, row * CHUNKS
	local gc, gr = floor(x), floor(y)
	local T, i, b = Chunk(inst, gc, gr)
	if T then
		if b >= SMALL then
			if (b - SMALL) % 4 > 0 then return gc * SPAN + gr * PARTS end
		else
			local n = Count(T, i, b)
			if n == 1 then return gc * SPAN + gr * PARTS end
			if n >= 2 then
				local l = Label(T, i, floor((x - gc) * 8), floor((y - gr) * 8))
				if l > 0 then return gc * SPAN + gr * PARTS + l - 1 end
			end
		end
	end
	local best, id
	for r = gr - SNAP, gr + SNAP do -- (rows, then columns, then parts: the first of equals; mmtools/walkdata.py's)
		for c = gc - SNAP, gc + SNAP do
			local T2, i2, b2 = Chunk(inst, c, r)
			if T2 then
				for q = 0, Count(T2, i2, b2) - 1 do
					local px, py = Where(T2, i2, b2, q, c, r)
					local d = (px - x) ^ 2 + (py - y) ^ 2
					if not best or d < best then best, id = d, c * SPAN + r * PARTS + q end
				end
			end
		end
	end
	return id
end

-- A node's position, tile coordinates; nil if there's no such node.
function Walk.Pos(inst, id)
	local gc, gr, p = Split(id)
	local T, i, b = Chunk(inst, gc, gr)
	if not T or p >= Count(T, i, b) then return nil end
	local x, y = Where(T, i, b, p, gc, gr)
	return x / CHUNKS, y / CHUNKS
end

-- A node's class: 1 land, 2 water, 3 magma/slime (0: no such node).
function Walk.Class(inst, id)
	local gc, gr, p = Split(id)
	local T, i, b = Chunk(inst, gc, gr)
	if not T or p >= Count(T, i, b) then return 0 end
	return PartClass(T, i, b, p)
end

-- Chunk (gc, gr): its class (its biggest part's; 0 none) and how many parts it has.
function Walk.Cell(inst, gc, gr)
	local T, i, b = Chunk(inst, gc, gr)
	if not T then return 0, 0 end
	if b >= SMALL then
		local k = (b - SMALL) % 4
		return k, k > 0 and 1 or 0
	end
	return b - 65, Count(T, i, b)
end

---------------------------------------------------------------------------------------------------
-- Edges.

local bufs = { {}, {}, {}, {} } -- (E, S, W, N: the straight steps' parts, the diagonals go on from)
local bufB = {}
local DX, DY = { 1, 0, -1, 0 }, { 0, 1, 0, -1 }
local DIAG = { { 1, 1, 1, 2 }, { 1, -1, 1, 4 }, { -1, 1, 3, 2 }, { -1, -1, 3, 4 } } -- dx, dy, its x and y step's buf
-- Edges' 3x3 (k = (dy + 1) * 3 + dx + 2): its chunks' tiles, indices, bytes. A side's relation is held by SIDE[d]
-- (E, S, W, N: itself, itself, west, north), the parts across it are in TO[d]. A diagonal (DIAG[d], on from its 4
-- fields): its chunk, then its second step's holder and flip, by the x neighbour and by the y one.
local nT, nI, nB = {}, {}, {}
local SIDE, TO = { 5, 5, 4, 2 }, { 6, 8, 4, 2 }
DIAG[1][5], DIAG[1][6], DIAG[1][7], DIAG[1][8], DIAG[1][9] = 9, 6, false, 8, false -- SE: E then S, S then E
DIAG[2][5], DIAG[2][6], DIAG[2][7], DIAG[2][8], DIAG[2][9] = 3, 3, true, 2, false -- NE: E then N, N then E
DIAG[3][5], DIAG[3][6], DIAG[3][7], DIAG[3][8], DIAG[3][9] = 7, 4, false, 7, true -- SW: W then S, S then W
DIAG[4][5], DIAG[4][6], DIAG[4][7], DIAG[4][8], DIAG[4][9] = 1, 1, true, 1, true -- NW: W then N, N then W
local links, linksBack = {}, {}

-- Edges' output, as it goes (no closure a call): its table, count, the node's position, the cost class into it.
local eOut, eN, eX, eY, eMine
local function Add(c, r, q, T2, i2, b2, cost)
	local x, y = Where(T2, i2, b2, q, c, r)
	local n = eN + 1
	eN = n
	eOut[2 * n - 1], eOut[2 * n] = c * SPAN + r * PARTS + q,
		cost or sqrt((x - eX) ^ 2 + (y - eY) ^ 2) * (eMine or COST[PartClass(T2, i2, b2, q)])
end

-- The map's hand links (tools/walk_links.json: tunnels, bridges, lifts): [node id] = { other id, cost, ... }
-- (flat), the edges out of a node; the list as Data has it ({ ac, ar, ap, bc, br, bp, cost, name, oneway });
-- and the edges into a node, as the first.
function Walk.Links(inst)
	local l = links[inst]
	local list = Data.WalkLinks and Data.WalkLinks[inst] or {}
	if not l then
		l = {}
		local back = {}
		local function Add(t, a, b, cost)
			local e = t[a]
			if not e then
				e = {}
				t[a] = e
			end
			e[#e + 1], e[#e + 2] = b, cost
		end
		for _, k in ipairs(list) do
			if type(k[7]) == "number" then -- (format 2's: a part at each end)
				local a, b = k[1] * SPAN + k[2] * PARTS + k[3], k[4] * SPAN + k[5] * PARTS + k[6]
				Add(l, a, b, k[7])
				Add(back, b, a, k[7])
				if not k[9] then
					Add(l, b, a, k[7])
					Add(back, a, b, k[7])
				end
			end
		end
		links[inst], linksBack[inst] = l, back
	end
	return l, list, linksBack[inst]
end

-- The nodes of chunk (gc + dx, gr + dy) that node id has an edge to, dx and dy each -1, 0 or 1: straight, a
-- derived diagonal (by either neighbour), or (0, 0) another part of its own chunk; into out[1..], their count.
-- No drop or hand links. rev: those with an edge to it.
function Walk.Step(inst, id, dx, dy, out, rev)
	local gc, gr, p = Split(id)
	local k = 0
	if dx == 0 and dy == 0 then
		local T, i, b = Chunk(inst, gc, gr)
		if not T or b >= SMALL then return 0 end
		local o, n, nE, nS = Head(T, i)
		if not o then return 0 end
		for j = 0, n - 1 do
			if j ~= p and (rev and Intra(T.ps, o, n, nE, nS, j, p) or not rev and Intra(T.ps, o, n, nE, nS, p, j)) then
				k = k + 1
				out[k] = gc * SPAN + gr * PARTS + j
			end
		end
		return k
	end
	local nc, nr = gc + dx, gr + dy
	if dx == 0 or dy == 0 then
		k = Across(inst, gc, gr, p, dx, dy, rev, bufB)
		for j = 1, k do out[j] = nc * SPAN + nr * PARTS + bufB[j] end
		return k
	end
	local seen, a = 0, bufs[1]
	for pass = 1, 2 do
		local mx, my = pass == 1 and dx or 0, pass == 1 and 0 or dy
		local na = Across(inst, gc, gr, p, mx, my, rev, a)
		for j = 1, na do
			local m = Across(inst, gc + mx, gr + my, a[j], dx - mx, dy - my, rev, bufB)
			for jj = 1, m do
				local q = bufB[jj]
				if floor(seen / POW2[q]) % 2 == 0 then seen = seen + POW2[q] end -- /: never 0 (powers of 2)
			end
		end
	end
	local q = 0
	while seen > 0 do
		if seen % 2 == 1 then
			k = k + 1
			out[k] = nc * SPAN + nr * PARTS + q
		end
		seen, q = floor(seen / 2), q + 1
	end
	return k
end

-- Node id's edges: out[2k - 1] its neighbour's id, out[2k] the cost; their count. Walk edges (the 4 neighbours,
-- its own chunk's other parts), derived diagonals, drop links and hand links. The cost: the distance between the
-- two positions, in chunks, times the class cost of the one the edge goes to (a hand link: its own cost). rev:
-- the edges into id (out[2k - 1] the one it comes from).
-- Edges' all-simple 3x3 (values: class + 4 east + 8 south): every relation both ways, every part at its centre.
local SQRT2 = sqrt(2)
local function Put(c, r, k, len)
	if k == 0 then return end
	local n = eN + 1
	eN = n
	eOut[2 * n - 1], eOut[2 * n] = c * SPAN + r * PARTS, len * (eMine or COST[k])
end
local function Simple(gc, gr, v, nw, n, ne, w, e, sw, s, se)
	local Ev, Sv, Ew, Sn = v % 8 >= 4, v >= 8, w % 8 >= 4, n >= 8
	if Ev then Put(gc + 1, gr, e % 4, 1) end
	if Sv then Put(gc, gr + 1, s % 4, 1) end
	if Ew then Put(gc - 1, gr, w % 4, 1) end
	if Sn then Put(gc, gr - 1, n % 4, 1) end
	if Ev and e >= 8 or Sv and s % 8 >= 4 then Put(gc + 1, gr + 1, se % 4, SQRT2) end
	if Ev and ne >= 8 or Sn and n % 8 >= 4 then Put(gc + 1, gr - 1, ne % 4, SQRT2) end
	if Ew and w >= 8 or Sv and sw % 8 >= 4 then Put(gc - 1, gr + 1, sw % 4, SQRT2) end
	if Ew and nw >= 8 or Sn and nw % 8 >= 4 then Put(gc - 1, gr - 1, nw % 4, SQRT2) end
end

-- A drop link's key, the entry at o of a tile's drop string: chunk index * PARTS + part.
local function DropKey(ds, o)
	return ((ds:byte(o) - 48) * 64 + ds:byte(o + 1) - 48) * PARTS + (ds:byte(o + 2) - 48) % 8
end

local function Extra(inst, T, i, p, id, rev)
	local ds = T.ds
	if ds then
		local want, lo, hi = i * PARTS + p, 0, floor(#ds / 8) -- (the first entry at or past want, in lo..hi - 1)
		while lo < hi do
			local mid = floor((lo + hi) / 2)
			if DropKey(ds, mid * 8 + 1) < want then lo = mid + 1 else hi = mid end
		end
		local o = lo * 8 + 1
		while o + 7 <= #ds and DropKey(ds, o) == want do
			if (ds:byte(o + 2) - 48 >= 8) == (rev and true or false) then -- (dir 0: from here; 1: to here)
				local c = (ds:byte(o + 3) - 48) * 64 + ds:byte(o + 4) - 48
				local r = (ds:byte(o + 5) - 48) * 64 + ds:byte(o + 6) - 48
				local T2, i2, b2 = Chunk(inst, c, r)
				local q = ds:byte(o + 7) - 48
				if T2 and q < Count(T2, i2, b2) then Add(c, r, q, T2, i2, b2) end
			end
			o = o + 8
		end
	end
	local fwd, _, back = Walk.Links(inst)
	local l = (rev and back or fwd)[id]
	if l then
		for k = 1, #l, 2 do
			local c, r, q = Split(l[k])
			local T2, i2, b2 = Chunk(inst, c, r)
			if T2 and q < Count(T2, i2, b2) then Add(c, r, q, T2, i2, b2, l[k + 1]) end
		end
	end
end

function Walk.Edges(inst, id, out, rev)
	local gc, gr, p = Split(id)
	local T, i, b = Chunk(inst, gc, gr)
	if not T or p >= Count(T, i, b) then return 0 end
	local x0, y0 = Where(T, i, b, p, gc, gr)
	eOut, eN, eX, eY, eMine = out, 0, x0, y0, rev and COST[PartClass(T, i, b, p)] -- (an edge into it: its class's cost)
	local lc, lr = i % CHUNKS, floor(i / CHUNKS)
	if b >= SMALL and lc >= 1 and lc <= CHUNKS - 2 and lr >= 1 and lr <= CHUNKS - 2 then
		-- Inside its tile, all 9 round it simple (most of the map): the 3x3 read at once, as the old grid's.
		local t = T.s
		local nw, n, ne = t:byte(i - 16, i - 14)
		local w, e = t:byte(i), t:byte(i + 2)
		local sw, so, se = t:byte(i + 16, i + 18)
		if nw >= SMALL and n >= SMALL and ne >= SMALL and w >= SMALL and e >= SMALL and sw >= SMALL and so >= SMALL and se >= SMALL then
			Simple(gc, gr, b - SMALL, nw - SMALL, n - SMALL, ne - SMALL, w - SMALL, e - SMALL, sw - SMALL, so - SMALL, se - SMALL)
			Extra(inst, T, i, p, id, rev)
			return eN
		end
	end
	-- The 3x3 round it read once (k = (dy + 1) * 3 + dx + 2: 5 itself), then each side's relation from the one
	-- that holds it.
	rev = rev and true or false
	for k = 1, 9 do
		local dx, dy = (k - 1) % 3 - 1, floor((k - 1) / 3) - 1
		local T2, i2, b2 = Chunk(inst, gc + dx, gr + dy)
		nT[k], nI[k], nB[k] = T2 or false, i2, b2
	end
	for d = 1, 4 do
		local buf, h = bufs[d], SIDE[d]
		local k = AcrossAt(nT[h], nI[h], nB[h], p, d % 2 == 1, d > 2, rev, buf)
		buf.n = k
		if k > 0 then
			local t = TO[d]
			for j = 1, k do Add(gc + DX[d], gr + DY[d], buf[j], nT[t], nI[t], nB[t]) end
		end
	end
	if b < SMALL then -- its chunk's other parts
		local o, np, nE, nS = Head(T, i)
		if o and np >= 2 then
			for j = 0, np - 1 do
				if j ~= p and (rev and Intra(T.ps, o, np, nE, nS, j, p) or not rev and Intra(T.ps, o, np, nE, nS, p, j)) then
					Add(gc, gr, j, T, i, b)
				end
			end
		end
	end
	for d = 1, 4 do -- diagonals: by the east or west neighbour, then north or south; or the other way round
		local dg = DIAG[d]
		local seen = 0
		for pass = 0, 1 do
			local a = bufs[dg[3 + pass]]
			local h, east, flip = dg[6 + 2 * pass], pass == 1, dg[7 + 2 * pass]
			local T2, i2, b2 = nT[h], nI[h], nB[h]
			for j = 1, a.n do
				for jj = 1, AcrossAt(T2, i2, b2, a[j], east, flip, rev, bufB) do
					local q = bufB[jj]
					if floor(seen / POW2[q]) % 2 == 0 then seen = seen + POW2[q] end -- /: never 0 (powers of 2)
				end
			end
		end
		local t, q = dg[5], 0
		while seen > 0 do -- (its bits, lowest first)
			if seen % 2 == 1 then Add(gc + dg[1], gr + dg[2], q, nT[t], nI[t], nB[t]) end
			seen, q = floor(seen / 2), q + 1
		end
	end
	Extra(inst, T, i, p, id, rev)
	return eN
end

---------------------------------------------------------------------------------------------------
-- Regions (Data/WalkRegions.lua): strongly connected parts of the graph, hand links counted; which reaches which.

local regionTiles = {} -- [inst][key] = [i * PARTS + p] = region (a table), or a number for the whole tile, or false

local function RegionTile(inst, key, yield)
	local cache = regionTiles[inst]
	if not cache then
		cache = {}
		regionTiles[inst] = cache
	end
	local t = cache[key]
	if t == nil then
		local enc = Data.WalkRegions[inst][key]
		if type(enc) == "string" then
			local T = Tile(inst, key)
			t = T and {}
			local str, ps = T and T.s, T and T.ps
			local i, q, n = -1, 0, 0 -- (the node: chunk i's part q, of n)
			for id, run in (T and enc or ""):gmatch("(%d+)x?(%d*)") do
				id = tonumber(id)
				for _ = 1, tonumber(run) or 1 do
					while q >= n and i < 255 do
						i, q = i + 1, 0
						local b = str:byte(i + 1)
						if b >= SMALL then
							n = (b - SMALL) % 4 > 0 and 1 or 0
						else
							local o = T[i]
							n = o and (ps:byte(o + 2) - 48) % 8 or 0
						end
					end
					t[i * PARTS + q] = id
					q = q + 1
					if yield and i % 32 == 31 and q == 1 then yield() end -- (every 32 chunks: a big tile's a few nodes' work)
				end
			end
		else
			t = enc or false
		end
		cache[key] = t
	end
	return t
end

-- Node id's region: 1 the map's biggest; nil where there are none (no Data/WalkRegions.lua, off its tiles).
-- yield (or nil): called now and then while a tile's regions are read the first time (inside a search's slice).
function Walk.Region(inst, id, yield)
	if not (Data.WalkRegions and Data.WalkRegions[inst]) then return nil end
	local gc, gr, p = Split(id)
	local t = RegionTile(inst, floor(gc / CHUNKS) * 64 + floor(gr / CHUNKS), yield)
	if not t then return nil end
	if type(t) == "number" then return t end
	return t[(gr % CHUNKS * CHUNKS + gc % CHUNKS) * PARTS + p]
end

local into = {} -- [inst][b] = { [h] = true }: the hubs that reach region b (Data's dn[b])

-- Does region a reach region b (a walk from any node of a to any of b)? nil: not known (no Data/WalkRegions.lua).
function Walk.Reach(inst, a, b)
	if a == b then return true end
	local R = Data.WalkReach and Data.WalkReach[inst]
	if not (R and a and b) then return nil end
	local own = R.own and R.own[a]
	if own then
		for k = 1, #own do
			if own[k] == b then return true end
		end
	end
	local sets = into[inst]
	if not sets then
		sets = {}
		into[inst] = sets
	end
	local dn = sets[b]
	if not dn then
		dn = {}
		for _, h in ipairs(R.dn and R.dn[b] or {}) do dn[h] = true end
		sets[b] = dn
	end
	if a <= (R.hubs or 0) and dn[a] then return true end
	local up = R.up and R.up[a]
	if up then
		for k = 1, #up do
			local h = up[k]
			if h == b or dn[h] then return true end
		end
	end
	return false
end
