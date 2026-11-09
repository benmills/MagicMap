-- The window's buttons (Core.lua:235-381): on the band, right-aligned on the title's line,
-- the gear (the world map's) and the mode button (its red expand, and on the big map its condense: ui/BigMap.lua);
-- inside the map, bottom left the quest pill (what you track: its name, progress, yards and time to it over a faint
-- fill of how far you've come; else your quests in this zone), bottom right the zoom buttons, above them the
-- reset while the map is off its default (not following you, or not at the default zoom). They and
-- the grip fade in while you hover (Core.lua:394-408; away from the map, as faint as Buttons at rest: hidden by
-- default), and each has a tip, its name (Core.lua:1454-1497). Their settings (ui/Feel.lua): General > Map window >
-- Buttons at rest, and the Quest pill page (declared at the bottom: what it shows and says, its fill, its fade, its
-- backing and size).

local _, ns = ...
local UI = ns.UI
local Atlas, Model, Runtime = ns.Atlas, ns.Model, ns.Runtime
local Camera, Window, Chrome, Menus = UI.Camera, UI.Window, UI.Chrome, UI.Menus

local HEADER_ICON = 20 -- Core.lua:281
local PAD = 12 -- from the map's edges (Core.lua:341)
local FADE = 0.15 -- s, hover reveal (Core.lua:402)
local REACH = HEADER_ICON + 12 -- the title's line counts as over the map (Core.lua:399)
local GRIP_ALPHA = 0.8 -- Core.lua:320
local TIP_DELAY = 0.35 -- s (Core.lua:1457)
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

-- Reset: above the zoom in (the gap the + and - keep), shown only while the map is off its default: not following you,
-- or the zoom isn't the default (UI.DefaultZoom(), ui/View.lua); a click flies back to you at that zoom (Motion.Reset).
-- A gold circular arrow as the + and - are gold glyphs: the first of Blizzard's the client has (greyed and tinted the
-- zoom buttons' gold: Forever's revert arrow is orange), else its refresh button's arrows (RefreshButtonTemplate's UI-RefreshButton, else its file).
local RESET_TOL = 1 -- px per tile: a zoom this close to the default is the default
local GOLD_ARROWS = { "transmog-icon-revert", "talents-button-undo" }
local WHITE_ARROWS = { "common-icon-undo", "uitools-icon-refresh" }
local ZOOM_GOLD = { 1, 0.86, 0.25 }
local zoomReset = CreateFrame("Button", nil, Chrome.controls)
zoomReset:SetSize(20, 20) -- (the + and -'s)
zoomReset:SetPoint("BOTTOM", zoomIn, "TOP", 0, 2)
do
	local gold, white = FirstAtlas(unpack(GOLD_ARROWS)), FirstAtlas(unpack(WHITE_ARROWS))
	local refresh = not (gold or white) and FirstAtlas("UI-RefreshButton")
	for _, layer in ipairs({ "ARTWORK", "HIGHLIGHT" }) do
		local arrows = zoomReset:CreateTexture(nil, layer)
		local atlas = gold or white or refresh
		if atlas then arrows:SetAtlas(atlas) else arrows:SetTexture("Interface\\Buttons\\UI-RefreshButton") end
		if gold or white then -- (orange or white: greyed, then the + and -'s gold)
			arrows:SetDesaturated(true)
			arrows:SetVertexColor(unpack(ZOOM_GOLD))
		end
		arrows:SetSize(18, 18)
		arrows:SetPoint("CENTER", zoomIn, "CENTER", 0, 22) -- (the + and -'s centre line, a step above the +)
		if layer == "HIGHLIGHT" then arrows:SetBlendMode("ADD") end
	end
end
zoomReset:Hide()
Controls.zoomReset = zoomReset

---------------------------------------------------------------------------
-- The quest pill (bottom left): the one pill for what you go to. With a target on this map (Model.Target: your
-- corpse, the quest you follow, your waypoint or the icon you track; UI.You.Target names it), that; else the quest
-- you follow (on another map: no distance); else how many of your quests are in this zone. On a small dark pill
-- that reads on any map. What it says is the pieces chosen on its page, in their order (as the title's,
-- ui/Title.lua): the name, the quest's progress, the yards to it (along the way, Model.Route, else straight) and
-- the time to arrive at your pace (now if you're moving, else the last pace you were seen at, else a run's: RUN).
-- Behind its text a faint gold fill, how far you've come: empty at the farthest you've been from this target since
-- you began going to it (where you started, unless you've wandered further off since: so it never runs backwards
-- past empty, and a target picked from across the zone starts empty however far it is), full on arriving (inside
-- its area). Worked out every EVERY s from Model's quest list, your zone and the target; its text fitted again only
-- when it changes. It fades with the other controls, but stays shown while it shows a target; on the followed quest
-- it is that quest's pin: hovering it shows the quest's tooltip and lights its area, a click (either button) grows it
-- into the popup (ui/Popup.lua; ui/Track.lua's Actions: Stop tracking or pathing, the other mode, Open in quest log).
-- Otherwise it takes no mouse. While it shows what you track or path to (not your corpse), a small x at its right
-- end lets it go (Track.Clear). Its look is Forever's progress bar (below).
---------------------------------------------------------------------------

local LINE_H, LINE_PAD = 16, 7
local ICON, ICON_X, ICON_GAP = 12, 7, 4 -- the icon: its size, its left, the gap to the text
local ZOOM_COL = 30 -- px at the map's right kept clear of the line: the zoom buttons' column and a gap
local EVERY = 0.3 -- s between looks: three or so a second (the yards change as you walk)
local RUN = 7 -- yd/s, a run
local YARDS_STEP = 10 -- yards are rounded to this from 100 up: no flicker while you walk
local SEP, NEAR = "  \194\183  ", "  " -- between pieces; between the name and its progress, as before
local ELLIPSIS = "\226\128\166" -- "…" in UTF-8
local BAR = { 1, 0.82, 0.25, 0.6 } -- the fill: the title's gold (its colour Settings > Quest pill > Bar colour)
local BAR_COLORS = {
	{ "Gold", { 1, 0.82, 0.25 } }, { "Parchment", { 1, 0.93, 0.76 } }, { "White", { 1, 1, 1 } },
	{ "Green", { 0.35, 0.9, 0.35 } }, { "Sky", { 0.45, 0.75, 1 } }, { "Rose", { 1, 0.5, 0.6 } },
}

-- On Chrome.overlay, not under the controls: the line shows at full alpha while it shows a target,
-- and fades with the controls otherwise (the step below).
local overlay = Chrome.overlay
local line = CreateFrame("Frame", nil, overlay)
line:SetPoint("BOTTOMLEFT", PAD, BOTTOM_Y)
line:SetHeight(LINE_H)
line:Hide()
local tracked = false -- the line shows a target (or the followed quest)
local followedQuest -- the followed quest's Known entry, while the line shows it
local hover = 1 -- the controls' fade (the step below)

-- The icon: the quest log tab's for a quest (filled: the client has no outline of it to pair with; the zone's count
-- dimmed), your corpse's and your waypoint's own (ui/You.lua's) for those.
local questAtlas = FirstAtlas("questlog-tab-icon-quest", "QuestNormal")
local ICONS = { quest = questAtlas, corpse = "deathrecap-icon-tombstone", waypoint = "Waypoint-MapPin-Tracked" }
local icon = line:CreateTexture(nil, "ARTWORK")
icon:SetSize(ICON, ICON)
icon:SetPoint("LEFT", line, "LEFT", ICON_X, 0)
if questAtlas then icon:SetAtlas(questAtlas) else icon:Hide() end
local iconKind = "quest"
-- The pill's art: Forever's own progress bar (its legacy bar, the c60 art: GetAtlasInfo takes the first name the
-- client has), a dark rounded track, the fill over it (the bar's green, greyed and tinted: Bar colour, Bar
-- opacity), a thin bronze frame round both; on a client without it, plain rectangles and no frame. Each a strip
-- of three (its ends kept, its middle stretched), file and coords set here (not SetAtlas) so the fill can be cut
-- at its share.
local function Info(...)
	for i = 1, select("#", ...) do
		local info = C_Texture.GetAtlasInfo(select(i, ...))
		if info then return info end
	end
end
local TRACK = Info("legacy-progressbar-bg-c60", "legacy-progressbar-bg")
local FILL = Info("legacy-progressbar-fill-c60", "legacy-progressbar-fill")
local FRAME = Info("legacy-progressbar-frame-c60", "legacy-progressbar-frame")
local TRACK_END, FRAME_END = 4, 12 -- the art's px of each end kept whole (its rounding)
-- The frame drawn at FRAME_K of its art (a thin border: its art is 131 x 26 round a 117 x 12 track, 7 px out), so it
-- reaches FRAME_OUT px past the track; its alpha.
local FRAME_K, FRAME_OUT, FRAME_A = 0.6, 4, 0.85
local PILL_A = 0.25 -- the track's alpha: faint ("pills.alpha" sets it live: SetPillAlpha)

-- A strip of three textures on line, out px past its edges: info's file (its ends: ends px of the art each, drawn
-- at k), else a plain colour.
local function Strip(layer, sub, info, ends, out, k)
	local parts = {}
	for i = 1, 3 do
		local t = line:CreateTexture(nil, layer, nil, sub)
		if info then t:SetTexture(info.file) else t:SetColorTexture(1, 1, 1) end
		parts[i] = t
	end
	local l, r, top, bottom = 0, 1, 0, 1
	if info then l, r, top, bottom = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord end
	local e = info and ends or 0
	local u = info and e * (r - l) / info.width or 0 -- /: never 0 (an atlas's width > 0)
	parts[1]:SetTexCoord(l, l + u, top, bottom)
	parts[2]:SetTexCoord(l + u, r - u, top, bottom)
	parts[3]:SetTexCoord(r - u, r, top, bottom)
	parts[1]:SetPoint("TOPLEFT", -out, out)
	parts[1]:SetPoint("BOTTOMLEFT", -out, -out)
	parts[1]:SetWidth(e * (k or 1))
	parts[3]:SetPoint("TOPRIGHT", out, out)
	parts[3]:SetPoint("BOTTOMRIGHT", out, -out)
	parts[3]:SetWidth(e * (k or 1))
	parts[2]:SetPoint("TOPLEFT", parts[1], "TOPRIGHT")
	parts[2]:SetPoint("BOTTOMRIGHT", parts[3], "BOTTOMLEFT")
	if e == 0 then parts[1]:Hide(); parts[3]:Hide() end
	return parts
end
local function Tint(parts, c, a)
	for _, t in ipairs(parts) do t:SetVertexColor(c[1], c[2], c[3], a) end
end

local backing = Strip("BACKGROUND", 0, TRACK, TRACK_END, 0)
local function SetPillAlpha(a) Tint(backing, { 0, 0, 0 }, a) end
SetPillAlpha(PILL_A)
if FRAME then Tint(Strip("ARTWORK", -1, FRAME, FRAME_END, FRAME_OUT, FRAME_K), { 1, 1, 1 }, FRAME_A) end

-- The fill: one texture, the bar's art cut at its share of the width (its left end kept, cut on the right).
local fillM = line:CreateTexture(nil, "BORDER")
if FILL then
	fillM:SetTexture(FILL.file)
	fillM:SetDesaturated(true) -- (its green greyed: the tint is its colour)
else
	fillM:SetColorTexture(1, 1, 1)
end
fillM:SetPoint("TOPLEFT")
fillM:SetPoint("BOTTOMLEFT")
-- The fill's colour (a preset's name or "#rrggbb") and its opacity.
local function SetBarColor(v)
	local _, c = UI.Feel.RGB(BAR_COLORS, v, BAR_COLORS[1][1])
	BAR[1], BAR[2], BAR[3] = c[1], c[2], c[3]
	fillM:SetVertexColor(BAR[1], BAR[2], BAR[3], BAR[4])
end
local function SetBarAlpha(v)
	BAR[4] = v
	SetBarColor(UI.Feel.Get("pills.barColor"))
end
SetBarColor(BAR_COLORS[1][1])
local function Fill(frac, w)
	local f = math.min(1, frac or 0)
	fillM:SetShown(f > 0)
	if f <= 0 then return end
	fillM:SetWidth(f * w)
	if FILL then
		local l, r = FILL.leftTexCoord, FILL.rightTexCoord
		fillM:SetTexCoord(l, l + (r - l) * f, FILL.topTexCoord, FILL.bottomTexCoord)
	end
end

-- The x: what the pill shows (a followed quest, a tracked or pathed icon, your waypoint) let go (Track.Clear); not
-- your corpse (the game ends that). Minimal: a thin x glyph (the client's, else a drawn one) in the text's colour,
-- soft at rest, full on hover, in a small square at the pill's right end.
local X, X_GLYPH, X_REST = LINE_H - 2, 8, 0.6 -- its square, its glyph (px), its alpha at rest
local close = CreateFrame("Button", nil, line)
close:SetSize(X, X)
close:SetPoint("RIGHT", line, "RIGHT", -3, 0)
local glyph = close:CreateTexture(nil, "OVERLAY")
glyph:SetSize(X_GLYPH, X_GLYPH)
glyph:SetPoint("CENTER")
local xAtlas = FirstAtlas("uitools-icon-close")
if xAtlas then glyph:SetAtlas(xAtlas) else glyph:SetTexture("Interface\\Buttons\\UI-StopButton") end
glyph:SetVertexColor(0.95, 0.9, 0.8, X_REST)
close:SetScript("OnEnter", Runtime.Wrap("map: pill x", function() glyph:SetVertexColor(1, 1, 1, 1) end))
close:SetScript("OnLeave", Runtime.Wrap("map: pill x", function() glyph:SetVertexColor(0.95, 0.9, 0.8, X_REST) end))
close:Hide()
Controls.questClose = close

-- The pill's look and behaviour (its page, through SetPill; these its defaults): its size, whether it shows, what it
-- says (the pieces, in order), its fill, and whether it fades until you point at the map.
local PILL = { scale = 0.9, questShow = "all", pieces = { "progress" }, bar = true, questFade = true }
local lineText = line:CreateFontString(nil, "OVERLAY")
lineText:SetFont(FONT, 10, "")
lineText:SetTextColor(0.95, 0.9, 0.8)
Controls.questLine, Controls.questFill = line, fillM

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

-- The yards to the target: along the way if there's one (tiles to yards), else straight (yd); rounded to
-- YARDS_STEP from 100 up.
local function Yards(yd)
	local way = Model.Route()
	if way and #way > 1 then
		local d = 0
		for i = 1, #way - 1 do
			local a, b = way[i], way[i + 1]
			d = d + math.sqrt((b.col - a.col) ^ 2 + (b.row - a.row) ^ 2)
		end
		yd = math.floor(d * Atlas.TILE_YARDS + 0.5)
	end
	if yd >= 100 then yd = math.floor(yd / YARDS_STEP + 0.5) * YARDS_STEP end
	return yd
end

local pace = RUN -- the last non-zero speed seen
local function Eta(yd)
	local secs = yd / pace -- /: never 0 (pace starts at RUN and only takes speeds above 0)
	if secs < 60 then return "<1 min" end
	if secs < 5400 then return string.format("%d min", math.floor(secs / 60 + 0.5)) end
	return string.format("%d h", math.floor(secs / 3600 + 0.5))
end

-- One piece's words, or nil: none to say.
local function Piece(p, name, quest, yd)
	if p == "name" then return name end
	if p == "progress" then
		if not quest then return nil end
		if quest.complete then return "ready to turn in" end
		local have, need = Progress(quest)
		return need > 0 and have .. "/" .. need or nil
	end
	if type(yd) ~= "number" then return nil end
	if p == "distance" then return yd .. " yd" end
	return Eta(yd)
end

-- The fill's reference: the farthest you've been from the target since you began going to it. The same target: a
-- quest by its key (its area's edge moves as you do), a corpse or waypoint (or the icon tracked on it) by its spot.
local farKind, farKey, far
local function Share(t, yd)
	if yd == false then return 1 end -- (inside its area: arrived)
	if not yd then return nil end
	local key = t.kind == "quest" and t.key or t.pos
	if t.kind ~= farKind or key ~= farKey then farKind, farKey, far = t.kind, key, yd end
	if yd > far then far = yd end
	return far > 0 and 1 - yd / far or 1 -- /: never 0 (far > 0 checked)
end

-- What the line says, as pre (kept), head (the name: cut first when long) and tail (kept), or nil for nothing; and
-- what it's about: followedQuest, tracked, iconKind and the fill's share (frac; nil: none) set.
local frac
local function Words(list, here)
	followedQuest, tracked, frac = nil, false, nil
	if PILL.questShow == "off" then return nil end
	local title, yd = UI.You.Target()
	local t = title and Model.Target()
	local quest
	if not t or t.kind == "quest" then
		for _, e in ipairs(list) do
			if e.followed then
				quest = e
				break
			end
		end
	end
	if quest or t then
		followedQuest, tracked = quest, true
		iconKind = quest and "quest" or t.kind
		if type(yd) == "number" then yd = Yards(yd) end -- (no target here, the followed quest elsewhere: none)
		frac = PILL.bar and t and Share(t, yd) or nil
		local name = quest and quest.name or title
		local pre, head, tail, prev = "", nil, "", nil
		for _, p in ipairs(PILL.pieces) do
			local w = Piece(p, name, quest, yd)
			if w then
				local sep = prev and (p == "progress" and prev == "name" and NEAR or SEP) or ""
				if p == "name" then
					pre, head = pre .. sep, w
				elseif head then
					tail = tail .. sep .. w
				else
					pre = pre .. sep .. w
				end
				prev = p
			end
		end
		return pre, head or "", tail
	end
	iconKind = "quest"
	if not here or PILL.questShow == "followed" then return nil end
	local n = 0
	for _, e in ipairs(list) do
		if PinZone(e.pos) == here.mapID then n = n + 1 end
	end
	if n == 0 then return nil end
	return string.format("%d %s in ", n, n == 1 and "quest" or "quests"), here.name, ""
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

local function Show(pre, head, tail)
	line:EnableMouse(followedQuest ~= nil)
	if not pre then
		line:Hide()
		return
	end
	local x = tracked and iconKind ~= "corpse"
	close:SetShown(x)
	local xw = x and X or 0
	-- Capped so the line never reaches the zoom buttons (the map's width less the zoom column).
	local textX = questAtlas and ICON_X + ICON + ICON_GAP or LINE_PAD
	-- In the pill's own units (SetScale).
	local w = overlay:GetWidth() / PILL.scale -- /: never 0 (the scale's least is 0.8)
	local avail = w > 0 and w - (2 * PAD + ZOOM_COL) / PILL.scale - textX - LINE_PAD - xw or math.huge -- /: never 0 (as above)
	lineText:SetPoint("LEFT", line, "LEFT", textX, 0)
	lineText:SetText(Fit(pre, head, tail, avail))
	line:SetWidth(textX + lineText:GetStringWidth() + LINE_PAD + xw)
	local atlas = ICONS[iconKind] or questAtlas
	if atlas and icon:GetAtlas() ~= atlas then icon:SetAtlas(atlas) end
	icon:SetDesaturated(not tracked)
	icon:SetAlpha(tracked and 1 or 0.6)
	line:SetAlpha((tracked or not PILL.questFade) and 1 or hover)
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

-- The followed quest's pin, in the pill: its tooltip and area under the cursor, its popup on a click.
line:SetScript("OnEnter", Runtime.Wrap("map: quest pill", function()
	local e = followedQuest
	if not e then return end
	UI.Areas.Hover(e)
	if UI.Popup.IsOpen() then return end
	GameTooltip:SetOwner(line, "ANCHOR_RIGHT")
	UI.QuestTooltip.Fill(GameTooltip, e)
	GameTooltip:Show()
end))
line:SetScript("OnLeave", Runtime.Wrap("map: quest pill", function()
	UI.Areas.Hover(nil)
	if GameTooltip:IsOwned(line) then GameTooltip:Hide() end
end))
line:SetScript("OnMouseUp", Runtime.Wrap("map: quest pill", function()
	local e = followedQuest
	if not e then return end
	UI.Popup.Open(function(tip) UI.QuestTooltip.Fill(tip, e) end, UI.Track.Actions(e))
end))

-- What the line last said (and the map's width: its cap), so it's fitted again only on a change; the fill each look.
local lastPre, lastHead, lastTail, lastW, lastKind, lastFrac, lastFillW
local function Look()
	local speed = Model.you.speed
	if speed and speed > 0 then pace = speed end
	local pre, head, tail = Words(Model.Known("quests"), YourZone())
	local w = overlay:GetWidth()
	if pre ~= lastPre or head ~= lastHead or tail ~= lastTail or w ~= lastW or iconKind ~= lastKind then
		lastPre, lastHead, lastTail, lastW, lastKind = pre, head, tail, w, iconKind
		Show(pre, head, tail)
	end
	local lw = pre and line:GetWidth()
	if pre and (frac ~= lastFrac or lw ~= lastFillW) then
		lastFrac, lastFillW = frac, lw
		Fill(frac, lw)
	end
end

-- The pill's size (SetScale: its offsets are in its own units, so divided by it).
local function Place()
	local sc = PILL.scale
	line:SetScale(sc)
	line:ClearAllPoints()
	line:SetPoint("BOTTOMLEFT", PAD / sc, BOTTOM_Y / sc) -- /: never 0 (the scale's least is 0.8)
end

-- The buttons' and the pill's alphas from the hover's fade: the buttons from Buttons at rest (away) to 1 (over).
local rest = 0
local function Reveal()
	local a = rest + (1 - rest) * hover
	Chrome.controls:SetAlpha(a)
	gear:SetAlpha(a)
	mode:SetAlpha(a)
	Chrome.grip:SetAlpha(GRIP_ALPHA * a)
	line:SetAlpha((tracked or not PILL.questFade) and 1 or hover)
end

-- One of PILL's settings: applied at once, the pill worked out again.
local function SetPill(key, v)
	if PILL[key] == v then return end
	PILL[key] = v
	Place()
	lastPre, lastFrac = nil, -1
	Look()
	Reveal()
end

-- The mode button points the way it goes: Blizzard's expand on the small map, its condense on the big one (the
-- world map's own pair: MaximizeMinimizeButtonFrameTemplate).
local EXPAND = { atlas = { "redbutton-expand-c60", "redbutton-expand" },
	pushed = { "redbutton-expand-pressed-c60", "redbutton-expand-pressed" } }
local CONDENSE = { atlas = { "redbutton-condense" }, pushed = { "redbutton-condense-pressed" } }
local modeBig = false
local function ModeLook()
	local big = UI.BigMap.big == true
	if big == modeBig then return end
	modeBig = big
	local art = big and CONDENSE or EXPAND
	local a, p = FirstAtlas(unpack(art.atlas)), FirstAtlas(unpack(art.pushed))
	if a then mode:SetNormalAtlas(a) end
	if p then mode:SetPushedAtlas(p) end
end

---------------------------------------------------------------------------
-- Reset: the button shows while the map is off its default (following you, at the default zoom); a click flies back.
-- The zoom buttons tinted while the zoom is past Blizzard's Minimap's (Motion.PastBlips: its blips not shown).
---------------------------------------------------------------------------

local resetShown, past = false, nil
local PAST = { 0.45, 0.75, 1 } -- the zoom buttons' tint past Blizzard's Minimap's zooms (its blips not shown)
local function ResetLook()
	local off = not Camera.follow or math.abs(Camera.cam.zoom - UI.DefaultZoom()) > RESET_TOL
	if off ~= resetShown then
		resetShown = off
		zoomReset:SetShown(off)
	end
	local p = UI.Motion.PastBlips()
	if p ~= past then
		past = p
		for _, b in ipairs({ zoomIn, zoomOut }) do
			local t = b:GetNormalTexture()
			if t then t:SetVertexColor(p and PAST[1] or 1, p and PAST[2] or 1, p and PAST[3] or 1) end
		end
	end
end

zoomReset:SetScript("OnClick", Runtime.Wrap("map: zoom reset", function() UI.Motion.Reset() end))

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

-- One step for the map's controls: the fade (the quest pill's too, unless it shows a target), the zoom reset's,
-- the zoom buttons' tint and the mode button's looks (each frame: a cheap compare), and the pill's (EVERY s: a step's
-- probes cost each frame, so these share one).
local since = EVERY
Runtime.Step("ui", "map: controls", function(elapsed)
	local want = (Window.frame:IsMouseOver(REACH, -REACH, 0, 0) or Menus.IsOpen()) and 1 or 0
	if hover ~= want then
		local step = elapsed / FADE
		hover = want > hover and math.min(want, hover + step) or math.max(want, hover - step)
		Reveal()
	end
	ResetLook()
	ModeLook()
	if UI.Cluster then UI.Cluster.Watch() end
	since = since + elapsed
	if since >= EVERY then
		since = 0
		Look()
	end
end, { shownOnly = Window.frame })

---------------------------------------------------------------------------
-- Tips: a button's name, a GameTooltip title alone right of it (ui/Tip.lua's Label), after a moment's hover; gone
-- when you leave, click or open a menu
---------------------------------------------------------------------------

local wait = CreateFrame("Frame", nil, UIParent) -- shown while a tip waits for its moment
wait:Hide()
Runtime.Step("ui", "map: tip", function(elapsed)
	wait.t = wait.t + elapsed
	if Menus.IsOpen() or not wait.owner:IsMouseOver() then
		wait:Hide()
	elseif wait.t >= TIP_DELAY then
		wait:Hide()
		UI.Tip.Label(wait.owner, wait.fn())
	end
end, { shownOnly = wait })

local function Hide(self)
	wait:Hide()
	if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end
Hide = Runtime.Wrap("map: tip hide", Hide)

function Controls.Tip(button, fn)
	button:HookScript("OnEnter", Runtime.Wrap("map: tip show", function(self)
		wait.owner, wait.fn, wait.t = self, fn, 0
		wait:Show()
	end))
	button:HookScript("OnLeave", Hide)
	button:HookScript("OnMouseDown", Hide)
end
Controls.Tip(zoomIn, function() return "Zoom in" end)
Controls.Tip(zoomOut, function() return "Zoom out" end)
Controls.Tip(zoomReset, function() return Camera.follow and "Reset zoom" or "Back to you" end)
Controls.Tip(gear, function() return "Settings" end)
close:SetScript("OnClick", Runtime.Wrap("map: pill close", function() UI.Track.Clear() end))
Controls.Tip(close, function() return UI.Track.ClearLabel() end)

ns.Game.Command({ kind = "slash", name = "follow", help = "follow you on the map, or stop",
	fn = ToggleFollow })

---------------------------------------------------------------------------
-- Settings (ui/Feel.lua): General > Map window, and the Quest pill page
---------------------------------------------------------------------------

UI.Feel.Add("general", "Map window", {
	{ key = "controls.rest", kind = "slider", label = "Buttons at rest", min = 0, max = 1, step = 0.05, pct = true, default = rest,
		apply = function(v) rest = v; Reveal() end,
		tip = "How much the map's buttons (gear, zoom, grow) and its resize grip show while you're not pointing at the map. 0%: hidden till you do." },
})
local function Pill(key) return function(v) SetPill(key, v) end end
local function QuestPill() return UI.Feel.Get("pills.questShow") ~= "off" end
local PIECES = { { "Name", "name" }, { "Objective progress", "progress" }, { "Distance", "distance" },
	{ "Time to arrive", "time" } }
UI.Feel.Add("pills", nil, {
	{ key = "pills.questShow", kind = "select", label = "Shows", default = PILL.questShow, apply = Pill("questShow"),
		options = { { "Target or zone count", "all" }, { "Target only", "followed" }, { "Off", "off" } },
		tip = "Bottom left: what you track (a quest, an icon, your waypoint, your corpse), else how many of your quests are in this zone; or only what you track; or nothing." },
	{ key = "pills.quest", kind = "list", ordered = true, label = "Says", options = PIECES, when = QuestPill,
		default = table.concat(PILL.pieces, ","), apply = function() SetPill("pieces", UI.Feel.List("pills.quest")) end,
		tip = "What the pill says about what you track, in this order: its name, the quest's progress (2/5, or ready to turn in), the yards to it along the way, and the time to get there at your pace." },
	{ key = "pills.questBar", kind = "toggle", label = "Progress bar", default = PILL.bar, when = QuestPill, apply = Pill("bar"),
		tip = "A fill behind the pill's text, how far you've come: empty at the farthest you've been from it since you began tracking it, full once you're there." },
	{ key = "pills.barAlpha", kind = "slider", label = "Bar opacity", min = 0.05, max = 1, step = 0.05, pct = true,
		default = BAR[4], when = function() return QuestPill() and UI.Feel.Get("pills.questBar") ~= false end,
		apply = SetBarAlpha, tip = "How solid the progress bar is behind the text." },
	{ key = "pills.barColor", kind = "color", label = "Bar colour", colors = BAR_COLORS, default = BAR_COLORS[1][1],
		when = function() return QuestPill() and UI.Feel.Get("pills.questBar") ~= false end, apply = SetBarColor,
		tip = "The progress bar's colour." },
	{ key = "pills.questFade", kind = "toggle", label = "Fade quest pill", default = PILL.questFade, when = QuestPill,
		apply = Pill("questFade"), tip = "The zone's quest count shows only while you point at the map. What you track always shows." },
})
UI.Feel.Add("pills", "Look", {
	{ key = "pills.alpha", kind = "slider", label = "Backing", min = 0, max = 0.8, step = 0.05, pct = true, default = PILL_A,
		apply = SetPillAlpha, tip = "How dark the pill's track is, behind the progress bar." },
	{ key = "pills.scale", kind = "slider", label = "Size", min = 0.8, max = 1.6, step = 0.1, pct = true, default = PILL.scale,
		apply = Pill("scale"), tip = "The pill's size, text and all." },
})
