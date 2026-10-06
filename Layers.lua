-- Optional map layers built from game data: C_Map, C_TaxiMap, C_DeathInfo,
-- C_EncounterJournal, C_QuestLog, C_MapExplorationInfo. Everything is placed
-- by world position; no Blizzard map artwork is drawn.
--
-- Zone borders: the continent map is sampled on a grid with
-- C_Map.GetMapInfoAtPosition, boundaries are traced with (multi-label)
-- marching squares, each crossing is refined by bisection against the real
-- API, and the chains are simplified + smoothed and drawn with Line regions.
-- Sampling runs in a coroutine a slice per frame, so it never hitches.
--
-- Quest areas: where the client supports it, a QuestPOIFrame per zone draws
-- the game's own objective blobs, positioned in tile space. Otherwise we
-- classify objectives (kill/collect = area, go-to/talk/turn-in = point) and
-- draw a dashed "rough area" circle for areas.
--
-- Each layer draws onto a 1x1 "canvas" frame positioned at tile (0,0): panning
-- moves only the canvas. While zooming:
--   * pins are styled once per data change and only moved;
--   * labels are moved, and re-placed (collisions, new names fading in) when
--     the zoom drifts far enough or settles;
--   * geometry (borders, shading, quest areas) is laid out at one zoom and
--     scaled to the current one. Borders, which run to thousands of lines,
--     are double-buffered: the layout for where the camera is headed is
--     built a slice per frame into a hidden back buffer, then cross-faded in,
--     so zooming and panning never wait on it.

local ADDON, ns = ...
local state = ns.state
local db

-- group: menu section (GROUPS below; "places" if unset). tip: the menu's
-- tooltip. parent: a sub-option, only in effect (and only clickable) while
-- that layer is on.
local LAYERS = {
	{ key = "zoneLabels", label = "Zone labels", group = "map", default = true,
		tip = "Names of zones and sub-zones." },
	{ key = "zoneBorders", label = "Zone borders", group = "map", default = true,
		tip = "Outlines between zones, traced from the terrain." },
	{ key = "unexplored", label = "Shade unexplored", group = "map", default = false,
		tip = "Darken the parts of each zone you haven't discovered yet." },
	{ key = "quests", label = "Quests", group = "quests", default = true,
		tip = "Quests in your log. Click one to follow it." },
	{ key = "questAreas", label = "Quest areas", group = "quests", default = true,
		tip = "Where each quest's objectives are, as the game draws them." },
	{ key = "questAreasApprox", label = "Estimate missing areas", group = "quests", parent = "questAreas", default = true,
		tip = "A rough dashed circle for kill and collect objectives the game gives no area for." },
	{ key = "offers", label = "Quests to pick up", group = "quests", default = true,
		tip = "Quests you could start nearby." },
	{ key = "flight", label = "Flight points", group = "places", default = true,
		tip = "Flight masters you can fly to or from." },
	{ key = "dungeons", label = "Dungeon entrances", group = "places", default = true,
		tip = "Dungeon and raid entrances." },
	{ key = "graveyards", label = "Graveyards", group = "places", default = false,
		tip = "Where your spirit goes when you release." },
	{ key = "corpse", label = "Corpse", group = "you", default = true,
		tip = "Where you died. While you're a ghost it's your target." },
	{ key = "group", label = "Party & raid", group = "people", default = true,
		tip = "Party and raid members, in their class colours." },
	{ key = "waypoint", label = "Waypoint", group = "you", default = true,
		tip = "Your map pin. Ctrl-click the map to set it, ctrl-right-click to clear it." },
}

-- Menu sections, in order. "addons" is filled at runtime and hidden while empty.
local GROUPS = {
	{ key = "map", title = "Map" },
	{ key = "quests", title = "Quests" },
	{ key = "places", title = "Places" },
	{ key = "people", title = "People" },
	{ key = "you", title = "You" },
	{ key = "addons", title = "Other addons" },
}

local layerByKey = {}
for _, layer in ipairs(LAYERS) do layerByKey[layer.key] = layer end

local CELL = 0.2              -- sampling grid cell, in tiles (~107 yards)
local SAMPLES_PER_FRAME = 700
local REFINE_STEPS = 5        -- bisection steps per border crossing (~3 yards)
local GAP_FILL_CELLS = 6        -- close unassigned gaps between zones up to ~640 yards wide
local LABEL_MAX_ZOOM = 200    -- hide zone labels when zoomed in further than this
local APPROX_RADIUS = 110 / 533.33 -- rough objective area radius, in tiles
local CIRCLE = ns.CIRCLE

-- A sub-option is off while its parent is.
local function Enabled(key)
	if not db then return nil end
	local parent = layerByKey[key] and layerByKey[key].parent
	if parent and not Enabled(parent) then return false end
	return db.layers[key]
end
ns.LayerEnabled = function(key) return Enabled(key) and true or false end

local function MapPos(x, y)
	if CreateVector2D then return CreateVector2D(x, y) end
	return { x = x, y = y }
end

local function PosXY(pos)
	if not pos then return end
	if pos.GetXY then return pos:GetXY() end
	return pos.x, pos.y
end

local function SafeCall(fn, ...)
	if not fn then return nil end
	local ok, a, b = pcall(fn, ...)
	if ok then return a, b end
end

-- The quest you follow: the game's super-tracked quest where the client has
-- one, else one remembered here for the session.
local followedQuest
local function FollowedQuest()
	if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
		local id = SafeCall(C_SuperTrack.GetSuperTrackedQuestID)
		if id and id ~= 0 then return id end
	end
	return followedQuest
end

local function FollowHint(questID)
	return FollowedQuest() == questID and "|cff9d9d9dClick to stop following|r" or "|cff9d9d9dClick to follow|r"
end

---------------------------------------------------------------------------
-- Canvases and pools
---------------------------------------------------------------------------

local canvases = {}
for _, name in ipairs({ "shade", "areas", "labels", "pins" }) do
	local c = CreateFrame("Frame", nil, ns.layerFrames[name])
	c:SetSize(1, 1)
	canvases[name] = c
end

-- Border buffers (see the top of the file): front is on screen, back is
-- being built. zoom/region: what a buffer's contents were laid out for.
local buffers = {}
for i = 1, 2 do
	local c = CreateFrame("Frame", nil, ns.layerFrames.lines)
	c:SetSize(1, 1)
	c:Hide()
	buffers[i] = { canvas = c }
end
local front, back = buffers[1], buffers[2]
local fade -- { from, to, t }: a swap cross-fading in

local layoutZoom = {} -- shade/areas canvas -> zoom its contents were laid out at
local hasLines = canvases.shade.CreateLine ~= nil

-- A scaled frame's anchor offsets are in its own (scaled) units.
local function PlaceCanvas(c, x, y, z)
	local s = z and state.zoom / z or 1
	if c:GetScale() ~= s then c:SetScale(s) end
	c:ClearAllPoints()
	c:SetPoint("TOPLEFT", c:GetParent(), "TOPLEFT", x / s, -y / s)
	return s
end

local function PositionCanvases()
	local x, y = ns.TileToScreen(0, 0)
	for _, c in pairs(canvases) do PlaceCanvas(c, x, y, layoutZoom[c]) end
	for _, b in ipairs(buffers) do
		if b.zoom then
			local s = PlaceCanvas(b.canvas, x, y, b.zoom)
			if not fade and b == front then
				-- Scaled far from its layout zoom, lines go hairline-thin or
				-- chunky; let them recede until the fresh layout fades in.
				local off = math.abs(math.log(s) / math.log(2))
				b.canvas:SetAlpha(math.max(0.25, math.min(1, 1.6 - 0.6 * off)))
			end
		end
	end
end

-- Reusable pool of textures/lines/font strings. `cap` bounds how many one
-- layout may use, so a dense map can never stall the frame.
local function Pool(create, cap)
	local pool = { list = {}, used = 0, peak = 0, cap = cap or math.huge }
	function pool:Reset()
		for i = 1, math.max(self.used, self.peak) do
			local obj = self.list[i]
			if obj then obj:Hide() end
		end
		self.used, self.peak = 0, 0
	end
	-- Refilling a hidden pool over several frames: reuse objects as they are,
	-- then hide whatever this fill didn't get to.
	function pool:Begin()
		self.peak = math.max(self.used, self.peak)
		self.used = 0
	end
	function pool:Finish()
		for i = self.used + 1, self.peak do
			local obj = self.list[i]
			if obj then obj:Hide() end
		end
		self.peak = self.used
	end
	function pool:Full() return self.used >= self.cap end
	function pool:Unget()
		self.list[self.used]:Hide()
		self.used = self.used - 1
	end
	function pool:Get()
		local obj = self.list[self.used + 1]
		if not obj then
			obj = create() -- count it only once it exists
			self.list[self.used + 1] = obj
		end
		self.used = self.used + 1
		obj:Show()
		return obj
	end
	return pool
end

local function LinePool(canvas, sublevel, cap)
	return Pool(function()
		local l = canvas:CreateLine(nil, "ARTWORK", nil, sublevel)
		l:SetColorTexture(1, 1, 1, 1)
		-- Without this, short or thin segments snap away and borders look dashed.
		if l.SetSnapToPixelGrid then l:SetSnapToPixelGrid(false) end
		if l.SetTexelSnappingBias then l:SetTexelSnappingBias(0) end
		return l
	end, cap or 3000)
end

local shadePool = Pool(function() return canvases.shade:CreateTexture(nil, "ARTWORK") end)
if hasLines then
	for _, b in ipairs(buffers) do
		-- Roomier than most: panning extends these in place (see StartExtend).
		b.sub = LinePool(b.canvas, -1, 5000)    -- subzone outlines
		b.shadow = LinePool(b.canvas, 0, 5000)  -- soft shadow under zone borders
		b.border = LinePool(b.canvas, 1, 5000)  -- zone borders
		b.highlight = LinePool(b.canvas, 3) -- the hovered zone's borders
	end
end
local areaFillPool = Pool(function() return canvases.areas:CreateTexture(nil, "ARTWORK", nil, 0) end)
local areaLinePool = hasLines and LinePool(canvases.areas, 1)
local labelPool = Pool(function()
	local fs = canvases.labels:CreateFontString(nil, "OVERLAY")
	fs:SetShadowOffset(1, -1)
	fs:SetShadowColor(0, 0, 0, 1)
	return fs
end)

-- The border builder is a coroutine resumed once a frame (see StartBuild);
-- DrawLine hands the frame back once the builder has had its slice (an
-- extension, only between whole lines: see BuildBorders).
local BUILD_SLICE_MS = 3
local URGENT_SLICE_MS = 8 -- while the view has run past the drawn borders
local build -- { co, buf, zoom, region, map, ms, urgent, extend, overflow }
local sliceStart, drawn = 0, 0
local function MaybeYield(lineStart)
	if build and build.extend and not lineStart then return end
	drawn = drawn + 1
	if not lineStart and drawn % 40 ~= 0 or not (build and coroutine.running() == build.co) then return end
	if debugprofilestop then
		if debugprofilestop() - sliceStart > (build.urgent and URGENT_SLICE_MS or BUILD_SLICE_MS) then coroutine.yield() end
	elseif drawn % 400 == 0 then
		coroutine.yield()
	end
end

local function DrawLine(pool, canvas, x1, y1, x2, y2, thick, r, g, b, a)
	if pool:Full() then return end
	MaybeYield()
	local l = pool:Get()
	-- Pooled lines mostly keep their style from the last layout; skip re-setting it.
	if l.r ~= r or l.g ~= g or l.b ~= b or l.a ~= a then
		l:SetColorTexture(r, g, b, a)
		l.r, l.g, l.b, l.a = r, g, b, a
	end
	if l.thick ~= thick then
		l:SetThickness(thick)
		l.thick = thick
	end
	l:SetStartPoint("TOPLEFT", canvas, x1, -y1)
	l:SetEndPoint("TOPLEFT", canvas, x2, -y2)
end

---------------------------------------------------------------------------
-- Pins (points of interest)
---------------------------------------------------------------------------

local function AtlasExists(atlas)
	return atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) ~= nil
end

local function PinOnEnter(self)
	local e = self.entry
	if not e then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(e.title or "?")
	for _, line in ipairs(e.lines or {}) do GameTooltip:AddLine(line, 1, 1, 1, true) end
	GameTooltip:Show()
end

local pinPool = Pool(function()
	local pin = CreateFrame("Frame", nil, canvases.pins)
	pin.ring = pin:CreateTexture(nil, "ARTWORK", nil, 0)
	pin.ring:SetPoint("CENTER")
	pin.ring:SetTexture(CIRCLE)
	pin.icon = pin:CreateTexture(nil, "ARTWORK", nil, 1)
	pin.icon:SetPoint("CENTER")
	pin:EnableMouse(true)
	-- Let clicks fall through to the map so dragging still works over pins.
	if pin.SetPropagateMouseClicks then pin:SetPropagateMouseClicks(true) end
	pin.glow = pin:CreateTexture(nil, "BACKGROUND")
	pin.glow:SetPoint("CENTER")
	pin.glow:SetTexture(CIRCLE)
	pin.glow:Hide()
	pin:SetScript("OnEnter", PinOnEnter)
	pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return pin
end)

local pinData = {} -- layer key -> list of { col, row, size, icon = { atlas, color, style }, title, lines }

-- icon: { texture } | { atlas, under (atlas drawn behind), scale } with color as the fallback dot
local function StylePin(pin, e)
	local size = e.size or 14
	-- A soft halo marks what you're following.
	if e.glow then
		pin.glow:SetVertexColor(1, 0.82, 0.3, 0.45)
		pin.glow:SetSize(size + 14, size + 14)
		pin.glow:Show()
	else
		pin.glow:Hide()
	end
	pin:SetSize(size, size)
	local icon = e.icon or {}
	local c = icon.color or { 1, 1, 1 }
	if icon.texture then
		-- Plain icon file (e.g. minimap tracking icons), bare as Blizzard draws them.
		pin.icon:SetTexture(icon.texture)
		pin.icon:SetTexCoord(0, 1, 0, 1)
		pin.icon:SetVertexColor(1, 1, 1, 1)
		pin.icon:SetSize(size, size)
		pin.ring:Hide()
		return
	end
	if icon.atlas and AtlasExists(icon.atlas) then
		if icon.under and AtlasExists(icon.under) then
			pin.ring:SetAtlas(icon.under)
			pin.ring:SetVertexColor(1, 1, 1, 1)
			pin.ring:SetSize(size, size)
			pin.ring:Show()
			local s = size * (icon.scale or 0.62)
			pin.icon:SetAtlas(icon.atlas)
			pin.icon:SetSize(s, s)
		else
			pin.icon:SetAtlas(icon.atlas)
			pin.icon:SetSize(size, size)
			pin.ring:Hide()
		end
		pin.icon:SetVertexColor(1, 1, 1, 1)
		return
	end
	pin.ring:SetTexture(CIRCLE)
	pin.ring:SetTexCoord(0, 1, 0, 1)
	pin.icon:SetTexture(CIRCLE)
	pin.icon:SetTexCoord(0, 1, 0, 1)
	pin.ring:Show()
	-- Fallback: a solid coloured dot on a dark ring.
	pin.ring:SetVertexColor(0, 0, 0, 0.9)
	pin.ring:SetSize(size * 0.6 + 3, size * 0.6 + 3)
	pin.icon:SetVertexColor(c[1], c[2], c[3], 1)
	pin.icon:SetSize(size * 0.6, size * 0.6)
end

-- Pins only move as you zoom; small landmarks appear once you're close
-- enough to use them. In minimap mode ours stay put over Blizzard's blips
-- (they sit above the Minimap): ours first, its own fill the gaps.
local function PositionPins()
	local z = state.zoom
	for i = 1, pinPool.used do
		local pin = pinPool.list[i]
		local e = pin.entry
		if e.minZoom and z < e.minZoom then
			if pin:IsShown() then pin:Hide() end
		else
			if not pin:IsShown() then pin:Show() end
			pin:SetPoint("CENTER", canvases.pins, "TOPLEFT", e.col * z, -e.row * z)
		end
	end
end

-- New pin data: style a pin per entry, then place them.
local function LayoutPins()
	pinPool:Reset()
	for _, layer in ipairs(LAYERS) do
		for _, e in ipairs(pinData[layer.key] or {}) do
			local pin = pinPool:Get()
			pin.entry = e
			StylePin(pin, e)
			pin:ClearAllPoints()
		end
	end
	PositionPins()
end

-- Add an entry positioned in a uiMap's normalized coordinates.
local function AddAt(list, uiMapID, x, y, entry)
	if not x then return end
	local inst, col, row = ns.MapToTile(uiMapID, x, y)
	if inst and inst == state.map then
		entry.col, entry.row = col, row
		list[#list + 1] = entry
		return entry
	end
end

-- Same, from a Vector2D-style position. (A call like AddAt(list, id, PosXY(p), e)
-- would truncate PosXY to one value, so unpack it here instead.)
local function AddAtPos(list, uiMapID, pos, entry)
	local x, y = PosXY(pos)
	return AddAt(list, uiMapID, x, y, entry)
end

-- Maps to query for a continent: the continent map itself plus its zones.
local function QueryMaps(mapID)
	local maps = {}
	local cont = ns.GetContinentMapID(mapID)
	if cont then maps[1] = cont end
	for _, z in ipairs(ns.GetZones(mapID)) do maps[#maps + 1] = z.uiMapID end
	return maps
end

local FACTION_COLORS = { [0] = { 1, 0.82, 0 }, [1] = { 0.9, 0.2, 0.2 }, [2] = { 0.3, 0.5, 1 } }

local sources = {}

sources.flight = function(mapID)
	local list, seen = {}, {}
	if not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then return list end
	for _, uiMapID in ipairs(QueryMaps(mapID)) do
		for _, n in ipairs(SafeCall(C_TaxiMap.GetTaxiNodesForMap, uiMapID) or {}) do
			if n.nodeID and not seen[n.nodeID] then
				seen[n.nodeID] = true
				AddAtPos(list, uiMapID, n.position, {
					size = 18, title = n.name, lines = { "Flight point" },
					icon = { atlas = n.atlasName, color = FACTION_COLORS[n.faction] or FACTION_COLORS[0] },
				})
			end
		end
	end
	return list
end

sources.graveyards = function(mapID)
	local list, seen = {}, {}
	if not (C_DeathInfo and C_DeathInfo.GetGraveyardsForMap) then return list end
	for _, uiMapID in ipairs(QueryMaps(mapID)) do
		for _, g in ipairs(SafeCall(C_DeathInfo.GetGraveyardsForMap, uiMapID) or {}) do
			local id = g.graveyardID or g.areaPOIID or g.name
			if id and not seen[id] then
				seen[id] = true
				AddAtPos(list, uiMapID, g.position, {
					size = 16, title = g.name or "Graveyard", lines = { "Graveyard" },
					icon = { atlas = "poi-graveyard-neutral", color = { 0.7, 0.7, 0.7 } },
				})
			end
		end
	end
	return list
end

local function IsGhost() return UnitIsGhost and UnitIsGhost("player") or false end

-- While you're a ghost your corpse is your target (ahead of quests and
-- waypoints). The client only knows where it is a while after you release,
-- so until it's found the layer asks again every CORPSE_POLL seconds.
local CORPSE_POLL = 1
local corpseFound -- seen while this ghost lasts

sources.corpse = function(mapID)
	local list = {}
	if not (C_DeathInfo and C_DeathInfo.GetCorpseMapPosition) then return list end
	for _, uiMapID in ipairs(QueryMaps(mapID)) do
		local x, y = PosXY(SafeCall(C_DeathInfo.GetCorpseMapPosition, uiMapID))
		if x and AddAt(list, uiMapID, x, y, {
			size = 20, title = "Your corpse", glow = IsGhost(),
			icon = { atlas = "Navigation-Tombstone-Icon", color = { 1, 1, 1 } },
		}) then
			break
		end
	end
	if list[1] and IsGhost() then corpseFound = true end
	return list
end

sources.dungeons = function(mapID)
	local list, seen = {}, {}
	if not (C_EncounterJournal and C_EncounterJournal.GetDungeonEntrancesForMap) then return list end
	for _, uiMapID in ipairs(QueryMaps(mapID)) do
		for _, d in ipairs(SafeCall(C_EncounterJournal.GetDungeonEntrancesForMap, uiMapID) or {}) do
			local id = d.journalInstanceID or d.name
			if id and not seen[id] then
				seen[id] = true
				AddAtPos(list, uiMapID, d.position, {
					size = 20, title = d.name, lines = { d.description },
					icon = { atlas = d.atlasName, color = { 0.7, 0.4, 1 } },
				})
			end
		end
	end
	return list
end

-- Objective types that usually mean "somewhere around here" rather than a spot.
local AREA_OBJECTIVES = { monster = true, item = true, object = true }

local function QuestObjectives(questID)
	return (C_QuestLog.GetQuestObjectives and SafeCall(C_QuestLog.GetQuestObjectives, questID)) or {}
end

-- "point" (turn-in / go-to / talk) or "area" (kill / collect / interact with many).
local function QuestShape(questID, complete)
	if complete then return "point" end
	for _, o in ipairs(QuestObjectives(questID)) do
		if not o.finished and AREA_OBJECTIVES[o.type] then return "area" end
	end
	return "point"
end

local function QuestLines(questID, complete)
	if complete then return { "|cff33ff33Ready to turn in|r" } end
	local lines = {}
	for _, o in ipairs(QuestObjectives(questID)) do
		if o.text and o.text ~= "" then
			lines[#lines + 1] = (o.finished and "|cff808080" or "|cffffffff") .. "- " .. o.text .. "|r"
		end
	end
	return lines
end

local function MapArea(uiMapID)
	local r = ns.MapRect(uiMapID)
	return r and (r.col1 - r.col0) * (r.row1 - r.row0) or math.huge
end

-- { uiMapID, questID, x, y (map-normalized), col, row, shape, hasBlob } for incomplete quests
local questAreas = {}

sources.quests = function(mapID)
	local list = {}
	wipe(questAreas)
	if not (C_QuestLog and C_QuestLog.GetQuestsOnMap) then return list end

	-- A quest can show on a zone and on a sub-zone (e.g. Dun Morogh and
	-- Coldridge Valley). Its objective area lives on the most specific one,
	-- so keep the smallest map that reports it. Continents never draw quests.
	local best = {}
	for _, uiMapID in ipairs(ns.GetQuestMaps(mapID)) do
		for _, q in ipairs(SafeCall(C_QuestLog.GetQuestsOnMap, uiMapID) or {}) do
			if q.questID and not q.isMapIndicatorQuest then
				local area = MapArea(uiMapID)
				local cur = best[q.questID]
				if not cur or area < cur.area then
					best[q.questID] = { uiMapID = uiMapID, x = q.x, y = q.y, area = area }
				end
			end
		end
	end

	for questID, b in pairs(best) do
		local complete = SafeCall(C_QuestLog.IsComplete, questID)
		local shape = QuestShape(questID, complete)
		local title = SafeCall(C_QuestLog.GetTitleForQuestID, questID) or ("Quest " .. questID)
		local followed = questID == FollowedQuest()
		local lines = QuestLines(questID, complete)
		lines[#lines + 1] = FollowHint(questID)
		-- Same art as the world map's quest buttons (re-skinned by the client).
		local icon = complete
			and { atlas = "UI-QuestIcon-TurnIn-Normal", color = { 0.2, 1, 0.2 } }
			or { atlas = "Quest-In-Progress-Icon-yellow", under = "UI-QuestPoi-QuestNumber", color = { 1, 0.82, 0 } }
		local e = AddAt(list, b.uiMapID, b.x, b.y, {
			size = followed and 26 or 22, glow = followed, questID = questID, title = title, icon = icon, turnIn = complete,
			lines = lines,
		})
		if e and not complete then
			questAreas[#questAreas + 1] = {
				uiMapID = b.uiMapID, questID = questID, x = b.x, y = b.y,
				col = e.col, row = e.row, shape = shape, title = title,
			}
		end
	end
	return list
end

sources.waypoint = function()
	local list = {}
	local point = C_Map and C_Map.GetUserWaypoint and C_Map.GetUserWaypoint()
	if point and point.uiMapID then
		AddAtPos(list, point.uiMapID, point.position, {
			size = 22, title = "Waypoint", lines = { "Ctrl-right-click the map to clear" },
			icon = { atlas = "Waypoint-MapPin-Tracked", color = { 0.2, 0.9, 1 } },
		})
	end
	return list
end

-- Quests you could pick up: the world map's quest offers (C_QuestLine, as
-- its QuestOfferDataProvider reads them). The client fills them in per map
-- once asked (QUESTLINE_UPDATE), so each zone is asked once.
local offersAsked = {}
sources.offers = function(mapID)
	local list, seen = {}, {}
	local Q = C_QuestLine
	if not (Q and Q.GetAvailableQuestLines) then return list end
	local hidden = C_Minimap and C_Minimap.IsTrackingHiddenQuests and SafeCall(C_Minimap.IsTrackingHiddenQuests)
	for _, uiMapID in ipairs(ns.GetQuestMaps(mapID)) do
		if Q.RequestQuestLinesForMap and not offersAsked[uiMapID] then
			offersAsked[uiMapID] = true
			SafeCall(Q.RequestQuestLinesForMap, uiMapID)
		end
		for _, q in ipairs(SafeCall(Q.GetAvailableQuestLines, uiMapID) or {}) do
			if q.questID and not seen[q.questID] and not q.inProgress and (hidden or not q.isHidden) then
				seen[q.questID] = true
				local lines = { "|cff9d9d9dQuest to pick up|r" }
				if q.questLineName and q.questLineName ~= "" and q.questLineName ~= q.questName then
					table.insert(lines, 1, q.questLineName)
				end
				AddAt(list, uiMapID, q.x, q.y, {
					size = 18, title = q.questName or ("Quest " .. q.questID), lines = lines,
					icon = { atlas = "QuestNormal", color = { 1, 0.82, 0 } },
				})
			end
		end
	end
	return list
end

---------------------------------------------------------------------------
-- Party and raid members: dots in their class colours. They walk, so they
-- are moved every frame, apart from the pin layout. (UnitPosition works for
-- them outdoors; instances withhold it.)
---------------------------------------------------------------------------

local GROUP_SIZE = 12
local groupDots = {}

local function GroupDotOnEnter(self)
	local unit = self.unit
	if not (unit and UnitExists(unit)) then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	local _, class = UnitClass(unit)
	local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	GameTooltip:AddLine(UnitName(unit) or "?", c and c.r or 1, c and c.g or 1, c and c.b or 1)
	local level = UnitLevel and UnitLevel(unit)
	local className = UnitClass(unit)
	if level and level > 0 and className then GameTooltip:AddLine((LEVEL or "Level") .. " " .. level .. " " .. className, 1, 1, 1) end
	if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then GameTooltip:AddLine("|cff808080Dead|r") end
	GameTooltip:Show()
end

local function GroupDot(i)
	local dot = groupDots[i]
	if dot then return dot end
	dot = CreateFrame("Frame", nil, canvases.pins)
	dot:SetSize(GROUP_SIZE, GROUP_SIZE)
	dot.ring = dot:CreateTexture(nil, "ARTWORK", nil, 0)
	dot.ring:SetTexture(CIRCLE)
	dot.ring:SetVertexColor(0, 0, 0, 0.9)
	dot.ring:SetPoint("CENTER")
	dot.ring:SetSize(GROUP_SIZE, GROUP_SIZE)
	dot.icon = dot:CreateTexture(nil, "ARTWORK", nil, 1)
	dot.icon:SetTexture(CIRCLE)
	dot.icon:SetPoint("CENTER")
	dot.icon:SetSize(GROUP_SIZE - 3, GROUP_SIZE - 3)
	dot:EnableMouse(true)
	if dot.SetPropagateMouseClicks then dot:SetPropagateMouseClicks(true) end
	dot:SetScript("OnEnter", GroupDotOnEnter)
	dot:SetScript("OnLeave", function() GameTooltip:Hide() end)
	groupDots[i] = dot
	return dot
end

local function Secret(v) return issecretvalue and issecretvalue(v) end

local groupShown = 0
local function UpdateGroup()
	local n = 0
	local members = Enabled("group") and state.map and GetNumGroupMembers and GetNumGroupMembers() or 0
	if members > 0 then
		local raid = IsInRaid and IsInRaid()
		local z = state.zoom
		for i = 1, raid and members or members - 1 do
			local unit = (raid and "raid" or "party") .. i
			if not (UnitIsUnit and UnitIsUnit(unit, "player")) then
				local north, west, _, inst = UnitPosition(unit)
				if north and not Secret(north) and inst == state.map then
					local col, row = ns.WorldToTile(north, west)
					n = n + 1
					local dot = GroupDot(n)
					dot.unit = unit
					local _, class = UnitClass(unit)
					local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
					if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then
						dot.icon:SetVertexColor(0.5, 0.5, 0.5, 1)
					else
						dot.icon:SetVertexColor(c and c.r or 1, c and c.g or 1, c and c.b or 1, 1)
					end
					dot:SetPoint("CENTER", canvases.pins, "TOPLEFT", col * z, -row * z)
					if not dot:IsShown() then dot:Show() end
				end
			end
		end
	end
	for i = n + 1, groupShown do groupDots[i]:Hide() end
	groupShown = n
end
ns.frame:HookScript("OnUpdate", UpdateGroup)

---------------------------------------------------------------------------
-- Quest areas
---------------------------------------------------------------------------

-- QuestPOIFrame draws the game's own objective areas ("blobs") for one uiMap
-- into its rectangle, exactly like the world map's QuestBlobPinTemplate. We
-- size one per map to that map's rectangle in tile space.
local blobFrames = {} -- in use: list of { frame, uiMapID }
local blobPool = {}
local blobSupported

local function NewBlobFrame()
	local ok, f = pcall(CreateFrame, "QuestPOIFrame", nil, canvases.areas)
	if not (ok and f and f.DrawBlob and f.SetMapID) then return nil end
	f:SetFillTexture("Interface\\WorldMap\\UI-QuestBlob-Inside")
	f:SetBorderTexture("Interface\\WorldMap\\UI-QuestBlob-Outside")
	f:SetBorderScalar(1.0)
	-- Hover is worked out from the cursor (OnMapHover); the frame itself must
	-- never take the mouse from the Minimap's blips above it.
	if f.EnableMouse then f:EnableMouse(false) end
	return f
end

-- The quest you follow gets its area drawn plainly; the rest are a faint
-- hint under the map (0-255).
local BLOB_ALPHA = { followed = { 56, 110 }, other = { 14, 32 } }
do
	local probe = NewBlobFrame()
	blobSupported = probe ~= nil
	if probe then
		probe:Hide()
		blobPool[1] = probe
	end
end

-- Does a drawn blob cover this map-normalized point? (What the world map uses for tooltips.)
local function BlobAt(f, x, y)
	if not f.UpdateMouseOverTooltip then return nil end
	local ok, questID = pcall(f.UpdateMouseOverTooltip, f, x, y)
	return ok and questID or nil
end

local approxPending
local LayoutApproxAreas -- forward

local function LayoutQuestAreas()
	local z = state.zoom
	layoutZoom[canvases.areas] = z
	PositionCanvases()
	for _, b in ipairs(blobFrames) do
		b.frame:Hide()
		blobPool[#blobPool + 1] = b.frame
	end
	wipe(blobFrames)

	if blobSupported and Enabled("quests") and Enabled("questAreas") then
		-- One frame per map and style (followed or not): alpha is per frame.
		local groups, followed = {}, FollowedQuest()
		for _, a in ipairs(questAreas) do
			local style = a.questID == followed and "followed" or "other"
			local key = a.uiMapID .. style
			groups[key] = groups[key] or { uiMapID = a.uiMapID, style = style }
			table.insert(groups[key], a.questID)
		end
		for _, quests in pairs(groups) do
			local uiMapID = quests.uiMapID
			local r = ns.MapRect(uiMapID)
			local f = r and (table.remove(blobPool) or NewBlobFrame())
			if f then
				f:SetFillAlpha(BLOB_ALPHA[quests.style][1])
				f:SetBorderAlpha(BLOB_ALPHA[quests.style][2])
				f:SetFrameLevel(canvases.areas:GetFrameLevel() + (quests.style == "followed" and 2 or 1))
				f:ClearAllPoints()
				f:SetPoint("TOPLEFT", canvases.areas, "TOPLEFT", r.col0 * z, -r.row0 * z)
				f:SetSize((r.col1 - r.col0) * z, (r.row1 - r.row0) * z)
				f:SetMapID(uiMapID)
				f:DrawNone()
				for _, questID in ipairs(quests) do f:DrawBlob(questID, true) end
				f:Show()
				blobFrames[#blobFrames + 1] = { frame = f, uiMapID = uiMapID, rect = r }
			end
		end
	end

	-- Which quests actually got an area? Check next frame, once blobs are built.
	if not approxPending then
		approxPending = true
		C_Timer.After(0, function()
			approxPending = nil
			for _, a in ipairs(questAreas) do
				a.hasBlob = false
				for _, b in ipairs(blobFrames) do
					if b.uiMapID == a.uiMapID and BlobAt(b.frame, a.x, a.y) then
						a.hasBlob = true
						break
					end
				end
			end
			LayoutApproxAreas()
		end)
	end
	LayoutApproxAreas()
end

-- Estimated areas for area-type objectives the game has no shape for: a very
-- faint disc with a dashed edge (dashes read as "approximate"). Nearby
-- quests share one circle.
LayoutApproxAreas = function()
	local z = layoutZoom[canvases.areas] or state.zoom
	areaFillPool:Reset()
	if areaLinePool then areaLinePool:Reset() end
	if not (Enabled("quests") and Enabled("questAreasApprox")) then return end

	local centers = {}
	for _, a in ipairs(questAreas) do
		if a.shape == "area" and a.hasBlob == false then
			local merged
			for _, c in ipairs(centers) do
				if math.abs(c.col - a.col) < APPROX_RADIUS * 0.6 and math.abs(c.row - a.row) < APPROX_RADIUS * 0.6 then
					merged = true
					break
				end
			end
			if not merged then centers[#centers + 1] = { col = a.col, row = a.row } end
		end
	end

	local radius = APPROX_RADIUS * z
	local segments = 36
	for _, c in ipairs(centers) do
		local x, y = c.col * z, c.row * z
		local disc = areaFillPool:Get()
		disc:SetTexture(CIRCLE)
		disc:SetVertexColor(1, 0.85, 0.4, 0.05)
		disc:ClearAllPoints()
		disc:SetPoint("CENTER", canvases.areas, "TOPLEFT", x, -y)
		disc:SetSize(radius * 2, radius * 2)
		if areaLinePool then
			for s = 0, segments - 1, 2 do
				local a1 = s / segments * 2 * math.pi
				local a2 = (s + 1.2) / segments * 2 * math.pi
				DrawLine(areaLinePool, canvases.areas,
					x + math.cos(a1) * radius, y + math.sin(a1) * radius,
					x + math.cos(a2) * radius, y + math.sin(a2) * radius,
					1.5, 1, 0.85, 0.4, 0.35)
			end
		end
	end
end

-- Hovering a quest area shows that quest, like the world map does.
local blobTooltipOwner = CreateFrame("Frame", nil, canvases.areas)
-- The quest whose drawn area covers tile (col, row), if any.
local function BlobQuestAt(col, row)
	for _, b in ipairs(blobFrames) do
		local r = b.rect
		if col >= r.col0 and col <= r.col1 and row >= r.row0 and row <= r.row1 then
			local questID = BlobAt(b.frame, (col - r.col0) / (r.col1 - r.col0), (row - r.row0) / (r.row1 - r.row0))
			if questID then return questID end
		end
	end
end

local function ShowBlobTooltip(questID)
	blobTooltipOwner.questID = questID
	GameTooltip:SetOwner(blobTooltipOwner, "ANCHOR_CURSOR_RIGHT", 12, 0)
	GameTooltip:AddLine(SafeCall(C_QuestLog.GetTitleForQuestID, questID) or "Quest")
	for _, line in ipairs(QuestLines(questID, false)) do GameTooltip:AddLine(line, 1, 1, 1, true) end
	GameTooltip:AddLine(FollowHint(questID))
	GameTooltip:Show()
end

-- Who gets GameTooltip over the map: our pins (they take the mouse first),
-- else a Blizzard blip under the cursor, else the quest area. While the
-- Minimap has the mouse (minimap mode), MinimapBlips settles the last two
-- right after Blizzard's own hover handler, every frame, so nothing flickers.
function ns.OnMapHover(col, row)
	if state.minimapHover and Minimap:IsVisible() then return end
	local questID = col and BlobQuestAt(col, row)
	local owner = GameTooltip:GetOwner()
	if questID then
		if owner and owner ~= blobTooltipOwner and GameTooltip:IsShown() then return end -- a pin tooltip wins
		if blobTooltipOwner.questID ~= questID or not GameTooltip:IsShown() or owner ~= blobTooltipOwner then
			ShowBlobTooltip(questID)
		end
	elseif owner == blobTooltipOwner then
		blobTooltipOwner.questID = nil
		GameTooltip:Hide()
	end
end

-- Under the Minimap, with no blip under the cursor: the quest area's tooltip,
-- rebuilt (Blizzard's handler clears GameTooltip every frame). True if shown.
function ns.ShowQuestAreaTooltip(col, row)
	local questID = col and BlobQuestAt(col, row)
	if questID then
		ShowBlobTooltip(questID)
		return true
	end
	if GameTooltip:IsOwned(blobTooltipOwner) then GameTooltip:Hide() end
	blobTooltipOwner.questID = nil
	return false
end

local function RefreshPins(key)
	if sources[key] then
		pinData[key] = (Enabled(key) and state.map) and sources[key](state.map) or nil
		if key == "quests" and not pinData[key] then wipe(questAreas) end
	end
end

-- Follow a quest: track it in the objective tracker and make it the target
-- (super-tracked where the client can). Again to stop.
local function ToggleFollowQuest(questID)
	if FollowedQuest() == questID then
		if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then SafeCall(C_SuperTrack.SetSuperTrackedQuestID, 0) end
		followedQuest = nil
	else
		if C_QuestLog.AddQuestWatch then
			SafeCall(C_QuestLog.AddQuestWatch, questID)
		elseif AddQuestWatch and GetQuestLogIndexByID then
			local index = GetQuestLogIndexByID(questID)
			if index and index > 0 then SafeCall(AddQuestWatch, index) end
			if QuestWatch_Update then SafeCall(QuestWatch_Update) end
		end
		if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then SafeCall(C_SuperTrack.SetSuperTrackedQuestID, questID) end
		followedQuest = questID
	end
	RefreshPins("quests")
	LayoutPins()
	LayoutQuestAreas()
	if ns.UpdateControls then ns.UpdateControls() end
end

-- A quick click on the map (Core): a quest pin, or (if allowAreas) a quest's
-- area, toggles following it. Returns true if it was one.
function ns.OnMapTap(col, row, allowAreas)
	for i = 1, pinPool.used do
		local pin = pinPool.list[i]
		local e = pin.entry
		if e and e.questID and pin:IsShown() and pin:IsMouseOver() then
			ToggleFollowQuest(e.questID)
			return true
		end
	end
	local questID = allowAreas and BlobQuestAt(col, row)
	if questID then
		ToggleFollowQuest(questID)
		return true
	end
	return false
end

-- Is this quest's turn-in drawn by our quests layer (AddonPins.lua skips
-- other addons' copies of it)?
function ns.ShowsTurnIn(questID)
	for _, e in ipairs(pinData.quests or {}) do
		if e.questID == questID and e.turnIn then return true end
	end
	return false
end

-- What path mode frames with you: the quest you follow if it's on this map,
-- else your waypoint. { col, row, title } (reused), or nil.
local target = {}
function ns.GetTarget()
	local followed = FollowedQuest()
	local found = IsGhost() and pinData.corpse and pinData.corpse[1]
	if not found and followed then
		for _, e in ipairs(pinData.quests or {}) do
			if e.questID == followed then found = e break end
		end
	end
	found = found or (pinData.waypoint and pinData.waypoint[1])
	if not found then return nil end
	target.col, target.row, target.title = found.col, found.row, found.title
	return target
end

-- Which target you have, wherever it is: a key that changes when you follow
-- another quest or move the waypoint, nil with none (Core's path mode keys
-- off it).
function ns.TargetKey()
	if not IsGhost() then corpseFound = nil end
	if corpseFound then return "corpse", true end -- true: back to following you
	local followed = FollowedQuest()
	if followed then return "quest:" .. followed end
	local point = C_Map and C_Map.GetUserWaypoint and C_Map.GetUserWaypoint()
	if point and point.uiMapID then
		local x, y = PosXY(point.position)
		return string.format("waypoint:%d:%.4f:%.4f", point.uiMapID, x or 0, y or 0)
	end
end

-- Register a layer (fields as in LAYERS, plus optional onToggle(on), called
-- after its setting changes). Works at file load and at runtime, e.g. once
-- another addon turns up: after login its setting starts from the default.
-- Again with the same key updates the existing entry.
function ns.AddLayer(layer)
	local cur = layerByKey[layer.key]
	if cur then
		for k, v in pairs(layer) do cur[k] = v end
		layer = cur
	else
		table.insert(LAYERS, layer)
		layerByKey[layer.key] = layer
	end
	if db and db.layers[layer.key] == nil then db.layers[layer.key] = layer.default end
	return layer
end

-- Extra pin layers (Landmarks.lua): the same, with a pin source.
function ns.AddPinLayer(layer, source)
	sources[layer.key] = source
	ns.AddLayer(layer)
end

-- Add an entry at a tile position if it's on the displayed continent.
function ns.PinAtTile(list, inst, col, row, entry)
	if inst ~= state.map then return nil end
	entry.col, entry.row = col, row
	list[#list + 1] = entry
	return entry
end

local function RefreshAllPins()
	for key in pairs(sources) do RefreshPins(key) end
	LayoutPins()
	LayoutQuestAreas()
end

-- Coalesce bursts of events (QUEST_LOG_UPDATE fires a lot).
local pendingRefresh = {}
local function ScheduleRefresh(key)
	if pendingRefresh[key] then return end
	pendingRefresh[key] = true
	C_Timer.After(0.3, function()
		pendingRefresh[key] = nil
		RefreshPins(key)
		LayoutPins()
		if key == "quests" then LayoutQuestAreas() end
	end)
end

function ns.RefreshLayer(key) ScheduleRefresh(key) end

---------------------------------------------------------------------------
-- Grid sampling and border tracing
---------------------------------------------------------------------------

local grids = {} -- instanceID -> grid
local jobs = {}  -- queue of coroutines, one resumed per frame

local function RunJob(fn)
	jobs[#jobs + 1] = coroutine.create(fn)
end

-- Budgeted sampler: yields every SAMPLES_PER_FRAME calls.
local sampleCount = 0
local function ZoneIdAt(grid, col, row)
	sampleCount = sampleCount + 1
	if sampleCount % SAMPLES_PER_FRAME == 0 then coroutine.yield() end
	local x, y = ns.TileToMap(grid.cont, col, row)
	local info = x and SafeCall(C_Map.GetMapInfoAtPosition, grid.cont, x, y)
	return (info and info.mapID ~= grid.cont) and info.mapID or 0
end

local function SamplePos(grid, i, j)
	return grid.c0 + (i + 0.5) * CELL, grid.r0 + (j + 0.5) * CELL
end

local function SampleZones(grid)
	for j = 0, grid.nr - 1 do
		for i = 0, grid.nc - 1 do
			grid.ids[j * grid.nc + i + 1] = ZoneIdAt(grid, SamplePos(grid, i, j))
		end
	end
end

-- Some ground belongs to no zone map, which leaves gaps and dead-ends in the
-- borders. Fill unassigned cells that sit *between* zones (zone cells on both
-- sides within GAP_FILL_CELLS, horizontally or vertically) with the nearest
-- zone. Coasts have zone on one side only, so borders don't bleed into the sea.
local function FillGaps(grid)
	local ids, nc, nr = grid.ids, grid.nc, grid.nr
	local original = {}
	for k = 1, nc * nr do original[k] = ids[k] end
	local function Orig(i, j)
		if i < 0 or i >= nc or j < 0 or j >= nr then return 0 end
		return original[j * nc + i + 1]
	end
	local function Sandwiched(i, j)
		local l, r, u, d
		for s = 1, GAP_FILL_CELLS do
			l = l or (Orig(i - s, j) ~= 0 and s)
			r = r or (Orig(i + s, j) ~= 0 and s)
			u = u or (Orig(i, j - s) ~= 0 and s)
			d = d or (Orig(i, j + s) ~= 0 and s)
		end
		return (l and r) or (u and d)
	end
	local queue, head, dist = {}, 1, {}
	for k = 1, nc * nr do
		if original[k] ~= 0 then queue[#queue + 1] = k; dist[k] = 0 end
	end
	while head <= #queue do
		local k = queue[head]
		head = head + 1
		if dist[k] < GAP_FILL_CELLS then
			local i, j = (k - 1) % nc, math.floor((k - 1) / nc)
			for _, o in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
				local ni, nj = i + o[1], j + o[2]
				if ni >= 0 and ni < nc and nj >= 0 and nj < nr then
					local nk = nj * nc + ni + 1
					if not dist[nk] and Sandwiched(ni, nj) then
						ids[nk] = ids[k]
						dist[nk] = dist[k] + 1
						queue[#queue + 1] = nk
					end
				end
			end
		end
		if head % 4000 == 0 then coroutine.yield() end
	end
end

-- The zone lookup flickers near some borders (a sample of zone B inside A, a
-- lone unzoned sample). Each flicker splits a border into dashes, so smooth
-- the grid with one pass of a 3x3 majority filter first. Zones only replace
-- "no zone" when clearly surrounded, and a zone speck only clears into "no
-- zone" when it's nearly isolated, so coastlines stay put.
local function MajorityFilter(grid)
	local ids, nc, nr = grid.ids, grid.nc, grid.nr
	local out = {}
	local counts = {}
	for j = 0, nr - 1 do
		for i = 0, nc - 1 do
			local k = j * nc + i + 1
			wipe(counts)
			for dj = -1, 1 do
				for di = -1, 1 do
					local ii, jj = i + di, j + dj
					local id = (ii >= 0 and ii < nc and jj >= 0 and jj < nr) and ids[jj * nc + ii + 1] or 0
					counts[id] = (counts[id] or 0) + 1
				end
			end
			local best, bestN = ids[k], 0
			for id, n in pairs(counts) do
				if n > bestN then best, bestN = id, n end
			end
			local cur = ids[k]
			if best ~= cur and ((cur == 0 and bestN >= 6) or (best == 0 and bestN >= 7) or (cur ~= 0 and best ~= 0 and bestN >= 5)) then
				out[k] = best
			else
				out[k] = cur
			end
			if k % 4000 == 0 then coroutine.yield() end
		end
	end
	grid.ids = out
end

-- Douglas-Peucker on a flat list { c1, r1, c2, r2, ... }.
local function Simplify(pts, tol)
	local n = #pts / 2
	if n <= 2 then return pts end
	local keep = { [1] = true, [n] = true }
	local stack = { { 1, n } }
	while #stack > 0 do
		local s = table.remove(stack)
		local a, b = s[1], s[2]
		local ax, ay, bx, by = pts[a * 2 - 1], pts[a * 2], pts[b * 2 - 1], pts[b * 2]
		local dx, dy = bx - ax, by - ay
		local len = math.sqrt(dx * dx + dy * dy)
		local worst, worstD = nil, tol
		for k = a + 1, b - 1 do
			local px, py = pts[k * 2 - 1], pts[k * 2]
			local d
			if len < 1e-9 then
				d = math.sqrt((px - ax) ^ 2 + (py - ay) ^ 2)
			else
				d = math.abs(dy * px - dx * py + bx * ay - by * ax) / len
			end
			if d > worstD then worst, worstD = k, d end
		end
		if worst then
			keep[worst] = true
			stack[#stack + 1] = { a, worst }
			stack[#stack + 1] = { worst, b }
		end
	end
	local out = {}
	for k = 1, n do
		if keep[k] then
			out[#out + 1] = pts[k * 2 - 1]
			out[#out + 1] = pts[k * 2]
		end
	end
	return out
end

-- One round of Chaikin corner cutting; endpoints stay put so chains still meet at junctions.
local function Smooth(pts)
	local n = #pts / 2
	if n < 3 then return pts end
	local out = { pts[1], pts[2] }
	for k = 1, n - 1 do
		local x1, y1, x2, y2 = pts[k * 2 - 1], pts[k * 2], pts[k * 2 + 1], pts[k * 2 + 2]
		out[#out + 1] = 0.75 * x1 + 0.25 * x2
		out[#out + 1] = 0.75 * y1 + 0.25 * y2
		out[#out + 1] = 0.25 * x1 + 0.75 * x2
		out[#out + 1] = 0.25 * y1 + 0.75 * y2
	end
	out[#out + 1], out[#out + 2] = pts[n * 2 - 1], pts[n * 2]
	return out
end

-- Multi-label marching squares over the sample grid. Crossing points sit on
-- grid edges between two different zones and are refined by bisection; a
-- square with 2 crossings joins them, 1 or 3+ join each to the square centre.
local function TraceBorders(grid)
	local ids, nc, nr = grid.ids, grid.nc, grid.nr
	local nodePos = {} -- key -> { c, r }
	local nodeZones = {} -- crossing key -> { zoneA, zoneB }
	local adj = {}     -- key -> { edge indices }
	local edges = {}

	local function Id(i, j) return ids[j * nc + i + 1] end

	-- Crossing on the grid edge from sample (i1,j1) to (i2,j2), or nil.
	local function Crossing(key, i1, j1, i2, j2)
		if nodePos[key] ~= nil then return nodePos[key] and key or nil end
		local a, b = Id(i1, j1), Id(i2, j2)
		if a == 0 or b == 0 or a == b then
			nodePos[key] = false
			return nil
		end
		local c1, r1 = SamplePos(grid, i1, j1)
		local c2, r2 = SamplePos(grid, i2, j2)
		for _ = 1, REFINE_STEPS do
			local mc, mr = (c1 + c2) / 2, (r1 + r2) / 2
			if ZoneIdAt(grid, mc, mr) == a then c1, r1 = mc, mr else c2, r2 = mc, mr end
		end
		nodePos[key] = { (c1 + c2) / 2, (r1 + r2) / 2 }
		nodeZones[key] = { a, b }
		return key
	end

	local function Link(k1, k2)
		edges[#edges + 1] = { k1, k2 }
		adj[k1] = adj[k1] or {}
		adj[k2] = adj[k2] or {}
		table.insert(adj[k1], #edges)
		table.insert(adj[k2], #edges)
	end

	local found = {}
	for j = 0, nr - 2 do
		for i = 0, nc - 2 do
			local base = (j * nc + i) * 3
			wipe(found)
			local top = Crossing(base, i, j, i + 1, j)                        -- H(i,j)
			local bottom = Crossing(((j + 1) * nc + i) * 3, i, j + 1, i + 1, j + 1) -- H(i,j+1)
			local left = Crossing(base + 1, i, j, i, j + 1)                  -- V(i,j)
			local right = Crossing((j * nc + i + 1) * 3 + 1, i + 1, j, i + 1, j + 1) -- V(i+1,j)
			if top then found[#found + 1] = top end
			if bottom then found[#found + 1] = bottom end
			if left then found[#found + 1] = left end
			if right then found[#found + 1] = right end
			if #found == 2 then
				Link(found[1], found[2])
			elseif #found > 0 then
				local center = base + 2
				local c, r = SamplePos(grid, i + 0.5, j + 0.5)
				nodePos[center] = { c, r }
				for _, k in ipairs(found) do Link(k, center) end
			end
		end
	end

	-- Walk edges into chains that break at junctions and dead ends.
	local used = {}
	local chains, chainZones = {}, {}
	local function Walk(start, e)
		local pts = { nodePos[start][1], nodePos[start][2] }
		local zones = {}
		local node = start
		while e and not used[e] do
			used[e] = true
			local ed = edges[e]
			node = (ed[1] == node) and ed[2] or ed[1]
			pts[#pts + 1] = nodePos[node][1]
			pts[#pts + 1] = nodePos[node][2]
			local nz = nodeZones[node]
			if nz then zones[nz[1]], zones[nz[2]] = true, true end
			local list = adj[node]
			if #list ~= 2 then break end
			e = used[list[1]] and list[2] or list[1]
		end
		-- Drop slivers: tiny dangling fragments (e.g. specks out at sea) read as
		-- noise. Short pieces between two junctions are real borders; keep those.
		local dangling = #adj[start] == 1 or #adj[node] == 1
		local len = 0
		for k = 1, #pts / 2 - 1 do
			len = len + math.sqrt((pts[k * 2 + 1] - pts[k * 2 - 1]) ^ 2 + (pts[k * 2 + 2] - pts[k * 2]) ^ 2)
		end
		if not dangling or len >= CELL * 2.5 then
			chains[#chains + 1] = pts
			chainZones[#chains] = zones
		end
	end
	for key, list in pairs(adj) do
		if #list ~= 2 then
			for _, e in ipairs(list) do
				if not used[e] then Walk(key, e) end
			end
		end
	end
	for e = 1, #edges do -- closed loops (islands, enclaves)
		if not used[e] then Walk(edges[e][1], e) end
	end
	grid.rawChains = chains
	grid.chainZones = chainZones -- which zones each chain separates (for hover highlight)
	grid.lod = {}
end

-- Border detail follows zoom: about a pixel of tolerance, bucketed and cached.
local LOD_LEVELS = { 0.006, 0.015, 0.035, 0.08, 0.2 }
local function ChainsForZoom(grid, z)
	if not grid.rawChains then return nil end
	local tol = 0.9 / z
	local level = LOD_LEVELS[1]
	for _, l in ipairs(LOD_LEVELS) do
		if l <= tol then level = l end
	end
	local chains = grid.lod[level]
	if not chains then
		chains = {}
		for i, pts in ipairs(grid.rawChains) do
			chains[i] = Smooth(Simplify(pts, level))
		end
		grid.lod[level] = chains
	end
	return chains
end

-- Label anchors: the cell deepest inside each zone (farthest from any border),
-- found with a multi-source BFS distance transform. Centroids of concave zones
-- can fall outside the zone; this can't. Weight = zone size, for priority.
local function BuildLabels(grid)
	local ids, nc, nr = grid.ids, grid.nc, grid.nr
	local dist, queue, head = {}, {}, 1
	local counts = {}
	for j = 0, nr - 1 do
		for i = 0, nc - 1 do
			local k = j * nc + i + 1
			local id = ids[k]
			if id ~= 0 then
				counts[id] = (counts[id] or 0) + 1
				local edge = i == 0 or j == 0 or i == nc - 1 or j == nr - 1
					or ids[k - 1] ~= id or ids[k + 1] ~= id or ids[k - nc] ~= id or ids[k + nc] ~= id
				if edge then
					dist[k] = 0
					queue[#queue + 1] = k
				end
			end
		end
	end
	while head <= #queue do
		local k = queue[head]
		head = head + 1
		local i = (k - 1) % nc
		for _, nk in ipairs({ i > 0 and k - 1, i < nc - 1 and k + 1, k - nc, k + nc }) do
			if nk and nk >= 1 and nk <= nc * nr and not dist[nk] and ids[nk] == ids[k] then
				dist[nk] = dist[k] + 1
				queue[#queue + 1] = nk
			end
		end
		if head % 4000 == 0 then coroutine.yield() end
	end
	local best = {}
	for k, d in pairs(dist) do
		local id = ids[k]
		if not best[id] or d > best[id].d then best[id] = { k = k, d = d } end
	end
	local labels = {}
	for id, b in pairs(best) do
		local info = C_Map.GetMapInfo(id)
		if info and counts[id] >= 12 then
			local col, row = SamplePos(grid, (b.k - 1) % nc, math.floor((b.k - 1) / nc))
			labels[#labels + 1] = { id = id, name = info.name, col = col, row = row, weight = counts[id] }
		end
	end
	table.sort(labels, function(a, b) return a.weight > b.weight end)
	grid.labels = labels
end

local function SampleExploration(grid)
	local explored = C_MapExplorationInfo and C_MapExplorationInfo.GetExploredAreaIDsAtPosition
	if not explored then grid.shade = {} return end
	local shade = {}
	for j = 0, grid.nr - 1 do
		local start
		for i = 0, grid.nc do
			local dark = false
			if i < grid.nc then
				local id = grid.ids[j * grid.nc + i + 1]
				if id ~= 0 then
					local col, row = SamplePos(grid, i, j)
					local x, y = ns.TileToMap(id, col, row)
					local areas = x and SafeCall(explored, id, MapPos(x, y))
					dark = not areas or #areas == 0
					sampleCount = sampleCount + 1
					if sampleCount % SAMPLES_PER_FRAME == 0 then coroutine.yield() end
				end
			end
			if dark and not start then start = i
			elseif not dark and start then
				shade[#shade + 1] = { grid.c0 + start * CELL, grid.r0 + j * CELL, (i - start) * CELL, CELL }
				start = nil
			end
		end
	end
	grid.shade = shade
end

local LayoutStatic -- forward

local function EnsureGrid(mapID)
	-- The sampled grid feeds unexplored shading, and borders/labels on maps
	-- without generated border data.
	local hasOffline = MagicMap_Borders and MagicMap_Borders[mapID]
	local needZones = Enabled("unexplored") or (not hasOffline and (Enabled("zoneBorders") or Enabled("zoneLabels")))
	if not (mapID and needZones and C_Map and C_Map.GetMapInfoAtPosition) then return end
	local grid = grids[mapID]
	if not grid then
		local cont = ns.GetContinentMapID(mapID)
		local r = cont and ns.MapRect(cont)
		if not r then return end
		grid = {
			cont = cont, c0 = r.col0, r0 = r.row0,
			nc = math.ceil((r.col1 - r.col0) / CELL), nr = math.ceil((r.row1 - r.row0) / CELL),
			ids = {},
		}
		grids[mapID] = grid
		RunJob(function()
			SampleZones(grid)
			BuildLabels(grid)
			FillGaps(grid)
			MajorityFilter(grid)
			grid.zonesDone = true
			if state.map == mapID then LayoutStatic() end
			if hasLines then
				TraceBorders(grid)
				if state.map == mapID then LayoutStatic() end
			end
		end)
	end
	if Enabled("unexplored") and (not grid.shade or grid.shadeStale) and not grid.shadeQueued then
		grid.shadeStale = nil
		grid.shadeQueued = true
		RunJob(function()
			while not grid.zonesDone do coroutine.yield() end
			SampleExploration(grid)
			grid.shadeQueued = nil
			if state.map == mapID then LayoutStatic() end
		end)
	end
end

local jobRunner = CreateFrame("Frame")
jobRunner:SetScript("OnUpdate", function()
	local job = jobs[1]
	if not job then return end
	local ok, err = coroutine.resume(job)
	if not ok then
		ns.Print("layer sampling failed: " .. tostring(err))
		table.remove(jobs, 1)
	elseif coroutine.status(job) == "dead" then
		table.remove(jobs, 1)
	end
end)

---------------------------------------------------------------------------
-- Static layout (re-run on zoom change or new data; panning moves canvases)
--
-- Borders come from Data/Borders_<product>.lua when present: exact zone and
-- subzone outlines traced from the terrain's own area data (see
-- tools/gen_borders.pl). Otherwise they're traced at runtime from the
-- sampled zone grid above.
---------------------------------------------------------------------------

local LABEL_FONT = (GameFontNormal and GameFontNormal:GetFont()) or STANDARD_TEXT_FONT
local LABEL_COLOR = { 1, 0.87, 0.55 }
local LABEL_HOVER = { 1, 1, 0.85 }
local SUBLABEL_COLOR = { 0.93, 0.89, 0.8 }
local SUBZONE_LINE_MIN_ZOOM = 140  -- subzone outlines appear from about here
local SUBZONE_TOL = 0.035          -- tiles: melts the 33-yard steps of subzone outlines into diagonals
local SUBZONE_LABEL_MIN_ZOOM = 200 -- ...and their names from here (zone names hide)
local labelByZone = {} -- hover key -> placed label
local hoverZone        -- zone uiMapID highlighted for click-to-zone

local function Overlaps(boxes, x0, y0, x1, y1)
	for _, b in ipairs(boxes) do
		if x0 < b[3] and x1 > b[1] and y0 < b[4] and y1 > b[2] then return true end
	end
	return false
end

-- Place a label at tile (col, row) unless it collides; tries just above/below
-- first. Placed labels are remembered (placedLabels) so zooming can move them.
local placedLabels = {}
local function PlaceLabel(pool, placed, text, col, row, z, size, color)
	local x, y = col * z, row * z
	local fs = pool:Get()
	fs:SetFont(LABEL_FONT, size, "")
	fs:SetTextColor(unpack(color))
	fs:SetText(text)
	local w, h = fs:GetStringWidth(), fs:GetStringHeight()
	for _, dy in ipairs({ 0, -(h + 3), h + 3 }) do
		local x0, y0, x1, y1 = x - w / 2 - 4, y + dy - h / 2 - 2, x + w / 2 + 4, y + dy + h / 2 + 2
		if not Overlaps(placed, x0, y0, x1, y1) then
			placed[#placed + 1] = { x0, y0, x1, y1 }
			fs:ClearAllPoints()
			fs:SetPoint("CENTER", canvases.labels, "TOPLEFT", x, -(y + dy))
			fs.col, fs.row, fs.dy = col, row, dy
			placedLabels[#placedLabels + 1] = fs
			return fs
		end
	end
	pool:Unget()
end

-- Offline borders for a map, prepared once: smoothed polylines with bounding
-- boxes, and labels with their (localized) names.
local function OfflineBorders(mapID)
	local data = MagicMap_Borders and MagicMap_Borders[mapID]
	if not data or data.prepared then return data end
	data.zoneLines, data.subLines = {}, {}
	for _, l in ipairs(data.lines) do
		local pts = {}
		for i = 6, #l do pts[#pts + 1] = l[i] end
		local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
		for i = 1, #pts, 2 do
			x0, x1 = math.min(x0, pts[i]), math.max(x1, pts[i])
			y0, y1 = math.min(y0, pts[i + 1]), math.max(y1, pts[i + 1])
		end
		local entry = { a = l[2], b = l[3], fadeStart = l[4] == 1, fadeEnd = l[5] == 1, raw = pts, lod = {},
			x0 = x0, y0 = y0, x1 = x1, y1 = y1 }
		table.insert(l[1] == 1 and data.zoneLines or data.subLines, entry)
	end
	data.zoneLabels, data.subLabels, data.zoneAreaByName = {}, {}, {}
	for _, l in ipairs(data.labels) do
		local name = C_Map.GetAreaInfo and C_Map.GetAreaInfo(l[1])
		if name and name ~= "" then
			local entry = { id = l[1], col = l[2], row = l[3], weight = l[4], name = name }
			if l[5] == 1 then
				table.insert(data.zoneLabels, entry)
				data.zoneAreaByName[name] = l[1]
			else
				table.insert(data.subLabels, entry)
			end
		end
	end
	local byWeight = function(a, b) return a.weight > b.weight end
	table.sort(data.zoneLabels, byWeight)
	table.sort(data.subLabels, byWeight)
	data.prepared = true
	return data
end

-- A border's points for this zoom: simplified to about a pixel (or `minTol`
-- tiles, which lets subzones collapse their 33-yard steps into diagonals),
-- then rounded off when zoomed in. Cached per zoom band.
local LOD_BUCKETS = { 0.004, 0.008, 0.016, 0.032, 0.064, 0.128, 0.256 }
local function LinePts(l, z, minTol)
	local tol = math.max(1.2 / z, minTol or 0)
	local bucket = LOD_BUCKETS[1]
	for _, b in ipairs(LOD_BUCKETS) do
		if b <= tol then bucket = b end
	end
	local smooth = z >= 250 and 2 or (z >= 70 and 1 or 0)
	local key = bucket * 10 + smooth
	local pts = l.lod[key]
	if not pts then
		pts = Simplify(l.raw, bucket)
		for _ = 1, smooth do pts = Smooth(pts) end
		l.lod[key] = pts
	end
	return pts
end

-- Hover keys: uiMapIDs for the sampled grid, AreaTable IDs for offline data.
local function HoverKey(uiMapID)
	if not uiMapID then return nil end
	local data = OfflineBorders(state.map)
	if not data then return uiMapID end
	local info = C_Map.GetMapInfo(uiMapID)
	return info and data.zoneAreaByName[info.name]
end

-- A polyline in tile units. Ends marked as dead ends break into shrinking
-- dashes and fade out over the last FADE_PX, instead of stopping bluntly.
local FADE_PX, DASH_PX, GAP_PX = 36, 5, 4
local MIN_SEG_PX = 2.5
local function DrawPolyline(pool, canvas, pts, z, thick, r, g, b, a, fadeStart, fadeEnd)
	-- Screen-space points, merging any closer than MIN_SEG_PX to the last one kept
	-- (far out, most of a detailed border would otherwise be sub-pixel segments).
	local xs, ys = {}, {}
	local n = #pts / 2
	for k = 1, n do
		local x, y = pts[k * 2 - 1] * z, pts[k * 2] * z
		local m = #xs
		if m == 0 or k == n or (x - xs[m]) ^ 2 + (y - ys[m]) ^ 2 >= MIN_SEG_PX * MIN_SEG_PX then
			xs[m + 1], ys[m + 1] = x, y
		end
	end
	n = #xs
	if n < 2 then return end
	local lens, total = {}, 0
	for k = 1, n - 1 do
		local d = math.sqrt((xs[k + 1] - xs[k]) ^ 2 + (ys[k + 1] - ys[k]) ^ 2)
		lens[k] = d
		total = total + d
	end
	local fade = math.min(FADE_PX, total / 2)
	local along = 0
	for k = 1, n - 1 do
		if pool:Full() then return end
		local x1, y1, x2, y2 = xs[k], ys[k], xs[k + 1], ys[k + 1]
		local d = lens[k]
		local inFade = (fadeStart and along < fade) or (fadeEnd and total - along - d < fade)
		if not inFade or d <= 0 then
			DrawLine(pool, canvas, x1, y1, x2, y2, thick, r, g, b, a)
		else
			local t = 0
			while t < d do
				local t2 = math.min(d, t + DASH_PX)
				local mid = along + (t + t2) / 2
				local f = 1
				if fadeStart then f = math.min(f, mid / fade) end
				if fadeEnd then f = math.min(f, (total - mid) / fade) end
				if f > 0.08 then
					DrawLine(pool, canvas, x1 + (x2 - x1) * t / d, y1 + (y2 - y1) * t / d,
						x1 + (x2 - x1) * t2 / d, y1 + (y2 - y1) * t2 / d, thick * (0.6 + 0.4 * f), r, g, b, a * f)
				end
				t = t2 + GAP_PX
			end
		end
		along = along + d
	end
end

-- Refined, quiet styling: zones a thin warm line on a soft shadow;
-- subzones a faint hairline.
local function ZoneLineStyle(z) return math.max(1.1, math.min(1.8, z / 140)), 1, 0.9, 0.72, 0.6 end
local function SubLineStyle(z) return math.max(0.8, math.min(1.1, z / 300)), 1, 0.95, 0.85, 0.22 end

-- Subzone names are dense, so only those near the view are placed; panning
-- past that region places them again (see OnViewChanged).
local subLabelPool = Pool(function() return canvases.labels:CreateFontString(nil, "OVERLAY") end)
local staticPending -- a layout was skipped while the window was hidden

local function ViewRect(margin, z, cx, cy)
	local w, h = ns.viewport:GetSize()
	z, cx, cy = z or state.zoom, cx or state.cx, cy or state.cy
	local hw, hh = w / 2 / z * (1 + margin), h / 2 / z * (1 + margin)
	return cx - hw, cy - hh, cx + hw, cy + hh
end

local function Contains(region, c0, r0, c1, r1)
	return region ~= nil and c0 >= region[1] and r0 >= region[2] and c1 <= region[3] and r1 <= region[4]
end

---------------------------------------------------------------------------
-- Labels: placed (with collisions) at one zoom, then just moved as the zoom
-- changes, until it drifts too far or settles. Names that weren't showing
-- before a placement fade in instead of popping.
---------------------------------------------------------------------------

local LABEL_FADE = 0.2
local labelZoom, labelRegion
local shownNames = {}   -- names on screen after the last placement
local fadingLabels = {} -- font string -> true while it fades in

local function PositionLabels()
	local z = state.zoom
	for _, fs in ipairs(placedLabels) do
		fs:SetPoint("CENTER", canvases.labels, "TOPLEFT", fs.col * z, -(fs.row * z + fs.dy))
	end
end

-- Subzone names within the label region.
local function LayoutSubzoneLabels(z)
	subLabelPool:Reset()
	if not Enabled("zoneLabels") or z < SUBZONE_LABEL_MIN_ZOOM then return end
	local c0, r0, c1, r1 = unpack(labelRegion)
	local placed = {}
	local data = OfflineBorders(state.map)
	for _, l in ipairs(data and data.subLabels or {}) do
		-- Small places only once you're close.
		local minZoom = l.weight >= 40 and SUBZONE_LABEL_MIN_ZOOM or (l.weight >= 15 and 350 or 600)
		if z >= minZoom and l.col >= c0 and l.col <= c1 and l.row >= r0 and l.row <= r1 then
			local fs = PlaceLabel(subLabelPool, placed, l.name, l.col, l.row, z, 11, SUBLABEL_COLOR)
			if fs then fs:SetShadowOffset(1, -1); fs:SetShadowColor(0, 0, 0, 1) end
		end
	end
end

-- Zone and subzone names at the current zoom.
local function LayoutLabels()
	labelPool:Reset()
	wipe(labelByZone)
	wipe(placedLabels)
	local z = state.zoom
	labelZoom = z
	labelRegion = { ViewRect(1.0) }
	local grid = state.map and grids[state.map]
	if Enabled("zoneLabels") and z <= LABEL_MAX_ZOOM then
		local data = OfflineBorders(state.map)
		local labels = {}
		for _, l in ipairs(data and data.zoneLabels or (grid and grid.labels) or {}) do labels[#labels + 1] = l end
		table.sort(labels, function(a, b) return a.weight > b.weight end)
		if #labels == 0 then -- fall back to zone rectangle centres until sampling finishes
			for _, zone in ipairs(ns.GetZones(state.map)) do
				labels[#labels + 1] = { id = zone.uiMapID, name = zone.name, col = (zone.col0 + zone.col1) / 2, row = (zone.row0 + zone.row1) / 2,
					weight = (zone.col1 - zone.col0) * (zone.row1 - zone.row0) }
			end
			table.sort(labels, function(a, b) return a.weight > b.weight end)
		end
		-- Biggest zones first; a label that would collide is skipped until you zoom in.
		local size = z < 48 and 11 or 12
		local hover = HoverKey(hoverZone)
		local placed = {}
		for _, l in ipairs(labels) do
			local fs = PlaceLabel(labelPool, placed, l.name, l.col, l.row, z, size,
				l.id == hover and LABEL_HOVER or LABEL_COLOR)
			if fs and l.id then labelByZone[l.id] = fs end
		end
	end
	LayoutSubzoneLabels(z)

	local now = {}
	wipe(fadingLabels)
	for _, fs in ipairs(placedLabels) do
		local name = fs:GetText()
		now[name] = true
		if shownNames[name] then
			fs:SetAlpha(1)
		else
			fs:SetAlpha(0)
			fadingLabels[fs] = true
		end
	end
	shownNames = now
end

---------------------------------------------------------------------------
-- Borders: built for where the camera is headed, a slice per frame, into the
-- back buffer, then swapped to the front and cross-faded in.
---------------------------------------------------------------------------

local CROSSFADE = 0.12
local REBUILD_DRIFT = 0.02 -- a layout within 2% of the wanted zoom will do
local function SameZoom(a, b)
	return math.abs(math.log(a / b)) < REBUILD_DRIFT
end

-- Builds cover the view plus REGION (in half-views) on every side. The next
-- one starts while the view still has PREFETCH of drawn border around it, so
-- a pan finds it ready instead of running off the edge first.
local REGION, PREFETCH = 1.0, 0.6
-- Past this share of a pool's cap, panning rebuilds instead of extending.
local EXTEND_MAX_FILL = 0.85

-- Zone borders and subzone outlines within `region`, at zoom z, into buf.
-- Runs inside the builder coroutine (DrawLine yields). extend: add to what
-- buf already shows (at this zoom) just the lines it doesn't have yet.
local function BuildBorders(buf, z, region, extend, b)
	if not hasLines then return end
	if not extend then
		buf.sub:Begin()
		buf.shadow:Begin()
		buf.border:Begin()
		buf.highlight:Reset()
		buf.drawn, buf.full = {}, nil
	end
	local drawn = buf.drawn
	-- An extension yields only between whole lines, so dropping it never
	-- leaves half of one; one that runs out of lines stops (see the runner)
	-- rather than remember lines it couldn't draw.
	local function Room()
		if not extend then return true end
		if buf.sub:Full() or buf.shadow:Full() or buf.border:Full() then
			b.overflow = true
			return false
		end
		MaybeYield(true)
		return true
	end
	if Enabled("zoneBorders") then
		local c0, r0, c1, r1 = unpack(region)
		local c = buf.canvas
		local thick, r, g, b, a = ZoneLineStyle(z)
		local data = OfflineBorders(state.map)
		local grid = state.map and grids[state.map]
		if data then
			for _, l in ipairs(data.zoneLines) do
				if not drawn[l] and l.x1 >= c0 and l.x0 <= c1 and l.y1 >= r0 and l.y0 <= r1 then
					if not Room() then return end
					drawn[l] = true
					local pts = LinePts(l, z)
					-- The soft shadow only matters close up.
					if z >= 60 then
						DrawPolyline(buf.shadow, c, pts, z, thick + 1.2, 0, 0, 0, 0.25, l.fadeStart, l.fadeEnd)
					end
					DrawPolyline(buf.border, c, pts, z, thick, r, g, b, a, l.fadeStart, l.fadeEnd)
				end
			end
		elseif grid and not extend then
			for _, pts in ipairs(ChainsForZoom(grid, z) or {}) do
				DrawPolyline(buf.shadow, c, pts, z, thick + 1.2, 0, 0, 0, 0.25)
				DrawPolyline(buf.border, c, pts, z, thick, r, g, b, a)
			end
		end
		if z >= SUBZONE_LINE_MIN_ZOOM then
			thick, r, g, b, a = SubLineStyle(z)
			for _, l in ipairs(data and data.subLines or {}) do
				if not drawn[l] and l.x1 >= c0 and l.x0 <= c1 and l.y1 >= r0 and l.y0 <= r1 then
					if not Room() then return end
					drawn[l] = true
					DrawPolyline(buf.sub, c, LinePts(l, z, SUBZONE_TOL), z, thick, r, g, b, a, false, false)
				end
			end
		end
	end
	if not extend then
		buf.sub:Finish()
		buf.shadow:Finish()
		buf.border:Finish()
	end
end

-- Unexplored shading (a few hundred rectangles; cheap), at zoom z.
local function LayoutShade(z)
	shadePool:Reset()
	layoutZoom[canvases.shade] = z
	local grid = state.map and grids[state.map]
	if not (Enabled("unexplored") and grid and grid.shade) then return end
	for _, r in ipairs(grid.shade) do
		local t = shadePool:Get()
		t:SetColorTexture(0, 0, 0, 0.55)
		t:ClearAllPoints()
		t:SetPoint("TOPLEFT", canvases.shade, "TOPLEFT", r[1] * z, -r[2] * z)
		t:SetSize(r[3] * z + 0.5, r[4] * z + 0.5)
	end
end

-- Hover highlight: the hovered zone's borders drawn brighter on the front
-- buffer, at its zoom.
local function LayoutHighlight()
	local buf = front
	if not (hasLines and buf.zoom) then return end
	buf.highlight:Reset()
	if not (hoverZone and Enabled("zoneBorders")) then return end
	local z = buf.zoom
	local thick = math.max(1.6, math.min(2.4, z / 100))
	local area = HoverKey(hoverZone)
	local data = OfflineBorders(state.map)
	if data then
		for _, l in ipairs(area and data.zoneLines or {}) do
			if l.a == area or l.b == area then
				DrawPolyline(buf.highlight, buf.canvas, LinePts(l, z), z, thick, 1, 0.84, 0.4, 0.95, l.fadeStart, l.fadeEnd)
			end
		end
		return
	end
	local grid = state.map and grids[state.map]
	if not (grid and grid.chainZones) then return end
	for i, pts in ipairs(ChainsForZoom(grid, z) or {}) do
		if grid.chainZones[i] and grid.chainZones[i][hoverZone] then
			DrawPolyline(buf.highlight, buf.canvas, pts, z, thick, 1, 0.84, 0.4, 0.95)
		end
	end
end

function ns.SetHoverZone(zoneID)
	if zoneID == hoverZone then return end
	local old = HoverKey(hoverZone)
	hoverZone = zoneID
	local new = HoverKey(zoneID)
	if old and labelByZone[old] then labelByZone[old]:SetTextColor(unpack(LABEL_COLOR)) end
	if new and labelByZone[new] then labelByZone[new]:SetTextColor(unpack(LABEL_HOVER)) end
	LayoutHighlight()
end

local function FinishCrossfade()
	if not fade then return end
	fade.to.canvas:SetAlpha(1)
	fade.from.canvas:Hide()
	fade = nil
end

-- A finished build becomes the front buffer.
local function Swap(b)
	local buf, old = b.buf, front
	buf.zoom, buf.region, buf.stale = b.zoom, b.region, nil
	front, back = buf, old
	buf.canvas:SetAlpha(0)
	buf.canvas:Show()
	-- Same zoom: the lines they share are identical, so cut straight over (a
	-- fade would only dim them for a moment mid-pan).
	local sameZoom = old.zoom and SameZoom(old.zoom, b.zoom)
	if old.zoom and old.canvas:IsShown() and not sameZoom then
		fade = { from = old, to = buf, t = 0, fromAlpha = old.canvas:GetAlpha() }
	else
		buf.canvas:SetAlpha(1)
		old.canvas:Hide()
	end
	LayoutShade(b.zoom)
	PositionCanvases()
	LayoutHighlight()
	ns.layoutStats = { ms = b.ms, lines = hasLines and (buf.border.used + buf.shadow.used + buf.sub.used) or 0 }
end

-- Grow the front buffer to cover a new region at its own zoom: panning only
-- needs the lines coming into view, and they show as they're drawn.
local function StartExtend(region)
	build = nil
	local buf = front
	local b = { buf = buf, zoom = buf.zoom, region = region, map = state.map, ms = 0, extend = true }
	b.co = coroutine.create(function() BuildBorders(buf, buf.zoom, region, true, b) end)
	build = b
end

local function StartBuild(z, cx, cy)
	build = nil
	FinishCrossfade()
	local buf = back
	buf.canvas:Hide()
	buf.zoom, buf.region = nil, nil
	local b = { buf = buf, zoom = z, region = { ViewRect(REGION, z, cx, cy) }, map = state.map, ms = 0 }
	b.co = coroutine.create(function() BuildBorders(buf, z, b.region) end)
	build = b
end

-- New map: nothing of the old one may linger.
local function ClearGeometry()
	build = nil
	FinishCrossfade()
	for _, b in ipairs(buffers) do
		b.canvas:Hide()
		b.zoom, b.region = nil, nil
	end
	shadePool:Reset()
end

local function Fits(b, z, view)
	return b.zoom ~= nil and not b.stale and SameZoom(b.zoom, z) and Contains(b.region, unpack(view))
end

-- Room on a buffer's pools for more lines.
local function Roomy(buf)
	if buf.full then return false end
	for _, pool in ipairs({ buf.sub, buf.shadow, buf.border }) do
		if pool.used > pool.cap * EXTEND_MAX_FILL then return false end
	end
	return true
end

-- What the border buffers hold (for /mm perf and tests).
function ns.GeometryInfo()
	local r = front.region
	return {
		zoom = front.zoom, region = r, canvas = front.canvas,
		covers = Contains(r, ViewRect(0)), -- the view, right now
		building = build ~= nil, extending = build and build.extend, fading = fade ~= nil,
		lines = hasLines and (front.border.used + front.shadow.used + front.sub.used) or 0,
	}
end

-- Make sure the borders for where the camera is headed are on screen or on
-- their way. force: the data changed, so rebuild even if they look current.
local function RequestGeometry(force)
	local z = ns.GoalZoom()
	local cx, cy = ns.GoalCenter()
	local view = { ViewRect(0, z, cx, cy) }
	local ahead = { ViewRect(PREFETCH, z, cx, cy) }
	if force then
		front.stale = true
	else
		if Fits(front, z, ahead) then
			build = nil
			return
		end
		-- An extension can be re-aimed for free; a full build only once it
		-- stops covering the view.
		if build and Fits(build, z, build.extend and ahead or view) then
			build.urgent = not Fits(front, z, view)
			return
		end
	end
	local urgent = not force and not Fits(front, z, view)
	-- Same zoom: grow what's on screen, until it holds too many stray lines
	-- from far behind (then a fresh build, out of sight, tidies up).
	local extendable = not force and front.zoom and front.drawn and not front.stale and front.canvas:IsShown()
		and SameZoom(front.zoom, z) and OfflineBorders(state.map) and Roomy(front)
	if extendable then
		StartExtend({ ViewRect(REGION, front.zoom, cx, cy) })
	else
		StartBuild(z, cx, cy)
	end
	build.urgent = urgent
end

local runner = CreateFrame("Frame")
runner:SetScript("OnUpdate", function(_, elapsed)
	local b = build
	if b then
		sliceStart = debugprofilestop and debugprofilestop() or 0
		local ok, err = coroutine.resume(b.co)
		if debugprofilestop then
			local ms = debugprofilestop() - sliceStart
			b.ms = b.ms + ms
			if ns.perf then ns.perf.Slice(ms) end
		end
		if not ok then
			build = nil
			ns.Print("border layout failed: " .. tostring(err))
		elseif coroutine.status(b.co) == "dead" then
			build = nil
			if ns.perf then ns.perf.Built(b) end
			if b.map == state.map then
				if b.overflow then
					b.buf.full = true -- no more extending; rebuild
					RequestGeometry(false)
				elseif b.extend then
					b.buf.region = b.region
				else
					Swap(b)
				end
			end
		end
	end
	if fade then
		fade.t = fade.t + elapsed
		local p = math.min(1, fade.t / CROSSFADE)
		fade.to.canvas:SetAlpha(p)
		fade.from.canvas:SetAlpha(fade.fromAlpha * (1 - p))
		if p >= 1 then FinishCrossfade() end
	end
	for fs in pairs(fadingLabels) do
		local a = math.min(1, fs:GetAlpha() + elapsed / LABEL_FADE)
		fs:SetAlpha(a)
		if a >= 1 then fadingLabels[fs] = nil end
	end
end)

-- Borders and labels for the view (after new data or a layer toggle).
LayoutStatic = function()
	-- Nothing to lay out for a hidden window; do it when it's shown.
	if not ns.viewport:IsVisible() then
		staticPending = true
		return
	end
	staticPending = nil
	RequestGeometry(true)
	LayoutLabels()
end
ns.LayoutStatic = function() LayoutStatic() end

-- How many zones meaningfully share the view? With offline data: zones whose
-- heart (label anchor) is on screen. Otherwise sampled from the zone grid:
-- each must cover >= 4% of the *zoned* part of the view, so zooming far out
-- (continent small, lots of sea) still counts every zone on screen.
local zonesInViewKey, zonesInViewCount
function ns.ZonesInView()
	if not state.map then return 0 end
	local key = state.map .. ":" .. state.cx .. ":" .. state.cy .. ":" .. state.zoom
	if key == zonesInViewKey then return zonesInViewCount end
	local n = 0
	local c0, r0, c1, r1 = ViewRect(0)
	local data = OfflineBorders(state.map)
	for _, l in ipairs(data and data.zoneLabels or {}) do
		if l.weight >= 30 and l.col >= c0 and l.col <= c1 and l.row >= r0 and l.row <= r1 then n = n + 1 end
	end
	if not data then
		local grid = state.map and grids[state.map]
		if not (grid and grid.zonesDone) then return 2 end -- assume several until we know
		local w, h = ns.viewport:GetSize()
		local z = state.zoom
		local c0, r0 = state.cx - w / 2 / z, state.cy - h / 2 / z
		local counts, STEPS = {}, 24
		for a = 0, STEPS - 1 do
			for b = 0, STEPS - 1 do
				local i = math.floor((c0 + (a + 0.5) / STEPS * w / z - grid.c0) / CELL)
				local j = math.floor((r0 + (b + 0.5) / STEPS * h / z - grid.r0) / CELL)
				if i >= 0 and i < grid.nc and j >= 0 and j < grid.nr then
					local id = grid.ids[j * grid.nc + i + 1]
					if id ~= 0 then counts[id] = (counts[id] or 0) + 1 end
				end
			end
		end
		local zoned = 0
		for _, c in pairs(counts) do zoned = zoned + c end
		for _, c in pairs(counts) do
			if c >= math.max(2, zoned * 0.04) then n = n + 1 end
		end
	end
	zonesInViewKey, zonesInViewCount = key, n
	return n
end

local LABEL_DRIFT = math.log(1.25) -- mid-zoom, re-place labels once they've drifted this far
local AREA_DRIFT = math.log(1.15)  -- at rest, redraw quest areas scaled further than this
local pinZoom
local function OnViewChanged()
	if staticPending then LayoutStatic() end
	local z = state.zoom
	PositionCanvases()
	if z ~= pinZoom then
		pinZoom = z
		PositionPins()
	end
	local animating = ns.IsAnimating()
	if z ~= labelZoom then
		if labelZoom and animating and math.abs(math.log(z / labelZoom)) < LABEL_DRIFT then
			PositionLabels()
		else
			LayoutLabels()
		end
	elseif not Contains(labelRegion, ViewRect(0)) then
		LayoutLabels() -- panned out of the placed region
	end
	local az = layoutZoom[canvases.areas]
	if az and not animating and math.abs(math.log(z / az)) > AREA_DRIFT then LayoutQuestAreas() end
	RequestGeometry(false)
end

local function OnMapChanged(mapID)
	EnsureGrid(mapID)
	ClearGeometry()
	RefreshAllPins()
	LayoutStatic()
	PositionCanvases()
end

---------------------------------------------------------------------------
-- Zone under the cursor, and modifier clicks
---------------------------------------------------------------------------

local function ZoneAt(col, row)
	if not state.map then return end
	local cont = ns.GetContinentMapID(state.map)
	if not cont then return end
	local x, y = ns.TileToMap(cont, col, row)
	if not x or x < 0 or x > 1 or y < 0 or y > 1 then return end
	local info = SafeCall(C_Map.GetMapInfoAtPosition, cont, x, y)
	if not info or info.mapID == cont then return end
	local zx, zy = ns.TileToMap(info.mapID, col, row)
	if not zx then return end
	return { mapID = info.mapID, name = info.name, x = zx, y = zy }
end

ns.GetZoneAt = ZoneAt

local function OpenChat(text)
	local open = ChatFrame_OpenChat or (ChatFrameUtil and ChatFrameUtil.OpenChat)
	if open then open(text) else ns.Print(text) end
end

-- Waypoints: the game's user waypoint, super-tracked so it's your target.
function ns.CanSetWaypoints() return C_Map.SetUserWaypoint and UiMapPoint and true or false end
function ns.HasWaypoint() return C_Map.GetUserWaypoint and C_Map.GetUserWaypoint() ~= nil end
function ns.ClearWaypoint()
	if C_Map.ClearUserWaypoint then C_Map.ClearUserWaypoint() end
end

-- Returns true if the waypoint was placed (else says why not).
function ns.SetWaypointAt(col, row)
	local z = ZoneAt(col, row)
	if not z then
		ns.Print("no zone here to put a waypoint in")
	elseif not ns.CanSetWaypoints() then
		ns.Print("waypoints aren't supported by this client")
	elseif C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(z.mapID) then
		ns.Print("can't place a waypoint in " .. z.name)
	else
		C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(z.mapID, z.x, z.y))
		if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
			C_SuperTrack.SetSuperTrackedUserWaypoint(true)
		end
		followedQuest = nil
		ScheduleRefresh("quests")
		-- The target comes from the pins, so don't wait for the event's refresh.
		RefreshPins("waypoint")
		return true
	end
	return false
end

-- Returns true if the click was handled (so the map doesn't start panning).
function ns.OnMapClick(button, col, row)
	if IsControlKeyDown() and button == "RightButton" then
		ns.ClearWaypoint()
		return true
	end
	if button ~= "LeftButton" then return false end
	local z = ZoneAt(col, row)
	if not z then return false end
	if IsControlKeyDown() then
		ns.SetWaypointAt(col, row)
		return true
	elseif IsShiftKeyDown() then
		OpenChat(string.format("/way %s %.1f %.1f", z.name, z.x * 100, z.y * 100))
		return true
	end
	return false
end

---------------------------------------------------------------------------
-- Layers menu, events, init
---------------------------------------------------------------------------

local STATIC_LAYERS = { zoneLabels = true, zoneBorders = true, unexplored = true }
local GROUP_KEYS = {}
for _, g in ipairs(GROUPS) do GROUP_KEYS[g.key] = true end
local ADDONS_INLINE = 6 -- more addon layers than this fold into a submenu (MenuUtil)

-- Redraw what a layer's setting affects, then tell its owner.
local function ApplyLayer(key)
	if sources[key] then
		RefreshPins(key)
		LayoutPins()
		LayoutQuestAreas()
	elseif key == "questAreas" or key == "questAreasApprox" then
		LayoutQuestAreas()
	elseif STATIC_LAYERS[key] then
		EnsureGrid(state.map)
		LayoutStatic()
	end -- "group" is moved every frame; addon layers draw themselves
	local layer = layerByKey[key]
	if layer and layer.onToggle then layer.onToggle(Enabled(key) and true or false) end
end

local function OnLayerSelect(key)
	if not layerByKey[key] then return end
	db.layers[key] = not db.layers[key]
	ApplyLayer(key)
	-- Its sub-options come and go with it.
	for _, layer in ipairs(LAYERS) do
		if layer.parent == key and db.layers[layer.key] then ApplyLayer(layer.key) end
	end
end

local function LayerLabel(layer)
	if layer.key == "questAreas" and not blobSupported then return layer.label .. " |cff888888(n/a)|r" end
	return layer.label
end

-- The menu's sections in order, each { title, key, layers }; empty ones left out.
local function LayerSections()
	local out = {}
	for _, g in ipairs(GROUPS) do
		local list = {}
		for _, layer in ipairs(LAYERS) do
			if (GROUP_KEYS[layer.group] and layer.group or "places") == g.key then list[#list + 1] = layer end
		end
		if #list > 0 then out[#out + 1] = { title = g.title, key = g.key, layers = list } end
	end
	return out
end

-- Checked shows your choice; a sub-option is greyed while its parent is off.
local function Checked(key) return db.layers[key] and true or false end
local function Usable(layer) return not layer.parent or Enabled(layer.parent) and true or false end

if MenuUtil and MenuUtil.CreateContextMenu then
	-- The client's own menu: section titles, checkboxes that stay open.
	local function Tooltip(layer)
		return function(tooltip)
			tooltip:SetText(layer.label, 1, 1, 1)
			tooltip:AddLine(layer.tip, 1, 0.82, 0, true)
		end
	end
	ns.gearButton:HookScript("OnClick", function(self)
		ns.OpenClientMenu(self, function(_, root)
			for i, sec in ipairs(LayerSections()) do
				local parent = root
				if i > 1 then root:CreateDivider() end
				if sec.key == "addons" and #sec.layers > ADDONS_INLINE then
					parent = root:CreateButton(sec.title)
				else
					root:CreateTitle(sec.title)
				end
				for _, layer in ipairs(sec.layers) do
					local key = layer.key
					local cb = parent:CreateCheckbox((layer.parent and "     " or "") .. LayerLabel(layer),
						function() return Checked(key) end,
						function()
							OnLayerSelect(key)
							return MenuResponse and MenuResponse.Refresh
						end, key)
					if layer.parent and cb.SetEnabled then cb:SetEnabled(function() return Usable(layer) end) end
					if layer.tip and cb.SetTooltip then cb:SetTooltip(Tooltip(layer)) end
				end
			end
		end)
	end)
else
	-- Our own checklist: gold section headings, sub-options indented.
	local layersMenu = ns.AttachMenu(ns.gearButton, 220, "down")
	layersMenu.keepOpen = true
	layersMenu.maxRows = 30
	layersMenu.getItems = function()
		local items = {}
		for _, sec in ipairs(LayerSections()) do
			items[#items + 1] = { text = "|cffffd100" .. sec.title .. "|r", disabled = true }
			for _, layer in ipairs(sec.layers) do
				items[#items + 1] = { text = LayerLabel(layer), value = layer.key, checked = Checked(layer.key),
					tip = layer.tip, indent = layer.parent and 1 or nil, disabled = not Usable(layer) }
			end
		end
		return items
	end
	layersMenu.onSelect = OnLayerSelect
end

ns.slash.layers = function()
	local parts = {}
	for _, sec in ipairs(LayerSections()) do
		local on = {}
		for _, layer in ipairs(sec.layers) do
			on[#on + 1] = (Enabled(layer.key) and "|cff33ff33" or "|cff888888") .. layer.key .. "|r"
		end
		parts[#parts + 1] = "|cffffd100" .. sec.title .. ":|r " .. table.concat(on, ", ")
	end
	ns.Print("layers: " .. table.concat(parts, "; ") .. ". Toggle them from the gear. "
		.. "Shift-click: /way at cursor. Ctrl-click: set waypoint. Ctrl-right-click: clear it. "
		.. "Quest areas: " .. (blobSupported and "exact blobs supported" or "approximate only"))
end

ns.On("Loaded", function(savedDB)
	db = savedDB
	db.layers = db.layers or {}
	for _, layer in ipairs(LAYERS) do
		if db.layers[layer.key] == nil then db.layers[layer.key] = layer.default end
	end
end)
ns.On("MapChanged", OnMapChanged)
ns.On("ViewChanged", OnViewChanged)

local events = CreateFrame("Frame")
local EVENT_LAYERS = {
	QUEST_LOG_UPDATE = { "quests", "offers" },
	QUESTLINE_UPDATE = { "offers" },
	MINIMAP_UPDATE_TRACKING = { "offers" },
	QUEST_POI_UPDATE = { "quests" },
	USER_WAYPOINT_UPDATED = { "waypoint" },
	SUPER_TRACKING_CHANGED = { "quests" },
	PLAYER_DEAD = { "corpse", "graveyards" },
	PLAYER_ALIVE = { "corpse", "graveyards" },
	PLAYER_UNGHOST = { "corpse", "graveyards" },
	TAXIMAP_OPENED = { "flight" },
}
for event in pairs(EVENT_LAYERS) do pcall(events.RegisterEvent, events, event) end
pcall(events.RegisterEvent, events, "MAP_EXPLORATION_UPDATED")
-- Ghost and no corpse on the map yet: keep asking.
local function PollCorpse()
	if IsGhost() and not corpseFound and Enabled("corpse") and state.map then ScheduleRefresh("corpse") end
	C_Timer.After(CORPSE_POLL, PollCorpse)
end
C_Timer.After(CORPSE_POLL, PollCorpse)
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "QUESTLINE_UPDATE" and arg1 then wipe(offersAsked) end -- asked to ask again
	if event == "MAP_EXPLORATION_UPDATED" then
		-- Keep showing the old shading until the new pass finishes.
		for _, grid in pairs(grids) do grid.shadeStale = true end
		EnsureGrid(state.map)
		return
	end
	for _, key in ipairs(EVENT_LAYERS[event] or {}) do ScheduleRefresh(key) end
end)

---------------------------------------------------------------------------
-- Exports for ZoneInfo.lua (the big map's right-click info). Read on a
-- right-click only.
---------------------------------------------------------------------------

-- Quests whose area covers tile (col, row): drawn blobs, then the estimated
-- circles. A list of { questID, title, followed }.
function ns.QuestsAt(col, row)
	local out, seen, followed = {}, {}, FollowedQuest()
	local function Add(questID, title)
		if seen[questID] then return end
		seen[questID] = true
		out[#out + 1] = { questID = questID, followed = questID == followed,
			title = title or SafeCall(C_QuestLog.GetTitleForQuestID, questID) or ("Quest " .. questID) }
	end
	for _, b in ipairs(blobFrames) do
		local r = b.rect
		if col >= r.col0 and col <= r.col1 and row >= r.row0 and row <= r.row1 then
			local questID = BlobAt(b.frame, (col - r.col0) / (r.col1 - r.col0), (row - r.row0) / (r.row1 - r.row0))
			if questID then Add(questID) end
		end
	end
	if Enabled("quests") and Enabled("questAreasApprox") then
		for _, a in ipairs(questAreas) do
			if a.shape == "area" and a.hasBlob == false
				and (a.col - col) ^ 2 + (a.row - row) ^ 2 <= APPROX_RADIUS ^ 2 then
				Add(a.questID, a.title)
			end
		end
	end
	return out
end

-- A layer's pins on the shown map, also while the layer is off. Only layers
-- whose source just reads the game (quests and corpse keep state).
local PURE_SOURCES = { flight = true, graveyards = true, dungeons = true, services = true, areaPOIs = true }
function ns.LayerPins(key)
	if pinData[key] then return pinData[key] end
	if PURE_SOURCES[key] and sources[key] and state.map then return SafeCall(sources[key], state.map) end
end

-- The sub-zone label (offline borders) nearest tile (col, row): name,
-- distance in tiles, and the label's col, row. Nil without offline borders.
function ns.SubzoneNear(col, row)
	local data = state.map and OfflineBorders(state.map)
	if not data then return nil end
	local best, bestD
	for _, l in ipairs(data.subLabels) do
		local d = (l.col - col) ^ 2 + (l.row - row) ^ 2
		if not bestD or d < bestD then best, bestD = l, d end
	end
	if best then return best.name, math.sqrt(bestD), best.col, best.row end
end
