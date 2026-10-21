-- Party and raid members (Layers.lua:666-760): Known("group"), those on the map shown, as the Minimap's
-- own blips: PartyRaidBlipsV2's filled dot (its left half), 12 px, in their class's colour, dead or a
-- ghost grey. They walk: placed again whenever Model's list changes (Game reads them 20 times a second,
-- game/parts/Group.lua) or the view moves, only what changed set; none while the layer's off (the gear's
-- "Party & raid"). Under the cursor (no pin there: ui/Pins.lua's go first), a member's tooltip, Game's
-- (the tooltip Command's member: its name in its class's colour, level and class, dead: Layers.lua:677-688).

local _, ns = ...
local UI, Model, Runtime = ns.UI, ns.Model, ns.Runtime
local Camera, Window, Engine, Pins = UI.Camera, UI.Window, UI.Engine, UI.Pins
local Maths = ns.Atlas.Camera
local Command = ns.Game.Command

local LEVEL = 13 -- with your corpse and waypoint (ui/You.lua): over the blips (12), under the offers (14)
local SIZE = 12 -- px (Layers.lua:666)
local BLIP = "Interface\\Minimap\\PartyRaidBlipsV2" -- a filled dot, then a ring (Layers.lua:667)
local DEAD = 0.5 -- grey (Layers.lua:739)
local NONE = {}

local Group = {}
UI.Group = Group

local view = Window.view
local frame = CreateFrame("Frame", nil, view)
frame:SetAllPoints()
frame:SetFrameLevel(view:GetFrameLevel() + LEVEL + 2) -- (as a pin layer's pins stand)
local tip = CreateFrame("Frame", nil, frame) -- the tooltip's owner, on the dot under the cursor
tip:SetSize(SIZE, SIZE)
Group.tip = tip
local dots, shown = {}, 0 -- 1..shown on the map
Group.dots = dots

local function Dot(i)
	local t = dots[i]
	if not t then
		t = frame:CreateTexture(nil, "ARTWORK")
		t:SetTexture(BLIP)
		t:SetTexCoord(0, 0.5, 0, 1)
		t:SetSize(SIZE, SIZE)
		t:SetSnapToPixelGrid(false)
		t:SetTexelSnappingBias(0)
		dots[i] = t
	end
	return t
end

-- Its colour: its class's, grey dead (Layers.lua:734-741); set when either changes.
local function Color(t, e)
	local dead = e.dead == true
	if t.class == e.class and t.dead == dead then return end
	t.class, t.dead = e.class, dead
	if dead then
		t:SetVertexColor(DEAD, DEAD, DEAD, 1)
	else
		local c = RAID_CLASS_COLORS[e.class]
		t:SetVertexColor(c.r, c.g, c.b, 1)
	end
end

-- The dots as laid out last: Known's rev, the camera, the view's size, the map, on.
local at = { rev = -1 }
local function Place(on)
	local list, rev = Model.Known("group")
	if shown == 0 and not (on and list[1]) then return end
	local cam, w, h = Camera.cam, Window.Size()
	local inst = Camera.inst
	if at.rev == rev and at.cx == cam.cx and at.cy == cam.cy and at.zoom == cam.zoom and at.w == w and at.h == h
		and at.inst == inst and at.on == on then return end
	at.rev, at.cx, at.cy, at.zoom, at.w, at.h, at.inst, at.on = rev, cam.cx, cam.cy, cam.zoom, w, h, inst, on
	local n = 0
	for _, e in ipairs(on and list or NONE) do
		local p = e.pos
		if p.inst == inst then
			n = n + 1
			local t = Dot(n)
			t.entry = e
			Color(t, e)
			local x, y = Maths.TileToScreen(cam, w, h, p.col, p.row)
			x, y = math.max(-SIZE, math.min(w + SIZE, x)), math.max(-SIZE, math.min(h + SIZE, y)) -- off the view: kept by it
			if t.x ~= x or t.y ~= y then
				t.x, t.y = x, y
				t:SetPoint("CENTER", frame, "TOPLEFT", x, -y)
			end
			if not t.shown then t.shown = true; t:Show() end
		end
	end
	for i = n + 1, shown do
		dots[i].shown, dots[i].entry = false, nil
		dots[i]:Hide()
	end
	shown = n
end

-- The member under the cursor (the nearest dot's within its size), while the view has the mouse and no pin's there.
local inside, hovered = false, nil -- hovered: its key
view:HookScript("OnEnter", Runtime.Wrap("map: group entered", function() inside = true end))
view:HookScript("OnLeave", Runtime.Wrap("map: group left", function() inside = false end))

local function Under()
	if not inside or Pins.Hovered() then return nil end
	local x, y = Window.Cursor()
	local best, d
	for i = 1, shown do
		local t = dots[i]
		local dx, dy = t.x - x, t.y - y
		if math.abs(dx) <= SIZE / 2 and math.abs(dy) <= SIZE / 2 and not (best and dx * dx + dy * dy >= d) then
			best, d = t, dx * dx + dy * dy
		end
	end
	return best
end

local function Hover(t)
	local e = t and t.entry
	if (e and e.key) == hovered then return end
	hovered = e and e.key
	if not e then return Command({ kind = "tooltip", owner = false }) end
	tip:SetPoint("CENTER", frame, "TOPLEFT", t.x, -t.y)
	Command({ kind = "tooltip", owner = tip, anchor = "ANCHOR_RIGHT", member = e.key })
end

Runtime.Step("ui", "map: group", function()
	Place(Engine.LayerOn("group"))
	Hover(Under())
end, { shownOnly = Window.frame })
Window.frame:HookScript("OnHide", Runtime.Wrap("map: group hidden", function() hovered = nil end))

UI.Menus.Layer({ key = "group", label = "Party & raid", group = "nearby", tip = "Party and raid members, in their class colours." })
