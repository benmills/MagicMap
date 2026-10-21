-- The window is the minimap: it takes the minimap's place (MinimapMode.lua:1-16).
--   * It starts on the minimap's spot, square, SPAN yards across, and keeps that as you
--     resize it. /mm reset puts it back there.
--   * M (Model.hooked "worldmap": Game hid Blizzard's world map) or the red button grows it
--     to most of the screen, in the same chrome; M, the button or Escape (hooked "escape":
--     Game's catcher, shown while View.window.big) shrink it back. While big, the Minimap's
--     home corner fades out (View.window.homeAlpha).
--   * Small, it sits at the minimap's strata (its cluster's: obs.minimap.homeStrata), so
--     other windows go over it.
--   * The rim button or the addon compartment (hooked "toggle") shows or hides it, as /mm toggle.
-- The camera's flights and zoom are Motion's (ui/Motion.lua: FlyTo, SetZoom, SetFollow).
-- Only the small window's rect and zoom are saved (SavedUI.window, zoom): never the big one,
-- so hiding or logging out while big comes back small (spike-bugs L4); growing again while
-- shrinking keeps the small rect it had (L3).

local _, ns = ...
local UI = ns.UI
local Atlas, Runtime = ns.Atlas, ns.Runtime
local Model = ns.Model
local Camera, Window, Controls, Motion = UI.Camera, UI.Window, UI.Controls, UI.Motion

local EXPAND_TIME, COLLAPSE_TIME = 0.22, 0.18 -- s (MinimapMode.lua:21)
local GROW_FLY = EXPAND_TIME + 0.1 -- s: the camera's flight out (MinimapMode.lua:172)
local EXPAND_ZOOM_OUT = 1.5 -- M zooms out this much; the window grows far more (MinimapMode.lua:22)
local EXPANDED_SIZE = 0.7 -- of the screen, each way (MinimapMode.lua:23)
local ZONE = 3 -- Enum.UIMapType.Zone (MinimapMode.lua:24)
local FIT = 0.92 -- a zone fitted with this much of the view (Core.lua:1038)
local SPAN = 200 -- yards across the small window (MinimapMode.lua:25)
local SPAN_TILES = SPAN / Atlas.TILE_YARDS

-- big: grown (View.window.big); homeAlpha: View.window.homeAlpha; home: the Minimap's home spot
-- and homeStrata its cluster's strata (Game's obs.minimap.home, an MM.ScreenRect, and homeStrata,
-- through Model.minimap), once known. Until then LOW, the cluster's in Blizzard's FrameXML.
local BigMap = { big = false, homeAlpha = 1, homeStrata = "LOW" }
UI.BigMap = BigMap

local frame = Window.frame
frame:SetFrameStrata(BigMap.homeStrata)

local small -- while big or shrinking back: the small rect { left, top, w, h, zoom } to return to
local restoreAlpha = 1 -- the home corner's alpha before growing
local tween, loaded

local function EaseOutCubic(t) return 1 - (1 - t) ^ 3 end

local function SetRect(left, top, w, h)
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
	frame:SetSize(w, h)
end

-- The small window's rect, kept (SavedUI.window); never the big one's.
function BigMap.SaveLayout()
	if small then return end
	UI.saved.window = { left = frame:GetLeft(), top = frame:GetTop(), w = frame:GetWidth(), h = frame:GetHeight() }
end

local function Follow() Motion.SetFollow(true) end

-- You, on the map shown.
local function Here()
	local you = Model.you
	return you.col and not you.stale and you.inst == Camera.inst and you or nil
end

-- Your zone's rect in tile space, walking up from a subzone or micro map (MinimapMode.lua:135-145).
local function ZoneRect()
	local id = Model.you.uiMap
	local m = id and Atlas.UiMap(id)
	while m and m.mapType > ZONE and m.parent do m = Atlas.UiMap(m.parent) end
	local r = m and Atlas.MapRect(m.id)
	return r and r.inst == Camera.inst and r or nil
end

-- The window's rect (and the home corner's alpha, a0 to a1) eased to `to` (MinimapMode.lua:59-86).
local function TweenTo(to, duration, onDone, a0, a1)
	tween = { l = frame:GetLeft(), t = frame:GetTop(), w = frame:GetWidth(), h = frame:GetHeight(), to = to,
		at = 0, dur = duration, onDone = onDone, a0 = a0, a1 = a1 }
end

local function StepTween(elapsed)
	local tw, to = tween, tween.to
	tw.at = tw.at + elapsed
	local p = EaseOutCubic(math.min(1, tw.at / tw.dur)) -- /: never 0 (EXPAND_TIME, COLLAPSE_TIME)
	BigMap.homeAlpha = tw.a0 + (tw.a1 - tw.a0) * p
	SetRect(tw.l + (to.left - tw.l) * p, tw.t + (to.top - tw.t) * p, tw.w + (to.w - tw.w) * p, tw.h + (to.h - tw.h) * p)
	if p >= 1 then
		tween = nil
		if tw.onDone then tw.onDone() end
	end
end

-- The minimap's spot, as a square SPAN yards across (MinimapMode.lua:99-114).
local function Place()
	local home = BigMap.home
	if not home then return end
	local k = UIParent:GetEffectiveScale() / frame:GetEffectiveScale() -- /: never 0 (an effective scale is > 0)
	local side = math.max(home.w, home.h) * k
	SetRect(home.left * k, home.top * k, side, side)
	BigMap.SaveLayout()
	Motion.SetZoom(side / SPAN_TILES)
end

---------------------------------------------------------------------------
-- Growing into the world map (M) and back (MinimapMode.lua:116-207)
---------------------------------------------------------------------------

local function Grow()
	if BigMap.big then return end
	BigMap.big = true
	UI.Borders.frame:SetAlpha(1) -- zone borders: the big map's only
	if not small then -- still shrinking back from the last time: the rect to return to stands
		small = { left = frame:GetLeft(), top = frame:GetTop(), w = frame:GetWidth(), h = frame:GetHeight(),
			zoom = (Motion.Goal()) } -- where a chase or flight was headed (MinimapMode.lua:152)
		restoreAlpha = BigMap.homeAlpha
	end
	local k = UIParent:GetEffectiveScale() / frame:GetEffectiveScale() -- /: never 0 (an effective scale is > 0)
	local sw, sh = UIParent:GetWidth() * k, UIParent:GetHeight() * k
	local w, h = sw * EXPANDED_SIZE, sh * EXPANDED_SIZE
	frame:SetFrameStrata("HIGH")
	frame:Raise()
	TweenTo({ left = (sw - w) / 2, top = (sh + h) / 2, w = w, h = h }, EXPAND_TIME, nil, BigMap.homeAlpha, 0)
	-- Still on you, a little further out: the bigger window does the rest. Never further out
	-- than your whole zone, the way the world map opens.
	local zoom = Camera.cam.zoom / EXPAND_ZOOM_OUT
	local r = ZoneRect()
	if r then
		local vw = w - (frame:GetWidth() - Window.view:GetWidth()) -- the map inside the border
		local vh = h - (frame:GetHeight() - Window.view:GetHeight())
		zoom = math.max(zoom, math.min(vw / (r.col1 - r.col0), vh / (r.row1 - r.row0)) * FIT) -- /: never 0 (map rects have area: gen_world.py)
	end
	local you = Here()
	if you then Motion.FlyTo(you.col, you.row, zoom, GROW_FLY, Follow) end
end

-- Back on you at the zoom you had, following.
local function Shrink()
	if not BigMap.big then return end
	BigMap.big = false
	UI.Borders.frame:SetAlpha(0)
	local target = small
	TweenTo(target, COLLAPSE_TIME, function()
		small = nil
		frame:SetFrameStrata(BigMap.homeStrata)
		BigMap.SaveLayout()
	end, 0, restoreAlpha)
	local you = Here()
	if you then
		Motion.FlyTo(you.col, you.row, target.zoom, COLLAPSE_TIME, Follow)
	else
		Motion.SetZoom(target.zoom)
		Follow()
	end
end

-- While big or shrinking back: the small rect it returns to (its zoom is the one saved).
function BigMap.Small() return small end

function BigMap.Toggle()
	if BigMap.big then Shrink() else Grow() end
end

-- Hidden while big (or growing, or shrinking): straight back to the small rect, so it comes back there.
frame:HookScript("OnHide", Runtime.Wrap("map: hidden small", function()
	if not small then return end
	local s = small
	tween, small = nil, nil
	BigMap.big = false
	UI.Borders.frame:SetAlpha(0)
	BigMap.homeAlpha = restoreAlpha
	SetRect(s.left, s.top, s.w, s.h)
	BigMap.SaveLayout()
	Motion.SetZoom(s.zoom)
	frame:SetFrameStrata(BigMap.homeStrata)
end))

-- The first time it shows (no saved rect), onto the minimap's spot.
frame:HookScript("OnShow", Runtime.Wrap("map: shown home", function()
	if not UI.saved.window then Place() end
	frame:SetFrameStrata(BigMap.homeStrata)
end))

-- Resizing the small window keeps the same yards across it: the zoom scales with it (MinimapMode.lua:88-97).
local lastSide
frame:HookScript("OnSizeChanged", Runtime.Wrap("map: resize keeps yards", function(_, w, h)
	local side = math.min(w, h)
	if loaded and not BigMap.big and not tween and lastSide and lastSide > 0 then
		Motion.SetZoom(Camera.cam.zoom * side / lastSide) -- /: never 0 (checked beside it)
	end
	lastSide = side
end))

-- A grow raises the window's tree (SetFrameStrata, Raise: its thousands of regions, ~2-3 ms in the
-- client), once a press: the press's calls get the frame's budget.
Controls.mode:SetScript("OnClick", Runtime.Wrap("map: mode", BigMap.Toggle, Runtime.FRAME_MS))
Controls.Tip(Controls.mode, function() return BigMap.big and "Minimap (M)" or "Big map (M)" end)

-- M, Escape and the rim button, as Game caught them (Model hands them on the same frame); the
-- Minimap's home spot and strata, once Game has read them. (A grow's press: the frame's budget, as above.)
Runtime.Step("ui", "map: keys", function()
	for _, h in ipairs(Model.hooked) do
		if h.kind == "worldmap" then BigMap.Toggle()
		elseif h.kind == "escape" then Shrink()
		elseif h.kind == "toggle" then Window.Toggle() end
	end
	local m = Model.minimap
	if m and m.home then
		BigMap.home = m.home
		if m.homeStrata ~= BigMap.homeStrata then
			BigMap.homeStrata = m.homeStrata
			if not small then frame:SetFrameStrata(m.homeStrata) end
		end
	end
end, { budgetMs = Runtime.FRAME_MS })

-- Window's draw step, first: the tween, and the first placing once the minimap's spot is known.
function BigMap.Step(elapsed)
	if tween then StepTween(elapsed) end
	if not (UI.saved.window or small) then Place() end
end

-- UI's saved part (ui/View.lua): the camera (zoom clamped, Core.lua:1678; the map and centre
-- when not following) and the window's rect.
function BigMap.Load(saved)
	local c = not saved.follow and saved.center
	Camera.cam = { cx = c and c.col or 32, cy = c and c.row or 32, zoom = Camera.cam.zoom }
	Motion.SetZoom(saved.zoom) -- (clamped to Motion's range)
	Camera.follow = saved.follow
	if not saved.follow then Camera.inst = saved.inst end
	local r = saved.window
	if r then SetRect(r.left, r.top, r.w, r.h) end
	loaded = true
end

-- /mm reset: back onto the minimap's spot, at its size, following.
function BigMap.Reset()
	if BigMap.big or tween then
		UI.Print("reset: shrink the map back first (M)")
		return
	end
	Place()
	Follow()
	frame:Show()
end

ns.Game.Command({ kind = "slash", name = "reset", help = "put the map back on the minimap's spot", fn = BigMap.Reset })
