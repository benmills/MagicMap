-- The way to the target (the spike's Route.lua): the way you'd walk there, around cliffs,
-- mountains and lava and (when it's shorter) around lakes, over Atlas.Walk's terrain chunks
-- (16 a tile side, ~33 yd). A* finds it in a Runtime.Job, SLICE_MS a frame (none while the view moves:
-- Focus.moving, the map's layouts have the frame); line of sight
-- straightens it, and its corners are rounded off. Found again when the target moves more than
-- GOAL_SLACK chunks or you stray REPLAN_OFF off it; the old one stays meanwhile while its goal
-- is within KEEP_SHOWN (spike-bugs M1: no straight frame while re-routing). A search that gave up at
-- Route.MAX_NODES (a goal no way reaches, as a rule: ~18 s of slices, ~4.4 MB) is searched again for that
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

-- (Route.lua:11-25; the search's own: atlas/Route.lua)
local Route = Atlas.Route
local CHUNKS, SPAN, COST = Route.CHUNKS, Route.SPAN, Route.COST
local LAND = 1
local SLICE_MS = 1                  -- A*'s time a frame (spike-bugs P2)
local FRAMES = 2400                 -- a search's frames at most (Runtime.Job cancels it past them): MAX_NODES at 25 a slice, and straightening
local REPLAN_OFF = 3                -- chunks off the route before it's found again
local RETRY_MOVED = 12              -- chunks you move before a target with no route is tried again
local GOAL_SLACK = 2                -- chunks the target can move (an area's nearest edge slides as you go) and keep its route
local KEEP_SHOWN = 8                -- ...and still show it while the new one's found
local LOOKAHEAD = 40                -- route points ahead of you checked for a straight way to them

local function Class(inst, gc, gr) return (Walk.Cell(inst, gc, gr)) end
local Sight = Route.Sight

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
		j.pts, j.partial, j.capped = Route.Find(inst, pc, pr, sc, sr, gc, gr, c2, r2, Runtime.Yield)
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
