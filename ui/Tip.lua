-- One look for every tip the map shows (GameTooltip's, the popup's: ui/Popup.lua).
-- A hover tip: the thing's name as the title (in the tooltip's text size, not its header's: compact; its icon before it) (the client's white, but where colour means something: a quest's
-- difficulty, a member's class; a number that goes with that colour, a quest's level or a node's skill, in a pill
-- of it beside the title: Pilled), under it what it is ("Herbalism", "Flight point", "Innkeeper") in a muted gold
-- (Sub), then its facts in small type, wrapping, in one grey (DIM), what matters in white, parts of a line apart by
-- SEP; a status ("Not in sight", "Nearby now") a line of its own. No hint lines. A control's: its title alone (Label). A
-- description (the settings window's rows, the gear's): Blizzard's white title, gold body, its default in DIM
-- (Describe). A menu row's icon: Mark.
-- Small type is set through Small, each font string its font back when its tooltip hides or clears (Watch: once a
-- tooltip; GameTooltip here). Nothing here measures a tooltip's own regions: the client answers their widths and
-- places secret (12.x).

local _, ns = ...
local UI, Runtime = ns.UI, ns.Runtime

local Tip = {}
UI.Tip = Tip

Tip.DIM, Tip.WHITE = "|cff9d9d9d", "|cffffffff" -- QuestInfo.lua:180
Tip.GREY = 0x9d / 255 -- DIM as a colour (AddLine's)
Tip.SEP = Tip.DIM .. "  ·  |r"
local GOLD = { 1, 0.82, 0 } -- a description's body (GearMenu.lua:69-72)

-- A tooltip's font strings by name (TextLeft3, TextRight1), found once each.
local regions = setmetatable({}, { __mode = "k" })
function Tip.Region(tip, name)
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
-- Its last line's left font string.
function Tip.Last(tip) return Tip.Region(tip, "TextLeft" .. tip:NumLines()) end

-- fs in small type, its font back when its tooltip hides or clears.
local styled = {} -- fs -> its font object before
local function Font(fs, font)
	if not styled[fs] then styled[fs] = fs:GetFontObject() end
	fs:SetFontObject(font)
end
function Tip.Small(fs) Font(fs, GameTooltipTextSmall) end
-- A title in the tooltip's text size rather than its header's: a compact tip (its font back as Small's).
function Tip.Title(fs) Font(fs, GameTooltipText) end

-- A fact under the title: small, wrapping, DIM (a part coloured itself keeps its colour).
function Tip.Fact(tip, text)
	tip:AddLine(text, Tip.GREY, Tip.GREY, Tip.GREY, true)
	Tip.Small(Tip.Last(tip))
end

-- What it is, under the title: small, wrapping, a muted gold (between the title's white and the facts' DIM).
Tip.SUB = { 0.8, 0.7, 0.45 }
function Tip.Sub(tip, text)
	tip:AddLine(text, Tip.SUB[1], Tip.SUB[2], Tip.SUB[3], true)
	Tip.Small(Tip.Last(tip))
end

local cleared = {} -- fn(tip): more to put back when a tooltip clears (ui/QuestTooltip.lua's level pill)
function Tip.OnClear(fn) cleared[#cleared + 1] = fn end
local function Cleared(tip)
	for fs, font in pairs(styled) do
		if fs:GetParent() == tip then
			fs:SetFontObject(font)
			styled[fs] = nil
		end
	end
	for _, fn in ipairs(cleared) do fn(tip) end
end
function Tip.Watch(tip)
	local fn = Runtime.Wrap("map: tip cleared", Cleared)
	tip:HookScript("OnHide", fn)
	tip:HookScript("OnTooltipCleared", fn)
end
Tip.Watch(GameTooltip)

-- The title with a number beside it in a subtle pill (the number in c on a faint disc-ended bar of it: the client's
-- circle mask, as the dots are), a little room past it before the tooltip's edge: a quest's level, a node's skill.
-- Each its own three regions of tip's, behind the text (stacked titles: one each), hidden when tip clears.
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask" -- the pill's ends (ui/Pins.lua's dots)
local PILL_H, PILL_PAD, PILL_ALPHA = 14, 5, 0.22 -- px tall, px past the number each side; its tint's alpha
local TRAIL = "  " -- after the number: the pill's room from the tooltip's right edge, as from its top

local pills = {} -- tip -> { used, [i] = its three regions }
local function Pill(tip)
	local all = pills[tip]
	if not all then
		all = { used = 0 }
		pills[tip] = all
	end
	all.used = all.used + 1
	local p = all[all.used]
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
	all[all.used] = p
	return p
end
Tip.OnClear(function(tip)
	local all = pills[tip]
	if not all then return end
	all.used = 0
	for _, p in ipairs(all) do
		for _, t in ipairs(p) do t:Hide() end
	end
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

function Tip.Hex(c) return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255) end

-- title in c (a title's font), n in its pill on the right.
function Tip.Pilled(tip, title, n, c)
	tip:AddDoubleLine(title, Tip.Hex(c) .. n .. "|r" .. TRAIL, c[1], c[2], c[3])
	Tip.Title(Tip.Last(tip))
	local fs = Tip.Region(tip, "TextRight" .. tip:NumLines())
	Tip.Small(fs)
	local p = Pill(tip)
	p[1]:ClearAllPoints()
	p[1]:SetPoint("LEFT", fs, "LEFT", -PILL_PAD, 0)
	p[3]:ClearAllPoints()
	p[3]:SetPoint("RIGHT", fs, "LEFT", Width(GameTooltipTextSmall, tostring(n)) + PILL_PAD, 0)
	for _, t in ipairs(p) do
		t:SetVertexColor(c[1], c[2], c[3], PILL_ALPHA)
		t:Show()
	end
end

-- A small picture over a line (a blip's above-or-below arrow on its icon): mark, a texture escape as the client writes
-- it (|Tfile:...|t or |Aatlas:...|a), size px square, its centre x, y px from fs's left middle. Pooled per tip, gone as
-- it clears. False if mark isn't one.
local badges = {}
function Tip.Badge(tip, mark, fs, x, y, size)
	local file = mark:match("^|T([^:|]+)")
	local atlas = not file and mark:match("^|A([^:|]+)")
	if not (file or atlas) then return false end
	local all = badges[tip]
	if not all then
		all = { used = 0 }
		badges[tip] = all
	end
	all.used = all.used + 1
	local t = all[all.used]
	if not t then
		t = tip:CreateTexture(nil, "OVERLAY", nil, 7)
		all[all.used] = t
	end
	if atlas then t:SetAtlas(atlas) else t:SetTexture(file); t:SetTexCoord(0, 1, 0, 1) end
	t:SetSize(size, size)
	t:ClearAllPoints()
	t:SetPoint("CENTER", fs, "LEFT", x, y)
	t:Show()
	return true
end
Tip.OnClear(function(tip)
	local all = badges[tip]
	if not all then return end
	for _, t in ipairs(all) do t:Hide() end
	all.used = 0
end)

-- A description on tooltip (shown by the caller, or a menu's): white title, gold body, then extra (its default) in DIM.
function Tip.Describe(tooltip, title, body, extra)
	tooltip:SetText(title, 1, 1, 1)
	if body then tooltip:AddLine(body, GOLD[1], GOLD[2], GOLD[3], true) end
	if extra then tooltip:AddLine(extra, Tip.GREY, Tip.GREY, Tip.GREY, true) end
end

-- A control's tip: its title alone, right of it (left where the screen's edge is near), or anchor.
local ROOM = 160 -- px past its right edge: room for a short tip
function Tip.Label(owner, text, anchor)
	if not anchor then
		local r, s = owner:GetRight(), owner:GetEffectiveScale()
		anchor = r and r * s + ROOM > UIParent:GetRight() * UIParent:GetEffectiveScale() and "ANCHOR_LEFT" or "ANCHOR_RIGHT"
	end
	GameTooltip:SetOwner(owner, anchor)
	GameTooltip:SetText(text, 1, 1, 1)
	GameTooltip:Show()
end

-- A menu row's icon before its name: 16 px, an Interface\Icons file's border cropped (5:59), an atlas whole (if this
-- client has it), two spaces after; "" for none.
function Tip.Mark(icon)
	if not icon then return "" end
	if type(icon) == "string" and icon:sub(1, 2) == "A:" then
		return C_Texture.GetAtlasInfo(icon:sub(3)) and "|A:" .. icon:sub(3) .. ":16:16|a  " or ""
	end
	return "|T" .. icon .. ":16:16:0:0:64:64:5:59:5:59|t  "
end
