-- The window's chrome: the template's frame (whose top is a header bar) gives way to its
-- metal border on all four sides from the client's frame atlases (UI.lua:1-79); the view
-- fills it, inset by the border's thickness clamped 2..6 (Forever's edge atlases report far
-- more than their visible metal: spike-bugs L2). Above it, at the spike's levels
-- (Core.lua:142-153, 177-182, 316-339): the band (title, gear, mode: ui/Title.lua,
-- ui/Controls.lua), the map's controls and the resize grip. Everything else of the
-- template is hidden (Core.lua:383-392).

local _, ns = ...
local UI = ns.UI
local Runtime = ns.Runtime
local Window = UI.Window
local frame, view = Window.frame, Window.view

local MAX_INSET = 6 -- px a side, at most (UI.lua:73)
local LEVEL_BORDER, LEVEL_BAND, LEVEL_CONTROLS, LEVEL_GRIP = 505, 515, 518, 520 -- over the frame's (Core.lua:181, 319, 333, 339)

local Chrome = { CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask" } -- UI.lua:6
UI.Chrome = Chrome

-- An atlas piece with an optional vertical flip: file + texcoords set here (not SetAtlas)
-- so the bottom corners and edge mirror for the top (UI.lua:17-28).
local function Piece(parent, atlas, flipV)
	local info = C_Texture.GetAtlasInfo(atlas)
	local t = parent:CreateTexture(nil, "OVERLAY")
	t:SetTexture(info.file)
	local l, r, top, bottom = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
	if flipV then top, bottom = bottom, top end
	t:SetTexCoord(l, r, top, bottom)
	t:SetSize(info.width, info.height)
	return t
end

-- ref: the template's NineSlice, whose corners say where the art sits. b.insets = { left,
-- top, right, bottom }: how far in the border reaches, so the view stops there (UI.lua:30-79).
local function Border(level, ref)
	local b = CreateFrame("Frame", nil, frame)
	b:SetAllPoints()
	b:SetFrameLevel(level)
	-- Only the thin bottom corners and edges; the top ones carry a header bar.
	local bl = Piece(b, "UI-Frame-Metal-CornerBottomLeft")
	local br = Piece(b, "UI-Frame-Metal-CornerBottomRight")
	local tl = Piece(b, "UI-Frame-Metal-CornerBottomLeft", true)
	local tr = Piece(b, "UI-Frame-Metal-CornerBottomRight", true)
	local bottom = Piece(b, "_UI-Frame-Metal-EdgeBottom")
	local top = Piece(b, "_UI-Frame-Metal-EdgeBottom", true)
	local left = Piece(b, "!UI-Frame-Metal-EdgeLeft")
	local right = Piece(b, "!UI-Frame-Metal-EdgeRight")
	-- The corner art carries padding; the template knows where it sits.
	local lx, y, rx = -3, -3, 3
	if ref and ref.BottomLeftCorner and ref.BottomRightCorner then
		local _, _, _, x1, y1 = ref.BottomLeftCorner:GetPoint(1)
		local _, _, _, x2 = ref.BottomRightCorner:GetPoint(1)
		if x1 and y1 and x2 then lx, y, rx = x1, y1, x2 end
	end
	bl:SetPoint("BOTTOMLEFT", lx, y)
	br:SetPoint("BOTTOMRIGHT", rx, y)
	tl:SetPoint("TOPLEFT", lx, -y)
	tr:SetPoint("TOPRIGHT", rx, -y)
	-- Edges are uniform strips: stretched, they look tiled.
	bottom:SetPoint("BOTTOMLEFT", bl, "BOTTOMRIGHT")
	bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
	top:SetPoint("TOPLEFT", tl, "TOPRIGHT")
	top:SetPoint("TOPRIGHT", tr, "TOPLEFT")
	left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT")
	left:SetPoint("BOTTOMLEFT", bl, "TOPLEFT")
	right:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT")
	right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
	-- Each edge starts |lx| (|y|) outside the frame; a pixel of overlap so nothing shows
	-- between the art and what it frames; capped (L2).
	local function In(thickness, outside)
		return math.max(2, math.min(MAX_INSET, math.floor((thickness or 0) - outside - 1)))
	end
	b.insets = { In(left:GetWidth(), -lx), In(top:GetHeight(), -y), In(right:GetWidth(), rx), In(bottom:GetHeight(), -y) }
	return b
end

local base = frame:GetFrameLevel()

-- The band: above the border, holding the zone line and its buttons. No mouse of its own.
local band = CreateFrame("Frame", nil, frame)
band:SetFrameLevel(base + LEVEL_BAND)
band:SetAllPoints()
Chrome.band = band

local grip = CreateFrame("Button", nil, frame)
grip:SetSize(14, 14)
grip:SetPoint("BOTTOMRIGHT", -4, 4)
grip:SetFrameLevel(base + LEVEL_GRIP)
grip:SetAlpha(0.8)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
grip:SetScript("OnMouseDown", Runtime.Wrap("map: resize", function() frame:StartSizing("BOTTOMRIGHT") end))
grip:SetScript("OnMouseUp", Runtime.Wrap("map: resized", function()
	frame:StopMovingOrSizing()
	Window.Moved()
end))
Chrome.grip = grip

local border = Border(base + LEVEL_BORDER, frame.NineSlice)
Chrome.border = border

-- Inside the map, shown while you hover: the follow toggle and zoom buttons (ui/Controls.lua).
local controls = CreateFrame("Frame", nil, frame)
controls:SetAllPoints(view)
controls:SetFrameLevel(base + LEVEL_CONTROLS) -- under the grip
Chrome.controls = controls

-- Everything of the template but its border's art goes; the map stops where that art begins.
local KEEP = { [view] = true, [band] = true, [grip] = true, [border] = true, [controls] = true }
for _, r in ipairs({ frame:GetRegions() }) do r:Hide() end
for _, c in ipairs({ frame:GetChildren() }) do
	if not KEEP[c] then c:Hide() end
end
local insets = border.insets
view:ClearAllPoints()
view:SetPoint("TOPLEFT", insets[1], -insets[2])
view:SetPoint("BOTTOMRIGHT", -insets[3], insets[4])
