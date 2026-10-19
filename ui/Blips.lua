-- Minimap blips on the map: Model.Known("blips") (sensed now) and Known("remembered") (seen
-- before: from zoom 60, Blips.lua:641-650; laid out from a drift below it but zooming out, Engine.From,
-- shown from it as the zoom moves: Engine.At's minimum zoom) as the spike's pins (Blips.lua:423-437,
-- 641-661), on the pin store (ui/Pins.lua): an icon, the game's tracking texture or a gathering atlas,
-- at 14 px (an atlas the client lacks: a dot of its colour, StylePin's form (d)); else a gold dot (d) at
-- 10. A remembered one a sensed one stands for (its key) is drawn once; while the sensor runs, none
-- within its word around you (LIVE_YARDS: only what it sees now, Blips.lua:628-650). Laid out again
-- when either changes, or you cross a walk chunk while sensing. Tooltip: its name, then what it is (a
-- gathering node's profession, Blips.lua:427-429), and a remembered one's "Not in sight".

local _, ns = ...
local UI, Model = ns.UI, ns.Model

local ICON, DOT = 14, 10 -- px: an icon's; the gold dot's (Blips.lua:436)
local GOLD = { 1, 0.82, 0 } -- Blips.lua:373
-- A gathering node's colour (its dot, an atlas the client lacks) and its line (Blips.lua:427-429).
local COLOR = { Professions_Tracking_Ore = { 0.8, 0.6, 0.4 }, Professions_Tracking_Herb = { 0.4, 0.9, 0.3 } }
local LINE = { Professions_Tracking_Ore = "Mining", Professions_Tracking_Herb = "Herbalism" }
local AWAY = "|cff808080Not in sight|r" -- Blips.lua:642
local REMOTE_ZOOM = 60 -- px a tile: remembered ones from here (Blips.lua REMOTE_MIN_ZOOM)
local REACH = 220 / ns.Atlas.TILE_YARDS -- tiles: around you, the sensor's word (Blips.lua:480 LIVE_YARDS)
local CHUNKS = ns.Atlas.Walk.CHUNKS

-- StylePin's looks, one an icon (Blips.lua:423-437).
local DOT_LOOK = { size = DOT, icon = { color = GOLD } }
local looks = {}
local function Look(icon)
	if not icon then return DOT_LOOK end
	local k = icon.texture or icon.atlas
	local look = looks[k]
	if not look then
		look = { size = ICON,
			icon = { texture = icon.texture, atlas = icon.atlas, color = icon.color or COLOR[icon.atlas] } }
		looks[k] = look
	end
	return look
end

-- A remembered one's "Not in sight" follows its line, as the spike read { sub, "Not in sight" } with
-- ipairs: with no line, neither (Blips.lua:641-642, Layers.lua:298).
local function Lines(b)
	local line = b.text or b.icon and LINE[b.icon.atlas]
	if b.live then return b.name, line end
	return b.name, line, line and AWAY
end

-- You while the sensor runs, by walk chunk (false: not sensing), and a rev that moves with it.
local here, hereRev = false, 0
local function Here()
	local m, you = Model.minimap, Model.you
	local key = m and m.sensing and you.col and not you.stale and math.floor(you.col * CHUNKS) * 4096 + math.floor(you.row * CHUNKS)
		or false
	if key ~= here then here, hereRev = key, hereRev + 1 end
	return hereRev
end

local carried = {} -- keys of remembered ones a sensed one stands for
UI.Blips = UI.Pins.Layer("blips", 12, function(put, inst, _, want)
	local live, seen = Model.Known("blips"), Model.Known("remembered")
	for k in pairs(carried) do carried[k] = nil end
	for _, b in ipairs(live) do
		carried[b.key] = true
		put(b, Look(b.icon))
	end
	if not seen[1] or not want(REMOTE_ZOOM) then return end
	local you = here and Model.you.inst == inst and Model.you
	for _, b in ipairs(seen) do
		local p = b.pos
		if not carried[b.key] and not (you and (p.col - you.col) ^ 2 + (p.row - you.row) ^ 2 < REACH * REACH) then
			put(b, Look(b.icon), REMOTE_ZOOM)
		end
	end
end, function() return select(2, Model.Known("blips")) + select(2, Model.Known("remembered")) + Here() end,
	{ lines = Lines })
