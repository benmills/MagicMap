-- MagicMap: a large, pannable, zoomable map rendered from the game's own
-- minimap terrain tiles (Texture:SetTexture(fileDataID)).
--
-- Coordinate system ("tile space"): (col, row) as floats, matching the
-- minimap file names world/minimaps/<dir>/map<col>_<row>.blp. Tile (0,0) is
-- the north-west corner of a 64x64 grid; col grows east, row grows south.

local ADDON, ns = ...
local TILE_YARDS = 1600 / 3 -- one ADT / minimap tile = 533.33 yards
local MIN_ZOOM, MAX_ZOOM = 16, 2048 -- screen units per tile
local WHEEL_STEP = 1.3
local FLY_TIME = 0.55
local ZOOM_RATE = 14 -- per second: how quickly wheel zoom closes on its target (higher = snappier)
local CLICK_SLOP, CLICK_TIME = 5, 0.35 -- a click moves less than this many px, this fast

local defaults = {
	shown = true,
	width = 860, height = 620,
	point = { "CENTER", "CENTER", 0, 0 },
	zoom = 384,
	follow = true,
	path = false, -- following, lean toward your target (see FollowCenter)
	map = nil, -- instanceID being viewed; nil = player's continent
	cx = 32, cy = 32,
	debug = false, -- show tile/FileDataID/zoom in the title band
	tint = true, -- draw tiles with Data/TileColor_*.lua's tints and coast fades
	minimap = { angle = 215, hide = false }, -- minimap button position (degrees) / visibility
}

local db
local TileData = {} -- set by LoadTileSet: instanceID -> { name, dir, tiles }

local state = {
	map = nil,        -- instanceID currently displayed
	cx = 32, cy = 32, -- view center in tile space
	zoom = 256,
	follow = true,
	dirty = true,
	dragging = false,
	lastCursorX = 0, lastCursorY = 0,
	playerCol = nil, playerRow = nil, playerMap = nil,
}

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cffffd100MagicMap|r: " .. tostring(msg))
end

-- Tiny event bus so Layers.lua can react to view and map changes.
local handlers = {}
function ns.On(event, fn)
	handlers[event] = handlers[event] or {}
	table.insert(handlers[event], fn)
end
local function Fire(event, ...)
	for _, fn in ipairs(handlers[event] or {}) do fn(...) end
end

local function Clamp(v, lo, hi)
	if v < lo then return lo elseif v > hi then return hi end
	return v
end

-- UnitPosition returns (north axis, west axis, z, instanceID) in world yards.
local function WorldToTile(north, west)
	return 32 - west / TILE_YARDS, 32 - north / TILE_YARDS
end

local function SortedMapIDs()
	local ids = {}
	for id in pairs(TileData) do ids[#ids + 1] = id end
	table.sort(ids)
	return ids
end

---------------------------------------------------------------------------
-- Window: Blizzard's own ButtonFrameTemplate (nine-slice border, title band,
-- close button), so it looks and lines up exactly like the client's other
-- windows - including Forever's re-skin. Everything lives in the title band:
--
--   [Zone name v  context · coords]              (layers) (follow) [X]
--
-- and the map fills the rest of the frame, edge to edge under the border.
-- The title is also the map picker: click it for continents and instances.
---------------------------------------------------------------------------

local BAND_HEIGHT = 21 -- the template's title band (its background starts at y = -21)
local BAND_MID = -11

local frame
do
	local ok, f = pcall(CreateFrame, "Frame", "MagicMapFrame", UIParent, "ButtonFrameTemplate")
	frame = ok and f or CreateFrame("Frame", "MagicMapFrame", UIParent)
end
local templated = frame.NineSlice ~= nil

frame:SetFrameStrata("HIGH")
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:SetResizable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
if frame.SetResizeBounds then
	frame:SetResizeBounds(120, 120)
else
	frame:SetMinResize(120, 120)
end
frame:Hide()
tinsert(UISpecialFrames, "MagicMapFrame") -- close on Escape

if templated then
	if ButtonFrameTemplate_HidePortrait then ButtonFrameTemplate_HidePortrait(frame) end
	if ButtonFrameTemplate_HideButtonBar then ButtonFrameTemplate_HideButtonBar(frame) end
	if frame.Inset then frame.Inset:Hide() end
	if frame.TitleContainer and frame.TitleContainer.TitleText then frame.TitleContainer.TitleText:SetText("") end
else
	-- Fallback for clients without the template: dark panel, bronze border, a band.
	local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	bg:SetAllPoints()
	bg:SetColorTexture(0.075, 0.065, 0.055, 0.98)
	ns.ApplyBorder(frame, frame:GetFrameLevel() + 500)
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	close:SetScript("OnClick", function() frame:Hide() end)
	frame.CloseButton = close
end

frame:SetScript("OnDragStart", function() frame:StartMoving() end)
frame:SetScript("OnDragStop", function()
	frame:StopMovingOrSizing()
	local p, _, rp, x, y = frame:GetPoint()
	db.point = { p, rp, x, y }
end)

-- Viewport: the map, filling the frame below the band. Clips the tiles to it;
-- the template's border (drawn at frame level +500) frames its edges.
local viewport = CreateFrame("Frame", nil, frame)
viewport:SetPoint("TOPLEFT", 2, -BAND_HEIGHT)
viewport:SetPoint("BOTTOMRIGHT", -2, 2)
viewport:SetClipsChildren(true)
viewport:EnableMouse(true)
viewport:EnableMouseWheel(true)

local viewportBg = viewport:CreateTexture(nil, "BACKGROUND", nil, -8)
viewportBg:SetAllPoints()
viewportBg:SetColorTexture(0, 0, 0, 1)

-- Tiles live on their own child frame so the layers can sit above them.
local tileLayer = CreateFrame("Frame", nil, viewport)
tileLayer:SetAllPoints()
-- Tiles sit at fixed spots on a canvas that panning just slides (one SetPoint
-- a frame); they're only laid out again when the zoom changes.
local tileCanvas = CreateFrame("Frame", nil, tileLayer)
tileCanvas:SetSize(1, 1)

-- Layer frames between the tiles and the player marker, bottom to top.
local layerFrames = {}
for i, name in ipairs({ "shade", "areas", "lines", "path", "labels", "pins" }) do
	local f = CreateFrame("Frame", nil, viewport)
	f:SetAllPoints()
	f:SetFrameLevel(tileLayer:GetFrameLevel() + i)
	layerFrames[name] = f
end

local overlay = CreateFrame("Frame", nil, viewport)
overlay:SetAllPoints()
overlay:SetFrameLevel(tileLayer:GetFrameLevel() + 8)

-- Player marker: the Minimap's own arrow (an atlas on Retail).
local playerMarker = CreateFrame("Frame", nil, overlay)
playerMarker:SetSize(1, 1)
playerMarker:Hide()

local arrow = playerMarker:CreateTexture(nil, "OVERLAY")
if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("minimaparrow") then
	arrow:SetAtlas("minimaparrow")
else
	arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
end
arrow:SetSize(32, 32)
arrow:SetPoint("CENTER")

-- The band: above the template's border (500) and title bar (510), so our
-- text and buttons draw on it. No mouse, so dragging the band moves the window.
local FONT = (GameFontNormal and GameFontNormal:GetFont()) or STANDARD_TEXT_FONT
local band = CreateFrame("Frame", nil, frame)
band:SetFrameLevel(frame:GetFrameLevel() + 515)
band:SetPoint("TOPLEFT")
band:SetPoint("TOPRIGHT")
band:SetHeight(BAND_HEIGHT)

local closeButton = frame.CloseButton -- the template's, already in the band's corner
closeButton:SetFrameLevel(band:GetFrameLevel() + 5)
closeButton:SetScript("OnClick", function()
	if ns.OnCloseClicked and ns.OnCloseClicked() then return end
	frame:Hide()
end)

local title = band:CreateFontString(nil, "OVERLAY")
title:SetFont(FONT, 14, "")
title:SetTextColor(1, 0.82, 0.25)
title:SetShadowOffset(1, -1)
title:SetShadowColor(0, 0, 0, 1)
title:SetJustifyH("LEFT")
title:SetWordWrap(false)

local subtitle = band:CreateFontString(nil, "OVERLAY")
subtitle:SetFont(FONT, 11, "")
subtitle:SetTextColor(0.74, 0.68, 0.58)
subtitle:SetShadowOffset(1, -1)
subtitle:SetShadowColor(0, 0, 0, 1)
subtitle:SetJustifyH("LEFT")
subtitle:SetWordWrap(false)

-- The title doubles as the map picker (see OpenMapMenu): a button over it,
-- with a small chevron after the name. Dragging it still moves the window.
local TITLE_COLOR, TITLE_HOVER = { 1, 0.82, 0.25 }, { 1, 0.93, 0.6 }
local CHEVRON = 14 -- chevron width plus its gap after the name
local OpenMapMenu -- forward

local chevron = band:CreateTexture(nil, "OVERLAY")
chevron:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
chevron:SetSize(12, 12)
chevron:SetPoint("LEFT", title, "RIGHT", 1, -3)
chevron:SetVertexColor(0.85, 0.7, 0.45)

local titleButton = CreateFrame("Button", nil, band)
titleButton:SetPoint("TOPLEFT", title, "TOPLEFT", -4, 3)
titleButton:SetPoint("BOTTOMRIGHT", title, "BOTTOMRIGHT", CHEVRON + 2, -3)
titleButton:RegisterForDrag("LeftButton")
titleButton:SetScript("OnDragStart", function(self)
	self.dragged = true
	frame:StartMoving()
end)
titleButton:SetScript("OnDragStop", function()
	frame:StopMovingOrSizing()
	local p, _, rp, x, y = frame:GetPoint()
	db.point = { p, rp, x, y }
end)
titleButton:SetScript("OnClick", function(self)
	if self.dragged then
		self.dragged = nil
		return
	end
	OpenMapMenu(self)
end)
titleButton:SetScript("OnEnter", function()
	title:SetTextColor(unpack(TITLE_HOVER))
	chevron:SetVertexColor(1, 0.9, 0.6)
end)
titleButton:SetScript("OnLeave", function()
	title:SetTextColor(unpack(TITLE_COLOR))
	chevron:SetVertexColor(0.85, 0.7, 0.45)
end)

-- Backing for the name when it sits on the map (narrow windows only).
local titlePlate = band:CreateTexture(nil, "BACKGROUND")
titlePlate:SetColorTexture(0.03, 0.025, 0.02, 0.72)
titlePlate:Hide()

local function NaturalWidth(fs)
	return fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
end

local compact = false -- minimap mode's chrome (see SetCompact)

-- Minimap mode's controls use Blizzard's own minimap art where the client
-- has it (Retail-engine clients), else plain textures.
local function HasAtlas(name)
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

-- The first of these atlases the client has, if any.
local function FirstAtlas(...)
	for i = 1, select("#", ...) do
		local name = select(i, ...)
		if HasAtlas(name) then return name end
	end
end

-- A button from art = { atlas = {names...}, pushed = {...}, highlight = {...} }
-- (the first each client has), else from file = path with optional
-- coords / pushedCoords into it.
local function SkinButton(b, art)
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
		if art.coords then
			b:GetNormalTexture():SetTexCoord(unpack(art.coords))
			b:GetHighlightTexture():SetTexCoord(unpack(art.coords))
			b:GetPushedTexture():SetTexCoord(unpack(art.pushedCoords or art.coords))
		end
	end
end

local function ArtButton(parent, w, h, art)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w, h)
	SkinButton(b, art)
	return b
end

-- On the zone's line, right-aligned and shown while you hover: the layers
-- menu (the world map's gold gear), and in or out of minimap mode (the world
-- map's red buttons: condense into the minimap, expand back to the window).
local HEADER_ICON = 20
local MODE_ART = {
	window = {
		atlas = { "redbutton-condense-c60", "redbutton-condense" },
		pushed = { "redbutton-condense-pressed-c60", "redbutton-condense-pressed" },
		highlight = { "redbutton-highlight-c60", "redbutton-highlight" },
		file = "Interface\\Icons\\INV_Misc_Spyglass_03",
	},
	minimap = {
		atlas = { "redbutton-expand-c60", "redbutton-expand" },
		pushed = { "redbutton-expand-pressed-c60", "redbutton-expand-pressed" },
		highlight = { "redbutton-highlight-c60", "redbutton-highlight" },
		file = "Interface\\Icons\\INV_Misc_Spyglass_03",
	},
}
local modeButton = ArtButton(band, HEADER_ICON, HEADER_ICON, MODE_ART.window)
local gearButton = ArtButton(band, HEADER_ICON + 4, HEADER_ICON + 4, {
	file = "Interface\\WorldMap\\Gear_64", coords = { 0, 0.5, 0, 0.5 }, pushedCoords = { 0, 0.5, 0.5, 1 },
})
gearButton:SetPoint("RIGHT", modeButton, "LEFT", -6, 0)

-- Compact: zone, then subzone, left-aligned on one line just above the map
-- (below it, if the map is at the top of the screen), with the gear and back
-- buttons at its right end - no plate, like the minimap's own.
local function FitCompactTitle()
	titlePlate:Hide()
	local top, screenTop = frame:GetTop(), UIParent:GetTop()
	if not top then return end
	local room = frame:GetWidth() - 4 - (2 * HEADER_ICON + 4 + 6 + 8) -- left of the buttons
	local tw = math.min(NaturalWidth(title), room)
	title:SetWidth(tw)
	subtitle:SetWidth(math.max(1, math.min(NaturalWidth(subtitle), room - tw - 6)))
	modeButton:ClearAllPoints()
	if screenTop - top >= 24 then
		title:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 2, 4)
		modeButton:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -2, 3)
	else
		title:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 2, -4)
		modeButton:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", -2, -3)
	end
	-- Share the title's baseline, nudged for the smaller descender.
	subtitle:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 6, 1)
end

-- In the band when it fits; otherwise on the map's top-left corner.
local function FitTitle()
	title:ClearAllPoints()
	subtitle:ClearAllPoints()
	if compact then return FitCompactTitle() end
	modeButton:ClearAllPoints()
	modeButton:SetPoint("RIGHT", frame, "TOPRIGHT", -28, BAND_MID)
	local left, controlsLeft = frame:GetLeft(), gearButton:GetLeft()
	if not (left and controlsLeft) then return end
	local room = controlsLeft - (left + 10) - 14 - CHEVRON
	local tw, sw = NaturalWidth(title), NaturalWidth(subtitle)
	if tw + 8 + math.min(sw, 80) <= room then
		titlePlate:Hide()
		title:SetPoint("LEFT", frame, "TOPLEFT", 10, BAND_MID)
		title:SetWidth(tw)
		-- Share the title's baseline: bottoms aligned, nudged for the smaller descender.
		subtitle:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8 + CHEVRON, 1)
		subtitle:SetWidth(math.max(1, room - tw - 8))
	else
		local maxW = viewport:GetWidth() - 24
		title:SetPoint("TOPLEFT", viewport, "TOPLEFT", 12, -9)
		title:SetWidth(math.min(tw, maxW))
		subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 1, -3)
		subtitle:SetWidth(math.min(sw, maxW))
		titlePlate:ClearAllPoints()
		titlePlate:SetPoint("TOPLEFT", viewport, "TOPLEFT", 0, 0)
		titlePlate:SetSize(math.min(math.max(tw + CHEVRON, sw), maxW) + 24, title:GetStringHeight() + subtitle:GetStringHeight() + 21)
		titlePlate:Show()
	end
end

local resizeGrip = CreateFrame("Button", nil, frame)
resizeGrip:SetSize(14, 14)
resizeGrip:SetPoint("BOTTOMRIGHT", -4, 4)
resizeGrip:SetFrameLevel(frame:GetFrameLevel() + 520)
resizeGrip:SetAlpha(0.8)
resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
resizeGrip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
resizeGrip:SetScript("OnMouseUp", function()
	frame:StopMovingOrSizing()
	db.width, db.height = frame:GetSize()
end)

-- Compact chrome (minimap mode): the title band and the template's frame
-- (whose top is a header bar) go; the map fills the frame inside the same
-- metal border with plain top corners, the zone floats above it, and the
-- buttons and grip fade in while you hover.
local compactBorder = ns.ApplyBorder(frame, frame:GetFrameLevel() + 505, frame.NineSlice)
compactBorder:Hide()

-- Inside the map, shown while you hover: follow and path toggles (bottom
-- left) and zoom buttons (bottom right, where the minimap keeps them).
local mapControls = CreateFrame("Frame", nil, frame)
mapControls:SetAllPoints(viewport)
mapControls:SetFrameLevel(frame:GetFrameLevel() + 518) -- under the resize grip

local PAD = 12 -- from the map's edges
local function ZoomArt(name, fallback)
	return { atlas = { name }, pushed = { name .. "-down" }, highlight = { name .. "-mouseover" }, file = fallback }
end
local zoomOut = ArtButton(mapControls, 20, HasAtlas("ui-hud-minimap-zoom-out") and 11 or 20,
	ZoomArt("ui-hud-minimap-zoom-out", "Interface\\Buttons\\UI-MinusButton-Up"))
zoomOut:SetPoint("BOTTOMRIGHT", -PAD, PAD + 6) -- clear of the resize grip
local zoomIn = ArtButton(mapControls, 20, 20, ZoomArt("ui-hud-minimap-zoom-in", "Interface\\Buttons\\UI-PlusButton-Up"))
zoomIn:SetPoint("BOTTOM", zoomOut, "TOP", 0, 2)

-- A toggle: a dark disc with an icon, ringed in gold and lit while on.
local TOGGLE = 24
local function Toggle(atlas, fallback)
	local b = CreateFrame("Button", nil, mapControls)
	b:SetSize(TOGGLE, TOGGLE)
	b.ring = b:CreateTexture(nil, "BACKGROUND", nil, -1)
	b.ring:SetTexture(ns.CIRCLE)
	b.ring:SetVertexColor(1, 0.82, 0.3, 0.9)
	b.ring:SetAllPoints()
	local disc = b:CreateTexture(nil, "BACKGROUND")
	disc:SetTexture(ns.CIRCLE)
	disc:SetVertexColor(0, 0, 0, 0.65)
	disc:SetPoint("CENTER")
	disc:SetSize(TOGGLE - 3, TOGGLE - 3)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	if HasAtlas(atlas) then b.icon:SetAtlas(atlas) else b.icon:SetTexture(fallback) end
	b.icon:SetPoint("CENTER")
	b.icon:SetSize(TOGGLE - 7, TOGGLE - 7)
	local glow = b:CreateTexture(nil, "HIGHLIGHT")
	glow:SetTexture(ns.CIRCLE)
	glow:SetVertexColor(1, 1, 1, 0.12)
	glow:SetAllPoints(disc)
	return b
end
local followToggle = Toggle("ui-hud-minimap-arrow-player", "Interface\\Minimap\\MinimapArrow")
followToggle:SetPoint("BOTTOMLEFT", PAD, PAD)
local pathToggle = Toggle("ui-hud-minimap-arrow-questtracking", "Interface\\Icons\\Ability_Tracking")
pathToggle:SetPoint("LEFT", followToggle, "RIGHT", 5, 0)

local function SetLit(b, on)
	b.ring:SetShown(on)
	b.icon:SetDesaturated(not on)
	b.icon:SetAlpha(on and 1 or 0.6)
end

local chromeHidden = {} -- template parts SetCompact hid
local KEEP = { [viewport] = true, [band] = true, [resizeGrip] = true, [compactBorder] = true, [closeButton] = true,
	[mapControls] = true }
local hoverAlpha = 1

local function SetViewportInsets(l, t, r, b)
	viewport:ClearAllPoints()
	viewport:SetPoint("TOPLEFT", l, -t)
	viewport:SetPoint("BOTTOMRIGHT", -r, b)
end

local function SetCompact(on)
	on = on and true or false
	if on == compact then return end
	compact = on
	if on then
		for _, r in ipairs({ frame:GetRegions() }) do
			if r:IsShown() then r:Hide(); chromeHidden[r] = true end
		end
		for _, c in ipairs({ frame:GetChildren() }) do
			if not KEEP[c] and c:IsShown() then c:Hide(); chromeHidden[c] = true end
		end
		SetViewportInsets(2, 2, 2, 2)
		chevron:Hide()
		closeButton:Hide() -- the mode button leaves minimap mode instead
		compactBorder:Show()
	else
		for o in pairs(chromeHidden) do o:Show() end
		wipe(chromeHidden)
		SetViewportInsets(2, BAND_HEIGHT, 2, 2)
		chevron:Show()
		closeButton:Show()
		compactBorder:Hide()
	end
	state.dirty = true
	FitTitle()
end

-- The controls and grip fade in while the mouse is over the map.
local function StepHover(elapsed)
	-- Compact, the header line (above or below the map) counts as over it.
	local reach = compact and HEADER_ICON + 12 or 0
	local want = (frame:IsMouseOver(reach, -reach, 0, 0) or (ns.IsMenuOpen and ns.IsMenuOpen())) and 1 or 0
	if hoverAlpha == want then return end
	local step = (elapsed or 0) / 0.15
	hoverAlpha = want > hoverAlpha and math.min(want, hoverAlpha + step) or math.max(want, hoverAlpha - step)
	mapControls:SetAlpha(hoverAlpha)
	gearButton:SetAlpha(hoverAlpha)
	modeButton:SetAlpha(hoverAlpha)
	resizeGrip:SetAlpha(0.8 * hoverAlpha)
end

---------------------------------------------------------------------------
-- Tile sets
--
-- Each Data/Tiles_<product>.lua is generated from that game version's own
-- WDT files, which list the exact minimap FileDataID for every tile the
-- version uses. The same ID can hold different images in different
-- versions, and a client can ship leftover tiles its world never uses, so
-- the tile *list* has to come from the matching version. We pick the set
-- whose version matches GetBuildInfo() (major.minor, then major), else retail.
---------------------------------------------------------------------------

local tileSetName, tileSetVersion
local tileCounts = {}

-- Data/Select.lua lets only the set matching this client load, so there's one.
local function PickTileSet()
	return next(MagicMap_TileSets or {})
end

local function LoadTileSet(product)
	local set = product and MagicMap_TileSets[product]
	tileSetName, tileSetVersion = product, set and set.version
	TileData = set and set.maps or {}
	wipe(tileCounts)
	for mapID, data in pairs(TileData) do
		local n = 0
		for _ in pairs(data.tiles) do n = n + 1 end
		tileCounts[mapID] = n
	end
end

local function GetTiles(mapID)
	local data = TileData[mapID]
	return data and data.tiles
end

---------------------------------------------------------------------------
-- Tile rendering (visible tiles only, textures pooled and reused)
---------------------------------------------------------------------------

local activeTiles = {} -- mapID * 4096 + key (col*64+row) -> texture
local freeTextures = {}
local seen = {}

-- Where the map runs out (open sea past the last tile), each edge tile fades
-- into the backdrop colour sampled from that map's own edge water, so the
-- square tile edges dissolve instead of stopping dead against a flat colour.
-- With colour data (Data/TileColor_<product>.lua: the mean colour along each
-- open side), the tile instead spills that colour outward across the empty
-- cell, fading to the backdrop there: a bright coast no longer gets cut into a
-- rectangle, and only a sliver of the tile itself is blended into the seam.
local FEATHER = 0.35 -- fraction of a tile: inward fade to the backdrop (no colour data)
local INNER_FEATHER = 0.08 -- inward fade to the side's own colour, softening the seam
local OUTER_FEATHER = 0.6 -- outward fade from the side's colour to the backdrop
local TILE_AHEAD = 1 -- tiles loaded past each edge of the view
local SIDES = {
	-- side, neighbour key offset, gradient orientation, alpha at min end, alpha at max end (inward),
	-- edge colour key, outward fade's point on the tile's point
	{ "left", -64, "HORIZONTAL", 1, 0, "l", "TOPRIGHT", "TOPLEFT" },
	{ "right", 64, "HORIZONTAL", 0, 1, "r", "TOPLEFT", "TOPRIGHT" },
	{ "top", -1, "VERTICAL", 0, 1, "t", "BOTTOMLEFT", "TOPLEFT" },    -- VERTICAL gradients run bottom (min) to top (max)
	{ "bottom", 1, "VERTICAL", 1, 0, "b", "TOPLEFT", "BOTTOMLEFT" },
}
-- Where two open sides meet and the diagonal cell is empty too, a corner piece
-- fills the gap the two side fades leave. One gradient can only run one way,
-- so it's two: the colour fading horizontally, then the backdrop colour
-- fading in vertically on top. Over the backdrop that leaves the colour at
-- (1-x)(1-y), which matches both side fades along the edges it shares.
local CORNERS = {
	-- the two SIDES, diagonal key offset, our point, tile's point, colour alphas (min, max), backdrop alphas (min, max)
	{ 1, 3, -65, "BOTTOMRIGHT", "TOPLEFT", 0, 1, 0, 1 },
	{ 2, 3, 63, "BOTTOMLEFT", "TOPRIGHT", 1, 0, 0, 1 },
	{ 1, 4, -63, "TOPRIGHT", "BOTTOMLEFT", 0, 1, 1, 0 },
	{ 2, 4, 65, "TOPLEFT", "BOTTOMRIGHT", 1, 0, 1, 0 },
}
-- ARTWORK sublevels, bottom to top. The outward pieces only ever lie over
-- empty cells, but sit under the tiles so a pixel of overlap never shows.
local SUB_CORNER, SUB_CORNER_BG, SUB_OUTER, SUB_TILE, SUB_ADD, SUB_FEATHER = -3, -2, -1, 0, 1, 2
local bgColor = { 0, 0, 0 }

local function SetFade(t, orientation, r, g, b, a1, a2)
	t:SetColorTexture(1, 1, 1, 1)
	if t.SetGradient and CreateColor then
		t:SetGradient(orientation, CreateColor(r, g, b, a1), CreateColor(r, g, b, a2))
	elseif t.SetGradientAlpha then
		t:SetGradientAlpha(orientation, r, g, b, a1, r, g, b, a2)
	end
end

local function SetBackdrop(color)
	bgColor = color or { 0.03, 0.06, 0.065 }
	viewportBg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], 1)
end

-- The client snaps each texture to the screen's pixel grid on its own, so
-- neighbouring tiles come out a pixel apart in size and resample their texels
-- unevenly (grit, and shimmer as the map moves). Tiles skip that: the canvas
-- they share is the only thing that moves.
local function Unsnapped(tex)
	if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false) end
	if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
	return tex
end

local function Piece(sublevel)
	local t = Unsnapped(tileCanvas:CreateTexture(nil, "ARTWORK", nil, sublevel))
	t:Hide()
	return t
end

local function SetOn(t, on)
	if on then
		if not t.on then t:Show(); t.on = true end
	elseif t and t.on then
		t:Hide(); t.on = nil
	end
end

local function AcquireTexture()
	local tex = table.remove(freeTextures)
	if not tex then
		tex = Unsnapped(tileCanvas:CreateTexture(nil, "ARTWORK", nil, SUB_TILE))
		tex.feathers = {}
		for i, s in ipairs(SIDES) do
			-- A feather never changes side, so it's anchored once, for good.
			local f = Piece(SUB_FEATHER)
			if s[3] == "HORIZONTAL" then
				f:SetPoint(s[1] == "left" and "TOPLEFT" or "TOPRIGHT", tex)
			else
				f:SetPoint(s[1] == "top" and "TOPLEFT" or "BOTTOMLEFT", tex)
			end
			tex.feathers[i] = f
		end
		-- The tint overlay and outward fades are made the first time this
		-- texture needs them (most tiles never do), then kept with it.
		tex.outs, tex.corners = {}, {}
	end
	tex:Show()
	return tex
end

local function ReleaseTexture(tex)
	tex:Hide()
	for i, f in ipairs(tex.feathers) do
		SetOn(f, false)
		SetOn(tex.outs[i], false)
	end
	for _, c in pairs(tex.corners) do
		SetOn(c[1], false); SetOn(c[2], false)
	end
	if tex.tint then
		-- The next tile drawn with this texture may not be tinted.
		tex:SetVertexColor(1, 1, 1)
		SetOn(tex.add, false)
		tex.tint = nil
	end
	tex.fdid, tex.zoom, tex.colors = nil, nil, nil
	freeTextures[#freeTextures + 1] = tex
end

local function ReleaseAllTiles()
	for key, tex in pairs(activeTiles) do
		ReleaseTexture(tex)
		activeTiles[key] = nil
	end
end

-- The tile-space bounds of a map's tiles.
local function TileBounds(mapID)
	local tiles = GetTiles(mapID)
	if not tiles then return nil end
	local c0, r0, c1, r1 = 64, 64, 0, 0
	for key in pairs(tiles) do
		local col, row = math.floor(key / 64), key % 64
		c0, r0 = math.min(c0, col), math.min(r0, row)
		c1, r1 = math.max(c1, col + 1), math.max(r1, row + 1)
	end
	if c1 <= c0 then return nil end
	return c0, r0, c1, r1
end

-- Terrain height in yards at (col, row) in mapID's own tile space, from
-- Data/Heights_<product>.lua (one byte per 33-yard chunk), or nil.
local function HeightAt(mapID, col, row)
	local hm = MagicMap_Heights and MagicMap_Heights[mapID]
	if not hm then return nil end
	local tc, tr = math.floor(col), math.floor(row)
	if tr < 0 or tr > 63 then return nil end
	local s = hm.tiles[tc * 64 + tr]
	if not s then return nil end
	local b = #s == 1 and s:byte(1) or s:byte(math.floor((row - tr) * 16) * 16 + math.floor((col - tc) * 16) + 1)
	return hm.min + ((b - hm.shift) % 256) * hm.scale
end

-- Fade t (one of a tile's pieces) with colour c, unless it already is.
local function FadeOnce(t, orientation, c, a1, a2)
	if t.fadeColor ~= c then
		SetFade(t, orientation, c[1], c[2], c[3], a1, a2)
		t.fadeColor = c
	end
end

-- Is a tile drawn at key? With colour data on, open sea tiles aren't, so
-- beside them counts as open.
local function Present(tiles, sea, key)
	return tiles[key] and not (sea and sea[key])
end

-- Place a tile on the canvas for this zoom. Edges are rounded (not origin +
-- size) so neighbours always share an edge. colors: this map's entry in
-- MagicMap_TileColor (or false); everything it changes is set here, once per
-- zoom, never per frame.
local function LayoutTile(tex, tiles, key, zoom, colors)
	local sea = colors and colors.sea
	local col, row = math.floor(key / 64), key % 64
	local left, top = math.floor(col * zoom + 0.5), math.floor(row * zoom + 0.5)
	local w = math.floor((col + 1) * zoom + 0.5) - left
	local h = math.floor((row + 1) * zoom + 0.5) - top
	tex:SetPoint("TOPLEFT", tileCanvas, "TOPLEFT", left, -top)
	tex:SetSize(w, h)

	-- Tiles baked darker, lighter or off-tint from their neighbours are drawn
	-- as texel * m + a: the vertex colour scales, an additive overlay lifts.
	local tint = colors and colors.tint and colors.tint[key] or nil
	if tint ~= tex.tint then
		if tint then
			tex:SetVertexColor(tint[1], tint[2], tint[3])
			if not tex.add then
				tex.add = Piece(SUB_ADD)
				tex.add:SetAllPoints(tex)
				tex.add:SetBlendMode("ADD")
			end
			tex.add:SetColorTexture(tint[4], tint[5], tint[6], 1)
			SetOn(tex.add, tint[4] > 0 or tint[5] > 0 or tint[6] > 0)
		else
			tex:SetVertexColor(1, 1, 1)
			SetOn(tex.add, false)
		end
		tex.tint = tint
	end

	local edge = colors and colors.edge and colors.edge[key]
	local ow, oh = math.floor(w * OUTER_FEATHER + 0.5), math.floor(h * OUTER_FEATHER + 0.5)
	for i, s in ipairs(SIDES) do
		local f, out = tex.feathers[i], tex.outs[i]
		local c = edge and edge[s[6]]
		if Present(tiles, sea, key + s[2]) then
			SetOn(f, false)
			SetOn(out, false)
		elseif c then
			-- Open, with its colour: a thin fade into that colour inside, then
			-- the colour spilling out over the empty cell.
			FadeOnce(f, s[3], c, s[4], s[5])
			if s[3] == "HORIZONTAL" then f:SetSize(w * INNER_FEATHER, h) else f:SetSize(w, h * INNER_FEATHER) end
			SetOn(f, true)
			if not out then
				out = Piece(SUB_OUTER)
				out:SetPoint(s[7], tex, s[8])
				tex.outs[i] = out
			end
			FadeOnce(out, s[3], c, s[5], s[4])
			if s[3] == "HORIZONTAL" then out:SetSize(ow, h) else out:SetSize(w, oh) end
			SetOn(out, true)
		else
			-- Each feather keeps its side; only a new backdrop colour changes it.
			FadeOnce(f, s[3], bgColor, s[4], s[5])
			if s[3] == "HORIZONTAL" then f:SetSize(w * FEATHER, h) else f:SetSize(w, h * FEATHER) end
			SetOn(f, true)
			SetOn(out, false)
		end
	end

	for j, k in ipairs(CORNERS) do
		local piece = tex.corners[j]
		local c1 = edge and edge[SIDES[k[1]][6]]
		local c2 = edge and edge[SIDES[k[2]][6]]
		-- Both sides fade outward and nothing is drawn in the diagonal cell.
		if c1 and c2 and not Present(tiles, sea, key + SIDES[k[1]][2])
			and not Present(tiles, sea, key + SIDES[k[2]][2]) and not Present(tiles, sea, key + k[3]) then
			if not piece then
				piece = { Piece(SUB_CORNER), Piece(SUB_CORNER_BG) }
				for _, t in ipairs(piece) do t:SetPoint(k[4], tex, k[5]) end
				tex.corners[j] = piece
			end
			if piece.c1 ~= c1 or piece.c2 ~= c2 then
				-- The two sides' colours, met halfway.
				SetFade(piece[1], "HORIZONTAL", (c1[1] + c2[1]) / 2, (c1[2] + c2[2]) / 2, (c1[3] + c2[3]) / 2, k[6], k[7])
				piece.c1, piece.c2 = c1, c2
			end
			FadeOnce(piece[2], "VERTICAL", bgColor, k[8], k[9])
			for _, t in ipairs(piece) do
				t:SetSize(ow, oh)
				SetOn(t, true)
			end
		elseif piece then
			SetOn(piece[1], false); SetOn(piece[2], false)
		end
	end
	tex.zoom, tex.bg, tex.colors = zoom, bgColor, colors
end

local function RenderTiles()
	local w, h = viewport:GetSize()
	if w <= 0 or h <= 0 then return end
	local zoom = state.zoom
	local halfW, halfH = w / 2, h / 2
	local cx, cy = state.cx, state.cy
	-- Not rounded: the layers, the Minimap and your arrow move by fractions of
	-- a pixel, so the terrain must too or they'd wobble against it. (Tiles
	-- keep whole-pixel spots on the canvas, so seams stay exact.)
	tileCanvas:SetPoint("TOPLEFT", tileLayer, "TOPLEFT", halfW - cx * zoom, -(halfH - cy * zoom))

	wipe(seen)
	local mapID = state.map
	local tiles = GetTiles(mapID)
	-- Colour data is looked up here, not kept, so /mm tint (or a test) can
	-- swap it: a different table re-lays the tiles out.
	local colors = db.tint and MagicMap_TileColor and MagicMap_TileColor[mapID] or false
	-- Tiles of nothing but flat sea are left out: the backdrop is that colour.
	local sea = colors and colors.sea
	if tiles then
		-- A ring of tiles past the edge too: the client streams textures in a
		-- frame or more after SetTexture, so a pan should find them loaded.
		local colMin = Clamp(math.floor(cx - halfW / zoom) - TILE_AHEAD, 0, 63)
		local colMax = Clamp(math.floor(cx + halfW / zoom) + TILE_AHEAD, 0, 63)
		local rowMin = Clamp(math.floor(cy - halfH / zoom) - TILE_AHEAD, 0, 63)
		local rowMax = Clamp(math.floor(cy + halfH / zoom) + TILE_AHEAD, 0, 63)
		for col = colMin, colMax do
			for row = rowMin, rowMax do
				local key = col * 64 + row
				local fdid = tiles[key]
				if fdid and not (sea and sea[key]) then
					local id = mapID * 4096 + key
					local tex = activeTiles[id]
					if not tex then
						tex = AcquireTexture()
						activeTiles[id] = tex
					end
					if tex.fdid ~= fdid then
						-- Trilinear: smoother when a tile is drawn smaller than its
						-- 512 texels (where the client has mipmaps for it).
						tex:SetTexture(fdid, "CLAMP", "CLAMP", "TRILINEAR")
						tex.fdid = fdid
					end
					if tex.zoom ~= zoom or tex.bg ~= bgColor or tex.colors ~= colors then
						LayoutTile(tex, tiles, key, zoom, colors)
					end
					seen[id] = true
				end
			end
		end
	end

	-- Keep tiles a ring further than that before letting go, so panning back and
	-- forth doesn't churn them.
	local c0, c1 = cx - halfW / zoom - TILE_AHEAD - 1, cx + halfW / zoom + TILE_AHEAD + 1
	local r0, r1 = cy - halfH / zoom - TILE_AHEAD - 1, cy + halfH / zoom + TILE_AHEAD + 1
	for id, tex in pairs(activeTiles) do
		if not seen[id] then
			local key = id % 4096
			local col, row = math.floor(key / 64), key % 64
			if not tiles or math.floor(id / 4096) ~= mapID or tex.zoom ~= zoom or (sea and sea[key])
				or col + 1 < c0 or col > c1 or row + 1 < r0 or row > r1 then
				ReleaseTexture(tex)
				activeTiles[id] = nil
			end
		end
	end
end

local function RenderArrow()
	if state.playerCol and state.playerMap == state.map and not state.minimapShown then
		local w, h = viewport:GetSize()
		local x = (state.playerCol - state.cx) * state.zoom + w / 2
		local y = (state.playerRow - state.cy) * state.zoom + h / 2
		playerMarker:ClearAllPoints()
		playerMarker:SetPoint("CENTER", overlay, "TOPLEFT", x, -y)
		local facing = GetPlayerFacing()
		if facing then
			arrow:SetRotation(facing)
			arrow:Show()
		else
			arrow:Hide()
		end
		playerMarker:Show()
	else
		playerMarker:Hide()
	end
end

---------------------------------------------------------------------------
-- Map geometry from C_Map (world-space rectangles; no map artwork is used)
---------------------------------------------------------------------------

local MAPTYPE_CONTINENT = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2
local MAPTYPE_ZONE = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
local MAPTYPE_MICRO = Enum and Enum.UIMapType and Enum.UIMapType.Micro or 5

local mapRects = {}        -- uiMapID -> { inst, col0, row0, col1, row1 } | false
local zonesByMap           -- instanceID -> sorted list of zone rects (+ name, uiMapID)
local continentByInst = {} -- instanceID -> uiMapID of the continent map
local questMapsByInst = {} -- instanceID -> uiMapIDs (zones + micro maps) that can carry quests

local function MapPos(x, y)
	if CreateVector2D then return CreateVector2D(x, y) end
	return { x = x, y = y }
end

local function WorldXY(v)
	if v.GetXY then return v:GetXY() end
	return v.x, v.y
end

-- A uiMap is an axis-aligned rectangle in world space, so two corners
-- give us a linear transform between its normalized coords and tile space.
local function MapRect(uiMapID)
	local rect = mapRects[uiMapID]
	if rect ~= nil then return rect or nil end
	rect = false
	if uiMapID and C_Map and C_Map.GetWorldPosFromMapPos then
		local ok, inst, tl = pcall(C_Map.GetWorldPosFromMapPos, uiMapID, MapPos(0, 0))
		local ok2, inst2, br = pcall(C_Map.GetWorldPosFromMapPos, uiMapID, MapPos(1, 1))
		if ok and ok2 and inst and tl and br and inst == inst2 then
			-- Same axis order as UnitPosition: (north, west).
			local top, left = WorldXY(tl)
			local bottom, right = WorldXY(br)
			local col0, row0 = WorldToTile(top, left)
			local col1, row1 = WorldToTile(bottom, right)
			if col1 > col0 and row1 > row0 then
				rect = { inst = inst, col0 = col0, row0 = row0, col1 = col1, row1 = row1 }
			end
		end
	end
	mapRects[uiMapID] = rect
	return rect or nil
end

-- uiMap normalized (x, y) -> instanceID, col, row
local function MapToTile(uiMapID, x, y)
	local r = MapRect(uiMapID)
	if not r then return nil end
	return r.inst, r.col0 + (r.col1 - r.col0) * x, r.row0 + (r.row1 - r.row0) * y
end

-- tile (col, row) -> uiMap normalized (x, y)
local function TileToMap(uiMapID, col, row)
	local r = MapRect(uiMapID)
	if not r then return nil end
	return (col - r.col0) / (r.col1 - r.col0), (row - r.row0) / (r.row1 - r.row0)
end

local function BuildZones()
	zonesByMap = {}
	wipe(continentByInst)
	wipe(questMapsByInst)
	if not (C_Map and C_Map.GetMapInfo) then return end
	local seenNames, continentArea = {}, {}
	for uiMapID = 1, 4000 do
		local info = C_Map.GetMapInfo(uiMapID)
		local wanted = info and (info.mapType == MAPTYPE_ZONE or info.mapType == MAPTYPE_CONTINENT or info.mapType == MAPTYPE_MICRO)
		if wanted and info.name and info.name ~= "" then
			local r = MapRect(uiMapID)
			if r and TileData[r.inst] and info.mapType ~= MAPTYPE_CONTINENT then
				questMapsByInst[r.inst] = questMapsByInst[r.inst] or {}
				table.insert(questMapsByInst[r.inst], uiMapID)
			end
			-- Only zones and continents go in the zone list; micro maps are for quests.
			if r and TileData[r.inst] and info.mapType ~= MAPTYPE_MICRO then
				if info.mapType == MAPTYPE_CONTINENT then
					-- Several continent maps can share an instance; keep the biggest.
					local area = (r.col1 - r.col0) * (r.row1 - r.row0)
					if area > (continentArea[r.inst] or 0) then
						continentArea[r.inst] = area
						continentByInst[r.inst] = uiMapID
					end
				else
					local key = r.inst .. ":" .. info.name
					if not seenNames[key] then
						seenNames[key] = true
						local list = zonesByMap[r.inst] or {}
						zonesByMap[r.inst] = list
						list[#list + 1] = { name = info.name, uiMapID = uiMapID,
							col0 = r.col0, col1 = r.col1, row0 = r.row0, row1 = r.row1 }
					end
				end
			end
		end
	end
	for _, list in pairs(zonesByMap) do
		table.sort(list, function(a, b) return a.name < b.name end)
	end
end

local function GetZones(mapID)
	if not zonesByMap then BuildZones() end
	return zonesByMap[mapID] or {}
end

local function GetContinentMapID(mapID)
	if not zonesByMap then BuildZones() end
	return continentByInst[mapID]
end

local function GetQuestMaps(mapID)
	if not zonesByMap then BuildZones() end
	return questMapsByInst[mapID] or {}
end

---------------------------------------------------------------------------
-- Camera: all view changes go through here. Flights (AnimateTo) are eased;
-- zooming in keeps the destination on a straight line toward the centre
-- (it "comes to you"). Wheel zoom instead chases a target zoom, closing a
-- fixed fraction of the (log) distance per second: quick ticks just move the
-- target, so the motion stays continuous instead of restarting a curve per
-- tick. It pins the point under the cursor (or you, when following).
---------------------------------------------------------------------------

local anim
local zoomGoal, zoomAnchor -- wheel zoom target, and { tx, ty, dx, dy }: world point kept at that screen offset

local function ViewSize() return viewport:GetSize() end

local function SaveView()
	db.zoom, db.cx, db.cy = state.zoom, state.cx, state.cy
end

local function EaseOutCubic(t) return 1 - (1 - t) ^ 3 end

-- opts.anchor = { tx, ty, dx, dy }: keep world point (tx,ty) at screen offset (dx,dy) from centre.
local function AnimateTo(cx, cy, zoom, duration, opts)
	opts = opts or {}
	zoomGoal = nil
	anim = {
		t = 0, dur = duration,
		fx = state.cx, fy = state.cy, fz = state.zoom,
		tx = cx, ty = cy, tz = Clamp(zoom, MIN_ZOOM, MAX_ZOOM),
		anchor = opts.anchor, onDone = opts.onDone,
	}
end

local function StopAnimation()
	anim = nil
	zoomGoal = nil
end

local function StepZoom(elapsed)
	if not zoomGoal then return end
	local lz, lg = math.log(state.zoom), math.log(zoomGoal)
	local z = math.exp(lz + (lg - lz) * (1 - math.exp(-ZOOM_RATE * elapsed)))
	if math.abs(lg - math.log(z)) < 0.002 then
		z = zoomGoal
		zoomGoal = nil
	end
	state.zoom = z
	if zoomAnchor and not state.follow then
		local a = zoomAnchor
		state.cx, state.cy = a[1] - a[3] / z, a[2] - a[4] / z
	end
	state.dirty = true
	if not zoomGoal then SaveView() end
end

-- Following puts you in the middle; path mode leans toward your target (the
-- quest you follow, else your waypoint): you sit off-centre so the view shows
-- the way there - halfway when that keeps both in view, never further than
-- LEAN of the view's shorter side. The zoom is always yours.
local LEAN = 0.35
local LEAN_RATE = 4 -- per second: how quickly the lean settles when the target changes
local leanX, leanY = 0, 0 -- in tiles, eased

local function WantedLean()
	local t = state.path and ns.GetTarget and ns.GetTarget()
	if not (t and state.playerCol and state.playerMap == state.map) then return 0, 0 end
	local w, h = ViewSize()
	local dx, dy = (t.col - state.playerCol) * state.zoom, (t.row - state.playerRow) * state.zoom
	local d = math.sqrt(dx * dx + dy * dy)
	if d < 1 then return 0, 0 end
	local k = math.min(d / 2, LEAN * math.min(w, h)) / d
	return dx * k / state.zoom, dy * k / state.zoom
end

-- Where following puts the centre: you, plus the lean.
local function FollowCenter()
	return state.playerCol + leanX, state.playerRow + leanY
end

local function StepLean(elapsed)
	local wx, wy = WantedLean()
	local k = math.min(1, LEAN_RATE * (elapsed or 0))
	leanX, leanY = leanX + (wx - leanX) * k, leanY + (wy - leanY) * k
end

-- Where the camera is headed: the zoom and centre it will settle at.
local function GoalZoom()
	return zoomGoal or (anim and anim.tz) or state.zoom
end

local function GoalCenter()
	if state.follow and state.playerCol then return FollowCenter() end
	if anim and not anim.anchor then return anim.tx, anim.ty end
	if zoomGoal and zoomAnchor then
		local a = zoomAnchor
		return a[1] - a[3] / zoomGoal, a[2] - a[4] / zoomGoal
	end
	return state.cx, state.cy
end

local function StepAnimation(elapsed)
	if not anim then return end
	anim.t = anim.t + elapsed
	local p = math.min(1, anim.t / anim.dur)
	local e = EaseOutCubic(p)
	local z = math.exp(math.log(anim.fz) + (math.log(anim.tz) - math.log(anim.fz)) * e)
	state.zoom = z
	if anim.anchor then
		local a = anim.anchor
		state.cx, state.cy = a[1] - a[3] / z, a[2] - a[4] / z
	elseif anim.tz > anim.fz then
		-- The target's screen offset shrinks linearly while we zoom in on it.
		local k = (anim.fz / z) * (1 - e)
		state.cx = anim.tx - (anim.tx - anim.fx) * k
		state.cy = anim.ty - (anim.ty - anim.fy) * k
	else
		state.cx = anim.fx + (anim.tx - anim.fx) * e
		state.cy = anim.fy + (anim.ty - anim.fy) * e
	end
	state.dirty = true
	if p >= 1 then
		local done = anim.onDone
		anim = nil
		SaveView()
		if done then done() end
	end
end

local function FitZoom(col0, row0, col1, row1, margin)
	local w, h = ViewSize()
	return Clamp(math.min(w / (col1 - col0), h / (row1 - row0)) * (margin or 0.92), MIN_ZOOM, MAX_ZOOM)
end

local function CursorInViewport()
	local scale = viewport:GetEffectiveScale()
	local x, y = GetCursorPosition()
	return x / scale - viewport:GetLeft(), viewport:GetTop() - y / scale
end

local function CursorTile()
	local mx, my = CursorInViewport()
	local w, h = ViewSize()
	return state.cx + (mx - w / 2) / state.zoom, state.cy + (my - h / 2) / state.zoom
end

local function TileToScreen(col, row)
	local w, h = ViewSize()
	return (col - state.cx) * state.zoom + w / 2, (row - state.cy) * state.zoom + h / 2
end

---------------------------------------------------------------------------
-- View state
---------------------------------------------------------------------------

local CONTINENT_MIN_TILES = 300 -- open-world maps this big are listed as continents

local function UpdateControls()
	SetLit(followToggle, state.follow)
	SetLit(pathToggle, state.path)
end

local function SetMap(mapID)
	if mapID == state.map then return end
	state.map = mapID
	state.zoneName = nil
	db.map = mapID
	SetBackdrop(TileData[mapID] and TileData[mapID].bg)
	UpdateControls()
	state.dirty = true
	Fire("MapChanged", mapID)
end

-- Following (the camera on you) or free. animate: glide back to you first,
-- at the zoom you have.
local function SetFollow(on, animate)
	if on and animate and state.playerCol then
		if state.playerMap ~= state.map then SetMap(state.playerMap) end
		local cx, cy = FollowCenter()
		AnimateTo(cx, cy, state.zoom, FLY_TIME, { onDone = function() SetFollow(true) end })
		return
	end
	state.follow = on
	db.follow = on
	if on and state.playerCol then SetMap(state.playerMap) end
	UpdateControls()
	state.dirty = true
end

-- Path mode (lean toward your target while following) on or off; turning
-- it on also goes back to following you, unless keepView.
local function SetPath(on, keepView)
	state.path = on and true or false
	db.path = state.path
	if on and not state.follow and not keepView then SetFollow(true, true) end
	UpdateControls()
	state.dirty = true
end

-- Path mode comes with a target: on when you get a new one (follow a quest,
-- set a waypoint), off when it's gone. In between, the toggle is yours.
-- Following a quest while you look around the map doesn't pull the view back.
local TARGET_CHECK = 0.2 -- seconds between looks
local lastTargetKey, targetCheckAt = false, 0 -- false: not looked yet
local function StepTargetChange()
	local now = GetTime()
	if now < targetCheckAt or not ns.TargetKey then return end
	targetCheckAt = now + TARGET_CHECK
	local key = ns.TargetKey()
	if key == lastTargetKey then return end
	local first = lastTargetKey == false
	lastTargetKey = key
	if first then return end -- what you had at login keeps your saved choice
	if key and not state.path then
		SetPath(true, true)
	elseif not key and state.path then
		SetPath(false)
	end
end

local function UpdatePlayer()
	local north, west, _, inst = UnitPosition("player")
	if north then
		state.playerCol, state.playerRow = WorldToTile(north, west)
		state.playerMap = inst
	else
		-- Instances may withhold your position; still know which map you're on.
		state.playerCol, state.playerRow = nil, nil
		local inst = GetInstanceInfo and select(8, GetInstanceInfo())
		state.playerMap = inst and TileData[inst] and inst or nil
	end
end

local function FlyToRect(col0, row0, col1, row1, name)
	SetFollow(false)
	state.zoneName = name
	AnimateTo((col0 + col1) / 2, (row0 + row1) / 2, FitZoom(col0, row0, col1, row1), FLY_TIME)
end

local function ZoomToZone(zone)
	FlyToRect(zone.col0, zone.row0, zone.col1, zone.row1, zone.name)
end

-- Show a whole map, fit to the window.
local function FitMap(mapID)
	SetMap(mapID)
	local cont = GetContinentMapID(mapID)
	local r = cont and MapRect(cont)
	local c0, r0, c1, r1
	if r then
		c0, r0, c1, r1 = r.col0, r.row0, r.col1, r.row1
	else
		c0, r0, c1, r1 = TileBounds(mapID)
	end
	if c0 then
		state.cx, state.cy = (c0 + c1) / 2, (r0 + r1) / 2
		state.zoom = FitZoom(c0, r0, c1, r1, 1.0)
	else
		state.cx, state.cy = 32, 32
	end
	SaveView()
	state.dirty = true
end

local function ShowMap(mapID)
	SetFollow(false)
	StopAnimation()
	FitMap(mapID)
end

---------------------------------------------------------------------------
-- Map picker (the title): continents, other open-world maps, and instances
-- by kind and the continent their entrance is on. Uses the client's own
-- menu (MenuUtil) where it exists; otherwise a flat list in our own menu.
---------------------------------------------------------------------------

local KINDS = { { "dungeon", "Dungeons" }, { "raid", "Raids" } }

local function ByName(a, b) return TileData[a].name < TileData[b].name end

-- { continents = {ids}, others = {ids}, dungeon = { {name, ids}, ... }, raid = ... }
local function MapGroups()
	local g = { continents = {}, others = {} }
	local byKind = {}
	for _, id in ipairs(SortedMapIDs()) do
		local data = TileData[id]
		if data.kind then
			local groups = byKind[data.kind] or {}
			byKind[data.kind] = groups
			local cont = data.continent and TileData[data.continent] and TileData[data.continent].name or "Other"
			groups[cont] = groups[cont] or {}
			table.insert(groups[cont], id)
		elseif (tileCounts[id] or 0) >= CONTINENT_MIN_TILES then
			table.insert(g.continents, id)
		else
			table.insert(g.others, id)
		end
	end
	table.sort(g.continents, ByName)
	table.sort(g.others, ByName)
	for _, k in ipairs(KINDS) do
		local list = {}
		for name, ids in pairs(byKind[k[1]] or {}) do
			table.sort(ids, ByName)
			list[#list + 1] = { name = name, ids = ids }
		end
		-- By continent name, with the unplaced ones last.
		table.sort(list, function(a, b)
			if (a.name == "Other") ~= (b.name == "Other") then return b.name == "Other" end
			return a.name < b.name
		end)
		g[k[1]] = list
	end
	return g
end

OpenMapMenu = function(owner)
	-- Without MenuUtil, the fallback menu below opens from the title's clicks itself.
	if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
	local g = MapGroups()
	MenuUtil.CreateContextMenu(owner, function(_, root)
		local function Radio(parent, id)
			parent:CreateRadio(TileData[id].name, function() return state.map == id end, function()
				ShowMap(id)
				frame:Show()
				return MenuResponse and MenuResponse.Close
			end)
		end
		root:CreateTitle("Continents")
		for _, id in ipairs(g.continents) do Radio(root, id) end
		if #g.others > 0 then
			local other = root:CreateButton("Other maps")
			for _, id in ipairs(g.others) do Radio(other, id) end
		end
		if #g.dungeon + #g.raid > 0 then
			root:CreateDivider()
			root:CreateTitle("Instances")
			for _, k in ipairs(KINDS) do
				local groups = g[k[1]]
				if #groups > 0 then
					local kind = root:CreateButton(k[2])
					for _, group in ipairs(groups) do
						-- Only one group: skip the continent level.
						local parent = #groups > 1 and kind:CreateButton(group.name) or kind
						for _, id in ipairs(group.ids) do Radio(parent, id) end
					end
				end
			end
		end
	end)
end

-- Older clients: one scrolling list with section headings, opened by
-- AttachMenu from the title's own clicks.
if not (MenuUtil and MenuUtil.CreateContextMenu) then
	local menu = ns.AttachMenu(titleButton, 220, "downleft")
	menu.onSelect = function(id) ShowMap(id) end
	menu.getItems = function()
		local g, items = MapGroups(), {}
		local function Head(text) items[#items + 1] = { text = "|cffffd100" .. text .. "|r", disabled = true } end
		local function Item(id, indent)
			items[#items + 1] = { text = (indent or "") .. TileData[id].name, value = id, selected = id == state.map }
		end
		Head("Continents")
		for _, id in ipairs(g.continents) do Item(id) end
		if #g.others > 0 then Head("Other maps") end
		for _, id in ipairs(g.others) do Item(id) end
		for _, k in ipairs(KINDS) do
			for _, group in ipairs(g[k[1]]) do
				Head(k[2] .. (#g[k[1]] > 1 and (" · " .. group.name) or ""))
				for _, id in ipairs(group.ids) do Item(id, "  ") end
			end
		end
		return items
	end
end

---------------------------------------------------------------------------
-- Title text. Hovering the map: the zone under the cursor. Otherwise: where
-- you are (or what you're looking at, if browsing another continent).
---------------------------------------------------------------------------

local SEP = "  ·  "
local function Coords(x, y) return string.format("%.1f, %.1f", x * 100, y * 100) end

local hoverZoneID
local function UpdateTitle()
	local continent = TileData[state.map] and TileData[state.map].name or ("Instance " .. tostring(state.map))
	local name, parts = nil, {}
	local hovering = viewport:IsMouseOver()
	local tc, tr
	hoverZoneID = nil
	if hovering then tc, tr = CursorTile() end
	-- Compact (minimap mode) always names where you are; coordinates only on hover.
	local here = compact and state.playerMap and state.playerMap == state.map
	if hovering and not here then
		local z = ns.GetZoneAt and ns.GetZoneAt(tc, tr)
		if z then
			hoverZoneID = z.mapID
			name = z.name
			parts[#parts + 1] = Coords(z.x, z.y)
		else
			name = continent
		end
		local hgt = HeightAt(state.map, tc, tr)
		if hgt then parts[#parts + 1] = string.format("%d yd", math.floor(hgt + 0.5)) end
	elseif here or (state.playerMap and state.playerMap == state.map) then
		local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
		local info = mapID and C_Map.GetMapInfo(mapID)
		name = (info and info.name) or GetZoneText()
		local subzone = GetSubZoneText and GetSubZoneText()
		if subzone and subzone ~= "" and subzone ~= name then parts[#parts + 1] = subzone end
		local pos = mapID and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
		if pos and (not compact or hovering) then
			local x, y = pos:GetXY()
			parts[#parts + 1] = Coords(x, y)
		end
		local t = state.path and (not compact or hovering) and ns.GetTarget and ns.GetTarget()
		if t and state.playerCol then
			local yd = math.sqrt((t.col - state.playerCol) ^ 2 + (t.row - state.playerRow) ^ 2) * TILE_YARDS
			parts[#parts + 1] = string.format("|cffffd27f%s|r %d yd", t.title or "Target", math.floor(yd + 0.5))
		end
	else
		name = state.zoneName or continent
		if not compact then parts[#parts + 1] = "|cff8a7f6eright-click to return to you|r" end
	end
	if db.debug then
		tc, tr = tc or state.cx, tr or state.cy
		local col, row = math.floor(tc), math.floor(tr)
		local tiles = GetTiles(state.map)
		local fdid = tiles and col >= 0 and col < 64 and row >= 0 and row < 64 and tiles[col * 64 + row]
		local ls = ns.layoutStats
		parts[#parts + 1] = string.format("|cff777777%d_%d  %s  zoom %d  layout %.1f ms / %d lines  %s|r",
			col, row, fdid and tostring(fdid) or "-", state.zoom, ls and ls.ms or 0, ls and ls.lines or 0, tostring(tileSetVersion))
	end
	local sub = table.concat(parts, SEP)
	if title:GetText() ~= name or subtitle:GetText() ~= sub then
		title:SetText(name)
		subtitle:SetText(sub)
		FitTitle()
	end

	-- Click-to-zone is offered only while more than one zone is in view.
	local clickable = hoverZoneID and not state.dragging and ns.ZonesInView and ns.ZonesInView() > 1
	if ns.SetHoverZone then ns.SetHoverZone(clickable and hoverZoneID or nil) end
	if ns.OnMapHover then
		if hovering then ns.OnMapHover(tc, tr) else ns.OnMapHover(nil) end
	end
	state.canClickZone = clickable
end

---------------------------------------------------------------------------
-- Input
---------------------------------------------------------------------------

local press -- { x, y, t } of the current left-button press, for click detection

viewport:SetScript("OnMouseDown", function(_, button)
	if button == "LeftButton" and IsAltKeyDown() then
		frame:StartMoving()
		state.movingFrame = true
		return
	end
	if ns.OnMapClick and (IsShiftKeyDown() or IsControlKeyDown()) and ns.OnMapClick(button, CursorTile()) then
		return
	end
	if button == "LeftButton" then
		local scale = viewport:GetEffectiveScale()
		local x, y = GetCursorPosition()
		state.lastInteract = GetTime()
		StopAnimation()
		state.dragging = true
		state.lastCursorX, state.lastCursorY = x / scale, y / scale
		press = { x = x / scale, y = y / scale, t = GetTime(), clickable = state.canClickZone, zone = hoverZoneID }
	end
end)

-- Right-click menu: only what makes sense where and how you clicked.
local function MapMenuItems(col, row)
	local items = {}
	if ns.CanSetWaypoints and ns.CanSetWaypoints() and ns.GetZoneAt and ns.GetZoneAt(col, row) then
		items[#items + 1] = { text = "Waypoint here", value = function()
			if ns.SetWaypointAt(col, row) then SetPath(true) end
		end }
	end
	if ns.HasWaypoint and ns.HasWaypoint() then
		items[#items + 1] = { text = "Clear waypoint", value = ns.ClearWaypoint }
	end
	if not state.follow then
		items[#items + 1] = { text = "Follow me", value = function() SetFollow(true, true) end }
	end
	return items
end

local function OpenMapMenuAt(col, row)
	local items = MapMenuItems(col, row)
	if #items == 0 then return end
	if MenuUtil and MenuUtil.CreateContextMenu then
		MenuUtil.CreateContextMenu(viewport, function(_, root)
			for _, it in ipairs(items) do root:CreateButton(it.text, it.value) end
		end)
	else
		ns.OpenMenuAtCursor(viewport, 140, items, function(fn) fn() end)
	end
end

viewport:SetScript("OnMouseUp", function(_, button)
	if state.movingFrame then
		frame:StopMovingOrSizing()
		state.movingFrame = nil
		local p, _, rp, x, y = frame:GetPoint()
		db.point = { p, rp, x, y }
		return
	end
	if button == "RightButton" then
		-- Modified right-clicks are handled on the way down (ns.OnMapClick).
		if not (IsShiftKeyDown() or IsControlKeyDown()) then OpenMapMenuAt(CursorTile()) end
		return
	end
	if button ~= "LeftButton" then return end
	state.dragging = false
	SaveView()
	-- A quick, still click: on a quest, follows it (ns.OnMapTap; its area only
	-- counts when zone clicks aren't on offer); otherwise, on a zone (while
	-- several are in view), flies there.
	if press and not press.moved and GetTime() - press.t < CLICK_TIME then
		local col, row = CursorTile()
		if ns.OnMapTap and ns.OnMapTap(col, row, not press.clickable) then
			press = nil
			return
		end
		if press.clickable and press.zone then
			local r = MapRect(press.zone)
			local info = C_Map.GetMapInfo(press.zone)
			if r and r.inst == state.map then FlyToRect(r.col0, r.row0, r.col1, r.row1, info and info.name) end
		end
	end
	press = nil
end)

-- One zoom step in (delta > 0) or out, held on you while following, else on
-- the cursor (the wheel) or the view's centre (the buttons).
local function ZoomStep(delta, atCursor)
	local w, h = ViewSize()
	local factor = delta > 0 and WHEEL_STEP or 1 / WHEEL_STEP
	state.lastInteract = GetTime()
	-- Quick ticks stack onto the running target.
	local target = Clamp((zoomGoal or state.zoom) * factor, MIN_ZOOM, MAX_ZOOM)
	anim = nil
	local ax, ay
	if state.follow and state.playerCol then
		ax, ay = TileToScreen(state.playerCol, state.playerRow) -- keep you where you are
	elseif atCursor then
		ax, ay = CursorInViewport()
	else
		ax, ay = w / 2, h / 2
	end
	local tx = state.cx + (ax - w / 2) / state.zoom
	local ty = state.cy + (ay - h / 2) / state.zoom
	zoomGoal, zoomAnchor = target, { tx, ty, ax - w / 2, ay - h / 2 }
end
viewport:SetScript("OnMouseWheel", function(_, delta) ZoomStep(delta, true) end)
zoomIn:SetScript("OnClick", function() ZoomStep(1) end)
zoomOut:SetScript("OnClick", function() ZoomStep(-1) end)

viewport:SetScript("OnSizeChanged", function()
	state.dirty = true
	FitTitle()
end)

local function OnFollowClick() SetFollow(not state.follow, true) end
local function OnPathClick()
	SetPath(not state.path)
	if state.path and not (ns.GetTarget and ns.GetTarget()) then
		Print("path mode on: it leans toward your target once there is one. Ctrl-click the map for a waypoint, or click a quest to follow it.")
	end
end
followToggle:SetScript("OnClick", OnFollowClick)
pathToggle:SetScript("OnClick", OnPathClick)

local function Tooltip(button, fn)
	button:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -4)
		GameTooltip:SetText(fn(), 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
end
local function FollowTip()
	return state.follow and "Following you  |cff888888(drag the map to stop)|r"
		or "Follow me"
end
local function PathTip()
	if state.path then return "Path mode  |cff888888(leaning toward your target; click to turn off)|r" end
	return "Path mode  |cff888888(lean toward your waypoint or followed quest)|r"
end
Tooltip(followToggle, FollowTip)
Tooltip(pathToggle, PathTip)
Tooltip(zoomIn, function() return "Zoom in  |cff888888(sets how close the map rests)|r" end)
Tooltip(zoomOut, function() return "Zoom out  |cff888888(sets how close the map rests)|r" end)
Tooltip(gearButton, function() return "Layers" end)

local titleElapsed = 0
frame:SetScript("OnUpdate", function(_, elapsed)
	local perf = ns.perf
	local t0 = perf and debugprofilestop()
	UpdatePlayer()
	StepAnimation(elapsed)
	StepZoom(elapsed)
	StepTargetChange()
	StepLean(elapsed)

	if state.dragging then
		if not IsMouseButtonDown("LeftButton") then
			state.dragging = false
		else
			local scale = viewport:GetEffectiveScale()
			local x, y = GetCursorPosition()
			x, y = x / scale, y / scale
			local dx, dy = x - state.lastCursorX, y - state.lastCursorY
			if press and (math.abs(x - press.x) > CLICK_SLOP or math.abs(y - press.y) > CLICK_SLOP) then
				press.moved = true
				if state.follow then SetFollow(false) end
			end
			if (dx ~= 0 or dy ~= 0) and (not press or press.moved) then
				state.cx = state.cx - dx / state.zoom
				state.cy = state.cy + dy / state.zoom -- screen y is up, rows grow south
				state.lastCursorX, state.lastCursorY = x, y
				state.dirty = true
			end
		end
	end

	if state.follow and not state.playerCol and state.playerMap and state.playerMap ~= state.map and not anim then
		FitMap(state.playerMap) -- an instance that hides your position: show it whole
	end
	if state.follow and state.playerCol and not anim then
		if state.playerMap ~= state.map then SetMap(state.playerMap) end
		local cx, cy = FollowCenter()
		if state.cx ~= cx or state.cy ~= cy then
			state.cx, state.cy = cx, cy
			state.dirty = true
		end
	end
	if state.dirty then
		RenderTiles()
		state.dirty = false
		Fire("ViewChanged")
	end
	RenderArrow()
	StepHover(elapsed)
	titleElapsed = titleElapsed + (elapsed or 0)
	if titleElapsed > 0.05 then
		titleElapsed = 0
		UpdateTitle()
	end
	if perf then perf.Frame(elapsed or 0, debugprofilestop() - t0) end
end)

frame:SetScript("OnShow", function() db.shown = true; state.dirty = true end)
frame:SetScript("OnHide", function()
	db.shown = false
	state.dragging = false
	if state.movingFrame then
		frame:StopMovingOrSizing()
		state.movingFrame = nil
	end
	SaveView()
end)

-- API for Layers.lua / Landmarks.lua
ns.state = state
ns.frame = frame
ns.viewport = viewport
ns.layerFrames = layerFrames
ns.overlay = overlay
ns.tileCanvas = tileCanvas
ns.gearButton, ns.modeButton = gearButton, modeButton
-- The mode button's art: condense (into the minimap) or expand (back out).
ns.SetModeButtonArt = function(minimapMode) SkinButton(modeButton, minimapMode and MODE_ART.minimap or MODE_ART.window) end
ns.titleText = title
ns.mapControls = { frame = mapControls, zoomIn = zoomIn, zoomOut = zoomOut, follow = followToggle, path = pathToggle }
ns.SetCompact = SetCompact
ns.IsCompact = function() return compact end
ns.FitTitle = FitTitle
ns.SetFollow = SetFollow
ns.Tooltip = Tooltip
ns.SetZoom = function(zoom)
	StopAnimation()
	state.zoom = Clamp(zoom, MIN_ZOOM, MAX_ZOOM)
	SaveView()
	state.dirty = true
end
ns.SaveFrameLayout = function()
	local p, _, rp, x, y = frame:GetPoint()
	db.point = { p, rp, x, y }
	db.width, db.height = frame:GetSize()
end
ns.Print = Print
ns.TileToScreen = TileToScreen
ns.IsAnimating = function() return anim ~= nil or zoomGoal ~= nil end
ns.SetPath, ns.UpdateControls = SetPath, UpdateControls
ns.GoalZoom, ns.GoalCenter = GoalZoom, GoalCenter
ns.FlyTo = function(cx, cy, zoom, duration, onDone) AnimateTo(cx, cy, zoom, duration or FLY_TIME, { onDone = onDone }) end
ns.FitZoom = FitZoom
ns.WorldToTile = WorldToTile
ns.MapRect, ns.MapToTile, ns.TileToMap = MapRect, MapToTile, TileToMap
ns.GetZones, ns.GetContinentMapID, ns.GetQuestMaps = GetZones, GetContinentMapID, GetQuestMaps
ns.slash = {} -- extra /mm subcommands: name -> fn(arg)
ns.activeTiles = activeTiles -- for tests: mapID * 4096 + key -> tile texture

-- The tile colour data on and off, to compare it with the plain tiles.
function ns.slash.tint()
	db.tint = not db.tint
	state.dirty = true -- a different colour table re-lays every tile out
	Print("tile colour correction " .. (db.tint and "on" or "off")
		.. ((db.tint and not (MagicMap_TileColor and MagicMap_TileColor[state.map])) and " (no data for this map)" or ""))
end
ns.Toggle = function() frame:SetShown(not frame:IsShown()) end

---------------------------------------------------------------------------
-- Init + slash commands
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON then
		MagicMapDB = MagicMapDB or {}
		db = MagicMapDB
		for k, v in pairs(defaults) do
			if db[k] == nil then db[k] = v end
		end
		LoadTileSet(PickTileSet())
		frame:SetSize(db.width, db.height)
		frame:ClearAllPoints()
		frame:SetPoint(db.point[1], UIParent, db.point[2], db.point[3], db.point[4])
		state.zoom = Clamp(db.zoom, MIN_ZOOM, MAX_ZOOM)
		state.follow, state.path = db.follow, db.path
		state.cx, state.cy = db.cx, db.cy
		self:UnregisterEvent("ADDON_LOADED")
		Fire("Loaded", db)
	elseif event == "PLAYER_ENTERING_WORLD" then
		UpdatePlayer()
		if not state.map then
			SetMap((not state.follow and db.map) or state.playerMap or db.map or 1)
		elseif state.follow and state.playerMap then
			SetMap(state.playerMap)
		end
		UpdateControls()
		if db.shown then frame:Show() end
	end
end)

SLASH_MAGICMAP1 = "/mm"
SLASH_MAGICMAP2 = "/magicmap"
SlashCmdList.MAGICMAP = function(msg)
	local cmd, arg = strsplit(" ", strtrim(msg or ""):lower(), 2)
	if cmd == "" or cmd == "toggle" then
		ns.Toggle()
	elseif cmd == "follow" then
		SetFollow(not state.follow, true)
	elseif cmd == "path" then
		SetPath(not state.path)
	elseif cmd == "map" then
		local id = tonumber(arg)
		if not id then
			for mapID, data in pairs(TileData) do
				if arg and (data.name:lower() == arg) then id = mapID end
			end
		end
		if id and TileData[id] then
			ShowMap(id)
			frame:Show()
		else
			local names = {}
			for _, mapID in ipairs(SortedMapIDs()) do
				names[#names + 1] = mapID .. "=" .. TileData[mapID].name
			end
			Print("usage: /mm map <id|name>  (" .. table.concat(names, ", ") .. ")")
		end
	elseif cmd == "zone" and arg then
		-- Search every map, preferring the one on screen.
		local found
		for _, mapID in ipairs({ state.map or -1, unpack(SortedMapIDs()) }) do
			for _, zone in ipairs(GetZones(mapID)) do
				if not found and zone.name:lower():find(arg, 1, true) then
					found = zone
					SetMap(mapID)
				end
			end
		end
		if found then
			frame:Show()
			ZoomToZone(found)
		else
			Print("no zone matching '" .. arg .. "'")
		end
	elseif cmd == "tiles" then
		local names = {}
		for _, mapID in ipairs(SortedMapIDs()) do
			names[#names + 1] = TileData[mapID].name .. " (" .. tileCounts[mapID] .. ")"
		end
		Print("tile set: " .. tostring(tileSetName) .. " " .. tostring(tileSetVersion) .. ". Maps: " .. table.concat(names, ", "))
	elseif cmd == "reset" then
		frame:ClearAllPoints()
		frame:SetPoint("CENTER")
		frame:SetSize(defaults.width, defaults.height)
		db.point, db.width, db.height = { "CENTER", "CENTER", 0, 0 }, defaults.width, defaults.height
		state.zoom = defaults.zoom
		SetFollow(true)
		frame:Show()
	elseif cmd == "debug" then
		db.debug = not db.debug
		Print("debug info " .. (db.debug and "on" or "off"))
	elseif ns.slash[cmd] then
		ns.slash[cmd](arg)
	else
		Print("/mm [toggle] | follow | path | map <id|name> | zone <name> | icon | minimap | tiles | tint | layers | landmarks | perf | debug | reset")
	end
end
