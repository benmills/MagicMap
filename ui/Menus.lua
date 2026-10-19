-- Menus are the client's own (MenuUtil), no skin (Menu.lua). Opened through here, they count
-- as open for the controls that opened them, so those don't fade out under them.
-- The gear menu (GearMenu.lua): what's drawn, a submenu per group of layers (Layers.lua:2179-2203),
-- then Settings: Map (Colour-matched tiles), Minimap (Minimap button, Reset position, Use Blizzard's
-- minimap). Tracking and Settings' Advanced: M4.5 (their commands: M4.1, M4.6).

local _, ns = ...
local UI, Model, Runtime = ns.UI, ns.Model, ns.Runtime
local Engine = UI.Engine

local Menus = {}
UI.Menus = Menus

local menu -- the last menu opened

function Menus.IsOpen()
	return menu ~= nil and menu:IsShown()
end

function Menus.Show(owner, generator)
	menu = MenuUtil.CreateContextMenu(owner, generator)
	return menu
end

-- A pick, called by the client from its menu: wrapped, as our scripts are.
local Run = Runtime.Wrap("map: gear pick", function(fn, arg) fn(arg) end)

-- A row's tooltip: white title, gold body (GearMenu.lua:69-72, Layers.lua:2171-2176).
local function Tip(label, tip)
	return function(tooltip)
		tooltip:SetText(label, 1, 1, 1)
		tooltip:AddLine(tip, 1, 0.82, 0, true)
	end
end

---------------------------------------------------------------------------
-- Layers: a submenu per group, of checkboxes that keep the menu open
---------------------------------------------------------------------------

-- The groups, in order (Layers.lua:63-70); one with no layer is left out.
local GROUPS = {
	{ key = "map", title = "Map" },
	{ key = "quests", title = "Quests" },
	{ key = "places", title = "Places" },
	{ key = "people", title = "People" },
	{ key = "you", title = "You" },
	{ key = "addons", title = "Other addons" },
}

-- The layers' rows: { key, label, group, tip, default?, parent?, onToggle? } (Layers.lua:30-61,
-- 1194-1215). key: the layer's, Engine.Layer's name (View.layers' too, for Game's); its setting is
-- Engine.LayerOn(key) (UI.saved.layers: only where it isn't its default). default: false for a layer off
-- until turned on (missing: on). parent: a sub-option, indented and only clickable while that layer is
-- on (drawn only then: its layer's own check). onToggle(on): called after its setting changes. M2-M4 add
-- theirs with their layers; each group's rows in the spike's order (ORDER: its keys, Layers.lua:30-61,
-- then Landmarks.lua:70, 110, 142 and Blips.lua:671 as its TOC loads them), a key not in it last.
local ORDER = {}
for i, key in ipairs({ "labels", "borders", "unexplored", "quests", "questAreas", "questAreasApprox", "offers",
	"flight", "dungeons", "graveyards", "corpse", "group", "waypoint", "rares", "vignettes", "areaPOIs", "blips" }) do
	ORDER[key] = i
end
local LAYERS = {}
local function Before(a, b) return a.place < b.place end
function Menus.Layer(row)
	LAYERS[#LAYERS + 1] = row
	row.place = ORDER[row.key] or 100 + #LAYERS
	Engine.defaults[row.key] = row.default
	table.sort(LAYERS, Before)
	return row
end

-- Drawn so far (Layers.lua:34-37, Blips.lua:671-672, Landmarks.lua:70-71).
Menus.Layer({ key = "labels", label = "Zone labels", group = "map", tip = "Names of zones and sub-zones." })
Menus.Layer({ key = "borders", label = "Zone borders", group = "map",
	tip = "Outlines between zones, traced from the terrain." })
Menus.Layer({ key = "blips", label = "Minimap blips", group = "places",
	tip = "What Blizzard's minimap tracks around you (herbs, ore, town services), drawn on the map." })
Menus.Layer({ key = "rares", label = "Rares you've seen", group = "people",
	tip = "Rare creatures where you last saw them, remembered between sessions." })

-- Other addons' world-map pins (AddonPins.lua:105-113): a row for each with some (Model.addons), its
-- pins borrowed while on (ui/Sockets.lua puts it in View.layers from the next frame).
local function AddonRow(a)
	local key, other = "addon:" .. a.key, a.key == "Other"
	return { key = key, label = a.name, group = "addons",
		tip = "Map pins " .. (other and "other addons put" or a.name .. " puts") .. " on the world map, shown here too." }
end

-- The groups with layers, in order, each { title, rows } (Layers.lua:2154-2166).
local function Sections()
	local out = {}
	for _, g in ipairs(GROUPS) do
		local rows = {}
		for _, row in ipairs(LAYERS) do
			if row.group == g.key then rows[#rows + 1] = row end
		end
		if g.key == "addons" then
			for _, a in ipairs(Model.addons) do
				if a.world then rows[#rows + 1] = AddonRow(a) end
			end
		end
		if rows[1] then out[#out + 1] = { title = g.title, rows = rows } end
	end
	return out
end

-- Its setting flipped (Layers.lua:2141-2150): Engine draws it or empties it from the next frame.
local function Flip(row)
	local on = not Engine.LayerOn(row.key)
	Engine.SetLayer(row.key, on)
	if row.onToggle then row.onToggle(on) end
end

local function AddLayers(root)
	for _, sec in ipairs(Sections()) do
		local sub = root:CreateButton(sec.title)
		for _, row in ipairs(sec.rows) do
			local cb = sub:CreateCheckbox((row.parent and "     " or "") .. row.label,
				function() return Engine.LayerOn(row.key) end,
				function()
					Run(Flip, row)
					return MenuResponse.Refresh
				end)
			if row.parent then cb:SetEnabled(function() return Engine.LayerOn(row.parent) end) end
			cb:SetTooltip(Tip(row.label, row.tip))
		end
	end
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

-- In sections: { title, rows }. A row is a checkbox ({ label, on =, run =, tip = }) or a button
-- ({ label, run = }) (GearMenu.lua:30-59).
local SETTINGS = {
	{ "Map", {
		{ "Colour-matched tiles", on = function() return UI.saved.tint end, run = function() UI.Tint() end,
			tip = "Evens out the minimap art's colours where tiles meet, and fades the coasts into the sea." },
	} },
	{ "Minimap", {
		{ "Minimap button", on = function() return UI.saved.button end, run = function() UI.Icon() end,
			tip = "The button on Blizzard's minimap, for when MagicMap is switched off." },
		{ "Reset position", run = function() UI.BigMap.Reset() end },
		{ "Use Blizzard's minimap", run = function() UI.Window.frame:Hide() end },
	} },
}

-- A checkbox keeps the menu open; a button closes it (the client's default).
local function AddSections(sub, sections)
	for n, section in ipairs(sections) do
		if n > 1 then sub:CreateDivider() end
		sub:CreateTitle(section[1])
		for _, row in ipairs(section[2]) do
			if row.on then
				local cb = sub:CreateCheckbox(row[1], function() return row.on() and true or false end, function()
					Run(row.run)
					return MenuResponse.Refresh
				end)
				cb:SetTooltip(Tip(row[1], row.tip))
			else
				sub:CreateButton(row[1], function() Run(row.run) end)
			end
		end
	end
end

-- The map's right-click menu (Core.lua:1355-1385), its minimum for now: "Follow me" while you
-- aren't followed (waypoints, the big map's zone info: M3.4).
function Menus.Map(owner)
	if UI.Camera.follow then return end
	Menus.Show(owner, function(_, root)
		root:CreateButton("Follow me", function() UI.Motion.SetFollow(true, true) end)
	end)
end

function Menus.Gear(owner)
	Menus.Show(owner, function(_, root)
		AddLayers(root)
		root:CreateDivider()
		AddSections(root:CreateButton("Settings"), SETTINGS)
	end)
end
