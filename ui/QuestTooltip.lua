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
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask" -- the pill's ends (ui/Pins.lua's dots)
local PILL_H, PILL_PAD, PILL_ALPHA = 14, 5, 0.22 -- px tall, px past the number each side; its tint's alpha
local TRAIL = "  " -- after the level: the pill's room from the tooltip's right edge, as from its top

local QuestTooltip = {}
UI.QuestTooltip = QuestTooltip

local function Hex(c)
	return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255)
end

-- The level's pill on tip: three of its own regions behind the text (the circle's halves, a bar between).
local pills = {}
local function Pill(tip)
	local p = pills[tip]
	if p then return p end
	p = { tip:CreateTexture(nil, "BORDER"), tip:CreateTexture(nil, "BORDER"), tip:CreateTexture(nil, "BORDER") }
	p[1]:SetTexture(CIRCLE)
	p[1]:SetTexCoord(0, 0.5, 0, 1)
	p[3]:SetTexture(CIRCLE)
	p[3]:SetTexCoord(0.5, 1, 0, 1)
	p[2]:SetTexture(CIRCLE)
	p[2]:SetTexCoord(0.5, 0.5, 0, 1) -- (the circle's middle column: a bar as tall as the ends)
	p[1]:SetSize(PILL_H / 2, PILL_H)
	p[3]:SetSize(PILL_H / 2, PILL_H)
	p[2]:SetHeight(PILL_H)
	p[2]:SetPoint("LEFT", p[1], "RIGHT")
	p[2]:SetPoint("RIGHT", p[3], "LEFT")
	for _, t in ipairs(p) do t:Hide() end
	pills[tip] = p
	return p
end
Tip.OnClear(function(tip)
	local p = pills[tip]
	if p then for _, t in ipairs(p) do t:Hide() end end
end)

-- Text widths measured on a font string of our own: a tooltip's own regions answer the client's measures secret
-- (no arithmetic on them: 12.x), so nothing here measures a tooltip's.
local ruler = CreateFrame("Frame", nil, UIParent):CreateFontString(nil, "ARTWORK")
ruler:Hide()
local function Width(font, text)
	ruler:SetFontObject(font)
	ruler:SetText(text)
	return ruler:GetStringWidth()
end

-- The pill behind fs's level (its text starts with it), tinted c.
local function ShowPill(tip, fs, c, level)
	local p = Pill(tip)
	p[1]:ClearAllPoints()
	p[1]:SetPoint("LEFT", fs, "LEFT", -PILL_PAD, 0)
	p[3]:ClearAllPoints()
	p[3]:SetPoint("RIGHT", fs, "LEFT", Width(GameTooltipTextSmall, tostring(level)) + PILL_PAD, 0)
	for _, t in ipairs(p) do
		t:SetVertexColor(c[1], c[2], c[3], PILL_ALPHA)
		t:Show()
	end
end

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
	local level = e.level and c and Hex(c) .. e.level .. "|r"
	-- The title, its level's pill beside it, on its line; past the pill, a little room before the edge (TRAIL).
	if level then
		tip:AddDoubleLine(e.name, level .. TRAIL, c[1], c[2], c[3])
		local right = Region(tip, "TextRight1")
		Small(right)
		ShowPill(tip, right, c, e.level)
	elseif c then
		tip:AddLine(e.name, c[1], c[2], c[3])
	else
		tip:AddLine(e.name, 1, 1, 1)
	end
	Tip.Title(Region(tip, "TextLeft1"))

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
