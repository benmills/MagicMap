-- Places on the map (Layers.lua:459-540; Landmarks.lua:71-142): Known("places") as pins on the pin store
-- (ui/Pins.lua), each kind its gear row: flight points (their art, 18; else a dot of their faction's colour:
-- Layers.lua:459), dungeon entrances (20), graveyards (16, off until turned on) and the zones' points of
-- interest (18), each in the art Model hands on: the client's atlas (Blizzard's HD art), a point of
-- interest without one its POIIcons cell (the art the client draws it with), a dot of the kind's colour
-- where the client has neither (StylePin's (d)). And what the game shows near you now (Landmarks.lua:73-108): Known("vignettes"),
-- rares and treasures, 20. One pin layer for them all, as the spike's one canvas (Layers.lua:418-430): a
-- kind turned off is left out of its next layout. Tooltips: the name, then what it is (a flight point, a
-- graveyard, a dungeon or raid), its description (a dungeon's, a point of interest's), "Nearby now" (a vignette).
-- Their types (Settings > Pins): each kind's (Places), and the vignettes' (Rares & treasures); the art is the client's
-- for each place, so no icon to choose.

local _, ns = ...
local UI, Model = ns.UI, ns.Model
local Pins, Menus, Engine = UI.Pins, UI.Menus, UI.Engine
local LayerOn = Engine.LayerOn

local LEVEL = 11 -- with the rares (the spike's landmarks)
local GOLD = { 1, 0.82, 0 } -- a flight point's, neutral (Layers.lua:459)
local FACTION = { H = { 0.9, 0.2, 0.2 }, A = { 0.3, 0.5, 1 } } -- Layers.lua:459
local VIGNETTE = { size = 20, color = { 1, 0.4, 0.3 }, line = "Nearby now", sample = "vignetteloot" } -- Landmarks.lua:94-95

-- Each kind of place: its layer's key (the gear's, Layers.lua:48-53, Landmarks.lua:142), size and fallback
-- colour (Layers.lua:470-534, Landmarks.lua:135), its tooltip's line (nil: the place's own text); its type's name and
-- the art its row shows (the client names each place's); big: on the big map always, zoomed out too (ui/PinTypes.lua).
local KINDS = {
	flight = { key = "flight", size = 18, line = "Flight point", name = "Flight point", sample = "taxinode_neutral", big = "always" },
	dungeon = { key = "dungeons", size = 20, color = { 0.7, 0.4, 1 }, name = "Dungeon & raid", sample = "dungeon", big = "always" },
	graveyard = { key = "graveyards", size = 16, color = { 0.7, 0.7, 0.7 }, line = "Graveyard", name = "Graveyard",
		sample = "poi-graveyard-neutral" },
	poi = { key = "areaPOIs", size = 18, color = { 0.6, 0.85, 1 }, name = "Landmark", sample = "poi-town" },
}
local ORDER = { "flight", "dungeon", "graveyard", "poi" }
local TIPS = { flight = "A flight master you can fly to or from.", dungeon = "A dungeon's or raid's entrance.",
	graveyard = "Where your spirit goes when you release (its gear row is off until turned on).",
	poi = "A place the game marks in its zone: a town, a camp, a landmark." }
for _, place in ipairs(ORDER) do
	local k = KINDS[place]
	UI.PinTypes.Add({ id = place, family = "places", name = k.name, look = { size = k.size, icon = { atlas = k.sample, color = k.color } },
		groups = true, big = k.big, tip = TIPS[place] })
end
UI.PinTypes.Add({ id = "vignette", family = "rares", name = "Nearby now",
	look = { size = VIGNETTE.size, icon = { atlas = VIGNETTE.sample, color = VIGNETTE.color } }, groups = true,
	tip = "A rare, treasure or event the game shows near you now, in its own art." })

-- POIIcons: the art the client draws an area POI with when it names no atlas for it (its textureIndex):
-- 14 cells of 18 px a row on a 256x512 sheet, as the game's GetPOITextureCoords cuts them (export_icons.py).
local POI_SHEET, POI_W, POI_H, POI_COLUMNS, POI_CELL = 136441, 256, 512, 14, 18
local cells = {}
local function Cell(n) -- cell n's texture part (left, right, top, bottom)
	local c = cells[n]
	if not c then
		local x, y = n % POI_COLUMNS * POI_CELL, math.floor(n / POI_COLUMNS) * POI_CELL
		c = { x / POI_W, (x + POI_CELL) / POI_W, y / POI_H, (y + POI_CELL) / POI_H }
		cells[n] = c
	end
	return c
end

-- StylePin's look for e's art at size, color its dot's: one table a look (by art and colour). The art: its
-- atlas, which Pins uses if the client has it; else (icon.alt) a POI's cell, POIIcons; else a dot.
local looks = {}
local function Look(kind, size, e, color)
	local icon = e.icon or {}
	local name = icon.atlas or (icon.cell and "cell:" .. icon.cell) or ""
	local of = looks[kind]
	if not of then of = {}; looks[kind] = of end
	local by = of[size]
	if not by then by = {}; of[size] = by end
	local at = by[name]
	if not at then at = {}; by[name] = at end
	local look = at[color]
	if not look then
		local art = { atlas = icon.atlas, color = color }
		if icon.cell then art.alt = { texture = POI_SHEET, coords = Cell(icon.cell) } end
		look = { size = size, icon = art, type = kind }
		at[color] = look
	end
	return look
end

-- Which kinds are on, and the lists' revs: the layer's rev moves with any.
-- While Blizzard's Minimap is seen over the small map (obs.minimap.overlaid: at one of its zooms) its own flight
-- masters are there: ours step aside.
local on, last, rev = {}, {}, 0
local function Rev()
	local mm = Model.minimap
	local blips = mm and mm.overlaid or false
	local changed = on.blips ~= blips
	on.blips = blips
	for _, place in ipairs(ORDER) do
		local v = LayerOn(KINDS[place].key)
		if on[place] ~= v then on[place], changed = v, true end
	end
	local v = LayerOn("vignettes")
	local p, q = select(2, Model.Known("places")), select(2, Model.Known("vignettes"))
	if on.vignettes ~= v or last.places ~= p or last.vignettes ~= q then changed = true end
	on.vignettes, last.places, last.vignettes = v, p, q
	if changed then rev = rev + 1 end
	return rev
end

local function Lines(e)
	if e.kind == "vignettes" then return e.name, VIGNETTE.line end
	if e.place == "dungeon" then return e.name, e.icon.atlas == "raid" and "Raid" or "Dungeon", e.text end
	return e.name, KINDS[e.place].line or e.text
end

UI.Places = Pins.Layer("places", LEVEL, function(put)
	for _, e in ipairs(Model.Known("places")) do
		local k = KINDS[e.place]
		if on[e.place] and not (e.place == "flight" and on.blips) then put(e, Look(e.place, k.size, e, k.color or FACTION[e.faction] or GOLD)) end
	end
	if not on.vignettes then return end
	for _, e in ipairs(Model.Known("vignettes")) do put(e, Look("vignette", VIGNETTE.size, e, VIGNETTE.color)) end
end, Rev, { lines = Lines, cluster = true })

-- Their gear rows (Layers.lua:38-53; Landmarks.lua:110-111, 142-143).
Menus.Layer({ key = "flight", label = "Flight points", group = "places", tip = "Flight masters you can fly to or from." })
Menus.Layer({ key = "dungeons", label = "Dungeons & raids", group = "places", tip = "Dungeon and raid entrances." })
Menus.Layer({ key = "graveyards", label = "Graveyards", group = "places", default = false,
	tip = "Where your spirit goes when you release." })
Menus.Layer({ key = "areaPOIs", label = "Points of interest", group = "places", tip = "Places the game marks in each zone." })
-- (vignettes: the gear's "Rares & treasures" row turns them with the rares, ui/Menus.lua)
