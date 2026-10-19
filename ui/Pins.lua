-- The one pin store (spike-bugs D1: every pin drawn from one store, diffed by id). Each kind of pin
-- (blips, rares; quests, offers and the rest to come) is an Engine "pin" layer made with Pins.Layer,
-- its Model.Known entries put by key: a layout keeps the pin its canvas showed for that key
-- (Engine.Keep) and sets only what changed, its look (StylePin, Layers.lua:338-400: each setter
-- called only when its value differs) and its place (Engine.At, when its tile, the canvas's zoom or
-- origin, or its minimum zoom differ), so a pan's layout re-places only the pins it adds and a changed
-- rev re-sets only the pins that changed; an unchanged rev lays nothing out (Engine). A pin is a frame
-- holding the spike's regions (Layers.lua:305-336) that doesn't take the mouse: the spike's took it and
-- passed clicks on (SetPropagateMouseClicks), but a layer's other canvas stands shown at alpha 0 with
-- the pins it showed, which would catch it; so each frame Pins finds the pin under the cursor on the
-- canvases shown (the topmost layer's, the nearest centre), and every click and drag is the view's.
-- Its tooltip: GameTooltip ANCHOR_RIGHT on the pin, its title, then grey 0.85 lines in
-- GameTooltipTextSmall, restored when it hides or clears (Layers.lua:288-301, QuestInfo.lua:253-272);
-- built once a hover, hidden on the one owner-checked path: the cursor off it, a menu open, the window
-- hidden (ui/Window.lua).

local _, ns = ...
local UI, Runtime = ns.UI, ns.Runtime
local Engine, Window, Camera, Menus = UI.Engine, UI.Window, UI.Camera, UI.Menus
local Get, Keep, At, Yield = Engine.Get, Engine.Keep, Engine.At, Runtime.Yield

local SIZE = 14 -- px: a pin's (StylePin's default, Layers.lua:340)
local INNER_SIZE, INNER_SHADE = 0.56, 0.55 -- (c)'s objective icon: share of its disc, its shade (Layers.lua:303)
local SCALE = 0.62 -- (c)'s atlas over its disc (Layers.lua:376)
local DOT, RING_PAD = 0.6, 3 -- (d): the dot's share of size, its ring's past it (Layers.lua:396-399)
local RING = { 0, 0, 0, 0.9 } -- Layers.lua:396
local GLOW, GLOW_PAD = { 1, 0.82, 0.3, 0.45 }, 14 -- the followed one's halo (Layers.lua:345-347)
local WHITE = { 1, 1, 1 }
local GREY = 0.85 -- a tooltip's lines under its title (Layers.lua:298)
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask" -- UI.lua:6
local NONE = {}

local Pins = {}
UI.Pins = Pins

---------------------------------------------------------------------------
-- StylePin (Layers.lua:338-400)
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

-- The rest made the first time a look needs them: a ring (or a disc under the icon), the objective icon
-- inside it, the halo, the count.
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

local function Glow(pin)
	local t = pin.glow
	if t then return t end
	t = Tex(pin, "BACKGROUND")
	t:SetTexture(CIRCLE)
	t:SetVertexColor(GLOW[1], GLOW[2], GLOW[3], GLOW[4])
	pin.glow = t
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
local function File(t, file) -- a whole file
	if t.art ~= file then
		t.art = file
		t:SetTexture(file)
		t:SetTexCoord(0, 1, 0, 1)
	end
end
local function Atlas(t, atlas)
	if t.art ~= atlas then
		t.art = atlas
		t:SetAtlas(atlas)
	end
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

-- look: { size? (14), icon? = { texture | atlas, under?, tint?, inner?, scale?, aspect?, color? }, glow?,
-- count? }: (a) a texture, bare; (b) an atlas; (c) an atlas over its under atlas tinted, the inner
-- texture in it; (d) else (an atlas the client lacks too) a dot of its colour on a dark ring. glow: the
-- halo (the quest you follow); count: a line under it.
local function Style(pin, look)
	local size, icon = look.size or SIZE, look.icon or NONE
	pin.psize = size
	Size(pin, size, size)
	if look.count or pin.count then
		local fs = Count(pin)
		if fs.text ~= look.count then
			fs.text = look.count
			fs:SetText(look.count)
		end
	end
	if look.glow then
		local g = Glow(pin)
		Size(g, size + GLOW_PAD, size + GLOW_PAD)
		Shown(g, true)
	else
		Shown(pin.glow, false)
	end
	local i, inner = pin.icon, false
	if icon.texture then -- (a)
		File(i, icon.texture)
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
			Size(i, size, size)
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

---------------------------------------------------------------------------
-- Layers
---------------------------------------------------------------------------

local layers = {} -- Pins' own, the highest level first: { layer, opts }

-- A pin of e (its key's) on canvas c: its look, then its place where that moved.
local function Set(c, o, e, look, minZoom)
	o.entry = e
	Style(o, look)
	local p = e.pos
	local x, y = (p.col - c.ox) * c.zoom, (p.row - c.oy) * c.zoom
	if o.az ~= c.zoom or o.x ~= x or o.y ~= y or o.amin ~= minZoom or o.on ~= (minZoom and c.mins[minZoom] or c) then
		At(c, o, "CENTER", p.col, p.row, 0, 0, minZoom)
	end
end

-- A pin layer: Engine.Layer(name, level, ..., rev, "pin") whose layout calls fill(put, inst, zoom, want).
-- fill calls put(e, look, minZoom) for each MM.Known e it would draw (Pins keeps those on the layout's map
-- and in its rect): look, StylePin's (above; a layer keeps one table a look, not one a layout); minZoom
-- (optional), shown from that zoom only (Engine.At's). want(minZoom): whether pins from that zoom draw in
-- this layout (false: they're left out, and shown once a layout would draw them: Engine.From), for fill
-- to skip a whole kind. rev: Engine.Layer's (Model.Known's revs). opts (optional): lines(e) -> title,
-- lines... for its tooltip (default e.name, e.text); tooltip(GameTooltip, e): fills it itself, owned by
-- the pin (and Shows it); hover(e): the cursor on its pin e, or (nil) off it; click(e, button): a click on
-- it (Pins.Tap).
function Pins.Layer(name, level, fill, rev, opts)
	local n, es, looks, mins = 0, {}, {}, {} -- the pins the canvas didn't show: set after the rest (a Get takes the next region, whatever it showed)
	local c, inst, zoom, c0, r0, c1, r1, any, from
	local function want(minZoom)
		if Engine.From(zoom, minZoom) then return true end
		if not from or minZoom < from then from = minZoom end
		return false
	end
	local function put(e, look, minZoom)
		local p = e.pos
		if p.inst ~= inst or minZoom and not want(minZoom) then return end
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

-- GameTooltip's lines in small type (the facts under a pin's name), each its font back when the tooltip
-- hides or clears (QuestInfo.lua:253-272). Its lines' font strings by name, found once each.
local left, styled, nstyled = {}, {}, 0
local function Line(i)
	if not left[i] then
		local name = GameTooltip:GetName() .. "TextLeft" .. i
		for _, r in ipairs({ GameTooltip:GetRegions() }) do
			if r:GetName() == name then left[i] = r end
		end
	end
	return left[i]
end

-- Lines first + 1 .. last of the shown GameTooltip in small type, then shown again (resized to them).
function Pins.Small(first, last)
	for i = first + 1, last do
		local fs = Line(i)
		fs:SetFontObject(GameTooltipTextSmall)
		nstyled = nstyled + 1
		styled[nstyled] = fs
	end
	GameTooltip:Show()
end

local Restore = Runtime.Wrap("map: tip fonts", function()
	for i = 1, nstyled do
		styled[i]:SetFontObject(GameTooltipText)
		styled[i] = nil
	end
	nstyled = 0
end)
GameTooltip:HookScript("OnHide", Restore)
GameTooltip:HookScript("OnTooltipCleared", Restore)

local function Lines(e) return e.name, e.text end

-- The title, then each line given grey and small (Layers.lua:288-301).
local function Fill(title, ...)
	GameTooltip:AddLine(title or "?")
	for i = 1, select("#", ...) do
		local line = select(i, ...)
		if line then GameTooltip:AddLine(line, GREY, GREY, GREY, true) end
	end
	GameTooltip:Show()
	Pins.Small(1, GameTooltip:NumLines())
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

local hovered, hoveredAt, showing -- the pin under the cursor, its layer's, the entry its tooltip shows

-- The cursor onto pin (nil: off any): the last one's tooltip hidden if it still has it, the new one's built.
local function Hover(pin, at)
	if hovered and GameTooltip:IsOwned(hovered) then GameTooltip:Hide() end
	local was = hoveredAt
	hovered, hoveredAt, showing = pin, at, pin and pin.entry
	if was and was.opts.hover and was ~= at then was.opts.hover(nil) end
	if not pin then return end
	local o, e = at.opts, pin.entry
	if o.hover then o.hover(e) end
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
	if o.tooltip then
		o.tooltip(GameTooltip, e)
	else
		Fill((o.lines or Lines)(e))
	end
end

Runtime.Step("ui", "map: pins", function()
	local pin, at
	if Window.view:IsMouseOver() and not Menus.IsOpen() then
		local x, y = Window.Cursor()
		local w, h = Window.Size()
		pin, at = Under(x - w / 2, y - h / 2)
	end
	if pin ~= hovered or pin and pin.entry ~= showing then Hover(pin, at) end
end, { shownOnly = Window.frame })

-- The pin under the cursor: its MM.Known entry and its layer's name; nil: none.
function Pins.Hovered()
	if hovered then return hovered.entry, hoveredAt.layer.name end
end

-- A click on the map (button: "LeftButton", ...): the pin under the cursor's, if its layer takes clicks.
-- True when one did.
function Pins.Tap(button)
	local click = hovered and hoveredAt.opts.click
	if not click then return false end
	click(hovered.entry, button)
	return true
end
