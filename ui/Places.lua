-- Places on the map (Layers.lua:459-540; Landmarks.lua:71-142): Known("places") as pins on the pin store
-- (ui/Pins.lua), each kind its gear row: flight points (their art, 18; else a dot of their faction's colour:
-- Layers.lua:459), dungeon entrances (20), graveyards (16, off until turned on) and the zones' points of
-- interest (18), each in the art Model hands on (the game's), a dot of the kind's colour where the client
-- lacks it (StylePin's (d)). And what the game shows near you now (Landmarks.lua:73-108): Known("vignettes"),
-- rares and treasures, 20. One pin layer for them all, as the spike's one canvas (Layers.lua:418-430): a
-- kind turned off is left out of its next layout. Tooltips: the name, then what it is (a flight point, a
-- graveyard), its description (a dungeon, a point of interest), "Nearby now" (a vignette).

local _, ns = ...
local UI, Model = ns.UI, ns.Model
local Pins, Menus, Engine = UI.Pins, UI.Menus, UI.Engine
local LayerOn = Engine.LayerOn

local LEVEL = 11 -- with the rares (the spike's landmarks): under the blips (12)
local GOLD = { 1, 0.82, 0 } -- a flight point's, neutral (Layers.lua:459)
local FACTION = { H = { 0.9, 0.2, 0.2 }, A = { 0.3, 0.5, 1 } } -- Layers.lua:459
local VIGNETTE = { size = 20, color = { 1, 0.4, 0.3 }, line = "|cff808080Nearby now|r" } -- Landmarks.lua:94-95

-- Each kind of place: its layer's key (the gear's, Layers.lua:48-53, Landmarks.lua:142), size and fallback
-- colour (Layers.lua:470-534, Landmarks.lua:135), its tooltip's line (nil: the place's own text).
local KINDS = {
	flight = { key = "flight", size = 18, line = "Flight point" },
	dungeon = { key = "dungeons", size = 20, color = { 0.7, 0.4, 1 } },
	graveyard = { key = "graveyards", size = 16, color = { 0.7, 0.7, 0.7 }, line = "Graveyard" },
	poi = { key = "areaPOIs", size = 18, color = { 0.6, 0.85, 1 } },
}
local ORDER = { "flight", "dungeon", "graveyard", "poi" }

-- StylePin's look for e's art at size, color its dot's: one table a look (by art and colour).
local looks = {}
local function Look(size, e, color)
	local icon = e.icon
	local art = icon and (icon.atlas or icon.texture) or ""
	local by = looks[size]
	if not by then by = {}; looks[size] = by end
	local at = by[art]
	if not at then at = {}; by[art] = at end
	local look = at[color]
	if not look then
		look = { size = size, icon = { atlas = icon and icon.atlas, texture = icon and icon.texture, color = color } }
		at[color] = look
	end
	return look
end

-- Which kinds are on, and the lists' revs: the layer's rev moves with any.
local on, last, rev = {}, {}, 0
local function Rev()
	local changed = false
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
	return e.name, KINDS[e.place].line or e.text
end

UI.Places = Pins.Layer("places", LEVEL, function(put)
	for _, e in ipairs(Model.Known("places")) do
		local k = KINDS[e.place]
		if on[e.place] then put(e, Look(k.size, e, k.color or FACTION[e.faction] or GOLD)) end
	end
	if not on.vignettes then return end
	for _, e in ipairs(Model.Known("vignettes")) do put(e, Look(VIGNETTE.size, e, VIGNETTE.color)) end
end, Rev, { lines = Lines, cluster = true })

-- Their gear rows (Layers.lua:38-53; Landmarks.lua:110-111, 142-143).
Menus.Layer({ key = "flight", label = "Flight points", group = "places", tip = "Flight masters you can fly to or from." })
Menus.Layer({ key = "dungeons", label = "Dungeon entrances", group = "places", tip = "Dungeon and raid entrances." })
Menus.Layer({ key = "graveyards", label = "Graveyards", group = "places", default = false,
	tip = "Where your spirit goes when you release." })
Menus.Layer({ key = "areaPOIs", label = "Points of interest", group = "places", tip = "Places the game marks in each zone." })
Menus.Layer({ key = "vignettes", label = "Live rares & treasures", group = "people",
	tip = "Rares, treasures and events the game is showing near you right now." })
