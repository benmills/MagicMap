-- Minimap blips on the map: Model.Known("blips") (sensed now) and Known("remembered") (seen
-- before: from zoom 60, Blips.lua:641-650; laid out from a drift below it, shown from it as the zoom
-- moves: Engine.At's minimum zoom) as the spike's pins (Blips.lua:420-436, Layers.lua:340-400):
-- an icon, the game's tracking texture or a gathering atlas, at 14 px (an atlas the client lacks: a
-- dot of its colour); else a gold dot 6 px on a dark ring 9 px (StylePin's form (d), size 10). A
-- remembered one a sensed one stands for (its key) is drawn once; while the sensor runs, none within
-- its word around you (LIVE_YARDS: only what it sees now, Blips.lua:628-650). Laid out again when
-- either changes, or you cross a walk chunk while sensing.

local _, ns = ...
local UI, Model = ns.UI, ns.Model
local Engine = UI.Engine
local Get = Engine.Get

local ICON, DOT = 14, 10 -- px: an icon's; a dot's StylePin size (Blips.lua:434)
local GOLD, RING = { 1, 0.82, 0 }, { 0, 0, 0, 0.9 } -- Blips.lua:373, Layers.lua:396
local COLOR = { Professions_Tracking_Ore = { 0.8, 0.6, 0.4 }, Professions_Tracking_Herb = { 0.4, 0.9, 0.3 } } -- Blips.lua:424-426
local REMOTE_ZOOM = 60 -- px a tile: remembered ones from here (Blips.lua REMOTE_MIN_ZOOM)
local REACH = 220 / ns.Atlas.TILE_YARDS -- tiles: around you, the sensor's word (Blips.lua:480 LIVE_YARDS)
local CHUNKS = ns.Atlas.Walk.CHUNKS
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask" -- UI.lua:6

local function Maker(sub, file)
	return function(c)
		local t = c:CreateTexture(nil, "OVERLAY", nil, sub)
		t:SetSnapToPixelGrid(false)
		t:SetTexelSnappingBias(0)
		if file then t:SetTexture(file) end
		return t
	end
end
local MakePin, MakeRing, MakeDot = Maker(2), Maker(0, CIRCLE), Maker(1, CIRCLE)

local has = {} -- atlas name -> the client has it
local function Has(atlas)
	if has[atlas] == nil then has[atlas] = C_Texture.GetAtlasInfo(atlas) ~= nil end
	return has[atlas]
end

local function Pin(c, b, inst, c0, r0, c1, r1, minZoom)
	local p, icon = b.pos, b.icon
	if p.inst ~= inst or p.col < c0 or p.col > c1 or p.row < r0 or p.row > r1 then return end
	if icon and (icon.texture or Has(icon.atlas)) then
		local t = Get(c, "pin", "tex", MakePin)
		if icon.texture then
			t:SetTexture(icon.texture)
			t:SetTexCoord(0, 1, 0, 1)
		else
			t:SetAtlas(icon.atlas)
		end
		t:SetSize(ICON, ICON)
		Engine.At(c, t, "CENTER", p.col, p.row, 0, 0, minZoom)
		t.blip = b.key
		return
	end
	local col = icon and (icon.color or COLOR[icon.atlas]) or GOLD
	local ring, dot = Get(c, "ring", "tex", MakeRing), Get(c, "dot", "tex", MakeDot)
	ring:SetVertexColor(RING[1], RING[2], RING[3], RING[4])
	ring:SetSize(DOT * 0.6 + 3, DOT * 0.6 + 3)
	dot:SetVertexColor(col[1], col[2], col[3], 1)
	dot:SetSize(DOT * 0.6, DOT * 0.6)
	Engine.At(c, ring, "CENTER", p.col, p.row, 0, 0, minZoom)
	Engine.At(c, dot, "CENTER", p.col, p.row, 0, 0, minZoom)
	dot.blip = b.key
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
UI.Blips = Engine.Layer("blips", 6, function(c, inst, zoom, c0, r0, c1, r1)
	local live, seen = Model.Known("blips"), Model.Known("remembered")
	local remote = zoom * Engine.DRIFT >= REMOTE_ZOOM
	if not live[1] and not (seen[1] and remote) then return true end
	for k in pairs(carried) do carried[k] = nil end
	for _, b in ipairs(live) do
		carried[b.key] = true
		Pin(c, b, inst, c0, r0, c1, r1)
	end
	if not remote then return end
	local you = here and Model.you.inst == inst and Model.you
	for _, b in ipairs(seen) do
		local p = b.pos
		if not carried[b.key] and not (you and (p.col - you.col) ^ 2 + (p.row - you.row) ^ 2 < REACH * REACH) then
			Pin(c, b, inst, c0, r0, c1, r1, REMOTE_ZOOM)
		end
	end
end, function() return select(2, Model.Known("blips")) + select(2, Model.Known("remembered")) + Here() end, "move")
