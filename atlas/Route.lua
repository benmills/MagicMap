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

local floor, ceil, sqrt, abs, max, min = math.floor, math.ceil, math.sqrt, math.abs, math.max, math.min
local CHUNKS, SPAN, PARTS, COST = Walk.CHUNKS, Walk.SPAN, Walk.PARTS, Walk.COST
local LAND = 1
local CHUNK_YD = 1600 / 3 / 16 -- yards a chunk side (/: never 0, constants)
local MAX_NODES = 60000             -- a plain search gives up past this many (no tile graph, or none found by it)
local NEAR_NODES = 4000             -- ...the one for a near way, where the tile graph can take over
local TILE_NODES = 4096             -- a search inside one tile (16 x 16 chunks, 7 parts at most each: never)
local MAX_NODES2 = 60000            -- the tile graph's search gives up past this many of its nodes (a continent's, all of them)
local PAD, PAD_SHARE = 24, 0.6      -- a plain search's box: start and goal's, grown by this many chunks or this share of the distance
local GAP, GAP_SHARE = 8, 0.25      -- no way all the way: the way to the nearest node it reaches, if this close (chunks, or share of the distance), then straight
local ROUND_COS = 0.9               -- a corner turning less than this cosine's angle (~25 degrees) stands: no curve for a bend you'd not see
local KEEP_NODES = 8192             -- a search's tables kept for the next (emptied first) while it closed no more than this
local GOAL, START = -1, -2          -- the tile graph search's own two nodes
local GREED = 1.5                   -- the tile graph's A* heuristic weighted: ways at most this much longer than the best, far fewer nodes
Route.CHUNKS, Route.SPAN, Route.PARTS, Route.COST, Route.MAX_NODES = CHUNKS, SPAN, PARTS, COST, MAX_NODES

-- How the line is drawn over the way found (Settings > Tracking > Route: ui/Path.lua sets them; the demo has these):
--   slack      yd of rough ground the line may cut across in one go (a rock, a bump: walked round without a line)
--   corridor   chunks either side of the way found the drawn line may stray, to keep off rough ground
--   roughCost, sheerCost  what a 4-yd cell of rough (too steep to walk up), of sheer (a fall, no ground) costs the line
--              there against open ground's 1: over them only where there's no way round in the corridor
--   round      chunks each corner is cut back along its legs (at most half of each) and curved off
--   roundSteps the curve's points, less one
local TUNE = { slack = 10, corridor = 1.5, roughCost = 6, sheerCost = 30, round = 2.1, roundSteps = 4 }
Route.TUNE = TUNE

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
	local Edges, Warm = Walk.Edges, Walk.Warm
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
			Warm(inst, id, yield)
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
	local Edges, Warm, key = Walk.Edges, Walk.Warm, TileOf(s)
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
			Warm(inst, id, yield)
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
		if i % 16 == 0 then yield() end
	end
	yield()
	local out = Back(sp, abstract[2] or s)
	yield()
	for i = 2, #abstract - 1 do
		local a, b = abstract[i], abstract[i + 1]
		if a ~= b then
			local leg
			local ac, ar = ChunkOf(a)
			local bc, br = ChunkOf(b)
			if TileOf(a) == TileOf(b) then
				leg = AStar(inst, a, b, TILE_NODES, TileOf(a), nil, yield, trace)
				-- (no way inside the tile: its graph's way leaves it, round a cliff; out of it then, a near search's
				-- nodes at most, rather than a straight jump over what's between)
				if not leg then leg = AStar(inst, a, b, NEAR_NODES, nil, nil, yield, trace) end
			elseif abs(ac - bc) > 1 or abs(ar - br) > 1 then
				-- (two tiles' entrances: each one part for a run of crossings up to 8 chunks long, so not always side
				-- by side: the way between them, not a jump along the border)
				leg = AStar(inst, a, b, NEAR_NODES, nil, nil, yield, trace)
			end
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
-- nil): called each SIGHT_STEPS chunks (a long line of sight is many nodes' work). The line must also keep off
-- rough ground (Clear) unless rough is false.
local SIGHT_STEPS = 8
local NARROW = 0.3 -- chunks a straight line may pass from a part that isn't most of its chunk
local CLEAR_STEP = 1 / 8 -- chunks between the samples a line's checked for rough ground at (a quad, ~4 yd)
local CLEAR_SLICE = 32 -- samples between yields

-- Does the straight line from global chunk position (x0, y0) to (x1, y1) keep off rough ground (Walk.Rough:
-- too steep to walk over, or no ground)? Off sheer ground always (over 61.6 degrees, or none); over rough ground
-- that isn't sheer, no more than slack yd in a row (TUNE.slack: a bump, a rock), or any, sheer true (steep you walk
-- down). Its ends aren't judged (a node's place can sit beside a cliff).
local function Clear(inst, x0, y0, x1, y1, yield, sheer, slack)
	local RoughChunk, RoughQuad = Walk.RoughChunk, Walk.RoughQuad
	local len = sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
	local n = ceil(len / CLEAR_STEP)
	local step = n > 0 and len / n * CHUNK_YD or 0 -- /: never 0 (n > 0)
	slack = slack or TUNE.slack
	local lc, lr, s, o -- (the chunk the last sample was in, its bits: a chunk's 8 or so samples one look)
	local run = 0 -- (yd of rough ground crossed in a row)
	for k = 1, n - 1 do
		local t = k / n -- /: never 0 (n >= 2 inside the loop)
		local x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
		local gc, gr = floor(x), floor(y)
		if gc ~= lc or gr ~= lr then
			lc, lr = gc, gr
			s, o = RoughChunk(inst, gc, gr)
		end
		local qx, qy = floor((x - gc) * 8), floor((y - gr) * 8)
		if s and RoughQuad(s, o + 11, qx, qy) then return false end -- (sheer: no slack, a cliff's face can be a quad)
		if s and not sheer and RoughQuad(s, o, qx, qy) then
			run = run + step
			if run > slack then return false end
		else
			run = 0
		end
		if yield and k % CLEAR_SLICE == 0 then yield() end
	end
	return true
end
Route.Clear = Clear

local sightBuf = {}
function Route.Sight(inst, a, b, worst, yield, ac, ar, bc, br, rough)
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
		if yield then Walk.Warm(inst, u, yield) end
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
		local joined = false
		for j = 1, Step(inst, u, 0, 0, sightBuf) do
			if sightBuf[j] == b then joined = true end
		end
		if not joined then return false end
	end
	if rough == false then return true end -- (the caller checks the ground itself: Route.Clear)
	return Clear(inst, x0, y0, x1, y1, yield)
end
local Sight = Route.Sight

-- A derived diagonal (u to w by a side chunk's part v: Walk.Step) is a leg between the two parts' places, the
-- corner cut; where that crosses rough ground, the route goes by v instead (by the side whose legs are clear,
-- else the first found): the search costs the diagonal, the line follows the parts that make it.
local viaBuf, viaBuf2 = {}, {}
local function Corners(inst, ids, yield)
	local Step, Pos = Walk.Step, Walk.Pos
	local out = { ids[1] }
	for k = 2, #ids do
		local u, w = ids[k - 1], ids[k]
		local uc, ur = ChunkOf(u)
		local wc, wr = ChunkOf(w)
		local dx, dy = wc - uc, wr - ur
		if (dx == 1 or dx == -1) and (dy == 1 or dy == -1) then
			local ux, uy = Pos(inst, u)
			local wx, wy = Pos(inst, w)
			if not Clear(inst, ux * CHUNKS, uy * CHUNKS, wx * CHUNKS, wy * CHUNKS, yield) then
				local best, any
				for side = 1, 2 do
					local sx, sy = side == 1 and dx or 0, side == 1 and 0 or dy
					local n = Step(inst, u, sx, sy, viaBuf)
					for j = 1, n do
						local v = viaBuf[j]
						local m = Step(inst, v, dx - sx, dy - sy, viaBuf2)
						yield()
						for i = 1, m do
							if viaBuf2[i] == w then
								any = any or v
								local vx, vy = Pos(inst, v)
								if not best and Clear(inst, ux * CHUNKS, uy * CHUNKS, vx * CHUNKS, vy * CHUNKS, yield)
									and Clear(inst, vx * CHUNKS, vy * CHUNKS, wx * CHUNKS, wy * CHUNKS, yield) then
									best = v
								end
							end
						end
					end
				end
				if best or any then out[#out + 1] = best or any end
			end
		end
		out[#out + 1] = w
		yield()
	end
	return out
end

-- The nodes where the route turns: from each, straight on to a furthest one in sight (through nothing costlier
-- than the route itself crosses there): a gallop (1, 2, 4, ... on) to the first out of sight, then halved back
-- between it and the last in sight; a few lines of sight a turn, not one for each node on.
local costs, linked = {}, {} -- the route's nodes' class costs; whether node k -> k + 1 is a hand link (this call's)
local function Straighten(inst, ids, yield)
	local Class, LinkAt, n = Walk.Class, Walk.LinkAt, #ids
	for k = 1, n do
		costs[k] = COST[Class(inst, ids[k])] or COST[LAND]
		linked[k] = k < n and LinkAt(inst, ids[k], ids[k + 1]) ~= nil
		if k % 32 == 0 then yield() end
	end
	for k = n + 1, #costs do costs[k], linked[k] = nil, nil end
	local function Seen(i, j) -- (i < j); a hand link's leg is taken as it is (both its ends turns)
		local worst = 0
		for k = i + 1, j do
			worst = max(worst, costs[k])
			if linked[k - 1] then return false end
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

-- The drawn line along a run of the way's points that crosses rough ground (the parts' places, a cliff's foot or a
-- bump's top among them: the line needn't touch them): the cheapest way over the ~4-yd cells (8 a chunk side) in a
-- corridor TUNE.corridor chunks either side of the run, rough cells dearer than open ground and sheer ones dearer
-- still (so it's over them only where there's no way round in the corridor), then pulled straight (Clear, with its
-- slack) and its points between the run's ends into out. False (out as it was) if the corridor's cells ran out
-- (CORRIDOR_POPS) or no way was found: the run stands as it is.
local CELL = 8               -- cells a chunk side (its quads)
local CORRIDOR_POPS = 40000  -- cells a corridor's search looks at, at most
local GREED = 1.5            -- the search's pull toward its goal (over 1: fewer cells looked at, a way a little longer)
local cOpen, cG, cFrom, cCost, cHeap, cSegs = {}, {}, {}, {}, { ids = {}, keys = {}, n = 0 }, {}
local cS, cO = {}, {} -- the corridor's chunks' rough bits (Walk.RoughChunk: false, none), each looked up once
local cLists, cCells = {}, {} -- cSegs' lists, kept to use again (a search's garbage: test_route_capped); the way's cells
local CKEY = 16384     -- a cell's key: cx * CKEY + cy (cells a continent side: 64 tiles x 16 chunks x 8 = 8192)
local function Corridor(inst, run, out, yield, soft)
	local RoughChunk, RoughQuad = Walk.RoughChunk, Walk.RoughQuad
	local R = TUNE.corridor * CELL
	local R2 = R * R
	local roughC, sheerC = TUNE.roughCost, soft and TUNE.sheerCost or false -- (sheer: none, till no way's found without)
	Empty(cOpen, yield); Empty(cG, yield); Empty(cFrom, yield); Empty(cCost, yield); Empty(cS, yield); Empty(cO, yield)
	Empty(cSegs, yield); Empty(cHeap.ids, yield); Empty(cHeap.keys, yield)
	cHeap.n = 0
	local lists = 0
	-- The run's legs in cells, listed in each chunk within R of them (a cell asks only its chunk's).
	local F = CHUNKS * CELL
	for i = 2, #run do
		local ax, ay, bx, by = run[i - 1].col * F, run[i - 1].row * F, run[i].col * F, run[i].row * F
		for gc = floor((min(ax, bx) - R) / CELL), floor((max(ax, bx) + R) / CELL) do -- /: never 0 (a constant)
			yield()
			for gr = floor((min(ay, by) - R) / CELL), floor((max(ay, by) + R) / CELL) do -- /: never 0 (a constant)
				local key = gc * CKEY + gr
				local l = cSegs[key]
				if not l then
					lists = lists + 1
					l = cLists[lists]
					if not l then l = { n = 0 }; cLists[lists] = l end
					l.n = 0
					cSegs[key] = l
				end
				l.n = l.n + 1
				l[l.n] = i
			end
		end
		yield()
	end
	-- A cell's cost to enter: 1 open, roughC, sheerC; false outside the corridor.
	local function Cost(cx, cy)
		local k = cx * CKEY + cy
		local c = cCost[k]
		if c ~= nil then return c end
		c = false
		local gc, gr = floor(cx / CELL), floor(cy / CELL) -- /: never 0 (a constant)
		local l = cSegs[gc * CKEY + gr]
		if l then
			local px, py = cx + 0.5, cy + 0.5
			for m = 1, l.n do
				local i = l[m]
				local ax, ay, bx, by = run[i - 1].col * F, run[i - 1].row * F, run[i].col * F, run[i].row * F
				local dx, dy = bx - ax, by - ay
				local L2 = dx * dx + dy * dy
				local t = L2 > 0 and max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / L2)) or 0 -- /: never 0 (L2 > 0)
				if (ax + dx * t - px) ^ 2 + (ay + dy * t - py) ^ 2 <= R2 then
					local ck = gc * CKEY + gr
					local s, o = cS[ck], cO[ck]
					if s == nil then
						s, o = RoughChunk(inst, gc, gr)
						s = s or false
						cS[ck], cO[ck] = s, o
					end
					local qx, qy = cx - gc * CELL, cy - gr * CELL
					if not s then c = 1
					elseif RoughQuad(s, o + 11, qx, qy) then c = sheerC
					else c = RoughQuad(s, o, qx, qy) and roughC or 1 end
					break
				end
			end
		end
		cCost[k] = c
		return c
	end
	local p, q = run[1], run[#run]
	local sx, sy, gx, gy = floor(p.col * F), floor(p.row * F), floor(q.col * F), floor(q.row * F)
	local start, goal = sx * CKEY + sy, gx * CKEY + gy
	cG[start] = 0
	Push(cHeap, start, 0)
	local pops, found = 0, false
	while cHeap.n > 0 do
		local u = Pop(cHeap)
		if u == goal then
			found = true
			break
		end
		if not cOpen[u] then
			cOpen[u] = true
			pops = pops + 1
			if pops > CORRIDOR_POPS then return false end
			yield()
			local ux = floor(u / CKEY) -- /: never 0 (a constant)
			local uy = u - ux * CKEY
			for ddx = -1, 1 do
				for ddy = -1, 1 do
					if ddx ~= 0 or ddy ~= 0 then
						local vx, vy = ux + ddx, uy + ddy
						local v = vx * CKEY + vy
						local c = v == goal and 1 or Cost(vx, vy)
						-- (a diagonal only where both its sides are in the corridor: no corner cut out of it)
						if c and not cOpen[v] and (ddx == 0 or ddy == 0 or Cost(ux + ddx, uy) and Cost(ux, uy + ddy)) then
							local ng = cG[u] + ((ddx ~= 0 and ddy ~= 0) and 1.4142 or 1) * c
							if not cG[v] or ng < cG[v] then
								cG[v], cFrom[v] = ng, u
								Push(cHeap, v, ng + GREED * sqrt((vx - gx) ^ 2 + (vy - gy) ^ 2))
							end
						end
					end
				end
			end
		end
	end
	if not found then return false end
	-- The cells from the start's on (its own left out: p is there), then pulled straight: from where it's got to, on
	-- to the furthest cell in clear sight (a gallop, then halved back), or the next where none is (over rough ground).
	local cells, n = cCells, 0
	local u = goal
	while u ~= start do
		n = n + 1
		cells[n] = u
		u = cFrom[u]
		if n % 64 == 0 then yield() end
	end
	-- (n: the way's cells, goal first: cells[n] is the first after the start; past n, an earlier way's)
	local function Centre(m)
		local c = cells[m]
		local cx = floor(c / CKEY) -- /: never 0 (a constant)
		return (cx + 0.5) / F, (c - cx * CKEY + 0.5) / F -- /: never 0 (a constant)
	end
	local function Seen(ax, ay, m)
		yield()
		local bx, by = Centre(m)
		return Clear(inst, ax * CHUNKS, ay * CHUNKS, bx * CHUNKS, by * CHUNKS, yield)
	end
	local ax, ay, at = p.col, p.row, n + 1 -- (at: the cell index got to; n + 1 the start's)
	while at > 1 do
		if Clear(inst, ax * CHUNKS, ay * CHUNKS, q.col * CHUNKS, q.row * CHUNKS, yield) then break end
		local ok, step, bad = at - 1, 1, nil
		if Seen(ax, ay, ok) then
			while true do
				local m = max(1, ok - step)
				if m == ok then break end
				if not Seen(ax, ay, m) then
					bad = m
					break
				end
				ok, step = m, step * 2
			end
			while bad and ok - bad > 1 do
				local mid = floor((ok + bad) / 2)
				if Seen(ax, ay, mid) then ok = mid else bad = mid end
			end
		end
		if ok == 1 then break end -- (the goal's cell: q follows)
		ax, ay = Centre(ok)
		out[#out + 1] = { inst = inst, col = ax, row = ay }
		at = ok
		yield()
	end
	return true
end


-- Each corner rounded off: the legs cut back ROUND chunks from it (half a leg at most, so neighbours
-- meet and never cross) and joined by a quadratic Bezier whose control is the corner. Lazier than
-- Chaikin's (which cut a quarter of a leg a pass): the line reads as a path walked, not turned sharply.
-- Ends kept.
local function Round(inst, pts, yield)
	local n = #pts
	if n < 3 then return pts end
	local out = { pts[1] }
	local curve = {}
	for i = 2, n - 1 do
		yield()
		local p, a, b = pts[i], pts[i - 1], pts[i + 1]
		local la, lb = sqrt((a.col - p.col) ^ 2 + (a.row - p.row) ^ 2), sqrt((b.col - p.col) ^ 2 + (b.row - p.row) ^ 2)
		local d = (p.link or a.link and b.link) and 0 or min(TUNE.round / CHUNKS, la / 2, lb / 2)
		if d > 0 and ((p.col - a.col) * (b.col - p.col) + (p.row - a.row) * (b.row - p.row)) > ROUND_COS * la * lb then d = 0 end
		local done = false
		while d > 0.25 / CHUNKS and not done do -- (a leg of none, or a link's end: the corner stands)
			local sx, sy = p.col + (a.col - p.col) / la * d, p.row + (a.row - p.row) / la * d -- /: never 0 (d > 0: la, lb > 0)
			local ex, ey = p.col + (b.col - p.col) / lb * d, p.row + (b.row - p.row) / lb * d -- /: never 0 (d > 0: la, lb > 0)
			local ok, px, py = true, sx, sy
			local steps = TUNE.roundSteps
			for k = 0, steps do
				local t = k / steps -- /: never 0 (roundSteps >= 1)
				local u = 1 - t
				local x, y = u * u * sx + 2 * u * t * p.col + t * t * ex, u * u * sy + 2 * u * t * p.row + t * t * ey
				curve[k + 1] = { inst = inst, col = x, row = y }
				if k > 0 and ok then
					yield()
					ok = Clear(inst, px * CHUNKS, py * CHUNKS, x * CHUNKS, y * CHUNKS, yield)
				end
				px, py = x, y
			end
			if ok then
				for k = 1, steps + 1 do out[#out + 1] = curve[k] end
				done = true
			else
				d = d / 2
			end
		end
		if not done then out[#out + 1] = p end
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
	ids = Corners(inst, ids, yield)
	yield()
	ids = Straighten(inst, ids, yield)
	yield()
	if trace then trace.turns = ids end
	-- The nodes' places, a hand link's legs at its ends' exact places (a bridge's deck, a lift's shaft); then the
	-- start and goal themselves in place of the first and last (short of the goal: on from the last node straight).
	local n, LinkAt, Pos = #ids, Walk.LinkAt, Walk.Pos
	local at = {}
	for i = 1, n do
		local col, row = Pos(inst, ids[i])
		at[i] = { inst = inst, col = col, row = row }
		if i % 16 == 0 then yield() end
	end
	yield()
	for i = 1, n - 1 do
		if i % 32 == 0 then yield() end
		local ax, ay, bx, by = LinkAt(inst, ids[i], ids[i + 1])
		if ax then
			at[i] = { inst = inst, col = ax, row = ay, link = true }
			at[i + 1] = { inst = inst, col = bx, row = by, link = true }
		end
	end
	local pts = { { inst = inst, col = c1, row = r1 } }
	if at[1].link then pts[2] = at[1] end
	for i = 2, partial and n or n - 1 do pts[#pts + 1] = at[i] end
	if not partial and n > 1 and at[n].link then pts[#pts + 1] = at[n] end
	pts[#pts + 1] = { inst = inst, col = c2, row = r2 }
	yield()
	-- The line: runs of the points between hand links (a link's leg, and a partial way's last, drawn as they are),
	-- each as it stands where all its legs keep off rough ground, else along its corridor.
	local fine = { pts[1] }
	-- (Each stretch of legs over rough ground with a clear leg either side, stretches that close merged: its ends
	-- then on open ground, where the line may meet the way's own points without a turn back to reach them.)
	local clear = {}
	local function Flush(a, b) -- (pts[a] is in fine already)
		for k = a + 1, b do
			yield()
			clear[k] = Clear(inst, pts[k - 1].col * CHUNKS, pts[k - 1].row * CHUNKS, pts[k].col * CHUNKS, pts[k].row * CHUNKS, yield)
		end
		local k = a + 1
		while k <= b do
			if clear[k] then
				fine[#fine + 1] = pts[k]
				k = k + 1
			else
				local e = k -- (on while the next three legs aren't all clear: a stretch near enough is this one's)
				while e < b and not ((e + 1 > b or clear[e + 1]) and (e + 2 > b or clear[e + 2]) and (e + 3 > b or clear[e + 3])) do
					e = e + 1
				end
				-- legs k..e: from pts[k - 2] (a clear leg before, if any) to pts[e + 1] (one after, if any)
				local s0, s1 = max(a, k - 2), min(b, e + 1)
				local run, was = {}, #fine
				if s0 < k - 1 then fine[#fine] = nil; was = was - 1 end -- (pts[k - 1] goes: the corridor passes it by)
				for m = s0, s1 do run[#run + 1] = pts[m] end
				if not Corridor(inst, run, fine, yield) and not Corridor(inst, run, fine, yield, true) then
					for m = #fine, was + 1, -1 do fine[m] = nil end
					for m = s0 + 1, s1 - 1 do fine[#fine + 1] = pts[m] end
				end
				fine[#fine + 1] = pts[s1]
				k = s1 + 1
			end
		end
		for m = a + 1, b do clear[m] = nil end
	end
	local a = 1
	for i = 2, #pts do
		if (pts[i - 1].link and pts[i].link) or (partial and i == #pts) then
			Flush(a, i - 1)
			fine[#fine + 1] = pts[i]
			a = i
		end
	end
	Flush(a, #pts)
	yield()
	local way = Round(inst, fine, yield)
	local out = { way[1] }
	for i = 2, #way - 1 do -- (no leg of nothing between: a detour's or a curve's point on its neighbour; the ends kept)
		local p, last = way[i], out[#out]
		if (p.col - last.col) ^ 2 + (p.row - last.row) ^ 2 > 1e-10 then out[#out + 1] = p end
	end
	if #way > 1 then out[#out + 1] = way[#way] end
	return out, partial, capped
end
