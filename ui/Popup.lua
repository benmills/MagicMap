-- The popup: a click on any pin (ui/Pins.lua's Tap, a group's grid icons too: ui/Cluster.lua; the quest pill,
-- ui/Controls.lua) grows its hover tooltip into it. A tooltip too, a second GameTooltipTemplate frame
-- (MagicMapPopup), filled by the same filler with the same lines in the same fonts (the pin layer's tooltip or
-- lines), put where the hover's tooltip stood (its top left, its scale) as that one hides: the panel stays where it
-- was, its lines where they were, and only grows, by a divider (the client menu's, MenuVariants.lua:26) and a line of
-- small buttons, the pin's actions (ui/Track.lua's Track.Actions): Track and Path to, each Blizzard's small red
-- button with a gold glyph (gold-trimmed while it's what you do); a quest's quest log, the micro menu's button; your
-- waypoint's Clear, Blizzard's red delete button. Each names itself in a tooltip on hover. Unlike the tooltip it
-- stays: until a button is picked, a click anywhere off it (a button pressed, looked at once a frame), Escape
-- (game/Hooks.lua names it in UISpecialFrames) or the map hidden. While it shows, no pin or area shows a hover
-- tooltip; it counts as a menu open (ui/Menus.lua's IsOpen: the controls stay).

local _, ns = ...
local UI, Runtime = ns.UI, ns.Runtime
local Tip = UI.Tip

local DIVIDER = "Interface\\Common\\UI-TooltipDivider-Transparent" -- MenuVariants.lua:26
local RED_BTN, GOLD_BTN = "128-redbutton", "128-goldredbutton" -- the buttons' art: Blizzard's red button, gold-trimmed
local GOLD = { 1, 0.82, 0 } -- a glyph made gold (the red buttons' own glyphs' colour)
local BTN, BTN_GAP, GLYPH = 22, 3, 0.6 -- the buttons: px square, px apart; a glyph's longer side, of the button
local CURSOR_GAP = 16 -- px: the popup right of the cursor when the tooltip's place is secret
local ROW_INSET = 6 -- px: the popup's buttons in from its edge
local PAD = 10 -- px: a tooltip's text in from its left edge (GameTooltipTemplate)

local Popup = {}
UI.Popup = Popup

-- w, h of a glyph whose longer side is n, at its atlas's proportions.
local function Fit(n, info)
	local w, h = info.width, info.height
	if w >= h then return n, n * h / w end -- /: never 0 (w >= h > 0)
	return n * w / h, n -- /: never 0 (h > w >= 0)
end

-- A frame's measure, or nil where the client keeps it secret.
local function Plain(v)
	if v ~= nil and not issecretvalue(v) then return v end
end

-- Spaces at least w px wide in GameTooltipText, measured on a font string of our own (a tooltip's own answer secret):
-- the buttons' line, so the popup is as wide as its buttons.
local ruler = CreateFrame("Frame", nil, UIParent):CreateFontString(nil, "ARTWORK")
ruler:Hide()
ruler:SetFontObject(GameTooltipText)
local function Spaces(w)
	ruler:SetText("    ")
	local four = ruler:GetStringWidth()
	return string.rep("    ", four > 0 and math.ceil(w / four) or 1) -- /: never 0 (checked beside it)
end

local popup = CreateFrame("GameTooltip", "MagicMapPopup", UIParent, "GameTooltipTemplate")
popup:Hide()
popup:EnableMouse(true) -- (a click on it is its own, not the map's under it)
popup:SetClampedToScreen(true)
Popup.frame = popup
Tip.Watch(popup)
local divider = popup:CreateTexture(nil, "ARTWORK")
divider:SetTexture(DIVIDER)
divider:SetHeight(13)
local pools = { red = {}, art = {} } -- its buttons by kind, made as needed
Popup.buttons = {} -- those it shows, in order

-- t shows the left (or right) square half of a wide atlas: its height over two, from that end.
local function Half(t, atlas, right)
	local info = C_Texture.GetAtlasInfo(atlas)
	local l, r = info.leftTexCoord, info.rightTexCoord
	local f = (r - l) * info.height / 2 / info.width -- /: never 0 (an atlas's width is > 0)
	if right then l = r - f else r = l + f end
	t:SetTexture(info.file)
	t:SetTexCoord(l, r, info.topTexCoord, info.bottomTexCoord)
end
-- A red button's face (kind: "", "-pressed"): Blizzard's small red square button (its 128-redbutton art: the left
-- end of the wide button's left piece and the right end of its right, a square together; gold-trimmed,
-- 128-goldredbutton, while it's what you do).
local function Face(b, kind)
	local base = b.on and GOLD_BTN or RED_BTN
	Half(b.l, base .. "-left" .. kind)
	Half(b.r, base .. "-right" .. kind, true)
	b.glyph:SetPoint("CENTER", 0, kind == "" and 0 or -1)
end

-- A button of kind "red" (the red square with a gold glyph) or "art" (an atlas button's own art: the micro menu's
-- quest log, Blizzard's red delete), its label in a tooltip on hover.
local function Button(kind, i)
	local pool = pools[kind]
	local b = pool[i]
	if b then return b end
	b = CreateFrame("Button", nil, popup)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	if kind == "red" then
		b.l, b.r = b:CreateTexture(nil, "BACKGROUND"), b:CreateTexture(nil, "BACKGROUND")
		b.l:SetPoint("TOPLEFT")
		b.l:SetPoint("BOTTOMRIGHT", b, "BOTTOM")
		b.r:SetPoint("TOPRIGHT")
		b.r:SetPoint("BOTTOMLEFT", b, "BOTTOM")
		local hl, hr = b:CreateTexture(nil, "HIGHLIGHT"), b:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints(b.l)
		hr:SetAllPoints(b.r)
		hl:SetBlendMode("ADD")
		hr:SetBlendMode("ADD")
		Half(hl, RED_BTN .. "-highlight")
		Half(hr, RED_BTN .. "-highlight", true)
		b.glyph = b:CreateTexture(nil, "ARTWORK")
		b:SetScript("OnMouseDown", Runtime.Wrap("map: popup button", function() Face(b, "-pressed") end))
		b:SetScript("OnMouseUp", Runtime.Wrap("map: popup button", function() Face(b, "") end))
	end
	b:SetScript("OnEnter", Runtime.Wrap("map: popup button", function() Tip.Label(b, b.label) end))
	b:SetScript("OnLeave", Runtime.Wrap("map: popup button", function() GameTooltip:Hide() end))
	b:SetScript("OnClick", Runtime.Wrap("map: popup pick", function()
		local fn = b.fn
		GameTooltip:Hide()
		popup:Hide()
		fn()
	end))
	pool[i] = b
	return b
end

-- a: an action { label, fn, icon = { atlas, gold? } | { up, down, lit, aspect, blend? }, on? }, dressed on its button.
local function Dress(a, n)
	local ic = a.icon
	local b = Button(ic.up and "art" or "red", n)
	b.fn, b.label, b.on = a[2], a[1], a.on
	if ic.up then -- an atlas button: its own art, its own proportions
		b:SetSize(BTN * ic.aspect, BTN)
		b:SetNormalAtlas(ic.up)
		b:SetPushedAtlas(ic.down)
		b:SetHighlightAtlas(ic.lit, ic.blend)
		return b
	end
	b:SetSize(BTN, BTN)
	Face(b, "")
	local g = b.glyph
	g:SetAtlas(ic.atlas)
	g:SetSize(Fit(BTN * GLYPH, C_Texture.GetAtlasInfo(ic.atlas)))
	g:SetDesaturated(ic.gold or false)
	if ic.gold then g:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1) else g:SetVertexColor(1, 1, 1, 1) end
	return b
end

-- The popup stands (no hover tooltips while it does).
function Popup.IsOpen()
	return popup:IsShown()
end

-- The click: the hover's tooltip (GameTooltip) grows into the popup, in its place (again where the popup last
-- stood while the tooltip waited for it). fill(tip): the pin's lines on tip (the hover's filler); actions: its
-- buttons, in order.
local at = { x = 0, y = 0, scale = 1 } -- where the popup last stood: its top left in its units, its scale
local used = { red = 0, art = 0 }
function Popup.Open(fill, actions)
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
	fill(popup)
	popup:AddLine(" ") -- (the divider's line)
	local gap = Tip.Last(popup)
	Tip.Small(gap)
	local list, w = Popup.buttons, 0
	used.red, used.art = 0, 0
	for i = #list, 1, -1 do list[i] = nil end
	for i, a in ipairs(actions) do
		local kind = a.icon.up and "art" or "red"
		used[kind] = used[kind] + 1
		local b = Dress(a, used[kind])
		list[i] = b
		w = w + (a.icon.up and BTN * a.icon.aspect or BTN) + (i > 1 and BTN_GAP or 0)
	end
	popup:AddLine(Spaces(w + 2 * ROW_INSET - 2 * PAD)) -- (the buttons' lines: two, their height; as wide as they are)
	local line = Tip.Last(popup)
	popup:AddLine(" ")
	popup:Show()
	divider:ClearAllPoints()
	divider:SetPoint("LEFT", gap, "LEFT", ROW_INSET - PAD, 0)
	local pw = Plain(popup:GetWidth())
	if pw then divider:SetWidth(pw - 2 * ROW_INSET) end
	for i, b in ipairs(list) do
		b:ClearAllPoints()
		if i > 1 then b:SetPoint("LEFT", list[i - 1], "RIGHT", BTN_GAP, 0)
		else b:SetPoint("TOPLEFT", line, "TOPLEFT", ROW_INSET - PAD, 0) end
		b:Show()
	end
	for kind, pool in pairs(pools) do
		for i = used[kind] + 1, #pool do pool[i]:Hide() end
	end
end

-- Closed by a press off it (either button), or the map hidden.
local down = false
Runtime.Step("ui", "map: popup", function()
	local now = IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")
	if now and not down and not popup:IsMouseOver() then popup:Hide() end
	down = now
end, { shownOnly = popup })
UI.Window.frame:HookScript("OnHide", Runtime.Wrap("map: popup", function() popup:Hide() end))
