-- The map window: Blizzard's ButtonFrameTemplate (Forever's re-skin) stripped to its
-- metal border (ui/Chrome.lua), the view inside it where the layers draw (ui/Engine.lua),
-- and input routing: the view's wheel, presses and releases go to Motion (ui/Motion.lua);
-- dragging the border or Alt+left-dragging the map moves the window. Its draw step, each
-- frame while shown: grow/shrink (ui/BigMap.lua), the map shown (yours while following),
-- Motion's chase, Engine's layers, the map state, your arrow.

local _, ns = ...
local UI = ns.UI
local Atlas, Runtime = ns.Atlas, ns.Runtime
local Camera = UI.Camera
local Maths = Atlas.Camera

local BACKDROP = { 0.03, 0.06, 0.065 } -- a map without its sea colour (Core.lua:487)

local Window = {}
UI.Window = Window

local function R2(v) return math.floor(v * 100 + 0.5) / 100 end -- for telemetry

-- Core.lua:86-100: until the minimap's spot is known, 200 square at the top right (Core.lua:21, 1676).
local frame = CreateFrame("Frame", "MagicMapAtlasMap", UIParent, "ButtonFrameTemplate")
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:SetResizable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetResizeBounds(120, 120)
frame:SetSize(200, 200)
frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -20)
frame:Hide()
ButtonFrameTemplate_HidePortrait(frame)
ButtonFrameTemplate_HideButtonBar(frame)
Window.frame = frame

local opened -- the first open builds Atlas's indexes: its frames are budgeted apart (docs/runtime.md)
frame:SetScript("OnShow", Runtime.Wrap("map: shown", function()
	if not opened then opened = true; Runtime.Grace("map", 2) end
	Runtime.Trace("map", "shown")
end))
Runtime.SetState("closed") -- frames by map state (docs/runtime.md); the draw step sets the shown ones

-- Its place, kept (ui/BigMap.lua: only the small window's).
local function Moved() UI.BigMap.SaveLayout() end
frame:SetScript("OnDragStart", Runtime.Wrap("map: move", function() frame:StartMoving() end))
frame:SetScript("OnDragStop", Runtime.Wrap("map: moved", function()
	frame:StopMovingOrSizing()
	Moved()
end))
Window.Moved = Moved

-- The view: the map, inside the border (placed by ui/Chrome.lua). Clips the layers to it.
local view = CreateFrame("Frame", nil, frame)
view:SetClipsChildren(true)
view:EnableMouse(true)
view:EnableMouseWheel(true)
Window.view = view

local backdrop = view:CreateTexture(nil, "BACKGROUND", nil, -8)
backdrop:SetAllPoints()
backdrop:SetColorTexture(0, 0, 0, 1)

-- Your arrow, above every layer.
local overlay = CreateFrame("Frame", nil, view)
overlay:SetAllPoints()
overlay:SetFrameLevel(view:GetFrameLevel() + 10)
local arrow = overlay:CreateTexture(nil, "OVERLAY")
arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
arrow:SetSize(28, 28)
arrow:SetSnapToPixelGrid(false)
arrow:SetTexelSnappingBias(0)
arrow:Hide()

function Window.Size()
	return view:GetWidth(), view:GetHeight()
end

-- The cursor in the view's units, from its top left.
function Window.Cursor()
	local x, y = GetCursorPosition()
	local s = view:GetEffectiveScale()
	return x / s - view:GetLeft(), view:GetTop() - y / s -- /: never 0 (an effective scale is > 0)
end

---------------------------------------------------------------------------
-- Input: the view's mouse, to Motion; Alt+left-drag moves the window (Core.lua:1335-1393)
---------------------------------------------------------------------------

local moving
view:SetScript("OnMouseWheel", Runtime.Wrap("map: wheel", function(_, delta) UI.Motion.Wheel(delta) end))
view:SetScript("OnMouseDown", Runtime.Wrap("map: press", function(_, button)
	if button ~= "LeftButton" then return end
	if IsAltKeyDown() then
		frame:StartMoving()
		moving = true
		return
	end
	UI.Motion.Press()
end))
-- Only the left button's release ends a press; the right one's opens the map's menu (Core.lua:1387-1399).
view:SetScript("OnMouseUp", Runtime.Wrap("map: release", function(_, button)
	if moving then
		frame:StopMovingOrSizing()
		moving = nil
		Moved()
		return
	end
	if button == "RightButton" then
		if not (IsShiftKeyDown() or IsControlKeyDown()) then UI.Menus.Map(view) end
	elseif button == "LeftButton" then
		UI.Motion.Release()
	end
end))
-- In the window (a tip on one of its widgets goes with it: Game hides only its own, spike-bugs G7).
local function Within(f)
	while f do
		if f == frame then return true end
		f = f:GetParent()
	end
	return false
end
frame:SetScript("OnHide", Runtime.Wrap("map: hidden", function()
	if moving then frame:StopMovingOrSizing(); moving = nil end
	local owner = GameTooltip:GetOwner()
	if owner and Within(owner) then GameTooltip:Hide() end
	Runtime.Trace("map", "hidden")
	Runtime.SetState("closed")
end))

---------------------------------------------------------------------------
-- Each frame: grow/shrink, the map shown, the camera, layouts and canvases, your arrow
---------------------------------------------------------------------------

local function You()
	local you = ns.Model.you
	return you and you.inst and you
end

local drawn -- the map the layers show
local function SetInst(inst)
	drawn = inst
	UI.Engine.Clear()
	local bg = BACKDROP
	for _, m in ipairs(Atlas.Maps()) do
		if m.inst == inst and m.bg then bg = m.bg end
	end
	backdrop:SetColorTexture(bg[1], bg[2], bg[3], 1)
end

Runtime.Step("ui", "map: draw", function(elapsed)
	UI.BigMap.Step(elapsed)
	local you, Motion = You(), UI.Motion
	Motion.Chase(you) -- (a map that withholds where you are: the whole of it)
	if not Camera.inst or (Camera.follow and you) then Camera.inst = you and you.inst or Camera.inst or 0 end -- following: your map
	local inst = Camera.inst
	if inst ~= drawn then SetInst(inst) end
	local cam = Camera.cam
	local w, h = Window.Size()
	if w <= 0 or h <= 0 then return end
	local zooming = UI.Engine.Draw(inst, cam, w, h)
	Runtime.SetState(Motion.Dragging() and "drag" or zooming and "zoom" or UI.BigMap.big and "big" or "small")
	-- The arrow: only what changed is applied (an idle frame makes no widget calls for it).
	if you and you.col and you.inst == inst then
		local x, y = Maths.TileToScreen(cam, w, h, you.col, you.row)
		local facing, stale = you.facing or 0, you.stale and true or false
		if arrow.x ~= x or arrow.y ~= y then
			arrow.x, arrow.y = x, y
			arrow:SetPoint("CENTER", overlay, "TOPLEFT", x, -y)
		end
		if arrow.facing ~= facing then arrow.facing = facing; arrow:SetRotation(facing) end
		if arrow.stale ~= stale then
			arrow.stale = stale
			arrow:SetDesaturated(stale) -- last known: greyed
			arrow:SetAlpha(stale and 0.5 or 1)
		end
		if not arrow.shown then arrow.shown = true; arrow:Show() end
	elseif arrow.shown then
		arrow.shown = false
		arrow:Hide()
	end
end, { shownOnly = frame })

-- Our map, or Blizzard's minimap (Core.lua:1654).
function Window.Toggle()
	frame:SetShown(not frame:IsShown())
end

-- For telemetry: the window and its camera (View.diag's map).
function Window.State()
	local cam, w, h = Camera.cam, Window.Size()
	return { shown = frame:IsShown(), inst = Camera.inst, cx = R2(cam.cx), cy = R2(cam.cy), zoom = R2(cam.zoom),
		follow = Camera.follow, w = R2(w), h = R2(h) }
end

ns.Game.Command({ kind = "slash", name = "map", help = "show or hide the map window", fn = Window.Toggle })
