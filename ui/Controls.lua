-- The window's buttons (Core.lua:235-381): on the band, right-aligned on the title's line,
-- the gear (the world map's) and the mode button (its red expand: ui/BigMap.lua); inside
-- the map, the follow toggle (bottom left) and the zoom buttons (bottom right, where the
-- minimap keeps them). They and the grip fade in while you hover (Core.lua:394-408), and
-- each has a tiny tip (Core.lua:1454-1497).

local _, ns = ...
local UI = ns.UI
local Runtime = ns.Runtime
local Camera, Window, Chrome, Menus = UI.Camera, UI.Window, UI.Chrome, UI.Menus

local HEADER_ICON = 20 -- Core.lua:281
local PAD = 12 -- from the map's edges (Core.lua:341)
local TOGGLE = 24 -- Core.lua:351
local FADE = 0.15 -- s, hover reveal (Core.lua:402)
local REACH = HEADER_ICON + 12 -- the title's line counts as over the map (Core.lua:399)
local GRIP_ALPHA = 0.8 -- Core.lua:320
local TIP_DELAY, TIP_LIFE, TIP_FADE = 0.35, 2.5, 0.12 -- s (Core.lua:1457)
local FONT = GameFontNormal:GetFont()

local Controls = {}
UI.Controls = Controls

-- The first of these atlases the client has, if any.
local function FirstAtlas(...)
	for i = 1, select("#", ...) do
		local name = select(i, ...)
		if C_Texture.GetAtlasInfo(name) then return name end
	end
end

-- A button from art = { atlas = {names...}, pushed = {...}, highlight = {...} } (the first each
-- client has), else from file = path with optional coords / pushedCoords into it (Core.lua:249-276):
-- a client without the atlas gets a blank button, as the spike's.
local function ArtButton(parent, w, h, art)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w, h)
	local atlas = art.atlas and FirstAtlas(unpack(art.atlas))
	if atlas then
		b:SetNormalAtlas(atlas)
		local pushed = art.pushed and FirstAtlas(unpack(art.pushed))
		if pushed then b:SetPushedAtlas(pushed) end
		b:SetHighlightAtlas(art.highlight and FirstAtlas(unpack(art.highlight)) or atlas, "ADD")
	else
		b:SetNormalTexture(art.file)
		b:SetPushedTexture(art.file)
		b:SetHighlightTexture(art.file, "ADD")
		if art.coords then -- Core.lua:263
			b:GetNormalTexture():SetTexCoord(unpack(art.coords))
			b:GetHighlightTexture():SetTexCoord(unpack(art.coords))
			b:GetPushedTexture():SetTexCoord(unpack(art.pushedCoords or art.coords))
		end
	end
	return b
end

local function ZoomArt(name)
	return { atlas = { name }, pushed = { name .. "-down" }, highlight = { name .. "-mouseover" } }
end

-- The band's: placed by the title (ui/Title.lua: above the map, or below at the screen's top).
local mode = ArtButton(Chrome.band, HEADER_ICON, HEADER_ICON, {
	atlas = { "redbutton-expand-c60", "redbutton-expand" },
	pushed = { "redbutton-expand-pressed-c60", "redbutton-expand-pressed" },
	highlight = { "redbutton-highlight-c60", "redbutton-highlight" },
})
local gear = ArtButton(Chrome.band, HEADER_ICON + 4, HEADER_ICON + 4, {
	file = "Interface\\WorldMap\\Gear_64", coords = { 0, 0.5, 0, 0.5 }, pushedCoords = { 0, 0.5, 0.5, 1 },
})
gear:SetPoint("RIGHT", mode, "LEFT", -6, 0)
Controls.mode, Controls.gear = mode, gear

local zoomOut = ArtButton(Chrome.controls, 20, 11, ZoomArt("ui-hud-minimap-zoom-out"))
zoomOut:SetPoint("BOTTOMRIGHT", -PAD, PAD + 6) -- clear of the grip
local zoomIn = ArtButton(Chrome.controls, 20, 20, ZoomArt("ui-hud-minimap-zoom-in"))
zoomIn:SetPoint("BOTTOM", zoomOut, "TOP", 0, 2)
Controls.zoomIn, Controls.zoomOut = zoomIn, zoomOut

-- A toggle: a dark disc with an icon, ringed in gold and lit while on (Core.lua:350-381).
local follow = CreateFrame("Button", nil, Chrome.controls)
follow:SetSize(TOGGLE, TOGGLE)
follow:SetPoint("BOTTOMLEFT", PAD, PAD)
follow.ring = follow:CreateTexture(nil, "BACKGROUND", nil, -1)
follow.ring:SetTexture(Chrome.CIRCLE)
follow.ring:SetVertexColor(1, 0.82, 0.3, 0.9)
follow.ring:SetAllPoints()
local disc = follow:CreateTexture(nil, "BACKGROUND")
disc:SetTexture(Chrome.CIRCLE)
disc:SetVertexColor(0, 0, 0, 0.65)
disc:SetPoint("CENTER")
disc:SetSize(TOGGLE - 3, TOGGLE - 3)
follow.icon = follow:CreateTexture(nil, "ARTWORK")
follow.icon:SetAtlas("ui-hud-minimap-arrow-player")
follow.icon:SetPoint("CENTER")
follow.icon:SetSize(TOGGLE - 7, TOGGLE - 7)
local glow = follow:CreateTexture(nil, "HIGHLIGHT")
glow:SetTexture(Chrome.CIRCLE)
glow:SetVertexColor(1, 1, 1, 0.12)
glow:SetAllPoints(disc)
Controls.follow = follow

local function SetLit(b, on)
	b.ring:SetShown(on)
	b.icon:SetDesaturated(not on)
	b.icon:SetAlpha(on and 1 or 0.6)
end

-- Following you, or free: back to you with a glide (Core.lua:1081-1093, 1451, 1703).
local function ToggleFollow() UI.Motion.SetFollow(not Camera.follow, true) end

-- The buttons zoom held on you while following, else on the view's centre (Core.lua:1420-1443).
zoomIn:SetScript("OnClick", Runtime.Wrap("map: zoom in", function() UI.Motion.ZoomStep(1) end))
zoomOut:SetScript("OnClick", Runtime.Wrap("map: zoom out", function() UI.Motion.ZoomStep(-1) end))
follow:SetScript("OnClick", Runtime.Wrap("map: follow", ToggleFollow))
gear:SetScript("OnClick", Runtime.Wrap("map: gear", function(self) Menus.Gear(self) end))

---------------------------------------------------------------------------
-- Hover reveal: the controls and grip fade in while the mouse is over the map
---------------------------------------------------------------------------

local hover, lit = 1, nil
Runtime.Step("ui", "map: hover", function(elapsed)
	if lit ~= Camera.follow then lit = Camera.follow; SetLit(follow, lit) end
	local want = (Window.frame:IsMouseOver(REACH, -REACH, 0, 0) or Menus.IsOpen()) and 1 or 0
	if hover == want then return end
	local step = elapsed / FADE
	hover = want > hover and math.min(want, hover + step) or math.max(want, hover - step)
	Chrome.controls:SetAlpha(hover)
	gear:SetAlpha(hover)
	mode:SetAlpha(hover)
	Chrome.grip:SetAlpha(GRIP_ALPHA * hover)
end, { shownOnly = Window.frame })

---------------------------------------------------------------------------
-- Tips: a word or two in small type just above a button, after a moment's hover, gone when
-- you leave, click, open a menu, or after a couple of seconds anyway
---------------------------------------------------------------------------

local tip = CreateFrame("Frame", nil, UIParent)
tip:SetFrameStrata("TOOLTIP")
tip:Hide()
local plate = tip:CreateTexture(nil, "BACKGROUND")
plate:SetAllPoints()
plate:SetColorTexture(0, 0, 0, 0.6)
local text = tip:CreateFontString(nil, "OVERLAY")
text:SetFont(FONT, 11, "")
text:SetTextColor(0.95, 0.9, 0.8)
text:SetPoint("CENTER")
Controls.tip, Controls.tipText = tip, text

Runtime.Step("ui", "map: tip", function(elapsed)
	tip.t = tip.t + elapsed
	if tip.t > TIP_DELAY + TIP_LIFE or Menus.IsOpen() or not tip.owner:IsMouseOver() then
		tip:Hide()
		return
	end
	if tip.t >= TIP_DELAY then
		if not tip.placed then
			tip.placed = true
			text:SetText(tip.fn())
			tip:SetSize(text:GetStringWidth() + 10, text:GetStringHeight() + 6)
			tip:ClearAllPoints()
			tip:SetPoint("BOTTOM", tip.owner, "TOP", 0, 3)
		end
		tip:SetAlpha(math.min(1, (tip.t - TIP_DELAY) / TIP_FADE))
	end
end, { shownOnly = tip })

local Hide = Runtime.Wrap("map: tip hide", function() tip:Hide() end)

function Controls.Tip(button, fn)
	button:HookScript("OnEnter", Runtime.Wrap("map: tip show", function(self)
		tip.owner, tip.fn, tip.t, tip.placed = self, fn, 0, false
		tip:SetAlpha(0)
		tip:Show()
	end))
	button:HookScript("OnLeave", Hide)
	button:HookScript("OnMouseDown", Hide)
end
Controls.Tip(follow, function() return Camera.follow and "Following" or "Follow" end)
Controls.Tip(zoomIn, function() return "Zoom in" end)
Controls.Tip(zoomOut, function() return "Zoom out" end)
Controls.Tip(gear, function() return "Layers & settings" end)

ns.Game.Command({ kind = "slash", name = "follow", help = "follow you on the map, or stop",
	fn = ToggleFollow })
