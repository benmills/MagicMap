-- What a quest in your log is like at a glance, for its pin and tooltips:
-- its level, coloured by how hard it is for you (the quest log's colours),
-- and how far along it is.

local ADDON, ns = ...

local function SafeCall(fn, ...)
	if not fn then return nil end
	local ok, a, b = pcall(fn, ...)
	if ok then return a, b end
end

-- The quest log's difficulty colours, by quest level minus yours: red at 5
-- or more, orange at 3, yellow down to -2, then green until the quest
-- turns trivial (grey), which the client knows.
local RED, ORANGE, YELLOW = { 1, 0.1, 0.1 }, { 1, 0.5, 0.25 }, { 1, 0.82, 0 }
local GREEN, GREY = { 0.25, 0.75, 0.25 }, { 0.5, 0.5, 0.5 }

local function Difficulty(questID, level)
	local diff = level - (UnitLevel("player") or level)
	if diff >= 5 then return RED end
	if diff >= 3 then return ORANGE end
	if diff >= -2 then return YELLOW end
	return SafeCall(C_QuestLog.IsQuestTrivial, questID) and GREY or GREEN
end

-- The quest's level, or nil if the client doesn't say (scaled quests: the
-- level they scale to).
local function Level(questID)
	local level = SafeCall(C_QuestLog.GetQuestDifficultyLevel, questID)
	return level and level > 0 and level or nil
end

local function Hex(c)
	return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255)
end

-- "[12] Title" and its difficulty colour { r, g, b } (nil without a level).
function ns.QuestTitle(questID, title)
	title = title or SafeCall(C_QuestLog.GetTitleForQuestID, questID) or ("Quest " .. questID)
	local level = Level(questID)
	if not level then return title, nil end
	return string.format("[%d] %s", level, title), Difficulty(questID, level)
end

-- The same, wrapped in its colour for text that's built from pieces.
function ns.QuestTitleText(questID, title)
	local text, c = ns.QuestTitle(questID, title)
	return c and (Hex(c) .. text .. "|r") or text
end

-- How far along it is, for its pin: the first unfinished objective that
-- counts something ("3/8"), or nil. Progress bars count to 100: no count.
function ns.QuestProgress(questID)
	for _, o in ipairs(SafeCall(C_QuestLog.GetQuestObjectives, questID) or {}) do
		local need = o.numRequired
		if not o.finished and o.type ~= "progressbar" and need and need > 1 then
			return string.format("%d/%d", math.min(o.numFulfilled or 0, need), need)
		end
	end
end

-- The first unfinished objective's icon, for inside its pin: an item's own
-- (looked up by the name in the objective's text, once the client has the
-- item cached), else one for the kind of objective; nil for the rest
-- (go somewhere, talk to someone). FileDataIDs.
local KIND_ICONS = {
	monster = 135274, -- INV_Sword_04
	object = 134063,  -- INV_Misc_Gear_01
	item = 133633,    -- INV_Misc_Bag_08, until the item's known
}

-- "Large Candle: 3/8" (or "3/8 Large Candle") -> "Large Candle"
local function ObjectiveName(text)
	local name = (text or ""):gsub("^%d+/%d+%s+", ""):gsub(":%s*%d+/%d+$", "")
	return name
end

function ns.QuestObjectiveIcon(questID)
	for _, o in ipairs(SafeCall(C_QuestLog.GetQuestObjectives, questID) or {}) do
		if not o.finished then
			if o.type == "item" then
				local ok, _, _, _, _, icon = pcall(C_Item.GetItemInfoInstant, ObjectiveName(o.text))
				if ok and icon then return icon end
			end
			return KIND_ICONS[o.type]
		end
	end
end
