-- What to go to (the spike's GetTarget, Layers.lua:1076-1180), on the map shown (Focus's instance):
-- your corpse while you're a ghost, else the quest you follow if its pin is there, else your
-- waypoint; each only while its layer is on (Focus.off: the spike's pinData, Layers.lua:1029). A
-- quest the game draws an area for is gone to the area's nearest edge, not its pin (while Quest
-- areas is on: a drawn area's, Layers.lua:1093-1097),
-- and once you're inside it you've arrived (inside: the line and edge arrow step aside): every
-- AREA_EVERY while the map shows and you're on it, where you stand is asked (Inside), a change held
-- AREA_SETTLE before it counts (no flicker at the edge: spike-bugs M1), and outside, the edge along
-- a fan of rays from you toward its pin, RAY_STEPS each, then REFINE halvings where one goes in. A
-- look's asks go on over frames: past ASKS a frame, or while the game can't tell (nil), on the next.
-- Model.Target(): the same table until it changes; false: none; nil: no Focus yet.
-- Known("corpse"), Known("waypoint"): obs.corpse and obs.waypoint, one entry or none; Model.waypointSet:
-- obs.waypointSet, the last handed.

local _, ns = ...
local Model = ns.Model

local AREA_EVERY, AREA_SETTLE = 0.25, 0.5 -- s (Layers.lua:1086-1087)
local FAN = { 0, 0.35, -0.35, 0.7, -0.7, 1.05, -1.05 } -- ray angles about the way to its pin (Layers.lua:1088)
local RAY_STEPS, REFINE = 16, 8 -- (Layers.lua:1089)
local ASKS = 32 -- Inside's asks a frame: "a few dozen" (types/observation.lua)
local CORPSE, WAYPOINT = "Your corpse", "Waypoint" -- their pins' titles (Layers.lua:513, 628)

local NONE = {}
local corpse, corpses, corpseRev = nil, NONE, 0
local waypoint, waypoints, waypointRev = nil, NONE, 0
local target
local now, oracles, asks = 0, nil, 0 -- this frame's
local titled, title -- the quest entry titled, its title

-- The followed quest's area: quest, at (the next look), inside, flipAt, pos (its edge, or its pin).
local area, want = {}, {} -- the look asked for: quest, col, row (where you are), pin, quests (obs.quests then)
local looker, looking -- the looks' coroutine (one for good, but for a look dropped half done); one under way

-- Inside, asked till it answers: past this frame's asks, or with no answer now, on the next frame.
local function Ask(quest, col, row)
	while true do
		if asks < ASKS then
			asks = asks + 1
			local v = oracles.Inside(quest, col, row)
			if v ~= nil then return v end
		end
		coroutine.yield()
	end
end

-- The nearest point of the quest's area from (pc, pr), toward its pin (cc, cr), or nil (Layers.lua:1104-1130).
local function NearestEdge(quest, pc, pr, cc, cr)
	local dx, dy = cc - pc, cr - pr
	local reach = math.sqrt(dx * dx + dy * dy) * 1.5
	if reach <= 0 then return nil end
	local base = math.atan2(dy, dx)
	local best, bc, br
	for _, off in ipairs(FAN) do
		local ux, uy = math.cos(base + off), math.sin(base + off)
		local lo = 0
		for i = 1, RAY_STEPS do
			local d = reach * i / RAY_STEPS
			if best and d >= best then break end
			if Ask(quest, pc + ux * d, pr + uy * d) then
				local hi = d
				for _ = 1, REFINE do
					local mid = (lo + hi) / 2
					if Ask(quest, pc + ux * mid, pr + uy * mid) then hi = mid else lo = mid end
				end
				best, bc, br = hi, pc + ux * hi, pr + uy * hi
				break
			end
			lo = d
		end
	end
	return bc, br
end

-- One look (Layers.lua:1139-1155): inside, held; outside, the nearest edge (none: its pin).
local function Look()
	local quest, pc, pr, pin = want.quest, want.col, want.row, want.pin
	local inside = Ask(quest, pc, pr)
	if area.inside == nil then
		area.inside = inside
	elseif inside ~= area.inside then
		area.flipAt = area.flipAt or now
		if now - area.flipAt >= AREA_SETTLE then area.inside, area.flipAt = inside, nil end
	else
		area.flipAt = nil
	end
	if not area.inside then
		local c, r = NearestEdge(quest, pc, pr, pin.col, pin.row)
		local p = area.pos
		if not c then
			area.pos = pin
		elseif not (p and p.col == c and p.row == r) then
			area.pos = { inst = pin.inst, col = c, row = r }
		end
	end
end

local function Looker()
	return coroutine.create(function()
		while true do
			Look()
			coroutine.yield(true)
		end
	end)
end

-- The followed quest's area, looked at once AREA_EVERY (from where you are then), a look till it's done; not
-- while nothing it asks about has changed since the last (where you are, its pin, the game's areas: a
-- QUEST_POI_UPDATE makes a new obs.quests) and no flip waits to settle: it would answer the same.
local function Area(e, you, quests)
	if area.quest ~= e.quest then
		area.quest, area.at, area.inside, area.flipAt, area.pos = e.quest, now, nil, nil, nil
		if looking then looker, looking = nil, false end -- (another quest's, half done)
	end
	if not looking then
		if now < area.at then return end
		area.at = now + AREA_EVERY
		if area.inside ~= nil and not area.flipAt and want.col == you.col and want.row == you.row and want.pin == e.pos
			and want.quests == quests then return end
		looking, looker = true, looker or Looker()
		want.quest, want.col, want.row, want.pin, want.quests = e.quest, you.col, you.row, e.pos, quests
	end
	local ok, done = coroutine.resume(looker)
	if not ok then
		looker, looking = nil, false
		error(done, 0)
	end
	if done then looking = false end
end

-- The followed quest whose pin is on inst, or nil.
local function Followed(inst)
	for _, e in ipairs((Model.Known("quests"))) do
		if e.followed and e.pos.inst == inst then return e end
	end
end

-- "[level] title", as its tooltip's (QuestInfo.lua:42-47).
local function Title(e)
	if e ~= titled then titled, title = e, e.level and string.format("[%d] %s", e.level, e.name) or e.name end
	return title
end

local function Set(kind, key, pos, inside, name, quest)
	local t = target
	if t and t.kind == kind and t.key == key and t.pos == pos and t.inside == inside and t.title == name then return end
	target = { kind = kind, key = key, pos = pos, inside = inside, title = name, quest = quest }
end

local function Pin(kind, pos, name)
	return { { key = kind, kind = kind, pos = pos, name = name, live = true } }
end

Model.Part(function(obs, o)
	now, oracles, asks = obs.t, o, 0
	if obs.corpse ~= nil and obs.corpse ~= corpse then
		corpse, corpseRev = obs.corpse, corpseRev + 1
		corpses = corpse and Pin("corpse", corpse, CORPSE) or NONE
	end
	if obs.waypoint ~= nil and obs.waypoint ~= waypoint then
		waypoint, waypointRev = obs.waypoint, waypointRev + 1
		waypoints = waypoint and Pin("waypoint", waypoint, WAYPOINT) or NONE
	end
	if obs.waypointSet ~= nil then Model.waypointSet = obs.waypointSet end
	local f, you = Model.focus, Model.you
	if not f then return end
	local inst, off = f.inst, f.off or NONE
	if you.ghost and corpse and corpse.inst == inst and not off.corpse then
		return Set("corpse", "corpse", corpse, nil, CORPSE)
	end
	local e = not off.quests and Followed(inst)
	if e then
		if e.complete or off.questAreas or not (f.shown and you.inst == inst and you.col and not you.stale) then
			return Set("quest", e.key, e.pos, nil, Title(e), e.quest)
		end
		Area(e, you, obs.quests)
		return Set("quest", e.key, area.pos or e.pos, area.inside, Title(e), e.quest)
	end
	if waypoint and waypoint.inst == inst and not off.waypoint then
		return Set("waypoint", "waypoint", waypoint, nil, WAYPOINT)
	end
	target = false
end)

Model.Kind("corpse", function() return corpses, corpseRev end)
Model.Kind("waypoint", function() return waypoints, waypointRev end)

function Model.Target() return target end
