-- The way you'd walk from one place to another on a map, over Atlas.Walk's terrain chunks (16 a tile side,
-- ~33 yd): A* around cliffs, mountains and lava and (when it's shorter) around lakes; line of sight
-- straightens it, and its corners are rounded off. The search alone, no state between calls but its reused
-- tables: model/Route.lua runs it in a Runtime.Job (yield: Runtime.Yield) and keeps the result up to date;
-- the web demo (demo/server.py /api/route) runs it whole, with a trace of what it did.

local _, ns = ...
local Atlas = ns.Atlas or {}; ns.Atlas = Atlas
local Walk = Atlas.Walk
local Route = {}
Atlas.Route = Route

local CHUNKS = 16                   -- a tile's side (Atlas.Walk.CHUNKS)
local SPAN = 1024                   -- node id = gc * SPAN + gr (global chunk column, row)
local BLOCKED, LAND = 0, 1
local COST = { [LAND] = 1, [2] = 3, [3] = 25 } -- a chunk crossed: swimming is slow, magma and slime hurt
local MAX_NODES = 60000             -- give up past this many
local PAD, PAD_SHARE = 24, 0.6      -- search box: start and goal's box, grown by this many chunks or this share of the distance
local GAP, GAP_SHARE = 8, 0.25      -- no way all the way: the way to the nearest chunk it reaches, if this close (chunks, or share of the distance), then straight
local ROUND = 5                     -- chunks a corner is cut back along each leg (at most half the leg) and rounded off: a walking line, not a polygon
local ROUND_STEPS = 3               -- the points of a rounded corner's curve, less one
local KEEP_NODES = 8192             -- a search's tables kept for the next (emptied first) while it closed no more than this
Route.CHUNKS, Route.SPAN, Route.COST, Route.MAX_NODES = CHUNKS, SPAN, COST, MAX_NODES

local SQRT2 = math.sqrt(2)
local function NoYield() end

local function Class(inst, gc, gr) return (Walk.Cell(inst, gc, gr)) end

-- A search's tables: g (a node's cost so far, negated less one once it's closed: no closed set), parent,
-- and a binary heap of (node, its f when pushed): a node found again by a cheaper way is pushed again,
-- and its older entries skipped (closed). Kept from search to search, so a stray's makes no garbage.
local gs, parents, heap, key, ways = {}, {}, {}, {}, {}

local function Empty(t, yield)
	local n = 0
	for k in pairs(t) do
		t[k] = nil
		n = n + 1
		if n % 256 == 0 then yield() end
	end
end

-- A*, from chunk (sc, sr) to (gc, gr), a node at a time between yields. The chunks along the way, start
-- first, or nil. With no way there (a hilltop it can't see the way up), the way to as near as it got, and
-- true. Third: it gave up at MAX_NODES. trace (or nil): .closed gets each node closed, in order; .nodes
-- their count.
local function Search(inst, sc, sr, gc, gr, yield, trace)
	local Around, DIRS = Walk.Around, Walk.DIRS -- (the 8 ways, in the order Around hands them)
	local links = Walk.Links(inst) -- (tunnels, bridges, lifts: any length, out of the box too)
	local g, parent = gs, parents
	Empty(g, yield)
	Empty(parent, yield)
	Empty(heap, yield)
	Empty(key, yield)
	local closed = trace and {}
	local d = math.sqrt((gc - sc) ^ 2 + (gr - sr) ^ 2)
	local pad = math.max(PAD, d * PAD_SHARE)
	local c0, c1 = math.min(sc, gc) - pad, math.max(sc, gc) + pad
	local r0, r1 = math.min(sr, gr) - pad, math.max(sr, gr) + pad
	local goal = gc * SPAN + gr
	g[sc * SPAN + sr], heap[1], key[1] = 0, sc * SPAN + sr, d
	local function Push(id, f)
		local i = #heap + 1
		heap[i], key[i] = id, f
		while i > 1 do
			local p = math.floor(i / 2)
			if key[p] <= key[i] then break end
			heap[p], heap[i], key[p], key[i] = heap[i], heap[p], key[i], key[p]
			i = p
		end
	end
	local function Pop()
		local top, n = heap[1], #heap
		heap[1], key[1] = heap[n], key[n]
		heap[n], key[n] = nil, nil
		n = n - 1
		local i = 1
		while true do
			local l, m = i * 2, i
			if l <= n and key[l] < key[m] then m = l end
			if l + 1 <= n and key[l + 1] < key[m] then m = l + 1 end
			if m == i then break end
			heap[m], heap[i], key[m], key[i] = heap[i], heap[m], key[i], key[m]
			i = m
		end
		return top
	end
	local function Way(id)
		local back = {}
		while id do
			back[#back + 1] = id
			id = parent[id]
		end
		local out, n = {}, #back
		for i = 1, n do out[i] = back[n + 1 - i] end
		return out
	end
	local near, nearD = sc * SPAN + sr, d -- the nearest it's got
	local count, found = 0, nil
	while #heap > 0 and count < MAX_NODES do
		local id = Pop()
		if id == goal then
			found = Way(id)
			break
		end
		local gi = g[id]
		if gi >= 0 then -- (not closed: a cheaper way's entry was popped before this one)
			g[id] = -gi - 1
			count = count + 1
			if closed then closed[count] = id end
			local c, r = math.floor(id / SPAN), id % SPAN
			local h = math.sqrt((gc - c) ^ 2 + (gr - r) ^ 2)
			if h < nearD then near, nearD = id, h end
			Around(inst, c, r, ways)
			for k = 1, 8 do
				local class = ways[k]
				if class then
					local dir = DIRS[k]
					local nc, nr = c + dir[1], r + dir[2]
					local nid = nc * SPAN + nr
					local gn = g[nid]
					if not (gn and gn < 0) and nc >= c0 and nc <= c1 and nr >= r0 and nr <= r1 then
						local ng = gi + (k > 4 and SQRT2 or 1) * COST[class]
						if not gn or ng < gn then
							g[nid], parent[nid] = ng, id
							Push(nid, ng + math.sqrt((gc - nc) ^ 2 + (gr - nr) ^ 2))
						end
					end
				end
			end
			local ls = links[id]
			if ls then
				for k = 1, #ls do
					local nid = ls[k][1]
					local gn = g[nid]
					if not (gn and gn < 0) then
						local ng = gi + ls[k][2] * COST[LAND]
						if not gn or ng < gn then
							g[nid], parent[nid] = ng, id
							local nc, nr = math.floor(nid / SPAN), nid % SPAN
							Push(nid, ng + math.sqrt((gc - nc) ^ 2 + (gr - nr) ^ 2))
						end
					end
				end
			end
		end
		yield() -- (a closed node's entry too: a run of them is a node's work)
	end
	local capped = count >= MAX_NODES
	local partial
	if not found and nearD <= math.max(GAP, d * GAP_SHARE) and nearD < d then found, partial = Way(near), true end
	if count > KEEP_NODES then gs, parents, heap, key = {}, {}, {}, {} end -- (not kept: MBs after a capped one)
	if trace then trace.closed, trace.nodes, trace.box = closed, count, { c0, r0, c1, r1 } end
	return found, partial, capped
end

-- Can you walk straight from chunk a to chunk b, through chunks no costlier than `worst`? Steps
-- chunk to chunk along the line, both ways round where it passes a corner exactly. Which boundary comes
-- first, (ix + 0.5) / nx or (iy + 0.5) / ny, is compared multiplied out: no divide by a count that's 0 on a
-- row or a column. yield (or nil): called each SIGHT_STEPS chunks (a long line of sight is many nodes' work).
local SIGHT_STEPS = 8
function Route.Sight(inst, ac, ar, bc, br, worst, yield)
	local CanMove = Walk.CanMove
	local dx, dy = bc - ac, br - ar
	local sx, sy = dx > 0 and 1 or -1, dy > 0 and 1 or -1
	local nx, ny = math.abs(dx), math.abs(dy)
	local c, r, ix, iy = ac, ar, 0, 0
	while ix < nx or iy < ny do
		local ex, ey = (ix + 0.5) * ny, (iy + 0.5) * nx
		if ex < ey then
			if not CanMove(inst, c, r, sx, 0) then return false end
			c, ix = c + sx, ix + 1
		elseif ey < ex then
			if not CanMove(inst, c, r, 0, sy) then return false end
			r, iy = r + sy, iy + 1
		else
			if not CanMove(inst, c, r, sx, sy) then return false end
			c, r, ix, iy = c + sx, r + sy, ix + 1, iy + 1
		end
		local k = Class(inst, c, r)
		if k == BLOCKED or COST[k] > worst then return false end
		if yield and (ix + iy) % SIGHT_STEPS == 0 then yield() end
	end
	return true
end
local Sight = Route.Sight

-- The chunks where the route turns: from each, straight on to the furthest one in sight (through
-- nothing costlier than the route itself crosses there).
local function Straighten(inst, ids, yield)
	local out, i = { ids[1] }, 1
	while i < #ids do
		local worst, j = 0, i + 1
		local best = j
		while j <= #ids do
			worst = math.max(worst, COST[Class(inst, math.floor(ids[j] / SPAN), ids[j] % SPAN)])
			yield()
			if not Sight(inst, math.floor(ids[i] / SPAN), ids[i] % SPAN, math.floor(ids[j] / SPAN), ids[j] % SPAN, worst,
				yield) then break end
			best, j = j, j + 1
		end
		out[#out + 1] = ids[best]
		i = best
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
		local la, lb = math.sqrt((a.col - p.col) ^ 2 + (a.row - p.row) ^ 2), math.sqrt((b.col - p.col) ^ 2 + (b.row - p.row) ^ 2)
		local d = math.min(ROUND / CHUNKS, la / 2, lb / 2)
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

-- In a different region from the start (Walk.Region: no walk joins them): the chunk nearest the goal in the
-- start's region, if one is within reach (GAP chunks, or GAP_SHARE of the way: as near as a search that gave
-- up would have gone on from); nil if none. Rings out from the goal, so the first ring with one has the nearest
-- but for a ring's corners: the ring after is looked through too.
local function Nearest(inst, region, sc, sr, gc, gr, yield)
	local reach = math.floor(math.max(GAP, math.sqrt((gc - sc) ^ 2 + (gr - sr) ^ 2) * GAP_SHARE))
	local Region = Walk.Region
	local best, bc, br, last
	for r = 1, reach do
		if last and r > last then break end
		for dc = -r, r do
			local step = (dc == -r or dc == r) and 1 or 2 * r -- (the ring's edge: whole columns at its sides)
			for dr = -r, r, step do
				if Region(inst, gc + dc, gr + dr) == region then
					local d = dc * dc + dr * dr
					if not best or d < best then best, bc, br = d, gc + dc, gr + dr end
				end
			end
		end
		if best and not last then last = math.ceil(math.sqrt(best)) end
		yield()
	end
	return bc, br
end

-- The route from tile position (c1, r1) to (c2, r2), from their chunks to stand on (sc, sr) and (gc, gr)
-- (Walk.Snap): MM.Pos[] from the one to the other, and whether it's partial; nil if there's none. Third: the
-- search gave up at MAX_NODES. Where the regions say no walk joins them, no search: the way to the nearest place
-- you can walk to (partial), or none at once. yield (or nil): called between bits of work. trace (or nil):
-- Search's, and .raw (the chunks A* found) and .turns (where the straightened way turns), chunk ids; .regions
-- (the start's, the goal's) and .goal (the chunk searched for instead of the goal's, or none) where they differ.
function Route.Find(inst, c1, r1, sc, sr, gc, gr, c2, r2, yield, trace)
	yield = yield or NoYield
	local rs, rg = Walk.Region(inst, sc, sr), Walk.Region(inst, gc, gr)
	local instead
	if rs and rg and rs ~= rg then
		local nc, nr = Nearest(inst, rs, sc, sr, gc, gr, yield)
		if trace then trace.regions, trace.goal = { rs, rg }, nc and { nc, nr } end
		if not nc then return nil, nil, false end
		gc, gr, instead = nc, nr, true
	end
	local ids, partial, capped = Search(inst, sc, sr, gc, gr, yield, trace)
	partial = partial or instead
	if not ids then return nil, nil, capped end
	if trace then trace.raw = ids end
	ids = Straighten(inst, ids, yield)
	if trace then trace.turns = ids end
	local pts = { { inst = inst, col = c1, row = r1 } }
	for i = 2, partial and #ids or #ids - 1 do -- short of the goal: on from the last chunk straight
		local id = ids[i]
		pts[#pts + 1] = { inst = inst, col = (math.floor(id / SPAN) + 0.5) / CHUNKS, row = (id % SPAN + 0.5) / CHUNKS }
	end
	pts[#pts + 1] = { inst = inst, col = c2, row = r2 }
	return Round(inst, pts), partial, capped
end
