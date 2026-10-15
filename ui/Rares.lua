-- Rare and rare-elite NPCs' spawn points on the map: Model.Known("rares") as
-- pins with the game's rare icon (its atlas name, from Model). Laid out again
-- when Model's list changes. Toggled like any layer (/mma layer rares).

local _, ns = ...
local UI, Model = ns.UI, ns.Model
local Map = UI.Map
local Get = Map.Get

local ICON = 16 -- px

local function MakePin(c)
	local t = c:CreateTexture(nil, "OVERLAY")
	t:SetSnapToPixelGrid(false)
	t:SetTexelSnappingBias(0)
	t:SetSize(ICON, ICON)
	return t
end

UI.Rares = Map.NewLayer("rares", 5, function(c, inst, zoom, c0, r0, c1, r1)
	for _, b in ipairs((Model.Known("rares"))) do
		local p = b.pos
		if p.inst == inst and p.col >= c0 and p.col <= c1 and p.row >= r0 and p.row <= r1 then
			local t = Get(c, "pin", "tex", MakePin)
			t:SetAtlas(b.icon and b.icon.atlas or "vignettekill")
			t:SetPoint("CENTER", c, "TOPLEFT", p.col * zoom, -p.row * zoom)
			t.rare = b.key
		end
		ns.Runtime.Yield()
	end
end, function() return select(2, Model.Known("rares")) end)
