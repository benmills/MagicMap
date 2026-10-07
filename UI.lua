-- Chrome helpers: a metal border from the client's frame atlases (minimap
-- mode's frame, and the window's when ButtonFrameTemplate is unavailable) and small round icon buttons using
-- the Forever minimap button ring. Both fall back to plain bronze shapes on
-- clients that lack the art.

local ADDON, ns = ...

local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local BRONZE = { 0.72, 0.55, 0.32 }
ns.CIRCLE, ns.BRONZE = CIRCLE, BRONZE

-- Forever's minimap button ring: interface/hud/uiminimap2xc60.blp, pixels 510..590 x 511..591.
local RING_FILE = "Interface\\HUD\\UIMinimap2xC60"
local RING_COORDS = { 510 / 1024, 591 / 1024, 511 / 1024, 592 / 1024 }

local function FileExists(path)
	return GetFileIDFromPath and GetFileIDFromPath(path) ~= nil
end

local function AtlasInfo(name)
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
end

-- An atlas piece with optional flips. Setting file + texcoords ourselves
-- (instead of SetAtlas) lets us mirror the bottom corners for the top.
local function Piece(parent, atlas, flipV)
	local info = AtlasInfo(atlas)
	if not (info and info.file) then return nil end
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

	if bl and br and tl and tr and bottom and top and left and right then
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
		-- so nothing shows between the art and what it frames.
		local function In(thickness, outside) return math.max(2, math.floor(thickness - outside - 1)) end
		b.insets = { In(left:GetWidth(), -lx), In(top:GetHeight(), -y), In(right:GetWidth(), rx), In(bottom:GetHeight(), -y) }
	else
		for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
			local t = b:CreateTexture(nil, "OVERLAY")
			t:SetColorTexture(BRONZE[1], BRONZE[2], BRONZE[3], 1)
			if side == "TOP" or side == "BOTTOM" then
				t:SetPoint(side .. "LEFT")
				t:SetPoint(side .. "RIGHT")
				t:SetHeight(2)
			else
				t:SetPoint("TOP" .. side)
				t:SetPoint("BOTTOM" .. side)
				t:SetWidth(2)
			end
		end
	end
	return b
end

local hasRing
function ns.CreateRoundButton(parent, size, opts)
	if hasRing == nil then hasRing = FileExists(RING_FILE .. ".blp") or FileExists(RING_FILE) end

	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size, size)

	if not hasRing then
		local under = b:CreateTexture(nil, "BACKGROUND", nil, -1)
		under:SetTexture(CIRCLE)
		under:SetVertexColor(BRONZE[1], BRONZE[2], BRONZE[3], 0.9)
		under:SetPoint("CENTER")
		under:SetSize(size, size)
	end

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
		if b.CreateMaskTexture and icon.AddMaskTexture and not opts.noMask then
			local mask = b:CreateMaskTexture()
			mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
			mask:SetAllPoints(icon)
			icon:AddMaskTexture(mask)
		end
		b.icon = icon
	end

	if hasRing then
		local ring = b:CreateTexture(nil, "OVERLAY")
		ring:SetTexture(RING_FILE)
		ring:SetTexCoord(unpack(RING_COORDS))
		ring:SetPoint("CENTER")
		ring:SetSize(size + 2, size + 2)
	end

	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetTexture(CIRCLE)
	hl:SetVertexColor(1, 0.9, 0.6, 0.18)
	hl:SetPoint("CENTER")
	hl:SetSize(size - 3, size - 3)

	b:SetScript("OnEnter", function(self)
		local tip = type(opts.tooltip) == "function" and opts.tooltip() or opts.tooltip
		if tip then
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(tip, 1, 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

