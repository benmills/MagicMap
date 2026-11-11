-- The one pin store (spike-bugs D1: every pin drawn from one store, diffed by id). Each kind of pin
-- (rares, places, quests, ...) is an Engine "pin" layer made with Pins.Layer,
-- its Model.Known entries put by key: a layout keeps the pin its canvas showed for that key
-- (Engine.Keep) and sets only what changed, its look (StylePin, Layers.lua:343-400: each setter
-- called only when its value differs) and its place (Engine.At, when its tile, the canvas's zoom or
-- origin, or its minimum zoom differ), so a pan's layout re-places only the pins it adds and a changed
-- rev re-sets only the pins that changed; an unchanged rev lays nothing out (Engine). A pin is a frame
-- holding the spike's regions (Layers.lua:304-336) that doesn't take the mouse: the spike's took it and
-- passed clicks on (SetPropagateMouseClicks, Layers.lua:323), but a layer's other canvas stands shown at
-- alpha 0 with the pins it showed, which would catch it; so while the view has the mouse (nothing over
-- it took it), each frame Pins finds the pin under the cursor on the canvases shown (the topmost layer's,
-- the nearest centre), and every click and drag is the view's. Its tooltip: GameTooltip ANCHOR_RIGHT on
-- the pin, its title, then its facts small and DIM (ui/Tip.lua's look: Layers.lua:288-301, QuestInfo.lua:251-305);
-- built once a hover, hidden on the one owner-checked path: the cursor off it or the view, the window hidden
-- (ui/Window.lua); none while the popup stands. A click on a pin, left or right, grows its tooltip into the popup
-- (ui/Popup.lua), its buttons the pin's actions (ui/Track.lua: Track, Path to, their Stops); every pin layer's rev carries Track's
-- (what you track is never held back to a closer zoom), so a change lays them out again.

local _, ns = ...
local UI, Runtime, Model = ns.UI, ns.Runtime, ns.Model
local Engine, Window, Camera, Track, Tip = UI.Engine, UI.Window, UI.Camera, UI.Track, UI.Tip
local Get, Keep, At, Yield = Engine.Get, Engine.Keep, Engine.At, Runtime.Yield

local SIZE = 14 -- px: a pin's (StylePin's default, Layers.lua:344)
local INNER_SIZE, INNER_SHADE = 0.56, 0.55 -- (c)'s objective icon: share of its disc, its shade (Layers.lua:303)
local SCALE = 0.62 -- (c)'s atlas over its disc (Layers.lua:379)
local DOT, RING_PAD = 0.6, 3 -- (d): the dot's share of size, its ring's past it (Layers.lua:396-399)
local RING = { 0, 0, 0, 0.9 } -- Layers.lua:396
local WHITE = { 1, 1, 1 }
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask" -- UI.lua:6
local NONE = {}

local Pins = {}
UI.Pins = Pins

-- A look's type (look.type: ui/PinTypes.lua) gives its style, Settings > Pins: whether it's drawn (put leaves it out),
-- its size (a factor on the look's but for a fixed one: a group's pill, whose slots are ICON px, ui/Cluster.lua), its
-- opacity and its icon as chosen, and on the big map from which zoom it shows (Types.Min); a pin layer's rev moves
-- with any type's (Types.Rev: the big map's threshold too), so the pins are set again.
local Types = UI.PinTypes
local Of, Min = Types.Of, Types.Min

---------------------------------------------------------------------------
-- StylePin (Layers.lua:304-400)
---------------------------------------------------------------------------

local has = {} -- atlas name -> the client has it
local function Has(atlas)
	if has[atlas] == nil then has[atlas] = C_Texture.GetAtlasInfo(atlas) ~= nil end
	return has[atlas]
end

-- A texture on pin, centred on it, unsnapped (the map moves by fractions of a pixel).
local function Tex(pin, layer, sub)
	local t = pin:CreateTexture(nil, layer, nil, sub)
	t:SetSnapToPixelGrid(false)
	t:SetTexelSnappingBias(0)
	t:SetPoint("CENTER")
	t.vis = true
	return t
end

local function MakePin(c)
	local pin = CreateFrame("Frame", nil, c)
	pin.icon = Tex(pin, "ARTWORK", 2)
	return pin
end
Pins.Make = MakePin -- (ui/Cluster.lua's pills)

-- The rest made the first time a look needs them: a ring (or a disc under the icon), the objective icon
-- inside it, the count.
local function Ring(pin)
	if not pin.ring then pin.ring = Tex(pin, "ARTWORK", 0) end
	return pin.ring
end

local function Inner(pin)
	local t = pin.inner
	if t then return t end
	t = Tex(pin, "ARTWORK", 1)
	t:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- an icon's own border trimmed off
	t:SetVertexColor(INNER_SHADE, INNER_SHADE, INNER_SHADE, 1)
	local mask = pin:CreateMaskTexture()
	mask:SetSnapToPixelGrid(false)
	mask:SetTexelSnappingBias(0)
	mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(t)
	t:AddMaskTexture(mask)
	pin.inner = t
	return t
end

local function Count(pin)
	local fs = pin.count
	if fs then return fs end
	fs = pin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
	fs:SetPoint("TOP", pin, "BOTTOM", 0, 2)
	pin.count = fs
	return fs
end

-- Setters calling the client only when the value changes: a pin kept as it was costs none.
local WHOLE = { 0, 1, 0, 1 }
local function File(t, file, coords) -- a whole file, or its part coords (left, right, top, bottom: a look's table)
	coords = coords or WHOLE
	if t.art ~= file or t.coords ~= coords then
		t.art, t.coords = file, coords
		t:SetTexture(file)
		t:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
	end
end
local function Atlas(t, atlas)
	if t.art ~= atlas then
		t.art = atlas
		t:SetAtlas(atlas, false) -- the pin's size, not the atlas's
	end
end
-- An atlas's width over height (1 if the client doesn't say): a pin keeps it, its longer side the size.
local aspects = {}
local function Aspect(atlas)
	local a = aspects[atlas]
	if a == nil then
		local info = C_Texture.GetAtlasInfo(atlas)
		a = info and info.width and info.height and info.width > 0 and info.height > 0 and info.width / info.height or 1 -- /: never 0 (the height is > 0 here)
		aspects[atlas] = a
	end
	return a
end
-- The width and height of a size-sided pin of aspect a (its longer side is size).
local function Fit(size, a)
	if a >= 1 then return size, size / a end -- /: never 0 (a >= 1 here)
	return size * a, size
end
local function Color(t, r, g, b, a)
	if t.r ~= r or t.g ~= g or t.b ~= b or t.a ~= a then
		t.r, t.g, t.b, t.a = r, g, b, a
		t:SetVertexColor(r, g, b, a)
	end
end
local function Size(r, w, h)
	if r.w ~= w or r.h ~= h then
		r.w, r.h = w, h
		r:SetSize(w, h)
	end
end
local function Shown(r, on)
	if r and r.vis ~= on then
		r.vis = on
		r:SetShown(on)
	end
end

-- look: { type? (its style's: ui/PinTypes.lua), size? (14), fixed? (not scaled by the settings),
-- icon? = { texture | atlas, alt?, coords?, under?, tint?, inner?, scale?, aspect?, color? },
-- count? }: (a) a texture (coords: its part, a cell of a sheet), bare; (b) an atlas, at its own aspect
-- (aspect: its width over height, else the client's); (c) an atlas over its under atlas tinted, the inner
-- texture in it; (d) else (an atlas the client lacks too, and no alt: the look drawn instead when the atlas is
-- missing) a dot of its colour on a dark ring; count: a line under it; sub (with subStyle): a second, under that.
-- The pin's icon as inline markup before its tooltip's title (16 px, its own proportions, two spaces after): a
-- texture whole, an atlas the client has; none for a sheet's cell, a disc's atlas (a quest's: its tooltip has its
-- own look) or a dot. One string an icon.
local MARK = 16
local marks = {} -- its art (a file or an atlas) -> its markup, or false
local function Mark(icon)
	if icon.coords or icon.under then return false end
	local k = icon.texture or icon.atlas
	if not k then return false end
	local m = marks[k]
	if m ~= nil then return m end
	m = false
	if icon.texture then
		m = "|T" .. icon.texture .. ":" .. MARK .. ":" .. MARK .. "|t  "
	elseif Has(icon.atlas) then
		local w, h = Fit(MARK, icon.aspect or Aspect(icon.atlas))
		m = string.format("|A:%s:%d:%d|a  ", icon.atlas, h + 0.5, w + 0.5)
	end
	marks[k] = m
	return m
end

local function Style(pin, look)
	local st = Of(look.type)
	local size, icon = (look.size or SIZE) * (look.fixed and 1 or st.size), st.icon or look.icon or NONE
	if pin.alpha ~= st.alpha then
		pin.alpha = st.alpha
		pin:SetAlpha(st.alpha)
	end
	if icon.alt and not icon.texture and not (icon.atlas and Has(icon.atlas)) then icon = icon.alt end -- (an atlas the client lacks: its alt)
	pin.psize = size
	pin.mark = Mark(icon) -- (its tooltip's title: Fill)
	Size(pin, size, size)
	if look.count or pin.count then
		local fs = Count(pin)
		local style = look.countStyle -- (nil: the small outlined white; else { font, size, color }: a quest's name)
		if fs.style ~= style then
			fs.style = style
			if style then
				fs:SetFont(style[1], style[2], "")
				fs:SetShadowOffset(1, -1)
				fs:SetShadowColor(0, 0, 0, 0.85)
				fs:SetTextColor(style[3][1], style[3][2], style[3][3], 1)
			else
				fs:SetFontObject("GameFontHighlightSmallOutline")
				fs:SetShadowOffset(0, 0)
				fs:SetTextColor(1, 1, 1, 1)
			end
		end
		if fs.text ~= look.count then
			fs.text = look.count
			fs:SetText(look.count)
		end
	end
	-- A second line under the count (a quest's progress under its name), secondary: look.sub in look.subStyle.
	if look.sub or pin.sub then
		local fs = pin.sub
		if not fs then
			fs = pin:CreateFontString(nil, "OVERLAY")
			fs:SetPoint("TOP", Count(pin), "BOTTOM", 0, -1)
			fs:SetShadowOffset(1, -1)
			fs:SetShadowColor(0, 0, 0, 0.85)
			pin.sub = fs
		end
		local style = look.subStyle
		if style and fs.style ~= style then
			fs.style = style
			fs:SetFont(style[1], style[2], "")
			fs:SetTextColor(style[3][1], style[3][2], style[3][3], 1)
		end
		if fs.text ~= (look.sub or "") then
			fs.text = look.sub or ""
			fs:SetText(fs.text)
		end
	end
	local i, inner = pin.icon, false
	if icon.texture then -- (a)
		File(i, icon.texture, icon.coords)
		Color(i, 1, 1, 1, 1)
		Size(i, size, size)
		Shown(pin.ring, false)
	elseif icon.atlas and Has(icon.atlas) then
		if icon.under and Has(icon.under) then -- (c)
			local r, t = Ring(pin), icon.tint or WHITE
			Atlas(r, icon.under)
			Color(r, t[1], t[2], t[3], 1)
			Size(r, size, size)
			Shown(r, true)
			if icon.inner then
				inner = Inner(pin)
				if inner.art ~= icon.inner then
					inner.art = icon.inner
					inner:SetTexture(icon.inner)
				end
				Size(inner, size * INNER_SIZE, size * INNER_SIZE)
				Shown(inner, true)
			end
			local s = size * (icon.scale or SCALE)
			Atlas(i, icon.atlas)
			Size(i, s * (icon.aspect or 1), s)
		else -- (b)
			Atlas(i, icon.atlas)
			Size(i, Fit(size, icon.aspect or Aspect(icon.atlas)))
			Shown(pin.ring, false)
		end
		Color(i, 1, 1, 1, 1)
	else -- (d)
		local r, c = Ring(pin), icon.color or WHITE
		File(r, CIRCLE)
		File(i, CIRCLE)
		Shown(r, true)
		Color(r, RING[1], RING[2], RING[3], RING[4])
		Size(r, size * DOT + RING_PAD, size * DOT + RING_PAD)
		Color(i, c[1], c[2], c[3], 1)
		Size(i, size * DOT, size * DOT)
	end
	if not inner then Shown(pin.inner, false) end
end
Pins.Style = Style -- (ui/Cluster.lua's pills)

---------------------------------------------------------------------------
-- Layers
---------------------------------------------------------------------------

local layers = {} -- Pins' own, the highest level first: { layer, opts }

-- What you track (Track.Focus: the tracked icon, the followed quest) wears a soft gold glow behind it, its size kept:
-- the world map's super-tracked quest glow (UI-QuestPoi-OuterGlow, added), toned down; Settings > Tracking > Tracked
-- icon: shown or not, its size (of the pin's), its opacity.
local GLOW_ART = "UI-QuestPoi-OuterGlow"
local glow = { on = true, size = 2, alpha = 1 }
local glowRev = 0 -- moves with the glow's settings (WithTrack: the layers lay out again)
local function Glow(pin, on)
	on = on and glow.on and Has(GLOW_ART)
	local g = pin.glow
	if not on then
		Shown(g, false)
		return
	end
	if not g then
		g = Tex(pin, "BACKGROUND", -8)
		g:SetAtlas(GLOW_ART)
		g:SetBlendMode("ADD")
		pin.glow = g
	end
	Size(g, pin.psize * glow.size, pin.psize * glow.size)
	if g.a ~= glow.alpha then
		g.a = glow.alpha
		g:SetAlpha(glow.alpha)
	end
	Shown(g, true)
end
local function Glows(key)
	return function(v)
		if glow[key] == v then return end
		glow[key], glowRev = v, glowRev + 1
	end
end
UI.Feel.Add("tracking", "Tracked icon", {
	{ key = "glow.on", kind = "toggle", label = "Glow", default = glow.on, apply = Glows("on"),
		tip = "A soft gold glow behind what you track or follow, as the world map marks its tracked quest." },
	{ key = "glow.size", kind = "slider", label = "Glow size", min = 1.2, max = 2.6, step = 0.1, pct = true,
		default = glow.size, apply = Glows("size"), when = function() return glow.on end,
		tip = "How far the glow reaches past the icon." },
	{ key = "glow.opacity", kind = "slider", label = "Glow opacity", min = 0.1, max = 1, step = 0.05, pct = true,
		default = glow.alpha, apply = Glows("alpha"), when = function() return glow.on end,
		tip = "How bright the glow is." },
})

-- A pin of e (its key's) on canvas c: its look, then its place where that moved.
local function Set(c, o, e, look, minZoom)
	o.entry = e
	Style(o, look)
	Glow(o, Track.Focus(e))
	local p = e.pos
	local x, y, on = (p.col - c.ox) * c.zoom, (p.row - c.oy) * c.zoom, c
	if minZoom then on = c.mins[minZoom] end -- (its frame for that zoom: Engine.At's)
	if o.az ~= c.zoom or o.x ~= x or o.y ~= y or o.amin ~= minZoom or o.on ~= on then
		At(c, o, "CENTER", p.col, p.row, 0, 0, minZoom)
	end
end

-- A pin layer: Engine.Layer(name, level, ..., rev, "pin") whose layout calls fill(put, inst, zoom, want).
-- fill calls put(e, look, minZoom) for each MM.Known e it would draw (Pins keeps those on the layout's map
-- and in its rect): look, StylePin's (above; a layer keeps one table a look, not one a layout); minZoom
-- (optional), shown from that zoom only (Engine.At's). want(minZoom): whether pins from that zoom draw in
-- this layout (false: they're left out, and shown once a layout would draw them: Engine.From), for fill
-- to skip a whole kind. rev: Engine.Layer's (Model.Known's revs); the tracked key's goes with it (Track.Rev).
-- opts (optional): lines(e) -> title, lines... for its tooltip (default e.name, e.text); tooltip(tip, e): fills
-- tip itself (GameTooltip owned by the pin, or the popup; shown by the caller); hover(e): the cursor on its pin e,
-- or (nil) off it.
local function WithTrack(rev)
	local a, t, s, g, n = nil, nil, nil, nil, 0
	return function()
		local r, tr, st = rev and rev(), Track.Rev(), Types.Rev()
		if r ~= a or tr ~= t or st ~= s or glowRev ~= g then a, t, s, g, n = r, tr, st, glowRev, n + 1 end
		return n
	end
end

function Pins.Layer(name, level, fill, rev, opts)
	local clustered = opts and opts.cluster -- (ui/Cluster.lua: its members stand in pills where they overlap)
	if clustered then rev = UI.Cluster.Add(name, fill, rev, opts) end
	rev = WithTrack(rev)
	-- The pins the canvas didn't show: set after the rest (a Get takes the next region, whatever it showed).
	local n, es, looks, mins = 0, {}, {}, {}
	local c, inst, zoom, c0, r0, c1, r1, any, from
	local function want(minZoom)
		if Engine.From(zoom, minZoom) then return true end
		if not from or minZoom < from then from = minZoom end
		return false
	end
	local function put(e, look, minZoom)
		local st = Of(look.type)
		if not st.show then return end -- (hidden: Settings > Pins)
		minZoom = Min(st, minZoom) -- (on the big map, zoomed in only: Settings > Pins)
		local p = e.pos
		if minZoom and Track.Focus(e) then minZoom = nil end -- (what you track: at any zoom)
		if p.inst ~= inst or minZoom and not want(minZoom) then return end
		if clustered and UI.Cluster.Hides(e, inst, zoom) then return end
		any = true
		if p.col >= c0 and p.col <= c1 and p.row >= r0 and p.row <= r1 then
			local o = Keep(c, "pin", e.key)
			if o then
				Set(c, o, e, look, minZoom)
			else
				n = n + 1
				es[n], looks[n], mins[n] = e, look, minZoom
			end
		end
		Yield()
	end
	local layer = Engine.Layer(name, level, function(canvas, i, z, a0, b0, a1, b1)
		c, inst, zoom, c0, r0, c1, r1, any, from, n = canvas, i, z, a0, b0, a1, b1, false, nil, 0
		fill(put, inst, zoom, want)
		for j = 1, n do
			Set(c, Get(c, "pin", "tex", MakePin, es[j].key), es[j], looks[j], mins[j])
			es[j], looks[j], mins[j] = nil, nil, nil
			if j % 32 == 0 then Yield() end
		end
		if from then return from end
		return not any or nil
	end, rev, "pin")
	local at, k = { layer = layer, opts = opts or NONE }, #layers + 1
	while k > 1 and layers[k - 1].layer.level < level do k = k - 1 end
	table.insert(layers, k, at)
	return layer
end

---------------------------------------------------------------------------
-- Hover, tooltips, clicks
---------------------------------------------------------------------------

local function Lines(e) return e.name, e.text end

-- The title, then the first line what it is (Tip.Sub: muted gold), the rest facts: small, DIM, wrapping (ui/Tip.lua's
-- look).
local function Fill(tip, pin, title, ...)
	tip:AddLine((pin and pin.mark or "") .. (title or "?"), 1, 1, 1)
	Tip.Title(Tip.Last(tip))
	local first = true
	for i = 1, select("#", ...) do
		local line = select(i, ...)
		if line then
			if first then Tip.Sub(tip, line) else Tip.Fact(tip, line) end
			first = false
		end
	end
end

-- A layer's tooltip for e on tip (its own filler, else its lines).
local function Tooltip(o, tip, e, pin)
	if o.tooltip then o.tooltip(tip, e) else Fill(tip, pin, (o.lines or Lines)(e)) end
end

-- The pin under the view's point (x, y) px from its centre, y down: on the topmost pin layer shown, the
-- one whose centre is nearest; and its layer.
local function Under(x, y)
	local cam = Camera.cam
	local z, cx, cy = cam.zoom, cam.cx, cam.cy
	for _, at in ipairs(layers) do
		local l = at.layer
		local c = l.front
		local p = l.on and c and c.alpha > 0 and c.pools.pin
		local best, d
		for i = 1, p and p.n or 0 do
			local o = p[i]
			if not (o.amin and z < o.amin) then
				local dx, dy, r = (o.acol - cx) * z - x, (o.arow - cy) * z - y, o.psize / 2
				if dx >= -r and dx <= r and dy >= -r and dy <= r and not (best and dx * dx + dy * dy >= d) then
					best, d = o, dx * dx + dy * dy
				end
			end
		end
		if best then return best, at end
	end
end

-- The pin under the cursor grows a little (HOVER, eased out, quick), and settles back when the cursor leaves it:
-- the client's animations, a pin's made the first time it's hovered. The grown scale is held by a long end delay
-- (an animation's last state lasts only while it plays).
local HOVER, GROW_TIME, SETTLE_TIME, HOLD = 1.2, 0.08, 0.12, 3600
local function Grows(pin)
	if pin.grow then return end
	local g = pin:CreateAnimationGroup()
	local a = g:CreateAnimation("Scale")
	a:SetScaleFrom(1, 1)
	a:SetScaleTo(HOVER, HOVER)
	a:SetDuration(GROW_TIME)
	a:SetSmoothing("OUT")
	a:SetEndDelay(HOLD)
	pin.grow = g
	g = pin:CreateAnimationGroup()
	a = g:CreateAnimation("Scale")
	a:SetScaleFrom(HOVER, HOVER)
	a:SetScaleTo(1, 1)
	a:SetDuration(SETTLE_TIME)
	a:SetSmoothing("OUT")
	pin.settle = g
end
local function Settle(pin)
	if pin and pin.grow and pin.grow:IsPlaying() then
		pin.grow:Stop()
		pin.settle:Play()
	end
end

local hovered, hoveredAt, showing -- the pin under the cursor, its layer's, the entry its tooltip shows
local waiting = false -- its tooltip waits for the popup to close

-- The cursor onto pin (nil: off any): the last one's tooltip hidden if it still has it, the new one's built.
local function Hover(pin, at)
	if hovered and GameTooltip:IsOwned(hovered) then GameTooltip:Hide() end
	if hovered ~= pin then
		Settle(hovered)
		if pin then
			Grows(pin)
			pin.settle:Stop()
			pin.grow:Play()
		end
	end
	local was = hoveredAt
	hovered, hoveredAt, showing = pin, at, pin and pin.entry
	if was and was.opts.hover and was ~= at then was.opts.hover(nil) end
	if not pin then return end
	local o, e = at.opts, pin.entry
	if o.hover then o.hover(e) end
	waiting = UI.Popup.IsOpen()
	if waiting then return end -- (a popup stands: no tooltip over or beside it, till it closes)
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
	Tooltip(o, GameTooltip, e, pin)
	GameTooltip:Show()
end

-- The view has the mouse: nothing over it took it (a button, another addon's pin, a menu), as the spike's
-- topmost pin frame had it.
local inside = false
Window.view:HookScript("OnEnter", Runtime.Wrap("map: pins entered", function() inside = true end))
Window.view:HookScript("OnLeave", Runtime.Wrap("map: pins left", function()
	inside = false
	Hover(nil)
end))

Runtime.Step("ui", "map: pins", function()
	local pin, at
	local mm = Model.minimap
	if (inside or mm and mm.mouse) and not (mm and mm.blip) and not Window.Blank() then -- (through the overlay; a blip's tooltip first)
		local x, y = Window.Cursor()
		local w, h = Window.Size()
		pin, at = Under(x - w / 2, y - h / 2)
	end
	if pin ~= hovered or pin and (pin.entry ~= showing or waiting and not UI.Popup.IsOpen()) then Hover(pin, at) end
end, { shownOnly = Window.frame })

-- The pin under the cursor: its MM.Known entry and its layer's name; nil: none.
function Pins.Hovered()
	if hovered then return hovered.entry, hoveredAt.layer.name end
end

-- A click on the map (button: "LeftButton" or "RightButton", the same either way): the pin under the cursor's
-- popup, its tooltip grown into it with its actions (ui/Popup.lua, ui/Track.lua's Actions; a grid pin's: the entry
-- it stands for). True when a pin took it.
function Pins.Tap(button)
	if UI.Cluster.Tap(button) then return true end
	if not hovered then return false end
	local e, o, pin = hovered.entry, hoveredAt.opts, hovered
	UI.Popup.Open(function(tip) Tooltip(o, tip, e, pin) end, Track.Actions(rawget(e, "real") or e))
	waiting = true -- (its tooltip again once the popup closes)
	return true
end
