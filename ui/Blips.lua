-- Minimap blips on the map: Model.Known("blips") (sensed now) and Known("remembered") (seen
-- before: from zoom 60, Blips.lua:641-650) as the spike's pins (Blips.lua:420-436, Layers.lua:340-400):
-- an icon, the game's tracking texture or a gathering atlas, at 14 px (an atlas the client lacks: a
-- dot of its colour); else a gold dot 6 px on a dark ring 9 px (StylePin's form (d), size 10). A
-- remembered one a sensed one stands for (its key) is drawn once. Laid out again when either changes.

local _, ns = ...
local UI, Model = ns.UI, ns.Model
local Engine = UI.Engine
local Get = Engine.Get

local ICON, DOT = 14, 10 -- px: an icon's; a dot's StylePin size (Blips.lua:434)
local GOLD, RING = { 1, 0.82, 0 }, { 0, 0, 0, 0.9 } -- Blips.lua:373, Layers.lua:396
local COLOR = { Professions_Tracking_Ore = { 0.8, 0.6, 0.4 }, Professions_Tracking_Herb = { 0.4, 0.9, 0.3 } } -- Blips.lua:424-426
local REMOTE_ZOOM = 60 -- px a tile: remembered ones from here (Blips.lua REMOTE_MIN_ZOOM)
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

local function Pin(c, b, inst, c0, r0, c1, r1)
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
		Engine.At(c, t, "CENTER", p.col, p.row)
		t.blip = b.key
		return
	end
	local col = icon and (icon.color or COLOR[icon.atlas]) or GOLD
	local ring, dot = Get(c, "ring", "tex", MakeRing), Get(c, "dot", "tex", MakeDot)
	ring:SetVertexColor(RING[1], RING[2], RING[3], RING[4])
	ring:SetSize(DOT * 0.6 + 3, DOT * 0.6 + 3)
	dot:SetVertexColor(col[1], col[2], col[3], 1)
	dot:SetSize(DOT * 0.6, DOT * 0.6)
	Engine.At(c, ring, "CENTER", p.col, p.row)
	Engine.At(c, dot, "CENTER", p.col, p.row)
	dot.blip = b.key
end

local carried = {} -- keys of remembered ones a sensed one stands for
UI.Blips = Engine.Layer("blips", 6, function(c, inst, zoom, c0, r0, c1, r1)
	local live, seen = Model.Known("blips"), Model.Known("remembered")
	if not live[1] and (not seen[1] or zoom < REMOTE_ZOOM) then return true end
	for k in pairs(carried) do carried[k] = nil end
	for _, b in ipairs(live) do
		carried[b.key] = true
		Pin(c, b, inst, c0, r0, c1, r1)
	end
	if zoom < REMOTE_ZOOM then return end
	for _, b in ipairs(seen) do
		if not carried[b.key] then Pin(c, b, inst, c0, r0, c1, r1) end
	end
end, function() return select(2, Model.Known("blips")) + select(2, Model.Known("remembered")) end, "move")
