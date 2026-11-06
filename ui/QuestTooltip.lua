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
-- way to a divider (the client menu's, MenuVariants.lua:26) and a line of small buttons, the pin's rows
-- (ui/Track.lua's Track.QuestRows): Track and Path to, each Blizzard's small red button with a gold glyph (gold-
-- trimmed while it's what you do), and the micro menu's quest log button; each names itself in a tooltip on hover. Unlike the tooltip it stays: until a row is picked, a click
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
local RED_BTN, GOLD_BTN = "128-redbutton", "128-goldredbutton" -- the buttons' art: Blizzard's red button, gold-trimmed
local GOLD = { 1, 0.82, 0 } -- a glyph made gold (the red buttons' own glyphs' colour)
local BTN, BTN_GAP, GLYPH = 22, 3, 0.6 -- the buttons: px square, px apart; a glyph's longer side, of the button
-- w, h of a glyph whose longer side is n, at its atlas's proportions.
local function Fit(n, info)
	local w, h = info.width, info.height
	if w >= h then return n, n * h / w end -- /: never 0 (w >= h > 0)
	return n * w / h, n -- /: never 0 (h > w >= 0)
end
local PILL_H, PILL_PAD, PILL_ALPHA = 14, 5, 0.22 -- px tall, px past the number each side; its tint's alpha
local FIT = 260 -- px: the title and its pill fit on one line within this (a tooltip's usual widest), else the pill goes under
local CURSOR_GAP = 16 -- px: the popup right of the cursor when the tooltip's place is secret
local ROW_INSET = 6 -- px: the popup's buttons in from its edge
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

-- Text widths measured on a font string of our own: a tooltip's own regions answer the client's measures secret
-- (no arithmetic on them: 12.x), so nothing here measures a tooltip's.
local ruler = CreateFrame("Frame", nil, UIParent):CreateFontString(nil, "ARTWORK")
ruler:Hide()
local function Width(font, text)
	ruler:SetFontObject(font)
	ruler:SetText(text)
	return ruler:GetStringWidth()
end
-- A frame's measure, or nil where the client keeps it secret.
local function Plain(v)
	if v ~= nil and not issecretvalue(v) then return v end
end

-- The pill behind fs (its text the level, in font), tinted c.
local function ShowPill(tip, fs, c, level)
	local p = Pill(tip)
	local w = Width(GameTooltipTextSmall, level) + 2 * PILL_PAD
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
		if Width(GameTooltipHeaderText, e.name) + PILL_PAD * 4 + Width(GameTooltipTextSmall, level) > FIT then
			right:SetText("")
			below = true
		else
			ShowPill(tip, right, c, level)
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
		ShowPill(tip, fs, c, level)
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
local rows = {} -- its buttons, made as needed
QuestTooltip.rows = rows

-- A row's button: Blizzard's small red square button (its 128-redbutton art: the left end of the wide button's
-- left piece and the right end of its right, a square together; gold-trimmed, 128-goldredbutton, while it's what you
-- do) with a gold glyph, or an atlas button's own art (the micro menu's quest log); its label in a tooltip on hover.
local function Tip(b)
	GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
	GameTooltip:SetText(b.label, 1, 1, 1)
	GameTooltip:Show()
end
-- t shows the left (or right) square half of a wide atlas: its height over two, from that end.
local function Half(t, atlas, right)
	local info = C_Texture.GetAtlasInfo(atlas)
	local l, r = info.leftTexCoord, info.rightTexCoord
	local f = (r - l) * info.height / 2 / info.width -- /: never 0 (an atlas's width is > 0)
	if right then l = r - f else r = l + f end
	t:SetTexture(info.file)
	t:SetTexCoord(l, r, info.topTexCoord, info.bottomTexCoord)
end
local function Face(b, kind) -- kind: "", "-pressed"
	local base = b.on and GOLD_BTN or RED_BTN
	Half(b.l, base .. "-left" .. kind)
	Half(b.r, base .. "-right" .. kind, true)
	b.glyph:SetPoint("CENTER", 0, kind == "" and 0 or -1)
end
local function Row(i)
	local b = rows[i]
	if b then return b end
	b = CreateFrame("Button", nil, popup)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b.l, b.r = b:CreateTexture(nil, "BACKGROUND"), b:CreateTexture(nil, "BACKGROUND")
	b.l:SetPoint("TOPLEFT")
	b.l:SetPoint("BOTTOMRIGHT", b, "BOTTOM")
	b.r:SetPoint("TOPRIGHT")
	b.r:SetPoint("BOTTOMLEFT", b, "BOTTOM")
	b.hl, b.hr = b:CreateTexture(nil, "HIGHLIGHT"), b:CreateTexture(nil, "HIGHLIGHT")
	b.hl:SetAllPoints(b.l)
	b.hr:SetAllPoints(b.r)
	b.hl:SetBlendMode("ADD")
	b.hr:SetBlendMode("ADD")
	b.glyph = b:CreateTexture(nil, "ARTWORK")
	b:SetScript("OnMouseDown", Runtime.Wrap("map: quest popup button", function() if b.red then Face(b, "-pressed") end end))
	b:SetScript("OnMouseUp", Runtime.Wrap("map: quest popup button", function() if b.red then Face(b, "") end end))
	b:SetScript("OnEnter", Runtime.Wrap("map: quest popup button", function() Tip(b) end))
	b:SetScript("OnLeave", Runtime.Wrap("map: quest popup button", function() GameTooltip:Hide() end))
	b:SetScript("OnClick", Runtime.Wrap("map: quest popup pick", function()
		local fn = b.fn
		GameTooltip:Hide()
		popup:Hide()
		fn()
	end))
	rows[i] = b
	return b
end

-- r: a QuestRows row { label, fn, icon = { atlas, gold? } | { up, down, lit, aspect }, on? }.
local function Dress(b, r)
	local ic = r.icon
	b.fn, b.label, b.on, b.red = r[2], r[1], r.on, not ic.up
	if ic.up then -- an atlas button (the micro menu's): its own art, its own proportions
		b:SetSize(BTN * ic.aspect, BTN)
		b:SetNormalAtlas(ic.up)
		b:SetPushedAtlas(ic.down)
		b:SetHighlightAtlas(ic.lit, "ADD")
		return
	end
	b:SetSize(BTN, BTN)
	Face(b, "")
	Half(b.hl, RED_BTN .. "-highlight")
	Half(b.hr, RED_BTN .. "-highlight", true)
	local g = b.glyph
	g:SetAtlas(ic.atlas)
	g:SetSize(Fit(BTN * GLYPH, C_Texture.GetAtlasInfo(ic.atlas)))
	g:SetDesaturated(ic.gold or false)
	if ic.gold then g:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1) else g:SetVertexColor(1, 1, 1, 1) end
end

popup:HookScript("OnHide", Runtime.Wrap("map: quest popup hidden", function()
	showing = nil
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
		local l, t = Plain(GameTooltip:GetLeft()), Plain(GameTooltip:GetTop())
		if l and t then
			at.x, at.y = l * gs / ps, t * gs / ps -- /: never 0 (a scale is > 0)
		else -- (secret: by the cursor, as the tooltip stood beside it)
			local x, y = GetCursorPosition()
			at.x, at.y = x / ps + CURSOR_GAP, y / ps -- /: never 0 (a scale is > 0)
		end
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
	popup:AddLine(" ") -- (the buttons' lines: two, their height)
	local line = Region(popup, "TextLeft" .. popup:NumLines())
	popup:AddLine(" ")
	popup:Show()
	divider:ClearAllPoints()
	divider:SetPoint("LEFT", gap, "LEFT", ROW_INSET - PAD, 0)
	local w = Plain(popup:GetWidth())
	if w then divider:SetWidth(w - 2 * ROW_INSET) end
	local prev
	for i, r in ipairs(list) do
		local b = Row(i)
		Dress(b, r)
		b:ClearAllPoints()
		if prev then b:SetPoint("LEFT", prev, "RIGHT", BTN_GAP, 0)
		else b:SetPoint("TOPLEFT", line, "TOPLEFT", ROW_INSET - PAD, 0) end
		b:Show()
		prev = b
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
