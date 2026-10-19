-- Quest areas (Layers.lua:765-1069): the game's own objective areas ("blobs"), drawn as the world map
-- draws them, by QuestPOIFrames on the "questAreas" layer (over the tiles, under the borders: parity S8):
-- one frame per map and style (art and alpha are per frame), its map's rect in size, its quests drawn
-- in it: the quest you follow filled blue, the rest a quiet edge in what they still need (rust: kill,
-- green: gather, blue: other) (S53). The client draws a blob into its frame's rect as it stands at
-- DrawBlob and lays a moved frame out only at the frame's end (spike-bugs L1), and its drawing doesn't
-- follow a scaled canvas (P5): so the layer is out of sight while the zoom moves and laid out where it's
-- headed once the wheel stops (Engine's "hold": after names and pins); a frame is drawn as it's laid out
-- (on a canvas at its own scale and zoom, else the frame it's shown at the camera's zoom), again the next
-- frame, and the layer shows again once they all are (Layers.lua:2032-2043). A frame whose quests (by
-- id), style and size are as they were, and the game's areas too (Known("quests")' poi), isn't drawn
-- again: its drawing moves with it (a pan, Layers.lua:142-156), and a count ticking changes no area. Each
-- stands on the point of its rect nearest the canvas's origin (a zone at zoom 800 is up to 9,600 px).
-- Unfinished kill, collect and interact quests with no area (Model's estimate) get a faint disc with a
-- dashed edge, one for quests within 0.6 r (Layers.lua:945-986: S54), out of sight with the rest.
-- Hovering a quest's area or its pin (ui/Quests.lua) lights its area: drawn again on top (HOVER); an
-- area's tooltip is its quest's (ui/QuestTooltip.lua), but a tooltip shown already wins (a pin's), and
-- it stays up through a zoom (the frames last shown answer the hit test while the layer is out of
-- sight, as the spike's blobFrames: Layers.lua:992-1025); a click on an area (no pin under it:
-- Pins.Tap) follows its quest, again to stop (Layers.lua:990-1069).

local _, ns = ...
local UI, Model = ns.UI, ns.Model
local Atlas, Runtime = ns.Atlas, ns.Runtime
local Engine, Window, Camera = UI.Engine, UI.Window, UI.Camera
local Get, Keep, At, Yield = Engine.Get, Engine.Keep, Engine.At, Runtime.Yield
local ScreenToTile = Atlas.Camera.ScreenToTile
local Command = ns.Game.Command

local LEVEL = 3 -- over the tiles (1) and the shade's 2 (M4.4), under the borders (7) (Core.lua:149)
-- The client's area art (each <base>Inside / <base>Outside): quest blue, bonus-objective green,
-- archaeology rust (Layers.lua:785-789).
local ART = { blue = "Interface\\WorldMap\\UI-QuestBlob-", green = "Interface\\WorldMap\\UI-BonusObjectiveBlob-",
	rust = "Interface\\WorldMap\\UI-ArchaeologyBlob-" }
-- Fill and edge alpha (0-255), edge width (Layers.lua:795-800); level: over the canvas (Layers.lua:910).
local STYLES = {
	followed = { art = "blue", fill = 32, border = 120, width = 0.8, level = 2, key = 1 },
	kill = { art = "rust", fill = 0, border = 85, width = 0.6, level = 1, key = 2 },
	gather = { art = "green", fill = 0, border = 55, width = 0.6, level = 1, key = 3 },
	other = { art = "blue", fill = 0, border = 85, width = 0.6, level = 1, key = 4 },
}
local HOVER = {} -- by art: lit, on top (Layers.lua:822, 853)
for art in pairs(ART) do HOVER[art] = { art = art, fill = 40, border = 150, width = 0.8, level = 3 } end
local RADIUS = 110 / 533.33 -- tiles: an estimate's (Layers.lua:78)
local SEGMENTS, DASH = 36, 1.2 -- its edge: every other of 36 arcs, each 1.2 of one long (Layers.lua:966-985)
local DISC, EDGE, THICK = { 1, 0.85, 0.4, 0.05 }, { 1, 0.85, 0.4, 0.35 }, 1.5 -- Layers.lua:974, 984
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask" -- UI.lua:6
local POINTS = { { "TOPLEFT", "TOP", "TOPRIGHT" }, { "LEFT", "CENTER", "RIGHT" }, { "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" } }

local Areas = {}
UI.Areas = Areas

local function On(name) return Engine.LayerOn(name) end

---------------------------------------------------------------------------
-- Blob frames (Layers.lua:772-818)
---------------------------------------------------------------------------

local function MakeBlob(c)
	local f = CreateFrame("QuestPOIFrame", nil, c)
	f:EnableMouse(false) -- the view's: hover is worked out from the cursor (Layers.lua:777-779)
	f.n, f.q, f.drawn = 0, {}, 0 -- f.q[1..n]: its quests' entries; drawn: times since they changed
	return f
end

-- Its art and alpha (Layers.lua:893-910): true if they changed.
local function Look(f, st, level)
	local changed = false
	if f.art ~= st.art then
		f:SetFillTexture(ART[st.art] .. "Inside")
		f:SetBorderTexture(ART[st.art] .. "Outside")
		f.art, changed = st.art, true
	end
	if f.st ~= st then
		f:SetFillAlpha(st.fill)
		f:SetBorderAlpha(st.border)
		f:SetBorderScalar(st.width)
		f.st, changed = st, true
	end
	if f:GetFrameLevel() ~= level then f:SetFrameLevel(level) end
	return changed
end

-- 1, 2 or 3: a, the middle or b, whichever is nearest o; and it.
local function Third(a, b, o)
	local m = (a + b) / 2
	if o < (a + m) / 2 then return 1, a end
	if o > (m + b) / 2 then return 3, b end
	return 2, m
end

-- f on canvas c for map rect r at zoom, on the point of r nearest the canvas's origin: true if its size
-- changed.
local function Place(c, f, r, zoom)
	local i, col = Third(r.col0, r.col1, c.ox)
	local j, row = Third(r.row0, r.row1, c.oy)
	local point, x, y = POINTS[j][i], (col - c.ox) * zoom, (row - c.oy) * zoom
	if f.az ~= zoom or f.x ~= x or f.y ~= y or f.apoint ~= point or f.on ~= c then At(c, f, point, col, row) end
	f.rect = r
	local w, h = (r.col1 - r.col0) * zoom, (r.row1 - r.row0) * zoom
	if f.w == w and f.h == h then return false end
	f.w, f.h = w, h
	f:SetSize(w, h)
	return true
end

local draws = 0 -- frames drawn (a hit test's answer may change)

-- Its quests drawn into its rect, laid out first (Layers.lua:802-818).
local function Draw(f)
	f:GetRect() -- (reading it lays it out in the client: Layers.lua:812)
	f:SetMapID(f.map)
	f:DrawNone()
	for i = 1, f.n do f:DrawBlob(f.q[i].quest, true) end
	f.drawn, draws = f.drawn + 1, draws + 1
end

-- f for group g (a map and style, its entries g[1..n]) as the game's areas are at poi: drawn now if
-- draw, and it changed or isn't yet.
local function SetBlob(c, f, g, zoom, base, draw, poi)
	local dirty = Look(f, g.st, base + g.st.level)
	if Place(c, f, g.rect, zoom) then dirty = true end
	if f.map ~= g.map or f.n ~= g.n or f.poi ~= poi then dirty = true end
	f.map, f.poi = g.map, poi
	for i = 1, math.max(f.n, g.n) do
		local a, b = f.q[i], g[i]
		if not (a and b and a.quest == b.quest) then dirty = true end
		f.q[i] = b
	end
	f.n = g.n
	if dirty then f.drawn = 0 end
	if draw and f.drawn == 0 then Draw(f) end
end

---------------------------------------------------------------------------
-- Estimates (Layers.lua:945-986): a disc and 18 dashes on a frame of their own, centred on the spot
---------------------------------------------------------------------------

local function Unsnap(r)
	r:SetSnapToPixelGrid(false)
	r:SetTexelSnappingBias(0)
end

local function MakeSpot(c)
	local f = CreateFrame("Frame", nil, c)
	local disc = f:CreateTexture(nil, "ARTWORK", nil, 0)
	Unsnap(disc)
	disc:SetTexture(CIRCLE)
	disc:SetVertexColor(DISC[1], DISC[2], DISC[3], DISC[4])
	disc:SetAllPoints()
	f.disc, f.dashes = disc, {}
	for i = 1, SEGMENTS / 2 do
		local l = f:CreateLine(nil, "ARTWORK", nil, 1)
		Unsnap(l)
		l:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], EDGE[4])
		l:SetThickness(THICK)
		f.dashes[i] = l
	end
	return f
end

local function SetSpot(c, f, p, zoom, base)
	if f:GetFrameLevel() ~= base then f:SetFrameLevel(base) end -- (under the blobs)
	local x, y = (p.col - c.ox) * zoom, (p.row - c.oy) * zoom
	if f.az ~= zoom or f.x ~= x or f.y ~= y or f.on ~= c then At(c, f, "CENTER", p.col, p.row) end
	local r = RADIUS * zoom
	if f.r == r then return end
	f.r = r
	f:SetSize(r * 2, r * 2)
	for i, l in ipairs(f.dashes) do
		local a1, a2 = (i - 1) * 2 / SEGMENTS * 2 * math.pi, ((i - 1) * 2 + DASH) / SEGMENTS * 2 * math.pi
		l:SetStartPoint("CENTER", f, math.cos(a1) * r, -math.sin(a1) * r)
		l:SetEndPoint("CENTER", f, math.cos(a2) * r, -math.sin(a2) * r)
	end
end

---------------------------------------------------------------------------
-- The layer
---------------------------------------------------------------------------

-- A layout's frames: its groups by key (a map's * 8 + its style's), each { map, rect, st, n, entries };
-- its estimates' spots; the keys and spots its canvas didn't show (set after the rest).
local groups, keys, nkeys = {}, {}, 0
local spots, nspots = {}, 0
local missed, nmissed = {}, 0

local function Group(e, r)
	local st = STYLES[e.followed and "followed" or e.need or "other"]
	local key = e.areaMap * 8 + st.key
	local g = groups[key]
	if not g then
		g = { n = 0 }
		groups[key] = g
	end
	if g.n == 0 then
		nkeys = nkeys + 1
		keys[nkeys] = key
		g.map, g.rect, g.st = e.areaMap, r, st
	end
	g.n = g.n + 1
	g[g.n] = e
end

local function Spot(p)
	for i = 1, nspots do
		if spots[i] == p then return end
	end
	nspots = nspots + 1
	spots[nspots] = p
end

local function Rev()
	return select(2, Model.Known("quests")) * 4 + (On("quests") and 2 or 0) + (On("questAreasApprox") and 1 or 0)
end

local layer = Engine.Layer("questAreas", LEVEL, function(c, inst, zoom, c0, r0, c1, r1)
	for i = 1, nkeys do
		local g = groups[keys[i]]
		for j = 1, g.n do g[j] = nil end
		g.n = 0
	end
	nkeys, nspots, nmissed = 0, 0, 0
	if not On("quests") then return true end
	local approx, any, list = On("questAreasApprox"), false, Model.Known("quests")
	for _, e in ipairs(list) do
		local r = e.areaMap and Atlas.MapRect(e.areaMap)
		if r and r.inst == inst then
			any = true
			if r.col1 >= c0 and r.col0 <= c1 and r.row1 >= r0 and r.row0 <= r1 then Group(e, r) end
		end
		local p = approx and e.estimate
		if p and p.inst == inst then
			any = true
			if p.col + RADIUS >= c0 and p.col - RADIUS <= c1 and p.row + RADIUS >= r0 and p.row - RADIUS <= r1 then Spot(p) end
		end
	end
	-- Drawn now on a canvas at its own scale, unless the zoom moves (out of sight till it lands): else the
	-- frame after the swap (Front).
	local base, draw = c:GetFrameLevel(), c.scale == 1 and zoom == Camera.cam.zoom and UI.Motion.Goal() == zoom
	for i = 1, nkeys do
		local f = Keep(c, "blob", keys[i])
		if f then
			SetBlob(c, f, groups[keys[i]], zoom, base, draw, list.poi)
		else
			nmissed = nmissed + 1
			missed[nmissed] = keys[i]
		end
		Yield()
	end
	for i = 1, nmissed do
		SetBlob(c, Get(c, "blob", "tex", MakeBlob, missed[i]), groups[missed[i]], zoom, base, draw, list.poi)
		Yield()
	end
	nmissed = 0
	for i = 1, nspots do
		local f = Keep(c, "spot", spots[i])
		if f then
			SetSpot(c, f, spots[i], zoom, base)
		else
			nmissed = nmissed + 1
			missed[nmissed] = spots[i]
		end
		Yield()
	end
	for i = 1, nmissed do
		SetSpot(c, Get(c, "spot", "tex", MakeSpot, missed[i]), missed[i], zoom, base)
		missed[i] = nil
		Yield()
	end
	return not any or nil
end, Rev, "hold")
Areas.layer = layer

---------------------------------------------------------------------------
-- Each frame: shown or not, drawn again, hover, tooltip (Layers.lua:822-866, 990-1025)
---------------------------------------------------------------------------

local alpha = 1 -- the layer's frame's
local shown -- the canvas shown
local held -- the canvas hovering hit-tests: the one shown, and while the layer's out of sight its last

-- The canvas to show: the front at the camera's zoom (no crossfade), each frame drawn until twice; out of
-- sight from a zoom until every one has been (nil).
local function Front()
	local c = layer.front
	if not (layer.on and c and c.zoom == Camera.cam.zoom and not layer.fade) then return nil end
	local p, ready = c.pools.blob, true
	for i = 1, p and p.n or 0 do
		local f = p[i]
		if f.drawn < 2 then
			if f.drawn == 0 then ready = false end
			Draw(f)
		end
	end
	return (ready or shown) and c or nil -- (shown already: a pan's new frames show as they're drawn)
end

local function Entry(quest)
	for _, e in ipairs(Model.Known("quests")) do
		if e.quest == quest then return e end
	end
end

-- Lit: a quest's area under the cursor, or its pin (Layers.lua:822-866): drawn again on top in its
-- own frame, on the canvas shown, twice.
local hover = {} -- pin, area: the quest under the cursor
local lit, litOn, litEpoch -- the entry it shows, on which canvas and epoch
local light -- its frame

local function Light(c)
	local q = hover.pin or hover.area
	local e = c and q and Entry(q)
	local r = e and e.areaMap and Atlas.MapRect(e.areaMap)
	if not (r and r.inst == c.inst) then e = nil end
	local epoch = c and c.epoch
	if e == lit and c == litOn and epoch == litEpoch then
		if e and light.drawn < 2 then Draw(light) end
		return
	end
	lit, litOn, litEpoch = e, c, epoch
	if not e then
		if light then light:Hide() end
		return
	end
	light = light or MakeBlob(c)
	Place(c, light, r, c.zoom)
	Look(light, HOVER[STYLES[e.followed and "followed" or e.need or "other"].art], c:GetFrameLevel() + 3)
	light.map, light.n, light.q[1], light.drawn = e.areaMap, 1, e, 0
	light:Show()
	Draw(light)
end

-- Every frame of c drawn as it stands (none since dirtied by a layout).
local function Drawn(c)
	local p = c.pools.blob
	for i = 1, p and p.n or 0 do
		if p[i].drawn == 0 then return false end
	end
	return true
end

-- The quest whose drawn area is under the cursor on c (Layers.lua:868-872, 992-1000), tested again only
-- when the cursor, the camera, the canvas or a drawing changed.
local asked = {} -- x, y, cx, cy, zoom, c, draws: what the last answer, q, was for
local function Under(c)
	local w, h = Window.Size()
	local x, y = Window.Cursor()
	local cam, a = Camera.cam, asked
	if a.x == x and a.y == y and a.cx == cam.cx and a.cy == cam.cy and a.zoom == cam.zoom and a.c == c and a.draws == draws then
		return a.q
	end
	a.x, a.y, a.cx, a.cy, a.zoom, a.c, a.draws, a.q = x, y, cam.cx, cam.cy, cam.zoom, c, draws, nil
	local col, row = ScreenToTile(cam, w, h, x, y)
	local p = c.pools.blob
	for i = 1, p and p.n or 0 do
		local f = p[i]
		local r = f.rect
		if col >= r.col0 and col <= r.col1 and row >= r.row0 and row <= r.row1 then
			local q = f:UpdateMouseOverTooltip((col - r.col0) / (r.col1 - r.col0), -- /: never 0 (a map's rect has a size)
				(row - r.row0) / (r.row1 - r.row0)) -- /: never 0 (a map's rect has a size)
			if q then
				a.q = q
				return q
			end
		end
	end
end

local owner = CreateFrame("Frame", nil, Window.view) -- an area's tooltip's (Layers.lua:990)
local showing -- the entry it shows

Runtime.Step("ui", "map: quest areas", function()
	local c = Front()
	shown = c
	local a = c and 1 or 0
	if alpha ~= a then
		alpha = a
		layer.frame:SetAlpha(a)
	end
	-- Out of sight for a zoom, its frames hold their drawings till a layout changes one (the hit test is in
	-- the map's own coordinates, whatever the zoom).
	if c then held = c elseif held and not (layer.on and Drawn(held)) then held = nil end
	-- The cursor in the view's rect, over what stands on it too (a control, another addon's pin), as the
	-- spike's viewport:IsMouseOver() (Core.lua:1264, 1325): the area stays lit, its tooltip up but for one
	-- shown already (that pin's).
	local q = held and Window.view:IsMouseOver() and Under(held) or nil
	hover.area = q
	Light(c)
	-- Who has GameTooltip over an area: one shown already (a pin's), else the area's (Layers.lua:1012-1025).
	local e, tip = q and Entry(q), GameTooltip
	if e then
		local o = tip:GetOwner()
		if o and o ~= owner and tip:IsShown() then return end
		if e ~= showing or o ~= owner or not tip:IsShown() then
			showing = e
			tip:SetOwner(owner, "ANCHOR_CURSOR_RIGHT", 12, 0)
			UI.QuestTooltip.Show(e)
		end
	elseif showing and tip:IsOwned(owner) then
		showing = nil
		tip:Hide()
	end
end, { shownOnly = Window.frame })

-- A quest's pin under the cursor (its layer's hover: ui/Quests.lua), or none: its area lit.
function Areas.Hover(e) hover.pin = e and e.quest end

-- Follow e's quest: the game's super-tracked quest, watched; again to stop (Layers.lua:1033-1046).
function Areas.Follow(e) Command({ kind = "follow", quest = not e.followed and e.quest }) end

-- A click on the map no pin took (ui/Window.lua): on a quest's drawn area, follows it, again to stop
-- (Layers.lua:1052-1069). True if it was one.
function Areas.Tap()
	local q = shown and Under(shown)
	local e = q and Entry(q)
	if not e then return false end
	Areas.Follow(e)
	return true
end

UI.Menus.Layer({ key = "questAreas", label = "Quest areas", group = "quests",
	tip = "Where each quest's objectives are, as the game draws them." })
UI.Menus.Layer({ key = "questAreasApprox", label = "Estimate missing areas", group = "quests", parent = "questAreas",
	tip = "A rough dashed circle for kill and collect objectives the game gives no area for." })
