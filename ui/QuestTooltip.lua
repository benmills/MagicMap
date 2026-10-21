-- A quest's tooltip (QuestInfo.lua:244-369), from its Known("quests") entry: the title in its
-- difficulty colour; a small line of facts (level, tag, ready); what's left to do, each item with where
-- it comes from in small type (who drops it, at most 3 lowest first and how many more; else the objects
-- it's in; else who sells it); then, apart and dim, who takes it in and the click hint. A dropper's line
-- shows a sword (a skull for an elite) until Game has met it, then its portrait (the tooltip Command,
-- game/commands/tooltip.lua). Small lines get their font back when the tooltip hides or clears
-- (Pins.Small). Without QuestieDB's data Model has no droppers, sources or turn-in: none of those lines.

local _, ns = ...
local UI = ns.UI
local Command = ns.Game.Command

local PORTRAIT = 14 -- px (QuestInfo.lua:135)
local INDENT = "    " -- QuestInfo.lua:175
local DIM, WHITE = "|cff9d9d9d", "|cffffffff" -- QuestInfo.lua:180
local GREEN, ORANGE = "|cff33ff33", "|cffff8040" -- QuestInfo.lua:253
local SEP = DIM .. "  ·  |r"
local MOB = string.format("|T135274:%d:%d:0:0:64:64:5:59:5:59|t", PORTRAIT, PORTRAIT) -- QuestInfo.lua:177-178
local ELITE = string.format("|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:%d:%d|t", PORTRAIT, PORTRAIT)
local TURN_IN = 0.85 -- QuestInfo.lua:358
local FOLLOW, UNFOLLOW = DIM .. "Click to follow|r", DIM .. "Click to stop following|r" -- Layers.lua:113

local QuestTooltip = {}
UI.QuestTooltip = QuestTooltip

local function Hex(c)
	return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255)
end

-- QuestInfo.lua:182-196
local function MobLine(m)
	local text = INDENT .. (m.rank and ELITE or MOB) .. " " .. WHITE .. m.name .. "|r"
	if m.hi then text = text .. " " .. Hex(m.color) .. (m.lo == m.hi and m.lo or (m.lo .. "-" .. m.hi)) .. "|r" end
	if m.rank then text = text .. " " .. DIM .. m.rank .. "|r" end
	return text
end

local small, mobs, facts = {}, {}, {} -- line -> true; line -> its dropper's NPC; the facts line's

local function Add(tip, text, r, g, b)
	tip:AddLine(text, r, g, b)
	small[tip:NumLines()] = true
end

-- Where an objective's item comes from (QuestInfo.lua:213-242), each line small.
local function Sources(tip, k)
	if k.drops then
		Add(tip, INDENT .. DIM .. "Dropped by|r", 1, 1, 1)
		for _, m in ipairs(k.drops) do
			Add(tip, MobLine(m), 1, 1, 1)
			mobs[tip:NumLines()] = m.npc
		end
		if k.more then Add(tip, INDENT .. DIM .. string.format("(+%d more)", k.more) .. "|r", 1, 1, 1) end
	elseif k.from then
		Add(tip, INDENT .. DIM .. "From|r " .. WHITE .. k.from .. "|r", 1, 1, 1)
	elseif k.sold then
		Add(tip, INDENT .. DIM .. "Sold by|r " .. WHITE .. k.sold .. "|r", 1, 1, 1)
	end
end

-- e's tooltip on GameTooltip (owned by the caller), the click hint last (Layers.lua:107-114: following
-- it or not). QuestInfo.lua:308-369.
function QuestTooltip.Show(e)
	local tip, c = GameTooltip, e.color
	for k in pairs(small) do small[k] = nil end
	for k in pairs(mobs) do mobs[k] = nil end
	if c then tip:AddLine(e.name, c[1], c[2], c[3]) else tip:AddLine(e.name) end

	-- Facts: level, tag (Elite, Group (3), Dungeon), ready.
	local f = facts
	for i = #f, 1, -1 do f[i] = nil end
	if e.level then f[#f + 1] = DIM .. "Level|r " .. Hex(c) .. e.level .. "|r" end
	if e.tag then f[#f + 1] = ORANGE .. e.tag .. (e.group and e.group > 1 and string.format(" (%d)", e.group) or "") .. "|r" end
	if e.complete then f[#f + 1] = GREEN .. "Ready to turn in|r" end
	if f[1] then Add(tip, table.concat(f, SEP)) end

	if not e.complete then
		for _, k in ipairs(e.objectives) do
			if k.finished then tip:AddLine(k.text, 0.5, 0.5, 0.5, true) else tip:AddLine(k.text, 1, 1, 1, true) end
			if not k.finished then Sources(tip, k) end
		end
	end

	-- Apart and dim: who takes it in, and the click hint.
	Add(tip, " ")
	if e.turnIn then Add(tip, DIM .. "Turn in to|r " .. e.turnIn, TURN_IN, TURN_IN, TURN_IN) end
	Add(tip, e.followed and UNFOLLOW or FOLLOW)
	tip:Show()
	local n, from = tip:NumLines(), nil -- the small lines in runs: Pins.Small(first, last) sets first + 1 .. last
	for i = 1, n + 1 do
		if small[i] and not from then
			from = i - 1
		elseif not small[i] and from then
			UI.Pins.Small(from, i - 1)
			from = nil
		end
	end
	local owner = tip:GetOwner()
	for line, npc in pairs(mobs) do Command({ kind = "tooltip", owner = owner, npc = npc, line = line }) end
end
