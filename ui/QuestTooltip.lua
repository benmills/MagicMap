-- A quest's tooltip (QuestInfo.lua:244-369), from its Known("quests") entry: the title in its
-- difficulty colour, its level in a subtle pill beside it (the number in that colour on a faint disc-ended
-- bar of it: the client's circle mask, as the dots are) where the two fit on one line, else just under it;
-- one compact line of facts (its tag: Elite, Group N, Dungeon; ready to turn in); what's left to do, an
-- item with where it's found in small type (the objects it's in, else who sells it; never who drops it);
-- then, apart and dim, the click hint. Small lines get their font back when the tooltip hides or clears.
-- Without QuestieDB's data Model has no sources: none of those lines.
--
-- The tooltip becomes the popup (a click on a quest pin: ui/Quests.lua's click). The popup is a tooltip
-- too, a second GameTooltipTemplate frame (MagicMapQuestPopup), filled by the same code with the same
-- lines in the same fonts, put where the hover's tooltip stood (its top left, its scale) as that one
-- hides: the panel stays where it was, its lines where they were, and only grows, the click hint giving
-- way to a divider (the client menu's, MenuVariants.lua:26) and the pin's rows (ui/Track.lua's
-- Track.QuestRows: Track quest, Path to quest, Open in quest log), each a button over its line lit as a
-- menu row is (MenuVariants.lua:46). Unlike the tooltip it stays: until a row is picked, a click
-- anywhere off it (a button pressed, looked at once a frame), Escape (game/Hooks.lua names it in
-- UISpecialFrames) or the map hidden. While it shows a quest, that quest's pin shows no hover tooltip;
-- it counts as a menu open (ui/Menus.lua's IsOpen: the controls stay).

local _, ns = ...
local UI, Runtime = ns.UI, ns.Runtime

local INDENT = "    " -- QuestInfo.lua:175
local DIM, WHITE = "|cff9d9d9d", "|cffffffff" -- QuestInfo.lua:180
local GREEN, ORANGE = "|cff33ff33", "|cffff8040" -- QuestInfo.lua:253
local SEP = DIM .. "  ·  |r"
local HINT = DIM .. "Click for options|r" -- (the popup: below)
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask" -- the pill's ends (ui/Pins.lua's dots)
local DIVIDER = "Interface\\Common\\UI-TooltipDivider-Transparent" -- MenuVariants.lua:26
local HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight" -- MenuVariants.lua:46
local PILL_H, PILL_PAD, PILL_ALPHA = 14, 5, 0.22 -- px tall, px past the number each side; its tint's alpha
local FIT = 260 -- px: the title and its pill fit on one line within this (a tooltip's usual widest), else the pill goes under
local ROW_H, ROW_INSET = 18, 4 -- the popup's rows: px tall, px in from its edges
local PAD = 10 -- px: a tooltip's text in from its left edge (GameTooltipTemplate)

local QuestTooltip = {}
UI.QuestTooltip = QuestTooltip

local function Hex(c)
	return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255)
end

-- A tooltip's font strings by name (TextLeft3, TextRight1), found once each.
local regions = setmetatable({}, { __mode = "k" })
local function Region(tip, name)
	local t = regions[tip]
	if not t then
		t = {}
		regions[tip] = t
	end
	if not t[name] then
		local full = tip:GetName() .. name
		for _, r in ipairs({ tip:GetRegions() }) do
			if r:GetName() == full then t[name] = r end
		end
	end
	return t[name]
end

-- Font strings set small, each its font back when its tooltip hides or clears (as ui/Pins.lua's Small).
local styled = {} -- fs -> its font object before
local function Small(fs)
	if not styled[fs] then styled[fs] = fs:GetFontObject() end
	fs:SetFontObject(GameTooltipTextSmall)
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

-- The pill behind fs (its text the level), tinted c.
local function ShowPill(tip, fs, c)
	local p = Pill(tip)
	local w = fs:GetStringWidth() + 2 * PILL_PAD
	p[1]:ClearAllPoints()
	p[1]:SetPoint("LEFT", fs, "CENTER", -w / 2, 0)
	p[3]:ClearAllPoints()
	p[3]:SetPoint("RIGHT", fs, "CENTER", w / 2, 0)
	for _, t in ipairs(p) do
		t:SetVertexColor(c[1], c[2], c[3], PILL_ALPHA)
		t:Show()
	end
end

local function Cleared(tip)
	for fs, font in pairs(styled) do
		if fs:GetParent() == tip then
			fs:SetFontObject(font)
			styled[fs] = nil
		end
	end
	local p = pills[tip]
	if p then for _, t in ipairs(p) do t:Hide() end end
end
local function Watch(tip)
	local fn = Runtime.Wrap("map: quest tip cleared", Cleared)
	tip:HookScript("OnHide", fn)
	tip:HookScript("OnTooltipCleared", fn)
end
Watch(GameTooltip)

-- Where an objective's item is found, small (QuestInfo.lua:213-242, less its droppers).
local function Sources(tip, k)
	if k.from then
		tip:AddLine(INDENT .. DIM .. "From|r " .. WHITE .. k.from .. "|r", 1, 1, 1)
	elseif k.sold then
		tip:AddLine(INDENT .. DIM .. "Sold by|r " .. WHITE .. k.sold .. "|r", 1, 1, 1)
	else
		return
	end
	Small(Region(tip, "TextLeft" .. tip:NumLines()))
end

local facts = {}

-- e's lines on tip (owned by the caller), up to the blank line before the hint or the rows. QuestInfo.lua:308-369.
local function Fill(tip, e)
	local c = e.color
	local level = e.level and c and Hex(c) .. e.level .. "|r"
	-- The title, its level's pill beside it where both fit, else just under it.
	local below = false
	if level then
		tip:AddDoubleLine(e.name, level, c[1], c[2], c[3])
		local title, right = Region(tip, "TextLeft1"), Region(tip, "TextRight1")
		Small(right)
		if title:GetStringWidth() + PILL_PAD * 4 + right:GetStringWidth() > FIT then
			right:SetText("")
			below = true
		else
			ShowPill(tip, right, c)
		end
	elseif c then
		tip:AddLine(e.name, c[1], c[2], c[3])
	else
		tip:AddLine(e.name)
	end
	if below then
		tip:AddLine(level)
		local fs = Region(tip, "TextLeft2")
		Small(fs)
		ShowPill(tip, fs, c)
	end

	-- Facts: tag (Elite, Group (3), Dungeon), ready.
	local f = facts
	for i = #f, 1, -1 do f[i] = nil end
	if e.tag then f[#f + 1] = ORANGE .. e.tag .. (e.group and e.group > 1 and " " .. e.group or "") .. "|r" end
	if e.complete then f[#f + 1] = GREEN .. "Ready to turn in|r" end
	if f[1] then
		tip:AddLine(table.concat(f, SEP))
		Small(Region(tip, "TextLeft" .. tip:NumLines()))
	end

	if not e.complete then
		for _, k in ipairs(e.objectives) do
			if k.finished then tip:AddLine(k.text, 0.5, 0.5, 0.5, true) else tip:AddLine(k.text, 1, 1, 1, true) end
			if not k.finished then Sources(tip, k) end
		end
	end
	tip:AddLine(" ")
	Small(Region(tip, "TextLeft" .. tip:NumLines()))
end

---------------------------------------------------------------------------
-- The popup
---------------------------------------------------------------------------

local popup = CreateFrame("GameTooltip", "MagicMapQuestPopup", UIParent, "GameTooltipTemplate")
popup:Hide()
popup:EnableMouse(true) -- (a click on it is its own, not the map's under it)
popup:SetClampedToScreen(true)
QuestTooltip.popup = popup
Watch(popup)
local showing -- the quest the popup shows
local divider = popup:CreateTexture(nil, "ARTWORK")
divider:SetTexture(DIVIDER)
divider:SetHeight(13)
local lit = popup:CreateTexture(nil, "BORDER")
lit:SetTexture(HIGHLIGHT)
lit:SetBlendMode("ADD")
lit:Hide()
local rows = {} -- its buttons, made as needed
QuestTooltip.rows = rows

local function Row(i)
	local b = rows[i]
	if b then return b end
	b = CreateFrame("Button", nil, popup)
	b:SetHeight(ROW_H)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetScript("OnEnter", Runtime.Wrap("map: quest popup row", function()
		lit:ClearAllPoints()
		lit:SetAllPoints(b)
		lit:Show()
	end))
	b:SetScript("OnLeave", Runtime.Wrap("map: quest popup row", function() lit:Hide() end))
	b:SetScript("OnClick", Runtime.Wrap("map: quest popup pick", function()
		local fn = b.fn
		popup:Hide()
		fn()
	end))
	rows[i] = b
	return b
end

popup:HookScript("OnHide", Runtime.Wrap("map: quest popup hidden", function()
	showing = nil
	lit:Hide()
end))

-- The popup shows a quest (its pin's tooltip waits while it does).
function QuestTooltip.IsOpen()
	return popup:IsShown()
end

-- The hover's tooltip, on GameTooltip (owned by the caller): e's lines, then the click hint; none while the
-- popup shows e's quest.
function QuestTooltip.Show(e)
	if showing == e.quest then return end
	Fill(GameTooltip, e)
	GameTooltip:AddLine(HINT)
	Small(Region(GameTooltip, "TextLeft" .. GameTooltip:NumLines()))
	GameTooltip:Show()
end

-- The click: the tooltip grows into the popup, in its place (again where the popup last stood while the
-- tooltip waited for it).
local at = { x = 0, y = 0, scale = 1 } -- where the popup last stood: its top left in its units, its scale
function QuestTooltip.Open(e)
	if GameTooltip:IsShown() then
		-- (its top left in screen px, then in the popup's units: UIParent's scale times its own, the tooltip's)
		local gs, ps = GameTooltip:GetEffectiveScale(), UIParent:GetEffectiveScale() * GameTooltip:GetScale()
		at.x, at.y = GameTooltip:GetLeft() * gs / ps, GameTooltip:GetTop() * gs / ps -- /: never 0 (a scale is > 0)
		at.scale = GameTooltip:GetScale()
		GameTooltip:Hide()
	end
	popup:SetOwner(UIParent, "ANCHOR_NONE")
	popup:SetScale(at.scale)
	popup:ClearAllPoints()
	popup:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", at.x, at.y)
	showing = e.quest
	Fill(popup, e)
	local gap = Region(popup, "TextLeft" .. popup:NumLines())
	local list = UI.Track.QuestRows(e)
	for _, r in ipairs(list) do popup:AddLine(r[1], 1, 1, 1) end
	popup:Show()
	local w, first = popup:GetWidth() - 2 * ROW_INSET, popup:NumLines() - #list
	divider:ClearAllPoints()
	divider:SetPoint("LEFT", gap, "LEFT", ROW_INSET - PAD, 0)
	divider:SetWidth(w)
	for i, r in ipairs(list) do
		local b = Row(i)
		b.fn, b.label = r[2], r[1]
		b:ClearAllPoints()
		b:SetPoint("LEFT", Region(popup, "TextLeft" .. first + i), "LEFT", ROW_INSET - PAD, 0)
		b:SetWidth(w)
		b:Show()
	end
	for i = #list + 1, #rows do rows[i]:Hide() end
end

-- Closed by a press off it (either button), or the map hidden.
local down = false
Runtime.Step("ui", "map: quest popup", function()
	local now = IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")
	if now and not down and not popup:IsMouseOver() then popup:Hide() end
	down = now
end, { shownOnly = popup })
UI.Window.frame:HookScript("OnHide", Runtime.Wrap("map: quest popup", function() popup:Hide() end))
