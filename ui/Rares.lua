-- Rare and rare-elite NPCs' spawn points on the map: Model.Known("rares") as pins on the pin store
-- (ui/Pins.lua), the spike's rare icon at 15 (Landmarks.lua:15, 59-64), from zoom 60 in (further out,
-- none: a continent's ~700 cost a 13 ms swap): laid out from a drift below it but zooming out
-- (Engine.From), shown from it as the zoom moves (Engine.At's minimum zoom). Laid out again when
-- Model's list changes. Tooltip: its name, Model's line ("Rare") and when you saw it, "Seen here <Mon
-- DD>". Toggled like any layer (/mm layer rares).

local _, ns = ...
local UI, Model = ns.UI, ns.Model

local MIN_ZOOM = 60 -- px a tile (Landmarks.lua:15 RARE_MIN_ZOOM)
local LOOK = { size = 15, icon = { texture = 137008 } } -- Landmarks.lua:15, 60-63 (RARE_ICON)

UI.Rares = UI.Pins.Layer("rares", 11, function(put, _, _, want)
	local list = Model.Known("rares")
	if not list[1] or not want(MIN_ZOOM) then return end -- Layers.lua:409
	for _, b in ipairs(list) do put(b, LOOK, MIN_ZOOM) end
end, function() return select(2, Model.Known("rares")) end,
	{ lines = function(e) return e.name, e.text, "|cff808080Seen here " .. date("%b %d", e.t) .. "|r" end }) -- Landmarks.lua:61
