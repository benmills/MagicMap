-- Place tints: a colour laid over the whole map while it shows a capital (the one whose map rect holds the view's
-- centre, on the camera's map: on the small map following you, the one you're in), or else a zone (the one whose
-- ground is under the view's centre). Each place has its own. The capitals' are on (Settings > Advanced > City
-- tints: each a switch with, under it, its Colour, Opacity, Blend and Brightness); the zones' are off until turned
-- on (Zone tints: a switch a continent, its zones under it, closed, each as a city's row). Declared below
-- (ui/Feel.lua). Over the ground and the buildings, under the quest areas, the path,
-- the names and the pins: a frame at the view's level + 6 (the interiors' canvases are at + 5: ui/Engine.lua makes
-- a layer's canvas a level over its frame; the quest areas' pieces at + 6 to + 8 may draw either side of it, the
-- followed and hovered ones over). Crossing into or out of a place, or a setting changed, it eases over FADE_S. Its
-- frame is made the first time a tint shows; the view is checked five times a second (the place looked up once its
-- centre has moved MOVED of a tile), and only an easing tint runs each frame (else nothing a frame).
-- Blend: Wash lays the colour over (BLEND at the opacity); Multiply shades the map toward it, darks kept (MOD, the
-- colour taken from white by the opacity); Glow lights it with the colour (ADD, premultiplied). Brightness: a second
-- texture over it, black BLEND below 0, white ADD above.

local _, ns = ...
local UI, Atlas = ns.UI, ns.Atlas
local Runtime, Window, Camera = ns.Runtime, UI.Window, UI.Camera

local LEVEL = 6 -- over the interiors' canvases (+ 5), under the path (+ 8) and the names (+ 9, + 10)
local FADE_S = 0.4
local WATCH_S = 0.2 -- how often the view is checked for another place
local MOVED = 1 / 64 -- of a tile (8 yd): the view's centre this far from where the place was last looked up, again -- /: never 0 (a constant)
-- uiMap, key, then the look it starts on: colour, opacity, blend, brightness. Each a Multiply, so the art's darks
-- stay: Undercity cold and dim, Ironforge forge-lit under its mountain, Orgrimmar a warm dust, Darnassus a soft
-- violet dusk, Stormwind and Thunder Bluff in daylight, a light cool stone and a light gold.
local CITIES = {
	{ 1453, "stormwind", "Blue", 0.15, "multiply", 0 }, { 1455, "ironforge", "Amber", 0.3, "multiply", -0.15 },
	{ 1457, "darnassus", "Violet", 0.25, "multiply", -0.1 }, { 1454, "orgrimmar", "Amber", 0.3, "multiply", -0.05 },
	{ 1456, "thunderBluff", "Gold", 0.2, "multiply", 0 }, { 1458, "undercity", "Blue", 0.3, "multiply", -0.3 },
}
local COLORS = {
	{ "Green", { 0.45, 0.85, 0.3 } }, { "Red", { 0.9, 0.3, 0.15 } }, { "Blue", { 0.3, 0.5, 1 } },
	{ "Amber", { 1, 0.6, 0.2 } }, { "Violet", { 0.6, 0.45, 1 } }, { "Gold", { 1, 0.82, 0.3 } },
	{ "Dusk", { 0.25, 0.3, 0.5 } },
}
local BLENDS = { { "Wash", "wash" }, { "Multiply", "multiply" }, { "Glow", "glow" } }
-- The zones, a continent a list (its map's instance, key, name): every zone of it but the capitals, each a row as
-- CITIES' (its key its uiMap, a number: never renamed), starting on LOOKS' by name, or else ZONE's.
local CONTINENTS = { { 0, "eastern", "Eastern Kingdoms" }, { 1, "kalimdor", "Kalimdor" } }
local ZONE = { "Gold", 0.15, "multiply", 0 }
local LOOKS = {
	["Duskwood"] = { "Dusk", 0.35, "multiply", -0.15 }, ["Deadwind Pass"] = { "Dusk", 0.3, "multiply", -0.1 },
	["Tirisfal Glades"] = { "Dusk", 0.2, "multiply", -0.05 }, ["Silverpine Forest"] = { "Dusk", 0.25, "multiply", -0.1 },
	["Western Plaguelands"] = { "Amber", 0.25, "multiply", -0.1 }, ["Eastern Plaguelands"] = { "Amber", 0.3, "multiply", -0.15 },
	["Burning Steppes"] = { "Red", 0.25, "multiply", -0.1 }, ["Searing Gorge"] = { "Red", 0.2, "multiply", -0.05 },
	["Blasted Lands"] = { "Red", 0.2, "multiply", 0 }, ["Badlands"] = { "Amber", 0.15, "multiply", 0 },
	["Swamp of Sorrows"] = { "Green", 0.2, "multiply", -0.1 }, ["Dun Morogh"] = { "Blue", 0.1, "multiply", 0 },
	["Felwood"] = { "Green", 0.25, "multiply", -0.1 }, ["Dustwallow Marsh"] = { "Green", 0.15, "multiply", -0.1 },
	["Un'Goro Crater"] = { "Green", 0.15, "multiply", 0 }, ["Winterspring"] = { "Blue", 0.15, "multiply", 0 },
	["Moonglade"] = { "Blue", 0.15, "multiply", 0 }, ["Darkshore"] = { "Dusk", 0.2, "multiply", -0.05 },
	["Ashenvale"] = { "Violet", 0.15, "multiply", 0 }, ["Teldrassil"] = { "Violet", 0.15, "multiply", 0 },
	["Desolace"] = { "Dusk", 0.2, "multiply", 0 }, ["Durotar"] = { "Amber", 0.15, "multiply", 0 },
	["Silithus"] = { "Amber", 0.2, "multiply", 0 }, ["Thousand Needles"] = { "Amber", 0.15, "multiply", 0 },
	["Tanaris"] = { "Gold", 0.2, "multiply", 0 },
}
local ZONES = {} -- [inst][the zone's areaID] = its row
local CONT = {} -- [inst] = whether its zones' tints show (the continent's switch)

-- The frame and its two textures, made the first time a tint shows (a frame on the view is laid out with it, so
-- none while no city has one: the default).
local frame, color, bright
local function Tex(sub)
	local t = UI.Under.Mask(frame:CreateTexture(nil, "ARTWORK", nil, sub))
	t:SetSnapToPixelGrid(false)
	t:SetTexelSnappingBias(0)
	t:SetAllPoints(Window.view)
	t:Hide()
	return t
end
local function Make()
	frame = CreateFrame("Frame", nil, Window.view)
	frame:SetAllPoints()
	frame:SetFrameLevel(Window.view:GetFrameLevel() + LEVEL)
	color, bright = Tex(0), Tex(1)
	UI.CityTint.color, UI.CityTint.bright = color, bright
end

local Tints = { CITIES = CITIES }
UI.CityTint = Tints

-- Each place's settings as they were last applied: cfg[key] = { on, color, opacity, blend, bright } (Feel's apply).
local cfg = {}
local function Cfg(c) cfg[c[2]] = { on = false, color = c[3], opacity = c[4], blend = c[5], bright = c[6] } end
for _, c in ipairs(CITIES) do Cfg(c) end

-- The place the view shows whose tint is on (its row): the capital, else the zone under the centre; or nil.
local function Shown()
	local inst, cam = Camera.inst, Camera.cam
	for _, c in ipairs(CITIES) do
		local r = Atlas.MapRect(c[1])
		if r and r.inst == inst and cam.cx >= r.col0 and cam.cx <= r.col1 and cam.cy >= r.row0 and cam.cy <= r.row1 then
			if cfg[c[2]].on then return c end
			break
		end
	end
	local zones = CONT[inst] and ZONES[inst]
	local id = zones and Atlas.AreaAt(inst, cam.cx, cam.cy)
	local area = id and Atlas.Area(id)
	local z = area and zones[area.zone]
	if z and cfg[z[2]].on then return z end
end

local city, fade = nil, 0 -- the city drawn (kept while fading out), how far in (0..1)
local dirty = true -- a setting changed since the textures were set
local setCity, setFade -- what they were set for
local function Set(c, f)
	if not dirty and c == setCity and f == setFade then return end
	dirty, setCity, setFade = false, c, f
	local k = c and cfg[c[2]]
	local on = k and f > 0
	if not frame then
		if not on then return end
		Make()
	end
	color:SetShown(on and k.opacity > 0 or false)
	bright:SetShown(on and k.bright ~= 0 or false)
	if not on then return end
	local _, rgb = UI.Feel.RGB(COLORS, k.color, c[3])
	local a, b = k.opacity * f, k.bright * f
	if k.blend == "multiply" then
		color:SetBlendMode("MOD")
		color:SetColorTexture(1 - (1 - rgb[1]) * a, 1 - (1 - rgb[2]) * a, 1 - (1 - rgb[3]) * a, 1)
	elseif k.blend == "glow" then
		color:SetBlendMode("ADD")
		color:SetColorTexture(rgb[1] * a, rgb[2] * a, rgb[3] * a, 1)
	else
		color:SetBlendMode("BLEND")
		color:SetColorTexture(rgb[1], rgb[2], rgb[3], a)
	end
	if b < 0 then
		bright:SetBlendMode("BLEND")
		bright:SetColorTexture(0, 0, 0, -b)
	elseif b > 0 then
		bright:SetBlendMode("ADD")
		bright:SetColorTexture(b, b, b, 1)
	end
end

-- The place in view is looked up WATCH_S apart while the map shows and its centre moves (a timer: nothing a frame); a change of it, or of a setting, shows the fader, whose OnUpdate eases the drawn tint out and the new
-- one in (another's, or none: the drawn one eased out first), then hides it again.
local anyOn = 0 -- how many places' tints are on: none, nothing looked up
local want, atInst, atX, atY -- the place in view, as last looked up with the view's centre there
local fader = CreateFrame("Frame")
fader:Hide()
fader:SetScript("OnUpdate", Runtime.Wrap("map: city tint", function(_, elapsed)
	local step = (elapsed or 0) / FADE_S -- /: never 0 (a constant)
	if want == city then
		fade = city and math.min(1, fade + step) or 0
	else
		fade = math.max(0, fade - step)
		if fade == 0 then city = want end
	end
	Set(city, fade)
	if want == city and (fade == 1 or not city) then fader:Hide() end
end))
local function Watch()
	if anyOn == 0 and not city or not Window.frame:IsVisible() then return end
	local cam = Camera.cam
	if dirty or Camera.inst ~= atInst or math.abs(cam.cx - atX) > MOVED or math.abs(cam.cy - atY) > MOVED then
		atInst, atX, atY = Camera.inst, cam.cx, cam.cy
		want = Shown()
		if want ~= city or dirty then fader:Show() end
	end
end
Runtime.Every(WATCH_S, "map: city tint watch", Watch)

function Tints.Shown() return frame ~= nil and (color:IsShown() or bright:IsShown()) end -- (the tests: Tints.color, .bright)

-- A setting's apply: the place's field, set again next frame.
local function Apply(c, field)
	return function(v)
		local k = cfg[c[2]]
		if field == "on" then
			v = v == true
			if v ~= k.on then anyOn = anyOn + (v and 1 or -1) end
		end
		k[field] = v
		dirty = true
		Watch()
	end
end
-- A place's rows: its switch (on by default or not; under: the row it stands under) and its four settings under it.
local function Rows(rows, c, key, name, on, under)
	local first = #rows + 1
	rows[#rows + 1] = { key = key, kind = "toggle", label = name, default = on, apply = Apply(c, "on"),
		under = under, when = under, tip = "A colour over the whole map while it shows " .. name .. "." }
	rows[#rows + 1] = { key = key .. "Color", kind = "color", label = "Colour", colors = COLORS, default = c[3],
		under = key, when = key, apply = Apply(c, "color"), tip = "The tint's colour." }
	rows[#rows + 1] = { key = key .. "Opacity", kind = "slider", label = "Opacity", min = 0.05, max = 1, step = 0.05,
		pct = true, default = c[4], under = key, when = key, apply = Apply(c, "opacity"), tip = "How strong the tint is." }
	rows[#rows + 1] = { key = key .. "Blend", kind = "select", label = "Blend", options = BLENDS, default = c[5],
		under = key, when = key, apply = Apply(c, "blend"),
		tip = "Wash lays the colour over the map; Multiply shades the map toward it, keeping its darks; Glow lights the map with it." }
	rows[#rows + 1] = { key = key .. "Bright", kind = "slider", label = "Brightness", min = -0.5, max = 0.5, step = 0.05,
		pct = true, default = c[6], under = key, when = key, apply = Apply(c, "bright"),
		tip = "Darker or lighter, over the tint." }
	for i = first, #rows do rows[i].lazy = under ~= nil end -- (a zone's rows: made once its continent is opened)
end
local rows = {}
for _, c in ipairs(CITIES) do
	Rows(rows, c, "cityTint." .. c[2], Atlas.UiMap(c[1]) and Atlas.UiMap(c[1]).name or c[2], true)
end
UI.Feel.Add("advanced", "City tints", rows)

rows = {}
for _, k in ipairs(CONTINENTS) do
	local inst, key = k[1], "zoneTint." .. k[2]
	local zones = {}
	ZONES[inst], CONT[inst] = zones, false
	rows[#rows + 1] = { key = key, kind = "toggle", label = k[3], default = true,
		apply = function(v)
			CONT[inst] = v == true
			dirty = true
			Watch()
		end,
		tip = "The tints of " .. k[3] .. "'s zones: open it for the list, each zone off until turned on. Off, none of them show." }
	for _, z in ipairs(Atlas.Zones(inst)) do
		local m, city = Atlas.UiMap(z.uiMapID), false
		for _, c in ipairs(CITIES) do city = city or c[1] == z.uiMapID end
		if not city and m.areaID then
			local look = LOOKS[z.name] or ZONE
			local c = { z.uiMapID, "zone" .. z.uiMapID, look[1], look[2], look[3], look[4] }
			Cfg(c)
			zones[m.areaID] = c
			Rows(rows, c, "zoneTint." .. z.uiMapID, z.name, false, key)
		end
	end
end
UI.Feel.Add("advanced", "Zone tints", rows)
