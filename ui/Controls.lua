-- The window's buttons (Core.lua:235-381): on the band, right-aligned on the title's line,
-- the gear (the world map's) and the mode button (its red expand: ui/BigMap.lua); inside
-- the map, top left the tracking pill (yards along the route and an ETA), bottom left the quest
-- pill (the followed quest and its progress, else your quests in this zone), bottom right the
-- zoom buttons and, while the zoom isn't the default, the reset above them. They and the grip fade in while you hover
-- (Core.lua:394-408; away from the map, as faint as Buttons at rest: hidden by default), and each has a tiny tip
-- (Core.lua:1454-1497). Their settings (ui/Feel.lua): General > Map window > Buttons at rest, and the Info pills page
-- (declared at the bottom: the pills' backing, size, what each says and shows, their fades, the distance pill's corner).

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
-- The quest pill's gap from the window's left and bottom borders is one: the border's insets differ, so its
-- bottom offset makes up the difference (BOTTOM_Y), and the zoom buttons drop by as much (clear of the grip).
local insets = Chrome.border.insets
local BOTTOM_Y = math.max(2, PAD + insets[1] - insets[4])
zoomOut:SetPoint("BOTTOMRIGHT", -PAD, BOTTOM_Y + 6)
local zoomIn = ArtButton(Chrome.controls, 20, 20, ZoomArt("ui-hud-minimap-zoom-in"))
zoomIn:SetPoint("BOTTOM", zoomOut, "TOP", 0, 2)
Controls.zoomIn, Controls.zoomOut = zoomIn, zoomOut

-- Reset zoom: above the zoom in (the gap the + and - keep), shown only while the zoom isn't the default (UI.DefaultZoom,
-- ui/View.lua). The client's reset atlas if it has one (Forever has none); else Blizzard's small gold dot
-- (levelup-dot-gold, the level-up toast's; its radio dot after it), the highlight the same, added; else, a client
-- with neither, a gold dot of our own on a dark disc.
local RESET_TOL = 1 -- px per tile: a zoom this close to the default is the default
local resetAtlas = FirstAtlas("ui-hud-minimap-zoom-reset", "ui-hud-minimap-zoom-default")
local dotAtlas = not resetAtlas and FirstAtlas("levelup-dot-gold", "common-radiobutton-dot")
local zoomReset = CreateFrame("Button", nil, Chrome.controls)
zoomReset:SetSize(16, 16)
zoomReset:SetPoint("BOTTOM", zoomIn, "TOP", 0, 2)
if resetAtlas then
	zoomReset:SetNormalAtlas(resetAtlas)
	zoomReset:SetHighlightAtlas(resetAtlas, "ADD")
elseif dotAtlas then
	local dot = zoomReset:CreateTexture(nil, "ARTWORK")
	dot:SetAtlas(dotAtlas)
	dot:SetSize(10, 10)
	dot:SetPoint("CENTER")
	local glow = zoomReset:CreateTexture(nil, "HIGHLIGHT")
	glow:SetAtlas(dotAtlas)
	glow:SetBlendMode("ADD")
	glow:SetAllPoints(dot)
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
-- The quest pill (bottom left): the followed quest and its progress, else how many of your quests
-- are in this zone; on a small dark pill that reads on any map. Worked out from Model's quest list
-- (Known("quests") and its rev: a change to the log) and your zone's map, at most every EVERY s,
-- and only when one of those changed. It fades with the other controls, but stays shown while a quest is tracked;
-- then it is that quest's pin: hovering it shows the quest's tooltip and lights its area, a click (either button)
-- opens its menu (ui/Track.lua: Stop tracking or pathing, the other mode, Open in quest log). Otherwise it takes no mouse.
---------------------------------------------------------------------------

local LINE_H, LINE_PAD = 15, 7
local ICON, ICON_X, ICON_GAP = 12, 7, 4 -- the quest icon: its size, its left, the gap to the text
local ZOOM_COL = 30 -- px at the map's right kept clear of the line: the zoom buttons' column and a gap
local EVERY = 0.5 -- s between looks at the quest list and your zone (two a second at most)
local ELLIPSIS = "\226\128\166" -- "…" in UTF-8

-- On Chrome.overlay, not under the controls: the line shows at full alpha while a quest is tracked,
-- and fades with the controls otherwise (the step below).
local overlay = Chrome.overlay
local line = CreateFrame("Frame", nil, overlay)
line:SetPoint("BOTTOMLEFT", PAD, BOTTOM_Y)
line:SetHeight(LINE_H)
line:Hide()
local tracked = false -- the line shows the followed quest
local followedQuest -- its Known entry, while it does
local hover = 1 -- the controls' fade (the step below)

-- The quest's icon: the quest log tab's, filled (the client has no outline of it to pair with); not
-- tracked, it is dimmed.
local questAtlas = FirstAtlas("questlog-tab-icon-quest", "QuestNormal")
local icon = line:CreateTexture(nil, "ARTWORK")
icon:SetSize(ICON, ICON)
icon:SetPoint("LEFT", line, "LEFT", ICON_X, 0)
if questAtlas then icon:SetAtlas(questAtlas) else icon:Hide() end
-- The pill: a half disc at each end (the circle mask's halves, so they don't overlap the middle).
local PILL_A = 0.25 -- the backing's alpha: faint ("pills.alpha" sets it live: SetPillAlpha)
local pills = {} -- every pill's backing textures (caps and middle)
local function Backing(f)
	local function Cap(left)
		local t = f:CreateTexture(nil, "BACKGROUND")
		t:SetTexture(Chrome.CIRCLE)
		t:SetVertexColor(0, 0, 0, PILL_A)
		t.cap = true
		pills[#pills + 1] = t
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
	local middle = f:CreateTexture(nil, "BACKGROUND")
	middle:SetColorTexture(0, 0, 0, PILL_A)
	middle:SetPoint("TOPLEFT", f, "TOPLEFT", LINE_H / 2, 0)
	middle:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -LINE_H / 2, 0)
	pills[#pills + 1] = middle
end
-- The pills' backing alpha (a cap takes it through its vertex colour, the middle as its colour).
local function SetPillAlpha(a)
	for _, t in ipairs(pills) do
		if t.cap then t:SetVertexColor(0, 0, 0, a) else t:SetColorTexture(0, 0, 0, a) end
	end
end
Backing(line)

-- The pills' look and behaviour (the Info pills page, through SetPill; these its defaults): their size, what each
-- says, whether each shows, fades until you point at the map, and the tracking pill's corner.
local PILL = { scale = 1, questShow = "all", questProgress = true, questFade = true, trackShow = true,
	trackWhat = "both", trackCorner = "left", trackFade = false }
local lineText = line:CreateFontString(nil, "OVERLAY")
lineText:SetFont(FONT, 10, "")
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

-- What the line says, as pre (kept), head (cut first when long) and tail (kept), and the followed quest's
-- entry if it is that (else false); nil for nothing: the followed quest first, else your quests in your zone.
local function Words(list, here)
	local followed
	for _, e in ipairs(list) do
		if e.followed then
			followed = e
			break
		end
	end
	if PILL.questShow == "off" then return nil end
	if followed then
		if not PILL.questProgress then return "", followed.name, "", followed end
		if followed.complete then return "", followed.name, "  ready to turn in", followed end
		local have, need = Progress(followed)
		if need > 0 then return "", followed.name, "  " .. have .. "/" .. need, followed end
		return "", followed.name, "", followed
	end
	if not here or PILL.questShow == "followed" then return nil end
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
	followedQuest = followed or nil
	line:EnableMouse(followedQuest ~= nil)
	if not pre then
		tracked = false
		line:Hide()
		return
	end
	tracked = followed ~= false
	-- Capped so the line never reaches the zoom buttons (the map's width less the zoom column).
	local textX = questAtlas and ICON_X + ICON + ICON_GAP or LINE_PAD
	-- In the pill's own units (SetScale).
	local w = overlay:GetWidth() / PILL.scale -- /: never 0 (the scale's least is 0.8)
	local avail = w > 0 and w - (2 * PAD + ZOOM_COL) / PILL.scale - textX - LINE_PAD or math.huge -- /: never 0 (as above)
	lineText:SetPoint("LEFT", line, "LEFT", textX, 0)
	lineText:SetText(Fit(pre, head, tail, avail))
	line:SetWidth(textX + lineText:GetStringWidth() + LINE_PAD)
	icon:SetDesaturated(not followed)
	icon:SetAlpha(followed and 1 or 0.6)
	line:SetAlpha((followed or not PILL.questFade) and 1 or hover)
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

-- The followed quest's pin, in the pill: its tooltip and area under the cursor, its menu on a click.
line:SetScript("OnEnter", Runtime.Wrap("map: quest pill", function()
	local e = followedQuest
	if not e then return end
	UI.Areas.Hover(e)
	GameTooltip:SetOwner(line, "ANCHOR_TOPRIGHT")
	UI.QuestTooltip.Show(e)
end))
line:SetScript("OnLeave", Runtime.Wrap("map: quest pill", function()
	UI.Areas.Hover(nil)
	if GameTooltip:IsOwned(line) then GameTooltip:Hide() end
end))
line:SetScript("OnMouseUp", Runtime.Wrap("map: quest pill", function()
	local e = followedQuest
	if not e then return end
	if GameTooltip:IsOwned(line) then GameTooltip:Hide() end
	UI.Track.Menu(line, e)
end, Runtime.FRAME_MS))

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
-- The tracking pill (top left of the map): what's tracked on this map, by how far (the yards along the
-- way, Model.Route(), else straight: UI.You.Target) and a plain ETA at your pace: now if you're moving, else
-- the last pace you were seen at, else a run's (RUN). Gone with nothing tracked, or once you're inside its
-- area. Looked at TRACK_EVERY s, its text set only when it changes (yards to 10 from 100 up, minutes whole).
---------------------------------------------------------------------------

local RUN = 7 -- yd/s, a run
local TRACK_EVERY = 0.3 -- s: three or so a second
local YARDS_STEP = 10 -- yards are rounded to this from 100 up: no flicker while you walk
local track = CreateFrame("Frame", nil, overlay)
track:SetPoint("TOPLEFT", PAD, -PAD)
track:SetHeight(LINE_H)
track:Hide()
Backing(track)
local trackText = track:CreateFontString(nil, "OVERLAY")
trackText:SetFont(FONT, 10, "")
trackText:SetTextColor(0.95, 0.9, 0.8)
trackText:SetPoint("LEFT", track, "LEFT", LINE_H / 2, 0)
Controls.trackLine = track

local pace = RUN -- the last non-zero speed seen
local trackShown, trackWords = false, nil
local function Track()
	local speed = Model.you.speed
	if speed and speed > 0 then pace = speed end
	local _, yd = UI.You.Target()
	if not yd or not PILL.trackShow then -- nothing tracked here (nil), or inside its area (false)
		if trackShown then
			trackShown = false
			track:Hide()
		end
		return
	end
	local way = Model.Route()
	if way and #way > 1 then -- the length along the way: tiles to yards
		local d = 0
		for i = 1, #way - 1 do
			local a, b = way[i], way[i + 1]
			d = d + math.sqrt((b.col - a.col) ^ 2 + (b.row - a.row) ^ 2)
		end
		yd = math.floor(d * Atlas.TILE_YARDS + 0.5)
	end
	if yd >= 100 then yd = math.floor(yd / YARDS_STEP + 0.5) * YARDS_STEP end
	local secs = yd / pace -- /: never 0 (pace starts at RUN and only takes speeds above 0)
	local eta
	if secs < 60 then
		eta = "<1 min"
	elseif secs < 5400 then
		eta = string.format("%d min", math.floor(secs / 60 + 0.5))
	else
		eta = string.format("%d h", math.floor(secs / 3600 + 0.5))
	end
	local words = string.format("%d yd  \194\183  %s", yd, eta)
	if PILL.trackWhat == "yards" then
		words = string.format("%d yd", yd)
	elseif PILL.trackWhat == "time" then
		words = eta
	end
	if words ~= trackWords then
		trackWords = words
		trackText:SetText(words)
		track:SetWidth(trackText:GetStringWidth() + LINE_H)
	end
	if not trackShown then
		trackShown = true
		track:Show()
	end
end

-- The tracking pill's corner and both pills' size (SetScale: its offsets are in its own units, so divided by it).
local function Place()
	local sc = PILL.scale
	line:SetScale(sc)
	line:ClearAllPoints()
	line:SetPoint("BOTTOMLEFT", PAD / sc, BOTTOM_Y / sc) -- /: never 0 (the scale's least is 0.8)
	track:SetScale(sc)
	track:ClearAllPoints()
	if PILL.trackCorner == "right" then
		track:SetPoint("TOPRIGHT", -PAD / sc, -PAD / sc) -- /: never 0 (as above)
	else
		track:SetPoint("TOPLEFT", PAD / sc, -PAD / sc) -- /: never 0 (as above)
	end
end

-- The buttons' and the pills' alphas from the hover's fade: the buttons from Buttons at rest (away) to 1 (over).
local rest = 0
local function Reveal()
	local a = rest + (1 - rest) * hover
	Chrome.controls:SetAlpha(a)
	gear:SetAlpha(a)
	mode:SetAlpha(a)
	Chrome.grip:SetAlpha(GRIP_ALPHA * a)
	line:SetAlpha((tracked or not PILL.questFade) and 1 or hover)
	track:SetAlpha(PILL.trackFade and hover or 1)
end

-- One of PILL's settings: applied at once, both pills worked out again.
local function SetPill(key, v)
	if PILL[key] == v then return end
	PILL[key] = v
	Place()
	lastRev, trackWords = nil, nil
	Look()
	Track()
	Reveal()
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

-- Following you, or free: the slash command (and the Settings row: ui/Motion.lua). Back to you with a
-- glide (Core.lua:1081-1093, 1451, 1703).
local function ToggleFollow() UI.Motion.SetFollow(not Camera.follow, true) end

---------------------------------------------------------------------------
-- Hover reveal: the controls and grip fade in while the mouse is over the map
---------------------------------------------------------------------------

-- One step for the map's controls: the fade (the quest pill's too, unless it shows a tracked quest), the
-- zoom reset's look (each frame: a cheap compare), and the pills' (EVERY s: a step's probes cost
-- each frame, so these share one).
local since, trackSince = EVERY, TRACK_EVERY
Runtime.Step("ui", "map: controls", function(elapsed)
	local want = (Window.frame:IsMouseOver(REACH, -REACH, 0, 0) or Menus.IsOpen()) and 1 or 0
	if hover ~= want then
		local step = elapsed / FADE
		hover = want > hover and math.min(want, hover + step) or math.max(want, hover - step)
		Reveal()
	end
	ResetLook()
	if UI.Cluster then UI.Cluster.Watch() end
	since = since + elapsed
	if since >= EVERY then
		since = 0
		Look()
	end
	trackSince = trackSince + elapsed
	if trackSince >= TRACK_EVERY then
		trackSince = 0
		Track()
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

---------------------------------------------------------------------------
-- Settings (ui/Feel.lua): General > Map window, and the Info pills page
---------------------------------------------------------------------------

UI.Feel.Add("general", "Map window", {
	{ key = "controls.rest", kind = "slider", label = "Buttons at rest", min = 0, max = 1, step = 0.05, pct = true, default = rest,
		apply = function(v) rest = v; Reveal() end,
		tip = "How much the map's buttons (gear, zoom, grow) and its resize grip show while you're not pointing at the map. 0%: hidden till you do." },
})
local function Pill(key) return function(v) SetPill(key, v) end end
local function QuestPill() return UI.Feel.Get("pills.questShow") ~= "off" end
UI.Feel.Add("pills", "Both pills", {
	{ key = "pills.alpha", kind = "slider", label = "Backing", min = 0, max = 0.8, step = 0.05, pct = true, default = PILL_A,
		apply = SetPillAlpha, tip = "How dark the pills' backing is: the quest pill (bottom left) and the distance pill (top)." },
	{ key = "pills.scale", kind = "slider", label = "Size", min = 0.8, max = 1.6, step = 0.1, pct = true, default = PILL.scale,
		apply = Pill("scale"), tip = "Both pills' size, text and all." },
})
UI.Feel.Add("pills", "Quest pill", {
	{ key = "pills.questShow", kind = "select", label = "Shows", default = PILL.questShow, apply = Pill("questShow"),
		options = { { "Quest or zone count", "all" }, { "Followed quest only", "followed" }, { "Off", "off" } },
		tip = "Bottom left: the quest you follow, else how many of your quests are in this zone; or only a followed quest; or none." },
	{ key = "pills.questProgress", kind = "toggle", label = "Quest progress", default = PILL.questProgress, when = QuestPill,
		apply = Pill("questProgress"), tip = "The followed quest's count (2/5) or \"ready to turn in\" after its name." },
	{ key = "pills.questFade", kind = "toggle", label = "Fade quest pill", default = PILL.questFade, when = QuestPill,
		apply = Pill("questFade"), tip = "The zone's quest count shows only while you point at the map. A followed quest always shows." },
})
UI.Feel.Add("pills", "Distance pill", {
	{ key = "pills.trackShow", kind = "toggle", label = "Distance pill", default = PILL.trackShow, apply = Pill("trackShow"),
		tip = "The yards and time to what you track (a quest, an icon, your waypoint)." },
	{ key = "pills.trackWhat", kind = "select", label = "Shows", default = PILL.trackWhat, when = "pills.trackShow",
		options = { { "Yards and time", "both" }, { "Yards", "yards" }, { "Time", "time" } }, apply = Pill("trackWhat"),
		tip = "What the distance pill says. The time is at your pace (a run's, until you've moved)." },
	{ key = "pills.trackCorner", kind = "select", label = "Corner", default = PILL.trackCorner, when = "pills.trackShow",
		options = { { "Top left", "left" }, { "Top right", "right" } }, apply = Pill("trackCorner"),
		tip = "Which top corner of the map the distance pill sits in." },
	{ key = "pills.trackFade", kind = "toggle", label = "Fade distance pill", default = PILL.trackFade, when = "pills.trackShow",
		apply = Pill("trackFade"), tip = "The distance pill shows only while you point at the map." },
})
