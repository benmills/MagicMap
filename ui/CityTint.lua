-- City tints: a colour laid over the whole map while it shows a capital (the capital whose map rect holds the view's
-- centre, on the camera's map: on the small map following you, the one you're in). Each capital has its own,
-- off until turned on: Settings > Advanced > City tints, each city a switch with, under it, its Colour, Opacity, Blend
-- and Brightness (declared below: ui/Feel.lua). Over the ground and the buildings, under the quest areas, the path,
-- the names and the pins: a frame at the view's level + 6 (the interiors' canvases are at + 5: ui/Engine.lua makes
-- a layer's canvas a level over its frame; the quest areas' pieces at + 6 to + 8 may draw either side of it, the
-- followed and hovered ones over). Crossing into or out of a city, or a setting changed, it eases over FADE_S. Its
-- frame and step are made the first time a city's tint is turned on: until then the map pays nothing for it.
-- Blend: Wash lays the colour over (BLEND at the opacity); Multiply shades the map toward it, darks kept (MOD, the
-- colour taken from white by the opacity); Glow lights it with the colour (ADD, premultiplied). Brightness: a second
-- texture over it, black BLEND below 0, white ADD above.

local _, ns = ...
local UI, Atlas = ns.UI, ns.Atlas
local Runtime, Window, Camera = ns.Runtime, UI.Window, UI.Camera

local LEVEL = 6 -- over the interiors' canvases (+ 5), under the path (+ 8) and the names (+ 9, + 10)
local FADE_S = 0.4
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

-- The frame and its two textures, made the first time a tint shows (a frame on the view is laid out with it, so
-- none while no city has one: the default).
local frame, color, bright
local function Tex(sub)
	local t = UI.Under.Mask(frame:CreateTexture(nil, "ARTWORK", nil, sub))
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

-- The capital the view shows (its CITIES row), or nil.
local function Shown()
	local inst, cam = Camera.inst, Camera.cam
	for _, c in ipairs(CITIES) do
		local r = Atlas.MapRect(c[1])
		if r and r.inst == inst and cam.cx >= r.col0 and cam.cx <= r.col1 and cam.cy >= r.row0 and cam.cy <= r.row1 then return c end
	end
end

-- Each city's settings as they were last applied: cfg[key] = { on, color, opacity, blend, bright } (Feel's apply).
local cfg = {}
for _, c in ipairs(CITIES) do cfg[c[2]] = { on = false, color = c[3], opacity = c[4], blend = c[5], bright = c[6] } end

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

-- Each frame the map shows: the city in view, its tint eased in (another's, or none: the drawn one eased out first).
-- (Registered the first time a city's tint is turned on: until then no step, as no frame.)
local anyOn = 0 -- how many cities' tints are on: none, the step does nothing once faded
local function Step(elapsed)
	if anyOn == 0 and fade == 0 then return end
	local want = Shown()
	if want and not cfg[want[2]].on then want = nil end
	local step = (elapsed or 0) / FADE_S -- /: never 0 (a constant)
	if want == city then
		fade = city and math.min(1, fade + step) or 0
	else
		fade = math.max(0, fade - step)
		if fade == 0 then city = want end
	end
	Set(city, fade)
end
local stepping = false

function Tints.Shown() return frame ~= nil and (color:IsShown() or bright:IsShown()) end -- (the tests: Tints.color, .bright)

-- A setting's apply: the city's field, set again next frame.
local function Apply(c, field)
	return function(v)
		local k = cfg[c[2]]
		if field == "on" then
			v = v == true
			if v ~= k.on then anyOn = anyOn + (v and 1 or -1) end
		end
		if anyOn > 0 and not stepping then
			stepping = true
			Runtime.Step("ui", "map: city tint", Step, { shownOnly = Window.frame })
		end
		k[field] = v
		dirty = true
	end
end
local rows = {}
for _, c in ipairs(CITIES) do
	local key = "cityTint." .. c[2]
	local name = Atlas.UiMap(c[1]) and Atlas.UiMap(c[1]).name or c[2]
	rows[#rows + 1] = { key = key, kind = "toggle", label = name, default = false, apply = Apply(c, "on"),
		tip = "A colour over the whole map while it shows " .. name .. "." }
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
end
UI.Feel.Add("advanced", "City tints", rows)
