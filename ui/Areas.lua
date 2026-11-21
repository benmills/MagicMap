-- Quest areas: the game's own objective areas ("blobs"), drawn as the world map draws them, by
-- QuestPOIFrames on the "questAreas" layer over the tiles: one frame per map and style (art and alpha are
-- per frame), its map's rect in size, the quest you follow filled blue, the rest a quiet edge in what they
-- still need (rust: kill, green: gather, blue: other). A QuestPOIFrame loads only client files (addon
-- TGAs show the missing-texture green). The client draws a blob into its frame's rect as it stands at
-- DrawBlob, lays a moved frame out only at the frame's end, and its drawing doesn't follow a scaled canvas:
-- so the layer is out of sight while the zoom moves, laid out where it's headed once the wheel stops
-- (Engine's "hold"); a frame is drawn as it's laid out and again the next frame, and the layer shows once
-- they all are. A frame whose quests, style, size and game areas are as they were isn't drawn again (its
-- drawing moves with it on a pan). Each stands on the point of its rect nearest the canvas's origin (a zone
-- at zoom 800 is up to 9,600 px). Hovering an area or its pin (ui/Quests.lua) lights it, drawn again on
-- top; its tooltip is its quest's (ui/QuestTooltip.lua) unless one is up already, and stays up through a
-- zoom (the frames last shown answer the hit test). A click on an area no pin took follows its quest,
-- again to stop.
local _, ns = ...
local UI, Model = ns.UI, ns.Model
local Atlas, Runtime = ns.Atlas, ns.Runtime
local Engine, Window, Camera = UI.Engine, UI.Window, UI.Camera
local Get, Keep, At, Yield = Engine.Get, Engine.Keep, Engine.At, Runtime.Yield
local ScreenToTile = Atlas.Camera.ScreenToTile
local Command = ns.Game.Command

local LEVEL = 4 -- over the tiles (1) and the buildings (4: these pieces stand over their canvas)
-- The client's area art (each <base>Inside / <base>Outside): quest blue, bonus-objective green,
-- archaeology rust.
local ART = { blue = "Interface\\WorldMap\\UI-QuestBlob-", green = "Interface\\WorldMap\\UI-BonusObjectiveBlob-",
	rust = "Interface\\WorldMap\\UI-ArchaeologyBlob-" }
-- Fill and edge alpha (0-255), edge width, level over the canvas; hover: lit, on top, a gentle lift over
-- the area's own style (the world map's hover). The look's numbers are the settings' ("areas.<name>",
-- Settings > Advanced, declared here: ui/Feel.lua; Quests > Areas a strength over them), alphas 0-255
-- shown as %. Restyle makes the style tables from them anew when they change (a
-- frame's style is the table, so a new one is applied again), and the layer's rev moves with that: every frame
-- laid out and drawn again.
local DEFAULTS = { fFill = 32, fEdge = 120, fWidth = 0.8, oFill = 0, oEdge = 85, oWidth = 0.6, hFill = 45, hEdge = 150 }
local Areas = {}
UI.Areas = Areas
local function Alpha(key, label, tip)
	return { key = "areas." .. key, kind = "slider", label = label, min = 0, max = 255, step = 1, of = 255, default = DEFAULTS[key], tip = tip }
end
local function Width(key, tip)
	return { key = "areas." .. key, kind = "slider", label = "Edge width", min = 0.2, max = 1.5, step = 0.1, fmt = "%.1f",
		default = DEFAULTS[key], tip = tip }
end
-- The two a player sets (Settings > Quests > Areas): each a strength over its raw numbers' (Advanced's) fill and edge.
local STRENGTH = { min = 0, max = 2, step = 0.1, pct = true, default = 1 }
local function Strength(key, label, tip)
	local t = { key = "areas." .. key, kind = "slider", label = label, tip = tip }
	for k, v in pairs(STRENGTH) do t[k] = v end
	return t
end
UI.Feel.Add("quests", "Areas", {
	Strength("followed", "Followed quest", "How strongly the area of the quest you follow is drawn: its fill and edge (100%: as the world map draws it; 0%: not at all)."),
	Strength("others", "Other quests", "How strongly your other quests' areas are drawn: their edge (100%: as the world map draws them; 0%: not at all)."),
})
UI.Feel.Add("advanced", "Followed quest area", {
	Alpha("fFill", "Fill", "How solid the fill of the quest you follow is."),
	Alpha("fEdge", "Edge", "How solid the edge of the quest you follow is."),
	Width("fWidth", "How thick the edge of the quest you follow is."),
})
UI.Feel.Add("advanced", "Other quest areas", {
	Alpha("oFill", "Fill", "How solid the fill of the other quests' areas is."),
	Alpha("oEdge", "Edge", "How solid the edge of the other quests' areas is (a gather area's a little less)."),
	Width("oWidth", "How thick the edge of the other quests' areas is."),
})
UI.Feel.Add("advanced", "Area under the cursor", {
	Alpha("hFill", "Fill lift", "How much an area under the cursor (or its pin) lifts its fill."),
	Alpha("hEdge", "Edge", "How solid the edge of an area under the cursor (or its pin) is."),
})
local STATES = { -- art, level, key; the gather's edge is the quieter 55/85 of the others'
	followed = { art = "blue", level = 2, key = 1 }, kill = { art = "rust", level = 1, key = 2 },
	gather = { art = "green", level = 1, key = 3, quiet = 55 / 85 }, other = { art = "blue", level = 1, key = 4 },
}
local HOVER_WIDTH = 0.8 -- hover's edge as the followed one's default
local NKEYS = 8 -- a map's groups' keys, 1..4 of them (a map's key * NKEYS + its style's)
local STYLES, LIT = {}, nil -- [state]: its style; hover's
local styleRev, feelRev, cur = 0, nil, {}
local function Restyle()
	local F = UI.Feel
	feelRev = F and F.rev
	local v = {}
	for k, d in pairs(DEFAULTS) do
		local x = F and F.Get("areas." .. k)
		if type(x) ~= "number" then x = d end
		v[k] = x
	end
	local function Strong(k) local x = F and F.Get("areas." .. k); return type(x) == "number" and x or 1 end
	local fs, os = Strong("followed"), Strong("others")
	v.fFill, v.fEdge = math.min(255, v.fFill * fs), math.min(255, v.fEdge * fs)
	v.oFill, v.oEdge = math.min(255, v.oFill * os), math.min(255, v.oEdge * os)
	local same = next(cur) ~= nil
	for k, x in pairs(v) do
		if cur[k] ~= x then same = false end
	end
	if same then return end
	cur, styleRev = v, styleRev + 1
	for state, s in pairs(STATES) do
		local f = state == "followed"
		STYLES[state] = { fill = math.floor((f and v.fFill or v.oFill) + 0.5), border = math.floor((f and v.fEdge or v.oEdge) * (s.quiet or 1) + 0.5),
			width = f and v.fWidth or v.oWidth, level = s.level, art = s.art, key = s.key }
	end
	LIT = { fill = v.hFill, border = v.hEdge, width = HOVER_WIDTH, level = 3, art = "blue" }
end
local POINTS = { { "TOPLEFT", "TOP", "TOPRIGHT" }, { "LEFT", "CENTER", "RIGHT" }, { "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" } }

local function On(name) return Engine.LayerOn(name) end

---------------------------------------------------------------------------
-- Blob frames
---------------------------------------------------------------------------

local function MakeBlob(c)
	local f = CreateFrame("QuestPOIFrame", nil, c)
	f:EnableMouse(false) -- the view's: hover is worked out from the cursor
	f.n, f.q, f.drawn = 0, {}, 0 -- f.q[1..n]: its quests' entries; drawn: times since they changed
	return f
end

-- Its art and alpha: true if they changed.
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
	if f.apoint ~= point then f:ClearAllPoints() end -- (one anchor: two would size it)
	if f.az ~= zoom or f.x ~= x or f.y ~= y or f.apoint ~= point or f.on ~= c then At(c, f, point, col, row) end
	f.rect = r
	local w, h = (r.col1 - r.col0) * zoom, (r.row1 - r.row0) * zoom
	if f.w == w and f.h == h then return false end
	f.w, f.h = w, h
	f:SetSize(w, h)
	return true
end

local draws = 0 -- frames drawn (a hit test's answer may change)

-- Its quests drawn into its rect, laid out first.
local function Draw(f)
	f:GetRect() -- (reading it lays it out in the client)
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
-- The layer
---------------------------------------------------------------------------

-- A layout's frames: its groups by key (a map's * NKEYS + its style's), each { map, rect, st, n, entries };
-- the keys its canvas didn't show (set after the rest).
local groups, keys, nkeys = {}, {}, 0
local missed, nmissed = {}, 0

local function Group(e, r)
	local st = STYLES[e.followed and "followed" or e.need or "other"]
	local key = e.areaMap * NKEYS + st.key
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

-- The layer's rev: the game's areas, the layer on, the look (a setting changed: laid out and drawn again).
local function Rev()
	local F = UI.Feel
	if not feelRev or F and F.rev ~= feelRev then Restyle() end
	return select(2, Model.Known("quests")) * 2 + (On("quests") and 1 or 0) + styleRev * 1e9
end

local layer = Engine.Layer("questAreas", LEVEL, function(c, inst, zoom, c0, r0, c1, r1)
	for i = 1, nkeys do
		local g = groups[keys[i]]
		for j = 1, g.n do g[j] = nil end
		g.n = 0
	end
	nkeys, nmissed = 0, 0
	if not On("quests") then return true end
	local any, list = false, Model.Known("quests")
	for _, e in ipairs(list) do
		local r = e.areaMap and Atlas.MapRect(e.areaMap)
		if r and r.inst == inst then
			any = true
			if r.col1 >= c0 and r.col0 <= c1 and r.row1 >= r0 and r.row0 <= r1 then Group(e, r) end
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
	return not any or nil
end, Rev, "hold")
Areas.layer = layer

---------------------------------------------------------------------------
-- Each frame: shown or not, drawn again, hover, tooltip
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

-- Lit: a quest's area under the cursor, or its pin: drawn again on top in its
-- own frame, on the canvas shown, twice.
local hover = {} -- pin, area: the quest under the cursor
local lit, litOn, litEpoch, litSt -- the entry it shows, on which canvas and epoch, in which style
local light -- its frame

local function Light(c)
	local q = hover.pin or hover.area
	local e = c and q and Entry(q)
	local r = e and e.areaMap and Atlas.MapRect(e.areaMap)
	if not (r and r.inst == c.inst) then e = nil end
	local epoch = c and c.epoch
	local st = e and (LIT or Restyle() or LIT)
	if e == lit and c == litOn and epoch == litEpoch and st == litSt then
		if e and light.drawn < 2 then Draw(light) end
		return
	end
	lit, litOn, litEpoch, litSt = e, c, epoch, st
	if not e then
		if light then light:Hide() end
		return
	end
	light = light or MakeBlob(c)
	Place(c, light, r, c.zoom)
	Look(light, st, c:GetFrameLevel() + st.level)
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

-- The quest whose area f draws at tile (col, row), or nil.
local function Hit(f, col, row)
	local r = f.rect
	if col >= r.col0 and col <= r.col1 and row >= r.row0 and row <= r.row1 then
		return f:UpdateMouseOverTooltip((col - r.col0) / (r.col1 - r.col0), -- /: never 0 (a map's rect has a size)
			(row - r.row0) / (r.row1 - r.row0)) -- /: never 0 (a map's rect has a size)
	end
end

-- The quest whose drawn area is under the cursor on c, tested again only when the
-- cursor, the camera, the canvas or a drawing changed.
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
		local q = Hit(p[i], col, row)
		if q then
			a.q = q
			return q
		end
	end
end

-- The quests whose drawn areas hold (col, row) on inst, one a frame: the inspector's
-- (ui/ZoneInfo.lua). A new list.
function Areas.QuestsAt(inst, col, row)
	local out, c = {}, layer.on and layer.front
	local p = c and c.inst == inst and c.pools.blob
	for i = 1, p and p.n or 0 do
		local f = p[i]
		local q = f.drawn > 0 and Hit(f, col, row)
		if q then out[#out + 1] = q end
	end
	return out
end

local owner = CreateFrame("Frame", nil, Window.view) -- an area's tooltip's
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
	-- The cursor in the view's rect, over what stands on it too (a control, another addon's pin), with
	-- IsMouseOver: the area stays lit, its tooltip up but for one shown already (that pin's).
	local mm = Model.minimap
	local q = held and not (mm and mm.blip) and Window.view:IsMouseOver() and Under(held) or nil -- (a blip's tooltip first)
	hover.area = q
	Light(c)
	-- Who has GameTooltip over an area: one shown already (a pin's), else the area's.
	local e, tip = q and Entry(q), GameTooltip
	if e then
		local o = tip:GetOwner()
		if o and o ~= owner and tip:IsShown() then return end
		if (e ~= showing or o ~= owner or not tip:IsShown()) and not UI.Popup.IsOpen() then
			showing = e
			tip:SetOwner(owner, "ANCHOR_CURSOR_RIGHT", 12, 0)
			UI.QuestTooltip.Fill(tip, e)
			tip:Show()
		end
	elseif showing and tip:IsOwned(owner) then
		showing = nil
		tip:Hide()
	end
end, { shownOnly = Window.frame })

-- A quest's pin under the cursor (its layer's hover: ui/Quests.lua), or none: its area lit.
function Areas.Hover(e) hover.pin = e and e.quest end

-- Follow e's quest: the game's super-tracked quest, watched; again to stop.
function Areas.Follow(e) Command({ kind = "follow", quest = not e.followed and e.quest }) end

-- A click on the map no pin took (ui/Window.lua): on a quest's drawn area, follows it, again to stop.
-- True if it was one.
function Areas.Tap()
	local q = shown and Under(shown)
	local e = q and Entry(q)
	if not e then return false end
	Areas.Follow(e)
	return true
end

UI.Menus.Layer({ key = "questAreas", label = "Quest areas", group = "quests",
	tip = "Where each quest's objectives are, as the game draws them." })
