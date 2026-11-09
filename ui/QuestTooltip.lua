-- A quest's tooltip (QuestInfo.lua:244-369), from its Known("quests") entry, in the map's one tip look (ui/Tip.lua):
-- the title in its difficulty colour, its level in a subtle pill beside it (the number in that colour on a faint
-- disc-ended bar of it: the client's circle mask, as the dots are) on its line, a little room past it;
-- one compact line of facts in DIM (its tag: Elite, Group N, Dungeon; ready to turn in, in white); what's left to do
-- in small white (done, grey), an item with where it's found in small type (the objects it's in, else who sells it;
-- never who drops it). No hint: a click grows it into the popup (ui/Popup.lua: the pin's actions, ui/Track.lua).
-- Small lines get their font back, and the pill goes, when the tooltip hides or clears (ui/Tip.lua's Watch).
-- Without QuestieDB's data Model has no sources: none of those lines.

local _, ns = ...
local UI = ns.UI
local Tip = UI.Tip
local Region, Small = Tip.Region, Tip.Small

local INDENT = "    " -- QuestInfo.lua:175
local DIM, WHITE, SEP = Tip.DIM, Tip.WHITE, Tip.SEP
local QuestTooltip = {}
UI.QuestTooltip = QuestTooltip

-- Where an objective's item is found, small (QuestInfo.lua:213-242, less its droppers).
local function Sources(tip, k)
	if k.from then
		tip:AddLine(INDENT .. DIM .. "From|r " .. WHITE .. k.from .. "|r", 1, 1, 1)
	elseif k.sold then
		tip:AddLine(INDENT .. DIM .. "Sold by|r " .. WHITE .. k.sold .. "|r", 1, 1, 1)
	else
		return
	end
	Small(Tip.Last(tip))
end

local facts = {}

-- e's lines on tip (owned by the caller, shown by it): the hover's tooltip and the popup's (ui/Popup.lua).
-- QuestInfo.lua:308-369.
function QuestTooltip.Fill(tip, e)
	local c = e.color
	-- The title, its level's pill beside it (Tip.Pilled).
	if e.level and c then
		Tip.Pilled(tip, e.name, e.level, c)
	else
		c = c or { 1, 1, 1 }
		tip:AddLine(e.name, c[1], c[2], c[3])
		Tip.Title(Region(tip, "TextLeft1"))
	end

	-- Facts: tag (Elite, Group 3, Dungeon), ready.
	local f = facts
	for i = #f, 1, -1 do f[i] = nil end
	if e.tag then f[#f + 1] = DIM .. e.tag .. (e.group and e.group > 1 and " " .. e.group or "") .. "|r" end
	if e.complete then f[#f + 1] = WHITE .. "Ready to turn in|r" end
	if f[1] then Tip.Fact(tip, table.concat(f, SEP)) end

	if not e.complete then
		for _, k in ipairs(e.objectives) do
			local v = k.finished and Tip.GREY or 1
			tip:AddLine(k.text, v, v, v, true)
			Small(Tip.Last(tip))
			if not k.finished then Sources(tip, k) end
		end
	end
end
