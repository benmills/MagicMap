-- Minimap blips on our map: the policy. Each frame this decides whether
-- Blizzard's Minimap belongs on the map, at which zoom level, where and how
-- big; MinimapTakeover.lua is what touches it.
--
-- The Minimap sits centred on you, sized so its yards per pixel match our
-- zoom, so its live blips (tracked herbs and ore, NPCs) and addon pins
-- (GatherMate, HandyNotes, via HereBeDragons, which reads the Minimap's own
-- size) land on our terrain, while our terrain shows far more than the
-- Minimap ever could.
--
-- Its square must stay on the screen: where it runs off, the client draws
-- its terrain and blips into the part still on screen, shifted and squashed
-- (measured in game, /mm sync's terrain against ours). It only knows what's
-- within its view radius (about 233 yards outdoors at its widest), so blips
-- cover the square around you it's sized to; past a certain zoom-out that's
-- too small to read and it steps aside.
--
-- Nothing confines its blips to our window: the client doesn't clip the
-- Minimap (not with SetClipsChildren, nor as a ScrollFrame's child), and a
-- mask texture hides its herbs and ore but not its arrow or some icons
-- (all tried in game). So by default its whole square fits in the window
-- around you: its widest zoom level that does. With db.blipsPastEdge it's
-- the closest level that covers the whole window instead, its blips
-- reaching past the window's edge where it's longer one way.
--
-- It only changes zoom level while shown: hidden, it doesn't redraw, and
-- comes back drawn at the level it was hidden with until you move. It steps
-- aside (hidden) mid-zoom, at its current level.
--
-- Indoors our terrain has nothing to show, so the window just wears the
-- Minimap itself: full terrain, centred, the wheel zooming it.
--
-- This runs while the map is shown.

local ADDON, ns = ...
local T = ns.Takeover
local TILE_YARDS = 1600 / 3
local MIN_DIAMETER = 28 -- px; any smaller and the blips just pile up on your arrow
local STILL = 0.002 -- a zoom change per frame smaller than this (log scale) counts as settled
local SCREEN_MARGIN = 4 -- px its square keeps inside the screen

-- Minimap:GetZoom() -> view diameter in yards: which map it's drawing (indoor
-- or outdoor), and the radius until the client reports one.
local DIAMETER = {
	outdoor = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 },
	indoor = { [0] = 300, 240, 180, 120, 80, 50 },
}

local db
local lastZoom

---------------------------------------------------------------------------
-- The plan: a pure function of the view, no frames touched.
---------------------------------------------------------------------------

-- The Minimap's zoom level at map zoom `zoom`, never more than `most` px
-- across (the screen around you): covering, the closest that is at least
-- `room` px across (its widest when even that isn't); else the widest no
-- more than `room`. nil if none will do.
local function PickLevel(zoom, room, covering, most)
	local px = zoom / TILE_YARDS
	local D = DIAMETER.outdoor
	if covering then
		for z = 5, 0, -1 do
			if D[z] * px > most then return z < 5 and z + 1 or nil end
			if D[z] * px >= room then return z end
		end
		return 0
	end
	for z = 0, 5 do
		if D[z] * px <= math.min(room, most) then return z end
	end
end

ns.MinimapPlan = { Level = PickLevel }

---------------------------------------------------------------------------
-- When it may join the map at all
---------------------------------------------------------------------------

-- nil if the Minimap can join the map right now, else why not.
local function Blocker()
	if not ns.frame:IsShown() then return "the map is closed" end
	if FarmHud and FarmHud.IsShown and FarmHud:IsShown() then return "FarmHud has the minimap" end
	if not ns.Camera().onMap then return "you're not on the map being shown" end
	return nil
end

-- Whether the Minimap is drawing its indoor map. Not IsIndoors(): that's
-- whether you may mount, and places like Orgrimmar's Cleft of Shadow let you
-- while the Minimap shows the floor plan. Its view radius tells: the indoor
-- and outdoor diameters at a zoom level never come near each other.
local function MinimapIndoors()
	local r = C_Minimap.GetViewRadius()
	if not (r and r > 0) then return IsIndoors() and true or false end
	local z = T.Level()
	local din, dout = DIAMETER.indoor[z] or DIAMETER.indoor[0], DIAMETER.outdoor[z] or DIAMETER.outdoor[0]
	return math.abs(2 * r - din) < math.abs(2 * r - dout)
end

---------------------------------------------------------------------------
-- /mm sync: the Minimap's own terrain at half strength over ours, inside an
-- outline of where we put it, so any drift between its blips and our map
-- shows as doubled terrain. /mm sync full: at full strength.
---------------------------------------------------------------------------

local syncCheck
local syncOutline = CreateFrame("Frame", nil, Minimap)
syncOutline:SetAllPoints()
syncOutline:Hide()
T.Own(syncOutline)
for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT", true }, { "TOPRIGHT", "BOTTOMRIGHT", true } }) do
	local t = syncOutline:CreateTexture(nil, "OVERLAY")
	t:SetColorTexture(1, 0.2, 0.8, 0.9) -- where we put the Minimap: its terrain should fill this exactly
	t:SetPoint(e[1])
	t:SetPoint(e[2])
	if e[3] then t:SetWidth(1) else t:SetHeight(1) end
end

ns.SyncShown = function() return syncCheck ~= nil end

ns.slash.sync = function(arg)
	syncCheck = not syncCheck and { alpha = arg == "full" and 1 or 0.5 } or nil
	if not syncCheck then syncOutline:Hide() end
	ns.Print(not syncCheck and "sync: off"
		or syncCheck.alpha == 1 and "sync: Blizzard's terrain in place of ours where its blips show. /mm sync again to stop"
		or "sync: Blizzard's terrain at 50% over ours; zoom and pan, watch for doubling. /mm sync again to stop")
end

local function ReportSync(level, d, zoom)
	if syncOutline:IsShown() ~= (syncCheck ~= nil) then syncOutline:SetShown(syncCheck ~= nil) end
	if not syncCheck or level == syncCheck.level then return end
	syncCheck.level = level
	ns.Print(string.format("sync: Minimap zoom %d, radius %.1f yd, %d px across at map zoom %.0f",
		level, DIAMETER.outdoor[level] / 2, d, zoom))
end

-- /mm dupes: Blizzard's own markers for what our layers draw, back on (or off again).
ns.slash.dupes = function()
	if not db then return end
	db.hideDupes = db.hideDupes == false
	T.RefreshTracking()
	local off = {}
	for id in pairs(db.trackingOff or {}) do off[#off + 1] = T.DUPLICATES[id] or tostring(id) end
	ns.Print(db.hideDupes and ("dupes: Blizzard's markers for what we draw are off while the minimap is in the map"
		.. (#off > 0 and (" (" .. table.concat(off, ", ") .. ")") or ""))
		or "dupes: Blizzard's markers stay on alongside ours")
end

---------------------------------------------------------------------------
-- Each frame
---------------------------------------------------------------------------

-- Where the Minimap's blips show on our map: the square around you (tile
-- space: centre and half its side), on while it's placed. Layers.lua's quest
-- givers step aside inside it.
local area = { on = false }
ns.BlipArea = area

local function Update()
	area.on = false
	if Blocker() then
		T.Release()
		return
	end
	T.Engage()
	local expanded = ns.IsMapExpanded()
	local indoors = MinimapIndoors()
	local whole = indoors and not expanded
	T.SetIndoor(whole)
	T.KeepTracking(not whole) -- indoors our pins are under the backdrop: Blizzard's stay
	if whole then
		T.ShowWhole()
		return
	end

	local cam = ns.Camera()
	local zoom = cam.zoom
	local still = not cam.animating and lastZoom and math.abs(math.log(zoom / lastZoom)) < STILL
	lastZoom = zoom
	local x, y, w, h = cam.playerX, cam.playerY, cam.viewW, cam.viewH
	-- The room around you in the window, each way; and on the screen.
	local roomW, roomH = 2 * math.min(x, w - x), 2 * math.min(y, h - y)
	local vp = ns.viewport
	local k = UIParent:GetEffectiveScale() / vp:GetEffectiveScale()
	local sx, sy = (vp:GetLeft() or 0) + x, (vp:GetTop() or 0) - y -- you, from the screen's bottom left
	local onScreen = 2 * math.min(sx, UIParent:GetWidth() * k - sx, sy, UIParent:GetHeight() * k - sy) - SCREEN_MARGIN
	local past = db.blipsPastEdge and true or false
	local level = PickLevel(zoom, past and math.max(roomW, roomH) or math.min(roomW, roomH), past, onScreen)
	if expanded or not (level and still) then
		T.Hide()
		return
	end
	local d = DIAMETER.outdoor[level] / TILE_YARDS * zoom
	if d < MIN_DIAMETER then
		T.Hide()
		return
	end

	T.Place(cam.canvas, cam.playerCol * zoom, -cam.playerRow * zoom, d, syncCheck and syncCheck.alpha or 0)
	T.SetLevel(level) -- (shown now: see above)
	area.on, area.col, area.row, area.half = true, cam.playerCol, cam.playerRow, d / 2 / zoom
	ReportSync(level, d, zoom)
end

-- After the map's own OnUpdate, so the view has already moved this frame.
ns.frame:HookScript("OnUpdate", ns.Timed("minimap", Update))
ns.frame:HookScript("OnHide", T.Release)

ns.On("Loaded", function(savedDB) db = savedDB end)
