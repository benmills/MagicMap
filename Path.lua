-- Path mode's line: a faint dashed line from you to your target, its dashes
-- drifting slowly toward the target. It's straight, not a route - it reads
-- as "that way" - and sits under the labels and pins.

local ADDON, ns = ...
local state = ns.state

local DASH, GAP = 7, 6     -- px
local FLOW = 14            -- px per second the dashes drift toward the target
local MAX_DASHES = 120     -- longer lines get longer dashes instead of more
local CLEAR_YOU, CLEAR_TARGET = 14, 15 -- px left clear around your arrow and the target's pin
local FADE = 40            -- px over which the line fades in and out at its ends
local DRIFT_HZ = 10        -- the drift steps this often (1.4 px a step); the line redraws only when it or the view moves

-- Off the map, your target gets a gold arrow on the map's edge, on the line
-- from you toward it (Blizzard's own rim arrows are pushed away: MinimapTakeover).
local EDGE_INSET = 16 -- px from the map's edge to the arrow's centre
local edgeArrow = ns.overlay:CreateTexture(nil, "OVERLAY", nil, 3)
edgeArrow:SetTexture("Interface\\Minimap\\ROTATING-MINIMAPGUIDEARROW")
edgeArrow:SetSize(32, 32)
edgeArrow:Hide()

ns.frame:HookScript("OnUpdate", ns.Timed("path arrow", function()
	local t = ns.FrameTarget()
	if t and not t.inside and state.playerCol and state.playerMap == state.map then
		local w, h = ns.ViewSize()
		local x1, y1 = ns.TileToScreen(state.playerCol, state.playerRow)
		local x2, y2 = ns.TileToScreen(t.col, t.row)
		local lo, hiX, hiY = EDGE_INSET, w - EDGE_INSET, h - EDGE_INSET
		local inside = x1 >= lo and x1 <= hiX and y1 >= lo and y1 <= hiY
		if inside and (x2 < lo or x2 > hiX or y2 < lo or y2 > hiY) then
			-- How far along you -> target the line leaves the inset rect.
			local dx, dy = x2 - x1, y2 - y1
			local k = 1
			if dx ~= 0 then k = math.min(k, ((dx > 0 and hiX or lo) - x1) / dx) end
			if dy ~= 0 then k = math.min(k, ((dy > 0 and hiY or lo) - y1) / dy) end
			local ax, ay = math.floor(x1 + dx * k + 0.5), math.floor(y1 + dy * k + 0.5)
			local rot = math.atan2(-dx, -dy) -- the art points up
			if ax ~= edgeArrow.x or ay ~= edgeArrow.y or rot ~= edgeArrow.rot then
				edgeArrow.x, edgeArrow.y, edgeArrow.rot = ax, ay, rot
				edgeArrow:ClearAllPoints()
				edgeArrow:SetPoint("CENTER", ns.overlay, "TOPLEFT", ax, -ay)
				edgeArrow:SetRotation(rot)
			end
			if not edgeArrow.on then
				edgeArrow.on = true
				edgeArrow:Show()
			end
			return
		end
	end
	if edgeArrow.on then
		edgeArrow.on = false
		edgeArrow:Hide()
	end
end))

local layer = ns.layerFrames.path

local dashes, shadows = {}, {}
local used = 0

local function Get(list, i, sublevel, thick)
	local l = list[i]
	if not l then
		l = layer:CreateLine(nil, "ARTWORK", nil, sublevel)
		l:SetThickness(thick)
		l:SetSnapToPixelGrid(false)
		l:SetTexelSnappingBias(0)
		list[i] = l
	end
	return l
end

-- Only what changed: most of a line's dashes keep their colour from frame to frame.
local function Segment(l, ax, ay, bx, by, r, g, b, a)
	if l.r ~= r or l.a ~= a then
		l.r, l.a = r, a
		l:SetColorTexture(r, g, b, a)
	end
	l:SetStartPoint("TOPLEFT", ns.tileCanvas, ax, -ay)
	l:SetEndPoint("TOPLEFT", ns.tileCanvas, bx, -by)
	if not l.on then
		l.on = true
		l:Show()
	end
end

local function Off(l)
	if l.on then
		l.on = false
		l:Hide()
	end
end

-- What the line was last drawn for; nothing moved, nothing to draw. It's
-- drawn on the tiles' canvas, so panning and following carry it along with
-- the map for free; it's redrawn when you or the target move half a pixel,
-- the zoom changes, or the drift steps (DRIFT_HZ).
local drawn = {}
local function Unchanged(x1, y1, x2, y2, phase)
	if drawn[1] == x1 and drawn[2] == y1 and drawn[3] == x2 and drawn[4] == y2 and drawn[5] == phase then return true end
	drawn[1], drawn[2], drawn[3], drawn[4], drawn[5] = x1, y1, x2, y2, phase
	return false
end

local function HalfPixel(v) return math.floor(v * 2 + 0.5) / 2 end

ns.frame:HookScript("OnUpdate", ns.Timed("path line", function()
	local n = 0
	local t = state.path and ns.FrameTarget()
	if t and not t.inside and state.playerCol and state.playerMap == state.map then
		-- On the canvas: tile (col, row) is at (col * zoom, row * zoom) down from its top left.
		local z = state.zoom
		local x1, y1 = HalfPixel(state.playerCol * z), HalfPixel(state.playerRow * z)
		local x2, y2 = HalfPixel(t.col * z), HalfPixel(t.row * z)
		local phase = math.floor(GetTime() * DRIFT_HZ) / DRIFT_HZ
		if Unchanged(x1, y1, x2, y2, phase) then return end
		local dx, dy = x2 - x1, y2 - y1
		local len = math.sqrt(dx * dx + dy * dy)
		local s0, s1 = CLEAR_YOU, len - CLEAR_TARGET
		if s1 > s0 then
			local ux, uy = dx / len, dy / len
			local scale = math.max(1, (s1 - s0) / (DASH + GAP) / MAX_DASHES)
			local dash, step = DASH * scale, (DASH + GAP) * scale
			local s = s0 + (phase * FLOW) % step - step
			while s < s1 and n < MAX_DASHES do
				local a, b = math.max(s, s0), math.min(s + dash, s1)
				if b > a then
					n = n + 1
					local mid = (a + b) / 2
					local f = math.min(1, (mid - s0) / FADE, (s1 - mid) / FADE)
					local ax, ay, bx, by = x1 + ux * a, y1 + uy * a, x1 + ux * b, y1 + uy * b
					Segment(Get(shadows, n, 0, 3.5), ax, ay, bx, by, 0, 0, 0, 0.3 * f)
					Segment(Get(dashes, n, 1, 1.8), ax, ay, bx, by, 1, 0.9, 0.65, 0.6 * f)
				end
				s = s + step
			end
		end
	end
	if n == 0 then drawn[1] = nil end
	for i = n + 1, used do
		Off(dashes[i])
		Off(shadows[i])
	end
	used = n
end))
