-- The Look & feel dialog (Settings > Advanced > Look & feel…, /mm feel): a small movable dialog of the
-- client's ButtonFrameTemplate (as the map window, ui/Window.lua, but kept as the client draws it:
-- header bar, close button), DIALOG strata, clamped to the screen, dragged by its header, Escape
-- closes it (game/Hooks.lua names it in UISpecialFrames). Three sections, each with a Reset, and
-- Reset all at the bottom; every change applies live:
--   Tracking line: style, weight, colour, glow, breathing, opacity. ui/Path.lua owns the values: it
--     reads Feel.Get("path.<key>") and lays out again when Feel.rev moves; its UI.Path.DEFAULTS and
--     UI.Path.COLORS (ordered presets { name, { r, g, b } }, the first the default) are read when asked,
--     never at load (Path.lua loads after this file; fallbacks until it lands). "path.color" is a preset's name.
--   Grouping: ui/Cluster.lua's five tunables, through Cluster.Get/Set (saved as UI.saved.clusterTune, as before).
--   Map: label size (ui/Labels.lua), your arrow's size (ui/You.lua), the pills' backing (ui/Controls.lua):
--     pushed to their setters on change, and again each time the map shows (the saved values, once loaded).
-- Every setting is declared once in KEYS ({ key, section, label, kind = "slider" | "check" | "pick", min, max,
-- step, default (a value, or a function), options (or a function), tip, apply? }): the dialog is built from
-- it, once, on the first open; its widgets are refreshed from the values on open and after a reset, each set
-- only when it differs. Saved in UI.saved.feel = { ["path.style"] = ... } (types/saved.lua), a key only while
-- it differs from its default, the table gone when none does. Hidden almost always: no step, nothing a frame.
-- API: Feel.Get(key), Feel.Set(key, v), Feel.Reset(section), Feel.ResetAll(), Feel.Open(), Feel.Toggle(), Feel.rev.

local _, ns = ...
local UI, Runtime = ns.UI, ns.Runtime
local Command = ns.Game.Command

local Feel = { rev = 0 }
UI.Feel = Feel

-- Until ui/Path.lua exposes its own.
local PATH_DEFAULTS = { style = "dashed", weight = 2, color = "Parchment", glow = true, breath = true, opacity = 0.9 }
local PATH_COLORS = { { "Parchment", { r = 1, g = 0.9, b = 0.7 } } }
local function PathDefaults() return UI.Path and UI.Path.DEFAULTS or PATH_DEFAULTS end
local function PathColors() return UI.Path and UI.Path.COLORS or PATH_COLORS end
local function PathDefault(k) return function() return PathDefaults()[k] end end
-- The default colour: Path's, if it names a preset; else the first preset.
local function ColorDefault()
	local d = PathDefaults().color
	return type(d) == "string" and d or PathColors()[1][1]
end
local function ColorOptions()
	local out = {}
	for i, c in ipairs(PathColors()) do out[i] = { c[1], c[1] } end
	return out
end

local SECTIONS = { { key = "path", title = "Tracking line" }, { key = "group", title = "Grouping" }, { key = "map", title = "Map" } }

-- pct: shown as a percentage. cluster: ui/Cluster.lua's tunable it is (held there, not in saved.feel).
-- apply(v): its setter, called on change and each time the map shows.
local KEYS = {
	{ key = "path.style", section = "path", label = "Style", kind = "pick", default = PathDefault("style"),
		options = { { "Dotted", "dotted" }, { "Dashed", "dashed" }, { "Solid", "solid" } },
		tip = "How the line to what you track is drawn." },
	{ key = "path.weight", section = "path", label = "Weight", kind = "slider", min = 1, max = 4, step = 0.2, -- (Path's range; its default 1.6 lies on the grid: an open mustn't save a snap)
		default = PathDefault("weight"), fmt = "%.1f px", tip = "How thick the line is." },
	{ key = "path.color", section = "path", label = "Colour", kind = "pick", default = ColorDefault, options = ColorOptions,
		tip = "The line's colour." },
	{ key = "path.glow", section = "path", label = "Glow", kind = "check", default = PathDefault("glow"),
		tip = "A soft glow along the line, so it reads on any map." },
	{ key = "path.breath", section = "path", label = "Breathing", kind = "check", default = PathDefault("breath"),
		tip = "The line slowly brightens and dims." },
	{ key = "path.opacity", section = "path", label = "Opacity", kind = "slider", min = 0.2, max = 1, step = 0.05, pct = true,
		default = PathDefault("opacity"), tip = "How solid the line is." },

	{ key = "group.range", section = "group", label = "Distance", kind = "slider", min = 16, max = 40, step = 4, cluster = "range",
		fmt = "%d px", tip = "How close icons' centres must be to group." },
	{ key = "group.reach", section = "group", label = "Reach", kind = "slider", min = 1, max = 6, step = 1, cluster = "reach",
		fmt = "%dx", tip = "How far a group grows from its first icon, by neighbours of neighbours, in distances." },
	{ key = "group.min", section = "group", label = "Smallest group", kind = "slider", min = 2, max = 5, step = 1, cluster = "min",
		fmt = "%d icons", tip = "Fewer icons than this stay apart." },
	{ key = "group.slots", section = "group", label = "Icons in a pill", kind = "slider", min = 2, max = 4, step = 1, cluster = "slots",
		fmt = "%d", tip = "A pill's slots: every icon if they fit, else one fewer and \"+N\"." },
	{ key = "group.alpha", section = "group", label = "Pill background", kind = "slider", min = 0, max = 0.7, step = 0.05, pct = true,
		cluster = "alpha", tip = "How dark the pill behind grouped icons is." },

	{ key = "labels.scale", section = "map", label = "Label size", kind = "slider", min = 0.7, max = 1.5, step = 0.1, pct = true,
		default = 1, apply = function(v) UI.Labels.SetScale(v) end, tip = "The zone and subzone names' size." },
	{ key = "arrow.scale", section = "map", label = "Your arrow", kind = "slider", min = 0.6, max = 1.6, step = 0.1, pct = true,
		default = 1, apply = function(v) UI.You.SetArrowScale(v) end, tip = "Your arrow's size." },
	{ key = "pills.alpha", section = "map", label = "Pill background", kind = "slider", min = 0, max = 0.8, step = 0.05, pct = true,
		default = 0.4, apply = function(v) UI.Controls.SetPillAlpha(v) end,
		tip = "How dark the backing of the map's pills (the tracked distance, the quest) is." },
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

local WIDTH, PAD, HEADER, ROW, TITLE = 340, 14, 26, 26, 24 -- px: the frame's width, its margin, its header bar, a row, a section's title
local LABEL_W, SLIDER_W, PICK_W, RESET_W = 118, 120, 120, 64
local THUMB = "Interface\\Buttons\\UI-SliderBar-Button-Horizontal"
local BOX = "Interface\\Buttons\\UI-CheckBox-"

Feel.widgets = {} -- key -> its row's widgets: { k, slider | check | button, value (what it shows), text? }
Feel.resets = {} -- section -> its Reset button
local frame, built

-- A value on its step, from its minimum (a slider lands between steps while dragged).
local function Snap(k, v)
	v = k.min + math.floor((v - k.min) / k.step + 0.5) * k.step -- /: never 0 (every slider in KEYS has a step)
	return math.floor(v * 1000 + 0.5) / 1000
end

local function Shown(k, v)
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

local function RefreshAll(section)
	for _, k in ipairs(KEYS) do
		if not section or k.section == section then Refresh(Feel.widgets[k.key]) end
	end
end

function Feel.Reset(section)
	for _, k in ipairs(KEYS) do
		if k.section == section then Feel.Set(k.key, k.cluster and UI.Cluster.DEFAULTS[k.cluster] or Default(k)) end
	end
	if built then RefreshAll(section) end
end

function Feel.ResetAll()
	for _, s in ipairs(SECTIONS) do Feel.Reset(s.key) end
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
		title:SetText("Look & feel")
	else
		title = Text(frame, GameFontNormal, "Look & feel")
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

	local y = -HEADER - 6
	for _, s in ipairs(SECTIONS) do
		local heading = Text(frame, GameFontNormal, s.title)
		heading:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, y - 4)
		local reset = PanelButton(frame, "Reset", RESET_W)
		reset:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, y)
		Script(reset, "OnClick", "feel: reset", function() Feel.Reset(s.key) end)
		Feel.resets[s.key] = reset
		y = y - TITLE
		for _, k in ipairs(KEYS) do
			if k.section == s.key then
				local row = CreateFrame("Frame", nil, frame)
				row:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, y)
				row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, y)
				row:SetHeight(ROW)
				row:EnableMouse(true)
				Tipped(row, k)
				local label = Text(row, GameFontHighlightSmall, k.label)
				label:SetPoint("LEFT", row, "LEFT", 4, 0)
				local w = { k = k }
				Feel.widgets[k.key] = w
				if k.kind == "slider" then AddSlider(row, w, k)
				elseif k.kind == "check" then AddCheck(row, w, k)
				else AddPick(row, w, k) end
				y = y - ROW
			end
		end
		y = y - 6
	end
	local all = PanelButton(frame, "Reset all", 96)
	all:SetPoint("TOP", frame, "TOP", 0, y)
	Script(all, "OnClick", "feel: reset", Feel.ResetAll)
	Feel.resetAll = all
	frame:SetHeight(-y + 22 + PAD)
	frame:Hide()
end

function Feel.Open()
	if not built then Build() end
	RefreshAll()
	frame:Show()
end

function Feel.Toggle()
	if built and frame:IsShown() then frame:Hide() else Feel.Open() end
end

Command({ kind = "slash", name = "feel", help = "the Look & feel dialog (the tracking line, grouping, the map)", fn = Feel.Toggle })
