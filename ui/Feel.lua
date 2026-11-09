-- MagicMap's settings: the values every part of the map reads, and the window that sets them (gear -> Settings…,
-- /mm feel, /mm settings; Game menu -> Options -> AddOns -> MagicMap opens it too: game/Options.lua).
--
-- Each feature declares its own settings next to its code, and the window is built only from what's declared:
--   Feel.Page({ key, title, icon, order, tip, sections = { "Header", ... } })  a page of the sidebar (by order)
--   Feel.Add(page, section, { setting, ... })  settings on a page, under a section's header (nil: above them all)
-- A setting is { key, kind, label, tip, default, ... }: its key is the name it's saved and read by ("<area>.<name>",
-- never renamed: players' saved values are under it); default a value, or a function (read when asked: a value
-- another setting gives, an inherited one; until it's set, its row and apply follow that setting); and by its kind:
--   toggle  a checkbox: true or false
--   slider  min, max, step (default on the grid); its live value beside it as pct (a share, as %), of (a part of
--           of, as %), fmt (a string.format pattern, or a function of the value); steppers either side
--   select  a dropdown, options = { { label, value, icon? } } (or a function giving them; an icon is a file, a
--           FileDataID or "A:<atlas>")
--   color   colors = { { name, { r, g, b } } } as swatches, the first the list's own; the value a preset's name
--           or, through the client's colour picker (Custom…; custom = false: none), "#rrggbb" (Feel.RGB reads either)
--   list    options as select's: choose several and, ordered = true, their order (arrows); the value the chosen
--           values joined by commas, in order (Feel.List gives them)
--   button  run(): an action, no value
-- and, any kind: apply(v), its setter, called on a change and each time the map shows (the saved value, once
-- loaded; only when it differs from what it last took; each wrapped: one failing can't stop the rest); get()/set(v):
-- a value its owner keeps (UI.saved, UI.Replace...), not saved here; keep = true: a reset leaves it as it is (an
-- owner's switch); when = a key (shown while that setting is on) or a function: a row shown only then (indented
-- under the row it depends on, in its section; a header shown while a row under it is); under = a key: the row stands
-- under that one (listed right after it, a level in), shown while it's opened (its plus: closed at first, kept for the
-- session); art = function(row, last): a region drawn at the label's left (given the one it made before; drawn again
-- as the page refreshes and on a change on its page). Its row: its label, its
-- control, and an undo mark while it differs from its default (a click puts the default back); its tooltip the
-- label, the tip and the default. Rows made from a list are a loop of Feel.Add's entries (keys "<area>.<id>.<name>").
-- The rule (tools/tests/test_lookfeel.py test_settings_declared holds it): every value the code reads or sets
-- through Feel by name, and every key saved in UI.saved.feel, is declared; every declared setting has a page, a
-- label, a tip and (but a button) a default its control offers. A new feature adds its settings with Feel.Add in its
-- own file (docs/development.md "How to add a setting"), never a frame of its own here.
--
-- The values: Feel.Get(key) (safe before the saved part loads, and for a key not declared yet: the saved value,
-- else nil), Feel.Set(key, v), Feel.Default(key), Feel.rev (moves on every change: a reader compares it to restyle),
-- Feel.Reset(page), Feel.ResetAll(), Feel.List(key), Feel.RGB(colors, v, default), Feel.Entry(key), Feel.Entries()
-- and Feel.Pages() (what's declared), Feel.OnLoad(fn) (fn runs once the saved part loads; Feel.Loaded() is View's:
-- it drops a saved value of the wrong type, a slider's out of range, an option or colour no longer offered). A look
-- is saved in UI.saved.feel = { ["path.style"] = ... } (types/saved.lua), a key only while it differs from its
-- default, the table gone when none does. This file loads right after ui/Window.lua, so every other UI file may
-- declare; the window is built on its first open, and a page or setting declared after that joins it.
--
-- The pages (order; who declares their settings), each with one job:
--   General (10), what MagicMap replaces, its window, how the map moves. Blizzard's maps: Replace minimap, Replace
--     world map (ui/Replace.lua), Minimap button (ui/View.lua); Map window: Buttons at rest (ui/Controls.lua), Reset
--     window position (ui/BigMap.lua); Movement: Follow you, Return to you, Return after, Zoom per notch (ui/Motion.lua).
--   Map (20), what the map shows. Names: Label size, Zone name opacity, Subzone size, Subzone opacity
--     (ui/Labels.lua); Ground: Ocean (ui/Sea.lua), Repair broken map art (ui/Repaint.lua); Indoors: Indoor dimming,
--     Indoor auto-zoom (ui/Interiors.lua); You: Your arrow (ui/You.lua).
--   Title (25, ui/Title.lua). At rest, On hover (the pieces, chosen and ordered); Format: Clock (while a time is
--     chosen).
--   Pins (30, ui/PinTypes.lua), every pin type the map draws. Show pins, Pin size, Pin opacity, On the big map,
--     Zoomed in from; By type: each family's row (Quests, Rares & treasures, Party, Places, Addons, Other: Size,
--     Opacity, On the big map), each type's under it (Size, Opacity, On the big map, Icon,
--     Group), declared by the files that draw them.
--   Resources (35). Tracking: Keep tracking (ui/Resources.lua).
--   Quest pill (40, ui/Controls.lua). Shows, Says (the pieces, chosen and ordered), Progress bar;
--     Look: Backing, Size.
--   Tracking (45), how the way is shown. Arrow (Track's): Size, Opacity, Distance (ui/Guide.lua); Path to: Frame the
--     way (ui/Path.lua).
--   Pathing (50, ui/Path.lua), Path to's line. Line: Style, Weight, Colour, Opacity; Effects: Glow, Breathing, Breath
--     pace; Outline: Outline, Outline colour.
--   Quest areas (60, ui/Areas.lua). Followed quest: Fill, Edge, Edge width; Other quests: the same; Under the
--     cursor: Fill lift, Edge.
--   (Grouping's settings, ui/Cluster.lua, and Keep tracking's, ui/Resources.lua, have no page: their defaults, the
--     gear's Keep tracking row, and /mm feel's key.)
--   Diagnostics (90, here). Debug info in title, Indoor maps report; Reports in chat: Record 10 seconds, Compare
--     with other addons, Memory breakdown (each a /mm command too).
-- Pages to come take an order between these. The sidebar has room for 14
-- before the window grows; a page longer than the window scrolls.
--
-- The window: a movable dialog of the client's ButtonFrameTemplate (as the map window, ui/Window.lua, but kept as
-- the client draws it: header bar, close button), DIALOG strata, clamped to the screen, dragged by its header,
-- Escape closes it (game/Hooks.lua names it in UISpecialFrames). The sidebar's pages (icon and title, the chosen
-- one lit, its job as its tooltip) and the chosen page on the right: its title over the client's divider, its
-- Reset, its rows under their sections' headers (made on its first showing, refreshed from the values on each),
-- the wheel or its bar scrolling it. Reset all at the bottom; it, a page's Reset and a row's undo mark lit only
-- while there's something to reset. The last page is kept (UI.saved.feelPage). Hidden almost always: no step,
-- nothing a frame. Its controls are the client's own: the settings panel's checkbox and slider with steppers
-- (checkbox-minimal, Minimal_SliderBar_*: the UI-CheckBox and slider-bar files where a client lacks them), its
-- dropdown (WowStyle1DropdownTemplate, the client's menu), ColorSwatchTemplate and ColorPickerFrame, the undo icon,
-- the minimal scroll bar's arrows.

local _, ns = ...
local UI, Runtime, Model = ns.UI, ns.Runtime, ns.Model
local Command = ns.Game.Command
local floor = math.floor

local Feel = { rev = 0 }
UI.Feel = Feel

---------------------------------------------------------------------------
-- What's declared
---------------------------------------------------------------------------

local PAGES, BY_PAGE = {}, {} -- by order (then as declared)
local KEYS, BY_KEY = {}, {} -- every setting, as declared
local INHERIT = {} -- the settings whose default is a function: told when another changes
local OPENS, opened = {}, {} -- the rows others stand under (their key -> true); those open now (this session)
local KINDS = { toggle = true, slider = true, select = true, color = true, list = true, button = true }
local built -- the window, made on its first open
local Sidebar, Grew -- (the window's, below: a page declared once it's built)

local function ByOrder(a, b)
	if a.order ~= b.order then return a.order < b.order end
	return a.n < b.n
end

function Feel.Page(p)
	assert(type(p.key) == "string" and p.title and not BY_PAGE[p.key], "Feel.Page: a new key and a title")
	p.order, p.n, p.sections = p.order or 100, #PAGES + 1, p.sections or {}
	PAGES[#PAGES + 1] = p
	BY_PAGE[p.key] = p
	table.sort(PAGES, ByOrder)
	if built then Sidebar() end
	return p
end

-- page false: a setting with no page (kept, with its default; Reset all resets it).
function Feel.Add(page, section, list)
	for _, k in ipairs(list) do
		assert(type(k.key) == "string" and not BY_KEY[k.key], "Feel.Add: a new key")
		assert(KINDS[k.kind], "Feel.Add: unknown kind " .. tostring(k.kind) .. " (" .. k.key .. ")")
		assert(k.kind ~= "slider" or k.min and k.max and k.step and k.step > 0, "Feel.Add: a slider's min, max, step")
		k.page, k.section = page, section or false
		if k.apply then k.apply = Runtime.Wrap("feel: " .. k.key, k.apply) end -- (one failing can't stop the rest)
		KEYS[#KEYS + 1] = k
		BY_KEY[k.key] = k
		if type(k.default) == "function" then INHERIT[#INHERIT + 1] = k end
		if k.under then OPENS[k.under] = true end
		local p = BY_PAGE[page]
		if p then p.items = nil end -- (its rows laid out again, the new one with them)
	end
end

function Feel.Entry(key) return BY_KEY[key] end
function Feel.Entries() return KEYS end
function Feel.Pages() return PAGES end

local function Default(k)
	local d = k.default
	if type(d) == "function" then return d() end
	return d
end
function Feel.Default(key)
	local k = BY_KEY[key]
	return k and Default(k)
end

local function Options(k)
	local o = k.options or k.colors
	if type(o) == "function" then return o() end
	return o or {}
end

---------------------------------------------------------------------------
-- The values
---------------------------------------------------------------------------

function Feel.Get(key)
	local k = BY_KEY[key]
	if k and k.get then return k.get() end
	local t = UI.saved and UI.saved.feel -- (nil before ui/View.lua loads: a layer's load-time look)
	local v = t and t[key]
	if v == nil and k then v = Default(k) end
	return v
end

local applied = {} -- key -> the value its apply last took (set only on change)
local function Apply(k, v)
	if not k.apply or applied[k.key] == v then return end
	applied[k.key] = v
	k.apply(v)
end

local Changed -- (the window's: a row and those that depend on it shown anew)

function Feel.Set(key, v)
	local k = assert(BY_KEY[key], "Feel.Set: no setting " .. tostring(key))
	if k.set then
		if k.get() ~= v then k.set(v) end -- (kept by its owner)
	else
		local saved = UI.saved
		local t = saved.feel or {}
		if v == Default(k) then t[key] = nil else t[key] = v end
		saved.feel = next(t) and t or nil
		Apply(k, v)
	end
	for _, d in ipairs(INHERIT) do -- (one following this one, not set itself, takes its new value)
		if d ~= k and not d.get then Apply(d, Feel.Get(d.key)) end
	end
	Feel.rev = Feel.rev + 1
	if built then Changed(k, v) end
end

local function Resettable(k) return not k.keep and k.kind ~= "button" and k.default ~= nil end
local function Differs(k) return Resettable(k) and Feel.Get(k.key) ~= Default(k) end

-- (A value saved that its inherited default has since come to equal is set too: back to inheriting.)
function Feel.Reset(page)
	local t = UI.saved and UI.saved.feel
	for _, k in ipairs(KEYS) do
		if k.page == page and (Differs(k) or Resettable(k) and t and t[k.key] ~= nil) then Feel.Set(k.key, Default(k)) end
	end
end

function Feel.ResetAll()
	for _, p in ipairs(PAGES) do Feel.Reset(p.key) end
end

-- A colour setting's value as { r, g, b }: a preset's name from colors, or "#rrggbb"; else the default's, else the
-- first preset's. Returns the value it read (name or hex) and its colour.
function Feel.RGB(colors, v, default)
	if type(v) == "string" then
		local r, g, b = v:match("^#(%x%x)(%x%x)(%x%x)$")
		if r then return v, { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255 } end
		for _, c in ipairs(colors) do
			if c[1] == v then return v, c[2] end
		end
	end
	if default ~= nil and default ~= v then return Feel.RGB(colors, default) end
	return colors[1][1], colors[1][2]
end
local function Hex(r, g, b)
	return string.format("#%02x%02x%02x", floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end

-- A list setting's chosen values, in order (those still offered).
local function Offered(k)
	local set = {}
	for _, o in ipairs(Options(k)) do set[o[2]] = o end
	return set
end
local function Split(k, v)
	local out, set = {}, Offered(k)
	for item in tostring(v or ""):gmatch("[^,]+") do
		if set[item] then out[#out + 1] = item end
	end
	return out
end
function Feel.List(key)
	local k = BY_KEY[key]
	return k and Split(k, Feel.Get(key)) or {}
end

-- A saved value its setting can't take: dropped, so it's the default (a wrong type, a slider's out of range, an
-- option or colour no longer offered).
local function Valid(k, v)
	local d = Default(k)
	if d ~= nil and type(v) ~= type(d) then return false end
	if k.kind == "slider" then return v >= k.min - 1e-9 and v <= k.max + 1e-9 end
	if k.kind == "select" and type(k.options) == "table" then return Offered(k)[v] ~= nil end
	if k.kind == "color" then return Feel.RGB(Options(k), v) == v end
	return true
end

-- The saved part loaded (ui/View.lua's load, at login): what can't be is dropped; rev moves, so what read the looks
-- before it (the line, the areas) reads them again, and each OnLoad fn runs then, in login's grace.
local loaded = {}
function Feel.OnLoad(fn) loaded[#loaded + 1] = fn end
function Feel.Loaded()
	local t = UI.saved.feel
	for key, v in pairs(t or {}) do
		local k = BY_KEY[key]
		if k and (k.get or not Valid(k, v)) then t[key] = nil end
	end
	if t and not next(t) then UI.saved.feel = nil end
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
-- The window
---------------------------------------------------------------------------

local SIDE_W, SIDE_ROW, TABS = 140, 28, 14 -- px: the sidebar's width, a page's row; the pages it has room for
local PAD, HEADER, TITLE = 14, 26, 30 -- px: the frame's margin, its header bar, a page's title and divider
local ROW, LINE, HEAD, GAP = 26, 20, 22, 6 -- px: a row, a list's line, a section's header, above a header
local PAGE_X = PAD + SIDE_W + 10 -- the page's left edge
local PAGE_W, BAR = 400, 16 -- the page; its scroll bar, at its right
local CONTENT_W = PAGE_W - BAR - 4 -- the rows
local FOOT = 22 + 8 -- Reset all, under the pages
local HEIGHT = HEADER + 8 + TABS * SIDE_ROW + FOOT + PAD
local CTRL_X, INDENT = 150, 14 -- a row's control, from its left; a dependent row's label, further in
local OPEN, ART = 12, 16 -- px: a row's open mark (rows stand under it), its art
local LABEL_W = CTRL_X - 10
local SLIDER_W, VALUE_W, DROP_W, SWATCH, CUSTOM_W = 120, 46, 176, 20, 60
local UNDO = 14 -- the undo mark, at a row's right
local GOLD, WHITE = { 1, 0.82, 0 }, { 1, 1, 1 }
local THUMB = "Interface\\Buttons\\UI-SliderBar-Button-Horizontal"
local BOX = "Interface\\Buttons\\UI-CheckBox-"
local KNOB = "Interface\\Buttons\\UI-ScrollBar-Knob"
local ELLIPSIS = "\226\128\166"

Feel.widgets = {} -- key -> its row: { k, row, value (what it shows), undo, and its kind's: check | slider, text | drop | swatches | lines | button }
Feel.resets = {} -- page -> its Reset button
Feel.pages = {} -- page -> its frame, once built
local frame, current
local headers = {} -- page -> section -> its header's frame

local has = {} -- atlas -> the client has it
local function Has(atlas)
	if has[atlas] == nil then has[atlas] = C_Texture.GetAtlasInfo(atlas) ~= nil end
	return has[atlas]
end

-- Every script of ours is wrapped (timed per name, isolated: spike-bugs P6).
local function Script(f, name, what, fn) f:SetScript(name, Runtime.Wrap(what, fn)) end

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

-- An option's label, with its icon before it (ui/Tip.lua's Mark: a file or FileDataID, its border cropped, or
-- "A:<atlas>" if this client has it).
local function Label(o) return UI.Tip.Mark(o[3]) .. o[1] end

-- A value as a row shows it (a slider's beside it; the default in a tooltip).
local function Shown(k, v)
	local kind = k.kind
	if kind == "slider" then
		if type(k.fmt) == "function" then return k.fmt(v) end
		if k.of then return floor(v * 100 / k.of + 0.5) .. "%" end -- /: never 0 (of: a slider's whole, > 0)
		if k.pct then return floor(v * 100 + 0.5) .. "%" end
		return string.format(k.fmt or "%s", v)
	elseif kind == "toggle" then
		return v and "on" or "off"
	elseif kind == "color" then
		return type(v) == "string" and v:sub(1, 1) == "#" and v:upper() or tostring(v)
	elseif kind == "select" or kind == "list" then
		local out = {}
		for _, item in ipairs(kind == "list" and Split(k, v) or { v }) do
			for _, o in ipairs(Options(k)) do
				if o[2] == item then out[#out + 1] = o[1] end
			end
		end
		return #out > 0 and table.concat(out, ", ") or kind == "list" and "none" or tostring(v)
	end
	return tostring(v)
end

-- A tooltip: a description, white title, gold body, then the default in DIM (ui/Tip.lua's Describe, as the gear's
-- rows: ui/Menus.lua). Hooked, so a template's own hover (the dropdown's, a swatch's) stays.
local function Tipped(f, k, title)
	f:HookScript("OnEnter", Runtime.Wrap("feel: tip", function()
		GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
		UI.Tip.Describe(GameTooltip, title or k.label, k.tip, Resettable(k) and "Default: " .. Shown(k, Default(k)) or nil)
		GameTooltip:Show()
	end))
	f:HookScript("OnLeave", Runtime.Wrap("feel: tip", function() GameTooltip:Hide() end))
end

-- A row's value set from its control (if it differs): Set shows it on the row (Changed).
local function SetValue(w, v)
	if Feel.Get(w.k.key) ~= v then Feel.Set(w.k.key, v) end
end

-- A value on its step, from its minimum (a slider lands between steps while dragged).
local function Snap(k, v)
	v = k.min + floor((v - k.min) / k.step + 0.5) * k.step -- /: never 0 (Feel.Add asserts a slider's step > 0)
	return floor(v * 1000 + 0.5) / 1000
end

-- Toggle -------------------------------------------------------------------

local function Check(parent, size)
	local c = CreateFrame("CheckButton", nil, parent)
	c:SetSize(size, size)
	if Has("checkbox-minimal") and Has("checkmark-minimal") then -- (the client's settings panel's)
		c:SetNormalAtlas("checkbox-minimal")
		c:SetPushedAtlas("checkbox-minimal")
		c:SetHighlightAtlas("checkbox-minimal", "ADD")
		local mark = c:CreateTexture(nil, "OVERLAY")
		mark:SetAtlas("checkmark-minimal")
		mark:SetAllPoints(c)
		c:SetCheckedTexture(mark)
	else
		c:SetNormalTexture(BOX .. "Up")
		c:SetPushedTexture(BOX .. "Down")
		c:SetHighlightTexture(BOX .. "Highlight")
		c:SetCheckedTexture(BOX .. "Check")
	end
	return c
end

local function AddToggle(row, w, k)
	local c = Check(row, 26)
	c:SetPoint("LEFT", row, "TOPLEFT", CTRL_X - 4, -ROW / 2)
	w.check = c
	Script(c, "OnClick", "feel: check", function() SetValue(w, c:GetChecked()) end)
	Tipped(c, k)
end

-- Slider -------------------------------------------------------------------

local MINIMAL = { "Minimal_SliderBar_Left", "_Minimal_SliderBar_Middle", "Minimal_SliderBar_Right", "Minimal_SliderBar_Button",
	"Minimal_SliderBar_Button_Left", "Minimal_SliderBar_Button_Right" }
local function Minimal()
	for _, a in ipairs(MINIMAL) do
		if not Has(a) then return false end
	end
	return true
end

-- A stepper's look: dimmed at the end it can't pass.
local function Steppers(w, v)
	local k = w.k
	for _, b in ipairs(w.steps) do
		local on = b.dir < 0 and v > k.min + k.step / 2 or b.dir > 0 and v < k.max - k.step / 2
		if b.on ~= on then
			b.on = on
			b:SetEnabled(on)
			b:SetAlpha(on and 1 or 0.35)
		end
	end
end

local function AddSlider(row, w, k)
	local s = CreateFrame("Slider", nil, row)
	s:SetPoint("LEFT", row, "TOPLEFT", CTRL_X + 15, -ROW / 2)
	s:SetSize(SLIDER_W, 19)
	s:SetOrientation("HORIZONTAL")
	s:SetMinMaxValues(k.min, k.max)
	s:SetValueStep(k.step)
	s:SetObeyStepOnDrag(true)
	w.steps = {}
	if Minimal() then -- the client's settings slider (MinimalSliderWithSteppersTemplate's art), its steppers either side
		local thumb = s:CreateTexture(nil, "OVERLAY")
		thumb:SetAtlas("Minimal_SliderBar_Button", true)
		s:SetThumbTexture(thumb)
		local l, m, r = s:CreateTexture(nil, "BACKGROUND"), s:CreateTexture(nil, "BACKGROUND"), s:CreateTexture(nil, "BACKGROUND")
		l:SetAtlas("Minimal_SliderBar_Left", true)
		l:SetPoint("LEFT", s, "LEFT", 0, 0)
		r:SetAtlas("Minimal_SliderBar_Right", true)
		r:SetPoint("RIGHT", s, "RIGHT", 0, 0)
		m:SetAtlas("_Minimal_SliderBar_Middle", true)
		m:SetPoint("TOPLEFT", l, "TOPRIGHT", 0, 0)
		m:SetPoint("TOPRIGHT", r, "TOPLEFT", 0, 0)
		for i, art in ipairs({ { "Minimal_SliderBar_Button_Left", -1, 11, 19 }, { "Minimal_SliderBar_Button_Right", 1, 9, 18 } }) do
			local b = CreateFrame("Button", nil, row)
			b:SetSize(art[3], art[4])
			b:SetNormalAtlas(art[1])
			b:SetHighlightAtlas(art[1], "ADD")
			if art[2] < 0 then b:SetPoint("RIGHT", s, "LEFT", -4, 0) else b:SetPoint("LEFT", s, "RIGHT", 4, 0) end
			b.dir = art[2]
			Script(b, "OnClick", "feel: step", function() s:SetValue(Snap(k, Snap(k, s:GetValue()) + b.dir * k.step)) end)
			Tipped(b, k)
			w.steps[i] = b
		end
	else -- (today's: the classic thumb on a dark track)
		s:SetThumbTexture(THUMB)
		s:GetThumbTexture():SetSize(16, 16)
		local track = s:CreateTexture(nil, "BACKGROUND")
		track:SetColorTexture(0, 0, 0, 0.6)
		track:SetPoint("LEFT", s, "LEFT", 0, 0)
		track:SetPoint("RIGHT", s, "RIGHT", 0, 0)
		track:SetHeight(6)
	end
	local text = Text(row, GameFontHighlightSmall, "")
	text:SetPoint("LEFT", row, "TOPLEFT", CTRL_X + 15 + SLIDER_W + 19, -ROW / 2)
	text:SetWidth(VALUE_W)
	text:SetJustifyH("LEFT")
	w.slider, w.text = s, text
	Script(s, "OnValueChanged", "feel: slide", function(_, v)
		v = Snap(k, v)
		local shown = Shown(k, v)
		if w.shown ~= shown then
			w.shown = shown
			text:SetText(shown)
		end
		Steppers(w, v)
		if not w.busy then SetValue(w, v) end
	end)
	Tipped(s, k)
end

-- Select: the client's dropdown, a radio per option -------------------------

local Picked = Runtime.Wrap("feel: pick", function(w, v) SetValue(w, v) end)
local function AddSelect(row, w, k)
	local d = CreateFrame("DropdownButton", nil, row, "WowStyle1DropdownTemplate")
	d:SetPoint("LEFT", row, "TOPLEFT", CTRL_X + 4, -ROW / 2)
	d:SetSize(DROP_W, 25)
	w.drop = d
	d:SetupMenu(function(_, root)
		for _, o in ipairs(Options(k)) do
			local v = o[2]
			root:CreateRadio(Label(o), function() return Feel.Get(k.key) == v end, function()
				Picked(w, v)
				return MenuResponse.Close
			end, v)
		end
	end)
	Tipped(d, k)
end

-- Color: the presets as the client's swatches, the chosen one ringed gold; Custom… the client's colour picker ----

local picking -- { w, before, start }: the colour picker's, while it's open for a row
local function Picker()
	local r, g, b = ColorPickerFrame:GetColorRGB()
	local hex = Hex(r, g, b)
	SetValue(picking.w, hex == picking.start and picking.before or hex) -- (it reports the colour it opens on too)
end
local PickerChanged = Runtime.Wrap("feel: colour", function() if picking then Picker() end end)
local PickerCancelled = Runtime.Wrap("feel: colour", function() if picking then SetValue(picking.w, picking.before) end end)
local function OpenPicker(w)
	local k = w.k
	local before = Feel.Get(k.key)
	local _, rgb = Feel.RGB(Options(k), before, Default(k))
	picking = { w = w, before = before, start = Hex(rgb[1], rgb[2], rgb[3]) }
	ColorPickerFrame:SetupColorPickerAndShow({ r = rgb[1], g = rgb[2], b = rgb[3], hasOpacity = false,
		swatchFunc = PickerChanged, cancelFunc = PickerCancelled })
	ColorPickerFrame:Raise()
end

local function Swatch(row, w, x, rgb)
	local sw = CreateFrame("Button", nil, row, "ColorSwatchTemplate")
	sw:SetPoint("LEFT", row, "TOPLEFT", x, -ROW / 2)
	sw.Color:SetVertexColor(rgb[1], rgb[2], rgb[3])
	sw:HookScript("OnLeave", Runtime.Wrap("feel: swatch", function() -- (the template's hover whitens the ring)
		local c = sw.ring
		sw.SwatchBg:SetVertexColor(c[1], c[2], c[3])
	end))
	sw.ring = WHITE
	return sw
end
local function Ring(sw, on)
	local c = on and GOLD or WHITE
	if sw.ring ~= c then
		sw.ring = c
		sw.SwatchBg:SetVertexColor(c[1], c[2], c[3])
	end
end

local function AddColor(row, w, k)
	w.swatches = {}
	local x = CTRL_X + 2
	for i, c in ipairs(Options(k)) do
		local sw = Swatch(row, w, x, c[2])
		sw.value = c[1]
		Script(sw, "OnClick", "feel: colour", function() SetValue(w, c[1]) end)
		Tipped(sw, k, k.label .. ": " .. c[1])
		w.swatches[i] = sw
		x = x + SWATCH
	end
	if k.custom ~= false and ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
		local sw = Swatch(row, w, x, WHITE) -- the custom colour, shown while it's the one
		Tipped(sw, k, k.label .. ": custom")
		Script(sw, "OnClick", "feel: colour picker", function() OpenPicker(w) end)
		local b = PanelButton(row, "Custom" .. ELLIPSIS, CUSTOM_W)
		b:SetHeight(20)
		b:SetPoint("LEFT", row, "TOPLEFT", x + SWATCH, -ROW / 2)
		Script(b, "OnClick", "feel: colour picker", function() OpenPicker(w) end)
		Tipped(b, k, k.label .. ": any colour")
		w.custom, w.pick = sw, b
	end
end

local function ShowColor(w, v)
	local name = Feel.RGB(Options(w.k), v, Default(w.k))
	for _, sw in ipairs(w.swatches) do Ring(sw, sw.value == name) end
	local custom = w.custom
	if custom then
		local hex = name:sub(1, 1) == "#"
		custom:SetShown(hex)
		if hex then
			local _, rgb = Feel.RGB(Options(w.k), name)
			custom.Color:SetVertexColor(rgb[1], rgb[2], rgb[3])
			Ring(custom, true)
		end
	end
end

-- List: a line an option (a box, its label; ordered: arrows to move a chosen one), the chosen first ---------

local function Arrow(row, atlas)
	local b = CreateFrame("Button", nil, row)
	b:SetSize(17, 11)
	b:SetNormalAtlas(atlas)
	b:SetHighlightAtlas(Has(atlas .. "-over") and atlas .. "-over" or atlas, "ADD")
	return b
end

local function Join(list) return table.concat(list, ",") end
local function ListToggle(w, i, on)
	local chosen, item = Split(w.k, w.value), w.lines[i].value
	for j = #chosen, 1, -1 do
		if chosen[j] == item then table.remove(chosen, j) end
	end
	if on then chosen[#chosen + 1] = item end
	SetValue(w, Join(chosen))
end
local function ListMove(w, i, d)
	local chosen = Split(w.k, w.value)
	if chosen[i] and chosen[i + d] then
		chosen[i], chosen[i + d] = chosen[i + d], chosen[i]
		SetValue(w, Join(chosen))
	end
end

local function AddList(row, w, k)
	w.lines = {}
	local arrows = k.ordered and Has("minimal-scrollbar-arrow-top") and Has("minimal-scrollbar-arrow-bottom")
	for i = 1, #Options(k) do
		local y = -(i - 1) * LINE - LINE / 2 - 3
		local c = Check(row, 20)
		c:SetPoint("LEFT", row, "TOPLEFT", CTRL_X - 1, y)
		local text = Text(row, GameFontHighlightSmall, "")
		text:SetPoint("LEFT", row, "TOPLEFT", CTRL_X + 22, y)
		text:SetWidth(arrows and 126 or 170)
		text:SetJustifyH("LEFT")
		local line = { check = c, text = text }
		Script(c, "OnClick", "feel: list", function() ListToggle(w, i, c:GetChecked()) end)
		Tipped(c, k)
		if arrows then
			line.up, line.down = Arrow(row, "minimal-scrollbar-arrow-top"), Arrow(row, "minimal-scrollbar-arrow-bottom")
			line.up:SetPoint("LEFT", row, "TOPLEFT", CTRL_X + 152, y)
			line.down:SetPoint("LEFT", row, "TOPLEFT", CTRL_X + 172, y)
			Script(line.up, "OnClick", "feel: list", function() ListMove(w, i, -1) end)
			Script(line.down, "OnClick", "feel: list", function() ListMove(w, i, 1) end)
		end
		w.lines[i] = line
	end
	row:SetHeight(math.max(ROW, #w.lines * LINE + 6))
end

local function ShowList(w, v)
	local chosen, rest, on = Split(w.k, v), {}, {}
	for _, item in ipairs(chosen) do on[item] = true end
	local label = {}
	for _, o in ipairs(Options(w.k)) do
		label[o[2]] = Label(o)
		if not on[o[2]] then rest[#rest + 1] = o[2] end
	end
	for i, line in ipairs(w.lines) do
		local item = chosen[i] or rest[i - #chosen]
		line.value = item
		line.text:SetText(item and label[item] or "")
		line.check:SetChecked(i <= #chosen)
		if line.up then
			line.up:SetShown(i <= #chosen and i > 1)
			line.down:SetShown(i < #chosen)
		end
	end
end

-- Button: an action, its label's text, at the row's left ---------------------

local function AddButton(row, w, k)
	local b = PanelButton(row, k.label, 190)
	b:SetPoint("LEFT", row, "TOPLEFT", 4, -ROW / 2)
	w.button = b
	Script(b, "OnClick", "feel: action", k.run)
	Tipped(b, k)
end

local ADD = { toggle = AddToggle, slider = AddSlider, select = AddSelect, color = AddColor, list = AddList, button = AddButton }

-- A row's control set to v: only what differs from what it shows. (While a menu is open the client sets its own text.)
local function Show(w, v)
	if w.value == v and w.shownOnce then return end
	w.value, w.shownOnce = v, true
	local kind = w.k.kind
	if kind == "toggle" then
		w.check:SetChecked(v == true)
	elseif kind == "slider" then
		w.busy = true
		w.slider:SetValue(v)
		w.busy = false
		local shown = Shown(w.k, v)
		if w.shown ~= shown then
			w.shown = shown
			w.text:SetText(shown)
		end
		Steppers(w, v)
	elseif kind == "select" then
		if not w.drop:IsMenuOpen() then w.drop:GenerateMenu() end
	elseif kind == "color" then
		ShowColor(w, v)
	elseif kind == "list" then
		ShowList(w, v)
	end
end

-- Its art (k.art(row, last): the region it draws, given the one it made before), drawn again on each refresh.
local function Draw(w)
	if w.k.art then w.art = w.k.art(w.row, w.art) end
end

local function Refresh(w)
	if w.k.kind ~= "button" then Show(w, Feel.Get(w.k.key)) end
	if w.art then Draw(w) end
end

-- The undo mark: shown while the row's value differs from its default; a click puts the default back.
local function Undo(row, w, k)
	local atlas = Has("common-icon-undo") and "common-icon-undo" or Has("auctionhouse-ui-filter-redx") and "auctionhouse-ui-filter-redx"
	if not atlas or not Resettable(k) then return end
	local b = CreateFrame("Button", nil, row)
	b:SetSize(UNDO, UNDO)
	b:SetPoint("RIGHT", row, "TOPRIGHT", -2, -ROW / 2)
	b:SetNormalAtlas(atlas)
	b:SetHighlightAtlas(atlas, "ADD")
	b:Hide()
	Script(b, "OnClick", "feel: undo", function() Feel.Set(k.key, Default(k)) end)
	b:HookScript("OnEnter", Runtime.Wrap("feel: tip", function()
		UI.Tip.Label(b, "Back to " .. Shown(k, Default(k)), "ANCHOR_RIGHT")
	end))
	b:HookScript("OnLeave", Runtime.Wrap("feel: tip", function() GameTooltip:Hide() end))
	w.undo = b
end

-- How deep a row stands under others (under: each a level).
local function Depth(k)
	local d, u = 0, k.under and BY_KEY[k.under]
	while u do d, u = d + 1, u.under and BY_KEY[u.under] end
	return d
end

-- Layout and Changed, below: a row opened or closed lays its page out again.
local Layout

-- The open mark of a row others stand under: the client's plus and minus; a click opens or closes it.
local PLUS, MINUS = "Interface\\Buttons\\UI-PlusButton-Up", "Interface\\Buttons\\UI-MinusButton-Up"
local function Opener(row, w, k, x)
	local b = CreateFrame("Button", nil, row)
	b:SetSize(OPEN, OPEN)
	b:SetPoint("LEFT", row, "TOPLEFT", x, -ROW / 2)
	b:SetNormalTexture(PLUS)
	b:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
	Script(b, "OnClick", "feel: open", function()
		opened[k.key] = not opened[k.key] or nil
		b:SetNormalTexture(opened[k.key] and MINUS or PLUS)
		Layout(BY_PAGE[k.page])
	end)
	b:HookScript("OnEnter", Runtime.Wrap("feel: tip", function()
		UI.Tip.Label(b, opened[k.key] and "Hide its settings" or "Show its settings", "ANCHOR_RIGHT")
	end))
	b:HookScript("OnLeave", Runtime.Wrap("feel: tip", function() GameTooltip:Hide() end))
	w.opener = b
end

-- A setting's row: its label (indented when it depends on another, a level a row it stands under; after its open mark
-- and its art), its control, its undo mark.
local function MakeRow(p, k)
	local row = CreateFrame("Frame", nil, p.content)
	row:SetSize(CONTENT_W, ROW)
	row:EnableMouse(true)
	Tipped(row, k)
	local w = { k = k, row = row }
	Feel.widgets[k.key] = w
	if k.kind ~= "button" then
		local on = type(k.when) == "string" and BY_KEY[k.when]
		local indent = k.when and (not on or on.section == k.section) and INDENT or 0 -- (under the row it depends on)
		indent = indent + Depth(k) * INDENT
		if OPENS[k.key] then
			Opener(row, w, k, 4 + indent)
			indent = indent + OPEN + 2
		end
		Draw(w)
		if w.art then
			w.art:ClearAllPoints()
			w.art:SetPoint("CENTER", row, "TOPLEFT", 4 + indent + ART / 2, -ROW / 2)
			indent = indent + ART + 4
		end
		local label = Text(row, GameFontHighlightSmall, k.label)
		label:SetPoint("LEFT", row, "TOPLEFT", 4 + indent, -ROW / 2)
		label:SetWidth(LABEL_W - indent)
		label:SetJustifyH("LEFT")
		label:SetWordWrap(false)
		w.label = label
	end
	ADD[k.kind](row, w, k)
	Undo(row, w, k)
	return w
end

local function MakeHeader(p, name)
	local f = CreateFrame("Frame", nil, p.content)
	f:SetSize(CONTENT_W, HEAD)
	Text(f, GameFontNormal, name):SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 2, 5)
	return f
end

-- A page's items in order: the settings without a section first, then each section's header and settings (the
-- page's sections in its order, then any other as first declared), each in the order declared, a row standing under
-- another right after it (and those under it), whenever declared. Made as needed.
local function Items(p)
	if p.items then return p.items end
	local order, seen = { false }, { [false] = true }
	for _, s in ipairs(p.sections) do
		if not seen[s] then order[#order + 1], seen[s] = s, true end
	end
	local kids = {} -- a row's key -> the rows under it
	for _, k in ipairs(KEYS) do
		if k.page == p.key then
			if not seen[k.section] then order[#order + 1], seen[k.section] = k.section, true end
			local u = k.under and BY_KEY[k.under]
			if u and u.page == p.key and u.section == k.section then
				kids[u.key] = kids[u.key] or {}
				table.insert(kids[u.key], k)
			end
		end
	end
	local items, hs = {}, headers[p.key] or {}
	headers[p.key] = hs
	local function Add(k)
		local w = Feel.widgets[k.key]
		if not w then
			w = MakeRow(p, k)
			Refresh(w)
		end
		items[#items + 1] = { k = k, w = w, f = w.row }
		for _, c in ipairs(kids[k.key] or {}) do Add(c) end
	end
	for _, s in ipairs(order) do
		local any = false
		for _, k in ipairs(KEYS) do
			local u = k.under and BY_KEY[k.under]
			if k.page == p.key and k.section == s and not (u and u.page == p.key and u.section == s) then
				if s and not any then
					hs[s] = hs[s] or MakeHeader(p, s)
					items[#items + 1] = { header = s, f = hs[s] }
				end
				any = true
				Add(k)
			end
		end
	end
	p.items = items
	return items
end

-- Whether a row shows: always, or while what it depends on is on; a row standing under another while that one is open
-- and shown.
local function Visible(k)
	local under = k.under and BY_KEY[k.under]
	if under and not (opened[under.key] and Visible(under)) then return false end
	local when = k.when
	if when == nil then return true end
	if type(when) == "function" then return when() and true or false end
	local v = Feel.Get(when)
	return v ~= nil and v ~= false
end

-- The page's rows placed, top down: those shown, each header while a row under it is; the scroll bar while
-- they're longer than the page.
Layout = function(p)
	local items = Items(p)
	local header
	for _, it in ipairs(items) do
		if it.header then
			header, it.on = it, false
		else
			it.on = Visible(it.k)
			if header and it.on then header.on = true end
		end
	end
	local y = 0
	for _, it in ipairs(items) do
		local f = it.f
		f:SetShown(it.on)
		if it.on then
			if it.header and y < 0 then y = y - GAP end
			f:ClearAllPoints()
			f:SetPoint("TOPLEFT", p.content, "TOPLEFT", 0, y)
			y = y - f:GetHeight()
		end
	end
	local h = -y + 4
	p.content:SetHeight(h)
	local range = math.max(0, h - p.scroll:GetHeight())
	p.bar:SetMinMaxValues(0, range)
	p.bar:SetShown(range > 0)
	if p.bar:GetValue() > range then p.bar:SetValue(range) end
	p.laid = true
end

-- The undo marks, the pages' Reset and Reset all: each lit while what it resets differs.
local function Marks()
	local any, page = false, {}
	for _, k in ipairs(KEYS) do
		local d = Differs(k)
		local w = Feel.widgets[k.key]
		if w and w.undo then w.undo:SetShown(d) end
		if d then any, page[k.page] = true, true end
	end
	for key, b in pairs(Feel.resets) do b:SetEnabled(page[key] == true) end
	Feel.resetAll:SetEnabled(any)
end

-- A setting changed (from its row, a reset, or anywhere): its control shows it, the rows that depend on it shown or
-- hidden, the marks lit.
Changed = function(k, v)
	local w = Feel.widgets[k.key]
	if w then Show(w, v) end
	for _, d in ipairs(INHERIT) do
		local dw = Feel.widgets[d.key]
		if dw and dw ~= w then Show(dw, Feel.Get(d.key)) end
	end
	local p = BY_PAGE[k.page]
	if p and p.laid then
		for _, it in ipairs(Items(p)) do
			if it.w and it.w.art then Draw(it.w) end -- (the art may show it)
		end
		for _, it in ipairs(Items(p)) do
			if it.k and it.on ~= Visible(it.k) then
				Layout(p)
				break
			end
		end
	end
	Marks()
end

-- A page's frame, made on its first showing: its title and divider, its Reset (where it has looks to reset), and a
-- scroll frame of its rows, the wheel and a bar to move them.
local function BuildPage(p)
	local page = CreateFrame("Frame", nil, frame)
	page:SetPoint("TOPLEFT", frame, "TOPLEFT", PAGE_X, -HEADER - 6)
	page:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD + FOOT)
	page:Hide()
	Text(page, GameFontNormalLarge, p.title):SetPoint("TOPLEFT", page, "TOPLEFT", 2, -6)
	if Has("Options_HorizontalDivider") then -- (the client's settings panel's, under its page title)
		local rule = page:CreateTexture(nil, "ARTWORK")
		rule:SetAtlas("Options_HorizontalDivider")
		rule:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -TITLE + 3)
		rule:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -TITLE + 3)
		rule:SetHeight(1)
	end
	local scroll = CreateFrame("ScrollFrame", nil, page)
	scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -TITLE)
	scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -BAR - 4, 0)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(CONTENT_W, 1)
	scroll:SetScrollChild(content)
	local bar = CreateFrame("Slider", nil, page)
	bar:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -TITLE)
	bar:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
	bar:SetWidth(BAR)
	bar:SetOrientation("VERTICAL")
	bar:SetMinMaxValues(0, 0)
	bar:SetValueStep(1)
	bar:SetThumbTexture(KNOB)
	bar:GetThumbTexture():SetSize(BAR, 24)
	bar:GetThumbTexture():SetTexCoord(0.2, 0.8, 0.125, 0.875)
	local track = bar:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints(bar)
	track:SetColorTexture(0, 0, 0, 0.3)
	bar:Hide()
	Script(bar, "OnValueChanged", "feel: scroll", function(_, v) scroll:SetVerticalScroll(v) end)
	scroll:EnableMouseWheel(true)
	Script(scroll, "OnMouseWheel", "feel: scroll", function(_, d) bar:SetValue(bar:GetValue() - d * ROW * 2) end)
	p.scroll, p.content, p.bar = scroll, content, bar
	local resettable = false
	for _, k in ipairs(KEYS) do resettable = resettable or k.page == p.key and Resettable(k) end
	if resettable then
		local reset = PanelButton(page, "Reset", 64)
		reset:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -2)
		Script(reset, "OnClick", "feel: reset", function() Feel.Reset(p.key) end)
		Feel.resets[p.key] = reset
	end
	Feel.pages[p.key] = page
	return page
end

-- The page chosen: shown (built if need be, its rows laid out and set from the values), the last one's hidden, kept.
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
	Layout(p)
	for _, it in ipairs(Items(p)) do
		if it.w then Refresh(it.w) end
	end
	Marks()
	page:Show()
	p.tab.sel:Show()
	p.tab.text:SetFontObject(GameFontNormal)
	if UI.saved then UI.saved.feelPage = key end
end
Feel.Select = function(key) if not built then Feel.Open(key) else Select(key) end end

-- A page's row in the sidebar: its icon and title, lit while chosen, a highlight under the cursor, its job as a tip.
local function Tab(p)
	local b = CreateFrame("Button", nil, frame)
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
	if p.tip then
		b:HookScript("OnEnter", Runtime.Wrap("feel: tip", function()
			GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
			UI.Tip.Describe(GameTooltip, p.title, p.tip)
			GameTooltip:Show()
		end))
		b:HookScript("OnLeave", Runtime.Wrap("feel: tip", function() GameTooltip:Hide() end))
	end
	p.tab = b
end

-- The sidebar in order (a page declared later takes its place); the window as tall as its pages need, 14 at least.
Grew = function()
	local h = math.max(HEIGHT, HEADER + 8 + #PAGES * SIDE_ROW + FOOT + PAD)
	if frame:GetHeight() ~= h then frame:SetHeight(h) end
end
Sidebar = function()
	for i, p in ipairs(PAGES) do
		if not p.tab then Tab(p) end
		p.tab:ClearAllPoints()
		p.tab:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -HEADER - 8 - (i - 1) * SIDE_ROW)
	end
	Grew()
end

local function Build()
	built = true
	frame = CreateFrame("Frame", "MagicMapFeel", UIParent, "ButtonFrameTemplate")
	Feel.frame = frame
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:SetSize(PAGE_X + PAGE_W + PAD, HEIGHT)
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
	local all = PanelButton(frame, "Reset all", 96)
	all:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD)
	Script(all, "OnClick", "feel: reset", Feel.ResetAll)
	Feel.resetAll = all
	Sidebar()
	frame:Hide()
end

-- Opened on page (a page's key; else the last one's, or General's).
function Feel.Open(page)
	if not built then Build() end
	if not page then
		local last = UI.saved and UI.saved.feelPage
		page = BY_PAGE[last] and last or current or "general"
	end
	Select(page)
	frame:Show()
end

function Feel.Toggle()
	if built and frame:IsShown() then frame:Hide() else Feel.Open() end
end

---------------------------------------------------------------------------
-- The pages, and Diagnostics' rows (Game's /mm commands)
---------------------------------------------------------------------------

Feel.Page({ key = "general", title = "General", icon = "Interface\\Icons\\Trade_Engineering", order = 10,
	tip = "What MagicMap replaces, its window and how the map moves.", sections = { "Blizzard's maps", "Map window", "Movement" } })
Feel.Page({ key = "map", title = "Map", icon = "Interface\\Icons\\INV_Misc_Map_01", order = 20,
	tip = "What the map shows: names, the ground, indoor maps and your arrow.", sections = { "Names", "Ground", "Indoors", "You" } })
Feel.Page({ key = "pills", title = "Quest pill", icon = "Interface\\Icons\\INV_Misc_PocketWatch_01", order = 40,
	tip = "The pill at the map's bottom left: what you track, how far, and how far you've come.", sections = { "Look" } })
Feel.Page({ key = "tracking", title = "Tracking", icon = "Interface\\Icons\\INV_Misc_Spyglass_03", order = 45,
	tip = "How the way is shown: Track's gold arrow, and Path to keeping the way in view (the line's look: Pathing).", sections = { "Arrow", "Path to" } })
Feel.Page({ key = "path", title = "Pathing", icon = "Interface\\Icons\\Ability_Hunter_Pathfinding", order = 50,
	tip = "The line to what you path to.", sections = { "Line", "Effects", "Outline" } })
Feel.Page({ key = "areas", title = "Quest areas", icon = "Interface\\Icons\\INV_Misc_Map02", order = 60,
	tip = "How your quests' objective areas are drawn.", sections = { "Followed quest", "Other quests", "Under the cursor" } })
Feel.Page({ key = "diag", title = "Diagnostics", icon = "Interface\\Icons\\INV_Gizmo_01", order = 90,
	tip = "Reports for a bug report: what the map is doing and what it costs.", sections = { "Reports in chat" } })

-- /mm <line>, as typed (Game owns them): a diagnostics row runs the same code (the gear's Advanced did).
local function Slash(line) return function() Command({ kind = "run", line = line }) end end
Feel.Add("diag", nil, {
	{ key = "diag.debug", kind = "toggle", label = "Debug info in title", default = false, keep = true,
		get = function() return UI.saved.debug == true end, set = Slash("debug"),
		tip = "Tile, zoom and layout timings next to the zone name." },
})
Feel.Add("diag", "Reports in chat", {
	{ key = "diag.record", kind = "button", label = "Record 10 seconds", run = Slash("perf"),
		tip = "Times every part of MagicMap while you play, then prints a summary in chat." },
	{ key = "diag.top", kind = "button", label = "Compare with other addons", run = Slash("perf top"),
		tip = "Prints in chat how MagicMap's cost compares with other addons'." },
	{ key = "diag.mem", kind = "button", label = "Memory breakdown", run = Slash("perf mem"),
		tip = "Prints in chat where MagicMap's memory is." },
})

Command({ kind = "slash", name = "feel", help = "[page]: the settings window, hidden again if shown (a page by its key: general, map...)",
	fn = function(arg) if built and frame:IsShown() and arg == "" then frame:Hide() else Feel.Open(BY_PAGE[arg:lower()] and arg:lower() or nil) end end })
Command({ kind = "slash", name = "settings", help = "the settings window (as /mm feel)", fn = Feel.Toggle })
