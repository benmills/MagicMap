-- The way you'd walk from one place to another on a map, over Atlas.Walk's graph of parts (the ground you can
-- stand on in each ~33 yd terrain chunk; promo/pathing/walk-v2-spec.md): around cliffs, mountains and lava and
-- (when it's shorter) around lakes. Near (the same or a neighbouring tile): A* over the parts. Far: over the tiles
-- (Data/WalkGraph.lua: the parts at each tile's borders and the cheapest ways between them inside it), its legs then
-- walked out part by part inside their tiles. Line of sight straightens it, and its corners are rounded off. The
-- regions (Data/WalkRegions.lua) say at once when there's no way, and the way to the nearest place there is. The
-- search alone, no state between calls but its reused tables: model/Route.lua runs it in a Runtime.Job (yield:
-- Runtime.Yield, a node at a time) and keeps the result up to date; the web demo (demo/server.py /api/route) runs
-- it whole, with a trace of what it did.

local _, ns = ...
local Atlas = ns.Atlas or {}; ns.Atlas = Atlas
local Data = ns.Data
local Walk = Atlas.Walk
local Route = {}
Atlas.Route = Route

local floor, sqrt, abs, max, min = math.floor, math.sqrt, math.abs, math.max, math.min
local CHUNKS, SPAN, PARTS, COST = Walk.CHUNKS, Walk.SPAN, Walk.PARTS, Walk.COST
local LAND = 1
local MAX_NODES = 60000             -- a plain search gives up past this many (no tile graph, or none found by it)
local NEAR_NODES = 4000             -- ...the one for a near way, where the tile graph can take over
local TILE_NODES = 4096             -- a search inside one tile (16 x 16 chunks, 7 parts at most each: never)
local MAX_NODES2 = 60000            -- the tile graph's search gives up past this many of its nodes (a continent's, all of them)
local PAD, PAD_SHARE = 24, 0.6      -- a plain search's box: start and goal's, grown by this many chunks or this share of the distance
local GAP, GAP_SHARE = 8, 0.25      -- no way all the way: the way to the nearest node it reaches, if this close (chunks, or share of the distance), then straight
local ROUND = 5                     -- chunks a corner is cut back along each leg (at most half the leg) and rounded off: a walking line, not a polygon
local ROUND_STEPS = 3               -- the points of a rounded corner's curve, less one
local KEEP_NODES = 8192             -- a search's tables kept for the next (emptied first) while it closed no more than this
local GOAL, START = -1, -2          -- the tile graph search's own two nodes
local GREED = 1.5                   -- the tile graph's A* heuristic weighted: ways at most this much longer than the best, far fewer nodes
Route.CHUNKS, Route.SPAN, Route.PARTS, Route.COST, Route.MAX_NODES = CHUNKS, SPAN, PARTS, COST, MAX_NODES

local function NoYield() end

-- A node's chunk; its tile's key.
local function ChunkOf(id)
	local gc = floor(id / SPAN)
	return gc, floor((id - gc * SPAN) / PARTS)
end
local function TileOf(id)
	local gc, gr = ChunkOf(id)
	return floor(gc / CHUNKS) * 64 + floor(gr / CHUNKS)
end

-- Binary heaps of (id, its f when pushed): a node found again by a cheaper way is pushed again, and its older
-- entries skipped (closed: its g negated less one, no closed set).
local function Push(H, id, f)
	local ids, keys = H.ids, H.keys
	local i = H.n + 1
	H.n = i
	while i > 1 do
		local p = floor(i / 2)
		if keys[p] <= f then break end
		ids[i], keys[i] = ids[p], keys[p]
		i = p
	end
	ids[i], keys[i] = id, f
end

local function Pop(H)
	local ids, keys, n = H.ids, H.keys, H.n
	local top, id, f = ids[1], ids[n], keys[n]
	ids[n], keys[n] = nil, nil
	n = n - 1
	H.n = n
	if n == 0 then return top end
	local i = 1
	while true do
		local l = i * 2
		if l > n then break end
		if l < n and keys[l + 1] < keys[l] then l = l + 1 end
		if keys[l] >= f then break end
		ids[i], keys[i] = ids[l], keys[l]
		i = l
	end
	ids[i], keys[i] = id, f
	return top
end

-- The searches' tables, kept from search to search (a stray's search makes no garbage): the parts' A* (ag, ap),
-- the start's and goal's tile searches (sg, sp; tg, tp), the tile graph's (g2, p2, h2: its nodes' heuristic); a heap for the parts, one for
-- the graph; Edges' out.
local ag, ap, sg, sp, tg, tp, g2, p2, h2 = {}, {}, {}, {}, {}, {}, {}, {}, {}
local H1, H2 = { ids = {}, keys = {}, n = 0 }, { ids = {}, keys = {}, n = 0 }
local ways = {}

local function Empty(t, yield)
	local n = 0
	for k in pairs(t) do
		t[k] = nil
		n = n + 1
		if n % 256 == 0 then yield() end
	end
end

local function Closed(trace, id)
	if trace then
		trace.nodes = trace.nodes + 1
		trace.closed[#trace.closed + 1] = id
	end
end

-- The path to id by parents p (the start first).
local function Back(p, id)
	local back = {}
	while id do
		back[#back + 1] = id
		id = p[id]
	end
	local out, n = {}, #back
	for i = 1, n do out[i] = back[n + 1 - i] end
	return out
end

---------------------------------------------------------------------------------------------------
-- Over the parts.

-- A*, from node s to node g, a node at a time between yields: the nodes along the way, s first, or nil. Inside
-- tile `inside` (its key) or box { c0, r0, c1, r1 } (chunks) if given. Then (none found): the way to the node
-- nearest g it closed and how far that is from g (chunks); whether it gave up at cap; how many it closed. Distances are the chunks' centres': a part's
-- position is inside its chunk, so it's within a chunk's diagonal of admissible.
local function AStar(inst, s, g, cap, inside, box, yield, trace)
	Empty(ag, yield)
	Empty(ap, yield)
	H1.n = 0
	local Edges = Walk.Edges
	local gc, gr = ChunkOf(g)
	local c0, r0, c1, r1
	if box then c0, r0, c1, r1 = box[1], box[2], box[3], box[4] end
	local sc, sr = ChunkOf(s)
	local d = sqrt((gc - sc) ^ 2 + (gr - sr) ^ 2)
	ag[s] = 0
	Push(H1, s, d)
	local near, nearD, count, found = s, d, 0, nil
	while H1.n > 0 and count < cap do
		local id = Pop(H1)
		if id == g then
			found = Back(ap, id)
			break
		end
		local gi = ag[id]
		if gi >= 0 then -- (not closed: a cheaper way's entry was popped before this one)
			ag[id] = -gi - 1
			count = count + 1
			Closed(trace, id)
			local c, r = ChunkOf(id)
			local h = sqrt((gc - c) ^ 2 + (gr - r) ^ 2)
			if h < nearD then near, nearD = id, h end
			for k = 1, Edges(inst, id, ways) do
				local nid = ways[2 * k - 1]
				local gn = ag[nid]
				if not (gn and gn < 0) then
					local nc, nr = ChunkOf(nid)
					if (not inside or floor(nc / CHUNKS) * 64 + floor(nr / CHUNKS) == inside)
						and (not box or nc >= c0 and nc <= c1 and nr >= r0 and nr <= r1) then
						local ng = gi + ways[2 * k]
						if not gn or ng < gn then
							ag[nid], ap[nid] = ng, id
							Push(H1, nid, ng + sqrt((gc - nc) ^ 2 + (gr - nr) ^ 2))
						end
					end
				end
			end
		end
		yield() -- (a closed node's entry too: a run of them is a node's work)
	end
	local way = not found and Back(ap, near)
	if count > KEEP_NODES then ag, ap, H1 = {}, {}, { ids = {}, keys = {}, n = 0 } end -- (not kept: MBs after a capped one)
	return found, way, nearD, count >= cap, count
end

-- Dijkstra inside s's tile, from s (rev: to s, over the edges backwards), every node of the tile it reaches:
-- their costs in g (closed: negated less one), the way back in p.
local function Spread(inst, s, rev, g, p, yield, trace)
	Empty(g, yield)
	Empty(p, yield)
	H1.n = 0
	local Edges, key = Walk.Edges, TileOf(s)
	g[s] = 0
	Push(H1, s, 0)
	local count = 0
	while H1.n > 0 and count < TILE_NODES do
		local id = Pop(H1)
		local gi = g[id]
		if gi >= 0 then
			g[id] = -gi - 1
			count = count + 1
			Closed(trace, id)
			for k = 1, Edges(inst, id, ways, rev) do
				local nid = ways[2 * k - 1]
				local gn = g[nid]
				if not (gn and gn < 0) and TileOf(nid) == key then
					local ng = gi + ways[2 * k]
					if not gn or ng < gn then
						g[nid], p[nid] = ng, id
						Push(H1, nid, ng)
					end
				end
			end
		end
		yield()
	end
	return count
end

---------------------------------------------------------------------------------------------------
-- Over the tiles (Data/WalkGraph.lua): node x = tile key * 64 + its index there.

local function Graph(inst, key)
	local G = Data.WalkGraph and Data.WalkGraph[inst]
	G = G and G[key]
	if not G then return nil end
	return G.nodes or G[1], G.costs or G[2], G.cross or G[3]
end

-- Tile key's graph node a: its part's id.
local function Part(nodes, key, a)
	local o = a * 3 + 1
	local i = (nodes:byte(o) - 48) * 64 + nodes:byte(o + 1) - 48
	return (floor(key / 64) * CHUNKS + i % CHUNKS) * SPAN + (key % 64 * CHUNKS + floor(i / CHUNKS)) * PARTS + nodes:byte(o + 2) - 48
end

-- The tile graph search's tables not kept for the next after a big one (MBs).
local function Drop(count)
	if count > KEEP_NODES then g2, p2, h2, H2 = {}, {}, {}, { ids = {}, keys = {}, n = 0 } end
end

-- The parts from s to graph node `last` (the tile graph search's, by its parents): the start's tile search's way
-- to the first graph node, then each leg walked out (A* inside its tile; a cross edge is an edge of the parts
-- already). And the graph's way as parts (s first).
local function Walkout(inst, s, last, yield, trace)
	local xs, x = {}, last
	while x ~= START do
		xs[#xs + 1] = x
		x = p2[x]
	end
	local abstract = { s }
	for i = #xs, 1, -1 do
		local key = floor(xs[i] / 64)
		abstract[#abstract + 1] = Part((Graph(inst, key)), key, xs[i] % 64)
	end
	local out = Back(sp, abstract[2] or s)
	for i = 2, #abstract - 1 do
		local a, b = abstract[i], abstract[i + 1]
		if a ~= b then
			local leg
			if TileOf(a) == TileOf(b) then leg = AStar(inst, a, b, TILE_NODES, TileOf(a), nil, yield, trace) end
			if leg then
				for k = 2, #leg do out[#out + 1] = leg[k] end
			else
				out[#out + 1] = b
			end
		end
	end
	return out, abstract
end

-- The way from s to g by the tile graph: the parts along it (s first), or nil; and the graph's nodes along it
-- (their parts' ids, s and g at its ends). No way: nil, the graph's way to as near as it got, the parts along that,
-- how far its end is from g (chunks).
local function Tiles(inst, s, g, yield, trace)
	local ks, kg = TileOf(s), TileOf(g)
	local ns0, nsg = Graph(inst, ks), Graph(inst, kg)
	if not (ns0 and nsg) then return nil end
	Spread(inst, s, false, sg, sp, yield, trace)
	Spread(inst, g, true, tg, tp, yield, trace)
	Empty(g2, yield)
	Empty(p2, yield)
	Empty(h2, yield)
	H2.n = 0
	local gc, gr = ChunkOf(g)
	local cur -- (the node being expanded: the parent of those it finds)
	-- x (tile key's node b; GOAL: nodes nil) found at cost ng: kept if it's the cheapest yet.
	local function Relax(x, ng, nodes, key, b)
		local gn = g2[x]
		if not gn or gn >= 0 and ng < gn then
			g2[x], p2[x] = ng, cur
			local h = h2[x]
			if not h then
				h = 0
				if nodes then
					local c, r = ChunkOf(Part(nodes, key, b))
					h = sqrt((gc - c) ^ 2 + (gr - r) ^ 2) * GREED
				end
				h2[x] = h
			end
			Push(H2, x, ng + h)
		end
	end
	cur = START
	for a = 0, #ns0 / 3 - 1 do
		local v = sg[Part(ns0, ks, a)]
		if v then Relax(ks * 64 + a, -v - 1, ns0, ks, a) end
		if a % 16 == 15 then yield() end
	end
	if ks == kg and sg[g] then Relax(GOAL, -sg[g] - 1) end
	local count, found = 0, false
	while H2.n > 0 and count < MAX_NODES2 do
		local x = Pop(H2)
		if x == GOAL then
			found = true
			break
		end
		local gi = g2[x]
		if gi >= 0 then
			g2[x] = -gi - 1
			count = count + 1
			cur = x
			local key, a = floor(x / 64), x % 64
			local nodes, costs, cross = Graph(inst, key)
			local part = Part(nodes, key, a)
			if trace then
				trace.nodes, trace.nodes2 = trace.nodes + 1, trace.nodes2 + 1
				trace.closed2[#trace.closed2 + 1] = part
			end
			local m, base = #nodes / 3, key * 64
			local row = a * m * 2 - 1
			local from = p2[x]
			-- Its tile's other nodes only if it came in from another tile: a tile's costs are the cheapest ways inside
			-- it, so in by one of them (or from the start's tile search) the others were found as cheap already.
			for b = 0, (from >= 0 and floor(from / 64) ~= key) and m - 1 or -1 do
				local hi, lo = costs:byte(row + 2 * b + 2, row + 2 * b + 3)
				local c = hi * 64 + lo - 3120 -- ((hi - 48) * 64 + lo - 48; 4095: none)
				if c < 4095 and b ~= a then
					local y, ng = base + b, gi + c / 8
					local gn = g2[y]
					if not gn or gn >= 0 and ng < gn then -- (Relax's, inline: a node's every way in its tile)
						g2[y], p2[y] = ng, x
						local h = h2[y]
						if not h then
							local cc, rr = ChunkOf(Part(nodes, key, b))
							h = sqrt((gc - cc) ^ 2 + (gr - rr) ^ 2) * GREED
							h2[y] = h
						end
						Push(H2, y, ng + h)
					end
				end
				if b % 16 == 15 then yield() end -- (63 of them at most: a node's work in 16)
			end
			for o = 1, #cross - 5, 6 do
				if cross:byte(o) - 48 == a then
					local k2 = (cross:byte(o + 1) - 48) * 64 + cross:byte(o + 2) - 48
					local b = cross:byte(o + 3) - 48
					local nodes2 = Graph(inst, k2)
					if nodes2 then
						Relax(k2 * 64 + b, gi + ((cross:byte(o + 4) - 48) * 64 + cross:byte(o + 5) - 48) / 8, nodes2, k2, b)
					end
				end
				if o % 192 == 1 then yield() end -- (every 32 looked at)
			end
			if key == kg then
				local v = tg[part]
				if v then Relax(GOAL, gi - v - 1) end
			end
		end
		yield()
	end
	if found then
		local out, abstract = Walkout(inst, s, p2[GOAL], yield, trace)
		local x = tp[out[#out]] -- (the last graph node, or s: on to g by the goal's tile search)
		while x do
			out[#out + 1] = x
			x = tp[x]
		end
		abstract[#abstract + 1] = g
		Drop(count)
		return out, abstract
	end
	-- None (no regions said so first; the graph searched out): the way to the graph node it closed nearest g, then
	-- on inside that one's tile to its part nearest g. Then: how far that is from g (chunks).
	local best, bestH, n = nil, nil, 0
	for x, v in pairs(g2) do
		if x >= 0 and v < 0 and (not bestH or h2[x] < bestH) then best, bestH = x, h2[x] end
		n = n + 1
		if n % 256 == 0 then yield() end
	end
	if not best then
		Drop(count)
		return nil
	end
	local out, abstract = Walkout(inst, s, best, yield, trace)
	local last = out[#out]
	Spread(inst, last, false, tg, tp, yield, trace)
	local near, nearD = last, nil
	for x in pairs(tg) do
		local c, r = ChunkOf(x)
		local d = sqrt((gc - c) ^ 2 + (gr - r) ^ 2)
		if not nearD or d < nearD then near, nearD = x, d end
	end
	local leg = Back(tp, near)
	for k = 2, #leg do out[#out + 1] = leg[k] end
	Drop(count)
	return nil, abstract, out, nearD
end

---------------------------------------------------------------------------------------------------
-- Line of sight, straightening, rounding.

-- Can you walk straight from node a to node b (or, b nil, to any part of the chunk under tile position (bc, br)),
-- through parts no costlier than `worst`? Steps chunk to chunk along the line from a's position (or (ac, ar),
-- tile coordinates, if that's in a's chunk) to b's (or (bc, br)), each step an edge of the parts (Walk.Step:
-- straight, or diagonal where the line passes a corner exactly), on to the part nearest the line where there's
-- more than one. Which boundary comes first is compared multiplied out: no divide by a 0 width. yield (or
-- nil): called each SIGHT_STEPS chunks (a long line of sight is many nodes' work).
local SIGHT_STEPS = 8
local NARROW = 0.3 -- chunks a straight line may pass from a part that isn't most of its chunk
local sightBuf = {}
function Route.Sight(inst, a, b, worst, yield, ac, ar, bc, br)
	local Step, Pos, Class = Walk.Step, Walk.Pos, Walk.Class
	local c, r = ChunkOf(a)
	local x0, y0
	if ac and floor(ac * CHUNKS) == c and floor(ar * CHUNKS) == r then
		x0, y0 = ac * CHUNKS, ar * CHUNKS
	else
		x0, y0 = Pos(inst, a)
		if not x0 then return false end
		x0, y0 = x0 * CHUNKS, y0 * CHUNKS
	end
	local x1, y1
	if b then
		x1, y1 = Pos(inst, b)
		if not x1 then return false end
		x1, y1 = x1 * CHUNKS, y1 * CHUNKS
	else
		x1, y1 = bc * CHUNKS, br * CHUNKS
	end
	local dx, dy = x1 - x0, y1 - y0
	local ex, ey = floor(x1), floor(y1)
	local sx, sy = ex > c and 1 or -1, ey > r and 1 or -1
	local nx, ny = abs(ex - c), abs(ey - r)
	local bx, by = sx > 0 and c + 1 or c, sy > 0 and r + 1 or r -- the next boundary each way
	local adx, ady = abs(dx), abs(dy)
	local u, steps = a, 0
	while nx > 0 or ny > 0 do
		local mx, my = sx, sy
		if nx == 0 then
			mx = 0
		elseif ny == 0 then
			my = 0
		else
			local tx, ty = abs(bx - x0) * ady, abs(by - y0) * adx
			if tx < ty then my = 0 elseif ty < tx then mx = 0 end
		end
		local k = Step(inst, u, mx, my, sightBuf)
		if k == 0 then return false end
		local v = sightBuf[1]
		if k > 1 then
			local best
			for j = 1, k do
				local w = sightBuf[j]
				if w == b then
					v = w
					break
				end
				local px, py = Pos(inst, w)
				local off = abs(dx * (py * CHUNKS - y0) - dy * (px * CHUNKS - x0)) -- (the line's length times the distance off it)
				if not best or off < best then v, best = w, off end
			end
		end
		if COST[Class(inst, v)] > worst then return false end
		u, c, r = v, c + mx, r + my
		-- A part that isn't most of its chunk (a ledge, a path up a slope: its place is its own, not the chunk's
		-- centre): the line must pass by where it is, or it's drawn over the cliff beside it.
		local px, py = Pos(inst, v)
		px, py = px * CHUNKS, py * CHUNKS
		if px - c ~= 0.5 or py - r ~= 0.5 then
			local off = abs(dx * (py - y0) - dy * (px - x0))
			if off * off > NARROW * NARROW * (dx * dx + dy * dy) then return false end
		end
		if mx ~= 0 then bx, nx = bx + sx, nx - 1 end
		if my ~= 0 then by, ny = by + sy, ny - 1 end
		steps = steps + 1
		if yield and steps % SIGHT_STEPS == 0 then yield() end
	end
	if b and u ~= b then -- (b's chunk, another part of it: on to b by its own chunk's edges)
		if COST[Class(inst, b)] > worst then return false end
		for j = 1, Step(inst, u, 0, 0, sightBuf) do
			if sightBuf[j] == b then return true end
		end
		return false
	end
	return true
end
local Sight = Route.Sight

-- The nodes where the route turns: from each, straight on to a furthest one in sight (through nothing costlier
-- than the route itself crosses there): a gallop (1, 2, 4, ... on) to the first out of sight, then halved back
-- between it and the last in sight; a few lines of sight a turn, not one for each node on.
local costs = {} -- the route's nodes' class costs (this call's)
local function Straighten(inst, ids, yield)
	local Class, n = Walk.Class, #ids
	for k = 1, n do
		costs[k] = COST[Class(inst, ids[k])] or COST[LAND]
		if k % 32 == 0 then yield() end
	end
	for k = n + 1, #costs do costs[k] = nil end
	local function Seen(i, j) -- (i < j)
		local worst = 0
		for k = i + 1, j do
			worst = max(worst, costs[k])
			if k % 256 == 0 then yield() end
		end
		yield()
		return Sight(inst, ids[i], ids[j], worst, yield)
	end
	local out, i = { ids[1] }, 1
	while i < n do
		local ok, step = i + 1, 1 -- (the next is in sight by its edge, or taken anyway)
		local bad
		while true do
			local j = min(n, ok + step)
			if j == ok then break end
			if not Seen(i, j) then
				bad = j
				break
			end
			ok, step = j, step * 2
		end
		while bad and bad - ok > 1 do
			local mid = floor((ok + bad) / 2)
			if Seen(i, mid) then ok = mid else bad = mid end
		end
		out[#out + 1] = ids[ok]
		i = ok
	end
	return out
end

-- Each corner rounded off: the legs cut back ROUND chunks from it (half a leg at most, so neighbours
-- meet and never cross) and joined by a quadratic Bezier whose control is the corner. Lazier than
-- Chaikin's (which cut a quarter of a leg a pass): the line reads as a path walked, not turned sharply.
-- Ends kept.
local function Round(inst, pts)
	local n = #pts
	if n < 3 then return pts end
	local out = { pts[1] }
	for i = 2, n - 1 do
		local p, a, b = pts[i], pts[i - 1], pts[i + 1]
		local la, lb = sqrt((a.col - p.col) ^ 2 + (a.row - p.row) ^ 2), sqrt((b.col - p.col) ^ 2 + (b.row - p.row) ^ 2)
		local d = min(ROUND / CHUNKS, la / 2, lb / 2)
		if d > 0 then -- (a leg of none: the corner stands)
			local sx, sy = p.col + (a.col - p.col) / la * d, p.row + (a.row - p.row) / la * d -- /: never 0 (d > 0: la, lb > 0)
			local ex, ey = p.col + (b.col - p.col) / lb * d, p.row + (b.row - p.row) / lb * d -- /: never 0 (d > 0: la, lb > 0)
			for k = 0, ROUND_STEPS do
				local t = k / ROUND_STEPS
				local u = 1 - t
				out[#out + 1] = { inst = inst, col = u * u * sx + 2 * u * t * p.col + t * t * ex, row = u * u * sy + 2 * u * t * p.row + t * t * ey }
			end
		else
			out[#out + 1] = p
		end
	end
	out[#out + 1] = pts[n]
	return out
end

---------------------------------------------------------------------------------------------------
-- The search.

-- Where the start's region doesn't reach the goal's: the node nearest the goal (by position) in a region the
-- start's reaches, if one is within reach (GAP chunks, or GAP_SHARE of the way: as near as a search that gave up
-- would have gone on from); nil if none. Rings of chunks out from the goal's, the ring after the first with one
-- looked through too (its corners can be nearer).
local reaches = {} -- [region] = whether the start's reaches it (this call's)
local function Nearest(inst, rs, s, g, yield)
	local Region, Reach, Cell, Pos = Walk.Region, Walk.Reach, Walk.Cell, Walk.Pos
	Empty(reaches, yield)
	local sc, sr = ChunkOf(s)
	local gc, gr = ChunkOf(g)
	local gx, gy = Pos(inst, g)
	local reach = floor(max(GAP, sqrt((gc - sc) ^ 2 + (gr - sr) ^ 2) * GAP_SHARE))
	local best, id, last
	for ring = 0, reach do
		if last and ring > last then break end
		for dc = -ring, ring do
			local step = (dc == -ring or dc == ring) and 1 or max(1, 2 * ring) -- (the ring's edge: whole columns at its sides)
			for dr = -ring, ring, step do
				local c, r = gc + dc, gr + dr
				local _, n = Cell(inst, c, r)
				for q = 0, n - 1 do
					local x = c * SPAN + r * PARTS + q
					local rx = Region(inst, x, yield)
					if rx then
						local ok = reaches[rx]
						if ok == nil then
							ok = Reach(inst, rs, rx) and true or false
							reaches[rx] = ok
						end
						if ok then
							local px, py = Pos(inst, x)
							local d = (px - gx) ^ 2 + (py - gy) ^ 2
							if not best or d < best then best, id = d, x end
						end
					end
				end
				yield() -- (a chunk's parts: a tile's regions read the first time among them)
			end
		end
		if best and not last then last = ring + 1 end
	end
	return id
end

-- The way from s to g: the nodes along it (s first), whether it's partial (no way all the way: to the node nearest
-- g it got to, if near enough), whether a search gave up.
local function Search(inst, s, g, yield, trace)
	if s == g then return { s }, false, false end
	local graph = Data.WalkGraph and Data.WalkGraph[inst]
	local sc, sr = ChunkOf(s)
	local gc, gr = ChunkOf(g)
	local d = sqrt((gc - sc) ^ 2 + (gr - sr) ^ 2)
	local pad = max(PAD, d * PAD_SHARE)
	local box = { min(sc, gc) - pad, min(sr, gr) - pad, max(sc, gc) + pad, max(sr, gr) + pad }
	if trace then trace.box = box end
	local near = abs(floor(sc / CHUNKS) - floor(gc / CHUNKS)) <= 1 and abs(floor(sr / CHUNKS) - floor(gr / CHUNKS)) <= 1
	if near or not graph then
		local ids, best, bestD, capped = AStar(inst, s, g, graph and NEAR_NODES or MAX_NODES, nil, box, yield, trace)
		if ids then return ids, false, false end
		if not graph then
			if bestD <= max(GAP, d * GAP_SHARE) and bestD < d then return best, true, capped end
			return nil, nil, capped
		end
	end
	local ids, abstract, way, wayD = Tiles(inst, s, g, yield, trace)
	if trace then trace.abstract = abstract end
	if ids then return ids, false, false end
	if abstract then -- (the graph searched out, no regions said so first: no way; given up, as a capped search)
		if wayD <= max(GAP, d * GAP_SHARE) and wayD < d then return way, true, true end
		return nil, nil, true
	end
	-- No graph at either end: as near as a plain search gets.
	local found, best, bestD, capped = AStar(inst, s, g, MAX_NODES, nil, box, yield, trace)
	if found then return found, false, false end
	if bestD <= max(GAP, d * GAP_SHARE) and bestD < d then return best, true, capped end
	return nil, nil, capped
end

-- The route from tile position (c1, r1) to (c2, r2), from their nodes s and g (Walk.Snap): MM.Pos[] from the one
-- to the other, and whether it's partial; nil if there's none. Third: a search gave up (MAX_NODES). Where the
-- regions say the start's doesn't reach the goal's, the way to the nearest node there is (partial), or none at
-- once. yield (or nil): called between bits of work, a node at a time. trace (or nil): .closed (the parts' nodes
-- closed, every search's, in order), .nodes (all closed, parts' and the tile graph's), .nodes2 and .closed2 (the
-- tile graph's: how many, their parts), .raw (the parts A* found), .abstract (the tile graph's way, as parts, s
-- and g at its ends; when it ran), .turns (where the straightened way turns), .box (the plain search's box,
-- chunks), .regions (the start's, the goal's) and .goal (the node searched for instead) where one doesn't reach
-- the other.
function Route.Find(inst, c1, r1, s, g, c2, r2, yield, trace)
	yield = yield or NoYield
	if trace then trace.closed, trace.nodes, trace.nodes2, trace.closed2 = {}, 0, 0, {} end
	local instead
	local rs = Walk.Region(inst, s, yield)
	local rg = Walk.Region(inst, g, yield)
	if rs and rg and Walk.Reach(inst, rs, rg) == false then
		local n = Nearest(inst, rs, s, g, yield)
		if trace then trace.regions, trace.goal = { rs, rg }, n end
		if not n then return nil, nil, false end
		g, instead = n, true
	end
	local ids, partial, capped = Search(inst, s, g, yield, trace)
	partial = partial or instead
	if not ids then return nil, nil, capped end
	if trace then trace.raw = ids end
	ids = Straighten(inst, ids, yield)
	if trace then trace.turns = ids end
	local pts = { { inst = inst, col = c1, row = r1 } }
	for i = 2, partial and #ids or #ids - 1 do -- short of the goal: on from the last node straight
		local col, row = Walk.Pos(inst, ids[i])
		pts[#pts + 1] = { inst = inst, col = col, row = row }
	end
	pts[#pts + 1] = { inst = inst, col = c2, row = r2 }
	return Round(inst, pts), partial, capped
end
