-- The way to the target (the spike's Route.lua): the way you'd walk there, around cliffs,
-- mountains and lava and (when it's shorter) around lakes, over Atlas.Walk's terrain chunks
-- (16 a tile side, ~33 yd). A* finds it in a Runtime.Job, SLICE_MS a frame (none while the view moves:
-- Focus.moving, the map's layouts have the frame); line of sight
-- straightens it, and its corners are rounded off. Found again when the target moves more than
-- GOAL_SLACK chunks or you stray REPLAN_OFF off it; the old one stays meanwhile while its goal
-- is within KEEP_SHOWN (spike-bugs M1: no straight frame while re-routing). A search that gave up at
-- MAX_NODES (a goal no way reaches, as a rule: ~18 s of slices, ~4.4 MB) is searched again for that
-- goal only once you've come half the way it spanned (the lead's decision at the M3 review: the spike
-- searched again each REPLAN_OFF stray or RETRY_MOVED moved, riding past the frame and allocation budgets).
-- Model.Route(): the way from you, cut to where you are: you, then the furthest point ahead you
-- can walk straight to, on to the target as it is now (an area's nearest edge drifts as you go).
-- nil: none to show (no target, you're in its area, not on its map, the map hidden: a search under
-- way stops till one's wanted again; or the first way still being found). straight: you and the
-- target only, where the walk grid has nowhere to stand (no data) or no way was found; partial: no
-- way all the way, it ends where it got nearest, then straight on. The same table while the way is
-- the same: its first point is Model.you (moved in place), its last the target's pos. Same
-- instance only: yours and the target's.

local _, ns = ...
local Atlas, Model, Runtime = ns.Atlas, ns.Model, ns.Runtime
local Walk = Atlas.Walk

-- (Route.lua:11-25)
local CHUNKS = 16                   -- a tile's side (Atlas.Walk.CHUNKS)
local SPAN = 1024                   -- node id = gc * SPAN + gr (global chunk column, row)
local BLOCKED, LAND = 0, 1
local COST = { [LAND] = 1, [2] = 3, [3] = 25 } -- a chunk crossed: swimming is slow, magma and slime hurt
local SLICE_MS = 1                  -- A*'s time a frame (spike-bugs P2)
local MAX_NODES = 60000             -- give up (straight) past this many
local FRAMES = 2400                 -- a search's frames at most (Runtime.Job cancels it past them): MAX_NODES at 25 a slice, and straightening
local PAD, PAD_SHARE = 24, 0.6      -- search box: start and goal's box, grown by this many chunks or this share of the distance
local GAP, GAP_SHARE = 8, 0.25      -- no way all the way: the way to the nearest chunk it reaches, if this close (chunks, or share of the distance), then straight
local REPLAN_OFF = 3                -- chunks off the route before it's found again
local RETRY_MOVED = 12              -- chunks you move before a target with no route is tried again
local GOAL_SLACK = 2                -- chunks the target can move (an area's nearest edge slides as you go) and keep its route
local KEEP_SHOWN = 8                -- ...and still show it while the new one's found
local SMOOTH = 2                    -- corner-rounding passes
local LOOKAHEAD = 40                -- route points ahead of you checked for a straight way to them

local SQRT2 = math.sqrt(2)
local KEEP_NODES = 8192 -- a search's tables kept for the next (emptied first) while it closed no more than this

local function Class(inst, gc, gr) return (Walk.Cell(inst, gc, gr)) end

-- A search's tables: g (a node's cost so far, negated less one once it's closed: no closed set), parent,
-- and a binary heap of (node, its f when pushed): a node found again by a cheaper way is pushed again,
-- and its older entries skipped (closed). Kept from search to search, so a stray's makes no garbage.
local gs, parents, heap, key, ways = {}, {}, {}, {}, {}

local function Empty(t)
	local n = 0
	for k in pairs(t) do
		t[k] = nil
		n = n + 1
		if n % 256 == 0 then Runtime.Yield() end
	end
end

-- A*, from chunk (sc, sr) to (gc, gr), a node at a time between Runtime.Yields. The chunks along
-- the way, start first, or nil. With no way there (a hilltop it can't see the way up), the way to
-- as near as it got, and true (Route.lua:109-183). Third: it gave up at MAX_NODES.
local function Search(inst, sc, sr, gc, gr)
	local Around, DIRS = Walk.Around, Walk.DIRS -- (the 8 ways, in the order Around hands them)
	local g, parent = gs, parents
	Empty(g)
	Empty(parent)
	Empty(heap)
	Empty(key)
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
		end
		Runtime.Yield() -- (a closed node's entry too: a run of them is a node's work)
	end
	local capped = count >= MAX_NODES
	local partial
	if not found and nearD <= math.max(GAP, d * GAP_SHARE) and nearD < d then found, partial = Way(near), true end
	if count > KEEP_NODES then gs, parents, heap, key = {}, {}, {}, {} end -- (not kept: MBs after a capped one)
	return found, partial, capped
end

-- Can you walk straight from chunk a to chunk b, through chunks no costlier than `worst`? Steps
-- chunk to chunk along the line, both ways round where it passes a corner exactly (Route.lua:185-212).
-- Which boundary comes first, (ix + 0.5) / nx or (iy + 0.5) / ny, is compared multiplied out: no
-- divide by a count that's 0 on a row or a column (spike-bugs E3). yield: called each SIGHT_STEPS
-- chunks (in the search's job: a long line of sight is many nodes' work).
local SIGHT_STEPS = 8
local function Sight(inst, ac, ar, bc, br, worst, yield)
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

-- The chunks where the route turns: from each, straight on to the furthest one in sight (through
-- nothing costlier than the route itself crosses there).
local function Straighten(inst, ids)
	local out, i = { ids[1] }, 1
	while i < #ids do
		local worst, j = 0, i + 1
		local best = j
		while j <= #ids do
			worst = math.max(worst, COST[Class(inst, math.floor(ids[j] / SPAN), ids[j] % SPAN)])
			Runtime.Yield()
			if not Sight(inst, math.floor(ids[i] / SPAN), ids[i] % SPAN, math.floor(ids[j] / SPAN), ids[j] % SPAN, worst,
				Runtime.Yield) then break end
			best, j = j, j + 1
		end
		out[#out + 1] = ids[best]
		i = best
	end
	return out
end

-- Chaikin's corner cutting, ends kept.
local function Round(inst, pts)
	for _ = 1, SMOOTH do
		if #pts < 3 then return pts end
		local out = { pts[1] }
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			if i > 1 then out[#out + 1] = { inst = inst, col = a.col * 0.75 + b.col * 0.25, row = a.row * 0.75 + b.row * 0.25 } end
			if i < #pts - 1 then out[#out + 1] = { inst = inst, col = a.col * 0.25 + b.col * 0.75, row = a.row * 0.25 + b.row * 0.75 } end
		end
		out[#out + 1] = pts[#pts]
		pts = out
	end
	return pts
end

-- The route from tile position (c1, r1) to (c2, r2), from their chunks to stand on (sc, sr) and
-- (gc, gr): MM.Pos[] from the one to the other, and whether it's partial; nil if there's none. Third:
-- the search gave up at MAX_NODES.
local function Find(inst, c1, r1, sc, sr, gc, gr, c2, r2)
	local ids, partial, capped = Search(inst, sc, sr, gc, gr)
	if not ids then return nil, nil, capped end
	ids = Straighten(inst, ids)
	local pts = { { inst = inst, col = c1, row = r1 } }
	for i = 2, partial and #ids or #ids - 1 do -- short of the goal: on from the last chunk straight
		local id = ids[i]
		pts[#pts + 1] = { inst = inst, col = (math.floor(id / SPAN) + 0.5) / CHUNKS, row = (id % SPAN + 0.5) / CHUNKS }
	end
	pts[#pts + 1] = { inst = inst, col = c2, row = r2 }
	return Round(inst, pts), partial, capped
end

---------------------------------------------------------------------------------------------------
-- The route to the target, kept up to date (Route.lua:271-371).

local route  -- { pts, inst, goal (chunk id), partial, col, row, half, capped } once found
local job    -- { run (its Runtime.Job), inst, goal, col, row, half, pts?, partial?, capped? } while one's being found
local failed -- { inst, goal, col, row, half, capped }: no route from there; straight until the goal changes or you move on
-- (col, row: where it was searched from; half: half its span, in chunks, RETRY_MOVED at least; capped: it
-- gave up at MAX_NODES)
local out    -- Model.Route()'s
local cut = {} -- what out was cut from: pts, from, dest

-- How far (in chunks) tile position (c, r) is from the route, and the leg nearest it. Kept for the
-- last route and position asked (Kept's and the cut's, a frame; standing, none).
local near = {} -- pts, c, r, d, i
local function Nearest(pts, c, r)
	if near.pts == pts and near.c == c and near.r == r then return near.d, near.i end
	local best, bi
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local dx, dy = b.col - a.col, b.row - a.row
		local len2 = dx * dx + dy * dy
		local t = len2 > 0 and math.max(0, math.min(1, ((c - a.col) * dx + (r - a.row) * dy) / len2)) or 0 -- /: never 0 (len2 > 0)
		local px, py = a.col + dx * t, a.row + dy * t
		local d = (px - c) ^ 2 + (py - r) ^ 2
		if not best or d < best then best, bi = d, i end
	end
	near.pts, near.c, near.r, near.d, near.i = pts, c, r, math.sqrt(best or 0) * CHUNKS, bi
	return near.d, bi
end

-- Moved more than n chunks (RETRY_MOVED) from (c1, r1)?
local function Moved(c1, r1, c2, r2, n) return math.sqrt((c1 - c2) ^ 2 + (r1 - r2) ^ 2) * CHUNKS > (n or RETRY_MOVED) end

-- A search's result kept for its goal, from (pc, pr): one that gave up, till you've come half its way; a
-- failed one, till you've moved RETRY_MOVED; a route, while you're within REPLAN_OFF of it.
local function Kept(x, pc, pr)
	if x.capped then return not Moved(x.col, x.row, pc, pr, x.half) end
	if x.pts then return Nearest(x.pts, pc, pr) <= REPLAN_OFF end
	return not Moved(x.col, x.row, pc, pr)
end

-- Are goal chunks a and b within n chunks of each other?
local function Near(a, b, n)
	return math.abs(math.floor(a / SPAN) - math.floor(b / SPAN)) <= n and math.abs(a % SPAN - b % SPAN) <= n
end

local function For(x, inst, goal, n) return x and x.inst == inst and Near(x.goal, goal, n) end

-- A new search from (pc, pr) to (c2, r2): nowhere to stand at either end (no walk data there), no route.
local function Start(inst, goal, pc, pr, c2, r2)
	if job then Runtime.Cancel(job.run) end
	job = nil
	local sc, sr = Walk.Snap(inst, math.floor(pc * CHUNKS), math.floor(pr * CHUNKS))
	local gc, gr = Walk.Snap(inst, math.floor(c2 * CHUNKS), math.floor(r2 * CHUNKS))
	if not (sc and gc) then
		route, failed = nil, { inst = inst, goal = goal, col = pc, row = pr }
		return
	end
	local half = math.max(RETRY_MOVED, math.sqrt((c2 - pc) ^ 2 + (r2 - pr) ^ 2) * CHUNKS / 2)
	local j = { inst = inst, goal = goal, col = pc, row = pr, half = half }
	j.run = Runtime.Job("model: route", function()
		j.pts, j.partial, j.capped = Find(inst, pc, pr, sc, sr, gc, gr, c2, r2)
	end, SLICE_MS, FRAMES)
	job = j
end

-- The furthest point of the route ahead of leg i you can walk straight to from (pc, pr): its
-- index, or nil. Looked for once a route, leg and chunk you're in.
local ahead = {} -- pts, chunk, i, index
local function Ahead(inst, pts, i, pc, pr)
	local yc, yr = math.floor(pc * CHUNKS), math.floor(pr * CHUNKS)
	local here = yc * SPAN + yr
	if ahead.pts == pts and ahead.chunk == here and ahead.i == i then return ahead.index end
	local worst = math.max(COST[LAND], COST[Class(inst, yc, yr)] or 0)
	local best
	for j = i + 1, math.min(#pts, i + LOOKAHEAD) do
		if not Sight(inst, yc, yr, math.floor(pts[j].col * CHUNKS), math.floor(pts[j].row * CHUNKS), worst) then break end
		best = j
	end
	ahead.pts, ahead.chunk, ahead.i, ahead.index = pts, here, i, best
	return best
end

local function Show(way) out, cut.pts = way, nil end

-- No route wanted now (the spike's isn't asked for one): its search stopped (begun again when it is),
-- what was found kept.
local function Pause()
	if job then Runtime.Cancel(job.run) end
	job = nil
	Show(nil)
end

Model.Part(function()
	local t, you, f = Model.Target(), Model.you, Model.focus
	if not (t and you.col and not you.stale) then
		route, failed = nil, nil
		return Pause()
	end
	if t.inside or not f.shown or t.pos.inst ~= you.inst then return Pause() end
	if job and job.run.done then
		local x = { inst = job.inst, goal = job.goal, col = job.col, row = job.row, half = job.half, capped = job.capped }
		if job.pts then
			x.pts, x.partial = job.pts, job.partial
			route, failed = x, nil
		else
			route, failed = nil, x
		end
		job = nil
	end
	local inst, pc, pr, dest = you.inst, you.col, you.row, t.pos
	local goal = math.floor(dest.col * CHUNKS) * SPAN + math.floor(dest.row * CHUNKS)
	if not (For(route, inst, goal, GOAL_SLACK) and Kept(route, pc, pr)) and not For(job, inst, goal, GOAL_SLACK)
		and not (For(failed, inst, goal, GOAL_SLACK) and Kept(failed, pc, pr)) then
		Start(inst, goal, pc, pr, dest.col, dest.row)
	end
	if job then job.run.budget = f.moving and 0 or SLICE_MS end -- (the view moving: queued, its turn waits)
	if not For(route, inst, goal, job and KEEP_SHOWN or GOAL_SLACK) then
		if job then return Show(nil) end
		if not (out and out.straight and out[2] == dest) then Show({ you, dest, straight = true }) end
		return
	end
	-- Straight on from you to as far along it as you can see: no hop back onto a route found from
	-- where you were.
	local pts = route.pts
	local _, i = Nearest(pts, pc, pr)
	local from = Ahead(inst, pts, i, pc, pr) or i + 1
	if out and cut.pts == pts and cut.from == from and cut.dest == dest then return end
	cut.pts, cut.from, cut.dest = pts, from, dest
	out = { you, partial = route.partial }
	for j = from, #pts - 1 do out[#out + 1] = pts[j] end
	out[#out + 1] = dest
end)

function Model.Route() return out end
