-- The map window: a movable, resizable frame around the view, where the layers
-- draw (ui/Engine.lua), and input routing: the view's wheel, presses and releases
-- go to Motion (ui/Motion.lua). Its draw step, each frame while shown: the map
-- shown (yours), Motion's chase, Engine's layers, the map state, your arrow.

local _, ns = ...
local UI = ns.UI
local Atlas, Runtime = ns.Atlas, ns.Runtime
local Camera = UI.Camera
local Maths = Atlas.Camera

local Window = {}
UI.Window = Window

local function R2(v) return math.floor(v * 100 + 0.5) / 100 end -- for telemetry

local frame = CreateFrame("Frame", "MagicMapAtlasMap", UIParent)
frame:SetSize(720, 520)
frame:SetPoint("CENTER")
frame:SetFrameStrata("HIGH")
frame:SetToplevel(true)
frame:SetMovable(true)
frame:SetResizable(true)
frame:SetResizeBounds(240, 180)
frame:SetClampedToScreen(true)
frame:EnableMouse(true)
frame:Hide()
local opened -- the first open builds Atlas's indexes: its frames are budgeted apart (docs/runtime.md)
frame:SetScript("OnShow", Runtime.Wrap("map: shown", function()
	if not opened then opened = true; Runtime.Grace("map", 2) end
	Runtime.Trace("map", "shown")
end))
frame:SetScript("OnHide", Runtime.Wrap("map: hidden", function()
	Runtime.Trace("map", "hidden")
	Runtime.SetState("closed")
end))
Runtime.SetState("closed") -- frames by map state (docs/runtime.md); the draw step sets the shown ones
Window.frame = frame

local bg = frame:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0.04, 0.04, 0.05, 0.96)

local bar = CreateFrame("Frame", nil, frame)
bar:SetPoint("TOPLEFT")
bar:SetPoint("TOPRIGHT")
bar:SetHeight(22)
bar:EnableMouse(true)
bar:RegisterForDrag("LeftButton")
bar:SetScript("OnDragStart", Runtime.Wrap("map: move", function() frame:StartMoving() end))
bar:SetScript("OnDragStop", Runtime.Wrap("map: moved", function() frame:StopMovingOrSizing() end))

local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("LEFT", 8, 0)

local close = CreateFrame("Button", nil, bar, "UIPanelCloseButton")
close:SetPoint("RIGHT", 2, 0)
close:SetSize(24, 24)

local view = CreateFrame("Frame", nil, frame)
view:SetPoint("TOPLEFT", 4, -22)
view:SetPoint("BOTTOMRIGHT", -4, 4)
view:SetClipsChildren(true)
view:EnableMouse(true)
view:EnableMouseWheel(true)
Window.view = view

local grip = CreateFrame("Button", nil, frame)
grip:SetSize(16, 16)
grip:SetPoint("BOTTOMRIGHT", -2, 2)
grip:SetFrameLevel(view:GetFrameLevel() + 20)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
grip:SetScript("OnMouseDown", Runtime.Wrap("map: resize", function() frame:StartSizing("BOTTOMRIGHT") end))
grip:SetScript("OnMouseUp", Runtime.Wrap("map: resized", function() frame:StopMovingOrSizing() end))

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
-- Input: the view's mouse, to Motion
---------------------------------------------------------------------------

view:SetScript("OnMouseWheel", Runtime.Wrap("map: wheel", function(_, delta) UI.Motion.Wheel(delta) end))
view:SetScript("OnMouseDown", Runtime.Wrap("map: press", function(_, button) UI.Motion.Press(button) end))
view:SetScript("OnMouseUp", Runtime.Wrap("map: release", function() UI.Motion.Release() end))

---------------------------------------------------------------------------
-- Each frame: the map shown, the camera, layouts and canvases, your arrow
---------------------------------------------------------------------------

local function You()
	local you = ns.Model.you
	return you and you.inst and you
end

local function SetInst(inst)
	Camera.inst = inst
	UI.Engine.Clear()
	local continent = Atlas.Continent(inst)
	local name = continent and Atlas.UiMap(continent).name
	if not name then
		for _, m in ipairs(Atlas.Maps()) do
			if m.inst == inst then name = m.name end
		end
	end
	title:SetText(name or ("Map " .. inst))
end

Runtime.Step("ui", "map: draw", function()
	local you = You()
	local inst = you and you.inst or Camera.inst or 0
	if inst ~= Camera.inst then SetInst(inst) end
	local Motion = UI.Motion
	Motion.Chase(you)
	local cam = Camera.cam
	local w, h = Window.Size()
	if w <= 0 or h <= 0 then return end
	local zooming = UI.Engine.Draw(inst, cam, w, h)
	Runtime.SetState(Motion.Dragging() and "drag" or zooming and "zoom" or "small") -- "big" comes with the grow (M1.7)
	-- The arrow: only what changed is applied (an idle frame makes no widget calls for it).
	if you and you.col then
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

function Window.Toggle()
	if frame:IsShown() then
		frame:Hide()
	else
		UI.Motion.Follow()
		frame:Show()
	end
end

-- For telemetry: the window and its camera (View.diag's map).
function Window.State()
	local cam, w, h = Camera.cam, Window.Size()
	return { shown = frame:IsShown(), inst = Camera.inst, cx = R2(cam.cx), cy = R2(cam.cy), zoom = R2(cam.zoom),
		follow = Camera.follow, w = R2(w), h = R2(h) }
end

ns.Game.Command({ kind = "slash", name = "map", help = "show or hide the map window", fn = Window.Toggle })
