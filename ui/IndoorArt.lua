-- Indoor ground (IndoorArt.lua; MinimapTakeover.lua:546-556): where the Minimap draws its indoor floor plan
-- (Model.minimap.indoors: its view radius tells, Game's) and the art of the map you're on (Model.indoorArt:
-- a dungeon floor's, or a map no wider than 1600 yd) is on the map shown with you on it, the window draws
-- that art over our tiles and under every layer, on a dark backdrop so the ground above doesn't show
-- through: View.renderer "ours+art" (the sensor, pins and your arrow as outdoors). Indoors with no art, the
-- small window wears Blizzard's whole Minimap ("blizzard": Game's), the big one our terrain ("ours").
-- /mma indoor (Game's, Model.minimap.indoorDebug) outlines the art in pink. Not a layer of the engine's
-- (one more there, empty but indoors, would take frames from the ground's layouts as the zoom moves): a
-- frame of its own at the tiles' canvases' level, laid on after them (IndoorArt.lua:3-6: the tiles' canvas),
-- its pieces placed at the camera's zoom when it changes (IndoorArt.lua:96-112, its ViewChanged), the frame
-- moved with a pan; hidden while the art is off the view.

local _, ns = ...
local UI, Model, Runtime = ns.UI, ns.Model, ns.Runtime
local Camera, Window = UI.Camera, UI.Window
local Maths = ns.Atlas.Camera

local BACKDROP = { 0.06, 0.05, 0.04, 1 } -- IndoorArt.lua:18
local OUTLINE, OUTLINE_PX = { 1, 0.2, 0.8, 0.9 }, 2 -- IndoorArt.lua:134-139
local PAD = 200 -- px past the view the art may start or end and still be shown (ui/Engine.lua's)

local IndoorArt = {}
UI.IndoorArt = IndoorArt

-- The art to draw on the map shown (nil: none), as the spike picks it (MinimapTakeover.lua:552).
local function Art()
	local m, art, you, inst = Model.minimap, Model.indoorArt, Model.you, Camera.inst
	if m and m.indoors and art and you.col and not you.stale and you.inst == inst and art.pieces[1].rect.inst == inst then
		return art
	end
end

-- View.renderer for the window (View.window: ui/Sockets.lua's step): ours, with the art where there's some;
-- else, indoors in the small window, Blizzard's floor plan (MinimapTakeover.lua:552-556). Hidden: ours.
function IndoorArt.Renderer(window)
	local m = Model.minimap
	if not (window.shown and m and m.indoors) then return "ours" end
	if Art() then return "ours+art" end
	return window.big and "ours" or "blizzard"
end

local view = Window.view
local frame = CreateFrame("Frame", nil, view)
frame:SetSize(1, 1)
frame:SetFrameLevel(view:GetFrameLevel() + 2) -- the tiles' canvases' (their layer's 1, + 1)
frame:Hide()
IndoorArt.frame = frame

local function Unsnapped(t)
	t:SetSnapToPixelGrid(false)
	t:SetTexelSnappingBias(0)
	return t
end
local backdrop = Unsnapped(frame:CreateTexture(nil, "OVERLAY", nil, -8))
backdrop:SetColorTexture(BACKDROP[1], BACKDROP[2], BACKDROP[3], BACKDROP[4])
backdrop:SetPoint("TOPLEFT")
local pieces, edges = {}, {} -- the art's textures; the outline's four
for i = 1, 4 do
	local t = Unsnapped(frame:CreateTexture(nil, "OVERLAY", nil, 1))
	t:SetColorTexture(OUTLINE[1], OUTLINE[2], OUTLINE[3], OUTLINE[4])
	edges[i] = t
end
edges[1]:SetPoint("TOPLEFT", backdrop)
edges[1]:SetPoint("TOPRIGHT", backdrop)
edges[2]:SetPoint("BOTTOMLEFT", backdrop)
edges[2]:SetPoint("BOTTOMRIGHT", backdrop)
edges[3]:SetPoint("TOPLEFT", backdrop)
edges[3]:SetPoint("BOTTOMLEFT", backdrop)
edges[4]:SetPoint("TOPRIGHT", backdrop)
edges[4]:SetPoint("BOTTOMRIGHT", backdrop)
for i = 1, 2 do edges[i]:SetHeight(OUTLINE_PX) end
for i = 3, 4 do edges[i]:SetWidth(OUTLINE_PX) end

-- What's drawn: the art (nil: none), outlined, at zoom; the frame at x, y on the view.
local drawn = {}

-- The art's textures, set when it changes (IndoorArt.lua:115-133).
local function Show(art, debug)
	for i, p in ipairs(art.pieces) do
		local t = pieces[i]
		if not t then
			t = Unsnapped(frame:CreateTexture(nil, "OVERLAY", nil, 0))
			pieces[i] = t
		end
		t:SetTexture(p.file)
		t:SetTexCoord(0, p.u or 1, 0, p.v or 1)
		t:Show()
	end
	for i = #art.pieces + 1, #pieces do pieces[i]:Hide() end
	for i = 1, 4 do edges[i]:SetShown(debug) end
end

-- Its pieces at zoom, from its top left (the frame's TOPLEFT).
local function Layout(art, zoom)
	local r0 = art.pieces[1].rect
	for i, p in ipairs(art.pieces) do
		local r = p.rect
		pieces[i]:SetPoint("TOPLEFT", frame, "TOPLEFT", (r.c0 - r0.c0) * zoom, -(r.r0 - r0.r0) * zoom)
		pieces[i]:SetSize((r.c1 - r.c0) * zoom, (r.r1 - r.r0) * zoom)
	end
	local r1 = art.pieces[#art.pieces].rect
	backdrop:SetSize((r1.c1 - r0.c0) * zoom, (r1.r1 - r0.r0) * zoom)
end

Runtime.Step("ui", "map: indoor art", function()
	local art = Art()
	local debug = art and Model.minimap.indoorDebug == true or false
	local cam, w, h = Camera.cam, 0, 0
	local x, y, near
	if art then
		w, h = Window.Size()
		local a, b = art.pieces[1].rect, art.pieces[#art.pieces].rect
		x, y = Maths.TileToScreen(cam, w, h, a.c0, a.r0)
		local x1, y1 = Maths.TileToScreen(cam, w, h, b.c1, b.r1)
		near = x < w + PAD and x1 > -PAD and y < h + PAD and y1 > -PAD
	end
	if art ~= drawn.art or debug ~= drawn.debug then
		drawn.art, drawn.debug, drawn.zoom, drawn.x = art, debug, nil, nil
		if art then Show(art, debug) end
	end
	if not near then
		if drawn.shown then drawn.shown = false; frame:Hide() end
		return
	end
	if cam.zoom ~= drawn.zoom then
		drawn.zoom = cam.zoom
		Layout(art, cam.zoom)
	end
	if x ~= drawn.x or y ~= drawn.y then
		drawn.x, drawn.y = x, y
		frame:SetPoint("TOPLEFT", view, "TOPLEFT", x, -y)
	end
	if not drawn.shown then drawn.shown = true; frame:Show() end
end, { shownOnly = Window.frame })
