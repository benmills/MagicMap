-- A quest's tooltip (QuestInfo.lua:244-369), from its Known("quests") entry: the title in its
-- difficulty colour; one compact line of facts (the level in its difficulty colour, no word before it;
-- its tag: Elite, Group N, Dungeon; ready to turn in); what's left to do, an item with where it's found in
-- small type (the objects it's in, else who sells it; never who drops it); then, apart and dim, who takes
-- it in behind the turn-in "?" (the questturnin atlas, the word only where the client lacks it) and the
-- click hint. Small lines get their font back when the tooltip hides or clears (Pins.Small). Without
-- QuestieDB's data Model has no sources or turn-in: none of those lines.

local _, ns = ...
local UI = ns.UI

local ICON = 14 -- px (QuestInfo.lua:135)
local INDENT = "    " -- QuestInfo.lua:175
local DIM, WHITE = "|cff9d9d9d", "|cffffffff" -- QuestInfo.lua:180
local GREEN, ORANGE = "|cff33ff33", "|cffff8040" -- QuestInfo.lua:253
local SEP = DIM .. "  ·  |r"
local TURN_IN = 0.85 -- QuestInfo.lua:358
local TURN_IN_ATLAS = "questturnin" -- the "?" before who takes it in (ui/Quests.lua's pin); the word where the client lacks it
local turnInMark -- "|A:...|a " or the dim word, found once
local HINT = DIM .. "Click for options|r" -- (the pin's menu: ui/Track.lua)

local QuestTooltip = {}
UI.QuestTooltip = QuestTooltip

local function Hex(c)
	return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255)
end

local small, facts = {}, {} -- line -> true; the facts line's

local function Add(tip, text, r, g, b)
	tip:AddLine(text, r, g, b)
	small[tip:NumLines()] = true
end

-- Where an objective's item is found, small (QuestInfo.lua:213-242, less its droppers).
local function Sources(tip, k)
	if k.from then
		Add(tip, INDENT .. DIM .. "From|r " .. WHITE .. k.from .. "|r", 1, 1, 1)
	elseif k.sold then
		Add(tip, INDENT .. DIM .. "Sold by|r " .. WHITE .. k.sold .. "|r", 1, 1, 1)
	end
end

-- e's tooltip on GameTooltip (owned by the caller), the click hint last. QuestInfo.lua:308-369.
function QuestTooltip.Show(e)
	local tip, c = GameTooltip, e.color
	for k in pairs(small) do small[k] = nil end
	if c then tip:AddLine(e.name, c[1], c[2], c[3]) else tip:AddLine(e.name) end

	-- Facts: level, tag (Elite, Group (3), Dungeon), ready.
	local f = facts
	for i = #f, 1, -1 do f[i] = nil end
	if e.level then f[#f + 1] = Hex(c) .. e.level .. "|r" end
	if e.tag then f[#f + 1] = ORANGE .. e.tag .. (e.group and e.group > 1 and " " .. e.group or "") .. "|r" end
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
	if e.turnIn then
		if not turnInMark then
			turnInMark = C_Texture.GetAtlasInfo(TURN_IN_ATLAS) and "|A:" .. TURN_IN_ATLAS .. ":" .. ICON .. ":" .. ICON .. "|a "
				or DIM .. "Turn in to|r "
		end
		Add(tip, turnInMark .. e.turnIn, TURN_IN, TURN_IN, TURN_IN)
	end
	Add(tip, HINT)
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
end
