-- Your log's quests on their maps (obs.quests) as Known("quests"), and what Atlas knows of
-- them (QuestieDB: who drops an objective's item, where else it comes from, who takes the quest
-- in), for their pins and tooltips (the spike's QuestInfo.lua, Layers.lua:544-621):
--   color     the quest log's difficulty colours, by its level minus yours
--   count     the first unfinished objective that counts ("3/8"); inner, the first unfinished's icon
--   need      what it still needs (kill, gather, other): its area's colour
--   estimate  an unfinished kill, collect or interact objective (Layers.lua:544) the game draws no
--             area for at its pin, its own or another quest's (HasArea false: Layers.lua:922-941)
--             gets a 110 yd disc, shared by the pins within 0.6 r of an earlier one's centre, each
--             way (Layers.lua:948-964)
-- A quest the same as before (by value) keeps its entry, so a layer diffing entries relays only
-- what changed. Each new log asks HasArea again for every such quest (the spike's refresh checks
-- them all), each frame till it answers (nil: can't tell yet); the last answer stands till then.

local _, ns = ...
local Atlas, Model = ns.Atlas, ns.Model

local NONE = {}
local MERGE = 110 / 533.33 * 0.6 -- 0.6 of an estimate's radius, tiles (Layers.lua:78, 959)
local RED, ORANGE, YELLOW = { 1, 0.1, 0.1 }, { 1, 0.5, 0.25 }, { 1, 0.82, 0 } -- QuestInfo.lua:17-18
local GREEN, GREY = { 0.25, 0.75, 0.25 }, { 0.5, 0.5, 0.5 }
local TURN_IN = { atlas = "UI-QuestIcon-TurnIn-Normal", color = { 0.2, 1, 0.2 } } -- Layers.lua:606-609
local ACTIVE = { atlas = "Quest-In-Progress-Icon-yellow", color = { 1, 0.82, 0 } }
local KIND_ICONS = { monster = { texture = 135274 }, object = { texture = 134063 }, item = { texture = 133633 } } -- QuestInfo.lua:109-113
local AREA = { monster = true, item = true, object = true } -- Layers.lua:544
local RANKS = { [1] = "Elite", [2] = "Rare Elite", [3] = "Boss", [4] = "Rare" } -- QuestInfo.lua:176
local MAX_MOBS = 3 -- QuestInfo.lua:174
local MAX_NAMES = 2 -- QuestInfo.lua:235, 240

local quests = {}           -- [id] = { q (the obs quest it's built from), e (its entry), has (an area at its pin), ask (an answer due) }
local log, list, rev = nil, NONE, 0
local level, range = nil, 5 -- yours, and how far below you a mob turns grey (obs.you.trivialRange, else 5: QuestInfo.lua:191)
local due = 0               -- quests whose answer is due
local icons = {}            -- an item's icon file -> its MM.Icon

-- red at 5 or more over you, orange at 3, yellow down to -2, then green till trivial (QuestInfo.lua:22-28)
local function Difficulty(lvl, trivial)
	local diff = lvl - (level or lvl)
	if diff >= 5 then return RED end
	if diff >= 3 then return ORANGE end
	if diff >= -2 then return YELLOW end
	return trivial and GREY or GREEN
end

local function Same(a, b)
	if a == b then return true end
	local p, x = a.pin, b.pin
	if a.title ~= b.title or a.level ~= b.level or a.trivial ~= b.trivial or a.complete ~= b.complete
		or a.followed ~= b.followed or a.areaMap ~= b.areaMap or p.inst ~= x.inst or p.col ~= x.col or p.row ~= x.row
		or a.tag ~= b.tag or a.group ~= b.group or a.poi ~= b.poi or #a.objectives ~= #b.objectives then return false end
	for i, o in ipairs(a.objectives) do
		local y = b.objectives[i]
		if o.type ~= y.type or o.text ~= y.text or o.have ~= y.have or o.need ~= y.need or o.finished ~= y.finished
			or o.itemID ~= y.itemID then return false end
	end
	return true
end

-- An unfinished kill, collect or interact objective: "somewhere around here" (Layers.lua:551-557).
local function Area(q)
	if q.complete then return false end
	for _, o in ipairs(q.objectives) do
		if not o.finished and AREA[o.type] then return true end
	end
	return false
end

-- Layers.lua:561-569
local function Need(q)
	for _, o in ipairs(q.objectives) do
		if not o.finished then
			if o.type == "monster" then return "kill" end
			if o.type == "item" or o.type == "object" then return "gather" end
		end
	end
	return "other"
end

-- Progress bars count to 100: no count (QuestInfo.lua:57-65).
local function Count(q)
	for _, o in ipairs(q.objectives) do
		local need = o.need
		if not o.finished and o.type ~= "progressbar" and need and need > 1 then
			return string.format("%d/%d", math.min(o.have or 0, need), need)
		end
	end
end

-- The item's own, else one for the kind; nil for the rest (go, talk) (QuestInfo.lua:115-127).
local function Inner(q)
	for _, o in ipairs(q.objectives) do
		if not o.finished then
			local item = o.type == "item" and o.itemID and Atlas.Item(o.itemID)
			local file = item and item.icon
			if file then
				if not icons[file] then icons[file] = { texture = file } end
				return icons[file]
			end
			return KIND_ICONS[o.type]
		end
	end
end

local function MaxLevel(id)
	local n = Atlas.Npc(id)
	return n and n.maxLevel or 0
end

local function ByLevel(a, b)
	local x, y = MaxLevel(a), MaxLevel(b)
	if x ~= y then return x < y end
	return a < b
end

-- QuestInfo.lua:182-196
local function Mob(id)
	local n = Atlas.Npc(id)
	if not n then return nil end
	local m, lo, hi = { npc = id, name = n.name, rank = RANKS[n.rank or 0] }, n.minLevel, n.maxLevel
	if hi and hi > 0 then
		m.lo, m.hi, m.color = lo and lo > 0 and lo or hi, hi, Difficulty(hi, (level or hi) - hi > range)
	end
	return m
end

-- "A, B" (and "+2 more") (QuestInfo.lua:199-209).
local function Names(get, ids)
	local names = {}
	for _, id in ipairs(ids) do
		if #names >= MAX_NAMES then
			names[#names] = names[#names] .. string.format(" (+%d more)", #ids - MAX_NAMES)
			break
		end
		local e = get(id)
		names[#names + 1] = e and e.name
	end
	return table.concat(names, ", ")
end

-- Who drops the item, lowest level first, else the objects it's in, else who sells it (QuestInfo.lua:213-242).
local function Sources(k, itemID)
	local item = Atlas.Item(itemID)
	if not item then return end
	if #item.npcDrops > 0 then
		local sorted = {}
		for i, id in ipairs(item.npcDrops) do sorted[i] = id end
		table.sort(sorted, ByLevel)
		k.drops = {}
		for i, id in ipairs(sorted) do
			if i > MAX_MOBS then
				k.more = #sorted - MAX_MOBS
				break
			end
			k.drops[#k.drops + 1] = Mob(id)
		end
	elseif #item.objectDrops > 0 then
		k.from = Names(Atlas.Object, item.objectDrops)
	elseif #item.vendors > 0 then
		k.sold = Names(Atlas.Npc, item.vendors)
	end
end

local function Objectives(q)
	local out = {}
	for _, o in ipairs(q.objectives) do
		if o.text ~= "" then
			local k = { text = o.text, finished = o.finished }
			if not o.finished and o.type == "item" and o.itemID then Sources(k, o.itemID) end
			out[#out + 1] = k
		end
	end
	return out
end

-- QuestInfo.lua:352-354
local function TurnIn(id)
	local quest = Atlas.Quest(id)
	if not quest then return nil end
	local npc, object = quest.finishedBy.npcs[1], quest.finishedBy.objects[1]
	npc, object = npc and Atlas.Npc(npc), object and Atlas.Object(object)
	return npc and npc.name or object and object.name or nil
end

local function Entry(q, estimate)
	local e = { key = "quest:" .. q.id, kind = "quests", pos = q.pin, name = q.title, live = true, quest = q.id,
		level = q.level, color = q.level and Difficulty(q.level, q.trivial), complete = q.complete, followed = q.followed,
		areaMap = q.areaMap, estimate = estimate, turnIn = TurnIn(q.id), tag = q.tag, group = q.group, poi = q.poi }
	if q.complete then
		e.icon = TURN_IN
	else
		e.icon, e.count, e.inner, e.need, e.objectives = ACTIVE, Count(q), Inner(q), Need(q), Objectives(q)
	end
	return e
end

-- A new log: a changed quest gets a new state (its last answer kept till the next); each that may
-- want an estimate is asked again (another quest's area may cover its pin now).
local function Sync(qs)
	local was = quests
	quests, due = {}, 0
	for _, q in ipairs(qs) do
		if q.pin then
			local s = was[q.id]
			if not (s and Same(s.q, q)) then s = { q = q, has = s and s.has } end
			s.ask = Area(q) or nil
			if s.ask then due = due + 1 end
			quests[q.id] = s
		end
	end
end

-- Answers due: whether the game draws an area at each pin (nil: not yet, ask next frame). True
-- when one changed.
local function Answer(HasArea)
	local changed = false
	for id, s in pairs(quests) do
		if s.ask then
			local has = HasArea(id)
			if has ~= nil then
				s.ask, due = nil, due - 1
				if has ~= s.has then s.has, changed = has, true end
			end
		end
	end
	return changed
end

local function Build()
	local centers, out = {}, {}
	for _, x in ipairs(log) do
		local s = quests[x.id]
		if s then
			local q, estimate = s.q, nil
			if s.has == false and Area(q) then
				local p = q.pin
				for _, c in ipairs(centers) do
					if c.inst == p.inst and math.abs(c.col - p.col) < MERGE and math.abs(c.row - p.row) < MERGE then
						estimate = c
						break
					end
				end
				if not estimate then
					estimate = p
					centers[#centers + 1] = p
				end
			end
			if not (s.e and s.level == level and s.range == range and s.e.estimate == estimate) then
				s.e, s.level, s.range = Entry(q, estimate), level, range
			end
			out[#out + 1] = s.e
		end
	end
	local same = #out == #list
	for i = 1, same and #out or 0 do
		if out[i] ~= list[i] then
			same = false
			break
		end
	end
	if not same then list, rev = out, rev + 1 end
end

Model.Part(function(obs, oracles)
	local qs, you = obs.quests or log, obs.you
	if not qs then return end
	local lvl, rng = you.level or level, you.trivialRange or range
	local dirty = qs ~= log or lvl ~= level or rng ~= range
	level, range = lvl, rng
	if qs ~= log then
		log = qs
		Sync(qs)
	end
	if due > 0 and Answer(oracles.HasArea) then dirty = true end
	if dirty then Build() end
end)

Model.Kind("quests", function() return list, rev end)
