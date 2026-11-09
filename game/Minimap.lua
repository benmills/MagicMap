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
end

local Unoverlay -- (the overlay's, below)
local function Release()
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
-- UpdateMouseoverAtPoint is ignored for it, so MagicMap draws no blips of its own): over our tiles, centred on you, sized so its view
-- radius (read each frame) is as many yards as ours, no ground, its own icons and arrow (ours hides: obs.minimap.overlaid).
-- Its square must cover the window around you (half >= need: you to the window's furthest edge) and be whole on the
-- screen (half <= room: you to the screen's nearest edge; a part off it, the client draws its map shifted back on). Its
-- zoom (0 widest .. 5) is the one whose square covers the window the tightest and fits; none covers: the widest that
-- fits, while it covers COVER of the need (else it fades out: zoomed or panned too far out); none fits (too far in, by
-- a screen edge): unseen at once. A square past the window is clipped to it (a clipping frame) and masked square.
-- A new zoom's radius applies a frame or two late: unseen SETTLE frames, then it fades in.
local ZOOMS, EDGE, COVER, STICK = 5, 2, 0.75, 0.98
local FADE_IN, FADE_OUT = 0.15, 0.12 -- s
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
-- The clipping frame: the window's view, the Minimap inside it while the overlay is seen.
local clip = CreateFrame("Frame", nil, UIParent)
clip:SetClipsChildren(true)
local clipAt
local function Clip(mm, p, w)
	if clipAt ~= p then
		clipAt = p
		clip:ClearAllPoints()
		clip:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.left, p.top)
		clip:SetSize(p.w, p.h)
	end
	clip:SetFrameStrata(w.strata)
	clip:SetFrameLevel(w.level + OVER - 1)
	if mm:GetParent() ~= clip then mm:SetParent(clip) end
end
local function Unclip(mm)
	if mm:GetParent() == clip then mm:SetParent(UIParent) end
	clipAt = nil
end
local Mouse
-- A radius one of its zooms has (indoors or out: Game.MinimapYards), within ODD of it.
local ODD = 0.05
local function Plausible(z, r)
	local out, inside = Game.MinimapYards(false)[z], Game.MinimapYards(true)[z]
	return out ~= nil and (math.abs(r - out / 2) <= ODD * out / 2 or math.abs(r - inside / 2) <= ODD * inside / 2)
end
local CALM = 2 -- frames our zoom and its radius stay still before it's seen
local Put -- (below)
local SETTLE = 3 -- frames unseen after a new zoom (GetZoom has it at once; its radius, a frame or two later)
local alpha, lastT = 0, nil
local function SetAlpha(mm, a)
	alpha = a
	if mm:GetAlpha() ~= a then mm:SetAlpha(a) end
	m.overlaid = a >= 0.5
	Mouse(a > 0)
end
local function Hide(mm)
	SetAlpha(mm, 0)
	placed = nil
end
-- The zoom whose square covers the window tightest (near enough: STICK) and fits; none covers:
-- the widest that fits, and whether it covers COVER of the need. nil: none fits.
local function Choose(perYd, need, room)
	for z = ZOOMS, 0, -1 do -- (near enough: a step's zoom covers just so, give or take a little)
		local h = Radius(z) * perYd
		if h <= room and h >= need * STICK then return z, true end
	end
	for z = 0, ZOOMS do
		local h = Radius(z) * perYd
		if h <= room then return z, h >= need * COVER end
	end
	return nil
end
local function Overlay(w, here, inst)
	local mm = Minimap
	local now = GetTime()
	local dt = lastT and math.min(now - lastT, 0.1) or 0
	lastT = now
	local r, p = C_Minimap.GetViewRadius(), w.place
	m.maxZoom, m.stepsOn = nil, false
	if not here or here.w <= 0 or not r or issecretvalue(r) then return Hide(mm) end
	local z = mm:GetZoom()
	-- A radius none of its zooms has (seen once over a zone change: its blips drawn far apart, the overlay sized for
	-- another): unseen, and not learnt, till it's one again. m.odd: the last such, for /mm overlay.
	if r > 0 and not Plausible(z, r) then m.odd = r; return Hide(mm) end
	if r > 0 and z == (m.zoom or 0) then
		local key = inst .. (Game.Indoors() and "i" or "o") -- (indoors, its zooms see less)
		if radii.key ~= key then radii = { key = key } end
		radii[z] = r
	end
	local k = p.w / here.w -- /: never 0 (checked above)
	local perYd = YD * here.zoom * k -- screen units a yard
	local x, y = p.left + here.x * k, p.top - here.y * k
	local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
	local room = math.min(x, y, sw - x, sh - y) - EDGE -- the most half it may have
	local need = math.max(x - p.left, p.left + p.w - x, p.top - y, y - (p.top - p.h)) -- the half that covers the window
	-- The map's zoom (view pixels a tile) at which its closest zoom just fits: Path to zooms in no further (ui/Motion.lua).
	if room > 0 then m.maxZoom = room / (Radius(ZOOMS) * YD * k) end -- /: never 0 (a radius > 0, YD, k > 0)
	m.need, m.room = need, room
	-- The steps: the map's zoom at which each of its zooms covers the window just so (Motion zooms by them while you're
	-- followed, as Blizzard's Minimap zooms: ui/Motion.lua); none while no square that covers fits.
	local steps = m.steps
	if need <= room then
		for i = 0, ZOOMS do steps[i + 1] = need / (Radius(i) * YD * k) end -- /: never 0 (a radius > 0, YD, k > 0)
		m.stepsOn = true
	else
		m.stepsOn = false
	end
	local want, good = Choose(perYd, need, room)
	if not want then return Hide(mm) end -- (too far in, or by a screen edge)
	if want ~= (m.zoom or 0) then m.zoom, m.settle, m.snap = want, SETTLE, true; mm:SetZoom(want); return Hide(mm) end
	if r <= 0 or z ~= want then return Hide(mm) end -- (a new zoom applies a frame or two late)
	if (m.settle or 0) > 0 then m.settle = m.settle - 1; return Hide(mm) end
	-- Unseen while our zoom moves (a glide resizes it every frame; the client draws a size a frame late: its blips
	-- swam) or its radius does (a new zoom's lands over a frame or two), till both are CALM frames still.
	if here.zoom ~= m.lastZoom or r ~= m.lastR then m.calm = 0 else m.calm = (m.calm or 0) + 1 end
	m.lastZoom, m.lastR = here.zoom, r
	if m.calm < CALM then return Hide(mm) end
	local half = r * perYd
	if half > room + EDGE then return Hide(mm) end -- (its radius not the guess: the next frame's choice sees to it)
	-- Seen: fading in, or out (too little of the window covered: still placed, so it fades where it is).
	local a = good and math.min(1, alpha + dt / FADE_IN) or math.max(0, alpha - dt / FADE_OUT) -- /: never 0 (constants)
	if good and m.snap then a = 1 end -- (a new zoom of its own, as Blizzard's: at once, no fade)
	m.snap = false
	Put(mm, w, x, y, half, a)
end
-- Seen at alpha a (none: unseen), square, clipped to the window, centred at (x, y), half on a side.
function Put(mm, w, x, y, half, a)
	SetAlpha(mm, a)
	if a <= 0 then placed = nil; return end
	local p = w.place
	Mask(true)
	Clip(mm, p, w)
	mm:SetFrameStrata(w.strata)
	mm:SetFrameLevel(w.level + OVER)
	local cx, cy = mm:GetCenter() -- (moved or sized by anyone else: put back, spike-bugs G3)
	if placed and placed.overlay and math.abs(placed.x - x) < 0.05 and math.abs(placed.y - y) < 0.05
		and math.abs(placed.half - half) < 0.05 and cx and math.abs(cx - x) < 0.5 and math.abs(cy - y) < 0.5
		and math.abs(mm:GetWidth() - half * 2) < 0.5 then return end
	placed = { overlay = true, x = x, y = y, half = half }
	mm:SetIconScale(1)
	mm:SetSize(half * 2, half * 2)
	mm:ClearAllPoints()
	mm:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
end
-- In an instance (the client withholds where you are: our map has nothing to show), Blizzard's Minimap as it is, ground
-- and all, over the map UI blanks (obs.minimap.instance): centred, covering the window (as much as fits on the screen).
-- Its zoom the step nearest the map's zoom (obs.minimap.steps as outdoors, so the wheel steps through them).
local function Instance(w, view)
	local mm = Minimap
	local r, p, cam = C_Minimap.GetViewRadius(), w.place, view.camera
	m.maxZoom, m.stepsOn = nil, false
	if not cam or cam.w <= 0 then return Hide(mm) end
	local x, y = p.left + p.w / 2, p.top - p.h / 2
	local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
	local room = math.min(x, y, sw - x, sh - y) - EDGE
	local need = math.max(p.w, p.h) / 2
	if room <= 0 then return Hide(mm) end
	local k = p.w / cam.w -- /: never 0 (checked above)
	local steps, want, best = m.steps, 0, nil
	for i = 0, ZOOMS do
		steps[i + 1] = need / (Radius(i) * YD * k) -- /: never 0 (a radius > 0, YD, k > 0)
		local d = math.abs(math.log(steps[i + 1] / cam.zoom)) -- /: never 0 (a zoom > 0)
		if not best or d < best then want, best = i, d end
	end
	m.stepsOn, m.need, m.room = true, need, room
	if want ~= (m.zoom or 0) then m.zoom, m.settle = want, SETTLE; mm:SetZoom(want); return Hide(mm) end
	if (m.settle or 0) > 0 then m.settle = m.settle - 1; return Hide(mm) end
	if not r or issecretvalue(r) or r <= 0 then return Hide(mm) end
	Put(mm, w, x, y, math.min(need, room), 1)
end

-- Off (the overlay, or the takeover): out of the clip, its mask back.
function Unoverlay()
	local mm = Minimap
	Unclip(mm)
	Mask(false)
	alpha, lastT, m.overlaid = 0, nil, false
end

-- Its blips' tooltips: seen, it takes the mouse's motion (not clicks or the wheel: those go through to our map), and
-- while it has it our OnUpdate stands for Blizzard's (Minimap_OnUpdate filled GameTooltip every frame, blip or not,
-- over our pins' and areas' tooltips): Blizzard's tooltip only while a blip is under the cursor (m.blip), hidden as it
-- leaves one. Game.minimap.mouse / blip go to UI (obs.minimap): our pins hover through it and give way to a blip.
local function Named()
	local data = C_TooltipInfo.GetMinimapMouseover()
	if not data or issecretvalue(data) or issecretvalue(data.lines) then return false end
	local line = data.lines and data.lines[1]
	local t = line and line.leftText
	return t ~= nil and (issecretvalue(t) or t ~= "")
end
local BlipTip = Runtime.Wrap("game: overlay tooltip", function()
	if Named() then
		m.blip = true
		GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
		GameTooltip:SetMinimapMouseover()
	elseif m.blip then
		m.blip = false
		if GameTooltip:GetOwner() == UIParent then GameTooltip:Hide() end
	end
end)
Minimap:HookScript("OnEnter", Runtime.Wrap("game: overlay entered", function(self)
	m.mouse = true
	self:SetScript("OnUpdate", BlipTip) -- (after Blizzard's OnEnter set its own)
end))
Minimap:HookScript("OnLeave", Runtime.Wrap("game: overlay left", function()
	m.mouse, m.blip = false, false
end))
function Mouse(on)
	local mm = Minimap
	if on then
		if not mm:IsMouseMotionEnabled() then mm:SetMouseMotionEnabled(true) end
		if mm:IsMouseClickEnabled() then mm:SetMouseClickEnabled(false) end
		if mm:IsMouseWheelEnabled() then mm:EnableMouseWheel(false) end
	elseif mm:IsMouseEnabled() or mm:IsMouseMotionEnabled() then
		mm:EnableMouse(false)
		mm:SetScript("OnUpdate", nil)
		m.mouse, m.blip = false, false
	end
end

Game.Slash("overlay", "the blips' overlay (Blizzard's Minimap over the map): where it is, why it hides", function()
	local mm = Minimap
	local l, b, w, h = mm:GetRect()
	Game.Say(("overlay: rect %s %s %s %s, UI %dx%d, zoom %d, radius %s, put %s"):format(
			tostring(l and math.floor(l)), tostring(b and math.floor(b)), tostring(w and math.floor(w)),
			tostring(h and math.floor(h)), UIParent:GetWidth(), UIParent:GetHeight(), mm:GetZoom(),
			tostring(C_Minimap.GetViewRadius()),
			(placed and placed.overlay and ("centre %d, %d, half %d"):format(placed.x, placed.y, placed.half) or "-")
				.. (", need %s, room %s, alpha %.2f, odd radius %s, instance %s"):format(tostring(m.need and math.floor(m.need)),
				tostring(m.room and math.floor(m.room)), mm:GetAlpha(), tostring(m.odd), tostring(m.instance))))
end)

Game.Apply("minimap", function(view)
	local w = view.window
	m.blocker = FarmHud and FarmHud.IsShown and FarmHud:IsShown() and "FarmHud has the minimap" or nil
	if view.minimap ~= "ours" or not (w.shown and w.place) or m.blocker then
		Release()
	else
		if not m.engaged then Engage() end
		local _, kind = GetInstanceInfo()
		m.instance = kind ~= nil and kind ~= "none" and not view.here -- (where it keeps where you are, the overlay)
		Hold(Minimap)
		if m.instance then
			Instance(w, view)
		elseif w.big then -- (the big map: no blips over it, your arrow ours)
			m.maxZoom, m.stepsOn = nil, false
			Hide(Minimap)
		else
			Overlay(w, view.here, view.inst)
		end
	end
	Cluster()
end)

Runtime.On("PLAYER_LOGOUT", "game.minimap logout", Release)
