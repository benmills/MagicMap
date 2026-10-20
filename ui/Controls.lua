-- The window's buttons (Core.lua:235-381): on the band, right-aligned on the title's line,
-- the gear (the world map's) and the mode button (its red expand: ui/BigMap.lua); inside
-- the map, bottom left the quest line (the followed quest and its progress, else your quests in
-- this zone), bottom right the zoom buttons and, while the zoom isn't the default, the reset
-- beside them. They and the grip fade in while you hover (Core.lua:394-408), and each has a
-- tiny tip (Core.lua:1454-1497). Follow is a Settings row now (ui/Menus.lua).

local _, ns = ...
local UI = ns.UI
local Atlas, Model, Runtime = ns.Atlas, ns.Model, ns.Runtime
local Camera, Window, Chrome, Menus = UI.Camera, UI.Window, UI.Chrome, UI.Menus

local HEADER_ICON = 20 -- Core.lua:281
local PAD = 12 -- from the map's edges (Core.lua:341)
local FADE = 0.15 -- s, hover reveal (Core.lua:402)
local REACH = HEADER_ICON + 12 -- the title's line counts as over the map (Core.lua:399)
local GRIP_ALPHA = 0.8 -- Core.lua:320
local TIP_DELAY, TIP_LIFE, TIP_FADE = 0.35, 2.5, 0.12 -- s (Core.lua:1457)
local FONT = GameFontNormal:GetFont()

local Controls = {}
UI.Controls = Controls

-- The first of these atlases the client has, if any.
local function FirstAtlas(...)
	for i = 1, select("#", ...) do
		local name = select(i, ...)
		if C_Texture.GetAtlasInfo(name) then return name end
	end
end

-- A button from art = { atlas = {names...}, pushed = {...}, highlight = {...} } (the first each
-- client has), else from file = path with optional coords / pushedCoords into it (Core.lua:249-276):
-- a client without the atlas gets a blank button, as the spike's.
local function ArtButton(parent, w, h, art)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w, h)
	local atlas = art.atlas and FirstAtlas(unpack(art.atlas))
	if atlas then
		b:SetNormalAtlas(atlas)
		local pushed = art.pushed and FirstAtlas(unpack(art.pushed))
		if pushed then b:SetPushedAtlas(pushed) end
		b:SetHighlightAtlas(art.highlight and FirstAtlas(unpack(art.highlight)) or atlas, "ADD")
	else
		b:SetNormalTexture(art.file)
		b:SetPushedTexture(art.file)
		b:SetHighlightTexture(art.file, "ADD")
		if art.coords then -- Core.lua:263
			b:GetNormalTexture():SetTexCoord(unpack(art.coords))
			b:GetHighlightTexture():SetTexCoord(unpack(art.coords))
			b:GetPushedTexture():SetTexCoord(unpack(art.pushedCoords or art.coords))
		end
	end
	return b
end

local function ZoomArt(name)
	return { atlas = { name }, pushed = { name .. "-down" }, highlight = { name .. "-mouseover" } }
end

-- The band's: placed by the title (ui/Title.lua: above the map, or below at the screen's top).
-- The mode button's chains are the spike's (Core.lua:282-286); Forever draws the second of each,
-- as the spike did there: its `-c60` names are art variants of the element, not atlas names (ui/Art.lua).
local mode = ArtButton(Chrome.band, HEADER_ICON, HEADER_ICON, {
	atlas = { "redbutton-expand-c60", "redbutton-expand" },
	pushed = { "redbutton-expand-pressed-c60", "redbutton-expand-pressed" },
	highlight = { "redbutton-highlight-c60", "redbutton-highlight" },
})
local gear = ArtButton(Chrome.band, HEADER_ICON + 4, HEADER_ICON + 4, {
	file = "Interface\\WorldMap\\Gear_64", coords = { 0, 0.5, 0, 0.5 }, pushedCoords = { 0, 0.5, 0.5, 1 },
})
gear:SetPoint("RIGHT", mode, "LEFT", -6, 0)
Controls.mode, Controls.gear = mode, gear

local zoomOut = ArtButton(Chrome.controls, 20, 11, ZoomArt("ui-hud-minimap-zoom-out"))
zoomOut:SetPoint("BOTTOMRIGHT", -PAD, PAD + 6) -- clear of the grip
local zoomIn = ArtButton(Chrome.controls, 20, 20, ZoomArt("ui-hud-minimap-zoom-in"))
zoomIn:SetPoint("BOTTOM", zoomOut, "TOP", 0, 2)
Controls.zoomIn, Controls.zoomOut = zoomIn, zoomOut

-- Reset zoom: beside the zoom in, shown only while the zoom isn't the default (UI.DefaultZoom,
-- ui/View.lua). An atlas if the client has one of these names; else a dark disc with a gold dot,
-- the highlight a glow as the zoom buttons' (no client here to check the atlas names against).
local RESET_TOL = 1 -- px per tile: a zoom this close to the default is the default
local resetAtlas = FirstAtlas("ui-hud-minimap-zoom-reset", "ui-hud-minimap-zoom-default")
local zoomReset = CreateFrame("Button", nil, Chrome.controls)
zoomReset:SetSize(16, 16)
zoomReset:SetPoint("RIGHT", zoomIn, "LEFT", -4, 0)
if resetAtlas then
	zoomReset:SetNormalAtlas(resetAtlas)
	zoomReset:SetHighlightAtlas(resetAtlas, "ADD")
else
	local disc = zoomReset:CreateTexture(nil, "BACKGROUND")
	disc:SetTexture(Chrome.CIRCLE)
	disc:SetVertexColor(0, 0, 0, 0.65)
	disc:SetAllPoints()
	local dot = zoomReset:CreateTexture(nil, "ARTWORK")
	dot:SetTexture(Chrome.CIRCLE)
	dot:SetVertexColor(1, 0.82, 0.3, 0.9)
	dot:SetSize(6, 6)
	dot:SetPoint("CENTER")
	local glow = zoomReset:CreateTexture(nil, "HIGHLIGHT")
	glow:SetTexture(Chrome.CIRCLE)
	glow:SetVertexColor(1, 1, 1, 0.15)
	glow:SetAllPoints(disc)
end
zoomReset:Hide()
Controls.zoomReset = zoomReset

---------------------------------------------------------------------------
-- The quest line (bottom left): the followed quest and its progress, else how many of your quests
-- are in this zone; on a small dark pill that reads on any map. Worked out from Model's quest list
-- (Known("quests") and its rev: a change to the log) and your zone's map, at most every EVERY s,
-- and only when one of those changed. Inside Chrome.controls: it fades with the other controls.
---------------------------------------------------------------------------

local LINE_H, LINE_PAD = 18, 8
local EVERY = 0.5 -- s between looks at the quest list and your zone (two a second at most)

local line = CreateFrame("Frame", nil, Chrome.controls)
line:SetPoint("BOTTOMLEFT", PAD, PAD)
line:SetHeight(LINE_H)
line:Hide()
-- The pill: a half disc at each end (the circle mask's halves, so they don't overlap the middle).
local function Cap(left)
	local t = line:CreateTexture(nil, "BACKGROUND")
	t:SetTexture(Chrome.CIRCLE)
	t:SetVertexColor(0, 0, 0, 0.65)
	t:SetSize(LINE_H / 2, LINE_H)
	if left then
		t:SetTexCoord(0, 0.5, 0, 1)
		t:SetPoint("TOPLEFT")
	else
		t:SetTexCoord(0.5, 1, 0, 1)
		t:SetPoint("TOPRIGHT")
	end
end
Cap(true)
Cap(false)
local middle = line:CreateTexture(nil, "BACKGROUND")
middle:SetColorTexture(0, 0, 0, 0.65)
middle:SetPoint("TOPLEFT", line, "TOPLEFT", LINE_H / 2, 0)
middle:SetPoint("BOTTOMRIGHT", line, "BOTTOMRIGHT", -LINE_H / 2, 0)
local lineText = line:CreateFontString(nil, "OVERLAY")
lineText:SetFont(FONT, 11, "")
lineText:SetTextColor(0.95, 0.9, 0.8)
lineText:SetPoint("CENTER")
Controls.questLine = line

local NONE = {}

-- A quest's progress: its counted objectives summed ("2/5" across them), else the finished ones of all
-- (have, need; need 0: none to count). Model's objectives carry have and need (model/Quests.lua).
local function Progress(e)
	local have, need, counted, done = 0, 0, false, 0
	for _, o in ipairs(e.objectives or NONE) do
		if o.finished then done = done + 1 end
		if o.need and o.need > 1 and o.type ~= "progressbar" then
			counted = true
			have, need = have + math.min(o.have or 0, o.need), need + o.need
		end
	end
	if counted then return have, need end
	return done, #(e.objectives or NONE)
end

-- What the line says, or nil for nothing: the followed quest first, else your quests in your zone.
local function Words(list, here)
	local followed
	for _, e in ipairs(list) do
		if e.followed then
			followed = e
			break
		end
	end
	if followed then
		if followed.complete then return followed.name .. "  ready to turn in" end
		local have, need = Progress(followed)
		if need > 0 then return followed.name .. "  " .. have .. "/" .. need end
		return followed.name
	end
	if not here then return nil end
	local n = 0
	for _, e in ipairs(list) do
		local p = e.pos
		local z = p and Atlas.ZoneAt(p.inst, p.col, p.row)
		if z and z.mapID == here.mapID then n = n + 1 end
	end
	if n == 0 then return nil end
	return string.format("%d %s in %s", n, n == 1 and "quest" or "quests", here.name)
end

local function Show(words)
	if not words then
		line:Hide()
		return
	end
	lineText:SetText(words)
	line:SetWidth(lineText:GetStringWidth() + 2 * LINE_PAD)
	line:Show()
end

-- Your zone (the Atlas zone at you): worked out again only when your area (a chunk's id) changes.
local areaId, areaInst, here -- the last area seen, its map, and its zone (nil: none)
local function YourZone()
	local you = Model.you
	if not (you.inst and you.col and not you.stale) then return nil end
	local id = Atlas.AreaAt(you.inst, you.col, you.row)
	if id ~= areaId or you.inst ~= areaInst then
		areaId, areaInst = id, you.inst
		here = id and Atlas.ZoneAt(you.inst, you.col, you.row) or nil
	end
	return here
end

local lastRev, lastZone -- what the line was last worked out from
local function Look()
	local list, rev = Model.Known("quests")
	local zone = YourZone()
	local key = zone and zone.mapID or false
	if rev == lastRev and key == lastZone then return end
	lastRev, lastZone = rev, key
	Show(Words(list, zone))
end

---------------------------------------------------------------------------
-- Zoom reset: the button shows while the zoom is off the default; a click glides back to it
-- (Motion.ZoomTo: the zoom buttons' own chase)
---------------------------------------------------------------------------

local resetShown = false
local function ResetLook()
	local off = math.abs(Camera.cam.zoom - UI.DefaultZoom) > RESET_TOL
	if off ~= resetShown then
		resetShown = off
		zoomReset:SetShown(off)
	end
end

zoomReset:SetScript("OnClick", Runtime.Wrap("map: zoom reset", function() UI.Motion.ZoomTo(UI.DefaultZoom) end))

-- The buttons zoom held on you while following, else on the view's centre (Core.lua:1420-1443).
zoomIn:SetScript("OnClick", Runtime.Wrap("map: zoom in", function() UI.Motion.ZoomStep(1) end))
zoomOut:SetScript("OnClick", Runtime.Wrap("map: zoom out", function() UI.Motion.ZoomStep(-1) end))
-- (The gear's click builds the client's own menu, MenuUtil: ~3 ms in the client, once a click, the frame's
-- budget.)
gear:SetScript("OnClick", Runtime.Wrap("map: gear", function(self) Menus.Gear(self) end, Runtime.FRAME_MS))

-- Following you, or free: the slash command (and the Settings row, ui/Menus.lua). Back to you with a
-- glide (Core.lua:1081-1093, 1451, 1703).
local function ToggleFollow() UI.Motion.SetFollow(not Camera.follow, true) end

---------------------------------------------------------------------------
-- Hover reveal: the controls and grip fade in while the mouse is over the map
---------------------------------------------------------------------------

-- One step for the map's controls: the fade, the zoom reset's look (each frame: a cheap compare), and
-- the quest line's (EVERY s: a step's probes cost each frame, so these share one).
local hover, since = 1, EVERY
Runtime.Step("ui", "map: controls", function(elapsed)
	local want = (Window.frame:IsMouseOver(REACH, -REACH, 0, 0) or Menus.IsOpen()) and 1 or 0
	if hover ~= want then
		local step = elapsed / FADE
		hover = want > hover and math.min(want, hover + step) or math.max(want, hover - step)
		Chrome.controls:SetAlpha(hover)
		gear:SetAlpha(hover)
		mode:SetAlpha(hover)
		Chrome.grip:SetAlpha(GRIP_ALPHA * hover)
	end
	ResetLook()
	since = since + elapsed
	if since >= EVERY then
		since = 0
		Look()
	end
end, { shownOnly = Window.frame })

---------------------------------------------------------------------------
-- Tips: a word or two in small type just above a button, after a moment's hover, gone when
-- you leave, click, open a menu, or after a couple of seconds anyway
---------------------------------------------------------------------------

local tip = CreateFrame("Frame", nil, UIParent)
tip:SetFrameStrata("TOOLTIP")
tip:Hide()
local plate = tip:CreateTexture(nil, "BACKGROUND")
plate:SetAllPoints()
plate:SetColorTexture(0, 0, 0, 0.6)
local text = tip:CreateFontString(nil, "OVERLAY")
text:SetFont(FONT, 11, "")
text:SetTextColor(0.95, 0.9, 0.8)
text:SetPoint("CENTER")
Controls.tip, Controls.tipText = tip, text

Runtime.Step("ui", "map: tip", function(elapsed)
	tip.t = tip.t + elapsed
	if tip.t > TIP_DELAY + TIP_LIFE or Menus.IsOpen() or not tip.owner:IsMouseOver() then
		tip:Hide()
		return
	end
	if tip.t >= TIP_DELAY then
		if not tip.placed then
			tip.placed = true
			text:SetText(tip.fn())
			tip:SetSize(text:GetStringWidth() + 10, text:GetStringHeight() + 6)
			tip:ClearAllPoints()
			tip:SetPoint("BOTTOM", tip.owner, "TOP", 0, 3)
		end
		tip:SetAlpha(math.min(1, (tip.t - TIP_DELAY) / TIP_FADE))
	end
end, { shownOnly = tip })

local Hide = Runtime.Wrap("map: tip hide", function() tip:Hide() end)

function Controls.Tip(button, fn)
	button:HookScript("OnEnter", Runtime.Wrap("map: tip show", function(self)
		tip.owner, tip.fn, tip.t, tip.placed = self, fn, 0, false
		tip:SetAlpha(0)
		tip:Show()
	end))
	button:HookScript("OnLeave", Hide)
	button:HookScript("OnMouseDown", Hide)
end
Controls.Tip(zoomIn, function() return "Zoom in" end)
Controls.Tip(zoomOut, function() return "Zoom out" end)
Controls.Tip(zoomReset, function() return "Reset zoom" end)
Controls.Tip(gear, function() return "Layers & settings" end)

ns.Game.Command({ kind = "slash", name = "follow", help = "follow you on the map, or stop",
	fn = ToggleFollow })
