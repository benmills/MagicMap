-- Minimap button (drag it around the minimap's edge) and the Retail addon
-- compartment entry. Both toggle the map.

local ADDON, ns = ...
local db

local button = ns.CreateRoundButton(Minimap, 28, {
	icon = "Interface\\Icons\\INV_Misc_Map_01",
	iconInset = 8,
	tooltip = "|cffffd100MagicMap|r\n|cffffffffClick|r to open the map\n|cffffffffDrag|r to move this button",
})
button:SetFrameStrata("MEDIUM")
button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
button:RegisterForDrag("LeftButton")
button:Hide()

local function Place()
	local angle = math.rad(db.minimap.angle)
	-- Sit on the rim: half the minimap plus a little, so the ring overlaps the edge.
	local r = Minimap:GetWidth() / 2 + 6
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function FollowCursor()
	local mx, my = Minimap:GetCenter()
	local scale = Minimap:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	db.minimap.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
	Place()
end

button:SetScript("OnClick", function() ns.Toggle() end)
button:SetScript("OnDragStart", function(self)
	GameTooltip:Hide()
	self:SetScript("OnUpdate", FollowCursor)
end)
button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

local function Refresh()
	if db.minimap.hide then button:Hide() else Place(); button:Show() end
end

ns.On("Loaded", function(savedDB)
	db = savedDB
	Refresh()
end)

ns.slash.icon = function()
	db.minimap.hide = not db.minimap.hide
	Refresh()
	ns.Print("minimap button " .. (db.minimap.hide and "hidden (/mm icon to show)" or "shown"))
end

-- Retail's addon compartment (the drop-down by the minimap); see the TOC.
function MagicMap_OnAddonCompartmentClick()
	ns.Toggle()
end
