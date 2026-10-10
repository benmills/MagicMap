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
-- The Minimap only knows what's within its view radius (about 233 yards
-- outdoors at its widest), so blips cover a circle around you; past a certain
-- zoom-out that circle is too small to read and the Minimap steps aside. It
-- also steps aside mid-zoom, and for a few frames after a change of its zoom
-- level (the client takes a moment to apply one).
--
-- The client doesn't clip the Minimap to the window (not with
-- SetClipsChildren, nor as a ScrollFrame's child: tried in game), so its
-- blips may only show inside it. When its square is bigger than the room
-- around you (zoomed in closer than its closest level, a window wider than
-- tall, you off centre), a mask texture whose opaque rectangle fits that room
-- confines them: the client hides blips where the mask is transparent. A
-- mask covers the whole Minimap, centred on you, so the room is what's
-- around you to the window's nearest edge each way; past that, nothing (and
-- no way to read the blips there either: the hover point can't be moved).
-- Without the mask files (new files need a client restart), it only shows
-- while its whole square fits.
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
local SETTLE_FRAMES = 3 -- frames the Minimap stays hidden after a change of its zoom level

-- Minimap:GetZoom() -> view diameter in yards, for choosing a zoom level (and
-- the radius until the client reports one).
local DIAMETER = {
	outdoor = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 },
	indoor = { [0] = 300, 240, 180, 120, 80, 50 },
}

local db
local lastZoom
local settling = 0

---------------------------------------------------------------------------
-- Masks. Textures/MinimapMask/Rect<w>x<h>: 32x32, opaque in a centred w x h
-- rectangle, w and h even (32: the whole width or height;
-- tools/gen_minimap_masks.py). Loaded up front so a switch never waits on a
-- file.
---------------------------------------------------------------------------

local MASK_PATH = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\MinimapMask\\Rect"
local maskPaths = {} -- [w * 64 + h] -> its path, built once
local MASK_TEXELS, MASK_MIN = 32, 4
local MASK_MARGIN = 2 -- px kept clear inside the room's edge
local masksFound
do
	local holder = CreateFrame("Frame", nil, UIParent)
	holder:SetSize(1, 1)
	holder:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 8, -8) -- off screen
	holder:SetAlpha(0)
	for w = MASK_MIN, MASK_TEXELS, 2 do
		for h = MASK_MIN, MASK_TEXELS, 2 do
			if w < MASK_TEXELS or h < MASK_TEXELS then
				local t = holder:CreateTexture(nil, "BACKGROUND")
				t:SetAllPoints()
				maskPaths[w * 64 + h] = MASK_PATH .. w .. "x" .. h
				local ok = t:SetTexture(maskPaths[w * 64 + h])
				if masksFound == nil then masksFound = ok ~= false end
			end
		end
	end
end

---------------------------------------------------------------------------
-- The plan: pure functions of the view, no frames touched.
---------------------------------------------------------------------------

-- The Minimap's zoom level for `room` px around you at map zoom `zoom`:
-- masked, the closest that still covers the room (its widest when even that
-- fits), but never more than dMax px across (past that no mask is narrow
-- enough for the room's short side); unmasked, the widest whose square
-- fits. nil if none does.
local function PickLevel(kind, zoom, room, masks, dMax)
	local px = zoom / TILE_YARDS
	if masks then
		for z = 5, 0, -1 do
			local d = DIAMETER[kind][z] * px
			if dMax and d > dMax then return z < 5 and z + 1 or nil end
			if d >= room then return z end
		end
		return 0
	end
	for z = 0, 5 do
		if DIAMETER[kind][z] * px <= room then return z end
	end
end

-- A mask's texels across, for a Minimap d px across in `room` px: all of
-- them if it fits whole that way; nil if no mask is narrow enough.
local function Texels(d, room)
	if d <= room + 1 then return MASK_TEXELS end
	-- Half a texel of slack each side: the mask's edge is filtered.
	local n = math.floor(((room - MASK_MARGIN) / d - 1 / MASK_TEXELS) * MASK_TEXELS / 2) * 2
	return n >= MASK_MIN and math.min(n, MASK_TEXELS - 2) or nil
end

-- The mask for a Minimap d px across in roomW x roomH px around you, and the
-- size (px) of the rectangle its blips may show in; nil if none fits.
local function MaskFor(d, roomW, roomH, masks)
	if d <= roomW + 1 and d <= roomH + 1 then return T.SQUARE_MASK, math.min(d, roomW), math.min(d, roomH) end
	if not masks then return nil end
	local w, h = Texels(d, roomW), Texels(d, roomH)
	if not (w and h) then return nil end
	return maskPaths[w * 64 + h], d * w / MASK_TEXELS, d * h / MASK_TEXELS
end

ns.MinimapPlan = { Level = PickLevel, Mask = MaskFor }

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

local function ViewRadius(kind)
	local r = C_Minimap.GetViewRadius()
	if r > 0 then return r end
	return (DIAMETER[kind][T.Level()] or DIAMETER[kind][0]) / 2 -- (before the client has one)
end

---------------------------------------------------------------------------
-- /mm sync: the Minimap's own terrain at half strength over ours, inside an
-- outline of where we put it, so any drift between its blips and our map
-- shows as doubled terrain. Its terrain is masked like its blips, so it
-- also shows the rectangle they're confined to. /mm sync full: at full strength.
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

local function ReportSync(level, kind, d, zoom, sideW, sideH, mask)
	if syncOutline:IsShown() ~= (syncCheck ~= nil) then syncOutline:SetShown(syncCheck ~= nil) end
	if not syncCheck or (level == syncCheck.level and mask == syncCheck.mask) then return end
	syncCheck.level, syncCheck.mask = level, mask
	ns.Print(string.format("sync: Minimap zoom %d, radius %.1f yd (%s), %d px across at map zoom %.0f; blips in %dx%d px (%s)",
		level, ViewRadius(kind), C_Minimap.GetViewRadius() > 0 and "client" or "table", d, zoom,
		sideW, sideH, mask == T.SQUARE_MASK and "whole square" or mask:match("Rect%d+x%d+$")))
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

local insets = {}

-- Where the Minimap's blips show on our map: a rectangle around you (tile
-- space: centre and half its width and height), on while it's placed.
-- Layers.lua's quest givers step aside inside it.
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

	-- Outdoors it only shows where it can't go wrong: the map settled, its
	-- blips confined to the room around you, its zoom level applied.
	local cam = ns.Camera()
	local zoom = cam.zoom
	local still = not cam.animating and lastZoom and math.abs(math.log(zoom / lastZoom)) < STILL
	lastZoom = zoom
	local kind = indoors and "indoor" or "outdoor"
	local x, y, w, h = cam.playerX, cam.playerY, cam.viewW, cam.viewH
	-- The biggest rectangle around you in the window: the mask needs the Minimap
	-- to cover it; unmasked, its square must fit inside.
	local roomW, roomH = 2 * math.min(x, w - x), 2 * math.min(y, h - y)
	local short = math.min(roomW, roomH)
	local level = PickLevel(kind, zoom, masksFound and math.max(roomW, roomH) or short, masksFound,
		(short - MASK_MARGIN) * MASK_TEXELS / MASK_MIN)
	if level and still and T.SetLevel(level) then settling = SETTLE_FRAMES end
	settling = math.max(0, settling - 1)
	local d = 2 * ViewRadius(kind) / TILE_YARDS * zoom
	local mask, sideW, sideH = MaskFor(d, roomW, roomH, masksFound)
	if expanded or not (level and still) or settling > 0 or d < MIN_DIAMETER or not mask then
		T.Hide()
		return
	end

	local insetW, insetH = (d - sideW) / 2, (d - sideH) / 2
	insets[1], insets[2] = math.max(insetW, d / 2 - x), math.max(insetW, d / 2 - (w - x))
	insets[3], insets[4] = math.max(insetH, d / 2 - y), math.max(insetH, d / 2 - (h - y))
	T.Place(cam.canvas, cam.playerCol * zoom, -cam.playerRow * zoom, d, mask, insets, syncCheck and syncCheck.alpha or 0)
	area.on, area.col, area.row = true, cam.playerCol, cam.playerRow
	area.halfW, area.halfH = sideW / 2 / zoom, sideH / 2 / zoom
	ReportSync(level, kind, d, zoom, sideW, sideH, mask)
end

-- After the map's own OnUpdate, so the view has already moved this frame.
ns.frame:HookScript("OnUpdate", ns.Timed("minimap", Update))
ns.frame:HookScript("OnHide", T.Release)

ns.On("Loaded", function(savedDB)
	db = savedDB
	-- Earlier versions' settings: /mm clip, and the clipping experiments.
	db.minimapClip, db.testClip, db.testStretch = nil, nil, nil
end)
