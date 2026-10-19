-- A small simulation of the WoW client's UI and map API, enough to load
-- MagicMap headlessly and drive it: frames and regions with anchor-based
-- layout, show/hide propagation, scripts and hooks, events, timers, mouse
-- input, tooltips, the Minimap, menus, and a mock world for C_Map.
--
-- It isn't the real client: it catches errors (nil calls, typos, bad
-- arithmetic, wrong assumptions about API shape) on the code paths a
-- scenario drives, not rendering problems. Unknown methods are
-- simply absent, as in the game, so calling one is an error.
--
-- Where the client is known to differ from plain Lua and a naive mock, it
-- copies it (docs/v1-plan.md M0.6): a priced clock (Sim.Price, off by
-- default), quest blobs laid out a frame late (L1), Forever's oversized edge
-- atlases (L2), the Minimap's view radius 0 while it zooms (E3/E6),
-- HereBeDragons pins with renamed copies (G6), protected frames refusing
-- insecure calls in combat (K2: Sim.protectedCalls), and x/0 raising
-- (Sim.Strict, opt-in, E3).
--
-- The client it simulates is WoW Forever (a Retail-engine client).
-- Ported from the MagicMap spike (its QuestieDB mocks dropped).

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

-- Taint, roughly (K2): the client's own code runs secure only from a key press
-- (Sim.Press, Sim.Escape); anything it calls of an addon's (scripts, hooks) runs
-- insecure, and so does everything else. Only insecure calls are refused.
local secure = false
local function Secure(fn, ...)
	local was = secure
	secure = true
	local ok, a, b = xpcall(fn, traceback, ...)
	secure = was
	if not ok then error(a, 0) end
	return a, b
end

-- The priced clock (Sim.Price(true)): what the client charges that plain Lua doesn't,
-- in ms added to debugprofilestop, as measured in game (docs/evidence/perf-m0.md):
-- probe: one Minimap mouseover read (a 400-probe sweep in 2 frames of 0.5 ms);
-- shown, shownLine: each region (line) a frame's Show makes visible (the swaps' ms over
-- their live regions); Show, Hide, SetScale, SetAlpha, SetPoint: a frame's own call, per
-- region under it, hidden ones too (/mma bench regions, canvases of 1000 clear Lines).
-- One widget call's own cost is the counted clock's (Sim.Counted: 3 us, above the bench's
-- 0.22-1.7 us for SetPoint, SetStartPoint, Create*, SetParent).
Sim.PRICES = { probe = 0.002, shown = 0.02, shownLine = 0.035,
	Show = 0.000004, Hide = 0.00002, SetScale = 0.00001, SetAlpha = 0.000004, SetPoint = 0.000001 }
Sim.pricing, Sim.priced = false, 0
function Sim.Price(on) Sim.pricing = on and true or false end

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
-- Allocates nothing (the client's layout costs no Lua memory; allocation per frame is measured):
-- the anchors being resolved (a cycle answers nil) are a stack, an array: a hash set's new keys rehash.
local resolving, depth = {}, 0
-- One axis from its anchors: the first (fa at va) and the last whose fraction differs (fb at vb).
local function solve(fa, va, fb, vb, size)
	if fa and fb then
		local span = (vb - va) / (fb - fa)
		return va - fa * span, span
	elseif fa and size then
		return va - fa * size, size
	end
end
local function rect(obj)
	if obj == Sim.UIParent then return 0, 0, UI_W, UI_H end
	for i = 1, depth do
		if resolving[i] == obj then return nil end
	end
	local st = S[obj]
	local scale = effScale(obj)
	local w, h = st.width and st.width * scale, st.height and st.height * scale
	local xfa, xva, xfb, xvb, yfa, yva, yfb, yvb
	depth = depth + 1
	resolving[depth] = obj
	local points = st.points
	for i = 1, #points do
		local p = points[i]
		local rel = p.rel or st.parent or Sim.UIParent
		local rl, rb, rw, rh = rect(rel)
		if rl then
			local x = rl + rw * POINT_X[p.relPoint] + p.x * scale
			local y = rb + rh * POINT_Y[p.relPoint] + p.y * scale
			local fx, fy = POINT_X[p.point], POINT_Y[p.point]
			if not xfa then xfa, xva = fx, x elseif fx ~= xfa then xfb, xvb = fx, x end
			if not yfa then yfa, yva = fy, y elseif fy ~= yfa then yfb, yvb = fy, y end
		end
	end
	depth = depth - 1
	local left, width = solve(xfa, xva, xfb, xvb, w)
	local bottom, height = solve(yfa, yva, yfb, yvb, h)
	if not (left and bottom) then return nil end
	return left, bottom, width, height
end
Sim.Rect = rect

local VALID_POINTS = POINT_X
local charge -- (Visibility, below)

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
	local points, e = S[self].points, nil
	for i = #points, 1, -1 do
		if points[i].point == point then e = table.remove(points, i) end
	end
	e = e or (S[self].spare and table.remove(S[self].spare)) or {} -- reused (no garbage per SetPoint)
	e.point, e.rel, e.relPoint, e.x, e.y = point, rel, relPoint, x or 0, y or 0
	points[#points + 1] = e
	if isFrame(self) then charge("SetPoint", self) end
end

function Region:SetAllPoints(rel)
	self:ClearAllPoints()
	self:SetPoint("TOPLEFT", rel or S[self].parent, "TOPLEFT")
	self:SetPoint("BOTTOMRIGHT", rel or S[self].parent, "BOTTOMRIGHT")
end

-- Its anchors kept aside for the next SetPoint (the client's setters make no Lua garbage).
function Region:ClearAllPoints()
	local st = S[self]
	local points, spare = st.points, st.spare or {}
	st.spare = spare
	for i = #points, 1, -1 do
		spare[#spare + 1] = points[i]
		points[i] = nil
	end
end
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

local function regionsUnder(f)
	local n = #S[f].regions
	for _, c in ipairs(S[f].children) do n = n + regionsUnder(c) end
	return n
end
function charge(what, frame)
	if Sim.pricing then Sim.priced = Sim.priced + Sim.PRICES[what] * (frame and regionsUnder(frame) or 1) end
end
-- The lines and other regions a shown frame shows (each shown, as every frame between).
local function shownUnder(f, lines, others)
	for _, r in ipairs(S[f].regions) do
		if S[r].shown then
			if S[r].type == "Line" then lines = lines + 1 else others = others + 1 end
		end
	end
	for _, c in ipairs(S[f].children) do
		if S[c].shown then lines, others = shownUnder(c, lines, others) end
	end
	return lines, others
end

local function setShown(self, shown)
	local st = S[self]
	if st.shown == shown then return end
	if not isFrame(self) then st.shown = shown; return end -- a region: no scripts (and no garbage)
	charge(shown and "Show" or "Hide", self)
	local before = visibleFrames(self, {})
	st.shown = shown
	if shown and Sim.pricing and visible(self) then
		local lines, others = shownUnder(self, 0, 0)
		Sim.priced = Sim.priced + lines * Sim.PRICES.shownLine + others * Sim.PRICES.shown
	end
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
function Region:SetAlpha(a)
	assert(type(a) == "number", "SetAlpha: number expected")
	a = math.max(0, math.min(1, a))
	if a ~= S[self].alpha and isFrame(self) then charge("SetAlpha", self) end
	S[self].alpha = a
end
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
function Region:SetScale(s)
	assert(type(s) == "number" and s > 0, "SetScale: positive number expected")
	if s ~= S[self].scale and isFrame(self) then charge("SetScale", self) end
	S[self].scale = s
end
function Region:GetEffectiveScale() return effScale(self) end
function Region:IsProtected() return false end
-- Offsets grow (or shrink) the tested rect: top up, bottom down when negative.
function Region:IsMouseOver(top, bottom, left, right)
	local l, b, w, h = rect(self)
	if not l or not visible(self) then return false end
	local x, y = Sim.cursorX, Sim.cursorY
	return x >= l + (left or 0) and x <= l + w + (right or 0) and y >= b + (bottom or 0) and y <= b + h + (top or 0)
end
-- A frame moved to a new parent is re-based on it, as the client does: its strata the parent's
-- unless set (SetFrameStrata), its level just above the parent's unless fixed, and what it holds
-- moved by as many levels.
local function rebase(f, strata, delta)
	local st = S[f]
	if not st.strataSet then st.strata = strata end
	if not st.fixedLevel then st.level = math.max(0, st.level + delta) end
	for _, c in ipairs(st.children) do rebase(c, st.strata, delta) end
end
function Region:SetParent(parent)
	if type(parent) == "string" then parent = named[parent] end
	if not isFrame(self) then return attach(self, parent, "regions") end
	attach(self, parent, "children")
	if parent then rebase(self, S[parent].strata, S[parent].level + 1 - S[self].level) end
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
	local c = S[self].color or {} -- reused: the client's setters make no Lua garbage
	c[1], c[2], c[3], c[4] = r, g, b, a or 1
	S[self].color = c
	S[self].texture = nil
end
-- useSize: the atlas's size as the client reports it (Forever's edges: 200 px, L2).
function Texture:SetAtlas(atlas, useSize)
	assert(type(atlas) == "string", "SetAtlas: string expected")
	S[self].atlas = atlas
	local info = useSize and C_Texture.GetAtlasInfo(atlas)
	if info then setSize(self, info.width, info.height) end
end
function Texture:GetAtlas() return S[self].atlas end
function Texture:SetVertexColor(r, g, b, a)
	assert(type(r) == "number", "SetVertexColor: numbers expected")
	local v = S[self].vertex or {} -- reused: the client's setters make no Lua garbage
	v[1], v[2], v[3], v[4] = r, g, b, a
	S[self].vertex = v
end
function Texture:GetVertexColor() local v = S[self].vertex or { 1, 1, 1, 1 }; return v[1], v[2], v[3], v[4] or 1 end
function Texture:SetTexCoord(...)
	local n = select("#", ...)
	assert(n == 4 or n == 8, "SetTexCoord: 4 or 8 numbers expected")
	local t = S[self].texCoord or {}
	for i = 1, 8 do t[i] = (select(i, ...)) end
	S[self].texCoord = t
end
function Texture:SetDesaturated(on) S[self].desaturated = not not on end
function Texture:IsDesaturated() return S[self].desaturated end
function Texture:SetBlendMode(mode) S[self].blend = mode end
function Texture:SetRotation(r) assert(type(r) == "number", "SetRotation: number expected"); S[self].rotation = r end
-- Kept for the tests (the client snaps a texture unless told not to): test_spike_bugs.py T.Anchors.
function Texture:SetSnapToPixelGrid(on) S[self].snap = not not on end
function Texture:SetTexelSnappingBias(b) assert(type(b) == "number", "SetTexelSnappingBias: number expected"); S[self].bias = b end
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
	local e = S[self][which] or {}
	e[1], e[2], e[3], e[4] = point, rel or S[self].parent, x or 0, y or 0
	S[self][which] = e
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
-- The fonts the client loads (case and slash direction don't matter); another leaves the font string as it was.
local FONTS = {}
for _, path in ipairs({ "Fonts\\FRIZQT__.TTF", "Fonts\\MORPHEUS.TTF", "Fonts\\ARIALN.TTF", "Fonts\\skurri.ttf" }) do FONTS[path:lower()] = true end
function FontString:SetFont(path, size, flags)
	assert(type(path) == "string" and type(size) == "number", "SetFont: path and size expected")
	if not FONTS[(path:lower():gsub("/", "\\"))] then return false end
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
-- Its children take it too, those that haven't set their own (as they do when parented: rebase).
local function carry(f, s)
	for _, c in ipairs(S[f].children) do
		if not S[c].strataSet then S[c].strata = s; carry(c, s) end
	end
end
function Frame:SetFrameStrata(s)
	assert(STRATA[s], "SetFrameStrata: bad strata " .. tostring(s))
	S[self].strata, S[self].strataSet = s, true
	carry(self, s)
end
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
	local fs = tooltipLine(self, st.numLines)
	fs:SetText(text)
	S[fs].textColor = r and { r, g, b } or nil
end
function Tooltip:AddDoubleLine(left, right) self:AddLine(left) end
function Tooltip:SetText(text, r, g, b, a, wrap) self:ClearLines(); self:AddLine(text) end
function Tooltip:NumLines() return S[self].numLines or 0 end
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

-- The Minimap: zoom levels, and a view radius that follows them, a frame or
-- two late: 0 while a new zoom applies (Sim.ZOOM_FRAMES, from the frame it's set in).
local MinimapClass = class("Minimap", "Frame")
Sim.ZOOM_FRAMES = 2
function MinimapClass:GetZoom() return S[self].zoom or 0 end
function MinimapClass:SetZoom(z)
	assert(type(z) == "number" and z >= 0 and z <= 5, "SetZoom: 0..5 expected")
	if z ~= (S[self].zoom or 0) then S[self].zoomedAt = Sim.frame end
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
-- The pretend mouse (the controller's soft cursor): while
-- SetUsingSoftCursor(true), UpdateMouseoverAtPoint(x, y) (screen pixels)
-- moves the point C_TooltipInfo.GetMinimapMouseover() reads; off, it reads
-- the real cursor. Sim.minimapBlips = { { name, north, west } } (yards)
-- each answer within a square Sim.BLIP_HIT screen units of where they sit
-- on the shown Minimap, inside its view radius, whatever its scale or icon
-- scale (as the client does).
Sim.minimapBlips, Sim.BLIP_HIT, Sim.BLIP_STEP = {}, 8.1, 0.25 -- (the client's: 7.84 Minimap units at scale 1.02)
function MinimapClass:SetUsingSoftCursor(on) S[self].soft = on and true or false end
function MinimapClass:SetIconScale(s) S[self].iconScale = s end
function MinimapClass:UpdateMouseoverAtPoint(x, y)
	if S[self].soft then S[self].hoverX, S[self].hoverY = x, y end
end
local function blipsAt(m, px, py)
	if not visible(m) then return nil end
	local l, b, w, h = rect(m)
	-- The client seems to move its blips in steps as you walk: where it
	-- last placed you, refreshed every Sim.BLIP_STEP seconds.
	local pn, pw = UnitPosition("player")
	if not (l and pn) then return nil end
	local at = S[m].blipsAt
	if not at or Sim.time - at.t >= Sim.BLIP_STEP then
		at = at or {}
		at.n, at.w, at.t = pn, pw, Sim.time
		S[m].blipsAt = at
	end
	pn, pw = at.n, at.w
	local s = effScale(m)
	local W, H = w / s, h / s
	local fx, fy = (px - l) / s, (py - b) / s
	local r = C_Minimap.GetViewRadius()
	local u = r / (W / 2)
	local hit = Sim.BLIP_HIT / s
	local names -- made on a hit only: a miss allocates nothing (allocation per frame is measured)
	for _, blip in ipairs(Sim.minimapBlips) do
		local east, north = pw - blip[3], blip[2] - pn
		if east * east + north * north <= r * r then
			local bx, by = W / 2 + east / u, H / 2 + north / u
			if math.abs(fx - bx) <= hit and math.abs(fy - by) <= hit then names = names or {}; names[#names + 1] = blip[1] end
		end
	end
	return names
end
-- A probe (priced): what answers is a fresh TooltipData, as the client's (its
-- line's colour too), so every answer allocates; nothing there answers nil, after
-- making as much garbage (0.34 KB: in game every probe makes ~0.35-0.4 KB, docs/evidence/perf-m0.md).
C_TooltipInfo = {
	GetMinimapMouseover = function()
		charge("probe")
		local st = S[Minimap]
		local x, y = Sim.cursorX, Sim.cursorY
		if st.soft then x, y = st.hoverX, st.hoverY end
		local names = x and blipsAt(Minimap, x, y)
		if not names then
			Sim.missed = { type = 21, dataInstanceID = Sim.frame, lines = {}, args = {} }
			return nil
		end
		return { type = 21, dataInstanceID = Sim.frame,
			lines = { { type = 0, leftText = table.concat(names, "\n"), leftColor = CreateColor(1, 1, 1, 1) } } }
	end,
}

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

-- QuestPOIFrame (retail): draws quest blobs for one uiMap. Its layout is a
-- frame late (L1): a new size or anchor holds for DrawBlob and hit tests only
-- after the end of the frame (Sim.Step's layout pass), and a blob is drawn into
-- the rect laid out when DrawBlob is called: into nothing before the first.
local POI = class("QuestPOIFrame", "Frame")
local pois = {}
function POI:SetMapID(id) assert(type(id) == "number", "SetMapID: number expected"); S[self].mapID = id end
-- Quest areas are circles: Sim.blobShapes[questID] = { x, y, r } in its map's
-- normalized coordinates; a frame keeps, per quest drawn, the rect it went into.
Sim.blobShapes = {}
local NONE = {}
function POI:DrawBlob(questID, draw)
	assert(type(questID) == "number", "DrawBlob: questID expected")
	local st = S[self]
	st.blobs = st.blobs or {}
	local d, laid = st.blobs[questID] or {}, st.laid or NONE
	d[1], d[2], d[3], d[4] = laid[1], laid[2], laid[3], laid[4]
	st.blobs[questID] = d
end
function POI:DrawNone() if S[self].blobs then wipe(S[self].blobs) end end
local function layOut()
	for _, f in ipairs(pois) do
		local st = S[f]
		local l, b, w, h = rect(f)
		local laid = l and (st.laid or {})
		if laid then laid[1], laid[2], laid[3], laid[4] = l, b, w, h end
		st.laid = laid or nil
	end
end
function POI:SetFillTexture(t) end
function POI:SetFillAlpha(a) end
function POI:SetBorderTexture(t) end
function POI:SetBorderScalar(s) end
function POI:SetBorderAlpha(a) end
function POI:EnableMerging(on) end
function POI:EnableSmoothing(on) end
function POI:SetMergeThreshold(t) end
function POI:SetNumSplinePoints(n) end
-- The quest whose drawn area covers (x, y), normalized on the frame as laid out:
-- Sim.questUnderCursor if set (for tooltip tests), else one of its quests whose
-- circle, as drawn into its rect then, holds the point. Never laid out: none.
function POI:UpdateMouseOverTooltip(x, y)
	if Sim.questUnderCursor then return Sim.questUnderCursor end
	local laid = S[self].laid
	if not laid then return nil end
	local sx, sy = laid[1] + x * laid[3], laid[2] + (1 - y) * laid[4]
	for questID, d in pairs(S[self].blobs or NONE) do
		local c = Sim.blobShapes[questID]
		if c and d[1] and ((sx - d[1]) / d[3] - c[1]) ^ 2 + ((d[2] + d[4] - sy) / d[4] - c[2]) ^ 2 <= c[3] ^ 2 then return questID end
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
	if cls == "QuestPOIFrame" then pois[#pois + 1] = f end
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

-- (Scripts run insecure: an addon's.)
function Sim.FireScript(frame, name, ...)
	local s = S[frame].scripts[name]
	if not s then return end
	local what = (S[frame].name or S[frame].type) .. ":" .. name
	local was = secure
	secure = false
	if s.main then Sim.Call(what, s.main, frame, ...) end
	for _, hook in ipairs(s.hooks) do Sim.Call(what .. " hook", hook, frame, ...) end
	secure = was
end

function Sim.FireEvent(event, ...)
	for _, f in ipairs(allFrames) do
		if S[f].events[event] then Sim.FireScript(f, "OnEvent", event, ...) end
	end
end

-- What the client does at the end of each frame, after OnUpdates: QuestPOI
-- layout (L1), HereBeDragons re-placing its minimap pins.
local endOfFrame = { layOut }

-- One rendered frame: timers, then every visible frame's OnUpdate, then the end of the frame.
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
	for _, fn in ipairs(endOfFrame) do fn() end
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

-- A typed slash command line, e.g. Sim.Slash("/mma perf load"): runs the
-- SlashCmdList entry whose SLASH_<KEY><n> matches, as the chat box does.
function Sim.Slash(line)
	local cmd, msg = line:match("^(/%S+)%s*(.-)$")
	for key, fn in pairs(SlashCmdList) do
		local i = 1
		while _G["SLASH_" .. key .. i] do
			if _G["SLASH_" .. key .. i]:lower() == cmd:lower() then return Sim.Call(line, fn, msg) end
			i = i + 1
		end
	end
	error("no slash command " .. cmd)
end

-- Every frame, created in order (for scenarios to find buttons etc.).
function Sim.Frames() return allFrames end
function Sim.Named(name) return named[name] end

---------------------------------------------------------------------------
-- Lua / WoW library functions
---------------------------------------------------------------------------

function wipe(t) for k in pairs(t) do t[k] = nil end return t end
-- The hook runs after the original, insecure (an addon's); the caller goes on as it was.
function hooksecurefunc(t, name, fn)
	if type(t) == "string" then t, name, fn = _G, t, name end -- hooksecurefunc("GlobalFunction", fn)
	local orig = t[name]
	t[name] = function(...)
		local r = { orig(...) }
		local was = secure
		secure = false
		fn(...)
		secure = was
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
-- Sim.Clock: the ms clock behind debugprofilestop; a scenario may swap it. What Sim.Price
-- charges, and Sim.Spend, is added on top. The default, Sim.RealClock, is os.clock's, slowed by
-- MM_CLOCK_SCALE (MM_CLOCK_SCALE=4 tools/check.sh: a slow CI runner's pace): what it measures
-- differs by machine, so no test reads it: the tests boot on Sim.Counted instead.
local scale = tonumber(os.getenv("MM_CLOCK_SCALE")) or 1
Sim.RealClock = function() return os.clock() * 1000 * scale end
Sim.Clock = Sim.RealClock
function debugprofilestop() return Sim.Clock() + Sim.priced end

-- The counted clock: each widget call costs ms (default 3 us, client-like), Lua nothing, the same
-- on every machine (what the client charges is mostly its engine calls). Counts from the first use.
function Sim.Counted(ms)
	if not Sim.calls then Sim.CountCalls() end
	ms = ms or 0.003
	Sim.Clock = function() return Sim.callTotal * ms end
end

-- A planted cost: ms spent now, exactly, on any clock.
function Sim.Spend(ms) Sim.priced = Sim.priced + ms end

function GetTime() return Sim.time end
time = os.time
date = os.date

function GetBuildInfo() return "1.60.1", "70009", "Sep 1 2026", 16001 end

-- WoW's xpcall passes extra args to f (Lua 5.1's doesn't). Up to 4 args go through one
-- reused trampoline, so the shim allocates nothing (as the client's doesn't: allocation
-- per frame is measured, docs/runtime.md); it reads its slots on entry, before f can nest.
local xpcall51 = xpcall
local tf, tn, t1, t2, t3, t4
local function trampoline()
	local f, n, a1, a2, a3, a4 = tf, tn, t1, t2, t3, t4
	tf, t1, t2, t3, t4 = nil, nil, nil, nil, nil
	if n == 0 then return f() elseif n == 1 then return f(a1) elseif n == 2 then return f(a1, a2)
	elseif n == 3 then return f(a1, a2, a3) end
	return f(a1, a2, a3, a4)
end
function xpcall(f, handler, ...)
	local n = select("#", ...)
	if n <= 4 then
		tf, tn, t1, t2, t3, t4 = f, n, ...
		return xpcall51(trampoline, handler)
	end
	local args = { ... }
	return xpcall51(function() return f(unpack(args, 1, n)) end, handler)
end
-- debugstack([thread,] [start]): the stack, without traceback's header.
function debugstack(a, b)
	local s
	if type(a) == "thread" then s = debug.traceback(a, "", b or 0) else s = debug.traceback("", (a or 1) + 1) end
	return (s:gsub("^\n?stack traceback:\n", ""))
end
Sim.errorHandler = function(msg) Sim.errors[#Sim.errors + 1] = "error handler: " .. tostring(msg) end
function geterrorhandler() return Sim.errorHandler end
function seterrorhandler(fn) assert(type(fn) == "function", "seterrorhandler: function expected"); Sim.errorHandler = fn end
-- The client writes the file, then fires SCREENSHOT_SUCCEEDED.
function Screenshot()
	Sim.screenshots = (Sim.screenshots or 0) + 1
	C_Timer.After(0, function() Sim.FireEvent("SCREENSHOT_SUCCEEDED") end)
end

function GetCursorPosition() return Sim.cursorX, Sim.cursorY end
function IsMouseButtonDown(button) return Sim.buttonsDown[button or "LeftButton"] == true end
function IsShiftKeyDown() return Sim.modifiers.shift end
function IsControlKeyDown() return Sim.modifiers.ctrl end
function IsAltKeyDown() return Sim.modifiers.alt end
Sim.modifiers = {}

Sim.cvars = { rotateMinimap = "0" }
Sim.minimapGround, Sim.minimapUnrotated = true, false
function GetCVar(name) return Sim.cvars[name] end
C_CVar = { GetCVar = GetCVar }

-- Client files by path (case and slash direction don't matter): the ones MagicMap asks for.
-- No font: Forever answers nil for the ones it has (the M0 gate's `art` misses); SetFont loads them.
local FILES = {}
for i, path in ipairs({ "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up", "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight",
	"Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down", "Interface\\Minimap\\MinimapArrow", "Interface\\COMMON\\Indicator-Yellow",
	"Interface\\WorldMap\\Gear_64", "Interface\\CharacterFrame\\TempPortraitAlphaMask",
	"Interface\\HUD\\UIMinimap2xC60", "Interface\\Icons\\INV_Misc_Map_01" }) do
	FILES[path:lower()] = 100000 + i
end
function GetFileIDFromPath(path) return FILES[(path:lower():gsub("/", "\\"))] end
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
SlashCmdList = {}
UISpecialFrames = {}
-- Escape, as the client's CloseSpecialWindows: hides the shown frames named there (secure).
function Sim.Escape()
	return Secure(function()
		local closed = false
		for _, name in ipairs(UISpecialFrames) do
			local f = _G[name]
			if f and f:IsShown() then f:Hide(); closed = true end
		end
		return closed
	end)
end
-- A key the client binds itself, pressed (secure): "M", "L", "ESCAPE".
local BINDINGS = { M = "ToggleWorldMap", L = "ToggleQuestLog" }
function Sim.Press(key)
	if key == "ESCAPE" then return Sim.Escape() end
	return Secure(_G[BINDINGS[key]])
end

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
-- print goes to the chat frame, as in the game.
function print(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
	DEFAULT_CHAT_FRAME:AddMessage(table.concat(parts, " "))
end
function ChatFrame_OpenChat(text) Sim.chat = text end
ChatFrameUtil = { OpenChat = function(text) Sim.chat = text end }

GameFontNormal = { GetFont = function() return STANDARD_TEXT_FONT, 12, "" end }
GameTooltipText = { GetFont = function() return STANDARD_TEXT_FONT, 12, "" end }
GameTooltipTextSmall = { GetFont = function() return STANDARD_TEXT_FONT, 10, "" end }
GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent, "GameTooltipTemplate")
GameTooltip:Hide()

MinimapCluster = CreateFrame("Frame", "MinimapCluster", UIParent)
MinimapCluster:SetFrameStrata("LOW") -- (Blizzard's Minimap.xml)
MinimapCluster:SetSize(230, 230)
MinimapCluster:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
Minimap = new("Minimap", "Minimap", nil)
attach(Minimap, MinimapCluster, "children")
S[Minimap].strata, S[Minimap].level = "LOW", S[MinimapCluster].level + 1 -- (the cluster's: Minimap.xml)
allFrames[#allFrames + 1] = Minimap
Minimap:SetSize(140, 140)
Minimap:SetPoint("CENTER", MinimapCluster, "TOP", 9, -92)
Minimap:EnableMouse(true)
Minimap:EnableMouseWheel(true)
for _, name in ipairs({ "MinimapBorder", "MinimapBorderTop", "MinimapZoneTextButton" }) do
	local f = CreateFrame("Frame", name, MinimapCluster)
	f:SetAllPoints(Minimap)
end
-- Blizzard's zoom button (a Minimap child), a button another addon hung on the minimap (its
-- strata and level its own, not fixed), and a GatherMate-style pin.
Sim.minimapZoom = CreateFrame("Button", "MinimapZoomIn", Minimap)
Sim.minimapZoom:SetSize(20, 20)
Sim.minimapZoom:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", 0, 0)
Sim.minimapZoom:SetFrameLevel(Minimap:GetFrameLevel() + 3)
Sim.minimapButton = CreateFrame("Button", "LibDBIcon10_SomeAddon", Minimap)
Sim.minimapButton:SetSize(31, 31)
Sim.minimapButton:SetPoint("CENTER", Minimap, "BOTTOMLEFT", 10, 10)
Sim.minimapButton:SetFrameStrata("MEDIUM")
Sim.minimapButton:SetFrameLevel(8)
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
-- LibStub: callable, and its libraries listed in .libs as in the real one
-- (HereBeDragons' copies: Sim.HBDPins, below the world).
Sim.libs = {}
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

-- Protected frames (K2): Sim.Protect(frame) makes one protected, and every frame
-- holding it too (IsProtected: protected, explicitly). In combat an insecure call
-- that would move, size, show or hide one is refused: not made, logged in
-- Sim.protectedCalls ({ frame, call, stack }) and ADDON_ACTION_BLOCKED fired.
-- Protected here: MinimapCluster and WorldMapFrame (hiding them is the spike's K2).
Sim.protectedCalls = {}
function Sim.Protect(frame, on) S[frame].protected = on ~= false end
local function protected(f)
	if S[f].protected then return true end
	for _, c in ipairs(S[f].children) do
		if protected(c) then return true end
	end
	return false
end
function methods:IsProtected() return protected(self), S[self].protected == true end
for _, name in ipairs({ "Show", "Hide", "SetShown", "SetPoint", "SetAllPoints", "ClearAllPoints", "SetParent", "SetSize",
	"SetWidth", "SetHeight", "SetScale", "SetFrameStrata", "SetFrameLevel", "Raise", "Lower", "EnableMouse" }) do
	local fn = methods[name]
	methods[name] = function(self, ...)
		if not (Sim.inCombat and not secure and protected(self)) then return fn(self, ...) end
		local call = (S[self].name or S[self].type) .. ":" .. name .. "()"
		Sim.protectedCalls[#Sim.protectedCalls + 1] = { frame = Sim.frame, call = call, stack = debug.traceback("", 2) }
		Sim.FireEvent("ADDON_ACTION_BLOCKED", Sim.addons[1][1], call)
	end
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
Sim.Protect(MinimapCluster)
Sim.Protect(WorldMapFrame)

local VIEW_INDOORS, VIEW_OUTDOORS = { [0] = 300, 240, 180, 120, 80, 50 }, { [0] = 466.67, 400, 333.33, 266.67, 200, 133.33 }
C_Minimap = {
	GetViewRadius = function()
		local at = S[Minimap].zoomedAt
		if at and Sim.frame - at < Sim.ZOOM_FRAMES then return 0 end -- (a new zoom applying)
		-- Indoors (or somewhere you may mount, Sim.floorPlan) its indoor map.
		local inside = Sim.indoors or Sim.floorPlan
		local d = (inside and VIEW_INDOORS or VIEW_OUTDOORS)[Minimap:GetZoom()]
		return d / 2
	end,
	SetMinimapInsetInfo = function(minAngle, maxAngle, scalar) Sim.rimInset = scalar end,
	ClearMinimapInsetInfo = function() Sim.rimInset = nil end,
	-- Its ground (terrain) and whether it ignores Rotate Minimap (HybridMinimap's switches).
	GetDrawGroundTextures = function() return Sim.minimapGround end,
	SetDrawGroundTextures = function(on) assert(type(on) == "boolean", "SetDrawGroundTextures: boolean expected"); Sim.minimapGround = on end,
	IsRotateMinimapIgnored = function() return Sim.minimapUnrotated end,
	SetIgnoreRotateMinimap = function(on) assert(type(on) == "boolean", "SetIgnoreRotateMinimap: boolean expected"); Sim.minimapUnrotated = on end,
	-- Tracking: the client keeps it per character (a CVar).
	GetNumTrackingTypes = function() return #Sim.tracking end,
	GetTrackingInfo = function(i)
		local t = Sim.tracking[i]
		return t and { name = t.name, texture = t.texture or 136456, active = t.active, type = "spell", subType = 2, spellID = t.spellID }
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
	{ name = "Mailbox", filterID = 64, active = true, texture = 136459 },
	{ name = "Innkeeper", filterID = 128, active = true, texture = 136458 },
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
Sim.addons = { { "MagicMapAtlas", 2400 }, { "Questie", 48000 }, { "Details", 9000 } }
function UpdateAddOnMemoryUsage() end
function GetNumAddOns() return #Sim.addons end
function GetAddOnInfo(i) return Sim.addons[i] and Sim.addons[i][1] end
function GetAddOnMemoryUsage(i)
	for j, a in ipairs(Sim.addons) do
		if j == i or a[1] == i then return a[2] end
	end
	return 0
end
C_AddOns = {
	GetNumAddOns = GetNumAddOns,
	GetAddOnInfo = function(i)
		for j, a in ipairs(Sim.addons) do
			if j == i or a[1] == i then return a[1], a[1], "", true, "INSECURE", false end
		end
	end,
	IsAddOnLoaded = function(i)
		for j, a in ipairs(Sim.addons) do
			if j == i or a[1] == i then return true, true end
		end
		return false, false
	end,
	GetAddOnMetadata = function(name, field) return field == "Version" and "0.1.0" or nil end,
}
Enum.AddOnProfilerMetric = { SessionAverageTime = 0, RecentAverageTime = 1, EncounterAverageTime = 2, LastTime = 3, PeakTime = 4 }
C_AddOnProfiler = {
	IsEnabled = function() return true end,
	GetAddOnMetric = function(name, metric) assert(type(name) == "string" and metric, "GetAddOnMetric: name, metric") return 0.05 end,
	GetOverallMetric = function(metric) return 0.4 end,
	GetTopKAddOnsForMetric = function(metric, k)
		return { { addOnName = "Questie", value = 0.2 }, { addOnName = "MagicMapAtlas", value = 0.05 } }
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
	[1433] = { "Redridge Mountains", T.Zone, 1415, 0, 35.0, 47.4, 38.6, 50.8 },
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
function IsFlying() return Sim.flying == true end
function IsFalling() return false end
function IsSwimming() return Sim.swimming == true end
function UnitOnTaxi(unit) return false end
function GetZoneText()
	local id = mapAt(Sim.player.inst, Sim.player.col, Sim.player.row, { [T.Zone] = true })
	return id and Sim.maps[id][1] or ""
end
Sim.subzone = "Goldshire" -- the client's name for where you are (an inn's, inside it)
function GetSubZoneText() return Sim.subzone end
GetRealZoneText, GetMinimapZoneText = GetZoneText, GetSubZoneText

Sim.units = { player = { name = "Tester", class = "MAGE", level = 5 } }
function UnitName(unit) local u = Sim.units[unit]; return u and u.name end
function UnitIsGhost(unit) return unit == "player" and Sim.ghost or false end
function UnitExists(unit) return Sim.units[unit] ~= nil end
function UnitClass(unit) local u = Sim.units[unit]; if u then return u.class, u.class, 8 end end
function UnitGUID(unit) local u = Sim.units[unit]; return u and (u.guid or "Player-1-00000001") end
function UnitIsPlayer(unit) local u = Sim.units[unit]; return u ~= nil and u.npc == nil end
function UnitClassification(unit) return Sim.units[unit] and Sim.units[unit].classification or "normal" end
function UnitLevel(unit) local u = Sim.units[unit]; return u and (u.level or 1) or 0 end
function UnitQuestTrivialLevelRange(unit) return 5 end
-- A unit's portrait drawn into a texture (the unit's GUID, for tests).
function SetPortraitTexture(tex, unit)
	assert(S[tex] and S[tex].type == "Texture", "SetPortraitTexture: texture expected")
	S[tex].portrait = UnitGUID(unit)
end
-- A group: Sim.group lists the other members' unit tokens (party1...),
-- each in Sim.units with a tile position (col, row) on the player's instance.
Sim.group = {}
function GetNumGroupMembers() return #Sim.group > 0 and #Sim.group + 1 or 0 end
function IsInRaid() return false end
function UnitIsUnit(a, b) return a == b end
function InCombatLockdown() return Sim.inCombat == true end
function UnitIsDeadOrGhost(unit) local u = Sim.units[unit]; return u ~= nil and u.dead == true end

C_Map = {}
function C_Map.GetMapInfo(id) return mapInfo(id) end
function C_Map.GetMapChildrenInfo(id, mapType, allDescendants)
	local out = {}
	for child, m in pairs(Sim.maps) do
		local p = m[3]
		while p and p ~= id and allDescendants do p = Sim.maps[p][3] end
		if p == id and (not mapType or m[2] == mapType) then out[#out + 1] = mapInfo(child) end
	end
	table.sort(out, function(a, b) return a.mapID < b.mapID end)
	return out
end
-- A map's rect on an ancestor's (left, right, top, bottom in 0..1).
function C_Map.GetMapRectOnMap(id, top)
	local m, t = Sim.maps[id], Sim.maps[top]
	local function x(c) return (c - t[5]) / (t[7] - t[5]) end
	local function y(r) return (r - t[6]) / (t[8] - t[6]) end
	return x(m[5]), x(m[7]), y(m[6]), y(m[8])
end
-- Map art (the world map's, and HybridMinimap's): Sim.mapArt[uiMapID] =
-- { w, h, tile } in pixels; its textures are made-up FileDataIDs.
Sim.mapArt = {}
function C_Map.GetMapArtLayers(id)
	local a = Sim.mapArt[id]
	if not a then return nil end
	return { { layerWidth = a[1], layerHeight = a[2], tileWidth = a[3], tileHeight = a[3], minScale = 1, maxScale = 1, additionalZoomSteps = 0 } }
end
function C_Map.GetMapArtLayerTextures(id, layer)
	local a = Sim.mapArt[id]
	if not a or layer ~= 1 then return nil end
	local files = {}
	for i = 1, math.ceil(a[1] / a[3]) * math.ceil(a[2] / a[3]) do files[i] = 900000 + i end
	return files
end
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
	GetAllTaxiNodes = function(id) return C_TaxiMap.GetTaxiNodesForMap(id) end,
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
	-- Sim.vignetteAtlas: its art ("VignetteKillElite" for a rare); Sim.noVignettes: none showing.
	GetVignettes = function() return Sim.noVignettes and {} or { "Vignette-0-1" } end,
	GetVignetteInfo = function(guid) return { vignetteGUID = guid, name = "Mother Fang", atlasName = Sim.vignetteAtlas or "VignetteKill", onMinimap = true } end,
	GetVignettePosition = function(guid, id) return id == 1429 and CreateVector2D(0.38, 0.79) or nil end,
}
-- Atlases: the ones MagicMap asks for that Retail-engine clients have
-- (checked against Forever's UiTextureAtlasMember); none on classic clients. By element
-- name, which GetAtlasInfo takes: a member's `-2x` or `-c60` variant isn't one (Forever
-- has no redbutton-expand-c60: the M0 gate's `art` misses).
local ATLASES = { Professions_Tracking_Herb = true, Professions_Tracking_Ore = true }
for _, base in ipairs({ "ui-hud-minimap-zoom-in", "ui-hud-minimap-zoom-out" }) do
	ATLASES[base], ATLASES[base .. "-mouseover"], ATLASES[base .. "-down"] = true, true, true
end
for _, name in ipairs({ "redbutton-expand", "redbutton-expand-pressed", "redbutton-highlight",
	"ui-hud-minimap-arrow-player", "ui-hud-minimap-arrow-questtracking", "minimaparrow", "Quest-In-Progress-Icon-yellow" }) do
	ATLASES[name] = true
end
-- The metal frame's pieces, sized as Forever reports them: the edges far
-- bigger than the metal you see (which once shrank the map: L2), by
-- GetAtlasInfo and SetAtlas(name, true) alike.
for _, name in ipairs({ "UI-Frame-Metal-CornerBottomLeft", "UI-Frame-Metal-CornerBottomRight" }) do ATLASES[name] = { 32, 32 } end
ATLASES["_UI-Frame-Metal-EdgeBottom"] = { 256, 200 }
ATLASES["UI-QuestPoi-QuestNumber"], ATLASES["deathrecap-icon-tombstone"] = { 32, 32 }, { 15, 20 }
ATLASES["!UI-Frame-Metal-EdgeLeft"] = { 200, 256 }
ATLASES["!UI-Frame-Metal-EdgeRight"] = { 200, 256 }
-- ui/Art.lua's (Forever's ObjectIconsAtlas, as tools/export_icons.py cuts them for the demo)
for _, name in ipairs({ "taxinode_alliance", "taxinode_horde", "taxinode_neutral", "vignettekill", "vignettekillelite" }) do
	ATLASES[name] = true
end
Sim.atlases = ATLASES -- [name] = true (16 px) or { w, h }: a scenario adds, resizes or removes one
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
	[60] = { title = "Kobold Candles", level = 7, map = 1429, x = 0.35, y = 0.55, complete = false,
		objectives = { { text = "Large Candle: 3/8", type = "item", finished = false, numFulfilled = 3, numRequired = 8 } } },
	[62] = { title = "The Fargodeep Mine", level = 4, map = 1429, x = 0.40, y = 0.80, complete = true,
		objectives = { { text = "Scout through the Fargodeep Mine", type = "event", finished = true, numFulfilled = 1, numRequired = 1 } } },
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
	GetQuestDifficultyLevel = function(questID) local q = Sim.quests[questID]; return q and q.level or 0 end,
	-- Grey more than 5 levels below you (the client's range grows with level).
	IsQuestTrivial = function(questID) local q = Sim.quests[questID]; return q ~= nil and UnitLevel("player") - q.level > 5 end,
	AddQuestWatch = function(questID) Sim.watched = questID; return true end,
}
-- Items by ID: GetItemInfoInstant's itemID .. icon.
Sim.items = { [772] = { 772, "Quest", "Quest", "", 134335 } }
C_Item = {
	GetItemInfoInstant = function(item)
		local i = Sim.items[item]
		if i then return i[1], i[2], i[3], i[4], i[5] end
	end,
}

function UnitFactionGroup(unit) return Sim.faction or "Alliance", Sim.faction or "Alliance" end
C_SuperTrack = {
	GetSuperTrackedQuestID = function() return Sim.superTracked or 0 end,
	SetSuperTrackedQuestID = function(id) Sim.superTracked = id end,
	SetSuperTrackedUserWaypoint = function(on) if on then Sim.superTracked = 0 end end,
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

function ButtonFrameTemplate_HidePortrait(f) end
function ButtonFrameTemplate_HideButtonBar(f) end

---------------------------------------------------------------------------
-- HereBeDragons-Pins-2.0: Sim.HBDPins(major) is a copy in LibStub, shaped like
-- the real one (Questie/Libs/HereBeDragons/HereBeDragons-Pins-2.0.lua): pins by
-- world yards (x = west, y = north: UnitPosition's second and first) in
-- minimapPins / worldmapPins, keyed by the addon's frame ("icon"), registries by
-- ref. Its world-map provider gives each pin on Blizzard's current map
-- (WorldMapFrame.mapID: the pin's own map; any map holding it for a continent
-- flag or a pin by world yards) a pin frame on the map's canvas and parents the
-- icon to it; releasing one hands the icon to UIParent, hidden. It refreshes
-- when the map opens on another map or after a removal (forceUpdate). Minimap
-- pins sit on pins.Minimap (SetMinimapObject) at your offset over the view
-- radius, turned under Rotate Minimap, hidden past 0.9 of it unless
-- floatOnEdge; re-placed at the end of a frame when you, the radius or that
-- frame changed, while that frame is visible (HereBeDragons-Pins-2.0.lua:539). The shared copy holds GatherMate's pin (Sim.gatherPin);
-- Questie's renamed copy comes with Sim.LoadQuestie(), as if Questie loaded later.
---------------------------------------------------------------------------

HBD_PINS_WORLDMAP_SHOW_PARENT, HBD_PINS_WORLDMAP_SHOW_CONTINENT, HBD_PINS_WORLDMAP_SHOW_WORLD = 1, 2, 3
local copies = {}

local function zoneToWorld(uiMapID, x, y)
	local m = Sim.maps[uiMapID]
	if not (m and m[4]) then return nil end
	local north, west = toWorld(m[5] + (m[7] - m[5]) * x, m[6] + (m[8] - m[6]) * y)
	return west, north, m[4]
end

function Sim.HBDPins(major)
	local pins = { Minimap = Minimap, minimapPins = {}, activeMinimapPins = {}, minimapPinRegistry = {},
		worldmapPins = {}, worldmapPinRegistry = {}, worldmapProvider = { forceUpdate = false }, last = {} }
	local provider, canvas, free, used = pins.worldmapProvider, WorldMapFrame.canvas, {}, {}

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
		local m = Sim.maps[id]
		if not (m and m[4] == data.instanceID) then return end
		if data.uiMapID and data.uiMapID ~= id and data.worldMapShowFlag < HBD_PINS_WORLDMAP_SHOW_CONTINENT then return end
		local x, y = normalized(id, 32 - data.x / TILE, 32 - data.y / TILE)
		if x < 0 or x > 1 or y < 0 or y > 1 then return end
		local pin = table.remove(free) or CreateFrame("Frame", nil, canvas)
		pin:SetSize(1, 1)
		pin:ClearAllPoints()
		pin:SetPoint("CENTER", canvas, "TOPLEFT", x * canvas:GetWidth(), -y * canvas:GetHeight())
		pin:Show()
		used[pin], pin.icon = true, icon
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

	function pins.place(icon, data)
		local north, west, _, inst = UnitPosition("player")
		local r = C_Minimap.GetViewRadius()
		if r == 0 then return end -- (a new zoom applying: left where it was)
		if not north or inst ~= data.instanceID then return icon:Hide() end
		local dx, dy = (west - data.x) / r, (north - data.y) / r
		if Sim.cvars.rotateMinimap == "1" then
			local s, c = math.sin(GetPlayerFacing()), math.cos(GetPlayerFacing())
			dx, dy = dx * c - dy * s, dx * s + dy * c
		end
		local dist = (dx * dx + dy * dy) / 0.81
		if dist > 1 and data.floatOnEdge then
			dist = dist ^ 0.5
			dx, dy = dx / dist, dy / dist
		end
		data.onEdge = dist > 1 or nil
		if dist > 1 and not data.floatOnEdge then return icon:Hide() end
		local m = pins.Minimap
		icon:Show()
		icon:ClearAllPoints()
		icon:SetPoint("CENTER", m, "CENTER", dx * m:GetWidth() / 2, -dy * m:GetHeight() / 2)
	end

	local function addMinimap(ref, icon, inst, x, y, uiMapID, inParent, floatOnEdge)
		assert(ref ~= nil and type(icon) == "table" and icon.SetPoint, major .. ": a ref and an icon frame expected")
		pins.minimapPinRegistry[ref] = pins.minimapPinRegistry[ref] or {}
		pins.minimapPinRegistry[ref][icon] = true
		local t = pins.minimapPins[icon] or {}
		t.instanceID, t.x, t.y, t.uiMapID, t.showInParentZone, t.floatOnEdge = inst, x, y, uiMapID, inParent, floatOnEdge
		pins.minimapPins[icon] = t
		icon:SetParent(pins.Minimap)
		pins.place(icon, t)
	end
	function pins:AddMinimapIconWorld(ref, icon, instanceID, x, y, floatOnEdge)
		addMinimap(ref, icon, instanceID, x, y, nil, nil, floatOnEdge)
	end
	function pins:AddMinimapIconMap(ref, icon, uiMapID, x, y, showInParentZone, floatOnEdge)
		local wx, wy, inst = zoneToWorld(uiMapID, x, y)
		if wx then addMinimap(ref, icon, inst, wx, wy, uiMapID, showInParentZone, floatOnEdge) end
	end
	function pins:IsMinimapIconOnEdge(icon) return self.minimapPins[icon] and self.minimapPins[icon].onEdge end
	function pins:RemoveMinimapIcon(ref, icon)
		if not (ref and icon and self.minimapPinRegistry[ref]) then return end
		self.minimapPinRegistry[ref][icon] = nil
		self.minimapPins[icon], self.activeMinimapPins[icon] = nil, nil
		icon:Hide()
	end
	function pins:RemoveAllMinimapIcons(ref)
		for icon in pairs(self.minimapPinRegistry[ref] or NONE) do self:RemoveMinimapIcon(ref, icon) end
	end
	function pins:SetMinimapObject(obj)
		self.Minimap = obj or Minimap
		assert(self.Minimap.GetZoom, "SetMinimapObject: the minimap object needs GetZoom")
		for icon in pairs(self.minimapPins) do icon:SetParent(self.Minimap) end
		if not self.Minimap:IsVisible() then return end
		for icon, data in pairs(self.minimapPins) do self.place(icon, data) end
	end

	local function addWorld(ref, icon, inst, x, y, uiMapID, showFlag, frameLevel)
		assert(ref ~= nil and type(icon) == "table" and icon.SetPoint, major .. ": a ref and an icon frame expected")
		pins.worldmapPinRegistry[ref] = pins.worldmapPinRegistry[ref] or {}
		pins.worldmapPinRegistry[ref][icon] = true
		local t = pins.worldmapPins[icon] or {}
		t.instanceID, t.x, t.y, t.uiMapID, t.worldMapShowFlag, t.frameLevelType = inst, x, y, uiMapID, showFlag or 0, frameLevel
		pins.worldmapPins[icon] = t
		provider:HandlePin(icon, t)
	end
	function pins:AddWorldMapIconWorld(ref, icon, instanceID, x, y, showFlag, frameLevel)
		addWorld(ref, icon, instanceID, x, y, nil, showFlag, frameLevel)
	end
	function pins:AddWorldMapIconMap(ref, icon, uiMapID, x, y, showFlag, frameLevel)
		local wx, wy, inst = zoneToWorld(uiMapID, x, y)
		if wx then addWorld(ref, icon, inst, wx, wy, uiMapID, showFlag, frameLevel) end
	end
	function pins:RemoveWorldMapIcon(ref, icon)
		if not (ref and icon and self.worldmapPinRegistry[ref]) then return end
		self.worldmapPinRegistry[ref][icon] = nil
		self.worldmapPins[icon] = nil
		provider:RemovePinByIcon(icon)
		provider.forceUpdate = true
	end
	function pins:RemoveAllWorldMapIcons(ref)
		for icon in pairs(self.worldmapPinRegistry[ref] or NONE) do self:RemoveWorldMapIcon(ref, icon) end
	end

	copies[#copies + 1] = pins
	Sim.libs[major] = pins
	return pins
end

endOfFrame[#endOfFrame + 1] = function()
	local north, west = UnitPosition("player")
	local r, facing = C_Minimap.GetViewRadius(), GetPlayerFacing()
	for _, pins in ipairs(copies) do
		local L, m = pins.last, pins.Minimap
		local _, _, w, h = rect(m)
		if m:IsVisible() and (north ~= L.n or west ~= L.w or r ~= L.r or facing ~= L.f or m ~= L.m or w ~= L.mw or h ~= L.mh) then
			L.n, L.w, L.r, L.f, L.m, L.mw, L.mh = north, west, r, facing, m, w, h
			for icon, data in pairs(pins.minimapPins) do pins.place(icon, data) end
		end
	end
end

Sim.hbdPins = Sim.HBDPins("HereBeDragons-Pins-2.0")
Sim.hbdPins:AddMinimapIconMap("GatherMate2", Sim.gatherPin, 1429, 0.297, 0.546) -- a herb 40 yd north-east of you

function Sim.LoadQuestie()
	if not Sim.questiePins then
		HBD_PINS_WORLDMAP_SHOW_CURRENT = -1 -- (Questie's: its own map only)
		Sim.libs["HereBeDragonsQuestie-2.0"] = {}
		Sim.questiePins = Sim.HBDPins("HereBeDragonsQuestie-Pins-2.0")
		Questie = { name = "Questie" }
	end
	return Sim.questiePins
end
-- A Questie map icon: a button at Questie's fixed frame level, hidden until placed,
-- with Questie's data ({ Type = "available" | "complete" | ..., Id = questID }).
function Sim.QuestieIcon(data)
	local icon = CreateFrame("Button", nil, UIParent)
	icon:SetSize(16, 16)
	icon:EnableMouse(true)
	icon:SetFrameLevel(2016)
	icon:SetFixedFrameLevel(true)
	icon:Hide()
	icon.data = data
	return icon
end

---------------------------------------------------------------------------
-- Strict (Sim.Strict(true), or MM_STRICT=1 before loading): WoW's Lua raises
-- "Division by zero" where plain Lua gives inf or nan (E3). Code loaded while
-- it's on (loadfile, loadstring; not Data/, which is generated) has each `/`
-- made `/ __strictdiv ^`: `^` binds tighter than anything that can follow `/`,
-- so the metamethod gets exactly the divisor, and hands it back or raises.
---------------------------------------------------------------------------

__strictdiv = setmetatable({}, { __pow = function(_, d)
	if d == 0 then error("Division by zero", 2) end
	return d
end })

-- Every `/` outside strings and comments.
local function rewrite(src)
	local out, from, i = {}, 1, 1
	while true do
		i = src:find("[-%[\"'/]", i)
		if not i then break end
		local c = src:sub(i, i)
		local long = src:match("^%[(=*)%[", c == "-" and i + 2 or i)
		if c == "/" then
			out[#out + 1] = src:sub(from, i) .. " __strictdiv ^"
			from, i = i + 1, i + 1
		elseif c == "-" and src:sub(i + 1, i + 1) == "-" then
			local _, e = src:find(long and "]" .. long .. "]" or "\n", i + 2, true)
			i = (e or #src) + 1
		elseif c == "[" and long then
			local _, e = src:find("]" .. long .. "]", i + 1, true)
			i = (e or #src) + 1
		elseif c == '"' or c == "'" then
			local j = i + 1
			while true do
				j = src:find("[\\" .. c .. "]", j)
				if not j or src:sub(j, j) == c then break end
				j = j + 2
			end
			i = (j or #src) + 1
		else
			i = i + 1
		end
	end
	out[#out + 1] = src:sub(from)
	return table.concat(out)
end

local loadfile51, loadstring51 = loadfile, loadstring
local function strictLoadstring(src, name) return loadstring51(rewrite(src), name or src) end
local function strictLoadfile(path)
	local f = not path:find("/Data/[^/]*%.lua$") and io.open(path, "rb")
	if not f then return loadfile51(path) end
	local src = f:read("*a")
	f:close()
	return loadstring51(rewrite(src), "@" .. path)
end
function Sim.Strict(on)
	loadfile, loadstring = on and strictLoadfile or loadfile51, on and strictLoadstring or loadstring51
end
Sim.Strict(os.getenv("MM_STRICT") == "1")

return Sim
