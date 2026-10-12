-- Path mode's route: the way you'd walk to your target, around cliffs,
-- mountains and lava and (when it's shorter) around lakes, over the terrain
-- chunks in Data/Walk.lua (~33 yards each). A* finds it a slice per frame,
-- line of sight straightens it, and its corners are rounded off. Without a
-- route (no data, nowhere to stand, nothing found) Path.lua draws its
-- straight line.

local ADDON, ns = ...
local state = ns.state

local CHUNKS = 16                  -- per tile
local W = 1024                     -- node id = gc * W + gr (global chunk column, row)
local BLOCKED, LAND, WATER = 0, 1, 2
local COST = { [LAND] = 1, [WATER] = 3, [3] = 25 } -- per chunk crossed: swimming is slow, magma and slime hurt
local SLICE_MS = 1                 -- A*'s time per frame
local MAX_NODES = 60000            -- give up (straight line) past this many
local PAD, PAD_SHARE = 24, 0.6     -- search box: start and goal's box, grown by this many chunks or this share of the distance
local SNAP = 4                     -- chunks to look around a spot you can't stand on (a bridge, a building) for one you can
local GAP, GAP_SHARE = 8, 0.25     -- no way all the way: the route to the nearest chunk it reaches, if this close (chunks, or share of the distance), then straight
local REPLAN_OFF = 3               -- chunks off the route before it's found again
local RETRY_MOVED = 12             -- chunks you move before a target with no route is tried again
local GOAL_SLACK = 2               -- chunks the target can move (an area's nearest edge slides as you go) and keep its route
local KEEP_SHOWN = 8               -- ...and still show it while the new one's found
local SMOOTH = 2                   -- corner-rounding passes

local walk = MagicMap_Walk or {}
local expanded = {} -- [inst][tile key] = its 256 chunk letters, run-length decoded

local function Tile(inst, key)
	local cache = expanded[inst]
	if not cache then
		cache = {}
		expanded[inst] = cache
	end
	local s = cache[key]
	if s == nil then
		local enc = walk[inst] and walk[inst][key]
		if enc then
			local parts = {}
			for letter, n in enc:gmatch("(%a)(%d*)") do parts[#parts + 1] = letter:rep(tonumber(n) or 1) end
			s = table.concat(parts)
		end
		cache[key] = s or false
		s = s or false
	end
	return s
end

-- A chunk's value: class + 4 (can cross east) + 8 (south); 0 off the terrain.
local function Cell(inst, gc, gr)
	if gc < 0 or gr < 0 then return 0 end
	local s = Tile(inst, math.floor(gc / CHUNKS) * 64 + math.floor(gr / CHUNKS))
	if not s then return 0 end
	return s:byte((gr % CHUNKS) * CHUNKS + gc % CHUNKS + 1) - 97
end

local function Class(v) return v % 4 end
local function East(v) return v % 8 >= 4 end
local function South(v) return v >= 8 end

-- Can you step from (gc, gr) one chunk over by (dx, dy), each -1, 0 or 1 (one of them 0)?
local function Step(inst, gc, gr, dx, dy)
	if dx == 1 then return East(Cell(inst, gc, gr)) end
	if dx == -1 then return East(Cell(inst, gc - 1, gr)) end
	if dy == 1 then return South(Cell(inst, gc, gr)) end
	return South(Cell(inst, gc, gr - 1))
end

local function Open(inst, gc, gr) return Class(Cell(inst, gc, gr)) ~= BLOCKED end

-- (dx, dy) any of the 8 ways: diagonals by either way round.
local function CanMove(inst, gc, gr, dx, dy)
	if dx == 0 or dy == 0 then return Step(inst, gc, gr, dx, dy) and Open(inst, gc + dx, gr + dy) end
	if not Open(inst, gc + dx, gr + dy) then return false end
	return (Step(inst, gc, gr, dx, 0) and Open(inst, gc + dx, gr) and Step(inst, gc + dx, gr, 0, dy))
		or (Step(inst, gc, gr, 0, dy) and Open(inst, gc, gr + dy) and Step(inst, gc, gr + dy, dx, 0))
end

-- The nearest chunk you can stand on to (gc, gr), within SNAP.
local function Snap(inst, gc, gr)
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
end

-- In a coroutine, hand the frame back once this slice has had SLICE_MS.
local sliceStart = 0
local function Pace()
	if coroutine.running() and debugprofilestop() - sliceStart > SLICE_MS then
		coroutine.yield()
		sliceStart = debugprofilestop()
	end
end

local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
local SQRT2 = math.sqrt(2)

-- A*, from chunk (sc, sr) to (gc, gr); yields between slices when run as a
-- coroutine. The chunks along the way, start first, or nil. With no way
-- there (a hilltop it can't see the way up), the way to as near as it got.
local function Search(inst, sc, sr, gc, gr)
	local d = math.sqrt((gc - sc) ^ 2 + (gr - sr) ^ 2)
	local pad = math.max(PAD, d * PAD_SHARE)
	local c0, c1 = math.min(sc, gc) - pad, math.max(sc, gc) + pad
	local r0, r1 = math.min(sr, gr) - pad, math.max(sr, gr) + pad
	local goal = gc * W + gr
	local g, parent, closed = { [sc * W + sr] = 0 }, {}, {}
	-- A binary heap of (node, its f when pushed): a node found again by a
	-- cheaper way is pushed again, and its older entries skipped (closed).
	local heap, key = { sc * W + sr }, { d }
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
		local out = {}
		while id do
			table.insert(out, 1, id)
			id = parent[id]
		end
		return out
	end
	local near, nearD = sc * W + sr, d -- the nearest it's got
	local count = 0
	while #heap > 0 and count < MAX_NODES do
		local id = Pop()
		if id == goal then return Way(id) end
		if not closed[id] then
			closed[id] = true
			count = count + 1
			local c, r = math.floor(id / W), id % W
			local h = math.sqrt((gc - c) ^ 2 + (gr - r) ^ 2)
			if h < nearD then near, nearD = id, h end
			for _, dir in ipairs(DIRS) do
				local nc, nr = c + dir[1], r + dir[2]
				local nid = nc * W + nr
				if not closed[nid] and nc >= c0 and nc <= c1 and nr >= r0 and nr <= r1 and CanMove(inst, c, r, dir[1], dir[2]) then
					local step = (dir[1] ~= 0 and dir[2] ~= 0) and SQRT2 or 1
					local ng = g[id] + step * COST[Class(Cell(inst, nc, nr))]
					if not g[nid] or ng < g[nid] then
						g[nid], parent[nid] = ng, id
						Push(nid, ng + math.sqrt((gc - nc) ^ 2 + (gr - nr) ^ 2))
					end
				end
			end
			if count % 50 == 0 then Pace() end
		end
	end
	if nearD <= math.max(GAP, d * GAP_SHARE) and nearD < d then return Way(near) end
end

-- Can you walk straight from chunk a to chunk b, through chunks no costlier
-- than `worst`? Steps chunk to chunk along the line (both ways round where
-- it passes a corner exactly).
local function Sight(inst, ac, ar, bc, br, worst)
	local dx, dy = bc - ac, br - ar
	local sx, sy = dx > 0 and 1 or -1, dy > 0 and 1 or -1
	local nx, ny = math.abs(dx), math.abs(dy)
	local c, r, ix, iy = ac, ar, 0, 0
	while ix < nx or iy < ny do
		-- How far along the next column / row boundary is. (WoW's Lua errors
		-- on division by zero, where plain Lua gives inf.)
		local ex = nx > 0 and (ix + 0.5) / nx or math.huge
		local ey = ny > 0 and (iy + 0.5) / ny or math.huge
		if ex < ey then
			if not Step(inst, c, r, sx, 0) then return false end
			c, ix = c + sx, ix + 1
		elseif ey < ex then
			if not Step(inst, c, r, 0, sy) then return false end
			r, iy = r + sy, iy + 1
		else
			if not CanMove(inst, c, r, sx, sy) then return false end
			c, r, ix, iy = c + sx, r + sy, ix + 1, iy + 1
		end
		local k = Class(Cell(inst, c, r))
		if k == BLOCKED or COST[k] > worst then return false end
	end
	return true
end

-- The chunks where the route turns: from each, straight on to the furthest
-- one in sight (through nothing costlier than the route itself crosses there).
local function Straighten(inst, ids)
	local out, i = { ids[1] }, 1
	while i < #ids do
		local worst, j = 0, i + 1
		local best = j
		while j <= #ids do
			worst = math.max(worst, COST[Class(Cell(inst, math.floor(ids[j] / W), ids[j] % W))])
			Pace()
			if not Sight(inst, math.floor(ids[i] / W), ids[i] % W, math.floor(ids[j] / W), ids[j] % W, worst) then break end
			best, j = j, j + 1
		end
		out[#out + 1] = ids[best]
		i = best
	end
	return out
end

-- Chaikin's corner cutting, ends kept.
local function Round(pts)
	for _ = 1, SMOOTH do
		if #pts < 3 then return pts end
		local out = { pts[1] }
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			if i > 1 then out[#out + 1] = { a[1] * 0.75 + b[1] * 0.25, a[2] * 0.75 + b[2] * 0.25 } end
			if i < #pts - 1 then out[#out + 1] = { a[1] * 0.25 + b[1] * 0.75, a[2] * 0.25 + b[2] * 0.75 } end
		end
		out[#out + 1] = pts[#pts]
		pts = out
	end
	return pts
end

-- The route from tile position (c1, r1) to (c2, r2) on instance inst, as
-- { { col, row }, ... } from the one to the other; nil if there's none.
-- Runs to the end unless it's in a coroutine (then a slice at a time).
local function Find(inst, c1, r1, c2, r2)
	if not walk[inst] then return nil end
	sliceStart = debugprofilestop()
	local sc, sr = Snap(inst, math.floor(c1 * CHUNKS), math.floor(r1 * CHUNKS))
	local gc, gr = Snap(inst, math.floor(c2 * CHUNKS), math.floor(r2 * CHUNKS))
	if not (sc and gc) then return nil end
	local ids = Search(inst, sc, sr, gc, gr)
	if not ids then return nil end
	ids = Straighten(inst, ids)
	local pts = { { c1, r1 } }
	local last = ids[#ids] == gc * W + gr and #ids - 1 or #ids -- short of the goal: on from the last chunk straight
	for i = 2, last do
		pts[#pts + 1] = { (math.floor(ids[i] / W) + 0.5) / CHUNKS, (ids[i] % W + 0.5) / CHUNKS }
	end
	pts[#pts + 1] = { c2, r2 }
	return Round(pts)
end
ns.FindRoute = Find -- for tests

---------------------------------------------------------------------------
-- The route to path mode's target, kept up to date: found again when the
-- target moves more than GOAL_SLACK chunks or you stray off it.
---------------------------------------------------------------------------

local route  -- { pts, inst, goal (chunk id) } once found
local job    -- { co, inst, goal } while one's being found
local failed -- { inst, goal, col, row }: no route from there; straight until the goal changes or you move on

-- How far (in chunks) tile position (c, r) is from the route, and the point
-- on it nearest you: segment index and how far along it (0-1).
local function Nearest(pts, c, r)
	local best, bi, bt
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local dx, dy = b[1] - a[1], b[2] - a[2]
		local len2 = dx * dx + dy * dy
		local t = len2 > 0 and math.max(0, math.min(1, ((c - a[1]) * dx + (r - a[2]) * dy) / len2)) or 0
		local px, py = a[1] + dx * t, a[2] + dy * t
		local d = (px - c) ^ 2 + (py - r) ^ 2
		if not best or d < best then best, bi, bt = d, i, t end
	end
	return math.sqrt(best or 0) * CHUNKS, bi, bt
end

local function Moved(c1, r1, c2, r2)
	return math.sqrt((c1 - c2) ^ 2 + (r1 - r2) ^ 2) * CHUNKS > RETRY_MOVED
end

-- Are goal chunks a and b within n chunks of each other?
local function Near(a, b, n)
	return math.abs(math.floor(a / W) - math.floor(b / W)) <= n and math.abs(a % W - b % W) <= n
end

local function For(x, inst, goal, n) return x and x.inst == inst and Near(x.goal, goal, n) end

local function StepJob()
	local ok, pts = coroutine.resume(job.co)
	if not ok then ns.Print("route finding failed: " .. tostring(pts)) end
	if not ok or coroutine.status(job.co) == "dead" then
		if ok and pts then
			route, failed = { pts = pts, inst = job.inst, goal = job.goal }, nil
		else
			route, failed = nil, { inst = job.inst, goal = job.goal, col = job.col, row = job.row }
		end
		job = nil
	end
end

local out, you, onto, dest = {}, {}, {}, {} -- reused: the route from where you are now

-- The way from you to target t (a ns.FrameTarget()), as tile positions,
-- you first: the route trimmed to where you are. Nil: draw it straight.
-- Second: the route it's cut from, the same table until it's found again.
function ns.RouteTo(t)
	local inst = state.map
	if not (t and state.playerCol and walk[inst]) then
		route, job = nil, nil
		return nil
	end
	local pc, pr = state.playerCol, state.playerRow
	local goal = math.floor(t.col * CHUNKS) * W + math.floor(t.row * CHUNKS)
	if not (For(route, inst, goal, GOAL_SLACK) and Nearest(route.pts, pc, pr) <= REPLAN_OFF)
		and not For(job, inst, goal, GOAL_SLACK)
		and not (For(failed, inst, goal, GOAL_SLACK) and not Moved(failed.col, failed.row, pc, pr)) then
		local c2, r2 = t.col, t.row
		job = { inst = inst, goal = goal, col = pc, row = pr,
			co = coroutine.create(function() return Find(inst, pc, pr, c2, r2) end) }
	end
	if job then StepJob() end
	if not For(route, inst, goal, job and KEEP_SHOWN or GOAL_SLACK) then return nil end
	local pts = route.pts
	local _, i, k = Nearest(pts, pc, pr)
	wipe(out)
	you[1], you[2] = pc, pr
	out[1] = you
	local a, b = pts[i], pts[i + 1]
	if k > 0 and k < 1 then
		onto[1], onto[2] = a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k
		out[2] = onto
	end
	for j = i + 1, #pts - 1 do out[#out + 1] = pts[j] end
	dest[1], dest[2] = t.col, t.row -- as it is now (an area's nearest edge drifts as you go)
	out[#out + 1] = dest
	return out, pts
end
