-- obs.indoorArt (types/observation.lua MM.ObsArt), on change: the world map's art for the map you're on
-- (obs.you.uiMap), as Blizzard's HybridMinimap draws it (IndoorArt.lua:38-74): the first of its art
-- layers, its textures as pieces in tile space over the map's rect, the client's (Core.lua:838-857:
-- Atlas keeps no dungeon floors or micro maps). Only the art of the place itself: a dungeon floor, a
-- micro map, or a map no wider than MAX_ART_YARDS (a city's); in a hut the map you're on is the whole
-- zone, its art the zone's painting: false. Each map's read once. outline: /mm indoor is on
-- (game/Renderer.lua): UI outlines the art. UI picks View.renderer with obs.minimap.indoors.

local _, ns = ...
local Atlas, Game = ns.Atlas, ns.Game

local MAX_ART_YARDS = 1600 -- IndoorArt.lua:22
local DUNGEON = 4 -- Enum.UIMapType: a dungeon floor, a micro map, an orphan's art is the place's own (IndoorArt.lua:46)

local cache, facts = {}, {} -- uiMap -> pieces | false; uiMap -> { layers, size } (the note's)
local shown, map, outline = false, nil, nil

-- The map's rect in tile space, the client's (Core.lua:838-857): Atlas keeps no dungeon floors or micro maps.
function Game.MapRect(uiMap)
	local inst, tl = C_Map.GetWorldPosFromMapPos(uiMap, CreateVector2D(0, 0))
	local inst2, br = C_Map.GetWorldPosFromMapPos(uiMap, CreateVector2D(1, 1))
	if not (tl and br and inst == inst2) then return nil end
	local c0, r0 = Atlas.WorldToTile(tl:GetXY())
	local c1, r1 = Atlas.WorldToTile(br:GetXY())
	if c1 > c0 and r1 > r0 then return { inst = inst, c0 = c0, r0 = r0, c1 = c1, r1 = r1 } end
end

local function Art(uiMap)
	local art = cache[uiMap]
	if art ~= nil then return art end
	art = false
	local rect, info = Game.MapRect(uiMap), C_Map.GetMapInfo(uiMap)
	if rect and info.mapType < DUNGEON and (rect.c1 - rect.c0) * Atlas.TILE_YARDS > MAX_ART_YARDS then rect = nil end
	local layers = rect and C_Map.GetMapArtLayers(uiMap)
	local layer = layers and layers[1]
	local files = layer and C_Map.GetMapArtLayerTextures(uiMap, 1)
	if files and #files > 0 and layer.layerWidth > 0 and layer.layerHeight > 0 and layer.tileWidth > 0 and layer.tileHeight > 0 then
		local W, H, tw, th = layer.layerWidth, layer.layerHeight, layer.tileWidth, layer.tileHeight
		local cols = math.ceil(W / tw) -- /: never 0 (sizes > 0, above)
		local cw, rh = rect.c1 - rect.c0, rect.r1 - rect.r0
		art = {}
		for i, file in ipairs(files) do
			local c, r = (i - 1) % cols, math.floor((i - 1) / cols) -- /: never 0 (cols >= 1)
			local x0, y0 = c * tw / W, r * th / H -- /: never 0 (sizes > 0)
			local x1, y1 = math.min((c + 1) * tw, W) / W, math.min((r + 1) * th, H) / H -- /: never 0 (sizes > 0)
			if x0 < 1 and y0 < 1 then
				art[#art + 1] = { file = file, rect = { inst = rect.inst, c0 = rect.c0 + cw * x0, r0 = rect.r0 + rh * y0,
					c1 = rect.c0 + cw * x1, r1 = rect.r0 + rh * y1 }, u = (x1 - x0) * W / tw, v = (y1 - y0) * H / th } -- /: never 0 (sizes > 0)
			end
		end
		facts[uiMap] = { layers = #layers, size = W .. "x" .. H }
	end
	cache[uiMap] = art
	return art
end

-- The note's (game/Renderer.lua): the map's art layers, and the first's size.
function Game.ArtFacts(uiMap) return facts[uiMap] end

Game.Part("indoorArt", function(obs)
	local uiMap, debug = obs.you.uiMap, Game.saved.indoorDebug or nil
	if uiMap == map and debug == outline then return shown end
	map, outline = uiMap, debug
	local pieces = uiMap and Art(uiMap)
	shown = pieces and { uiMap = uiMap, pieces = pieces, outline = debug } or false
	return shown
end)
