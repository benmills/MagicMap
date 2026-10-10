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
-- The client doesn't clip the Minimap to the window, so its blips may only
-- show inside it. Zoomed in closer than its closest level, or with you off
-- centre, its square is bigger than the room around you; then a mask texture
-- whose opaque square fits that room confines its blips (the client hides
-- blips where the mask is transparent). Without the mask files (new files
-- need a client restart), it only shows while its whole square fits.
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
-- Masks. Textures/MinimapMask/Square<n>: 64x64, opaque in a centred n x n
-- square (tools/gen_minimap_masks.py). Loaded up front so a switch never
-- waits on a file.
---------------------------------------------------------------------------

local MASK_PATH = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\MinimapMask\\Square"
local maskPaths = {} -- n -> its path, built once
local MASK_TEXELS, MASK_MIN = 64, 8
local MASK_MARGIN = 2 -- px kept clear inside the room's edge
local masksFound
do
	local holder = CreateFrame("Frame", nil, UIParent)
	holder:SetSize(1, 1)
	holder:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 8, -8) -- off screen
	holder:SetAlpha(0)
	for n = MASK_MIN, MASK_TEXELS - 2, 2 do
		local t = holder:CreateTexture(nil, "BACKGROUND")
		t:SetAllPoints()
		maskPaths[n] = MASK_PATH .. n
		local ok = t:SetTexture(maskPaths[n])
		if n == MASK_MIN then masksFound = ok ~= false end
	end
end

---------------------------------------------------------------------------
-- The plan: pure functions of the view, no frames touched.
---------------------------------------------------------------------------

-- The Minimap's zoom level for `room` px around you at map zoom `zoom`:
-- masked, the closest that still covers the room (its widest when even that
-- fits); unmasked, the widest whose square fits. nil if none does.
local function PickLevel(kind, zoom, room, masks)
	local px = zoom / TILE_YARDS
	if masks then
		for z = 5, 0, -1 do
			if DIAMETER[kind][z] * px >= room then return z end
		end
		return 0
	end
	for z = 0, 5 do
		if DIAMETER[kind][z] * px <= room then return z end
	end
end

-- The mask for a Minimap d px across in `room` px around you, and the side
-- (px) of the square its blips may show in; nil if none fits.
local function MaskFor(d, room, masks)
	if d <= room + 1 then return T.SQUARE_MASK, math.min(d, room) end
	if not masks then return nil end
	-- Half a texel of slack each side: the mask's edge is filtered.
	local n = math.floor(((room - MASK_MARGIN) / d - 1 / MASK_TEXELS) * MASK_TEXELS / 2) * 2
	if n < MASK_MIN then return nil end
	n = math.min(n, MASK_TEXELS - 2)
	return maskPaths[n], d * n / MASK_TEXELS
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

local function ViewRadius(kind)
	local r = C_Minimap.GetViewRadius()
	if r > 0 then return r end
	return (DIAMETER[kind][T.Level()] or DIAMETER[kind][0]) / 2 -- (before the client has one)
end

---------------------------------------------------------------------------
-- /mm sync: the Minimap's own terrain at half strength over ours, inside an
-- outline of where we put it, so any drift between its blips and our map
-- shows as doubled terrain. Its terrain is masked like its blips, so it
-- also shows the square they're confined to. /mm sync full: at full strength.
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

local function ReportSync(level, kind, d, zoom, side, mask)
	if syncOutline:IsShown() ~= (syncCheck ~= nil) then syncOutline:SetShown(syncCheck ~= nil) end
	if not syncCheck or (level == syncCheck.level and mask == syncCheck.mask) then return end
	syncCheck.level, syncCheck.mask = level, mask
	ns.Print(string.format("sync: Minimap zoom %d, radius %.1f yd (%s), %d px across at map zoom %.0f; blips in %d px (%s)",
		level, ViewRadius(kind), C_Minimap.GetViewRadius() > 0 and "client" or "table", d, zoom,
		side, mask == T.SQUARE_MASK and "whole square" or mask:match("Square%d+$")))
end

-- /mm dupes: Blizzard's own markers for what our layers draw, back on (or off again).
---------------------------------------------------------------------------
-- Experiment (/mm blips; to come out once answered): can we read the
-- Minimap's blips without the mouse, everywhere on it? Blizzard's hover
-- calls GameTooltip:SetMinimapMouseover(), which the client fills with the
-- names under its hover point; Minimap:UpdateMouseoverAtPoint(x, y) moves
-- that point, in coordinates nothing documents. So: scan the whole Minimap
-- in each convention we can think of, and say what was found where -
-- inside the mask (where its blips show) or outside it, inside the window
-- or outside it - and what a probe costs. Blips found outside the mask
-- would mean we could draw them ourselves, anywhere.
---------------------------------------------------------------------------

local probeTip
local function ProbeText()
	probeTip:SetOwner(UIParent, "ANCHOR_NONE")
	probeTip:SetMinimapMouseover()
	local text
	for i = 1, probeTip:NumLines() do
		local fs = _G["MagicMapBlipProbeTextLeft" .. i]
		local t = fs and fs:GetText()
		if t and issecretvalue(t) then return "<secret>" end
		if t and t ~= "" then text = text and (text .. " / " .. t) or t end
	end
	probeTip:Hide()
	return text
end

ns.slash.blips = function()
	local sq = ns.BlipSquare
	if not (T.IsEngaged() and ns.MinimapShowsPlayer() and sq and sq.on) then
		return ns.Print("blips: needs Blizzard's blips on the map (outdoors, the map settled on you); zoom in close so the Minimap is bigger than the window")
	end
	probeTip = probeTip or CreateFrame("GameTooltip", "MagicMapBlipProbe", nil, "GameTooltipTemplate")
	local cx, cy = Minimap:GetCenter()
	local half = Minimap:GetWidth() / 2
	local scale = Minimap:GetEffectiveScale()
	local maskHalf = sq.half * ns.state.zoom -- px: where its blips show
	local vl, vb, vw, vh = ns.viewport:GetRect()
	local yd = C_Minimap.GetViewRadius() / half
	local step = math.max(4, math.floor(half / 40))
	for _, mode in ipairs({ "offset", "ui", "screen" }) do
		local seen, n, inMask, outMask, outWindow, probes = {}, 0, 0, 0, 0, 0
		local t0 = debugprofilestop()
		for dy = -half, half, step do
			for dx = -half, half, step do
				local x, y = dx, dy
				if mode == "ui" then x, y = cx + dx, cy + dy
				elseif mode == "screen" then x, y = (cx + dx) * scale, (cy + dy) * scale end
				probes = probes + 1
				local text = pcall(Minimap.UpdateMouseoverAtPoint, Minimap, x, y) and ProbeText()
				if text and not seen[text] then
					seen[text] = true
					n = n + 1
					local px, py = cx + dx, cy + dy
					local masked = math.abs(dx) > maskHalf or math.abs(dy) > maskHalf
					if masked then outMask = outMask + 1 else inMask = inMask + 1 end
					if px < vl or px > vl + vw or py < vb or py > vb + vh then outWindow = outWindow + 1 end
					if n <= 6 then
						ns.Print(string.format("  [%s] %s  (%+d, %+d yd%s)", mode, text, dx * yd, dy * yd, masked and ", masked out" or ""))
					end
				end
			end
		end
		local us = (debugprofilestop() - t0) * 1000 / probes
		ns.Print(string.format("blips [%s]: %d found, %d where its blips show, %d masked out (%d outside the window); %.1f us a probe",
			mode, n, inMask, outMask, outWindow, us))
	end
	ns.Print(string.format("Minimap %d px across, its blips in %d px; view radius %d yd", half * 2, maskHalf * 2, C_Minimap.GetViewRadius()))
end

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

-- Where the Minimap's blips show on our map: a square around you (tile
-- space: centre and half its side), on while it's placed. Layers.lua's quest
-- givers step aside inside it.
local square = { on = false }
ns.BlipSquare = square

local function Update()
	square.on = false
	if Blocker() then
		T.Release()
		return
	end
	T.Engage()
	local expanded = ns.IsMapExpanded()
	local indoors = IsIndoors() and true or false
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
	local room = 2 * math.min(x, w - x, y, h - y) -- the biggest square around you in the window
	local clipTest, stretch = T.TestClip(), T.TestStretch() and w / h or 1
	if clipTest then room = 2 * math.max(w, h) end -- (experiment: big enough for the whole window)
	local level = PickLevel(kind, zoom, room, masksFound)
	if level and still and T.SetLevel(level) then settling = SETTLE_FRAMES end
	settling = math.max(0, settling - 1)
	local d = 2 * ViewRadius(kind) / TILE_YARDS * zoom
	local mask, side = MaskFor(d, room, masksFound)
	if clipTest or stretch ~= 1 then mask, side = T.SQUARE_MASK, d end
	if expanded or not (level and still) or settling > 0 or d < MIN_DIAMETER or not mask then
		T.Hide()
		return
	end

	local inset = (d - side) / 2
	insets[1], insets[2] = math.max(inset, d / 2 - x), math.max(inset, d / 2 - (w - x))
	insets[3], insets[4] = math.max(inset, d / 2 - y), math.max(inset, d / 2 - (h - y))
	T.Place(cam.canvas, cam.playerCol * zoom, -cam.playerRow * zoom, d, mask, insets, syncCheck and syncCheck.alpha or 0, stretch)
	square.on, square.col, square.row, square.half = true, cam.playerCol, cam.playerRow, side / 2 / zoom
	ReportSync(level, kind, d, zoom, side, mask)
end

-- After the map's own OnUpdate, so the view has already moved this frame.
ns.frame:HookScript("OnUpdate", ns.Timed("minimap", Update))
ns.frame:HookScript("OnHide", T.Release)

ns.On("Loaded", function(savedDB)
	db = savedDB
	db.minimapClip = nil -- an earlier version's setting (/mm clip)
end)
