-- A small simulation of the WoW client's UI and map API, enough to load
-- MagicMap headlessly and drive it: frames and regions with anchor-based
-- layout, show/hide propagation, scripts and hooks, events, timers, mouse
-- input, tooltips, the Minimap, menus, and a mock world for C_Map.
--
-- It isn't the real client: it catches errors (nil calls, typos, bad
-- arithmetic, wrong assumptions about API shape) on the code paths a
-- scenario drives, not rendering or taint problems. Unknown methods are
-- simply absent, as in the game, so calling one is an error.
--
-- The client it simulates is WoW Forever (a Retail-engine client).

local Sim = { time = 0, frame = 0, errors = {}, timers = {}, prints = {} }
_G.Sim = Sim

---------------------------------------------------------------------------
-- Errors: every script, event and timer runs protected; failures are
-- collected (with a traceback) and the simulation carries on, like the game.
---------------------------------------------------------------------------

local function traceback(err)
	return debug.traceback(tostring(err), 2)
end

function Sim.Call(what, fn, ...)
	local n, args = select("#", ...), { ... }
	local ok, err = xpcall(function() return fn(unpack(args, 1, n)) end, traceback)
	if not ok then
		Sim.errors[#Sim.errors + 1] = what .. ": " .. err
	end
	return ok
end

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------

local S = setmetatable({}, { __mode = "k" }) -- widget -> internal state
Sim.state = S
local classes = {}
local allFrames = {}  -- in creation order
local named = {}

local function class(name, base)
	local methods = setmetatable({}, { __index = base and classes[base].methods })
	classes[name] = { methods = methods, mt = { __index = methods }, base = base }
	return methods
end

local function isA(obj, name)
	local c = classes[S[obj].type]
	while c do
		if c == classes[name] then return true end
		c = c.base and classes[c.base]
	end
	return false
end

local function new(typ, name, parent)
	local obj = setmetatable({}, classes[typ].mt)
	S[obj] = {
		type = typ, name = name, parent = parent, points = {}, shown = true, alpha = 1, scale = 1,
		children = {}, regions = {}, scripts = {}, events = {}, level = 0, strata = "MEDIUM",
	}
	if name then
		named[name] = obj
		_G[name] = obj
	end
	return obj
end

local function attach(obj, parent, list)
	local st = S[obj]
	if st.parent then
		local old = S[st.parent][list]
		for i = #old, 1, -1 do
			if old[i] == obj then table.remove(old, i) end
		end
	end
	st.parent = parent
	if parent then table.insert(S[parent][list], obj) end
end

local function isFrame(obj) return isA(obj, "Frame") end

local Region = class("Region")

-- Layout -------------------------------------------------------------------

local UI_W, UI_H = 1920, 1080

local function effScale(obj)
	local s = 1
	while obj do
		s = s * (S[obj].scale or 1)
		obj = S[obj].parent
	end
	return s
end

local POINT_X = { LEFT = 0, TOPLEFT = 0, BOTTOMLEFT = 0, CENTER = 0.5, TOP = 0.5, BOTTOM = 0.5, RIGHT = 1, TOPRIGHT = 1, BOTTOMRIGHT = 1 }
local POINT_Y = { BOTTOM = 0, BOTTOMLEFT = 0, BOTTOMRIGHT = 0, CENTER = 0.5, LEFT = 0.5, RIGHT = 0.5, TOP = 1, TOPLEFT = 1, TOPRIGHT = 1 }

-- Screen rect (pixels from the bottom-left): left, bottom, width, height.
local resolving = {}
local function rect(obj)
	if obj == Sim.UIParent then return 0, 0, UI_W, UI_H end
	if resolving[obj] then return nil end
	local st = S[obj]
	local scale = effScale(obj)
	local w, h = st.width and st.width * scale, st.height and st.height * scale
	local xs, ys = {}, {}
	resolving[obj] = true
	for _, p in ipairs(st.points) do
		local rel = p.rel or st.parent or Sim.UIParent
		local rl, rb, rw, rh = rect(rel)
		if rl then
			local x = rl + rw * POINT_X[p.relPoint] + p.x * scale
			local y = rb + rh * POINT_Y[p.relPoint] + p.y * scale
			xs[#xs + 1] = { POINT_X[p.point], x }
			ys[#ys + 1] = { POINT_Y[p.point], y }
		end
	end
	resolving[obj] = nil
	local function solve(list, size)
		local a, b
		for _, e in ipairs(list) do
			if not a then a = e elseif e[1] ~= a[1] then b = e end
		end
		if a and b then
			local span = (b[2] - a[2]) / (b[1] - a[1])
			return a[2] - a[1] * span, span
		elseif a and size then
			return a[2] - a[1] * size, size
		end
	end
	local left, width = solve(xs, w)
	local bottom, height = solve(ys, h)
	if not (left and bottom) then return nil end
	return left, bottom, width, height
end
Sim.Rect = rect

local VALID_POINTS = POINT_X

function Region:SetPoint(point, rel, relPoint, x, y)
	assert(VALID_POINTS[point], "SetPoint: bad point " .. tostring(point))
	if type(rel) == "string" then
		rel = named[rel]
	end
	if type(rel) == "number" or rel == nil and type(relPoint) == "number" then
		-- SetPoint(point, x, y)
		rel, relPoint, x, y = nil, point, rel, relPoint
	elseif type(relPoint) == "number" then
		-- SetPoint(point, rel, x, y)
		relPoint, x, y = point, relPoint, x
	end
	relPoint = relPoint or point
	assert(VALID_POINTS[relPoint], "SetPoint: bad relative point " .. tostring(relPoint))
	if rel ~= nil then assert(S[rel], "SetPoint: relative to a non-region") end
	assert(rel ~= self, "SetPoint: anchored to itself")
	local points = S[self].points
	for i = #points, 1, -1 do
		if points[i].point == point then table.remove(points, i) end
	end
	points[#points + 1] = { point = point, rel = rel, relPoint = relPoint, x = x or 0, y = y or 0 }
end

function Region:SetAllPoints(rel)
	self:ClearAllPoints()
	self:SetPoint("TOPLEFT", rel or S[self].parent, "TOPLEFT")
	self:SetPoint("BOTTOMRIGHT", rel or S[self].parent, "BOTTOMRIGHT")
end

function Region:ClearAllPoints() S[self].points = {} end
function Region:GetNumPoints() return #S[self].points end
function Region:GetPoint(i)
	local p = S[self].points[i or 1]
	if p then return p.point, p.rel or S[self].parent, p.relPoint, p.x, p.y end
end

local function setSize(self, w, h)
	local st = S[self]
	local changed = (w and w ~= st.width) or (h and h ~= st.height)
	if w then st.width = w end
	if h then st.height = h end
	if changed and st.scripts.OnSizeChanged then
		Sim.FireScript(self, "OnSizeChanged", self:GetWidth(), self:GetHeight())
	end
end
function Region:SetSize(w, h) assert(type(w) == "number" and type(h) == "number", "SetSize: numbers expected"); setSize(self, w, h) end
function Region:SetWidth(w) assert(type(w) == "number", "SetWidth: number expected"); setSize(self, w, nil) end
function Region:SetHeight(h) assert(type(h) == "number", "SetHeight: number expected"); setSize(self, nil, h) end

function Region:GetSize() return self:GetWidth(), self:GetHeight() end
function Region:GetWidth()
	local l, b, w = rect(self)
	if l then return w / effScale(self) end
	return S[self].width or 0
end
function Region:GetHeight()
	local l, b, w, h = rect(self)
	if l then return h / effScale(self) end
	return S[self].height or 0
end
function Region:GetLeft() local l = rect(self); return l and l / effScale(self) end
function Region:GetBottom() local _, b = rect(self); return b and b / effScale(self) end
function Region:GetRight() local l, _, w = rect(self); return l and (l + w) / effScale(self) end
function Region:GetTop() local _, b, _, h = rect(self); return b and (b + h) / effScale(self) end
function Region:GetCenter()
	local l, b, w, h = rect(self)
	if l then
		local s = effScale(self)
		return (l + w / 2) / s, (b + h / 2) / s
	end
end
function Region:GetRect()
	local l, b, w, h = rect(self)
	if l then
		local s = effScale(self)
		return l / s, b / s, w / s, h / s
	end
end

-- Visibility -----------------------------------------------------------------

local function visible(obj)
	while obj do
		if not S[obj].shown then return false end
		obj = S[obj].parent
	end
	return true
end

local function visibleFrames(obj, out)
	if not visible(obj) then return out end
	if isFrame(obj) then out[#out + 1] = obj end
	for _, c in ipairs(S[obj].children) do visibleFrames(c, out) end
	return out
end

local function setShown(self, shown)
	local st = S[self]
	if st.shown == shown then return end
	local before = visibleFrames(self, {})
	st.shown = shown
	if shown then
		for _, f in ipairs(visibleFrames(self, {})) do Sim.FireScript(f, "OnShow") end
	else
		for _, f in ipairs(before) do Sim.FireScript(f, "OnHide") end
	end
end

function Region:Show() setShown(self, true) end
function Region:Hide() setShown(self, false) end
function Region:SetShown(on) setShown(self, not not on) end
function Region:IsShown() return S[self].shown end
function Region:IsVisible() return visible(self) end
function Region:SetAlpha(a) assert(type(a) == "number", "SetAlpha: number expected"); S[self].alpha = math.max(0, math.min(1, a)) end
function Region:GetAlpha() return S[self].alpha end
function Region:GetEffectiveAlpha()
	local a, obj = 1, self
	while obj do a = a * S[obj].alpha; obj = S[obj].parent end
	return a
end
function Region:GetParent() return S[self].parent end
function Region:GetObjectType() return S[self].type == "Minimap" and "Minimap" or S[self].type end
function Region:IsObjectType(t) return isA(self, t) end
function Region:GetName() return S[self].name end
function Region:GetDebugName() return S[self].name or ("<" .. S[self].type .. ">") end
function Region:GetScale() return S[self].scale end
function Region:SetScale(s) assert(type(s) == "number" and s > 0, "SetScale: positive number expected"); S[self].scale = s end
function Region:GetEffectiveScale() return effScale(self) end
function Region:IsProtected() return false end
-- Offsets grow (or shrink) the tested rect: top up, bottom down when negative.
function Region:IsMouseOver(top, bottom, left, right)
	local l, b, w, h = rect(self)
	if not l or not visible(self) then return false end
	local x, y = Sim.cursorX, Sim.cursorY
	return x >= l + (left or 0) and x <= l + w + (right or 0) and y >= b + (bottom or 0) and y <= b + h + (top or 0)
end
function Region:SetParent(parent)
	if type(parent) == "string" then parent = named[parent] end
	attach(self, parent, isFrame(self) and "children" or "regions")
end

-- Textures, lines, masks, font strings -------------------------------------

local LAYERS = { BACKGROUND = true, BORDER = true, ARTWORK = true, OVERLAY = true, HIGHLIGHT = true }

local Texture = class("Texture", "Region")
function Texture:SetTexture(tex, wrapH, wrapV)
	assert(tex == nil or type(tex) == "string" or type(tex) == "number", "SetTexture: path or FileDataID expected")
	S[self].texture = tex
	S[self].color = nil
end
function Texture:GetTexture() return S[self].texture end
function Texture:GetTextureFileID() return type(S[self].texture) == "number" and S[self].texture or nil end
function Texture:SetColorTexture(r, g, b, a)
	assert(type(r) == "number" and type(g) == "number" and type(b) == "number", "SetColorTexture: numbers expected")
	S[self].color = { r, g, b, a or 1 }
	S[self].texture = nil
end
function Texture:SetAtlas(atlas, useSize)
	assert(type(atlas) == "string", "SetAtlas: string expected")
	S[self].atlas = atlas
end
function Texture:GetAtlas() return S[self].atlas end
function Texture:SetVertexColor(r, g, b, a) assert(type(r) == "number", "SetVertexColor: numbers expected"); S[self].vertex = { r, g, b, a } end
function Texture:GetVertexColor() local v = S[self].vertex or { 1, 1, 1, 1 }; return v[1], v[2], v[3], v[4] or 1 end
function Texture:SetTexCoord(...)
	local n = select("#", ...)
	assert(n == 4 or n == 8, "SetTexCoord: 4 or 8 numbers expected")
	S[self].texCoord = { ... }
end
function Texture:SetDesaturated(on) S[self].desaturated = not not on end
function Texture:IsDesaturated() return S[self].desaturated end
function Texture:SetBlendMode(mode) S[self].blend = mode end
function Texture:SetRotation(r) assert(type(r) == "number", "SetRotation: number expected"); S[self].rotation = r end
function Texture:SetSnapToPixelGrid(on) end
function Texture:SetTexelSnappingBias(b) end
function Texture:SetHorizTile(on) end
function Texture:SetVertTile(on) end
function Texture:AddMaskTexture(mask) assert(mask and S[mask] and S[mask].type == "MaskTexture", "AddMaskTexture: mask expected") end
function Texture:RemoveMaskTexture(mask) end
function Texture:SetGradient(orientation, c1, c2)
	assert(orientation == "HORIZONTAL" or orientation == "VERTICAL", "SetGradient: bad orientation")
	assert(type(c1) == "table" and c1.GetRGBA and type(c2) == "table" and c2.GetRGBA, "SetGradient: colors expected")
	S[self].gradient = { orientation, c1, c2 }
end
local function setDrawLayer(self, layer, sublevel)
	assert(LAYERS[layer], "SetDrawLayer: bad layer " .. tostring(layer))
	assert(sublevel == nil or (sublevel >= -8 and sublevel <= 7), "SetDrawLayer: sublevel out of range")
	S[self].layer, S[self].sublevel = layer, sublevel or 0
end
Texture.SetDrawLayer = setDrawLayer
function Texture:GetDrawLayer() return S[self].layer, S[self].sublevel end

local Line = class("Line", "Texture")
local function lineAnchor(self, which, point, rel, x, y)
	assert(VALID_POINTS[point], "Line point: bad point")
	S[self][which] = { point, rel or S[self].parent, x or 0, y or 0 }
end
function Line:SetStartPoint(point, rel, x, y) lineAnchor(self, "startPoint", point, rel, x, y) end
function Line:SetEndPoint(point, rel, x, y) lineAnchor(self, "endPoint", point, rel, x, y) end
function Line:GetStartPoint() local p = S[self].startPoint; if p then return unpack(p) end end
function Line:GetEndPoint() local p = S[self].endPoint; if p then return unpack(p) end end
function Line:SetThickness(t) assert(type(t) == "number" and t >= 0, "SetThickness: number expected"); S[self].thickness = t end
function Line:GetThickness() return S[self].thickness or 1 end

class("MaskTexture", "Texture")

local FontString = class("FontString", "Region")
function FontString:SetText(text)
	if text ~= nil and type(text) ~= "string" and type(text) ~= "number" then error("SetText: string expected, got " .. type(text), 2) end
	S[self].text = text and tostring(text)
end
function FontString:GetText() return S[self].text end
function FontString:SetFormattedText(fmt, ...) S[self].text = string.format(fmt, ...) end
function FontString:SetFont(path, size, flags)
	assert(type(path) == "string" and type(size) == "number", "SetFont: path and size expected")
	S[self].font = { path, size, flags }
	return true
end
function FontString:GetFont() local f = S[self].font or { "Fonts\\FRIZQT__.TTF", 12, "" }; return f[1], f[2], f[3] end
function FontString:SetFontObject(obj) S[self].fontObject = obj end
function FontString:SetTextColor(r, g, b, a) assert(type(r) == "number", "SetTextColor: numbers expected") end
function FontString:SetJustifyH(j) assert(j == "LEFT" or j == "CENTER" or j == "RIGHT", "SetJustifyH: bad value") end
function FontString:SetJustifyV(j) end
function FontString:SetShadowOffset(x, y) end
function FontString:SetShadowColor(r, g, b, a) end
function FontString:SetWordWrap(on) end
function FontString:SetNonSpaceWrap(on) end
function FontString:SetMaxLines(n) end
function FontString:SetSpacing(n) end
function FontString:GetStringWidth()
	local _, size = self:GetFont()
	return #(S[self].text or "") * size * 0.55
end
function FontString:GetUnboundedStringWidth() return self:GetStringWidth() end
function FontString:GetStringHeight()
	local _, size = self:GetFont()
	return S[self].text and size or 0
end
FontString.SetDrawLayer = setDrawLayer
FontString.GetDrawLayer = Texture.GetDrawLayer
FontString.SetVertexColor = Texture.SetVertexColor

-- Frames ---------------------------------------------------------------------

local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }

local Frame = class("Frame", "Region")
local function newRegion(self, typ, name, layer, template, sublevel)
	assert(layer == nil or LAYERS[layer], "bad draw layer " .. tostring(layer))
	assert(sublevel == nil or (sublevel >= -8 and sublevel <= 7), "sublevel out of range")
	local r = new(typ, name, nil)
	attach(r, self, "regions")
	S[r].layer, S[r].sublevel = layer or "ARTWORK", sublevel or 0
	return r
end
function Frame:CreateTexture(name, layer, template, sublevel) return newRegion(self, "Texture", name, layer, template, sublevel) end
function Frame:CreateMaskTexture(name, layer, template, sublevel) return newRegion(self, "MaskTexture", name, layer, template, sublevel) end
function Frame:CreateLine(name, layer, template, sublevel) return newRegion(self, "Line", name, layer, template, sublevel) end
function Frame:CreateFontString(name, layer, template) return newRegion(self, "FontString", name, layer, template) end

local SCRIPTS = {
	OnUpdate = true, OnEvent = true, OnShow = true, OnHide = true, OnClick = true, OnEnter = true, OnLeave = true,
	OnMouseDown = true, OnMouseUp = true, OnMouseWheel = true, OnDragStart = true, OnDragStop = true,
	OnSizeChanged = true, OnLoad = true, OnReceiveDrag = true, OnDoubleClick = true, OnTooltipCleared = true,
}
function Frame:SetScript(name, fn)
	assert(SCRIPTS[name], "SetScript: unknown script " .. tostring(name))
	assert(fn == nil or type(fn) == "function", "SetScript: function expected")
	S[self].scripts[name] = fn and { main = fn, hooks = {} } or nil
end
function Frame:GetScript(name) local s = S[self].scripts[name]; return s and s.main end
function Frame:HasScript(name) return SCRIPTS[name] ~= nil end
function Frame:HookScript(name, fn)
	assert(SCRIPTS[name], "HookScript: unknown script " .. tostring(name))
	assert(type(fn) == "function", "HookScript: function expected")
	local s = S[self].scripts[name]
	if not s then
		s = { hooks = {} }
		S[self].scripts[name] = s
	end
	table.insert(s.hooks, fn)
end
function Frame:RegisterEvent(event)
	assert(type(event) == "string", "RegisterEvent: string expected")
	if Sim.unknownEvents[event] then error("Attempt to register unknown event \"" .. event .. "\"", 2) end
	S[self].events[event] = true
end
function Frame:UnregisterEvent(event) S[self].events[event] = nil end
function Frame:UnregisterAllEvents() S[self].events = {} end
function Frame:IsEventRegistered(event) return S[self].events[event] == true end
function Frame:SetFrameStrata(s) assert(STRATA[s], "SetFrameStrata: bad strata " .. tostring(s)); S[self].strata = s end
function Frame:GetFrameStrata() return S[self].strata end
function Frame:SetFrameLevel(l) assert(type(l) == "number" and l >= 0, "SetFrameLevel: non-negative number expected"); S[self].level = math.floor(l) end
function Frame:GetFrameLevel() return S[self].level end
function Frame:Raise() S[self].level = S[self].level + 1 end
function Frame:Lower() end
function Frame:SetToplevel(on) end
function Frame:EnableMouse(on) S[self].mouse = not not on; S[self].mouseClick = not not on; S[self].mouseMotion = not not on end
function Frame:IsMouseEnabled() return S[self].mouse == true end
function Frame:EnableMouseWheel(on) S[self].wheel = not not on end
function Frame:IsMouseWheelEnabled() return S[self].wheel == true end
function Frame:SetMouseClickEnabled(on) S[self].mouseClick = not not on end
function Frame:SetMouseMotionEnabled(on) S[self].mouseMotion = not not on end
function Frame:SetPropagateMouseClicks(on) end
function Frame:SetPropagateMouseMotion(on) end
function Frame:RegisterForDrag(...) S[self].drag = { ... } end
function Frame:RegisterForClicks(...) end
function Frame:SetMovable(on) S[self].movable = on end
function Frame:IsMovable() return S[self].movable end
function Frame:SetResizable(on) S[self].resizable = on end
function Frame:SetClampedToScreen(on) S[self].clamped = not not on end
function Frame:IsClampedToScreen() return S[self].clamped == true end
function Frame:SetClipsChildren(on) end
function Frame:SetHitRectInsets(l, r, t, b)
	assert(type(l) == "number" and type(r) == "number" and type(t) == "number" and type(b) == "number", "SetHitRectInsets: numbers expected")
	S[self].hitInsets = { l, r, t, b }
end
function Frame:GetHitRectInsets() local i = S[self].hitInsets or { 0, 0, 0, 0 }; return i[1], i[2], i[3], i[4] end
function Frame:SetID(id) S[self].id = id end
function Frame:GetID() return S[self].id or 0 end
function Frame:StartMoving() assert(S[self].movable, "StartMoving: frame isn't movable") end
function Frame:StartSizing() assert(S[self].resizable, "StartSizing: frame isn't resizable") end
function Frame:StopMovingOrSizing() end
function Frame:GetChildren() return unpack(S[self].children) end
function Frame:GetNumChildren() return #S[self].children end
function Frame:GetRegions() return unpack(S[self].regions) end
function Frame:GetNumRegions() return #S[self].regions end
function Frame:SetResizeBounds(minW, minH, maxW, maxH) end

local Button = class("Button", "Frame")
local function buttonTexture(self, key, tex)
	if type(tex) == "string" or type(tex) == "number" then
		local t = S[self][key] or self:CreateTexture(nil, "ARTWORK")
		t:SetTexture(tex)
		tex = t
	end
	S[self][key] = tex
end
function Button:SetNormalTexture(t) buttonTexture(self, "normal", t) end
local function buttonAtlas(self, key, atlas)
	assert(C_Texture.GetAtlasInfo(atlas), "unknown atlas " .. tostring(atlas))
	local t = S[self][key] or self:CreateTexture(nil, "ARTWORK")
	t:SetAtlas(atlas)
	S[self][key] = t
end
function Button:SetNormalAtlas(a) buttonAtlas(self, "normal", a) end
function Button:SetPushedAtlas(a) buttonAtlas(self, "pushed", a) end
function Button:SetHighlightAtlas(a, mode) buttonAtlas(self, "highlight", a) end
function Button:SetPushedTexture(t) buttonTexture(self, "pushed", t) end
function Button:SetHighlightTexture(t, mode) buttonTexture(self, "highlight", t) end
function Button:SetDisabledTexture(t) buttonTexture(self, "disabled", t) end
function Button:GetNormalTexture() return S[self].normal end
function Button:GetPushedTexture() return S[self].pushed end
function Button:GetHighlightTexture() return S[self].highlight end
function Button:Enable() S[self].disabled = false end
function Button:Disable() S[self].disabled = true end
function Button:SetEnabled(on) S[self].disabled = not on end
function Button:IsEnabled() return not S[self].disabled end
function Button:Click(button) Sim.FireScript(self, "OnClick", button or "LeftButton", false) end
function Button:SetText(t) S[self].text = t end
function Button:GetText() return S[self].text end

-- GameTooltip: lines are font strings named <name>TextLeft<i>, as in the game.
local Tooltip = class("GameTooltip", "Frame")
local function tooltipLine(self, i)
	local st = S[self]
	st.lines = st.lines or {}
	if not st.lines[i] then
		local name = st.name and (st.name .. "TextLeft" .. i)
		st.lines[i] = self:CreateFontString(name, "ARTWORK")
	end
	return st.lines[i]
end
function Tooltip:SetOwner(owner, anchor) S[self].owner = owner; self:ClearLines() end
function Tooltip:GetOwner() return S[self].owner end
function Tooltip:IsOwned(f) return S[self].owner == f end
function Tooltip:ClearLines()
	local st = S[self]
	for _, fs in ipairs(st.lines or {}) do fs:SetText(nil) end
	st.numLines = 0
end
function Tooltip:AddLine(text, r, g, b, wrap)
	local st = S[self]
	st.numLines = (st.numLines or 0) + 1
	tooltipLine(self, st.numLines):SetText(text)
end
function Tooltip:AddDoubleLine(left, right) self:AddLine(left) end
function Tooltip:SetText(text, r, g, b, a, wrap) self:ClearLines(); self:AddLine(text) end
function Tooltip:NumLines() return S[self].numLines or 0 end
function Tooltip:SetUnit(unit)
	self:ClearLines()
	local name = UnitName(unit)
	if name then
		self:AddLine(name)
		self:AddLine(Sim.unitSubtitle[unit] or "Level 10")
	end
end
-- The Minimap's hover: Sim.blip names the blip under the cursor; with none
-- the tooltip is left empty and hidden.
local function minimapMouseover(self)
	self:ClearLines()
	if Sim.blip then
		self:AddLine(Sim.blip)
		self:Show()
	else
		self:Hide()
	end
end
Tooltip.SetMinimapMouseover = minimapMouseover

-- The Minimap: zoom levels, and a view radius that follows them.
local MinimapClass = class("Minimap", "Frame")
function MinimapClass:GetZoom() return S[self].zoom or 0 end
function MinimapClass:SetZoom(z)
	assert(type(z) == "number" and z >= 0 and z <= 5, "SetZoom: 0..5 expected")
	S[self].zoom = z
end
function MinimapClass:GetZoomLevels() return 6 end
function MinimapClass:SetMaskTexture(t) Sim.minimapMask = t end
-- The quest/dig-site/bonus-objective rings at its rim: size, 1 = at the rim.
Sim.blobRings = { Quest = 1, Arch = 1, Task = 1 }
for kind in pairs(Sim.blobRings) do
	MinimapClass["Set" .. kind .. "BlobRingScalar"] = function(_, v) Sim.blobRings[kind] = v end
end
local function RingsAt(v)
	for _, r in pairs(Sim.blobRings) do if r ~= v then return false end end
	return true
end
Sim.BlobRingsAt = RingsAt
function MinimapClass:UpdateMouseoverAtPoint(x, y) end

-- ScrollFrame: its scroll child is reparented to it.
local ScrollFrame = class("ScrollFrame", "Frame")
function ScrollFrame:SetScrollChild(child)
	assert(child and S[child] and isFrame(child), "SetScrollChild: frame expected")
	child:SetParent(self)
	S[self].scrollChild = child
end
function ScrollFrame:GetScrollChild() return S[self].scrollChild end
function ScrollFrame:SetHorizontalScroll(v) S[self].hscroll = v end
function ScrollFrame:SetVerticalScroll(v) S[self].vscroll = v end

-- QuestPOIFrame (retail): draws quest blobs for one uiMap.
local POI = class("QuestPOIFrame", "Frame")
function POI:SetMapID(id) assert(type(id) == "number", "SetMapID: number expected"); S[self].mapID = id end
-- Quest areas are circles: Sim.blobShapes[questID] = { x, y, r } in its map's
-- normalized coordinates; a frame knows which quests it has drawn.
Sim.blobShapes = {}
function POI:DrawBlob(questID, draw)
	assert(type(questID) == "number", "DrawBlob: questID expected")
	S[self].blobs = S[self].blobs or {}
	S[self].blobs[questID] = true
end
function POI:DrawNone() S[self].blobs = {} end
function POI:SetFillTexture(t) end
function POI:SetFillAlpha(a) end
function POI:SetBorderTexture(t) end
function POI:SetBorderScalar(s) end
function POI:SetBorderAlpha(a) end
function POI:EnableMerging(on) end
function POI:EnableSmoothing(on) end
function POI:SetMergeThreshold(t) end
function POI:SetNumSplinePoints(n) end
-- The quest whose drawn area covers (x, y): Sim.questUnderCursor if set (for
-- tooltip tests), else one of its quests whose circle holds the point.
function POI:UpdateMouseOverTooltip(x, y)
	if Sim.questUnderCursor then return Sim.questUnderCursor end
	for questID in pairs(S[self].blobs or {}) do
		local c = Sim.blobShapes[questID]
		if c and (x - c[1]) ^ 2 + (y - c[2]) ^ 2 <= c[3] ^ 2 then return questID end
	end
end
function POI:GetTooltipIndex() return 0 end

local FRAME_TYPES = { Frame = "Frame", Button = "Button", GameTooltip = "GameTooltip", ScrollFrame = "ScrollFrame" }
FRAME_TYPES.QuestPOIFrame = "QuestPOIFrame"

local TEMPLATES = { UIPanelCloseButton = true, GameTooltipTemplate = true, ButtonFrameTemplate = true, BackdropTemplate = true }

function CreateFrame(typ, name, parent, template)
	local cls = FRAME_TYPES[typ]
	if not cls then error("CreateFrame: unknown frame type '" .. tostring(typ) .. "'", 2) end
	if type(parent) == "string" then parent = named[parent] end
	if parent ~= nil then assert(S[parent] and isFrame(parent), "CreateFrame: parent must be a frame") end
	for t in tostring(template or ""):gmatch("[^,%s]+") do
		if not TEMPLATES[t] then error("CreateFrame: unknown template '" .. t .. "'", 2) end
	end
	local f = new(cls, name, nil)
	attach(f, parent, "children")
	if parent then
		S[f].strata, S[f].level = S[parent].strata, S[parent].level + 1
	end
	allFrames[#allFrames + 1] = f
	if template and template:find("UIPanelCloseButton") then
		f:SetSize(32, 32)
	end
	if template and template:find("ButtonFrameTemplate") then
		-- Retail's has a NineSlice border; the others take the addon's fallback.
		f.NineSlice = CreateFrame("Frame", nil, f)
		f.TitleText = f:CreateFontString(nil, "OVERLAY")
		f.CloseButton = CreateFrame("Button", nil, f)
		f.CloseButton:SetSize(24, 24)
		f.CloseButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
		f.Bg = f:CreateTexture(nil, "BACKGROUND")
	end
	return f
end

-- Count every widget method call (a proxy for frame cost in the client,
-- where each is a call into the engine): Sim.calls[name], Sim.callTotal,
-- and per widget, Sim.callsOn[widget].
function Sim.CountCalls()
	Sim.calls, Sim.callTotal, Sim.callsOn = {}, 0, setmetatable({}, { __mode = "k" })
	for _, c in pairs(classes) do
		for name, fn in pairs(c.methods) do
			if type(fn) == "function" then
				c.methods[name] = function(self, ...)
					Sim.callTotal = Sim.callTotal + 1
					Sim.calls[name] = (Sim.calls[name] or 0) + 1
					if type(self) == "table" then Sim.callsOn[self] = (Sim.callsOn[self] or 0) + 1 end
					return fn(self, ...)
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Driving the simulation
---------------------------------------------------------------------------

function Sim.FireScript(frame, name, ...)
	local s = S[frame].scripts[name]
	if not s then return end
	local what = (S[frame].name or S[frame].type) .. ":" .. name
	if s.main then Sim.Call(what, s.main, frame, ...) end
	for _, hook in ipairs(s.hooks) do Sim.Call(what .. " hook", hook, frame, ...) end
end

function Sim.FireEvent(event, ...)
	for _, f in ipairs(allFrames) do
		if S[f].events[event] then Sim.FireScript(f, "OnEvent", event, ...) end
	end
end

-- One rendered frame: timers, then every visible frame's OnUpdate.
function Sim.Step(elapsed)
	elapsed = elapsed or 1 / 60
	Sim.time = Sim.time + elapsed
	Sim.frame = Sim.frame + 1
	if Sim.onStep then Sim.onStep(elapsed) end
	local due = {}
	for i = #Sim.timers, 1, -1 do
		if Sim.timers[i].at <= Sim.time then
			table.insert(due, 1, table.remove(Sim.timers, i))
		end
	end
	for _, t in ipairs(due) do Sim.Call("C_Timer callback", t.fn) end
	local list = {}
	for _, f in ipairs(allFrames) do
		if S[f].scripts.OnUpdate and visible(f) then list[#list + 1] = f end
	end
	for _, f in ipairs(list) do
		if visible(f) then Sim.FireScript(f, "OnUpdate", elapsed) end
	end
end

function Sim.Run(seconds, fps)
	local dt = 1 / (fps or 60)
	for _ = 1, math.ceil(seconds / dt) do Sim.Step(dt) end
end

-- Mouse: the cursor in screen pixels.
Sim.cursorX, Sim.cursorY = UI_W / 2, UI_H / 2
Sim.buttonsDown = {}

function Sim.MoveCursorTo(frame, fx, fy)
	local l, b, w, h = rect(frame)
	assert(l, "MoveCursorTo: frame has no position")
	Sim.cursorX, Sim.cursorY = l + w * (fx or 0.5), b + h * (fy or 0.5)
end

function Sim.Wheel(frame, delta)
	Sim.MoveCursorTo(frame)
	if S[frame].wheel then Sim.FireScript(frame, "OnMouseWheel", delta) end
end

-- Click `frame` with the cursor at (fx, fy) of its rect, or at screen point
-- (x, y) when `at` = "screen".
function Sim.Click(frame, button, fx, fy, at)
	button = button or "LeftButton"
	Sim.menu = nil -- a click anywhere closes the client's menu (its entries aren't frames here)
	if at == "screen" then
		Sim.cursorX, Sim.cursorY = fx, fy
	else
		Sim.MoveCursorTo(frame, fx, fy)
	end
	Sim.buttonsDown[button] = true
	Sim.FireScript(frame, "OnMouseDown", button)
	Sim.Step()
	Sim.buttonsDown[button] = nil
	Sim.FireScript(frame, "OnMouseUp", button)
	Sim.FireScript(frame, "OnClick", button, false)
	Sim.Step()
end

-- Press, move the cursor by (dx, dy) pixels over `steps` frames, release.
function Sim.Drag(frame, dx, dy, steps)
	steps = steps or 20
	Sim.MoveCursorTo(frame)
	Sim.buttonsDown.LeftButton = true
	Sim.FireScript(frame, "OnMouseDown", "LeftButton")
	if S[frame].drag then Sim.FireScript(frame, "OnDragStart", "LeftButton") end
	for _ = 1, steps do
		Sim.cursorX, Sim.cursorY = Sim.cursorX + dx / steps, Sim.cursorY + dy / steps
		Sim.Step()
	end
	Sim.buttonsDown.LeftButton = nil
	if S[frame].drag then Sim.FireScript(frame, "OnDragStop") end
	Sim.FireScript(frame, "OnMouseUp", "LeftButton")
	Sim.Step()
end

function Sim.Hover(frame)
	Sim.MoveCursorTo(frame)
	Sim.FireScript(frame, "OnEnter", false)
	Sim.Step()
	Sim.FireScript(frame, "OnLeave", false)
end

function Sim.Slash(msg)
	Sim.Call("/mm " .. msg, SlashCmdList.MAGICMAP, msg)
end

-- Every frame, created in order (for scenarios to find buttons etc.).
function Sim.Frames() return allFrames end
function Sim.Named(name) return named[name] end

---------------------------------------------------------------------------
-- Lua / WoW library functions
---------------------------------------------------------------------------

function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function hooksecurefunc(t, name, fn)
	if type(t) == "string" then t, name, fn = _G, t, name end -- hooksecurefunc("GlobalFunction", fn)
	local orig = t[name]
	t[name] = function(...)
		local r = { orig(...) }
		fn(...)
		return unpack(r)
	end
end
tinsert, tremove = table.insert, table.remove
function strtrim(s, chars)
	chars = chars or " \t\r\n"
	local pat = "[" .. chars:gsub("[%]%^%-]", "%%%0") .. "]"
	return (s:gsub("^" .. pat .. "+", ""):gsub(pat .. "+$", ""))
end
function strsplit(sep, s, limit)
	local out, start, n = {}, 1, 0
	while true do
		n = n + 1
		local i, j = s:find(sep, start, true)
		if not i or (limit and n >= limit) then
			out[#out + 1] = s:sub(start)
			break
		end
		out[#out + 1] = s:sub(start, i - 1)
		start = j + 1
	end
	return unpack(out)
end
function debugprofilestop() return os.clock() * 1000 end
function GetTime() return Sim.time end
time = os.time
date = os.date

function GetBuildInfo() return "1.60.1", "70009", "Sep 1 2026", 16001 end

function GetCursorPosition() return Sim.cursorX, Sim.cursorY end
function IsMouseButtonDown(button) return Sim.buttonsDown[button or "LeftButton"] == true end
function IsShiftKeyDown() return Sim.modifiers.shift end
function IsControlKeyDown() return Sim.modifiers.ctrl end
function IsAltKeyDown() return Sim.modifiers.alt end
Sim.modifiers = {}

Sim.cvars = { rotateMinimap = "0" }
function GetCVar(name) return Sim.cvars[name] end
C_CVar = { GetCVar = GetCVar }

function GetFileIDFromPath(path) return nil end
function HideUIPanel(frame) frame:Hide() end

function CreateColor(r, g, b, a)
	return { r = r, g = g, b = b, a = a or 1, GetRGBA = function(c) return c.r, c.g, c.b, c.a end }
end

local Vector2D = {}
Vector2D.__index = Vector2D
function Vector2D:GetXY() return self.x, self.y end
function CreateVector2D(x, y)
	assert(type(x) == "number" and type(y) == "number", "CreateVector2D: numbers expected")
	return setmetatable({ x = x, y = y }, Vector2D)
end

C_Timer = {
	After = function(seconds, fn)
		assert(type(seconds) == "number" and type(fn) == "function", "C_Timer.After: seconds, function expected")
		Sim.timers[#Sim.timers + 1] = { at = Sim.time + seconds, fn = fn }
	end,
}

STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
LEVEL = "Level"
RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, colorStr = "ffffffff" } end })
LOCALIZED_CLASS_NAMES_MALE = setmetatable({}, { __index = function(_, k) return k end })
LOCALIZED_CLASS_NAMES_FEMALE = LOCALIZED_CLASS_NAMES_MALE
SlashCmdList = {}
UISpecialFrames = {}

Sim.unknownEvents = {}

---------------------------------------------------------------------------
-- The standard frames
---------------------------------------------------------------------------

Sim.UIParent = new("Frame", "UIParent", nil)
allFrames[#allFrames + 1] = Sim.UIParent
UIParent = Sim.UIParent
WorldFrame = CreateFrame("Frame", "WorldFrame")

DEFAULT_CHAT_FRAME = CreateFrame("Frame", "ChatFrame1", UIParent)
function DEFAULT_CHAT_FRAME:AddMessage(msg)
	assert(type(msg) == "string", "AddMessage: string expected")
	Sim.prints[#Sim.prints + 1] = msg
end
function ChatFrame_OpenChat(text) Sim.chat = text end
ChatFrameUtil = { OpenChat = function(text) Sim.chat = text end }

GameFontNormal = { GetFont = function() return STANDARD_TEXT_FONT, 12, "" end }
GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent, "GameTooltipTemplate")
GameTooltip:Hide()

MinimapCluster = CreateFrame("Frame", "MinimapCluster", UIParent)
MinimapCluster:SetSize(230, 230)
MinimapCluster:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
Minimap = new("Minimap", "Minimap", nil)
attach(Minimap, MinimapCluster, "children")
allFrames[#allFrames + 1] = Minimap
Minimap:SetSize(140, 140)
Minimap:SetPoint("CENTER", MinimapCluster, "TOP", 9, -92)
Minimap:EnableMouse(true)
Minimap:EnableMouseWheel(true)
for _, name in ipairs({ "MinimapBorder", "MinimapBorderTop", "MinimapZoneTextButton" }) do
	local f = CreateFrame("Frame", name, MinimapCluster)
	f:SetAllPoints(Minimap)
end
-- A button another addon hung on the minimap, and a GatherMate-style pin.
Sim.minimapButton = CreateFrame("Button", "LibDBIcon10_SomeAddon", Minimap)
Sim.minimapButton:SetSize(31, 31)
Sim.minimapButton:SetPoint("CENTER", Minimap, "BOTTOMLEFT", 10, 10)
Sim.gatherPin = CreateFrame("Frame", "GatherMatePin1", Minimap)
Sim.gatherPin:SetSize(12, 12)
Sim.gatherPin:SetPoint("CENTER", Minimap, "CENTER", 20, 20)
-- Blizzard's hover handler (Blizzard_Minimap): while the Minimap has the
-- mouse, GameTooltip shows the blips under the cursor, every frame.
function Minimap_OnUpdate(self)
	GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
	GameTooltip:SetMinimapMouseover()
end
Minimap:SetScript("OnEnter", function(self) self:SetScript("OnUpdate", Minimap_OnUpdate) end)
Minimap:SetScript("OnLeave", function(self)
	self:SetScript("OnUpdate", nil)
	GameTooltip:Hide()
end)
-- HereBeDragons-Pins (GatherMate's pin above is one of its pins): places
-- them on whatever frame it's given as the minimap.
local hbdPins = { Minimap = Minimap, minimapPins = { [Sim.gatherPin] = {} } }
function hbdPins:SetMinimapObject(obj)
	self.Minimap = obj or Minimap
	assert(self.Minimap.GetZoom, "SetMinimapObject: the minimap object needs GetZoom")
	self.Minimap:GetZoom()
	for pin in pairs(self.minimapPins) do
		pin:SetParent(self.Minimap)
		pin:ClearAllPoints()
		pin:SetPoint("CENTER", self.Minimap, "CENTER", 20, 20)
	end
end
Sim.hbdPins = hbdPins
Sim.libs = { ["HereBeDragons-Pins-2.0"] = hbdPins }
-- LibStub: callable, and its libraries listed in .libs as in the real one.
LibStub = setmetatable({ libs = Sim.libs, minors = {} }, {
	__call = function(self, name, silent)
		local lib = Sim.libs[name]
		if not lib and not silent then error("Cannot find a library instance of " .. tostring(name)) end
		return lib
	end,
})
function LibStub:IterateLibraries() return pairs(self.libs) end

-- Retail-engine frames can pin their frame level (Questie does on its map
-- icons): a fixed frame ignores SetFrameLevel until unfixed.
local methods = classes.Frame.methods
local setLevel = methods.SetFrameLevel
function methods:SetFrameLevel(l)
	if S[self].fixedLevel then return end
	setLevel(self, l)
end
function methods:SetFixedFrameLevel(on) S[self].fixedLevel = not not on end
function methods:HasFixedFrameLevel() return S[self].fixedLevel == true end

-- Questie's own renamed copy, HereBeDragonsQuestie-Pins-2.0, shaped like the
-- real one (Questie/Libs/HereBeDragons/HereBeDragons-Pins-2.0.lua): pins by
-- world yards (x = west, y = north) in minimapPins / worldmapPins, keyed by
-- the addon's frame ("icon"), with registries by ref. Its world-map provider
-- gives each pin on Blizzard's current map (WorldMapFrame.mapID, a zone) a
-- pin frame on the map's canvas and parents the icon to it; releasing one
-- hands the icon to UIParent, hidden. It refreshes when the map opens on
-- another map, or after a removal (Questie's forceUpdate). Not loaded until
-- a scenario calls Sim.LoadQuestie(), as if Questie loaded later.
local HBD_SHOW_CURRENT, HBD_SHOW_WORLD = -1, 3
function Sim.LoadQuestie()
	if Sim.questiePins then return Sim.questiePins end
	HBD_PINS_WORLDMAP_SHOW_CURRENT, HBD_PINS_WORLDMAP_SHOW_WORLD = HBD_SHOW_CURRENT, HBD_SHOW_WORLD
	local pins = {
		Minimap = Minimap, minimapPins = {}, activeMinimapPins = {}, minimapPinRegistry = {},
		worldmapPins = {}, worldmapPinRegistry = {}, worldmapProvider = { forceUpdate = false },
	}
	local provider = pins.worldmapProvider
	local canvas = WorldMapFrame.canvas
	local free, used = {}, {}
	local function release(pin)
		used[pin] = nil
		if pin.icon then
			pin.icon:Hide()
			pin.icon:SetParent(UIParent)
			pin.icon:ClearAllPoints()
			pin.icon = nil
		end
		pin:Hide()
		free[#free + 1] = pin
	end
	function provider:RemovePinByIcon(icon)
		for pin in pairs(used) do
			if pin.icon == icon then release(pin) end
		end
	end
	function provider:HandlePin(icon, data)
		local id = WorldMapFrame.mapID
		if data.uiMapID ~= id then return end -- (zone maps only, here)
		local pin = table.remove(free) or CreateFrame("Frame", nil, canvas)
		pin:SetSize(1, 1)
		pin:Show()
		used[pin] = true
		pin.icon = icon
		icon:SetParent(pin)
		icon:ClearAllPoints()
		icon:SetPoint("CENTER", pin, "CENTER")
		icon:Show()
	end
	function provider:RefreshAllData()
		if self.lastMap == WorldMapFrame.mapID and not self.forceUpdate then return end
		for pin in pairs(used) do release(pin) end
		for icon, data in pairs(pins.worldmapPins) do self:HandlePin(icon, data) end
		self.lastMap, self.forceUpdate = WorldMapFrame.mapID, false
	end
	WorldMapFrame:HookScript("OnShow", function() provider:RefreshAllData() end)
	local function world(uiMapID, x, y)
		local m = Sim.maps[uiMapID]
		local col, row = m[5] + (m[7] - m[5]) * x, m[6] + (m[8] - m[6]) * y
		return (32 - col) * 1600 / 3, (32 - row) * 1600 / 3, m[4] -- west, north
	end
	local function place(icon, data)
		local px, py = UnitPosition("player")
		if not px then return icon:Hide() end
		-- Scaled as the Minimap's own yards per pixel (radius from its zoom).
		local r = C_Minimap and C_Minimap.GetViewRadius() or 233
		local s = pins.Minimap:GetWidth() / 2 / r
		icon:ClearAllPoints()
		icon:SetPoint("CENTER", pins.Minimap, "CENTER", (py - data.x) * s, (px - data.y) * s)
		icon:Show()
	end
	function pins:AddMinimapIconMap(ref, icon, uiMapID, x, y, showInParentZone, floatOnEdge)
		local wx, wy, inst = world(uiMapID, x, y)
		self.minimapPinRegistry[ref] = self.minimapPinRegistry[ref] or {}
		self.minimapPinRegistry[ref][icon] = true
		self.minimapPins[icon] = { instanceID = inst, x = wx, y = wy, uiMapID = uiMapID, floatOnEdge = floatOnEdge }
		icon:SetParent(self.Minimap)
		place(icon, self.minimapPins[icon])
	end
	function pins:SetMinimapObject(obj)
		self.Minimap = obj or Minimap
		assert(self.Minimap.GetZoom and self.Minimap.GetWidth, "SetMinimapObject: the minimap object needs GetZoom")
		for icon, data in pairs(self.minimapPins) do
			icon:SetParent(self.Minimap)
			place(icon, data)
		end
	end
	function pins:AddWorldMapIconMap(ref, icon, uiMapID, x, y, showFlag, frameLevel)
		assert(type(icon) == "table" and icon.SetPoint, "AddWorldMapIconMap: 'icon' must be a frame")
		local wx, wy, inst = world(uiMapID, x, y)
		self.worldmapPinRegistry[ref] = self.worldmapPinRegistry[ref] or {}
		self.worldmapPinRegistry[ref][icon] = true
		local t = self.worldmapPins[icon] or {}
		t.instanceID, t.x, t.y, t.uiMapID, t.worldMapShowFlag, t.frameLevelType = inst, wx, wy, uiMapID, showFlag or 0, frameLevel
		self.worldmapPins[icon] = t
		provider:HandlePin(icon, t)
	end
	function pins:RemoveWorldMapIcon(ref, icon)
		if not ref or not icon or not self.worldmapPinRegistry[ref] then return end
		self.worldmapPinRegistry[ref][icon] = nil
		self.worldmapPins[icon] = nil
		provider:RemovePinByIcon(icon)
		provider.forceUpdate = true
	end
	Sim.questiePins = pins
	Sim.libs["HereBeDragonsQuestie-Pins-2.0"] = pins
	Sim.libs["HereBeDragonsQuestie-2.0"] = {}
	Questie = Questie or { name = "Questie" }
	return pins
end

-- A Questie map icon: a button at Questie's fixed frame level, hidden until placed.
function Sim.QuestieIcon()
	local icon = CreateFrame("Button", nil, UIParent)
	icon:SetSize(16, 16)
	icon:EnableMouse(true)
	icon:SetFrameLevel(2016)
	if icon.SetFixedFrameLevel then icon:SetFixedFrameLevel(true) end
	icon:Hide()
	return icon
end

WorldMapFrame = CreateFrame("Frame", "WorldMapFrame", UIParent)
WorldMapFrame:SetSize(1000, 700)
WorldMapFrame:SetPoint("CENTER")
WorldMapFrame:SetFrameStrata("HIGH")
WorldMapFrame:Hide()
WorldMapFrame.canvas = CreateFrame("Frame", nil, WorldMapFrame)
WorldMapFrame.canvas:SetAllPoints()
WorldMapFrame.mapID = 1429 -- the map it shows (Elwynn Forest)
-- The keybindings: M toggles the world map; L (Retail-engine clients) opens it
-- on the quest log.
function ToggleWorldMap() WorldMapFrame:SetShown(not WorldMapFrame:IsShown()) end
function ToggleQuestLog() WorldMapFrame:SetShown(not WorldMapFrame:IsShown()) end

C_Minimap = {
	GetViewRadius = function()
		local d = ({ [0] = 466.67, 400, 333.33, 266.67, 200, 133.33 })[Minimap:GetZoom()]
		return d / 2
	end,
	SetMinimapInsetInfo = function(minAngle, maxAngle, scalar) Sim.rimInset = scalar end,
	ClearMinimapInsetInfo = function() Sim.rimInset = nil end,
	-- Tracking: the client keeps it per character (a CVar).
	GetNumTrackingTypes = function() return #Sim.tracking end,
	GetTrackingInfo = function(i)
		local t = Sim.tracking[i]
		return t and { name = t.name, texture = 136456, active = t.active, type = "spell", subType = 2, spellID = t.spellID }
	end,
	GetTrackingFilter = function(i)
		local t = Sim.tracking[i]
		return t and { filterID = t.filterID, spellID = t.spellID }
	end,
	SetTracking = function(i, on)
		assert(Sim.tracking[i] and type(on) == "boolean", "SetTracking: index, boolean expected")
		Sim.tracking[i].active = on
		C_Timer.After(0, function() Sim.FireEvent("MINIMAP_UPDATE_TRACKING") end)
	end,
	IsTrackingHiddenQuests = function() return false end,
}
Sim.tracking = {
	{ name = "Flight Master", filterID = 8, active = true },
	{ name = "Find Herbs", spellID = 2383, active = true },
	{ name = "Track Quest POIs", filterID = 65536, active = true },
	{ name = "Points of Interest", filterID = 8192, active = false },
	{ name = "Mailbox", filterID = 64, active = true },
}

-- Context menus (retail-style MenuUtil): records the menu so scenarios can
-- pick entries. Classic flavors have none, so the addon's fallback runs.
local function description(kind, text, isSelected, onSelect, data)
	local d = { kind = kind, text = text, isSelected = isSelected, onSelect = onSelect, data = data, items = {} }
	function d:CreateTitle(t) local e = description("title", t); table.insert(self.items, e); return e end
	function d:CreateDivider() local e = description("divider"); table.insert(self.items, e); return e end
	function d:CreateButton(t, fn, dat) local e = description("button", t, nil, fn, dat); table.insert(self.items, e); return e end
	function d:CreateRadio(t, sel, fn, dat) local e = description("radio", t, sel, fn, dat); table.insert(self.items, e); return e end
	function d:CreateCheckbox(t, sel, fn, dat) local e = description("checkbox", t, sel, fn, dat); table.insert(self.items, e); return e end
	function d:SetScrollMode(h) end
	function d:SetEnabled(e) self.enabled = e end
	function d:IsEnabled()
		if type(self.enabled) == "function" then return self.enabled(self) end
		return self.enabled ~= false
	end
	function d:SetTooltip(fn) assert(type(fn) == "function", "SetTooltip: function expected"); self.tooltip = fn end
	return d
end
MenuResponse = { Open = 1, Refresh = 2, Close = 3, CloseAll = 4 }
MenuUtil = {
	CreateContextMenu = function(owner, generator)
		local root = description("root")
		generator(owner, root)
		Sim.menu = root
		return { Close = function() Sim.menu = nil end, IsShown = function() return Sim.menu == root end }
	end,
}

function Sim.MenuItems(kind)
	local out = {}
	local function walk(d)
		for _, e in ipairs(d.items) do
			if not kind or e.kind == kind then out[#out + 1] = e end
			walk(e)
		end
	end
	if Sim.menu then walk(Sim.menu) end
	return out
end

---------------------------------------------------------------------------
-- The world: a few uiMaps over real tile coordinates, the player, quests.
-- Maps are given in tile space and converted to world yards like the game:
-- north = (32 - row) * 533.33, west = (32 - col) * 533.33.
---------------------------------------------------------------------------

local TILE = 1600 / 3
local function toWorld(col, row) return (32 - row) * TILE, (32 - col) * TILE end

Enum = { UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 } }
-- Addon memory (every client) and the addon profiler (Retail-engine clients).
Sim.addons = { { "MagicMap", 2400 }, { "Questie", 48000 }, { "Details", 9000 } }
function UpdateAddOnMemoryUsage() end
function GetNumAddOns() return #Sim.addons end
function GetAddOnInfo(i) return Sim.addons[i] and Sim.addons[i][1] end
function GetAddOnMemoryUsage(i)
	for j, a in ipairs(Sim.addons) do
		if j == i or a[1] == i then return a[2] end
	end
	return 0
end
Enum.AddOnProfilerMetric = { SessionAverageTime = 0, RecentAverageTime = 1, EncounterAverageTime = 2, LastTime = 3, PeakTime = 4 }
C_AddOnProfiler = {
	IsEnabled = function() return true end,
	GetAddOnMetric = function(name, metric) assert(type(name) == "string" and metric, "GetAddOnMetric: name, metric") return 0.05 end,
	GetOverallMetric = function(metric) return 0.4 end,
	GetTopKAddOnsForMetric = function(metric, k)
		return { { addOnName = "Questie", value = 0.2 }, { addOnName = "MagicMap", value = 0.05 } }
	end,
}
if C_Minimap then Enum.MinimapTrackingFilter = { Unfiltered = 0, TaxiNode = 8, Mailbox = 64, POI = 8192, QuestPOIs = 65536 } end
local T = Enum.UIMapType

Sim.maps = {
	-- uiMapID = { name, mapType, parent, instance, col0, row0, col1, row1 }
	[947] = { "Azeroth", T.World, nil, nil },
	[1415] = { "Eastern Kingdoms", T.Continent, 947, 0, 22, 4, 44, 60 },
	[1414] = { "Kalimdor", T.Continent, 947, 1, 14, 4, 44, 60 },
	[1429] = { "Elwynn Forest", T.Zone, 1415, 0, 30.6, 47.6, 35.4, 51.4 },
	[1436] = { "Westfall", T.Zone, 1415, 0, 27.6, 49.0, 31.4, 55.2 },
	[1453] = { "Stormwind City", T.Zone, 1415, 0, 30.3, 46.6, 32.4, 48.6 },
	[1426] = { "Dun Morogh", T.Zone, 1415, 0, 30.0, 37.0, 37.0, 42.0 },
	[1455] = { "Ironforge", T.Zone, 1415, 0, 32.4, 38.5, 33.6, 39.6 },
	[1411] = { "Durotar", T.Zone, 1414, 1, 40.0, 25.0, 44.0, 32.0 },
	[1601] = { "Fargodeep Mine", T.Micro, 1429, 0, 31.6, 50.1, 32.0, 50.5 },
}

local function mapAt(inst, col, row, types)
	local best, bestArea
	for id, m in pairs(Sim.maps) do
		if m[4] == inst and types[m[2]] and col >= m[5] and col <= m[7] and row >= m[6] and row <= m[8] then
			local area = (m[7] - m[5]) * (m[8] - m[6])
			if not best or area < bestArea then best, bestArea = id, area end
		end
	end
	return best
end

local function mapInfo(id)
	local m = Sim.maps[id]
	if not m then return nil end
	return { mapID = id, name = m[1], mapType = m[2], parentMapID = m[3] or 0, flags = 0 }
end

-- The player: tile coordinates on an instance, moving each step.
Sim.player = { inst = 0, col = 31.95, row = 49.75, facing = 0, speed = 0 }
Sim.restricted = false -- an instance that withholds your position
Sim.onStep = function(elapsed)
	local p = Sim.player
	if p.speed ~= 0 then
		p.col = p.col + math.sin(p.facing) * p.speed * elapsed / TILE
		p.row = p.row - math.cos(p.facing) * p.speed * elapsed / TILE
	end
end

function UnitPosition(unit)
	if Sim.restricted then return nil end
	local u = Sim.units[unit]
	if unit ~= "player" and u and u.col then
		local north, west = toWorld(u.col, u.row)
		return north, west, 0, Sim.player.inst
	end
	if unit ~= "player" then return nil end
	local p = Sim.player
	local north, west = toWorld(p.col, p.row)
	return north, west, 0, p.inst
end
function GetPlayerFacing() return (not Sim.restricted) and Sim.player.facing or nil end
function GetInstanceInfo()
	local p = Sim.player
	return "Instance", Sim.restricted and "party" or "none", 0, "", 5, 0, false, p.inst
end
function IsIndoors() return Sim.indoors == true end
function GetZoneText()
	local id = mapAt(Sim.player.inst, Sim.player.col, Sim.player.row, { [T.Zone] = true })
	return id and Sim.maps[id][1] or ""
end
function GetSubZoneText() return "Goldshire" end

Sim.units = { player = { name = "Tester", class = "MAGE", level = 5 } }
Sim.unitSubtitle = {}
function UnitName(unit) local u = Sim.units[unit]; return u and u.name end
function UnitIsGhost(unit) return unit == "player" and Sim.ghost or false end
function UnitExists(unit) return Sim.units[unit] ~= nil end
function UnitClass(unit) local u = Sim.units[unit]; if u then return u.class, u.class, 8 end end
function UnitGUID(unit) local u = Sim.units[unit]; return u and (u.guid or "Player-1-00000001") end
function UnitIsPlayer(unit) local u = Sim.units[unit]; return u ~= nil and u.npc == nil end
function UnitClassification(unit) return "normal" end
function UnitLevel(unit) local u = Sim.units[unit]; return u and (u.level or 1) or 0 end
-- A group: Sim.group lists the other members' unit tokens (party1...),
-- each in Sim.units with a tile position (col, row) on the player's instance.
Sim.group = {}
function GetNumGroupMembers() return #Sim.group > 0 and #Sim.group + 1 or 0 end
function IsInRaid() return false end
function UnitIsUnit(a, b) return a == b end
function UnitIsDeadOrGhost(unit) local u = Sim.units[unit]; return u ~= nil and u.dead == true end

C_Map = {}
function C_Map.GetMapInfo(id) return mapInfo(id) end
function C_Map.GetBestMapForUnit(unit)
	if unit ~= "player" then return nil end
	local p = Sim.player
	return mapAt(p.inst, p.col, p.row, { [T.Zone] = true, [T.Micro] = Sim.indoors or nil })
		or mapAt(p.inst, p.col, p.row, { [T.Continent] = true })
end
function C_Map.GetWorldPosFromMapPos(id, pos)
	local m = Sim.maps[id]
	assert(type(pos) == "table" and pos.x, "GetWorldPosFromMapPos: vector expected")
	if not (m and m[4]) then return nil end
	local col = m[5] + (m[7] - m[5]) * pos.x
	local row = m[6] + (m[8] - m[6]) * pos.y
	return m[4], CreateVector2D(toWorld(col, row))
end
local function normalized(id, col, row)
	local m = Sim.maps[id]
	return (col - m[5]) / (m[7] - m[5]), (row - m[6]) / (m[8] - m[6])
end
function C_Map.GetPlayerMapPosition(id, unit)
	local m = Sim.maps[id]
	local p = Sim.player
	if Sim.restricted or not (m and m[4] == p.inst) then return nil end
	return CreateVector2D(normalized(id, p.col, p.row))
end
function C_Map.GetMapInfoAtPosition(id, x, y)
	local m = Sim.maps[id]
	if not (m and m[4]) then return nil end
	local col, row = m[5] + (m[7] - m[5]) * x, m[6] + (m[8] - m[6]) * y
	return mapInfo(mapAt(m[4], col, row, { [T.Zone] = true }))
end
Sim.areaNames = { [87] = "Goldshire" }
function C_Map.GetAreaInfo(areaID) return Sim.areaNames[areaID] or ("Area " .. areaID) end
-- Level ranges: (playerMin, playerMax, petMin, petMax); 0s for maps without one.
Sim.mapLevels = { [1429] = { 1, 10 }, [1436] = { 9, 18 }, [1426] = { 1, 10 }, [1411] = { 1, 10 } }
function C_Map.GetMapLevels(id)
	local l = Sim.mapLevels[id]
	if l then return l[1], l[2], 0, 0 end
	return 0, 0, 0, 0
end
Sim.waypoint = nil
function C_Map.CanSetUserWaypointOnMap(id) return Sim.maps[id] ~= nil and Sim.maps[id][2] ~= T.World end
function C_Map.SetUserWaypoint(point)
	assert(type(point) == "table" and point.uiMapID and point.position, "SetUserWaypoint: UiMapPoint expected")
	Sim.waypoint = point
end
function C_Map.GetUserWaypoint() return Sim.waypoint end
function C_Map.ClearUserWaypoint() Sim.waypoint = nil end
UiMapPoint = {
	CreateFromCoordinates = function(id, x, y, z) return { uiMapID = id, position = CreateVector2D(x, y), z = z } end,
	CreateFromVector2D = function(id, v, z) return { uiMapID = id, position = v, z = z } end,
}

C_TaxiMap = {
	GetTaxiNodesForMap = function(id)
		if id ~= 1429 and id ~= 1415 then return {} end
		return { { nodeID = 2, name = "Stormwind, Elwynn", position = CreateVector2D(0.3, 0.1), atlasName = "TaxiNode_Alliance", faction = 2 } }
	end,
}
C_DeathInfo = {
	GetGraveyardsForMap = function(id)
		if id ~= 1429 then return {} end
		return { { graveyardID = 1, name = "Goldshire", position = CreateVector2D(0.4, 0.6) } }
	end,
	GetCorpseMapPosition = function(id) return Sim.corpse and Sim.corpse[id] end,
}
C_EncounterJournal = {
	GetDungeonEntrancesForMap = function(id)
		if id ~= 1436 then return {} end
		return { { journalInstanceID = 63, name = "Deadmines", description = "A dungeon", position = CreateVector2D(0.42, 0.72), atlasName = "Dungeon" } }
	end,
}
C_MapExplorationInfo = {
	-- Sim.unexplored: nothing explored anywhere (the client returns nil then).
	GetExploredAreaIDsAtPosition = function(id, pos)
		assert(type(pos) == "table" and pos.x, "GetExploredAreaIDsAtPosition: vector expected")
		if Sim.unexplored then return nil end
		return { 87 }
	end,
}
C_AreaPoiInfo = {
	GetAreaPOIForMap = function(id) return id == 1429 and { 501 } or {} end,
	GetAreaPOIInfo = function(id, poiID)
		return { areaPoiID = poiID, name = "Lion's Pride Inn", description = "An inn", position = CreateVector2D(0.42, 0.66), atlasName = "poi-town" }
	end,
}
C_VignetteInfo = {
	GetVignettes = function() return { "Vignette-0-1" } end,
	GetVignetteInfo = function(guid) return { vignetteGUID = guid, name = "Mother Fang", atlasName = "VignetteKill", onMinimap = true } end,
	GetVignettePosition = function(guid, id) return id == 1429 and CreateVector2D(0.38, 0.79) or nil end,
}
-- Atlases: the ones MagicMap asks for that Retail-engine clients have
-- (checked against Forever's UiTextureAtlasMember); none on classic clients.
local ATLASES = {}
for _, base in ipairs({ "ui-hud-minimap-zoom-in", "ui-hud-minimap-zoom-out" }) do
	ATLASES[base], ATLASES[base .. "-mouseover"], ATLASES[base .. "-down"] = true, true, true
end
for _, name in ipairs({ "redbutton-expand-c60", "redbutton-expand-pressed-c60", "redbutton-highlight-c60" }) do ATLASES[name] = true end
for _, name in ipairs({ "redbutton-expand", "redbutton-expand-pressed", "redbutton-highlight",
	"ui-hud-minimap-arrow-player", "ui-hud-minimap-arrow-questtracking", "minimaparrow" }) do
	ATLASES[name] = true
end
-- The metal frame's pieces, sized as Forever reports them: the edges far
-- bigger than the metal you see (which once shrank minimap mode's map).
for _, name in ipairs({ "UI-Frame-Metal-CornerBottomLeft", "UI-Frame-Metal-CornerBottomRight" }) do ATLASES[name] = { 32, 32 } end
ATLASES["_UI-Frame-Metal-EdgeBottom"] = { 256, 200 }
ATLASES["UI-QuestPoi-QuestNumber"], ATLASES["deathrecap-icon-tombstone"] = { 32, 32 }, { 15, 20 }
ATLASES["!UI-Frame-Metal-EdgeLeft"] = { 200, 256 }
ATLASES["!UI-Frame-Metal-EdgeRight"] = { 200, 256 }
C_Texture = {
	GetAtlasInfo = function(name)
		if ATLASES[name] then
			local size = type(ATLASES[name]) == "table" and ATLASES[name] or { 16, 16 }
			return { file = "atlas/" .. name, width = size[1], height = size[2], leftTexCoord = 0, rightTexCoord = 1, topTexCoord = 0, bottomTexCoord = 1 }
		end
	end,
}

-- Quests: one in Elwynn, with an objective area.
Sim.quests = {
	[60] = { title = "Kobold Candles", map = 1429, x = 0.35, y = 0.55, complete = false,
		objectives = { { text = "Large Candle: 0/8", type = "item", finished = false } } },
	[62] = { title = "The Fargodeep Mine", map = 1429, x = 0.40, y = 0.80, complete = true,
		objectives = { { text = "Scout through the Fargodeep Mine", type = "event", finished = true } } },
}
C_QuestLog = {
	GetQuestsOnMap = function(id)
		local out = {}
		for questID, q in pairs(Sim.quests) do
			if q.map == id then out[#out + 1] = { questID = questID, x = q.x, y = q.y, isMapIndicatorQuest = false } end
		end
		table.sort(out, function(a, b) return a.questID < b.questID end)
		return out
	end,
	GetTitleForQuestID = function(questID) local q = Sim.quests[questID]; return q and q.title end,
	IsComplete = function(questID) local q = Sim.quests[questID]; return q and q.complete end,
	GetQuestObjectives = function(questID) local q = Sim.quests[questID]; return q and q.objectives or {} end,
	AddQuestWatch = function(questID) Sim.watched = questID; return true end,
}
C_SuperTrack = {
	GetSuperTrackedQuestID = function() return Sim.superTracked or 0 end,
	SetSuperTrackedQuestID = function(id) Sim.superTracked = id end,
	SetSuperTrackedUserWaypoint = function(on) if on then Sim.superTracked = 0 end end,
}
C_TooltipInfo = {
	GetUnit = function(unit)
		local name = UnitName(unit)
		return name and { lines = { { leftText = name }, { leftText = Sim.unitSubtitle[unit] or "Level 10" } } }
	end,
}
-- 12.x secret values: readable, but any arithmetic or comparison on them
-- from addon code is an error. GetUnitSpeed is one.
local SECRET = setmetatable({}, {
	__add = function() error("attempt to perform arithmetic on a secret number value") end,
	__lt = function() error("attempt to compare a secret number value") end,
	__tostring = function() return "<secret number>" end,
})
function issecretvalue(v) return v == SECRET end
function GetUnitSpeed(unit) return SECRET end

-- Quests to pick up (C_QuestLine, the world map's quest offers): given once
-- a map has been asked for.
Sim.offers = { [1429] = { { questID = 70, questName = "Wolves Across the Border", questLineName = "", questLineID = 1,
	x = 0.45, y = 0.62, isHidden = false, inProgress = false, startMapID = 1429 } } }
Sim.offersAsked = {}
C_QuestLine = {
	RequestQuestLinesForMap = function(id)
		assert(type(id) == "number", "RequestQuestLinesForMap: uiMapID expected")
		Sim.offersAsked[id] = true
		C_Timer.After(0.1, function() Sim.FireEvent("QUESTLINE_UPDATE", false) end)
	end,
	GetAvailableQuestLines = function(id) return Sim.offersAsked[id] and Sim.offers[id] or {} end,
}

function CanMerchantRepair() return Sim.canRepair == true end
function ButtonFrameTemplate_HidePortrait(f) end
function ButtonFrameTemplate_HideButtonBar(f) end

return Sim
