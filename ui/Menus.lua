-- Menus are the client's own (MenuUtil), no skin (Menu.lua). Opened through here, they count
-- as open for the controls that opened them, so those don't fade out under them.
-- The gear menu (GearMenu.lua): what's drawn, a submenu per group of layers (Map, Quests, Places, Nearby,
-- Other addons), each with an "All" box on top (the group on or off) and each row's icon beside its name;
-- Nearby lists Blizzard's tracking types too (but those ours replace). Then quick actions (Use Blizzard's
-- minimap, Reset to defaults: every layer as installed), then Settings, one list (Follow you, Group
-- overlapping icons, Minimap button, Reset window position, Advanced: Diagnostics, Grouping's tunables,
-- Performance).
-- /mm layers (Layers.lua:2196-2207).
-- The map picker (the title's click: ui/ZoneInfo.lua) and /mm map; the map's right-click menu.

local _, ns = ...
local UI, Model, Atlas, Runtime = ns.UI, ns.Model, ns.Atlas, ns.Runtime
local Engine = UI.Engine
local Command = ns.Game.Command

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
local Pick = Runtime.Wrap("map: menu pick", function(fn, arg) fn(arg) end) -- the picker's, the map menu's

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
	{ key = "nearby", title = "Nearby" }, -- then Blizzard's tracking types (AddLayers)
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
for i, key in ipairs({ "labels", "borders", "quests", "questAreas", "offers",
	"flight", "dungeons", "graveyards", "areaPOIs", "rares", "group" }) do
	ORDER[key] = i
end
local LAYERS = {}
local function Before(a, b) return a.place < b.place end
function Menus.Layer(row)
	LAYERS[#LAYERS + 1] = row
	row.place = ORDER[row.key] or 100 + #LAYERS
	Engine.defaults[row.key] = row.default ~= false -- (a gear row's key: /mm layer takes it too)
	table.sort(LAYERS, Before)
	return row
end

-- Drawn so far (Layers.lua:34-37, Blips.lua:671-672, Landmarks.lua:70-71).
Menus.Layer({ key = "labels", label = "Zone labels", group = "map", tip = "Names of zones and sub-zones." })
Menus.Layer({ key = "borders", label = "Zone borders", group = "map",
	tip = "Outlines between zones, traced from the terrain." })
-- Rares you've seen and the live ones (vignettes: rares, treasures, events the game shows near you): one row.
Menus.Layer({ key = "rares", label = "Rares & treasures", group = "nearby",
	tip = "Rares where you last saw them, and the rares, treasures and events the game shows near you now.",
	onToggle = function(on) Engine.SetLayer("vignettes", on) end })

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
		if rows[1] then out[#out + 1] = { key = g.key, title = g.title, rows = rows } end
	end
	return out
end

-- Its setting flipped (Layers.lua:2141-2150): Engine draws it or empties it from the next frame.
local function Flip(row)
	local on = not Engine.LayerOn(row.key)
	Engine.SetLayer(row.key, on)
	if row.onToggle then row.onToggle(on) end
end

-- Each layer's icon beside its name (legibility): the art its pins draw (an atlas), else a client icon.
local ICON = {
	labels = "Interface\\Icons\\INV_Misc_Note_01", borders = "Interface\\Icons\\INV_Misc_Map_01",
	questAreas = "Interface\\Icons\\INV_Misc_Map02",
	quests = "A:Quest-In-Progress-Icon-yellow", offers = "A:QuestNormal", flight = "A:taxinode_neutral",
	dungeons = "A:dungeon", graveyards = "A:poi-graveyard-neutral",
	group = "Interface\\Icons\\Spell_Holy_PrayerOfFortitude",
	rares = "A:vignettekill", areaPOIs = "Interface\\Icons\\INV_Misc_Map_01",
}
local function Label(row)
	local icon, mark = ICON[row.key], ""
	if icon and icon:sub(1, 2) == "A:" then
		if C_Texture.GetAtlasInfo(icon:sub(3)) then mark = "|A:" .. icon:sub(3) .. ":16:16|a  " end
	elseif icon then
		mark = "|T" .. icon .. ":16:16:0:0:64:64:5:59:5:59|t  " -- (an icon's border cropped)
	end
	return (row.parent and "     " or "") .. mark .. row.label
end

-- Its setting set (Flip, when it differs).
local function Set(row, on)
	if Engine.LayerOn(row.key) ~= on then Flip(row) end
end

-- Nearby's tracking rows (Blizzard's types, below): set later in this file.
local TrackingOn, SetTracking, AddTrackingRows

-- A group's rows all on (Nearby: its tracking types too).
local function AllOn(sec)
	for _, row in ipairs(sec.rows) do
		if not Engine.LayerOn(row.key) then return false end
	end
	return sec.key ~= "nearby" or TrackingOn()
end

-- A group toggled whole: all on, or all off when they all were.
local function SetGroup(sec)
	local on = not AllOn(sec)
	for _, row in ipairs(sec.rows) do Set(row, on) end
	if sec.key == "nearby" then SetTracking(on) end
end

-- Every layer back to its default (on, but those off until turned on).
local function Reset()
	for _, sec in ipairs(Sections()) do
		for _, row in ipairs(sec.rows) do Set(row, row.default ~= false) end
	end
end

local function AddLayers(root)
	for _, sec in ipairs(Sections()) do
		local sub = root:CreateButton(sec.title)
		local rows = sec.rows
		sub:CreateCheckbox("All " .. sec.title:lower(), function() return AllOn(sec) end, function()
			Run(SetGroup, sec)
			return MenuResponse.Refresh
		end)
		sub:CreateDivider()
		for _, row in ipairs(rows) do
			local cb = sub:CreateCheckbox(Label(row),
				function() return Engine.LayerOn(row.key) end,
				function()
					Run(Flip, row)
					return MenuResponse.Refresh
				end)
			if row.parent then cb:SetEnabled(function() return Engine.LayerOn(row.parent) end) end
			cb:SetTooltip(Tip(row.label, row.tip))
		end
		if sec.key == "nearby" then AddTrackingRows(sub) end
	end
end

-- On green, off grey (a sub-option off while its parent is), by group (Layers.lua:2196-2207); the spike's
-- keys (Layers.lua:33-36) where ours name the layer that draws them.
local SPIKE_KEY = { labels = "zoneLabels", borders = "zoneBorders" }
Command({ kind = "slash", name = "layers", help = "the map's layers by group, on or off", fn = function()
	local parts = {}
	for _, sec in ipairs(Sections()) do
		local on = {}
		for _, row in ipairs(sec.rows) do
			local shown = Engine.LayerOn(row.key) and (not row.parent or Engine.LayerOn(row.parent))
			on[#on + 1] = (shown and "|cff33ff33" or "|cff888888") .. (SPIKE_KEY[row.key] or row.key) .. "|r"
		end
		parts[#parts + 1] = "|cffffd100" .. sec.title .. ":|r " .. table.concat(on, ", ")
	end
	UI.Print("layers: " .. table.concat(parts, "; ") .. ". Toggle them from the gear. "
		.. "Shift-click: /way at cursor. Ctrl-click: set waypoint. Ctrl-right-click: clear it.")
end })

---------------------------------------------------------------------------
-- Tracking (GearMenu.lua:9-26): Blizzard's types but those ours replace (kind "duplicate": Game keeps
-- them off while our layer draws the same), in the client's order
---------------------------------------------------------------------------

-- A box Game sets (a Command, carried out in its next input step; the spike's took at once) shows what
-- was asked of it while its state is still what it was then. Asked anew each time the gear opens.
local want, was = {}, {} -- a box's key -> what was asked, its state then
local function Shown(key, on)
	if was[key] == on then return want[key] end
	was[key] = nil
	return on
end
local function Ask(key, on)
	local w = not Shown(key, on)
	if was[key] == nil then was[key] = on end
	want[key] = w
	return w
end

local function Active(id)
	for _, t in ipairs(Model.tracking) do
		if t.id == id then return t.active end
	end
	return false
end

local function Track(id)
	Command({ kind = "tracking", id = id, on = Ask(id, Active(id)) })
end

-- The types listed (Blizzard's but those ours replace: kind "duplicate").
local function Listed(fn)
	for _, t in ipairs(Model.tracking) do
		if t.kind ~= "duplicate" then fn(t) end
	end
end

function TrackingOn()
	local all = true
	Listed(function(t) all = all and Shown(t.id, Active(t.id)) end)
	return all
end

function SetTracking(on)
	Listed(function(t)
		if Shown(t.id, Active(t.id)) ~= on then Track(t.id) end
	end)
end

-- Under Nearby's rows, a divider and each type with its icon (as Blizzard's menu has it): what it finds is
-- drawn on the map (the blips layer).
function AddTrackingRows(sub)
	if not Model.tracking[1] then return end
	sub:CreateDivider()
	Listed(function(t)
		local id = t.id
		local mark = t.texture and "|T" .. t.texture .. ":16:16|t  " or ""
		sub:CreateCheckbox(mark .. t.name, function() return Shown(id, Active(id)) end, function()
			Run(Track, id)
			return MenuResponse.Refresh
		end)
	end)
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

-- /mm <line>, as typed (Game owns them): Advanced runs the same code (GearMenu.lua:28).
local function Slash(line) return function() Command({ kind = "run", line = line }) end end

-- Advanced (GearMenu.lua:33-46): a box shows its command's state where its owner keeps it: the title's
-- debug line in UI's saved part (the spike's db.debug), Game's indoor reports on obs.minimap, a recording
-- Runtime's.
local ADVANCED = {
	{ "Diagnostics", {
		{ "Debug info in the title", on = function() return UI.saved.debug end, run = Slash("debug"),
			tip = "Tile, zoom and layout timings next to the zone name." },
		{ "Indoor maps", on = function() return Model.minimap.indoorDebug end, run = Slash("indoor"),
			tip = "Says in chat which map you're on indoors, whether it has art, and what the map shows; outlines the art." },
	} },
	{ "Grouping", {
		{ "Distance", choices = { { "16 px", 16 }, { "20 px", 20 }, { "24 px", 24 }, { "28 px", 28 }, { "32 px", 32 }, { "40 px", 40 } },
			key = "range", tip = "How close icons' centres must be to group." },
		{ "Reach", choices = { { "1x distance", 1 }, { "2x", 2 }, { "3x", 3 }, { "4x", 4 }, { "6x", 6 } },
			key = "reach", tip = "How far a group grows from its first icon, by neighbours of neighbours." },
		{ "Smallest group", choices = { { "2 icons", 2 }, { "3 icons", 3 }, { "4 icons", 4 }, { "5 icons", 5 } },
			key = "min", tip = "Fewer icons than this stay apart." },
		{ "Icons in a pill", choices = { { "2", 2 }, { "3", 3 }, { "4", 4 } },
			key = "slots", tip = "A pill's slots: every icon if they fit, else one fewer and \"+N\"." },
		{ "Pill background", choices = { { "None", 0 }, { "15%", 0.15 }, { "25%", 0.25 }, { "35%", 0.35 }, { "50%", 0.5 }, { "70%", 0.7 } },
			key = "alpha", tip = "How dark the pill behind grouped icons is." },
		{ "Reset grouping", run = function() UI.Cluster.Reset() end },
	} },
	{ "Performance", {
		{ "Record 10 seconds", on = function() return Runtime.recording end, run = Slash("perf"),
			tip = "Times every part of MagicMap while you play, then prints a summary." },
		{ "Compare with other addons", run = Slash("perf top") },
		{ "Memory breakdown", run = Slash("perf mem") },
	} },
}

-- In sections: { title, rows }. A row is a checkbox ({ label, on =, run =, tip = }), a button
-- ({ label, run = }) or a submenu ({ label, sub = sections }) (GearMenu.lua:30-59).
local SETTINGS = {
	{ nil, {
		{ "Follow you", on = function() return UI.Camera.follow end, run = function() UI.Motion.SetFollow(not UI.Camera.follow, true) end,
			tip = "Keeps the map centred on you. Drag the map to look about; it glides back to you when left alone." },
		{ "Group overlapping icons", on = function() return UI.saved.cluster ~= false end,
			run = function() UI.saved.cluster = UI.saved.cluster == false end,
			tip = "Where icons crowd together, one small pill: click it to see them all." },
		{ "Minimap button", on = function() return UI.saved.button end, run = function() UI.Icon() end,
			tip = "The button on Blizzard's minimap, for when MagicMap is switched off." },
		{ "Reset window position", run = function() UI.BigMap.Reset() end },
		{ "Advanced", sub = ADVANCED },
	} },
}

local function On(row) return row.on() and true or false end

local function Set(row)
	Ask(row, On(row))
	row.run()
end

-- A checkbox keeps the menu open; a button closes it (the client's default).
local function AddSections(sub, sections)
	for n, section in ipairs(sections) do
		if n > 1 then sub:CreateDivider() end
		if section[1] then sub:CreateTitle(section[1]) end
		for _, row in ipairs(section[2]) do
			if row.sub then
				AddSections(sub:CreateButton(row[1]), row.sub)
			elseif row.choices then -- (grouping's tunables: one of a few values, UI.Cluster's)
				local pick = sub:CreateButton(row[1])
				pick:SetTooltip(Tip(row[1], row.tip))
				for _, c in ipairs(row.choices) do
					local value = c[2]
					pick:CreateRadio(c[1] .. (value == UI.Cluster.DEFAULTS[row.key] and "  (default)" or ""),
						function() return UI.Cluster.Get(row.key) == value end, function()
							Run(function() UI.Cluster.Set(row.key, value) end)
							return MenuResponse.Refresh
						end)
				end
			elseif row.on then
				local cb = sub:CreateCheckbox(row[1], function() return Shown(row, On(row)) end, function()
					Run(Set, row)
					return MenuResponse.Refresh
				end)
				cb:SetTooltip(Tip(row[1], row.tip))
			else
				sub:CreateButton(row[1], function() Run(row.run) end)
			end
		end
	end
end

---------------------------------------------------------------------------
-- The map picker (Core.lua:1161-1240) and /mm map (Core.lua:1704-1720)
---------------------------------------------------------------------------

local CONTINENT_MIN_TILES = 300 -- open-world maps this big are listed as continents (Core.lua:1062)
local KINDS = { { "dungeon", "Dungeons" }, { "raid", "Raids" } }

local counts = {} -- inst -> its tiles
local function Count(inst)
	local n = counts[inst]
	if not n then
		n = 0
		for _ in pairs(Atlas.Tiles(inst)) do n = n + 1 end
		counts[inst] = n
	end
	return n
end

local function ByName(a, b) return a.name < b.name end

-- { continents = { maps }, others = { maps }, dungeon = { { name, maps }, ... }, raid = ... }: instances by
-- the continent their entrance is on, "Other" (unplaced) last.
local function Groups()
	local g, byKind, names = { continents = {}, others = {} }, {}, {}
	for _, m in ipairs(Atlas.Maps()) do names[m.inst] = m.name end
	for _, m in ipairs(Atlas.Maps()) do
		if m.kind then
			local groups = byKind[m.kind] or {}
			byKind[m.kind] = groups
			local cont = m.continent and names[m.continent] or "Other"
			groups[cont] = groups[cont] or {}
			table.insert(groups[cont], m)
		elseif Count(m.inst) >= CONTINENT_MIN_TILES then
			table.insert(g.continents, m)
		else
			table.insert(g.others, m)
		end
	end
	table.sort(g.continents, ByName)
	table.sort(g.others, ByName)
	for _, k in ipairs(KINDS) do
		local list = {}
		for name, maps in pairs(byKind[k[1]] or {}) do
			table.sort(maps, ByName)
			list[#list + 1] = { name = name, maps = maps }
		end
		table.sort(list, function(a, b)
			if (a.name == "Other") ~= (b.name == "Other") then return b.name == "Other" end
			return a.name < b.name
		end)
		g[k[1]] = list
	end
	return g
end

-- A whole map, fit to the window, following off (Core.lua:1154-1159).
function Menus.ShowMap(inst)
	UI.Motion.SetFollow(false)
	UI.Motion.FitMap(inst)
	UI.Window.frame:Show()
end

function Menus.Picker(owner)
	local g = Groups()
	Menus.Show(owner, function(_, root)
		local function Radio(parent, m)
			parent:CreateRadio(m.name, function() return UI.Camera.inst == m.inst end, function()
				Pick(Menus.ShowMap, m.inst)
				return MenuResponse.Close
			end)
		end
		root:CreateTitle("Continents")
		for _, m in ipairs(g.continents) do Radio(root, m) end
		if g.others[1] then
			local other = root:CreateButton("Other maps")
			for _, m in ipairs(g.others) do Radio(other, m) end
		end
		if g.dungeon[1] or g.raid[1] then
			root:CreateDivider()
			root:CreateTitle("Instances")
			for _, k in ipairs(KINDS) do
				local groups = g[k[1]]
				if groups[1] then
					local kind = root:CreateButton(k[2])
					for _, group in ipairs(groups) do
						-- Only one group: the continent level skipped.
						local parent = groups[2] and kind:CreateButton(group.name) or kind
						for _, m in ipairs(group.maps) do Radio(parent, m) end
					end
				end
			end
		end
	end)
end

Command({ kind = "slash", name = "map", help = "<id|name>: show a map whole; alone, list them", fn = function(arg)
	arg = arg:lower()
	local id = tonumber(arg)
	for _, m in ipairs(Atlas.Maps()) do
		if m.inst == id or m.name:lower() == arg then return Menus.ShowMap(m.inst) end
	end
	local names = {}
	for _, m in ipairs(Atlas.Maps()) do names[#names + 1] = m.inst .. "=" .. m.name end
	UI.Print("usage: /mm map <id|name>  (" .. table.concat(names, ", ") .. ")")
end })

---------------------------------------------------------------------------
-- The map's right-click menu (Core.lua:1355-1385)
---------------------------------------------------------------------------

-- Only what makes sense where you clicked: Waypoint here (in a zone), Clear waypoint (one set), Follow me
-- (not following); the big map leads with what's there (ui/ZoneInfo.lua), at the minimap's size the
-- actions alone.
function Menus.Map(owner, col, row)
	local inst, items = UI.Camera.inst, {}
	if Atlas.ZoneMapAt(inst, col, row) then -- (where Game's waypoint can go)
		items[#items + 1] = { "Waypoint here", function()
			Command({ kind = "waypoint", pos = { inst = inst, col = col, row = row } })
		end }
	end
	if Model.waypointSet then -- (wherever it is: Layers.lua:2080-2081)
		items[#items + 1] = { "Clear waypoint", function() Command({ kind = "waypoint", pos = false }) end }
	end
	if not UI.Camera.follow then
		items[#items + 1] = { "Follow me", function() UI.Motion.SetFollow(true, true) end }
	end
	local info = UI.BigMap.big and UI.ZoneInfo.At(col, row) or nil
	if not (items[1] or info) then return end
	Menus.Show(owner, function(_, root)
		if info then
			for _, line in ipairs(info) do root:CreateTitle(line) end
			if items[1] then root:CreateDivider() end
		end
		for _, it in ipairs(items) do root:CreateButton(it[1], function() Pick(it[2]) end) end
	end)
end

function Menus.Gear(owner)
	want, was = {}, {}
	Menus.Show(owner, function(_, root)
		AddLayers(root)
		root:CreateDivider()
		root:CreateButton("Use Blizzard's minimap", function() Run(function() UI.Window.frame:Hide() end) end)
		root:CreateButton("Reset to defaults", function() Run(Reset) end)
			:SetTooltip(Tip("Reset to defaults", "Every layer back as it was installed."))
		root:CreateDivider()
		AddSections(root:CreateButton("Settings"), SETTINGS)
	end)
end
