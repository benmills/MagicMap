-- Minimap blips on the map: Model.Known("blips") as pins, the game's own tracking
-- icon where the blip has one (Game matched it), else a gold dot like Blizzard's.
-- Remembered ones (not sensed now) are faded. Laid out again when Model's list changes.

local _, ns = ...
local UI, Model = ns.UI, ns.Model
local Engine = UI.Engine
local Get = Engine.Get

local ICON, DOT = 14, 8 -- px
local GOLD = { 1, 0.82, 0 }

local function MakePin(c)
	local t = c:CreateTexture(nil, "OVERLAY")
	t:SetSnapToPixelGrid(false)
	t:SetTexelSnappingBias(0)
	return t
end

UI.Blips = Engine.Layer("blips", 6, function(c, inst, zoom, c0, r0, c1, r1)
	for _, b in ipairs((Model.Known("blips"))) do
		local p = b.pos
		if p.inst == inst and p.col >= c0 and p.col <= c1 and p.row >= r0 and p.row <= r1 then
			local t = Get(c, "pin", "tex", MakePin)
			local icon = b.icon and b.icon.texture
			if icon then
				t:SetTexture(icon)
				t:SetVertexColor(1, 1, 1, 1)
			else
				t:SetTexture("Interface\\COMMON\\Indicator-Yellow")
				t:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
			end
			local size = icon and ICON or DOT
			t:SetSize(size, size)
			t:SetAlpha(b.live and 1 or 0.6)
			Engine.At(c, t, "CENTER", p.col, p.row)
			t.blip = b.key
		end
	end
end, function() return select(2, Model.Known("blips")) end, "move")
