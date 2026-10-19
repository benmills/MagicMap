-- obs.quests (types/observation.lua MM.ObsQuest[]), on change: your log's quests on the zones of the
-- map shown (View.inst, a frame behind) and of yours, as the world map has them (Layers.lua:581-631):
-- GetQuestsOnMap per zone (Atlas.Zones), map indicators skipped, a quest on several kept on the
-- smallest (its objective area lives there: areaMap, but for one ready to turn in). An item
-- objective's item is QuestieDB's of that kind and place (QuestInfo.lua:94-110). Read again 0.3 s
-- after a burst of the 5 events (Layers.lua:1231-1242, 2219-2228), at once when the super-tracked
-- quest (a follow Command, Blizzard's tracker: the same frame's obs) or the instances change;
-- sorted by id, a new table only when something did. poi: the QUEST_POI_UPDATEs seen, on every
-- quest, so the game's areas changing makes every quest new (Layers.lua:2225, 1233-1240).

local _, ns = ...
local Atlas, Game, Runtime = ns.Atlas, ns.Game, ns.Runtime

local DELAY = 0.3 -- s: QUEST_LOG_UPDATE fires a lot (Layers.lua:1236)
local TYPES = { monster = true, item = true, object = true, event = true, log = true, progressbar = true, reputation = true }

local list -- the last handed over
local dirty, pending = true, false
local poi -- QUEST_POI_UPDATEs seen
local shown, read, readShown, followed -- the instance shown; those last read and the super-tracked quest then

local function Due() pending, dirty = false, true end
local function Soon()
	if pending then return end
	pending = true
	Runtime.After(DELAY, "game.quests refresh", Due)
end
for _, event in ipairs({ "QUEST_LOG_UPDATE", "SUPER_TRACKING_CHANGED", "PLAYER_LEVEL_UP", "GET_ITEM_INFO_RECEIVED" }) do
	Runtime.On(event, "game.quests", Soon)
end
Runtime.On("QUEST_POI_UPDATE", "game.quests", function()
	poi = (poi or 0) + 1
	Soon()
end)
Game.Apply("quests shown", function(view) shown = view.inst end)

local function Same(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return a == b end
	for k, v in pairs(a) do
		if not Same(v, b[k]) then return false end
	end
	for k in pairs(b) do
		if a[k] == nil then return false end
	end
	return true
end

-- quest -> { map, x, y, area }: the smallest of inst's zones that has its pin.
local function Scan(inst, best)
	for _, z in ipairs(Atlas.Zones(inst)) do
		local area = (z.col1 - z.col0) * (z.row1 - z.row0)
		for _, q in ipairs(C_QuestLog.GetQuestsOnMap(z.uiMapID)) do
			local b = best[q.questID]
			if not q.isMapIndicatorQuest and not (b and b.area <= area) then
				best[q.questID] = { map = z.uiMapID, x = q.x, y = q.y, area = area }
			end
		end
	end
end

local function Objectives(id)
	local items, out, k = {}, {}, 0 -- QuestieDB's items, in order: the game's k-th item objective is its k-th
	local q = Atlas.Quest(id)
	for _, o in ipairs(q and q.objectives or {}) do
		if o.kind == "item" then items[#items + 1] = o.id end
	end
	for i, o in ipairs(C_QuestLog.GetQuestObjectives(id)) do
		local item
		if o.type == "item" then
			k = k + 1
			item = items[k]
		end
		out[i] = { type = TYPES[o.type] and o.type or "other", text = o.text, have = o.numFulfilled, need = o.numRequired,
			finished = o.finished, itemID = item }
	end
	return out
end

local function Read(you)
	local best, out = {}, {}
	Scan(you, best)
	if shown ~= you then Scan(shown, best) end
	for id, b in pairs(best) do
		local level, complete, inst, col, row = C_QuestLog.GetQuestDifficultyLevel(id), C_QuestLog.IsComplete(id),
			Atlas.MapToTile(b.map, b.x, b.y)
		local tag, group = C_QuestLog.GetQuestTagInfo(id), C_QuestLog.GetSuggestedGroupSize(id) -- QuestInfo.lua:321-325
		out[#out + 1] = { id = id, title = C_QuestLog.GetTitleForQuestID(id) or ("Quest " .. id),
			level = level > 0 and level or nil, trivial = C_QuestLog.IsQuestTrivial(id), complete = complete,
			followed = id == followed, objectives = Objectives(id), pin = { inst = inst, col = col, row = row },
			areaMap = not complete and b.map or nil, tag = tag and tag.tagName ~= "" and tag.tagName or nil,
			group = group > 0 and group or nil, poi = poi }
	end
	table.sort(out, function(a, b) return a.id < b.id end)
	return out
end

Game.Part("quests", function(obs)
	local you, super = obs.you.inst, C_SuperTrack.GetSuperTrackedQuestID()
	if dirty or super ~= followed or you ~= read or shown ~= readShown then
		dirty, followed, read, readShown = false, super, you, shown
		local new = Read(you)
		if not Same(new, list) then list = new end
	end
	return list
end)
