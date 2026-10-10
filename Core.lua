-- MagicMap: a large, pannable, zoomable map rendered from the game's own
-- minimap terrain tiles (Texture:SetTexture(fileDataID)).
--
-- Coordinate system ("tile space"): (col, row) as floats, matching the
-- minimap file names world/minimaps/<dir>/map<col>_<row>.blp. Tile (0,0) is
-- the north-west corner of a 64x64 grid; col grows east, row grows south.

local ADDON, ns = ...
local TILE_YARDS = 1600 / 3 -- one ADT / minimap tile = 533.33 yards
-- Screen units per tile. Closest is about Blizzard's own closest minimap zoom
-- (its tiles are 256 px: any closer and they just smear).
local MIN_ZOOM, MAX_ZOOM = 16, 800
local WHEEL_STEP = 1.3
local FLY_TIME = 0.55
local ZOOM_RATE = 14 -- per second: how quickly wheel zoom closes on its target (higher = snappier)
local CLICK_SLOP, CLICK_TIME = 5, 0.35 -- a click moves less than this many px, this fast

local defaults = {
	shown = true,
	width = 200, height = 200, -- point: none until MinimapMode puts it on the minimap's spot
	zoom = 384,
	follow = true,
	path = false, -- following, lean toward your target (see FollowCenter)
	map = nil, -- instanceID being viewed; nil = player's continent
	cx = 32, cy = 32,
	debug = false, -- show tile/FileDataID/zoom in the title band
	tint = true, -- draw tiles with Data/TileColor.lua's tints and coast fades
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
-- Window: the map inside the metal border of Blizzard's ButtonFrameTemplate
-- (Forever's re-skin), the template's own title bar and buttons hidden. On a
-- line just outside the map (above it, or below at the screen's top):
--
--   Zone name  context · coords                          (gear) (mode)
--
-- The zone name is also the map picker: click it for continents and instances.
---------------------------------------------------------------------------

local frame = CreateFrame("Frame", "MagicMapFrame", UIParent, "ButtonFrameTemplate")

frame:SetFrameStrata("HIGH")
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:SetResizable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetResizeBounds(120, 120)
frame:Hide()

ButtonFrameTemplate_HidePortrait(frame)
ButtonFrameTemplate_HideButtonBar(frame)
if frame.Inset then frame.Inset:Hide() end
if frame.TitleContainer and frame.TitleContainer.TitleText then frame.TitleContainer.TitleText:SetText("") end

-- Where the window sits, for the next session (its size is saved on resize).
local function SavePoint()
	local p, _, rp, x, y = frame:GetPoint()
	db.point = { p, rp, x, y }
end

frame:SetScript("OnDragStart", function() frame:StartMoving() end)
frame:SetScript("OnDragStop", function()
	frame:StopMovingOrSizing()
	SavePoint()
end)

-- Viewport: the map, filling the frame inside its border (placed with the
-- border, below). Clips the tiles to it.
local viewport = CreateFrame("Frame", nil, frame)
viewport:SetClipsChildren(true)
viewport:EnableMouse(true)
viewport:EnableMouseWheel(true)

-- Its size, looked up at most once a frame (the map's OnUpdate forgets it)
-- and again whenever it may have changed.
local viewW, viewH
local function ViewSize()
	if not viewW then viewW, viewH = viewport:GetSize() end
	return viewW, viewH
end
local function ViewSizeChanged() viewW = nil end
viewport:HookScript("OnSizeChanged", ViewSizeChanged)
frame:HookScript("OnSizeChanged", ViewSizeChanged)

local viewportBg = viewport:CreateTexture(nil, "BACKGROUND", nil, -8)
viewportBg:SetAllPoints()
viewportBg:SetColorTexture(0, 0, 0, 1)

-- Tiles live on their own child frame so the layers can sit above them.
local tileLayer = CreateFrame("Frame", nil, viewport)
tileLayer:SetAllPoints()
-- The tiles' canvas: tile (col, row) at (col * zoom, -row * zoom) on it, so
-- panning just slides it (one SetPoint a frame). The Minimap and the path
-- line are placed on it too.
local tileCanvas = CreateFrame("Frame", nil, tileLayer)
tileCanvas:SetSize(1, 1)
-- The tiles themselves: on the canvas's spot, laid out at one zoom
-- (tileZoom). While the zoom moves they're scaled to it, as the layers'
-- geometry is, and laid out afresh once it settles.
local tileArt = CreateFrame("Frame", nil, tileLayer)
tileArt:SetSize(1, 1)
local tileZoom, tileScale

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

-- Player marker: the Minimap's own arrow.
local playerMarker = CreateFrame("Frame", nil, overlay)
playerMarker:SetSize(1, 1)
playerMarker:Hide()

local arrow = playerMarker:CreateTexture(nil, "OVERLAY")
arrow:SetAtlas("minimaparrow")
arrow:SetSize(32, 32)
arrow:SetPoint("CENTER")

-- The band: a layer above the template's border (500) and title bar (510),
-- holding the zone line and its buttons. No mouse of its own.
local FONT = (GameFontNormal and GameFontNormal:GetFont()) or STANDARD_TEXT_FONT
local band = CreateFrame("Frame", nil, frame)
band:SetFrameLevel(frame:GetFrameLevel() + 515)
band:SetAllPoints()

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

-- The title doubles as the map picker (see OpenMapMenu): a button over it.
-- Dragging it still moves the window.
local TITLE_COLOR, TITLE_HOVER = { 1, 0.82, 0.25 }, { 1, 0.93, 0.6 }
local OpenMapMenu -- forward

local titleButton = CreateFrame("Button", nil, band)
titleButton:SetPoint("TOPLEFT", title, "TOPLEFT", -4, 3)
titleButton:SetPoint("BOTTOMRIGHT", title, "BOTTOMRIGHT", 4, -3)
titleButton:RegisterForDrag("LeftButton")
titleButton:SetScript("OnDragStart", function(self)
	self.dragged = true
	frame:StartMoving()
end)
titleButton:SetScript("OnDragStop", function()
	frame:StopMovingOrSizing()
	SavePoint()
end)
titleButton:SetScript("OnClick", function(self)
	if self.dragged then
		self.dragged = nil
		return
	end
	OpenMapMenu(self)
end)
titleButton:SetScript("OnEnter", function() title:SetTextColor(unpack(TITLE_HOVER)) end)
titleButton:SetScript("OnLeave", function() title:SetTextColor(unpack(TITLE_COLOR)) end)

local function NaturalWidth(fs)
	return fs:GetUnboundedStringWidth()
end

-- At the minimap's size it names where you are and keeps to actions; grown
-- (M), it reads as a big map, in the same chrome.
local function SmallMap() return not ns.IsMapExpanded() end

-- The controls use Blizzard's own minimap art where the client
-- has it, else plain textures.
local function HasAtlas(name)
	return C_Texture.GetAtlasInfo(name) ~= nil
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
-- menu (the world map's gold gear), and the world map's red expand button,
-- which grows the map as M does (MinimapMode.lua).
local HEADER_ICON = 20
local modeButton = ArtButton(band, HEADER_ICON, HEADER_ICON, {
	atlas = { "redbutton-expand-c60", "redbutton-expand" },
	pushed = { "redbutton-expand-pressed-c60", "redbutton-expand-pressed" },
	highlight = { "redbutton-highlight-c60", "redbutton-highlight" },
})
local gearButton = ArtButton(band, HEADER_ICON + 4, HEADER_ICON + 4, {
	file = "Interface\\WorldMap\\Gear_64", coords = { 0, 0.5, 0, 0.5 }, pushedCoords = { 0, 0.5, 0.5, 1 },
})
gearButton:SetPoint("RIGHT", modeButton, "LEFT", -6, 0)

-- The zone, then subzone, left-aligned on one line just above the map (below
-- it, if the map is at the top of the screen), with the gear and red buttons
-- at its right end - no plate, like the minimap's own.
local function FitTitle()
	title:ClearAllPoints()
	subtitle:ClearAllPoints()
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

-- The template's frame (whose top is a header bar) gives way to the same
-- metal border with plain top corners (UI.lua); the map fills it, and the
-- buttons and grip fade in while you hover.
local border = ns.ApplyBorder(frame, frame:GetFrameLevel() + 505, frame.NineSlice)

-- Inside the map, shown while you hover: follow and path toggles (bottom
-- left) and zoom buttons (bottom right, where the minimap keeps them).
local mapControls = CreateFrame("Frame", nil, frame)
mapControls:SetAllPoints(viewport)
mapControls:SetFrameLevel(frame:GetFrameLevel() + 518) -- under the resize grip

local PAD = 12 -- from the map's edges
local function ZoomArt(name)
	return { atlas = { name }, pushed = { name .. "-down" }, highlight = { name .. "-mouseover" } }
end
local zoomOut = ArtButton(mapControls, 20, 11, ZoomArt("ui-hud-minimap-zoom-out"))
zoomOut:SetPoint("BOTTOMRIGHT", -PAD, PAD + 6) -- clear of the resize grip
local zoomIn = ArtButton(mapControls, 20, 20, ZoomArt("ui-hud-minimap-zoom-in"))
zoomIn:SetPoint("BOTTOM", zoomOut, "TOP", 0, 2)

-- A toggle: a dark disc with an icon, ringed in gold and lit while on.
local TOGGLE = 24
local function Toggle(atlas)
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
	b.icon:SetAtlas(atlas)
	b.icon:SetPoint("CENTER")
	b.icon:SetSize(TOGGLE - 7, TOGGLE - 7)
	local glow = b:CreateTexture(nil, "HIGHLIGHT")
	glow:SetTexture(ns.CIRCLE)
	glow:SetVertexColor(1, 1, 1, 0.12)
	glow:SetAllPoints(disc)
	return b
end
local followToggle = Toggle("ui-hud-minimap-arrow-player")
followToggle:SetPoint("BOTTOMLEFT", PAD, PAD)
local pathToggle = Toggle("ui-hud-minimap-arrow-questtracking")
pathToggle:SetPoint("LEFT", followToggle, "RIGHT", 5, 0)

local function SetLit(b, on)
	b.ring:SetShown(on)
	b.icon:SetDesaturated(not on)
	b.icon:SetAlpha(on and 1 or 0.6)
end

-- Everything of the template but its border's art goes; the map stops where
-- that art begins.
local KEEP = { [viewport] = true, [band] = true, [resizeGrip] = true, [border] = true, [mapControls] = true }
for _, r in ipairs({ frame:GetRegions() }) do r:Hide() end
for _, c in ipairs({ frame:GetChildren() }) do
	if not KEEP[c] then c:Hide() end
end
viewport:ClearAllPoints()
viewport:SetPoint("TOPLEFT", border.insets[1], -border.insets[2])
viewport:SetPoint("BOTTOMRIGHT", -border.insets[3], border.insets[4])

local hoverAlpha = 1

-- The controls and grip fade in while the mouse is over the map.
local function StepHover(elapsed)
	-- The header line (above or below the map) counts as over it.
	local reach = HEADER_ICON + 12
	local want = (frame:IsMouseOver(reach, -reach, 0, 0) or ns.IsMenuOpen()) and 1 or 0
	if hoverAlpha == want then return end
	local step = (elapsed or 0) / 0.15
	hoverAlpha = want > hoverAlpha and math.min(want, hoverAlpha + step) or math.max(want, hoverAlpha - step)
	mapControls:SetAlpha(hoverAlpha)
	gearButton:SetAlpha(hoverAlpha)
	modeButton:SetAlpha(hoverAlpha)
	resizeGrip:SetAlpha(0.8 * hoverAlpha)
end

---------------------------------------------------------------------------
-- The tile set: Data/Tiles.lua, generated from WoW Forever's own WDT files,
-- which list the exact minimap FileDataID for every tile it uses (the same
-- ID can hold different images in other versions, so the list has to come
-- from Forever's). Regenerate it when a patch changes the terrain.
---------------------------------------------------------------------------

local tileSetName, tileSetVersion
local tileCounts = {}

local function LoadTileSet()
	local set = MagicMap_Tiles
	tileSetName, tileSetVersion = set and set.product, set and set.version
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
-- With colour data (Data/TileColor.lua: the mean colour along each
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
local SUB_CORNER, SUB_CORNER_BG, SUB_OUTER, SUB_TILE, SUB_ADD, SUB_WATER, SUB_FEATHER = -3, -2, -1, 0, 1, 2, 3
local bgColor = { 0, 0, 0 }

local function SetFade(t, orientation, r, g, b, a1, a2)
	t:SetColorTexture(1, 1, 1, 1)
	t:SetGradient(orientation, CreateColor(r, g, b, a1), CreateColor(r, g, b, a2))
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
	tex:SetSnapToPixelGrid(false)
	tex:SetTexelSnappingBias(0)
	return tex
end

local function Piece(sublevel)
	local t = Unsnapped(tileArt:CreateTexture(nil, "ARTWORK", nil, sublevel))
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
		tex = Unsnapped(tileArt:CreateTexture(nil, "ARTWORK", nil, SUB_TILE))
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
	-- Off the canvas: a spare (and its pieces, anchored to it) mustn't be
	-- re-placed by the client every time the canvas moves. LayoutTile
	-- anchors it again when it's next used.
	tex:ClearAllPoints()
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
	SetOn(tex.water, false)
	tex.fdid, tex.zoom, tex.colors = nil, nil, nil
	freeTextures[#freeTextures + 1] = tex
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
local function LayoutTile(tex, tiles, key, zoom, colors, mapID)
	local sea = colors and colors.sea
	local col, row = math.floor(key / 64), key % 64
	local left, top = math.floor(col * zoom + 0.5), math.floor(row * zoom + 0.5)
	local w = math.floor((col + 1) * zoom + 0.5) - left
	local h = math.floor((row + 1) * zoom + 0.5) - top
	tex:SetPoint("TOPLEFT", tileArt, "TOPLEFT", left, -top)
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

	-- Shallow coastal water the tile was baked a different blue from the open
	-- sea: a mask (white; alpha = how much sea covers each pixel) tinted the
	-- backdrop colour pulls it toward the sea around it.
	if colors and colors.water and colors.water[key] then
		local water = tex.water
		if not water then
			water = Piece(SUB_WATER)
			water:SetAllPoints(tex)
			tex.water = water
		end
		local path = colors.waterDir .. mapID .. "_" .. key .. ".tga"
		if water.path ~= path then
			water:SetTexture(path, "CLAMP", "CLAMP", "LINEAR")
			water.path = path
		end
		if water.bg ~= bgColor then
			water:SetVertexColor(bgColor[1], bgColor[2], bgColor[3])
			water.bg = bgColor
		end
		SetOn(water, true)
	else
		SetOn(tex.water, false)
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

-- What RenderTiles last looked over. While all of it is the same (panning
-- within a tile), there's nothing new to draw or let go.
local scanned = {}

local function RenderTiles()
	local w, h = ViewSize()
	if w <= 0 or h <= 0 then return end
	local zoom = state.zoom
	local halfW, halfH = w / 2, h / 2
	local cx, cy = state.cx, state.cy
	-- Not rounded: the layers, the Minimap and your arrow move by fractions of
	-- a pixel, so the terrain must too or they'd wobble against it. (Tiles
	-- keep whole-pixel spots on the canvas, so seams stay exact.)
	local perf = ns.perf
	local t0 = perf and debugprofilestop()
	local x, y = halfW - cx * zoom, -(halfH - cy * zoom)
	tileCanvas:SetPoint("TOPLEFT", tileLayer, "TOPLEFT", x, y)
	-- Laid out afresh at rest, or once the zoom has moved half as far again.
	if not (ns.IsAnimating() and tileZoom and zoom < tileZoom * 1.5 and tileZoom < zoom * 1.5) then tileZoom = zoom end
	local scale = zoom / tileZoom
	if scale ~= tileScale then
		tileScale = scale
		tileArt:SetScale(scale)
	end
	tileArt:SetPoint("TOPLEFT", tileLayer, "TOPLEFT", x / scale, y / scale) -- (in its own, scaled units)
	if perf then
		local t1 = debugprofilestop()
		perf.Spent("> map: tiles: moving the canvas", t1 - t0)
		t0 = t1
	end

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
		local s = scanned
		if s.map == mapID and s.zoom == tileZoom and s.colors == colors and s.bg == bgColor and s.tiles == tiles
			and s.c0 == colMin and s.c1 == colMax and s.r0 == rowMin and s.r1 == rowMax then
			if perf then perf.Spent("> map: tiles: which are in view, new ones", debugprofilestop() - t0) end
			return
		end
		s.map, s.zoom, s.colors, s.bg, s.tiles = mapID, tileZoom, colors, bgColor, tiles
		s.c0, s.c1, s.r0, s.r1 = colMin, colMax, rowMin, rowMax
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
					if tex.zoom ~= tileZoom or tex.bg ~= bgColor or tex.colors ~= colors then
						LayoutTile(tex, tiles, key, tileZoom, colors, mapID)
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
			if not tiles or math.floor(id / 4096) ~= mapID or tex.zoom ~= tileZoom or (sea and sea[key])
				or col + 1 < c0 or col > c1 or row + 1 < r0 or row > r1 then
				ReleaseTexture(tex)
				activeTiles[id] = nil
			end
		end
	end
	if perf then perf.Spent("> map: tiles: which are in view, new ones", debugprofilestop() - t0) end
end

-- Only what changed: most frames you've neither moved nor turned.
local marker = {}
local function RenderArrow()
	if state.playerCol and state.playerMap == state.map and not ns.MinimapShowsPlayer() then
		local w, h = ViewSize()
		local x = (state.playerCol - state.cx) * state.zoom + w / 2
		local y = (state.playerRow - state.cy) * state.zoom + h / 2
		if x ~= marker.x or y ~= marker.y then
			marker.x, marker.y = x, y
			playerMarker:SetPoint("CENTER", overlay, "TOPLEFT", x, -y)
		end
		local facing = GetPlayerFacing()
		if facing ~= marker.facing then
			marker.facing = facing
			if facing then arrow:SetRotation(facing) end
			arrow:SetShown(facing ~= nil)
		end
		if not marker.on then
			marker.on = true
			playerMarker:Show()
		end
	elseif marker.on then
		marker.on = false
		playerMarker:Hide()
	end
end

---------------------------------------------------------------------------
-- Map geometry from C_Map (world-space rectangles; no map artwork is used)
---------------------------------------------------------------------------

local MAPTYPE_CONTINENT = Enum.UIMapType.Continent
local MAPTYPE_ZONE = Enum.UIMapType.Zone
local MAPTYPE_MICRO = Enum.UIMapType.Micro

local mapRects = {}        -- uiMapID -> { inst, col0, row0, col1, row1 } | false
local zonesByMap           -- instanceID -> sorted list of zone rects (+ name, uiMapID)
local continentByInst = {} -- instanceID -> uiMapID of the continent map
local questMapsByInst = {} -- instanceID -> uiMapIDs (zones + micro maps) that can carry quests

-- A uiMap is an axis-aligned rectangle in world space, so two corners
-- give us a linear transform between its normalized coords and tile space.
local function MapRect(uiMapID)
	local rect = mapRects[uiMapID]
	if rect ~= nil then return rect or nil end
	rect = false
	if uiMapID then
		local ok, inst, tl = pcall(C_Map.GetWorldPosFromMapPos, uiMapID, CreateVector2D(0, 0))
		local ok2, inst2, br = pcall(C_Map.GetWorldPosFromMapPos, uiMapID, CreateVector2D(1, 1))
		if ok and ok2 and inst and tl and br and inst == inst2 then
			-- Same axis order as UnitPosition: (north, west).
			local top, left = tl:GetXY()
			local bottom, right = br:GetXY()
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
local restZoom -- while path mode has zoomed out to show your target: your own zoom, to come back to

local function SaveView()
	db.zoom, db.cx, db.cy = restZoom or state.zoom, state.cx, state.cy
end

local function EaseOutCubic(t) return 1 - (1 - t) ^ 3 end

-- opts.anchor = { tx, ty, dx, dy }: keep world point (tx,ty) at screen offset (dx,dy) from centre.
local function AnimateTo(cx, cy, zoom, duration, opts)
	opts = opts or {}
	zoomGoal, restZoom = nil, nil
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

-- Following puts you in the middle. Path mode keeps your target (the quest
-- you follow, else your waypoint) in view: you sit halfway toward it, and when
-- it wouldn't fit at your zoom, the view eases out just enough to show you
-- both, and back in as it comes closer or goes. Your zoom meanwhile is
-- restZoom: the wheel changes it, and it's what's saved. Past MIN_ZOOM it
-- stops; you stay in view and the edge arrow points the way.
local PATH_MARGIN = 28 -- px kept clear around you and the target
local PATH_SLACK = 0.8 -- zooming out for the target, this much further than needed
local PATH_RATE, LEAN_RATE = 4, 4 -- per second: how quickly the zoom and the lean settle
local leanX, leanY = 0, 0 -- in tiles, eased
local pathFit -- the closest zoom that shows you both, this frame (nil: no target)
local pathGoal -- the zoom path mode is easing to
local frameTarget -- ns.GetTarget(), once a frame (StepPath), for everything that draws it

-- Where following puts the centre: you, plus the lean.
local function FollowCenter()
	return state.playerCol + leanX, state.playerRow + leanY
end

local function StepPath(elapsed)
	frameTarget = ns.GetTarget()
	local t = state.path and frameTarget
	local w, h = ViewSize()
	local wx, wy = 0, 0
	pathFit = nil
	-- Inside the followed quest's area you've arrived: no lean, your zoom.
	if t and not t.inside and state.playerCol and state.playerMap == state.map then
		local dc, dr = t.col - state.playerCol, t.row - state.playerRow
		local d = math.sqrt(dc * dc + dr * dr) * state.zoom -- px
		if d >= 1 then
			local k = math.min(d / 2, math.min(w, h) / 2 - PATH_MARGIN) / d
			wx, wy = dc * k, dr * k
		end
		local zx = dc ~= 0 and (w - 2 * PATH_MARGIN) / math.abs(dc) or MAX_ZOOM
		local zy = dr ~= 0 and (h - 2 * PATH_MARGIN) / math.abs(dr) or MAX_ZOOM
		pathFit = Clamp(math.min(zx, zy), MIN_ZOOM, MAX_ZOOM)
	end
	local k = math.min(1, LEAN_RATE * (elapsed or 0))
	leanX, leanY = leanX + (wx - leanX) * k, leanY + (wy - leanY) * k

	-- The zoom: yours, or as close as shows you both. Not while a flight or
	-- the wheel has it, and only while following (pan away and it's yours).
	-- Every zoom change lays the map out again, so it moves in steps, not every
	-- frame as you ride: out a little further than needed (PATH_SLACK), held
	-- while the target stays in view, back in only once there's clearly room.
	if anim or zoomGoal then
		pathGoal = nil
		return
	end
	if not state.follow then
		restZoom, pathGoal = nil, nil
		return
	end
	local z, rest = state.zoom, restZoom or state.zoom
	if not pathGoal then
		local roomy = pathFit and math.min(rest, pathFit * PATH_SLACK) or rest
		if pathFit and z > pathFit then
			pathGoal = math.max(MIN_ZOOM, roomy)
		elseif restZoom and (roomy > z * 1.25 or roomy == rest) and roomy ~= z then
			pathGoal = roomy
		else
			return
		end
		restZoom = rest
	end
	local lz, lg = math.log(z), math.log(pathGoal)
	if math.abs(lg - lz) < 0.01 then
		state.zoom = pathGoal
		if pathGoal == rest then restZoom = nil end
		pathGoal = nil
	else
		state.zoom = math.exp(lz + (lg - lz) * (1 - math.exp(-PATH_RATE * (elapsed or 0))))
	end
	state.dirty = true
end

-- Where the camera is headed: the zoom and centre it will settle at.
local function GoalZoom()
	return zoomGoal or (anim and anim.tz) or pathGoal or state.zoom
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
	local key, bringBack = ns.TargetKey()
	if key == lastTargetKey then return end
	local first = lastTargetKey == false
	lastTargetKey = key
	if first then return end -- what you had at login keeps your saved choice
	if bringBack then
		SetPath(true) -- your corpse: back to following you, leaning toward it
	elseif key and not state.path then
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
		local inst = select(8, GetInstanceInfo())
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
-- by kind and the continent their entrance is on, in the client's own menu.
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
	local g = MapGroups()
	ns.OpenClientMenu(owner, function(_, root)
		local function Radio(parent, id)
			parent:CreateRadio(TileData[id].name, function() return state.map == id end, function()
				ShowMap(id)
				frame:Show()
				return MenuResponse.Close
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

---------------------------------------------------------------------------
-- Title text. Hovering the map: the zone under the cursor. Otherwise: where
-- you are (or what you're looking at, if browsing another continent).
---------------------------------------------------------------------------

local SEP = "  ·  "
local function Coords(x, y) return string.format("%.1f, %.1f", x * 100, y * 100) end

local hoverZoneID
-- Kept between updates (it runs 20 times a second): the parts list, map
-- names, and what the title last showed.
local titleParts, mapNames, shownName, shownSub = {}, {}, nil, nil
local function MapName(mapID)
	local n = mapNames[mapID]
	if n == nil then
		local info = C_Map.GetMapInfo(mapID)
		n = info and info.name or false
		mapNames[mapID] = n
	end
	return n or nil
end

local function UpdateTitle()
	local continent = TileData[state.map] and TileData[state.map].name or ("Instance " .. tostring(state.map))
	local name, parts = nil, wipe(titleParts)
	local hovering = viewport:IsMouseOver()
	local tc, tr
	hoverZoneID = nil
	if hovering then tc, tr = CursorTile() end
	-- At the minimap's size it always names where you are; coordinates only on hover.
	local here = SmallMap() and state.playerMap and state.playerMap == state.map
	if hovering and not here then
		local z = ns.GetZoneAt and ns.GetZoneAt(tc, tr)
		if z then
			hoverZoneID = z.mapID
			name = z.name
			parts[#parts + 1] = Coords(z.x, z.y)
		else
			name = continent
		end
	elseif here or (state.playerMap and state.playerMap == state.map) then
		local mapID = C_Map.GetBestMapForUnit("player")
		name = (mapID and MapName(mapID)) or GetZoneText()
		local subzone = GetSubZoneText()
		if subzone and subzone ~= "" and subzone ~= name then parts[#parts + 1] = subzone end
		-- From where we already have you (no position object to make).
		local x, y
		if mapID and (not SmallMap() or hovering) then
			if state.playerCol then x, y = TileToMap(mapID, state.playerCol, state.playerRow) end
			if not x then -- (a map we have no rect for)
				local pos = C_Map.GetPlayerMapPosition(mapID, "player")
				if pos then x, y = pos:GetXY() end
			end
		end
		if x then parts[#parts + 1] = Coords(x, y) end
		local t = state.path and (not SmallMap() or hovering) and frameTarget
		if t and t.inside then
			parts[#parts + 1] = string.format("|cffffd27f%s|r here", t.title or "Target")
		elseif t and state.playerCol then
			local yd = math.sqrt((t.col - state.playerCol) ^ 2 + (t.row - state.playerRow) ^ 2) * TILE_YARDS
			parts[#parts + 1] = string.format("|cffffd27f%s|r %d yd", t.title or "Target", math.floor(yd + 0.5))
		end
	else
		name = state.zoneName or continent
		if not SmallMap() then parts[#parts + 1] = "|cff8a7f6eright-click to return to you|r" end
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
	if name ~= shownName or sub ~= shownSub then
		shownName, shownSub = name, sub
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
	if ns.GetZoneAt and ns.GetZoneAt(col, row) then
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

-- The big map leads with what's at the click (ZoneInfo.lua); at the
-- minimap's size it keeps to the actions.
local function OpenMapMenuAt(col, row)
	local items = MapMenuItems(col, row)
	local info = not SmallMap() and ns.ZoneInfoAt and ns.ZoneInfoAt(col, row) or nil
	if #items == 0 and not info then return end
	ns.OpenClientMenu(viewport, function(_, root)
		if info then
			for _, line in ipairs(info) do root:CreateTitle(line) end
			if #items > 0 then root:CreateDivider() end
		end
		for _, it in ipairs(items) do root:CreateButton(it.text, it.value) end
	end)
end

viewport:SetScript("OnMouseUp", function(_, button)
	if state.movingFrame then
		frame:StopMovingOrSizing()
		state.movingFrame = nil
		SavePoint()
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
	-- Quick ticks stack onto the running target. Path mode showing your target
	-- (restZoom): the wheel changes your zoom, but never past what shows it.
	local target = Clamp((restZoom or zoomGoal or state.zoom) * factor, MIN_ZOOM, MAX_ZOOM)
	if restZoom then
		restZoom = target
		target = math.min(target, pathFit or target)
	end
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

viewport:SetScript("OnSizeChanged", function() -- (in place of the hook above)
	ViewSizeChanged()
	state.dirty = true
	FitTitle()
end)

local function OnFollowClick() SetFollow(not state.follow, true) end
local function OnPathClick()
	SetPath(not state.path)
	if state.path and not frameTarget then
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
Tooltip(gearButton, function() return "Layers, tracking and settings" end)

local titleElapsed = 0
-- While /mm perf records, the map script's parts are timed too ("> " marks
-- a part of "map", not counted again in the total).
local function Mark(perf, name, t)
	local now = debugprofilestop()
	perf.Spent(name, now - t)
	return now
end
frame:SetScript("OnUpdate", ns.Timed("map", function(_, elapsed)
	local perf = ns.perf
	local t0 = perf and debugprofilestop()
	local t = t0
	UpdatePlayer()
	if perf then t = Mark(perf, "> map: your position", t) end
	StepAnimation(elapsed)
	StepZoom(elapsed)
	StepTargetChange()
	StepPath(elapsed)
	if perf then t = Mark(perf, "> map: camera", t) end

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
	if perf then t = Mark(perf, "> map: following", t) end
	if state.dirty then
		RenderTiles()
		if perf then t = Mark(perf, "> map: tiles", t) end
		state.dirty = false
		Fire("ViewChanged")
		if perf then t = Mark(perf, "> map: view changed (layers, addon pins)", t) end
	end
	RenderArrow()
	StepHover(elapsed)
	if perf then t = Mark(perf, "> map: arrow, hover", t) end
	titleElapsed = titleElapsed + (elapsed or 0)
	if titleElapsed > 0.05 then
		titleElapsed = 0
		UpdateTitle()
		if perf then Mark(perf, "> map: title", t) end
	end
	if perf then perf.Frame(elapsed or 0, debugprofilestop() - t0) end
end))

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

-- API for the other modules
ns.state = state
ns.frame = frame
ns.viewport = viewport
ns.layerFrames = layerFrames
ns.overlay = overlay
ns.tileCanvas = tileCanvas
ns.gearButton, ns.modeButton = gearButton, modeButton
ns.titleText = title
ns.mapControls = { frame = mapControls, zoomIn = zoomIn, zoomOut = zoomOut, follow = followToggle, path = pathToggle }
ns.SetFollow = SetFollow
ns.Tooltip = Tooltip
ns.SetZoom = function(zoom)
	StopAnimation()
	restZoom = nil
	state.zoom = Clamp(zoom, MIN_ZOOM, MAX_ZOOM)
	SaveView()
	state.dirty = true
end
ns.SaveFrameLayout = function()
	SavePoint()
	db.width, db.height = frame:GetSize()
end
ns.Print = Print
ns.TileToScreen = TileToScreen
ns.ViewSize = ViewSize
-- The target this frame (Path.lua): ns.GetTarget's, looked up once.
ns.FrameTarget = function() return frameTarget end
ns.IsAnimating = function() return anim ~= nil or zoomGoal ~= nil or pathGoal ~= nil end
-- The tile under the cursor (nil before the window is laid out).
ns.CursorTile = function()
	if not viewport:GetLeft() then return nil end
	return CursorTile()
end
-- The view as it is this frame, for the Minimap's placing: read-only, one table reused.
local camera = {}
ns.Camera = function()
	local c = camera
	c.zoom, c.cx, c.cy = state.zoom, state.cx, state.cy
	c.viewW, c.viewH = ViewSize()
	c.animating = anim ~= nil or zoomGoal ~= nil or pathGoal ~= nil
	c.onMap = state.playerCol ~= nil and state.playerMap == state.map
	c.playerCol, c.playerRow = state.playerCol, state.playerRow
	if c.onMap then
		c.playerX, c.playerY = TileToScreen(state.playerCol, state.playerRow)
	else
		c.playerX, c.playerY = nil, nil
	end
	c.canvas = tileCanvas -- the tiles' canvas: tile (col, row) sits at (col * zoom, -row * zoom) on it
	return c
end
ns.SetPath, ns.UpdateControls = SetPath, UpdateControls
ns.GoalZoom, ns.GoalCenter = GoalZoom, GoalCenter
ns.FlyTo = function(cx, cy, zoom, duration, onDone) AnimateTo(cx, cy, zoom, duration or FLY_TIME, { onDone = onDone }) end
ns.WorldToTile = WorldToTile
ns.MapRect, ns.MapToTile, ns.TileToMap = MapRect, MapToTile, TileToMap
ns.GetZones, ns.GetContinentMapID, ns.GetQuestMaps = GetZones, GetContinentMapID, GetQuestMaps
ns.slash = {} -- extra /mm subcommands: name -> fn(arg)
ns.activeTiles = activeTiles -- for tests: mapID * 4096 + key -> tile texture
-- For /mm perf mem: tile textures drawn now, and spare ones kept for reuse.
ns.TileCounts = function()
	local n = 0
	for _ in pairs(activeTiles) do n = n + 1 end
	return n, #freeTextures
end

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
events:SetScript("OnEvent", ns.TimedEvents("core", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON then
		MagicMapDB = MagicMapDB or {}
		db = MagicMapDB
		for k, v in pairs(defaults) do
			if db[k] == nil then db[k] = v end
		end
		LoadTileSet()
		frame:SetSize(db.width, db.height)
		frame:ClearAllPoints()
		if db.point then
			frame:SetPoint(db.point[1], UIParent, db.point[2], db.point[3], db.point[4])
		else
			frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -20) -- until MinimapMode places it
		end
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
end))

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
		ns.ResetLayout()
	elseif cmd == "debug" then
		db.debug = not db.debug
		Print("debug info " .. (db.debug and "on" or "off"))
	elseif ns.slash[cmd] then
		ns.slash[cmd](arg)
	else
		Print("/mm [toggle] | follow | path | map <id|name> | zone <name> | icon | tiles | tint | dupes | layers | landmarks | perf | debug | reset")
	end
end
