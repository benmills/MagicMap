-- The pin inventory (#16): every kind of pin the map draws, each declared by the file that draws it, next to the look
-- it draws (Types.Add: ui/Quests.lua's, ui/Rares.lua's, ui/Places.lua's from its
-- KINDS, ui/You.lua's corpse and waypoint, ui/Group.lua's party dot, ui/Sockets.lua's other addons'), and Settings >
-- Pins built from them, so a new type is on the page by being declared. A type is { id, family, name, look (its
-- look, StylePin's: the page draws it so), icons? (Blizzard's art for it, { label, value } each, the first today's: a
-- value "A:<atlas>", a FileDataID or a path), groups? (it may stand in a pill: ui/Cluster.lua), size = false (no size:
-- other addons' pins, never scaled), big? ("always": its big-map rule, not its family's), tip }. Families, in the
-- page's order: Quests, Rares & treasures, Party, Places, Addons, Other.
-- Three levels: All pins (Show pins, Pin size: "icons.scale", the Icons page's, Pin opacity), a family (its row: show,
-- and under it its size and opacity), a type (its row: its art drawn as on the map and show; under it its size,
-- opacity, icon and grouping). A type's value, until set, is its family's, and a family's All's (Feel's inherited
-- default; Party's size its own, 100%: its dots never followed the icon size); each row's undo hands it back. Each
-- family's and type's settings stand under its row, shown once it's opened (its plus).
-- What's drawn reads Types.Of(id) (a look's type: look.type): { show, size (a factor on its look's px), alpha, icon (the
-- art chosen, a look's icon: nil for today's), group }, resolved for every type at once when Feel.rev moves (not a pin
-- at a time), and Types.Rev(), which moves when any type's resolved style does: each pin layer's rev carries it
-- (ui/Pins.lua), as do the group dots', the sockets' and the grouping's.
-- On the big map (#20) a type shows always, or only zoomed in: from the zoom at which the view spans "Zoomed in
-- from" yards across or less (Types.Min: a pin layer's minimum zoom for it, ui/Pins.lua's put and ui/Cluster.lua's,
-- faded in over Engine's FADE_IN past it); never held back on the minimap. Its rule ("big": "always" or "zoomed")
-- inherits All's (zoomed), a family's, a type's like its size; by default quests, your party, flight points,
-- dungeons and raids, your corpse and waypoint always, the rest zoomed in. The threshold moves Types.Rev (the big map
-- opened or closed, the view resized, the setting), so the pins are laid out again for it. Other addons' pins draw
-- by their own addons' rules: no rule for them.

local _, ns = ...
local UI = ns.UI
local Feel = UI.Feel

local Types = {}
UI.PinTypes = Types

local ALL = 1.2 -- every pin's size, a factor: the Icons page's "Icon size" (its key kept: icons.scale)
local SIZE = { min = 0.5, max = 2, step = 0.1 }
local ALPHA = { min = 0.2, max = 1, step = 0.05 }
local ART = 16 -- px: a row's art
local ZOOM_IN = 3000 -- yards across the big map's view: "zoomed in" types show from there in (a whole zone is 3000-5000)
local STEP = 1.1 -- the threshold's zoom, on a grid of this ratio: a resize moves it (a layout) only a step at a time
local LOG_STEP = math.log(STEP)
local BIG = { { "Always", "always" }, { "Zoomed in", "zoomed" } }

local FAMILIES = {
	{ key = "quests", name = "Quests", big = "always" }, { key = "rares", name = "Rares & treasures" },
	{ key = "party", name = "Party", size = 1, big = "always" }, -- (its dots kept their size whatever the icon size: 100% of their own)
	{ key = "places", name = "Places" }, { key = "addons", name = "Addons", noSize = true, noBig = true },
	{ key = "other", name = "Other" },
}
local FAMILY = {}
for _, f in ipairs(FAMILIES) do FAMILY[f.key] = f end
Types.FAMILIES = FAMILIES

local list, byId = {}, {} -- the types, as declared; by id
Types.list = list

local function Get(key) return Feel.Get(key) end
local function From(key) return function() return Feel.Get(key) end end -- an inherited default

---------------------------------------------------------------------------
-- The styles: every type's, resolved when Feel.rev moves
---------------------------------------------------------------------------

local NEUTRAL = { show = true, size = 1, alpha = 1, group = true } -- a look of no type (a settings row's art)
local styles, seen, rev = {}, nil, 0
local bigMin -- the zoom "zoomed in" types show from: the big map's (nil on the minimap)

-- A chosen icon's look icon: an atlas, a FileDataID or a path; its dot's colour today's.
local function Decode(v, color)
	local atlas = v:match("^A:(.+)$")
	local icon = atlas and { atlas = atlas } or { texture = tonumber(v) or v }
	icon.color = color
	return icon
end

local function Resolve()
	seen = Feel.rev
	local changed = false
	for _, t in ipairs(list) do
		local p = "pins." .. t.id .. "."
		local s = styles[t.id]
		if not s then s, changed = {}, true; styles[t.id] = s end
		local show = Get(p .. "show") ~= false
		local size = t.size == false and 1 or Get(p .. "size")
		local alpha = Get(p .. "alpha")
		local group = t.groups and Get(p .. "group") ~= false or false
		local zoomed = not FAMILY[t.family].noBig and Get(p .. "big") == "zoomed"
		local icon
		if t.icons then
			local v = Get(p .. "icon")
			if v ~= t.native then
				icon = t.made[v]
				if not icon then
					icon = Decode(v, t.look.icon and t.look.icon.color)
					t.made[v] = icon
				end
			end
		end
		if s.show ~= show or s.size ~= size or s.alpha ~= alpha or s.group ~= group or s.icon ~= icon
			or s.zoomed ~= zoomed then
			s.show, s.size, s.alpha, s.group, s.icon, s.zoomed, changed = show, size, alpha, group, icon, zoomed, true
		end
	end
	if changed then rev = rev + 1 end
end

-- A type's style (NEUTRAL for none: a row's art, false; a look with no type, nil, counted in Types.untyped, which
-- tools/tests/test_pins.py holds at none for the map's own pins).
Types.untyped = 0
function Types.Of(id)
	if Feel.rev ~= seen then Resolve() end
	local s = id and styles[id]
	if s then return s end
	if id == nil then Types.untyped = Types.untyped + 1 end
	return NEUTRAL
end

-- The zoom (px a tile) at which the big map's view spans "Zoomed in from" yards across, on STEP's grid; nil while
-- the map is small.
local function BigMin()
	if not UI.BigMap.big then return nil end
	local z = UI.Window.Size() * ns.Atlas.TILE_YARDS / Get("pins.zoomIn") -- /: never 0 (the slider's min)
	return STEP ^ math.floor(math.log(z) / LOG_STEP + 0.5) -- (the view has a width: z > 0)
end

-- Moves when any type's style does, or the big map's threshold.
function Types.Rev()
	if Feel.rev ~= seen then Resolve() end
	local m = BigMin()
	if m ~= bigMin then
		bigMin, rev = m, rev + 1
		if m then UI.Engine.Fades(m) end -- (faded in past it, not popped: a few grid steps a session)
	end
	return rev
end

-- A pin's minimum zoom (minZoom: its layer's own, or nil) with its style's big-map rule: from the threshold, for a
-- type shown zoomed in only, on the big map.
function Types.Min(st, minZoom)
	local m = st.zoomed and bigMin
	if m and not (minZoom and minZoom >= m) then return m end
	return minZoom
end

function Types.Get(id) return byId[id] end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------

Feel.Page({ key = "pins", title = "Pins", icon = "Interface\\Icons\\Ability_Tracking", order = 30,
	tip = "Every kind of pin the map draws: shown or not, its size, opacity and icon; for all pins, a family or one type.",
	sections = { "By type" } })

Feel.Add("pins", nil, {
	{ key = "pins.all.show", kind = "toggle", label = "Show pins", default = true,
		tip = "Every pin on the map. A family or a type you set yourself stays as you set it. Open it (+) for which "
			.. "show on the big map zoomed out." },
	{ key = "icons.scale", kind = "slider", label = "Pin size", min = SIZE.min, max = SIZE.max, step = SIZE.step, pct = true,
		default = ALL, tip = "Every pin's size (a group's pill keeps its own). A family or a type you size yourself keeps its size." },
	{ key = "pins.all.alpha", kind = "slider", label = "Pin opacity", min = ALPHA.min, max = ALPHA.max, step = ALPHA.step,
		pct = true, default = 1, tip = "How solid every pin is. A family or a type you set yourself keeps its own." },
	{ key = "pins.all.big", kind = "select", label = "On the big map", under = "pins.all.show", options = BIG, default = "zoomed",
		tip = "Zoomed in: on the big map a pin shows only once you zoom in (it fades in), so the zoomed-out map stays "
			.. "clear; quests, your party, flight points, dungeons and raids show always. A family or a type you set "
			.. "yourself keeps its own. The minimap shows them all." },
	{ key = "pins.zoomIn", kind = "slider", label = "Zoomed in from", under = "pins.all.show", min = 1000, max = 8000, step = 250, fmt = "%d yd",
		default = ZOOM_IN, tip = "How close is zoomed in: the big map's view this many yards across or less. A whole "
			.. "zone is about 3000 to 5000." },
})

-- A row's art: the type's look as the map draws it (its icon as chosen), at ART px; a family's its first type's.
local function Art(id, family)
	local look = { size = ART, fixed = true, type = false } -- (drawn whole: no type's size or opacity)
	return function(row, pin)
		local t = byId[id]
		if family then
			for _, x in ipairs(list) do
				if x.family == family then t = x; break end
			end
		end
		if not t then return pin end
		pin = pin or UI.Pins.Make(row)
		look.icon = Types.Of(t.id).icon or t.look.icon
		UI.Pins.Style(pin, look)
		return pin
	end
end

for _, f in ipairs(FAMILIES) do
	local p = "pins." .. f.key .. "."
	local rows = {
		{ key = p .. "show", kind = "toggle", label = f.name, default = From("pins.all.show"), art = Art(nil, f.key),
			tip = f.name .. ": shown or not. Each of its types follows this until you set it; open it (+) for its size, "
				.. "opacity and types." },
	}
	if not f.noSize then
		rows[#rows + 1] = { key = p .. "size", kind = "slider", label = "Size", under = p .. "show", min = SIZE.min,
			max = SIZE.max, step = SIZE.step, pct = true, default = f.size or From("icons.scale"),
			tip = f.name .. ": their size" .. (f.size and ", of their own (they never followed the icon size)."
				or ", Pin size's until you set it.") }
	end
	rows[#rows + 1] = { key = p .. "alpha", kind = "slider", label = "Opacity", under = p .. "show", min = ALPHA.min,
		max = ALPHA.max, step = ALPHA.step, pct = true, default = From("pins.all.alpha"),
		tip = f.name .. ": how solid they are, Pin opacity's until you set it." }
	if not f.noBig then
		rows[#rows + 1] = { key = p .. "big", kind = "select", label = "On the big map", under = p .. "show", options = BIG,
			default = f.big or From("pins.all.big"), tip = f.name .. ": always on the big map, or only zoomed in"
				.. (f.big and " (always, of their own)." or ", as On the big map is until you set it.") }
	end
	Feel.Add("pins", "By type", rows)
end

-- A value as an icon option: its art the value itself (Feel's options take "A:<atlas>", a FileDataID or a path).
local function Encode(icon)
	if icon.atlas then return "A:" .. icon.atlas end
	return tostring(icon.texture)
end

function Types.Add(t)
	assert(FAMILY[t.family] and not byId[t.id], "PinTypes.Add: a new id in a family")
	list[#list + 1], byId[t.id] = t, t
	seen = nil -- (resolved again, with it)
	local f, p = "pins." .. t.family .. ".", "pins." .. t.id .. "."
	local rows = {
		{ key = p .. "show", kind = "toggle", label = t.name, under = f .. "show", default = From(f .. "show"), art = Art(t.id),
			tip = t.tip .. " Shown as its family is until you set it." },
	}
	if t.size ~= false then
		rows[#rows + 1] = { key = p .. "size", kind = "slider", label = "Size", under = p .. "show", min = SIZE.min,
			max = SIZE.max, step = SIZE.step, pct = true, default = From(f .. "size"), tip = "Its size: its family's until you set it." }
	end
	rows[#rows + 1] = { key = p .. "alpha", kind = "slider", label = "Opacity", under = p .. "show", min = ALPHA.min,
		max = ALPHA.max, step = ALPHA.step, pct = true, default = From(f .. "alpha"),
		tip = "How solid it is: its family's until you set it." }
	if not FAMILY[t.family].noBig then
		rows[#rows + 1] = { key = p .. "big", kind = "select", label = "On the big map", under = p .. "show", options = BIG,
			default = t.big or From(f .. "big"), tip = "Always on the big map, or only zoomed in: "
				.. (t.big and "always by default." or "its family's until you set it.") }
	end
	if t.icons then
		local options = {}
		for i, o in ipairs(t.icons) do options[i] = { o[1], o[2], o[2] } end
		t.native, t.made = t.icons[1][2], {}
		assert(not t.look.icon or t.native == Encode(t.look.icon), "PinTypes.Add: the first icon is today's")
		rows[#rows + 1] = { key = p .. "icon", kind = "select", label = "Icon", under = p .. "show", options = options,
			default = t.native, tip = "Its icon: the client's own art, " .. t.icons[1][1]:lower() .. " by default." }
	end
	if t.groups then
		rows[#rows + 1] = { key = p .. "group", kind = "toggle", label = "Group", under = p .. "show", default = true,
			tip = "On the big map, where it crowds others, it may stand in a group's pill." }
	end
	Feel.Add("pins", "By type", rows)
	return t
end
