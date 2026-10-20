-- The window's buttons (Core.lua:235-381): on the band, right-aligned on the title's line,
-- the gear (the world map's) and the mode button (its red expand: ui/BigMap.lua); inside
-- the map, bottom left the quest line (the followed quest and its progress, else your quests in
-- this zone), bottom right the zoom buttons and, while the zoom isn't the default, the reset
-- above them. They and the grip fade in while you hover (Core.lua:394-408), and each has a
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

-- Reset zoom: above the zoom in (the gap the + and - keep), shown only while the zoom isn't the default (UI.DefaultZoom,
-- ui/View.lua). An atlas if the client has one of these names; else a dark disc with a gold dot,
-- the highlight a glow as the zoom buttons' (no client here to check the atlas names against).
local RESET_TOL = 1 -- px per tile: a zoom this close to the default is the default
local resetAtlas = FirstAtlas("ui-hud-minimap-zoom-reset", "ui-hud-minimap-zoom-default")
local zoomReset = CreateFrame("Button", nil, Chrome.controls)
zoomReset:SetSize(16, 16)
zoomReset:SetPoint("BOTTOM", zoomIn, "TOP", 0, 2)
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
-- and only when one of those changed. It fades with the other controls, but stays shown while a quest is tracked.
---------------------------------------------------------------------------

local LINE_H, LINE_PAD = 18, 8
local ICON, ICON_X, ICON_GAP = 14, 8, 5 -- the quest icon: its size, its left, the gap to the text
local ZOOM_COL = 30 -- px at the map's right kept clear of the line: the zoom buttons' column and a gap
local EVERY = 0.5 -- s between looks at the quest list and your zone (two a second at most)
local ELLIPSIS = "\226\128\166" -- "…" in UTF-8

-- On Chrome.overlay, not under the controls: the line shows at full alpha while a quest is tracked,
-- and fades with the controls otherwise (the step below).
local overlay = Chrome.overlay
local line = CreateFrame("Frame", nil, overlay)
line:SetPoint("BOTTOMLEFT", PAD, PAD)
line:SetHeight(LINE_H)
line:Hide()
local tracked = false -- the line shows the followed quest
local hover = 1 -- the controls' fade (the step below)

-- The quest's icon: the quest log tab's, filled (the client has no outline of it to pair with); not
-- tracked, it is dimmed.
local questAtlas = FirstAtlas("questlog-tab-icon-quest", "QuestNormal")
local icon = line:CreateTexture(nil, "ARTWORK")
icon:SetSize(ICON, ICON)
icon:SetPoint("LEFT", line, "LEFT", ICON_X, 0)
if questAtlas then icon:SetAtlas(questAtlas) else icon:Hide() end
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

-- A quest pin's zone map (false: none), kept per pin table: the list is rebuilt often, its pins rarely.
local pinZones = setmetatable({}, { __mode = "k" })
local function PinZone(p)
	if not p then return false end
	local z = pinZones[p]
	if z == nil then
		local zone = Atlas.ZoneAt(p.inst, p.col, p.row)
		z = zone and zone.mapID or false
		pinZones[p] = z
	end
	return z
end

-- What the line says, as pre (kept), head (cut first when long) and tail (kept), and whether it is the
-- followed quest; nil for nothing: the followed quest first, else your quests in your zone.
local function Words(list, here)
	local followed
	for _, e in ipairs(list) do
		if e.followed then
			followed = e
			break
		end
	end
	if followed then
		if followed.complete then return "", followed.name, "  ready to turn in", true end
		local have, need = Progress(followed)
		if need > 0 then return "", followed.name, "  " .. have .. "/" .. need, true end
		return "", followed.name, "", true
	end
	if not here then return nil end
	local n = 0
	for _, e in ipairs(list) do
		if PinZone(e.pos) == here.mapID then n = n + 1 end
	end
	if n == 0 then return nil end
	return string.format("%d %s in ", n, n == 1 and "quest" or "quests"), here.name, "", false
end

-- The byte count of the first i bytes of s, backed off to a UTF-8 character's start.
local function Cut(s, i)
	local b = s:byte(i + 1)
	while i > 0 and b and b >= 0x80 and b < 0xC0 do
		i = i - 1
		b = s:byte(i + 1)
	end
	return i
end

-- pre .. head .. tail in the line's text, the head cut with an ellipsis until it is at most avail px.
local function Fit(pre, head, tail, avail)
	lineText:SetText(pre .. head .. tail)
	if lineText:GetStringWidth() <= avail then return pre .. head .. tail end
	local lo, hi = 0, #head
	while lo < hi do
		local mid = math.floor((lo + hi + 1) / 2)
		lineText:SetText(pre .. head:sub(1, Cut(head, mid)) .. ELLIPSIS .. tail)
		if lineText:GetStringWidth() <= avail then lo = mid else hi = mid - 1 end
	end
	return pre .. head:sub(1, Cut(head, lo)) .. ELLIPSIS .. tail
end

local function Show(pre, head, tail, followed)
	if not pre then
		tracked = false
		line:Hide()
		return
	end
	tracked = followed
	-- Capped so the line never reaches the zoom buttons (the map's width less the zoom column).
	local textX = questAtlas and ICON_X + ICON + ICON_GAP or LINE_PAD
	local w = overlay:GetWidth()
	local avail = w > 0 and w - 2 * PAD - ZOOM_COL - textX - LINE_PAD or math.huge
	lineText:SetPoint("LEFT", line, "LEFT", textX, 0)
	lineText:SetText(Fit(pre, head, tail, avail))
	line:SetWidth(textX + lineText:GetStringWidth() + LINE_PAD)
	icon:SetDesaturated(not followed)
	icon:SetAlpha(followed and 1 or 0.6)
	line:SetAlpha(followed and 1 or hover)
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

local lastRev, lastZone, lastW -- what the line was last worked out from (the map's width too: its cap)
local function Look()
	local list, rev = Model.Known("quests")
	local zone = YourZone()
	local key = zone and zone.mapID or false
	local w = overlay:GetWidth()
	if rev == lastRev and key == lastZone and w == lastW then return end
	lastRev, lastZone, lastW = rev, key, w
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

-- One step for the map's controls: the fade (the quest line's too, unless it shows a tracked quest), the
-- zoom reset's look (each frame: a cheap compare), and the quest line's (EVERY s: a step's probes cost
-- each frame, so these share one).
local since = EVERY
Runtime.Step("ui", "map: controls", function(elapsed)
	local want = (Window.frame:IsMouseOver(REACH, -REACH, 0, 0) or Menus.IsOpen()) and 1 or 0
	if hover ~= want then
		local step = elapsed / FADE
		hover = want > hover and math.min(want, hover + step) or math.max(want, hover - step)
		Chrome.controls:SetAlpha(hover)
		gear:SetAlpha(hover)
		mode:SetAlpha(hover)
		Chrome.grip:SetAlpha(GRIP_ALPHA * hover)
		line:SetAlpha(tracked and 1 or hover)
	end
	ResetLook()
	if UI.Cluster then UI.Cluster.Watch() end
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
