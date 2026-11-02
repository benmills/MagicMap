-- MagicMap's settings window (gear -> Settings…, /mm feel, /mm settings; Game menu -> Options -> AddOns -> MagicMap
-- opens it too): a small movable dialog of the client's ButtonFrameTemplate (as the map window, ui/Window.lua, but
-- kept as the client draws it: header bar, close button), DIALOG strata, clamped to the screen, dragged by its
-- header, Escape closes it (game/Hooks.lua names it in UISpecialFrames). A sidebar of categories (icon, name, the
-- chosen one lit) and the page of the chosen one on its right; each page built on its first showing, with its own
-- Reset (where its settings are looks: General's and Diagnostics' are switches and actions, nothing to reset), and
-- Reset all at the bottom. The last category is kept (UI.saved.feelPage). Every change applies live:
--   General: Replace minimap / world map (UI.Replace, the other half of the contract: Get(key), Set(key, on)),
--     Follow you (UI.Motion), Minimap button (UI.Icon), Group icons (UI.saved.cluster), Reset window position.
--   Map: label size, subzone label size and opacity (ui/Labels.lua), zone borders' opacity and width (ui/Borders.lua),
--     your arrow's size (ui/You.lua), the info pills' backing (ui/Controls.lua), the indoor veil's strength and whether
--     a small building zooms the map in (ui/Interiors.lua), the ocean (ui/Sea.lua) and the repaints (ui/Repaint.lua). Pushed to their setters on change, and again each time the
--     map shows (the saved values, once loaded); each owner lays out anew by a rev of its own.
--   Icons: every pin's size, and the quests' (ui/Pins.lua, ui/Quests.lua; their revs move with it); the focus ring
--     round what you track: its size, opacity and colour (Pins.SetGlow; "ring.color" a name of UI.Pins.GLOW_COLORS).
--   Tracking line: style, weight, colour, glow, breathing, opacity, the outline and its colour. ui/Path.lua owns the values: it
--     reads Feel.Get("path.<key>") and lays out again when Feel.rev moves; its UI.Path.DEFAULTS and
--     UI.Path.COLORS and EDGE_COLORS (ordered presets { name, { r, g, b } }, the first the default) are read when
--     asked, never at load (Path.lua loads after this file; fallbacks until it lands). "path.color" and
--     "path.edgeColor" are presets' names.
--   Quest areas: the fill, edge alpha and edge width of the followed quest's area and of the others', and the
--     hover's fill and edge alpha (alphas 0-255, shown as %): ui/Areas.lua reads Feel.Get("areas.<key>") and
--     styles its frames anew when Feel.rev moves (UI.Areas.DEFAULTS are the defaults, read when asked).
--   Grouping: ui/Cluster.lua's five tunables, through Cluster.Get/Set (saved as UI.saved.clusterTune, as before).
--   Diagnostics: the title's debug line, the indoor reports, and the recording, comparison and memory reports
--     (each the /mm command it was in the gear's Advanced; they stay slash commands too).
-- Every setting is declared once in KEYS ({ key, section, label, kind = "slider" | "check" | "pick" | "button", min,
-- max, step, default (a value, or a function), options (or a function), tip, apply? }): the dialog is built from
-- it; its widgets are refreshed from the values on open, on a page's showing and after a reset, each set only when
-- it differs. A look is saved in UI.saved.feel = { ["path.style"] = ... } (types/saved.lua), a key only while it
-- differs from its default, the table gone when none does. A key with get/set (ext) lives where its owner keeps it
-- (UI.saved, UI.Replace, Game's commands): Get/Set go there, no rev, no reset. Hidden almost always: no step, nothing a frame.
-- API: Feel.Get(key), Feel.Set(key, v), Feel.Reset(section), Feel.ResetAll(), Feel.Open(page?), Feel.Toggle(), Feel.rev,
-- Feel.OnLoad(fn) (fn runs once the saved part loads; Feel.Loaded() is View's).
-- Feel.Get is safe before the saved part loads (a layer's load-time Apply asks it). The client's own Settings
-- entry (Game menu -> Options -> AddOns -> MagicMap) is Game's (game/Options.lua): its button runs /mm feel open.

local _, ns = ...
local UI, Runtime, Model = ns.UI, ns.Runtime, ns.Model
local Command = ns.Game.Command

local Feel = { rev = 0 }
UI.Feel = Feel

-- Until ui/Path.lua exposes its own.
local PATH_DEFAULTS = { style = "dashed", weight = 1, color = "Gold", glow = false, breath = false, opacity = 0.55,
	edge = false, edgeColor = "Dark" }
local PATH_COLORS = { { "Gold", { 1, 0.82, 0.3 } } }
local EDGE_COLORS = { { "Dark", { 0.12, 0.08, 0.03 } } }
-- Until ui/Pins.lua (after this file) exposes its own.
local RING_COLORS = { { "Gold", { 1, 0.82, 0.3 } } }
-- Until ui/Areas.lua (after this file) exposes its own.
local AREA_DEFAULTS = { fFill = 32, fEdge = 120, fWidth = 0.8, oFill = 0, oEdge = 85, oWidth = 0.6, hFill = 45, hEdge = 150 }
local function PathDefaults() return UI.Path and UI.Path.DEFAULTS or PATH_DEFAULTS end
local function PathColors() return UI.Path and UI.Path.COLORS or PATH_COLORS end
local function PathDefault(k) return function() return PathDefaults()[k] end end
-- The default colour: Path's, if it names a preset; else the first preset.
local function ColorDefault()
	local d = PathDefaults().color
	return type(d) == "string" and d or PathColors()[1][1]
end
-- A pick's options from presets { name, rgb } (a function: read when asked).
local function Names(list)
	return function()
		local out = {}
		for i, c in ipairs(list()) do out[i] = { c[1], c[1] } end
		return out
	end
end
local ColorOptions = Names(PathColors)
local EdgeOptions = Names(function() return UI.Path and UI.Path.EDGE_COLORS or EDGE_COLORS end)
local RingColors = function() return UI.Pins and UI.Pins.GLOW_COLORS or RING_COLORS end

local function AreaDefault(k) return function() return UI.Areas and UI.Areas.DEFAULTS[k] or AREA_DEFAULTS[k] end end

local PAGES = {
	{ key = "general", title = "General", icon = "Interface\\Icons\\Trade_Engineering" },
	{ key = "map", title = "Map", icon = "Interface\\Icons\\INV_Misc_Map_01" },
	{ key = "icons", title = "Icons", icon = "Interface\\Icons\\Ability_Tracking" },
	{ key = "path", title = "Tracking line", icon = "Interface\\Icons\\Ability_Hunter_Pathfinding" },
	{ key = "areas", title = "Quest areas", icon = "Interface\\Icons\\INV_Misc_Map02" },
	{ key = "group", title = "Grouping", icon = "Interface\\Icons\\INV_Misc_Bag_08" },
	{ key = "diag", title = "Diagnostics", icon = "Interface\\Icons\\INV_Gizmo_01" },
}
local BY_PAGE = {}
for _, p in ipairs(PAGES) do BY_PAGE[p.key] = p end

-- /mm <line>, as typed (Game owns them): a diagnostics row runs the same code (the gear's Advanced did).
local function Slash(line) return function() Command({ kind = "run", line = line }) end end
-- UI.Replace (the contract: Get(key), Set(key, on)), if it's loaded.
local function Replaced(key) return UI.Replace ~= nil and UI.Replace.Get(key) == true end
local function Replace(key) return function(on) if UI.Replace then UI.Replace.Set(key, on) end end end

-- pct: shown as a percentage; of: as a percentage of it (alphas 0-255; step 1: their defaults lie on the grid). cluster: ui/Cluster.lua's tunable it is (held there, not in saved.feel).
-- get/set: an ext key, kept by its owner. apply(v): its setter, called on change and each time the map shows. run: a button's.
local KEYS = {
	{ key = "replace.minimap", section = "general", label = "Replace minimap", kind = "check", get = function() return Replaced("minimap") end,
		set = Replace("minimap"), tip = "Our map stands in for Blizzard's minimap. Off: Blizzard's minimap as usual." },
	{ key = "replace.worldmap", section = "general", label = "Replace world map", kind = "check", get = function() return Replaced("worldmap") end,
		set = Replace("worldmap"), tip = "M opens our map in place of Blizzard's world map. Off: M opens Blizzard's world map as usual." },
	{ key = "general.follow", section = "general", label = "Follow you", kind = "check", get = function() return UI.Camera.follow == true end,
		set = function(on) UI.Motion.SetFollow(on, true) end,
		tip = "Keeps the map centred on you. Drag the map to look about; it glides back to you when left alone." },
	{ key = "general.button", section = "general", label = "Minimap button", kind = "check", get = function() return UI.saved.button == true end,
		set = function(on) if (UI.saved.button == true) ~= on then UI.Icon() end end, tip = "The button on Blizzard's minimap, for when MagicMap is switched off." },
	{ key = "general.cluster", section = "general", label = "Group icons", kind = "check", get = function() return UI.saved.cluster ~= false end,
		set = function(on) UI.saved.cluster = on end,
		tip = "Where icons crowd together, one small pill: click it to see them all. Its tunables are under Grouping." },
	{ key = "general.resetpos", section = "general", label = "Reset window position", kind = "button", run = function() UI.BigMap.Reset() end,
		tip = "Puts the map window back on the minimap's spot." },

	{ key = "labels.scale", section = "map", label = "Label size", kind = "slider", min = 0.7, max = 1.5, step = 0.1, pct = true,
		default = 1, apply = function(v) UI.Labels.SetScale(v) end, tip = "The zone and subzone names' size." },
	{ key = "labels.subScale", section = "map", label = "Subzone size", kind = "slider", min = 0.7, max = 1.5, step = 0.1, pct = true,
		default = 1, apply = function(v) UI.Labels.SetSubScale(v) end, tip = "The subzone names' size, on top of the label size." },
	{ key = "labels.subAlpha", section = "map", label = "Subzone opacity", kind = "slider", min = 0.2, max = 1, step = 0.05, pct = true,
		default = 0.6, apply = function(v) UI.Labels.SetSubAlpha(v) end, tip = "How solid the subzone names are." },
	{ key = "borders.alpha", section = "map", label = "Border opacity", kind = "slider", min = 0.2, max = 1.3, step = 0.1, pct = true,
		default = 1, apply = function(v) UI.Borders.SetLook(v, nil) end, tip = "How solid the zone and subzone borders are (100%: as designed)." },
	{ key = "borders.width", section = "map", label = "Border width", kind = "slider", min = 0.5, max = 2, step = 0.1, pct = true,
		default = 1, apply = function(v) UI.Borders.SetLook(nil, v) end, tip = "How thick the zone and subzone borders are (100%: as designed)." },
	{ key = "arrow.scale", section = "map", label = "Your arrow", kind = "slider", min = 0.6, max = 1.6, step = 0.1, pct = true,
		default = 1, apply = function(v) UI.You.SetArrowScale(v) end, tip = "Your arrow's size." },
	{ key = "pills.alpha", section = "map", label = "Info pill backing", kind = "slider", min = 0, max = 0.8, step = 0.05, pct = true,
		default = 0.25, apply = function(v) UI.Controls.SetPillAlpha(v) end,
		tip = "How dark the backing of the map's pills (the tracked distance, the quest) is." },
	{ key = "interiors.dim", section = "map", label = "Indoor dimming", kind = "slider", min = 0.3, max = 0.9, step = 0.05, pct = true,
		default = 0.65, apply = function(v) UI.Interiors.SetDim(v) end,
		tip = "How dark the terrain is under a building's indoor map, while you're inside and the map is small." },
	{ key = "interiors.zoom", section = "map", label = "Indoor auto-zoom", kind = "check", default = true,
		tip = "Walking into a small building (a house, an inn) zooms the small map in; leaving zooms back." },

	{ key = "sea.on", section = "map", label = "Ocean", kind = "check", default = true,
		apply = function(v) UI.Sea.Set(v) end, tip = "A coloured ocean round the land, where Blizzard's map is near-black." },
	{ key = "repaint.on", section = "map", label = "Repair broken map art", kind = "check", default = true,
		apply = function(v) UI.Repaint.Set(v) end,
		tip = "Paints over the flat, unfinished blocks in Blizzard's map with AI-generated pictures. Only on the game build they were checked against: on another, the map stays as Blizzard's until MagicMap updates." },

	{ key = "icons.scale", section = "icons", label = "Icon size", kind = "slider", min = 0.6, max = 1.6, step = 0.1, pct = true,
		default = 1.2, apply = function(v) UI.Pins.SetScale(v) end,
		tip = "Every icon on the map: quests, places, rares, the lot (a group's pill keeps its size)." },
	{ key = "quests.scale", section = "icons", label = "Quest icon size", kind = "slider", min = 0.7, max = 1.6, step = 0.1, pct = true,
		default = 1, apply = function(v) UI.Quests.SetScale(v) end, tip = "The quests' icons, on top of the icon size." },
	{ key = "ring.size", section = "icons", label = "Focus ring size", kind = "slider", min = 0.8, max = 1.6, step = 0.05, pct = true,
		default = 1.45, apply = function(v) UI.Pins.SetGlow("size", v) end,
		tip = "The ring round what you track (the quest you follow, a tracked pin)." },
	{ key = "ring.alpha", section = "icons", label = "Focus ring opacity", kind = "slider", min = 0.1, max = 1, step = 0.05, pct = true,
		default = 0.25, apply = function(v) UI.Pins.SetGlow("alpha", v) end, tip = "How solid the ring round what you track is." },
	{ key = "ring.color", section = "icons", label = "Focus ring colour", kind = "pick", default = function() return RingColors()[1][1] end,
		options = Names(RingColors), apply = function(v) UI.Pins.SetGlow("color", v) end, tip = "The ring's colour." },

	{ key = "path.style", section = "path", label = "Style", kind = "pick", default = PathDefault("style"),
		options = { { "Dotted", "dotted" }, { "Dashed", "dashed" }, { "Solid", "solid" } },
		tip = "How the line to what you track is drawn." },
	{ key = "path.weight", section = "path", label = "Weight", kind = "slider", min = 1, max = 4, step = 0.2, -- (Path's range; its default 1 lies on the grid: an open mustn't save a snap)
		default = PathDefault("weight"), fmt = "%.1f px", tip = "How thick the line is." },
	{ key = "path.color", section = "path", label = "Colour", kind = "pick", default = ColorDefault, options = ColorOptions,
		tip = "The line's colour." },
	{ key = "path.glow", section = "path", label = "Glow", kind = "check", default = PathDefault("glow"),
		tip = "A soft glow along the line, so it reads on any map." },
	{ key = "path.breath", section = "path", label = "Breathing", kind = "check", default = PathDefault("breath"),
		tip = "The line slowly brightens and dims." },
	{ key = "path.opacity", section = "path", label = "Opacity", kind = "slider", min = 0.2, max = 1, step = 0.05, pct = true,
		default = PathDefault("opacity"), tip = "How solid the line is." },
	{ key = "path.edge", section = "path", label = "Outline", kind = "check", default = PathDefault("edge"),
		tip = "A darker edge under the line, so it reads on pale ground." },
	{ key = "path.edgeColor", section = "path", label = "Outline colour", kind = "pick", default = PathDefault("edgeColor"),
		options = EdgeOptions, tip = "The outline's colour." },

	{ key = "areas.fFill", section = "areas", label = "Followed fill", kind = "slider", min = 0, max = 255, step = 1, of = 255,
		default = AreaDefault("fFill"), tip = "How solid the fill of the quest you follow is." },
	{ key = "areas.fEdge", section = "areas", label = "Followed edge", kind = "slider", min = 0, max = 255, step = 1, of = 255,
		default = AreaDefault("fEdge"), tip = "How solid the edge of the quest you follow is." },
	{ key = "areas.fWidth", section = "areas", label = "Followed width", kind = "slider", min = 0.2, max = 1.5, step = 0.1,
		default = AreaDefault("fWidth"), fmt = "%.1f", tip = "How thick the edge of the quest you follow is." },
	{ key = "areas.oFill", section = "areas", label = "Others' fill", kind = "slider", min = 0, max = 255, step = 1, of = 255,
		default = AreaDefault("oFill"), tip = "How solid the fill of the other quests' areas is." },
	{ key = "areas.oEdge", section = "areas", label = "Others' edge", kind = "slider", min = 0, max = 255, step = 1, of = 255,
		default = AreaDefault("oEdge"), tip = "How solid the edge of the other quests' areas is (a gather area's a little less)." },
	{ key = "areas.oWidth", section = "areas", label = "Others' width", kind = "slider", min = 0.2, max = 1.5, step = 0.1,
		default = AreaDefault("oWidth"), fmt = "%.1f", tip = "How thick the edge of the other quests' areas is." },
	{ key = "areas.hFill", section = "areas", label = "Hover fill", kind = "slider", min = 0, max = 255, step = 1, of = 255,
		default = AreaDefault("hFill"), tip = "How much an area under the cursor (or its pin) lifts its fill." },
	{ key = "areas.hEdge", section = "areas", label = "Hover edge", kind = "slider", min = 0, max = 255, step = 1, of = 255,
		default = AreaDefault("hEdge"), tip = "How solid the edge of an area under the cursor (or its pin) is." },

	{ key = "group.range", section = "group", label = "Distance", kind = "slider", min = 16, max = 40, step = 4, cluster = "range",
		fmt = "%d px", tip = "How close icons' centres must be to group." },
	{ key = "group.reach", section = "group", label = "Reach", kind = "slider", min = 1, max = 6, step = 1, cluster = "reach",
		fmt = "%dx", tip = "How far a group grows from its first icon, by neighbours of neighbours, in distances." },
	{ key = "group.min", section = "group", label = "Smallest group", kind = "slider", min = 2, max = 5, step = 1, cluster = "min",
		fmt = "%d icons", tip = "Fewer icons than this stay apart." },
	{ key = "group.slots", section = "group", label = "Icons in a pill", kind = "slider", min = 2, max = 4, step = 1, cluster = "slots",
		fmt = "%d", tip = "A pill's slots: every icon if they fit, else one fewer and \"+N\"." },
	{ key = "group.alpha", section = "group", label = "Group pill backing", kind = "slider", min = 0, max = 0.7, step = 0.05, pct = true,
		cluster = "alpha", tip = "How dark the pill behind grouped icons is." },

	{ key = "diag.debug", section = "diag", label = "Debug info in title", kind = "check", get = function() return UI.saved.debug == true end,
		set = Slash("debug"), tip = "Tile, zoom and layout timings next to the zone name." },
	{ key = "diag.indoor", section = "diag", label = "Indoor maps report", kind = "check",
		get = function() return Model.minimap.indoorDebug == true end, set = Slash("indoor"),
		tip = "Says in chat which building and room you're in, each time either changes." },
	{ key = "diag.record", section = "diag", label = "Record 10 seconds", kind = "button", run = Slash("perf"),
		tip = "Times every part of MagicMap while you play, then prints a summary in chat." },
	{ key = "diag.top", section = "diag", label = "Compare with other addons", kind = "button", run = Slash("perf top"),
		tip = "Prints in chat how MagicMap's cost compares with other addons'." },
	{ key = "diag.mem", section = "diag", label = "Memory breakdown", kind = "button", run = Slash("perf mem"),
		tip = "Prints in chat where MagicMap's memory is." },
}
local BY_KEY = {}
for _, k in ipairs(KEYS) do BY_KEY[k.key] = k end

local function Default(k)
	local d = k.default
	if type(d) == "function" then return d() end
	return d
end

local function Options(k)
	local o = k.options
	if type(o) == "function" then return o() end
	return o
end

---------------------------------------------------------------------------
-- The values
---------------------------------------------------------------------------

function Feel.Get(key)
	local k = assert(BY_KEY[key], "Feel.Get: no setting " .. tostring(key))
	if k.get then return k.get() end
	if k.cluster then return UI.Cluster.Get(k.cluster) end
	local t = UI.saved and UI.saved.feel -- (nil before ui/View.lua loads: Path.lua's first Apply at load)
	local v = t and t[key]
	if v == nil then v = Default(k) end
	return v
end

local applied = {} -- key -> the value its apply last took (set only on change)
local function Apply(k, v)
	if not k.apply or applied[k.key] == v then return end
	applied[k.key] = v
	k.apply(v)
end

function Feel.Set(key, v)
	local k = assert(BY_KEY[key], "Feel.Set: no setting " .. tostring(key))
	if k.set then return k.set(v) end -- (kept by its owner: no rev)
	if k.cluster then
		UI.Cluster.Set(k.cluster, v)
	else
		local saved = UI.saved
		local t = saved.feel or {}
		if v == Default(k) then t[key] = nil else t[key] = v end
		saved.feel = next(t) and t or nil
		Apply(k, v)
	end
	Feel.rev = Feel.rev + 1
end

-- The saved part loaded (ui/View.lua's load, at login): rev moves, so what read the looks before it (the line, the
-- areas) reads them again, and each OnLoad fn runs then, in login's grace (the line's restyle: 640 regions).
local loaded = {}
function Feel.OnLoad(fn) loaded[#loaded + 1] = fn end
function Feel.Loaded()
	Feel.rev = Feel.rev + 1
	for _, fn in ipairs(loaded) do fn() end
end

-- The map's setters given the saved values, each time the map shows (the saved part is loaded by then;
-- each setter only when its value differs from what it last took).
UI.Window.frame:HookScript("OnShow", Runtime.Wrap("feel: shown", function()
	for _, k in ipairs(KEYS) do
		if k.apply then Apply(k, Feel.Get(k.key)) end
	end
end))

---------------------------------------------------------------------------
-- The dialog
---------------------------------------------------------------------------

local SIDE_W, SIDE_ROW = 132, 28 -- px: the sidebar's width, a category's row
local PAD, HEADER, ROW, TITLE = 14, 26, 26, 24 -- px: the frame's margin, its header bar, a row, a page's title
local PAGE_X = PAD + SIDE_W + 12 -- the page's left edge
local WIDTH = PAGE_X + 340 + PAD
local LABEL_W, SLIDER_W, PICK_W, RESET_W = 124, 120, 120, 64
local THUMB = "Interface\\Buttons\\UI-SliderBar-Button-Horizontal"
local BOX = "Interface\\Buttons\\UI-CheckBox-"

Feel.widgets = {} -- key -> its row's widgets: { k, slider | check | button, value (what it shows), text? }
Feel.resets = {} -- page -> its Reset button
Feel.pages = {} -- page -> its frame, once built
local frame, built, current

-- A value on its step, from its minimum (a slider lands between steps while dragged).
local function Snap(k, v)
	v = k.min + math.floor((v - k.min) / k.step + 0.5) * k.step -- /: never 0 (every slider in KEYS has a step)
	return math.floor(v * 1000 + 0.5) / 1000
end

local function Shown(k, v)
	if k.of then return math.floor(v * 100 / k.of + 0.5) .. "%" end -- /: never 0 (of is 255)
	if k.pct then return math.floor(v * 100 + 0.5) .. "%" end
	return string.format(k.fmt or "%s", v)
end

local function OptionLabel(k, v)
	for _, o in ipairs(Options(k)) do
		if o[2] == v then return o[1] end
	end
	return tostring(v)
end

-- A row's widgets set from its value: only what differs from what they show.
local function Refresh(w)
	local k = w.k
	if k.kind == "button" then return end
	local v = Feel.Get(k.key)
	if w.value == v then return end
	w.value = v
	if w.slider then
		w.slider:SetValue(v) -- (OnValueChanged sets the text)
	elseif w.check then
		w.check:SetChecked(v)
	else
		w.button:SetText(OptionLabel(k, v))
	end
end

-- The widgets of the pages built (a page not built yet is made from the values).
local function RefreshAll(section)
	for _, k in ipairs(KEYS) do
		local w = Feel.widgets[k.key]
		if w and (not section or k.section == section) then Refresh(w) end
	end
end

function Feel.Reset(section)
	for _, k in ipairs(KEYS) do
		if k.section == section and not k.get and k.kind ~= "button" then
			Feel.Set(k.key, k.cluster and UI.Cluster.DEFAULTS[k.cluster] or Default(k))
		end
	end
	if built then RefreshAll(section) end
end

function Feel.ResetAll()
	for _, p in ipairs(PAGES) do Feel.Reset(p.key) end
end

-- Every script of ours is wrapped (timed per name, isolated: spike-bugs P6).
local function Script(f, name, what, fn) f:SetScript(name, Runtime.Wrap(what, fn)) end

-- A row's tooltip: white title, gold body (as the gear's rows: ui/Menus.lua).
local function Tipped(f, k)
	Script(f, "OnEnter", "feel: tip", function()
		GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
		GameTooltip:SetText(k.label, 1, 1, 1)
		GameTooltip:AddLine(k.tip, 1, 0.82, 0, true)
		GameTooltip:Show()
	end)
	Script(f, "OnLeave", "feel: tip", function() GameTooltip:Hide() end)
end

local function Text(parent, font, text)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFontObject(font)
	fs:SetText(text)
	return fs
end

local function PanelButton(parent, text, w)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(w, 22)
	b:SetText(text)
	return b
end

local function SetValue(w, v)
	if Feel.Get(w.k.key) ~= v then Feel.Set(w.k.key, v) end
	w.value = v
end

local function AddSlider(row, w, k)
	local s = CreateFrame("Slider", nil, row)
	s:SetPoint("LEFT", row, "LEFT", LABEL_W, 0)
	s:SetSize(SLIDER_W, 16)
	s:SetOrientation("HORIZONTAL")
	s:SetMinMaxValues(k.min, k.max)
	s:SetValueStep(k.step)
	s:SetObeyStepOnDrag(true)
	s:SetThumbTexture(THUMB)
	s:GetThumbTexture():SetSize(16, 16)
	local track = s:CreateTexture(nil, "BACKGROUND")
	track:SetColorTexture(0, 0, 0, 0.6)
	track:SetPoint("LEFT", s, "LEFT", 0, 0)
	track:SetPoint("RIGHT", s, "RIGHT", 0, 0)
	track:SetHeight(6)
	local text = Text(row, GameFontHighlightSmall, "")
	text:SetPoint("LEFT", s, "RIGHT", 8, 0)
	w.slider, w.text = s, text
	Script(s, "OnValueChanged", "feel: slide", function(_, v)
		v = Snap(k, v)
		local shown = Shown(k, v)
		if w.shown ~= shown then
			w.shown = shown
			text:SetText(shown)
		end
		SetValue(w, v)
	end)
	Tipped(s, k)
end

local function AddCheck(row, w, k)
	local c = CreateFrame("CheckButton", nil, row)
	c:SetPoint("LEFT", row, "LEFT", LABEL_W - 2, 0)
	c:SetSize(24, 24)
	c:SetNormalTexture(BOX .. "Up")
	c:SetPushedTexture(BOX .. "Down")
	c:SetHighlightTexture(BOX .. "Highlight")
	c:SetCheckedTexture(BOX .. "Check")
	w.check = c
	Script(c, "OnClick", "feel: check", function() SetValue(w, c:GetChecked()) end)
	Tipped(c, k)
end

-- A dropdown: the client's menu (ui/Menus.lua's), a radio per option; its pick wrapped, as the gear's.
local Pick = Runtime.Wrap("feel: pick", function(w, v)
	SetValue(w, v)
	w.button:SetText(OptionLabel(w.k, v))
end)
local function AddPick(row, w, k)
	local b = PanelButton(row, "", PICK_W)
	b:SetPoint("LEFT", row, "LEFT", LABEL_W, 0)
	w.button = b
	Script(b, "OnClick", "feel: menu", function()
		UI.Menus.Show(b, function(_, root)
			for _, o in ipairs(Options(k)) do
				local v = o[2]
				root:CreateRadio(o[1], function() return Feel.Get(k.key) == v end, function()
					Pick(w, v)
					return MenuResponse.Close
				end)
			end
		end)
	end)
	Tipped(b, k)
end

-- An action: a button of its label's text, at the row's left.
local function AddButton(row, w, k)
	local b = PanelButton(row, k.label, 190)
	b:SetPoint("LEFT", row, "LEFT", 2, 0)
	w.button = b
	Script(b, "OnClick", "feel: action", k.run)
	Tipped(b, k)
end

-- A page's frame, made on its first showing: its title and Reset (where it has looks to reset), then its rows.
local function BuildPage(p)
	local page = CreateFrame("Frame", nil, frame)
	page:SetPoint("TOPLEFT", frame, "TOPLEFT", PAGE_X, -HEADER - 6)
	page:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -HEADER - 6)
	page:SetHeight(TITLE + ROW * 10)
	page:Hide()
	Text(page, GameFontNormal, p.title):SetPoint("TOPLEFT", page, "TOPLEFT", 0, -4)
	local y, resettable = -TITLE, false
	for _, k in ipairs(KEYS) do
		if k.section == p.key then
			local row = CreateFrame("Frame", nil, page)
			row:SetPoint("TOPLEFT", page, "TOPLEFT", 0, y)
			row:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, y)
			row:SetHeight(ROW)
			row:EnableMouse(true)
			Tipped(row, k)
			local w = { k = k }
			Feel.widgets[k.key] = w
			if k.kind == "button" then
				AddButton(row, w, k)
			else
				Text(row, GameFontHighlightSmall, k.label):SetPoint("LEFT", row, "LEFT", 4, 0)
				if k.kind == "slider" then AddSlider(row, w, k)
				elseif k.kind == "check" then AddCheck(row, w, k)
				else AddPick(row, w, k) end
				resettable = resettable or not k.get
			end
			y = y - ROW
		end
	end
	if resettable then
		local reset = PanelButton(page, "Reset", RESET_W)
		reset:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
		Script(reset, "OnClick", "feel: reset", function() Feel.Reset(p.key) end)
		Feel.resets[p.key] = reset
	end
	Feel.pages[p.key] = page
	return page
end

-- The category chosen: its page shown (built if need be, set from the values), the last one's hidden, kept.
local function Select(key)
	local p = BY_PAGE[key] or PAGES[1]
	key = p.key
	if current and current ~= key then
		Feel.pages[current]:Hide()
		local old = BY_PAGE[current]
		old.tab.sel:Hide()
		old.tab.text:SetFontObject(GameFontHighlight)
	end
	current = key
	local page = Feel.pages[key] or BuildPage(p)
	for _, k in ipairs(KEYS) do
		if k.section == key then Refresh(Feel.widgets[k.key]) end
	end
	page:Show()
	p.tab.sel:Show()
	p.tab.text:SetFontObject(GameFontNormal)
	if UI.saved then UI.saved.feelPage = key end
end
Feel.Select = function(key) if not built then Feel.Open(key) else Select(key) end end

-- A category's row in the sidebar: its icon and name, lit while chosen, a highlight under the cursor.
local function AddTab(p, y)
	local b = CreateFrame("Button", nil, frame)
	b:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, y)
	b:SetSize(SIDE_W, SIDE_ROW)
	b:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
	local sel = b:CreateTexture(nil, "BACKGROUND")
	sel:SetAllPoints(b)
	sel:SetColorTexture(1, 0.82, 0, 0.18)
	sel:Hide()
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetSize(18, 18)
	icon:SetPoint("LEFT", b, "LEFT", 6, 0)
	icon:SetTexture(p.icon)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	local text = Text(b, GameFontHighlight, p.title)
	text:SetPoint("LEFT", icon, "RIGHT", 6, 0)
	b.sel, b.text = sel, text
	Script(b, "OnClick", "feel: page", function() Select(p.key) end)
	p.tab = b
end

local function Build()
	built = true
	frame = CreateFrame("Frame", "MagicMapFeel", UIParent, "ButtonFrameTemplate")
	Feel.frame = frame
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:SetWidth(WIDTH)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
	ButtonFrameTemplate_HidePortrait(frame)
	ButtonFrameTemplate_HideButtonBar(frame)
	local title = frame.TitleText or frame.TitleContainer and frame.TitleContainer.TitleText
	if title then
		title:SetText("MagicMap Settings")
	else
		title = Text(frame, GameFontNormal, "MagicMap Settings")
		title:SetPoint("TOP", frame, "TOP", 0, -7)
	end
	if not frame.CloseButton then
		local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
		frame.CloseButton = close
	end
	Script(frame.CloseButton, "OnClick", "feel: close", function() frame:Hide() end)
	-- The header bar drags it.
	local header = CreateFrame("Frame", nil, frame)
	header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, 0)
	header:SetHeight(HEADER)
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton")
	Script(header, "OnDragStart", "feel: move", function() frame:StartMoving() end)
	Script(header, "OnDragStop", "feel: move", function() frame:StopMovingOrSizing() end)

	-- As tall as the longest page (its title and rows), the footer's Reset all under it.
	local most, count = 0, {}
	for _, k in ipairs(KEYS) do
		count[k.section] = (count[k.section] or 0) + 1
		most = math.max(most, count[k.section])
	end
	local y = -HEADER - 10
	for _, p in ipairs(PAGES) do
		AddTab(p, y)
		y = y - SIDE_ROW
	end
	local bottom = HEADER + 6 + TITLE + most * ROW + 12
	local all = PanelButton(frame, "Reset all", 96)
	all:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD)
	Script(all, "OnClick", "feel: reset", Feel.ResetAll)
	Feel.resetAll = all
	frame:SetHeight(math.max(bottom + 22 + PAD, -y + 22 + PAD))
	frame:Hide()
end

-- Opened on page (a category's key; else the last one's, or General's).
function Feel.Open(page)
	if not built then Build() end
	if not page then
		local last = UI.saved and UI.saved.feelPage
		page = BY_PAGE[last] and last or current or "general"
	end
	Select(page)
	RefreshAll()
	frame:Show()
end

function Feel.Toggle()
	if built and frame:IsShown() then frame:Hide() else Feel.Open() end
end

Command({ kind = "slash", name = "feel", help = "[page]: the settings window, hidden again if shown (pages: general, map, icons, path, areas, group, diag)",
	fn = function(arg) if built and frame:IsShown() and arg == "" then frame:Hide() else Feel.Open(BY_PAGE[arg:lower()] and arg:lower() or nil) end end })
Command({ kind = "slash", name = "settings", help = "the settings window (as /mm feel)", fn = Feel.Toggle })
