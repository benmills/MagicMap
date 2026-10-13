-- Indoor ground: where Blizzard's Minimap would show its indoor floor plan
-- (Undercity, a city's halls, a dungeon floor), we draw the art of the map
-- you're on instead, as Blizzard's own HybridMinimap does: the world map's
-- art for that uiMap (C_Map.GetMapArtLayers / GetMapArtLayerTextures), on
-- the tiles' canvas above the terrain and below every layer, over a dark
-- backdrop so the ground above doesn't show through. Pins, the sensor's
-- blips and the arrow carry on as outdoors. MinimapTakeover decides when;
-- where a map has no art, the window still wears Blizzard's whole Minimap.
--
-- /mm indoor (or gear > Settings > Advanced) says what's decided as you
-- move and outlines the art.

local ADDON, ns = ...
local state = ns.state
local A = {}
ns.IndoorArt = A

local BACKDROP = { 0.06, 0.05, 0.04, 1 } -- under the art, over the terrain above
-- Only the art of the place itself: a dungeon floor or a sub-zone map, or a
-- city's (narrower than this). Indoors in a hut, the map you're on is the
-- whole zone, and its art is the zone's painting.
local MAX_ART_YARDS = 1600

local db
local canvas = ns.tileCanvas
local cache = {} -- uiMapID -> { rect, pieces = { { file, c0, r0, c1, r1, u, v } } } | false
local textures = {} -- in use, then spare
local used = 0
local backdrop, outline
local shownMap, laidZoom

local function Unsnapped(t)
	t:SetSnapToPixelGrid(false)
	t:SetTexelSnappingBias(0)
	return t
end

-- The art of `uiMapID` as pieces in tile space, or false if it has none on
-- the map we can place it on.
local function Art(uiMapID)
	local art = cache[uiMapID]
	if art ~= nil then return art end
	art = false
	local rect = ns.MapRect(uiMapID)
	local info = C_Map.GetMapInfo(uiMapID)
	if rect and info and info.mapType and info.mapType < Enum.UIMapType.Dungeon
		and (rect.col1 - rect.col0) * ns.TILE_YARDS > MAX_ART_YARDS then
		rect = nil -- (a zone's, or bigger)
	end
	local ok, layers = pcall(C_Map.GetMapArtLayers, uiMapID)
	local layer = ok and type(layers) == "table" and layers[1]
	local ok2, files = false, nil
	if layer then ok2, files = pcall(C_Map.GetMapArtLayerTextures, uiMapID, 1) end
	if rect and layer and ok2 and type(files) == "table" and #files > 0
		and layer.layerWidth > 0 and layer.tileWidth > 0 and layer.layerHeight > 0 and layer.tileHeight > 0 then
		local W, H, tw, th = layer.layerWidth, layer.layerHeight, layer.tileWidth, layer.tileHeight
		local cols = math.ceil(W / tw)
		local cw, rh = rect.col1 - rect.col0, rect.row1 - rect.row0
		local pieces = {}
		for i, file in ipairs(files) do
			local c, r = (i - 1) % cols, math.floor((i - 1) / cols)
			local x0, y0 = c * tw / W, r * th / H
			local x1, y1 = math.min((c + 1) * tw, W) / W, math.min((r + 1) * th, H) / H
			if x0 < 1 and y0 < 1 then
				pieces[#pieces + 1] = { file,
					rect.col0 + cw * x0, rect.row0 + rh * y0, rect.col0 + cw * x1, rect.row0 + rh * y1,
					(x1 - x0) * W / tw, (y1 - y0) * H / th }
			end
		end
		art = { rect = rect, pieces = pieces, layers = #layers, size = W .. "x" .. H }
	end
	cache[uiMapID] = art
	return art
end

-- Whether the art of `uiMapID` can stand in for the floor plan now: it has
-- some, on the map being shown.
function A.Usable(uiMapID)
	local art = uiMapID and Art(uiMapID)
	return art and art.rect.inst == state.map or false
end

local function Place(t, c0, r0, c1, r1, z)
	t:ClearAllPoints()
	t:SetPoint("TOPLEFT", canvas, "TOPLEFT", c0 * z, -r0 * z)
	t:SetSize((c1 - c0) * z, (r1 - r0) * z)
end

local function Layout()
	local art = shownMap and Art(shownMap)
	if not art then return end
	local z = state.zoom
	laidZoom = z
	local r = art.rect
	Place(backdrop, r.col0, r.row0, r.col1, r.row1, z)
	for i, p in ipairs(art.pieces) do Place(textures[i], p[2], p[3], p[4], p[5], z) end
	if outline:IsShown() then
		outline:ClearAllPoints()
		outline:SetPoint("TOPLEFT", backdrop)
		outline:SetPoint("BOTTOMRIGHT", backdrop)
	end
end

local function Hide()
	for i = 1, used do textures[i]:Hide() end
	used = 0
	if backdrop then backdrop:Hide() end
	if outline then outline:Hide() end
end

-- Draw the art of `uiMapID` (nil: none). Cheap when it's already shown.
function A.Show(uiMapID)
	if uiMapID == shownMap then return end
	shownMap = uiMapID
	Hide()
	local art = uiMapID and Art(uiMapID)
	if not art then
		shownMap = nil
		return
	end
	if not backdrop then
		backdrop = canvas:CreateTexture(nil, "OVERLAY", nil, -8)
		backdrop:SetColorTexture(unpack(BACKDROP))
		outline = CreateFrame("Frame", nil, canvas)
		for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT", true }, { "TOPRIGHT", "BOTTOMRIGHT", true } }) do
			local t = outline:CreateTexture(nil, "OVERLAY")
			t:SetColorTexture(1, 0.2, 0.8, 0.9)
			t:SetPoint(e[1])
			t:SetPoint(e[2])
			if e[3] then t:SetWidth(2) else t:SetHeight(2) end
		end
	end
	backdrop:Show()
	for i, p in ipairs(art.pieces) do
		local t = textures[i]
		if not t then
			t = Unsnapped(canvas:CreateTexture(nil, "OVERLAY", nil, 0))
			textures[i] = t
		end
		t:SetTexture(p[1])
		t:SetTexCoord(0, p[6], 0, p[7])
		t:Show()
	end
	used = #art.pieces
	outline:SetShown(db and db.indoorDebug or false)
	Layout()
end

function A.Shown() return shownMap end

ns.On("ViewChanged", function()
	if shownMap and state.zoom ~= laidZoom then Layout() end
end)

---------------------------------------------------------------------------
-- /mm indoor: what's decided, as it changes, and the art outlined.
---------------------------------------------------------------------------

local lastNote
-- MinimapTakeover's decision this frame: the map you're on, whether the
-- Minimap draws its indoor map, and what the window shows ("art", "floor
-- plan" or "terrain").
function A.Note(uiMapID, indoor, shows)
	if not (db and db.indoorDebug) then return end
	local key = tostring(uiMapID) .. (indoor and "i" or "o") .. shows
	if key == lastNote then return end
	lastNote = key
	local info = uiMapID and C_Map.GetMapInfo(uiMapID)
	local art = uiMapID and Art(uiMapID)
	ns.Print(("indoor: map %s (%s, type %s); Minimap %s; art %s; showing %s"):format(
		tostring(uiMapID), info and info.name or "?", info and tostring(info.mapType) or "?",
		indoor and "indoors" or "outdoors",
		art and (("%d layer(s), %s, %d pieces%s"):format(art.layers, art.size, #art.pieces,
			art.rect.inst == state.map and "" or ", on another map")) or "none",
		shows))
end

ns.slash.indoor = function()
	db.indoorDebug = not db.indoorDebug or nil
	lastNote = nil
	if outline then outline:SetShown(db.indoorDebug and shownMap ~= nil or false) end
	if db.indoorDebug and shownMap then Layout() end
	ns.Print(db.indoorDebug and "indoor maps: reporting each change (the art outlined in pink); /mm indoor to stop"
		or "indoor maps: quiet")
end
A.Debugging = function() return db and db.indoorDebug or false end

ns.On("Loaded", function(savedDB) db = savedDB end)
