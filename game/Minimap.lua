-- The Minimap takeover (the spike's MinimapTakeover.lua), in the apply phase (Game.Apply),
-- from View (types/view.lua):
--   View.minimap "ours" and the window shown (nothing blocking): Blizzard's
--     Minimap becomes the overlay (below): its blips over our map, north up, no ground, its
--     clicks and wheel ours (each put right every apply: other client code turns them back).
--     What hung on it waits on a stand-in at its home spot; the cluster hides.
--     HereBeDragons' minimap pins go to hosts of Game's (game/AddonPins.lua): on the Minimap
--     they'd take the mouse, over our map.
--   otherwise (or a View Game can't use: SAFE, game/Apply.lua): released, every change undone.
-- Every change Engage makes is paired with its undo on a list; Release runs it
-- backwards, so what comes back is exactly what was taken. But the cluster: its Show and
-- Hide are refused in combat (it's protected: spike-bugs K2), so each apply puts it right
-- once they aren't, hidden while engaged and as it was otherwise; meanwhile, engaged, it's
-- faded (Game.minimap.fade: game/Home.lua; alpha isn't refused).
-- Game.minimap (obs.minimap: game/parts/MinimapState.lua) tells UI where things stand.

local _, ns = ...
local Game, Runtime, Atlas = ns.Game, ns.Runtime, ns.Atlas


local OVER = 30         -- the overlay's frame level above the window's (over the tiles, under the chrome)
local YD = 1 / Atlas.TILE_YARDS
local m = { engaged = false, fade = false, steps = {} } -- blocker: why it isn't taken
Game.minimap = m
local undo, placed = {}, nil
local clusterShown -- the cluster's own shown state, from an engage until it's back

local standIn = CreateFrame("Frame", "MagicMapMinimapStandIn", UIParent)
standIn:Hide()

local function OnRelease(fn) undo[#undo + 1] = fn end
local ZOOMS = 5 -- Blizzard's Minimap's zooms: 0 (widest) .. ZOOMS (game/parts/MinimapState.lua's yards)
-- A line in chat once a session (key: which).
local said = {} -- the chat lines said this session, by key
local function SayOnce(key, msg)
	if said[key] then return end
	said[key] = true
	Game.Say(msg)
end

-- A pin travels with the Minimap: a copy's that stayed there, or GatherMate's (MinimapTakeover.lua:124-129).
local function IsPin(obj)
	for _, copy in ipairs(Game.PinLibs()) do
		if copy.lib.minimapPins[obj] then return true end
	end
	return obj:GetDebugName():find("GatherMatePin", 1, true) ~= nil
end

-- Swap anchors relative to `from` for the same anchors relative to `to` (true if any).
local function Reanchor(obj, from, to)
	local points = {}
	for i = 1, obj:GetNumPoints() do
		local p, rel, rp, x, y = obj:GetPoint(i)
		if rel == from then points[#points + 1] = { p, rp, x, y } end
	end
	for _, p in ipairs(points) do obj:SetPoint(p[1], to, p[2], p[3], p[4]) end
	return #points > 0
end

-- A new parent, keeping the draw layer (regions) or strata and level (frames: the client
-- re-bases them on the new parent) (MinimapTakeover.lua:181-195).
local function Reparent(obj, parent)
	local layer, sublevel, strata, level
	if obj.GetDrawLayer then
		layer, sublevel = obj:GetDrawLayer()
	else
		strata, level = obj:GetFrameStrata(), obj:GetFrameLevel()
	end
	obj:SetParent(parent)
	if layer then
		obj:SetDrawLayer(layer, sublevel)
	else
		obj:SetFrameStrata(strata)
		obj:SetFrameLevel(level)
	end
end

local function Move(obj, from, to)
	local t = obj:GetObjectType()
	if t == "Line" or t == "MaskTexture" or (obj.IsProtected and obj:IsProtected()) or IsPin(obj) then return end
	Reparent(obj, to)
	Reanchor(obj, from, to)
	OnRelease(function()
		Reparent(obj, from)
		Reanchor(obj, to, from)
	end)
end

-- Blizzard's parts that hang off the Minimap without being its children (borders, the zone
-- text, its buttons), a few levels down from the cluster: onto the stand-in (MinimapTakeover.lua:215-229).
local function ReanchorAround(frame, depth)
	local function One(obj)
		if Reanchor(obj, Minimap, standIn) then
			OnRelease(function() Reanchor(obj, standIn, Minimap) end)
		end
	end
	for _, obj in ipairs({ frame:GetRegions() }) do One(obj) end
	for _, child in ipairs({ frame:GetChildren() }) do
		if child ~= Minimap and child ~= standIn and not (child.IsProtected and child:IsProtected()) then
			One(child)
			if depth > 1 then ReanchorAround(child, depth - 1) end
		end
	end
end

-- The cluster hidden while engaged, else as it was; its state forgotten once it's back.
local function Cluster()
	local c = MinimapCluster
	if m.engaged and clusterShown == nil then clusterShown = c:IsShown() end
	if clusterShown == nil then return end
	local want = not m.engaged and clusterShown
	if c:IsShown() ~= want and not InCombatLockdown() then c:SetShown(want) end
	m.fade = m.engaged and c:IsShown()
	if not m.engaged and c:IsShown() == clusterShown then clusterShown = nil end
end

-- Taken (MinimapTakeover.lua:434-443): unseen till the overlay places it, no mouse, no ground.
local function Init()
	local mm = Minimap
	mm:SetAlpha(0)
	mm:SetIconScale(1)
	mm:EnableMouse(false)
	mm:EnableMouseWheel(false)
	C_Minimap.SetDrawGroundTextures(false)
	placed = nil
end

local function Engage()
	m.engaged = true
	local levels = Minimap.GetZoomLevels and Minimap:GetZoomLevels()
	if levels and levels ~= ZOOMS + 1 then
		SayOnce("zooms", ("Blizzard's minimap has %d zooms, not the %d MagicMap knows (a game update?): its blips "
			.. "may not line up with the map. /mm overlay for details."):format(levels, ZOOMS + 1))
	end
	Game.PinLibs(true) -- any copy loaded since (its pins travel with the Minimap: IsPin)
	-- Undone last: the pins back on the Minimap once it's back at its own size (MinimapTakeover.lua:338-344).
	OnRelease(Game.MinimapPinsHome)
	local mm = Minimap
	local parent, w, h = mm:GetParent(), mm:GetSize()
	local points = {}
	for i = 1, mm:GetNumPoints() do points[i] = { mm:GetPoint(i) } end
	local scale, strata, level, zoom, alpha = mm:GetScale(), mm:GetFrameStrata(), mm:GetFrameLevel(), mm:GetZoom(), mm:GetAlpha()
	local ground, unrotated = C_Minimap.GetDrawGroundTextures(), C_Minimap.IsRotateMinimapIgnored()
	local mouse, wheel, shown = mm:IsMouseEnabled(), mm:IsMouseWheelEnabled(), mm:IsShown()
	local clamped = mm:IsClampedToScreen()
	-- The stand-in takes the Minimap's place exactly (hidden: it only holds things).
	standIn:SetParent(parent)
	standIn:SetScale(scale)
	standIn:SetFrameStrata(strata)
	standIn:SetFrameLevel(level)
	standIn:ClearAllPoints()
	for _, p in ipairs(points) do standIn:SetPoint(unpack(p)) end
	standIn:SetSize(w, h)
	for _, obj in ipairs({ mm:GetChildren() }) do Move(obj, mm, standIn) end
	for _, obj in ipairs({ mm:GetRegions() }) do Move(obj, mm, standIn) end
	ReanchorAround(MinimapCluster, 3)
	-- Undone first: the Minimap back in its place before what hung on it comes back to it
	-- (a parent moved re-bases what it holds).
	OnRelease(function()
		mm:SetParent(parent)
		mm:ClearAllPoints()
		for _, p in ipairs(points) do mm:SetPoint(unpack(p)) end
		mm:SetSize(w, h)
		mm:SetScale(scale)
		mm:SetFrameStrata(strata)
		mm:SetFrameLevel(level)
		mm:EnableMouse(mouse)
		mm:EnableMouseWheel(wheel)
		mm:SetClampedToScreen(clamped)
		mm:SetAlpha(alpha)
		mm:SetIconScale(1) -- (the client's own; it can't be read back)
		C_Minimap.SetDrawGroundTextures(ground)
		C_Minimap.SetIgnoreRotateMinimap(unrotated)
		mm:SetZoom(zoom)
		mm:SetShown(shown)
	end)
	mm:SetParent(UIParent)
	mm:SetScale(1)
	Init()
	C_Minimap.SetIgnoreRotateMinimap(true)
	mm:Show()
	Runtime.Trace("minimap", "engaged")
	return true
end

local Unoverlay, Untip -- (the overlay's and its tooltips', below)
local Release
-- Engage all or nothing: one that fails part way (another addon's frame on the Minimap that won't move, say) is
-- recorded as any error (Runtime: /mm errors), what it had taken given back at once (Release), and not tried again
-- this session (m.failed: the blocker), with one line in chat. Blizzard's minimap stays as it was meanwhile.
local TryEngage = Runtime.Wrap("game: minimap engage", Engage, false)
local function Take()
	if TryEngage() then return true end
	m.failed = true
	pcall(Release)
	SayOnce("failed", "couldn't put Blizzard's minimap blips over the map (/mm errors has why), so they're off this "
		.. "session: Blizzard's minimap is as it was. /reload to try again.")
	return false
end
function Release()
	if not m.engaged then return end
	m.engaged, m.instance, placed = false, false, nil
	Unoverlay()
	local failure
	for i = #undo, 1, -1 do -- every step runs; the first failure is raised after
		local ok, err = pcall(undo[i])
		if not ok and not failure then failure = err end
		undo[i] = nil
	end
	Cluster()
	Untip()
	Runtime.Trace("minimap", "released")
	if failure then error(failure, 0) end
end

-- What other client code turns back (HybridMinimap turns its ground and rotation on as it
-- hides: spike-bugs G3), or anyone zooms, hides or shows it, put right every apply. True if it held.
local function Hold(mm)
	local zoom = m.zoom or 0
	local held = mm:IsShown() and mm:GetZoom() == zoom and C_Minimap.IsRotateMinimapIgnored()
	if not mm:IsShown() then mm:Show() end
	if mm:GetZoom() ~= zoom then mm:SetZoom(zoom) end
	if C_Minimap.GetDrawGroundTextures() ~= (m.instance == true) then C_Minimap.SetDrawGroundTextures(m.instance == true) end
	if not C_Minimap.IsRotateMinimapIgnored() then C_Minimap.SetIgnoreRotateMinimap(true) end
	return held
end

-- The overlay: Blizzard's Minimap itself, seen, draws the blips (since 1.60.1.70862 addon code can't read them:
-- UpdateMouseoverAtPoint is ignored for it, so MagicMap draws no blips of its own): over our tiles, centred on you, sized
-- so its view radius (read each frame) is as many yards as ours, no ground, masked square, its own icons and arrow (ours
-- hides: obs.minimap.overlaid). Its square is the biggest centred on you that's inside the window (half <= inside: you to
-- the window's nearest edge; past it, the client shifts its drawing back in: blips off where they are, 70862) and whole
-- on the screen (half <= room; likewise). Its zoom (0 widest .. 5): the widest whose square fits, seen while it fills
-- COVER of that (else zoomed too far out: unseen); none fits (too far in): unseen. Unseen is out of sight, not alpha 0
-- (its icons and arrow ignore alpha): its icons a speck, beneath the window. A new zoom's radius applies a frame or two
-- late: unseen SETTLE frames, then till our zoom and its radius are CALM frames still.
local EDGE, STICK, COVER = 2, 1.02, 0.75
local SPECK = 0.05 -- its icons' scale unseen (alpha alone doesn't hide them: the sensor's ICONS)
-- (ROUND: the client's round alpha mask, as its own Minimap's, when nothing else set one)
local SQUARE, ROUND = "Interface\\ChatFrame\\ChatFrameBackground", "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local radii = {} -- the view radius seen at each zoom (this map kind); else half the yards across it has (Game.MinimapYards)
local function Radius(z)
	if radii[z] then return radii[z] end
	local yd = Game.MinimapYards(Game.Indoors())
	return yd[z] / 2
end
-- The mask others set (Leatrix's square, say), put back once the overlay lets go.
local mask, masked = nil, false
if Minimap.SetMaskTexture then
	hooksecurefunc(Minimap, "SetMaskTexture", function(_, t) if not masked then mask = t end end)
end
local function Mask(on)
	local mm = Minimap
	if on == masked or not mm.SetMaskTexture then return end
	masked = on
	if on then mm:SetMaskTexture(SQUARE) else mm:SetMaskTexture(mask or ROUND) end
end
local Mouse
-- A radius one of its zooms has (indoors or out: Game.MinimapYards), within ODD of it.
local ODD = 0.05
local ODD_FOR = 5 -- s a radius stays odd before it's said in chat (a zone change's is gone in a frame or two)
local function Plausible(z, r)
	local out, inside = Game.MinimapYards(false)[z], Game.MinimapYards(true)[z]
	return out ~= nil and (math.abs(r - out / 2) <= ODD * out / 2 or math.abs(r - inside / 2) <= ODD * inside / 2)
end
local CALM = 2 -- frames our zoom and its radius stay still before it's seen
local SETTLE = 3 -- frames unseen after a new zoom (GetZoom has it at once; its radius, a frame or two later)
local seen -- (nil: not yet set either way)
-- Seen, or out of sight: alpha 0, its icons a speck, beneath the window (w: View.window, its strata and level).
local function See(mm, on, w)
	if on ~= seen then
		seen = on
		mm:SetAlpha(on and 1 or 0)
		mm:SetIconScale(on and 1 or SPECK)
		m.overlaid = on
		Mouse(on)
	end
	if w then
		mm:SetFrameStrata(w.strata)
		local level = on and w.level + OVER or math.max(0, w.level - 1)
		if mm:GetFrameLevel() ~= level then mm:SetFrameLevel(level) end
	end
end
local function Hide(mm, w)
	See(mm, false, w)
	placed = nil
end
-- The widest zoom whose square (half Radius * perYd) fits in limit (near enough: STICK), and whether it fills COVER of
-- it. nil: none fits.
local function Choose(perYd, limit)
	for z = 0, ZOOMS do
		local h = Radius(z) * perYd
		if h <= limit * STICK then return z, h >= limit * COVER end
	end
	return nil
end
-- Seen: square, centred at (x, y), half on a side.
local function Put(mm, w, x, y, half)
	See(mm, true, w)
	Mask(true)
	local cx, cy = mm:GetCenter() -- (moved or sized by anyone else: put back, spike-bugs G3)
	if placed and math.abs(placed.x - x) < 0.05 and math.abs(placed.y - y) < 0.05
		and math.abs(placed.half - half) < 0.05 and cx and math.abs(cx - x) < 0.5 and math.abs(cy - y) < 0.5
		and math.abs(mm:GetWidth() - half * 2) < 0.5 then return end
	placed = { x = x, y = y, half = half }
	mm:SetSize(half * 2, half * 2)
	mm:ClearAllPoints()
	mm:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
end
-- The steps (obs.minimap.steps): the map's zoom at which each of its zooms' square is the biggest that fits, as if you
-- were in the window's middle (as following has you: they hold still while it's panned). Motion zooms by them while
-- you're followed, as Blizzard's Minimap zooms (ui/Motion.lua). k: screen units a view pixel.
local function Steps(p, k)
	local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
	local cx, cy = p.left + p.w / 2, p.top - p.h / 2
	local limit = math.min(p.w / 2, p.h / 2, cx - EDGE, cy - EDGE, sw - cx - EDGE, sh - cy - EDGE)
	m.stepsOn = limit > 0
	if not m.stepsOn then return end
	for i = 0, ZOOMS do m.steps[i + 1] = limit / (Radius(i) * YD * k) end -- /: never 0 (a radius > 0, YD, k > 0)
	m.minZoom = m.steps[1] * COVER -- (further out, its widest fills less than COVER: unseen)
end
local function Overlay(w, here, inst)
	local mm = Minimap
	local r, p = C_Minimap.GetViewRadius(), w.place
	m.maxZoom, m.stepsOn = nil, false
	if not here or here.w <= 0 or not r or issecretvalue(r) then return Hide(mm, w) end
	local z = mm:GetZoom()
	-- A radius none of its zooms has (seen once over a zone change: its blips drawn far apart, the overlay sized for
	-- another): unseen, and not learnt, till it's one again. m.odd: the last such, for /mm overlay.
	if r > 0 and not Plausible(z, r) then
		m.odd = r
		m.oddSince = m.oddSince or GetTime()
		if GetTime() - m.oddSince >= ODD_FOR then
			SayOnce("odd", ("Blizzard's minimap zooms aren't the sizes MagicMap knows (radius %.0f yd at zoom %d: a game "
				.. "update?), so its blips are hidden over the map. /mm overlay for details."):format(r, z))
		end
		return Hide(mm, w)
	end
	m.oddSince = nil
	if r > 0 and z == (m.zoom or 0) then
		local key = inst .. (Game.Indoors() and "i" or "o") -- (indoors, its zooms see less)
		if radii.key ~= key then radii = { key = key } end
		radii[z] = r
	end
	local k = p.w / here.w -- /: never 0 (checked above)
	local perYd = YD * here.zoom * k -- screen units a yard
	local x, y = p.left + here.x * k, p.top - here.y * k
	local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
	local room = math.min(x, y, sw - x, sh - y) - EDGE -- on the screen
	local inside = math.min(x - p.left, p.left + p.w - x, p.top - y, y - (p.top - p.h)) -- in the window
	local limit = math.min(room, inside)
	m.need, m.room = inside, room
	Steps(p, k)
	if limit <= 0 then return Hide(mm, w) end -- (you off the window, or the screen)
	-- The map's zoom (view pixels a tile) at which its closest zoom just fits: Path to zooms in no further (ui/Motion.lua).
	m.maxZoom = limit / (Radius(ZOOMS) * YD * k) -- /: never 0 (a radius > 0, YD, k > 0)
	local want, good = Choose(perYd, limit)
	if not want then return Hide(mm, w) end -- (too far in)
	if want ~= (m.zoom or 0) then m.zoom, m.settle = want, SETTLE; mm:SetZoom(want); return Hide(mm, w) end
	if r <= 0 or z ~= want then return Hide(mm, w) end -- (a new zoom applies a frame or two late)
	if (m.settle or 0) > 0 then m.settle = m.settle - 1; return Hide(mm, w) end
	-- Unseen while our zoom moves (a glide resizes it every frame; the client draws a size a frame late: its blips
	-- swam) or its radius does (a new zoom's lands over a frame or two), till both are CALM frames still.
	if here.zoom ~= m.lastZoom or r ~= m.lastR then m.calm = 0 else m.calm = (m.calm or 0) + 1 end
	m.lastZoom, m.lastR = here.zoom, r
	if m.calm < CALM or not good then return Hide(mm, w) end -- (not good: zoomed too far out)
	local half = r * perYd
	if half > limit * STICK then return Hide(mm, w) end -- (its radius not the guess: the next frame's choice sees to it)
	Put(mm, w, x, y, half)
end
-- In an instance (the client withholds where you are: our map has nothing to show), Blizzard's Minimap as it is, ground
-- and all, over the map UI blanks (obs.minimap.instance): the biggest square centred in the window. Its zoom the step
-- nearest the map's zoom (obs.minimap.steps as outdoors, so the wheel steps through them).
local function Instance(w, view)
	local mm = Minimap
	local p, cam = w.place, view.camera
	m.maxZoom, m.stepsOn = nil, false
	if not cam or cam.w <= 0 then return Hide(mm, w) end
	local k = p.w / cam.w -- /: never 0 (checked above)
	Steps(p, k)
	if not m.stepsOn then return Hide(mm, w) end
	local want, best = 0, nil
	for i = 0, ZOOMS do
		local d = math.abs(math.log(m.steps[i + 1] / cam.zoom)) -- /: never 0 (a zoom > 0)
		if not best or d < best then want, best = i, d end
	end
	-- A new zoom applied as it stays shown: its square the same size at every zoom (the steps fit it so), no tiles of
	-- ours under it to line up with, so nothing to wait for (hidden, the black curtain showed while you zoomed).
	if want ~= (m.zoom or 0) then m.zoom = want; mm:SetZoom(want) end
	local x, y = p.left + p.w / 2, p.top - p.h / 2
	Put(mm, w, x, y, m.steps[want + 1] * Radius(want) * YD * k)
end

-- Off (the overlay, or the takeover): its mask back.
function Unoverlay()
	Mask(false)
	seen, m.overlaid = nil, false
end

-- Its blips' tooltips: seen, it takes the mouse's motion (not clicks or the wheel: those go through to our map), and
-- while it has it our OnUpdate stands for Blizzard's (Minimap_OnUpdate filled GameTooltip every frame, blip or not,
-- over our pins' and areas' tooltips). On a blip (m.blip), the names under the cursor (stacked blips each: the
-- tooltip's lines, split at line breaks, their colours dropped) go to UI as m.names (obs.minimap.names), which draws
-- them our way (ui/BlipTip.lua); one the client keeps secret: Blizzard's own tooltip, as it was. Off a blip, the
-- tooltip hidden. Game.minimap.mouse / blip go to UI too: our pins hover through it and give way to a blip.
local names, marks, shown, shownMarks = {}, {}, {}, {}
-- A blip above or below you: the client's arrow, a texture escape in its name (|T...|t or |A...|a), split off it: the
-- name alone (what Atlas knows), the escape kept beside it (marks[i], "" for none) for UI to draw.
local function Split(part)
	local mark = part:match("|T.-|t") or part:match("|A.-|a") or ""
	if mark ~= "" then part = part:gsub("|T.-|t", ""):gsub("|A.-|a", "") end
	return part:match("^%s*(.-)%s*$"), mark
end
-- The names under the cursor into `names` (their count; their marks into `marks`), or false: secret (Blizzard's
-- tooltip then), nil: none.
local function Names()
	local data = C_TooltipInfo.GetMinimapMouseover()
	if not data or issecretvalue(data) or issecretvalue(data.lines) or not data.lines then return nil end
	local n = 0
	for _, line in ipairs(data.lines) do
		local t = line.leftText
		if t ~= nil then
			if issecretvalue(t) then return false end
			for part in t:gmatch("[^\n]+") do
				local name, mark = Split(part:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
				if name ~= "" then n = n + 1; names[n], marks[n] = name, mark end
			end
		end
	end
	for i = #names, n + 1, -1 do names[i], marks[i] = nil, nil end
	return n > 0 and n or nil
end
-- m.names (and m.marks) new tables only when they changed (UI rebuilds its tooltip then).
local function Publish(n)
	local same = m.names ~= nil and #shown == n
	for i = 1, n do
		if shown[i] ~= names[i] or shownMarks[i] ~= marks[i] then same = false end
	end
	if same then return end
	shown, shownMarks = {}, {}
	for i = 1, n do shown[i], shownMarks[i] = names[i], marks[i] end
	m.names, m.marks = shown, shownMarks
end
local BlipTip = Runtime.Wrap("game: overlay tooltip", function()
	local n = Names()
	if n == false then
		m.blip, m.names = true, nil
		GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
		GameTooltip:SetMinimapMouseover()
	elseif n then
		if m.blip and not m.names and GameTooltip:GetOwner() == UIParent then GameTooltip:Hide() end -- (Blizzard's, before)
		m.blip = true
		Publish(n)
	elseif m.blip then
		m.blip, m.names = false, nil
		if GameTooltip:GetOwner() == UIParent then GameTooltip:Hide() end
	end
end)
-- (A hook can't be undone: released, these leave Blizzard's Minimap to itself, its own tooltips.)
Minimap:HookScript("OnEnter", Runtime.Wrap("game: overlay entered", function(self)
	if not m.engaged then return end
	m.mouse = true
	self:SetScript("OnUpdate", BlipTip) -- (after Blizzard's OnEnter set its own)
end))
Minimap:HookScript("OnLeave", Runtime.Wrap("game: overlay left", function()
	m.mouse, m.blip, m.names = false, false, nil
end))
-- Released: our tooltip handler off the Minimap and its state cleared; under the cursor, Blizzard's OnEnter again
-- (its own OnUpdate, its tooltips).
function Untip()
	local mm = Minimap
	m.mouse, m.blip, m.names = false, false, nil
	if mm:GetScript("OnUpdate") == BlipTip then mm:SetScript("OnUpdate", nil) end
	if GameTooltip:GetOwner() == UIParent and not mm:IsMouseOver() then GameTooltip:Hide() end
	local enter = mm:GetScript("OnEnter")
	if enter and mm:IsShown() and mm:IsMouseOver() then enter(mm) end
end
function Mouse(on)
	local mm = Minimap
	if on then
		if not mm:IsMouseMotionEnabled() then mm:SetMouseMotionEnabled(true) end
		if mm:IsMouseClickEnabled() then mm:SetMouseClickEnabled(false) end
		if mm:IsMouseWheelEnabled() then mm:EnableMouseWheel(false) end
	elseif mm:IsMouseEnabled() or mm:IsMouseMotionEnabled() then
		mm:EnableMouse(false)
		mm:SetScript("OnUpdate", nil)
		m.mouse, m.blip, m.names = false, false, nil
	end
end

Game.Slash("overlay", "the blips' overlay (Blizzard's Minimap over the map): where it is, why it hides", function()
	local mm = Minimap
	local l, b, w, h = mm:GetRect()
	Game.Say(("overlay: rect %s %s %s %s, UI %dx%d, zoom %d, radius %s, put %s"):format(
			tostring(l and math.floor(l)), tostring(b and math.floor(b)), tostring(w and math.floor(w)),
			tostring(h and math.floor(h)), UIParent:GetWidth(), UIParent:GetHeight(), mm:GetZoom(),
			tostring(C_Minimap.GetViewRadius()),
			(placed and ("centre %d, %d, half %d"):format(placed.x, placed.y, placed.half) or "-")
				.. (", need %s, room %s, alpha %.2f, seen %s, odd radius %s, instance %s, blocked %s"):format(tostring(m.need and math.floor(m.need)),
				tostring(m.room and math.floor(m.room)), mm:GetAlpha(), tostring(seen), tostring(m.odd), tostring(m.instance), tostring(m.blocker))))
end)

Game.Apply("minimap", function(view)
	local w = view.window
	m.blocker = m.failed and "couldn't take the minimap (/mm errors)"
		or FarmHud and FarmHud.IsShown and FarmHud:IsShown() and "FarmHud has the minimap" or nil
	if view.minimap ~= "ours" or not (w.shown and w.place) or m.blocker then
		Release()
	elseif m.engaged or Take() then
		local _, kind = GetInstanceInfo()
		m.instance = kind ~= nil and kind ~= "none" and not view.here -- (where it keeps where you are, the overlay)
		Hold(Minimap)
		if m.instance then
			Instance(w, view)
		elseif w.big or view.pathing then -- (the big map, or a path's line: no blips over it, your arrow and zoom ours)
			m.maxZoom, m.stepsOn = nil, false
			Hide(Minimap, w)
		else
			Overlay(w, view.here, view.inst)
		end
	end
	Cluster()
end)

Runtime.On("PLAYER_LOGOUT", "game.minimap logout", Release)
