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

local layer = ns.layerFrames.path
if not layer.CreateLine then return end

local dashes, shadows = {}, {}
local used = 0

local function Get(list, i, sublevel, thick)
	local l = list[i]
	if not l then
		l = layer:CreateLine(nil, "ARTWORK", nil, sublevel)
		l:SetThickness(thick)
		if l.SetSnapToPixelGrid then l:SetSnapToPixelGrid(false) end
		if l.SetTexelSnappingBias then l:SetTexelSnappingBias(0) end
		list[i] = l
	end
	return l
end

local function Segment(l, ax, ay, bx, by, r, g, b, a)
	l:SetColorTexture(r, g, b, a)
	l:SetStartPoint("TOPLEFT", layer, ax, -ay)
	l:SetEndPoint("TOPLEFT", layer, bx, -by)
	l:Show()
end

ns.frame:HookScript("OnUpdate", function()
	local n = 0
	local t = state.path and ns.GetTarget and ns.GetTarget()
	if t and state.playerCol and state.playerMap == state.map then
		local x1, y1 = ns.TileToScreen(state.playerCol, state.playerRow)
		local x2, y2 = ns.TileToScreen(t.col, t.row)
		local dx, dy = x2 - x1, y2 - y1
		local len = math.sqrt(dx * dx + dy * dy)
		local s0, s1 = CLEAR_YOU, len - CLEAR_TARGET
		if s1 > s0 then
			local ux, uy = dx / len, dy / len
			local scale = math.max(1, (s1 - s0) / (DASH + GAP) / MAX_DASHES)
			local dash, step = DASH * scale, (DASH + GAP) * scale
			local s = s0 + (GetTime() * FLOW) % step - step
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
	for i = n + 1, used do
		dashes[i]:Hide()
		shadows[i]:Hide()
	end
	used = n
end)
