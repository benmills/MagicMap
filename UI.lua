-- Chrome helpers: a metal border from the client's frame atlases (minimap
-- mode's frame) and small round icon buttons using Forever's minimap button
-- ring.

local ADDON, ns = ...

local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
ns.CIRCLE = CIRCLE

-- Forever's minimap button ring: interface/hud/uiminimap2xc60.blp, pixels 510..590 x 511..591.
local RING_FILE = "Interface\\HUD\\UIMinimap2xC60"
local RING_COORDS = { 510 / 1024, 591 / 1024, 511 / 1024, 592 / 1024 }

local function AtlasInfo(name)
	return C_Texture.GetAtlasInfo(name)
end

-- An atlas piece with optional flips. Setting file + texcoords ourselves
-- (instead of SetAtlas) lets us mirror the bottom corners for the top.
local function Piece(parent, atlas, flipV)
	local info = AtlasInfo(atlas)
	local t = parent:CreateTexture(nil, "OVERLAY")
	t:SetTexture(info.file)
	local l, r, top, bottom = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
	if flipV then top, bottom = bottom, top end
	t:SetTexCoord(l, r, top, bottom)
	t:SetSize(info.width, info.height)
	return t
end

-- ref: a template NineSlice to copy the corners' placement from.
-- b.insets = { left, top, right, bottom }: how far in from the frame's edges
-- the border's edges reach, so what it frames can stop there instead of
-- showing through the art.
function ns.ApplyBorder(frame, level, ref)
	local b = CreateFrame("Frame", nil, frame)
	b:SetAllPoints()
	b:SetFrameLevel(level)
	b.insets = { 2, 2, 2, 2 }

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
	-- Edges are uniform strips, so stretching them looks the same as tiling.
	bottom:SetPoint("BOTTOMLEFT", bl, "BOTTOMRIGHT")
	bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
	top:SetPoint("TOPLEFT", tl, "TOPRIGHT")
	top:SetPoint("TOPRIGHT", tr, "TOPLEFT")
	left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT")
	left:SetPoint("BOTTOMLEFT", bl, "TOPLEFT")
	right:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT")
	right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
	-- Each edge starts |lx| (|y|) outside the frame; a pixel of overlap
	-- so nothing shows between the art and what it frames. Capped: some
	-- clients report an edge atlas far bigger than its visible metal
	-- (Forever's insets came out ~190 px and shrank the map to a stamp).
	local MAX_INSET = 6
	local function In(thickness, outside)
		return math.max(2, math.min(MAX_INSET, math.floor((thickness or 0) - outside - 1)))
	end
	b.insets = { In(left:GetWidth(), -lx), In(top:GetHeight(), -y), In(right:GetWidth(), rx), In(bottom:GetHeight(), -y) }
	return b
end

function ns.CreateRoundButton(parent, size, opts)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size, size)

	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture(CIRCLE)
	bg:SetVertexColor(0.06, 0.05, 0.04, 0.9)
	bg:SetPoint("CENTER")
	bg:SetSize(size - 3, size - 3)

	if opts.icon then
		local icon = b:CreateTexture(nil, "ARTWORK")
		icon:SetTexture(opts.icon)
		icon:SetPoint("CENTER")
		local inset = opts.iconInset or 7
		icon:SetSize(size - inset, size - inset)
		local mask = b:CreateMaskTexture()
		mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(icon)
		icon:AddMaskTexture(mask)
		b.icon = icon
	end

	local ring = b:CreateTexture(nil, "OVERLAY")
	ring:SetTexture(RING_FILE)
	ring:SetTexCoord(unpack(RING_COORDS))
	ring:SetPoint("CENTER")
	ring:SetSize(size + 2, size + 2)

	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetTexture(CIRCLE)
	hl:SetVertexColor(1, 0.9, 0.6, 0.18)
	hl:SetPoint("CENTER")
	hl:SetSize(size - 3, size - 3)

	b:SetScript("OnEnter", function(self)
		if opts.tooltip then
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(opts.tooltip, 1, 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

