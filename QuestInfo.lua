-- What a quest in your log is like at a glance, for its pin and tooltips:
-- its level, coloured by how hard it is for you (the quest log's colours),
-- how far along it is, and from QuestieDB (a dependency) what each
-- objective is: which mobs drop an item, their levels, who you turn it in to.

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

-- trivial: whether the client calls it grey (for quests it says; for mobs,
-- more than your trivial range below you).
local function Difficulty(level, trivial)
	local diff = level - (UnitLevel("player") or level)
	if diff >= 5 then return RED end
	if diff >= 3 then return ORANGE end
	if diff >= -2 then return YELLOW end
	return trivial and GREY or GREEN
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
	return string.format("[%d] %s", level, title), Difficulty(level, SafeCall(C_QuestLog.IsQuestTrivial, questID))
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

---------------------------------------------------------------------------
-- QuestieDB
---------------------------------------------------------------------------

local CONTRACT = 3 -- the QuestieDB contract this is written against
local DB = LibQuestieDB
if not (DB and DB.RequireContract) then
	DB = nil
	ns.Print("QuestieDB isn't loaded: quests show without their mobs and items.")
else
	local ok, why = DB.RequireContract(CONTRACT)
	if not ok then
		DB = nil
		ns.Print(why)
	end
end

local function Read(entity, field, id)
	if not (DB and id) then return nil end
	return SafeCall(DB[entity][field], id)
end

-- The game's objective types, and where QuestieDB keeps the same kind.
local DB_KIND = { monster = 1, object = 2, item = 3 }

-- The NPC, object or item an objective is about: QuestieDB lists each kind
-- in the quest's own order, so the game's k-th item objective is its k-th.
local function ObjectiveID(questID, objectives, index)
	local o = objectives[index]
	local kind = DB_KIND[o.type]
	local list = kind and Read("Quest", "objectives", questID)
	if not (list and list[kind]) then return nil end
	local k = 0
	for i = 1, index do
		if objectives[i].type == o.type then k = k + 1 end
	end
	local entry = list[kind][k]
	return entry and entry[1]
end

-- The first unfinished objective's icon, for inside its pin: the item's
-- own, else one for the kind of objective; nil for the rest (go somewhere,
-- talk to someone). FileDataIDs.
local KIND_ICONS = {
	monster = 135274, -- INV_Sword_04
	object = 134063,  -- INV_Misc_Gear_01
	item = 133633,    -- INV_Misc_Bag_08: an item QuestieDB doesn't know
}

function ns.QuestObjectiveIcon(questID)
	local objectives = SafeCall(C_QuestLog.GetQuestObjectives, questID) or {}
	for i, o in ipairs(objectives) do
		if not o.finished then
			if o.type == "item" then
				local itemID = ObjectiveID(questID, objectives, i)
				local ok, _, _, _, _, icon = pcall(C_Item.GetItemInfoInstant, itemID)
				if itemID and ok and icon then return icon end
			end
			return KIND_ICONS[o.type]
		end
	end
end

---------------------------------------------------------------------------
-- Mob portraits: the game draws one only from a unit that's there (your
-- target, the mob under the mouse, a nameplate), so each mob's is kept as
-- it's met, for this session, and its quest tooltip lines show it.
---------------------------------------------------------------------------

local PORTRAIT = 14  -- px
local MAX_PORTRAITS = 300
local portraitHolder = CreateFrame("Frame")
portraitHolder:Hide()
local portraits, portraitCount = {}, 0 -- NPC ID -> texture

local function NpcID(unit)
	local guid = UnitGUID(unit)
	if not guid or (issecretvalue and issecretvalue(guid)) then return nil end
	local kind, _, _, _, _, id = strsplit("-", guid)
	return (kind == "Creature" or kind == "Vehicle") and tonumber(id) or nil
end

local function Capture(unit)
	local id = NpcID(unit)
	if not id or portraits[id] or portraitCount >= MAX_PORTRAITS then return end
	local tex = portraitHolder:CreateTexture(nil, "OVERLAY")
	SetPortraitTexture(tex, unit)
	tex:SetSize(PORTRAIT, PORTRAIT)
	portraits[id], portraitCount = tex, portraitCount + 1
end

local capture = CreateFrame("Frame")
capture:SetScript("OnEvent", function(_, event, unit)
	if event == "UPDATE_MOUSEOVER_UNIT" then
		Capture("mouseover")
	elseif event == "PLAYER_TARGET_CHANGED" then
		Capture("target")
	else
		Capture(unit) -- NAME_PLATE_UNIT_ADDED
	end
end)
for _, event in ipairs({ "UPDATE_MOUSEOVER_UNIT", "PLAYER_TARGET_CHANGED", "NAME_PLATE_UNIT_ADDED" }) do
	pcall(capture.RegisterEvent, capture, event)
end

-- A mob, as a tooltip line: its portrait (a dark disc under it, placed by
-- ns.ShowTooltipPortraits) or until it's been seen a sword (a skull for
-- elites), name, level range in its difficulty colour for you, rank.
local MAX_MOBS = 3
local INDENT = "    "
local RANKS = { [1] = "Elite", [2] = "Rare Elite", [3] = "Boss", [4] = "Rare" }
local MOB_ICON = string.format("|T135274:%d:%d:0:0:64:64:5:59:5:59|t", PORTRAIT, PORTRAIT)
local ELITE_ICON = string.format("|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:%d:%d|t", PORTRAIT, PORTRAIT)
local DISC = string.format("|T%s:%d:%d:0:0:64:64:0:64:0:64:0:0:0|t", ns.CIRCLE, PORTRAIT, PORTRAIT)
local DIM, WHITE = "|cff9d9d9d", "|cffffffff"

local function MobLine(npcID)
	local name = Read("Npc", "name", npcID)
	if not name then return nil end
	local lo, hi = Read("Npc", "minLevel", npcID), Read("Npc", "maxLevel", npcID)
	local rank = RANKS[Read("Npc", "rank", npcID) or 0]
	local icon = portraits[npcID] and DISC or rank and ELITE_ICON or MOB_ICON
	local text = INDENT .. icon .. " " .. WHITE .. name .. "|r"
	if hi and hi > 0 then
		lo = lo and lo > 0 and lo or hi
		local trivial = (UnitLevel("player") or hi) - hi > (SafeCall(UnitQuestTrivialLevelRange, "player") or 5)
		text = text .. " " .. Hex(Difficulty(hi, trivial)) .. (lo == hi and lo or (lo .. "-" .. hi)) .. "|r"
	end
	if rank then text = text .. " " .. DIM .. rank .. "|r" end
	return text
end

-- Names of entities, "A, B" (and "+2 more").
local function Names(entity, ids, max)
	local names = {}
	for _, id in ipairs(ids) do
		if #names >= max then
			names[#names] = names[#names] .. string.format(" (+%d more)", #ids - max)
			break
		end
		names[#names + 1] = Read(entity, "name", id)
	end
	return table.concat(names, ", ")
end

-- Where an objective's item comes from: the mobs that drop it (shown[line]
-- = NPC ID for those with a portrait), else the objects it's in, else who sells it.
local function ItemSources(lines, shown, itemID)
	local mobs = Read("Item", "npcDrops", itemID)
	if mobs and #mobs > 0 then
		lines[#lines + 1] = "    " .. DIM .. "Dropped by|r"
		local sorted = {}
		for _, id in ipairs(mobs) do sorted[#sorted + 1] = id end
		table.sort(sorted, function(a, b) return (Read("Npc", "maxLevel", a) or 0) < (Read("Npc", "maxLevel", b) or 0) end)
		for i, id in ipairs(sorted) do
			if i > MAX_MOBS then
				lines[#lines + 1] = "    " .. DIM .. string.format("(+%d more)", #sorted - MAX_MOBS) .. "|r"
				break
			end
			local line = MobLine(id)
			if line then
				lines[#lines + 1] = line
				shown[#lines] = portraits[id] and id or nil
			end
		end
		return
	end
	local objects = Read("Item", "objectDrops", itemID)
	if objects and #objects > 0 then
		lines[#lines + 1] = "    " .. DIM .. "From|r " .. WHITE .. Names("Object", objects, 2) .. "|r"
		return
	end
	local vendors = Read("Item", "vendors", itemID)
	if vendors and #vendors > 0 then
		lines[#lines + 1] = "    " .. DIM .. "Sold by|r " .. WHITE .. Names("Npc", vendors, 2) .. "|r"
	end
end

-- The quest's tooltip lines (after its title): what's left to do and,
-- for items mobs drop, which mobs (a kill objective already names its
-- mob); its tag (Elite, Group, Dungeon) and who to turn it in to. Second:
-- { [line] = NPC ID } of the mobs with portraits, for ns.ShowTooltipPortraits.
function ns.QuestTooltipLines(questID, complete)
	local lines, shown = {}, {}
	if complete then
		lines[1] = "|cff33ff33Ready to turn in|r"
	else
		local objectives = SafeCall(C_QuestLog.GetQuestObjectives, questID) or {}
		for i, o in ipairs(objectives) do
			if o.text and o.text ~= "" then
				lines[#lines + 1] = (o.finished and "|cff808080" or WHITE) .. "- " .. o.text .. "|r"
				local id = not o.finished and o.type == "item" and ObjectiveID(questID, objectives, i)
				if id then ItemSources(lines, shown, id) end
			end
		end
	end
	local tag = SafeCall(C_QuestLog.GetQuestTagInfo, questID)
	local group = SafeCall(C_QuestLog.GetSuggestedGroupSize, questID)
	if tag and tag.tagName and tag.tagName ~= "" then
		lines[#lines + 1] = "|cffff8040" .. tag.tagName .. (group and group > 1 and string.format(" (%d)", group) or "") .. "|r"
	end
	local finishers = Read("Quest", "finishedBy", questID)
	local npc = finishers and finishers[1] and finishers[1][1]
	local who = npc and Read("Npc", "name", npc) or (finishers and finishers[2] and Read("Object", "name", finishers[2][1]))
	if who then lines[#lines + 1] = DIM .. "Turn in to|r " .. WHITE .. who .. "|r" end
	return lines, shown
end

-- Portraits onto a shown tooltip, over their lines' dark discs: shown[i] is
-- the mob on line first + i. Lent to the tooltip while it's up.
local lent = {}
local probe = portraitHolder:CreateFontString()
function ns.ShowTooltipPortraits(tooltip, first, shown)
	for _, tex in ipairs(lent) do tex:Hide() end
	wipe(lent)
	for i, npcID in pairs(shown) do
		local fs = _G[tooltip:GetName() .. "TextLeft" .. (first + i)]
		local tex = portraits[npcID]
		if fs and tex then
			probe:SetFont(fs:GetFont())
			probe:SetText(INDENT)
			tex:SetParent(tooltip)
			tex:SetDrawLayer("OVERLAY", 7)
			tex:ClearAllPoints()
			tex:SetPoint("LEFT", fs, "LEFT", probe:GetStringWidth(), 0)
			tex:Show()
			lent[#lent + 1] = tex
		end
	end
end
GameTooltip:HookScript("OnHide", function()
	for _, tex in ipairs(lent) do tex:Hide() end
	wipe(lent)
end)
