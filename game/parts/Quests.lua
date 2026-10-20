-- obs.quests (types/observation.lua MM.ObsQuest[]), on change: your log's quests on the zones of the
-- map shown (Game.shownInst, a frame behind) and of yours, as the world map has them (Layers.lua:581-631):
-- GetQuestsOnMap per zone (Atlas.Zones), map indicators skipped, a quest on several kept on the
-- smallest (its objective area lives there: areaMap, but for one ready to turn in). An item
-- objective's item is QuestieDB's of that kind and place (QuestInfo.lua:94-110). Read again 0.3 s
-- after a burst of the 5 events (Layers.lua:1231-1242, 2219-2228) or of QUEST_ACCEPTED and
-- QUEST_REMOVED (Forever's: a quest's id, as Questie's EventHandler.lua:157-193), at once when the
-- super-tracked quest (a follow Command, Blizzard's tracker: the same frame's obs) or the instances change, and
-- only while the map is shown (once it shows, for what came while it wasn't). Each quest is
-- compared with its last as it's read and kept if the same, so a read that finds nothing new makes
-- nothing; a new table only when something changed, sorted by id. poi, on the list: the
-- QUEST_POI_UPDATEs seen, so the game's areas changing makes a new list, its quests kept (UI draws
-- the areas again: Layers.lua:2225, 1233-1240).
-- Where the pins are (every zone's GetQuestsOnMap: the client makes a table a quest each call) is read
-- again only when they may have moved: a quest taken or given up, the game's areas (QUEST_POI_UPDATE),
-- the instances, a quest done or a count changed (found by the read: its pin may go to the turn-in or
-- the next objective's area, read again at once); a QUEST_LOG_UPDATE storm (looting) reads no zone.

local _, ns = ...
local Atlas, Game, Runtime = ns.Atlas, ns.Game, ns.Runtime

local DELAY = 0.3 -- s: QUEST_LOG_UPDATE fires a lot (Layers.lua:1236)
local TYPES = { monster = true, item = true, object = true, event = true, log = true, progressbar = true, reputation = true }
local NONE = {}

local list -- the last handed over
local dirty, pending = true, false
local scan = true -- where the pins are to be read again
local poi -- QUEST_POI_UPDATEs seen
local read, readShown, followed -- the instances last read and the super-tracked quest then
local pins = {} -- quest -> { map, x, y, area, at (the read that found it) }: the smallest zone with its pin
local last = {} -- quest -> its MM.ObsQuest in list
local reads = 0

local function Due() pending, dirty = false, true end
local function Soon()
	if pending then return end
	pending = true
	Runtime.After(DELAY, "game.quests refresh", Due)
end
for _, event in ipairs({ "QUEST_LOG_UPDATE", "SUPER_TRACKING_CHANGED", "PLAYER_LEVEL_UP", "GET_ITEM_INFO_RECEIVED" }) do
	Runtime.On(event, "game.quests", Soon)
end
local function Moved()
	scan = true
	Soon()
end
Runtime.On("QUEST_ACCEPTED", "game.quests", Moved)
Runtime.On("QUEST_REMOVED", "game.quests", Moved)
Runtime.On("QUEST_POI_UPDATE", "game.quests", function()
	poi = (poi or 0) + 1
	Moved()
end)

local function ScanZones(inst)
	for _, z in ipairs(Atlas.Zones(inst)) do
		local area = (z.col1 - z.col0) * (z.row1 - z.row0)
		for _, q in ipairs(C_QuestLog.GetQuestsOnMap(z.uiMapID)) do
			if not q.isMapIndicatorQuest then
				local b = pins[q.questID]
				if not b then
					b = {}
					pins[q.questID] = b
				end
				if b.at ~= reads or area < b.area then b.at, b.map, b.x, b.y, b.area = reads, z.uiMapID, q.x, q.y, area end
			end
		end
	end
end

-- The pins found this read (b.at): on your instance's zones and the shown one's.
local function Scan(you, shown)
	scan = false
	ScanZones(you)
	if shown ~= you then ScanZones(shown) end
end

-- QuestieDB's k-th item objective of quest q: the game's k-th item objective's item.
local function Item(q, k)
	for _, o in ipairs(q and q.objectives or NONE) do
		if o.kind == "item" then
			k = k - 1
			if k == 0 then return o.id end
		end
	end
end

-- The game's objectives as obs has them: was (the last) if the same.
local function Objectives(id, was)
	local game, q = C_QuestLog.GetQuestObjectives(id), Atlas.Quest(id)
	local same, k = was and #was == #game, 0
	for i, o in ipairs(same and game or NONE) do
		local w, item = was[i], nil
		if o.type == "item" then
			k = k + 1
			item = Item(q, k)
		end
		if w.type ~= (TYPES[o.type] and o.type or "other") or w.text ~= o.text or w.have ~= o.numFulfilled
			or w.need ~= o.numRequired or w.finished ~= o.finished or w.itemID ~= item then
			same = false
			break
		end
	end
	if same then return was end
	local out = {}
	k = 0
	for i, o in ipairs(game) do
		local item
		if o.type == "item" then
			k = k + 1
			item = Item(q, k)
		end
		out[i] = { type = TYPES[o.type] and o.type or "other", text = o.text, have = o.numFulfilled, need = o.numRequired,
			finished = o.finished, itemID = item }
	end
	return out
end

-- Quest id at pin b as the game has it now: was (its last) if the same.
local function Quest(id, b, was)
	local level, complete, trivial = C_QuestLog.GetQuestDifficultyLevel(id), C_QuestLog.IsComplete(id), C_QuestLog.IsQuestTrivial(id)
	local title = C_QuestLog.GetTitleForQuestID(id) or ("Quest " .. id)
	local tag, group = C_QuestLog.GetQuestTagInfo(id), C_QuestLog.GetSuggestedGroupSize(id) -- QuestInfo.lua:321-325
	level, group, tag = level > 0 and level or nil, group > 0 and group or nil, tag and tag.tagName ~= "" and tag.tagName or nil
	local areaMap, inst, col, row = not complete and b.map or nil, Atlas.MapToTile(b.map, b.x, b.y)
	local objectives, p = Objectives(id, was and was.objectives), was and was.pin
	if was and objectives == was.objectives and title == was.title and level == was.level and trivial == was.trivial
		and complete == was.complete and (id == followed) == was.followed and areaMap == was.areaMap and tag == was.tag
		and group == was.group and inst == p.inst and col == p.col and row == p.row then
		return was
	end
	return { id = id, title = title, level = level, trivial = trivial, complete = complete, followed = id == followed,
		objectives = objectives, pin = { inst = inst, col = col, row = row }, areaMap = areaMap, tag = tag, group = group }
end

-- q (as read) at pin b: q if it stands there already.
local function At(q, b)
	local areaMap, inst, col, row = not q.complete and b.map or nil, Atlas.MapToTile(b.map, b.x, b.y)
	local p = q.pin
	if areaMap == q.areaMap and inst == p.inst and col == p.col and row == p.row then return q end
	local out = {}
	for k, v in pairs(q) do out[k] = v end
	out.areaMap, out.pin = areaMap, { inst = inst, col = col, row = row }
	return out
end

local function ById(a, b) return a.id < b.id end

local function Read(you, shown)
	reads = reads + 1
	local scanned = scan
	if scan then
		Scan(you, shown)
	else
		for _, b in pairs(pins) do b.at = reads end -- (where they were)
	end
	local changed, moved = list == nil or list.poi ~= poi, false
	for id, b in pairs(pins) do
		if b.at ~= reads then
			pins[id] = nil
		else
			local was = last[id]
			local q = Quest(id, b, was)
			if q ~= was then
				last[id], changed = q, true
				if was and not scanned and (q.complete ~= was.complete or q.objectives ~= was.objectives) then moved = true end
			end
		end
	end
	if moved then -- where they stand now, as just read
		reads = reads + 1
		Scan(you, shown)
		for id, b in pairs(pins) do
			if b.at ~= reads then
				pins[id] = nil
			else
				local q = last[id]
				last[id] = q and At(q, b) or Quest(id, b)
			end
		end
	end
	for id in pairs(last) do
		if not pins[id] then last[id], changed = nil, true end
	end
	if not changed then return list end
	local out = { poi = poi }
	for _, q in pairs(last) do out[#out + 1] = q end
	table.sort(out, ById)
	return out
end

Game.Part("quests", function(obs)
	local shown = Game.shownInst
	if shown == false then return list end -- (hidden: read once it's shown)
	local you, super = obs.you.inst, C_SuperTrack.GetSuperTrackedQuestID()
	shown = shown or you
	if dirty or super ~= followed or you ~= read or shown ~= readShown then
		if you ~= read or shown ~= readShown then scan = true end
		dirty, followed, read, readShown = false, super, you, shown
		list = Read(you, shown)
	end
	return list
end)
