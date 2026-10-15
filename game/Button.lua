-- The minimap button (spike MinimapButton.lua, UI.lua:81-125 CreateRoundButton): on the Minimap's
-- rim, dragged round it (its angle saved: SavedGame.buttonAngle), shown while View.button. A click,
-- or the addon compartment's entry (the TOC's AddonCompartmentFunc), is "toggle" for UI
-- (obs.hooked, game/Hooks.lua): it shows or hides the map. It hangs on the Minimap, so while the
-- takeover has it, it waits hidden on the stand-in with the rest (game/Minimap.lua).

local _, ns = ...
local Game, Runtime = ns.Game, ns.Runtime

local SIZE, INSET = 28, 8 -- MinimapButton.lua:7-9
local RIM = 6             -- past the Minimap's edge, so the ring overlaps it (MinimapButton.lua:20)
local ANGLE = 215         -- degrees, until dragged (Core.lua:28)
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask" -- UI.lua:6
local RING = "Interface\\HUD\\UIMinimap2xC60"                      -- UI.lua:9-11: Forever's minimap button ring
local RING_COORDS = { 510 / 1024, 591 / 1024, 511 / 1024, 592 / 1024 }
local ICON = "Interface\\Icons\\INV_Misc_Map_01"                  -- MinimapButton.lua:8
local TIP = "|cffffd100MagicMap|r\n|cffffffffClick|r to open the map\n|cffffffffDrag|r to move this button" -- MinimapButton.lua:10

local button = CreateFrame("Button", nil, Minimap)
button:SetSize(SIZE, SIZE)
button:RegisterForDrag("LeftButton")
button:Hide()

local bg = button:CreateTexture(nil, "BACKGROUND")
bg:SetTexture(CIRCLE)
bg:SetVertexColor(0.06, 0.05, 0.04, 0.9)
bg:SetPoint("CENTER")
bg:SetSize(SIZE - 3, SIZE - 3)

local icon = button:CreateTexture(nil, "ARTWORK")
icon:SetTexture(ICON)
icon:SetPoint("CENTER")
icon:SetSize(SIZE - INSET, SIZE - INSET)
local mask = button:CreateMaskTexture()
mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
mask:SetAllPoints(icon)
icon:AddMaskTexture(mask)

local ring = button:CreateTexture(nil, "OVERLAY")
ring:SetTexture(RING)
ring:SetTexCoord(unpack(RING_COORDS))
ring:SetPoint("CENTER")
ring:SetSize(SIZE + 2, SIZE + 2)

local hl = button:CreateTexture(nil, "HIGHLIGHT")
hl:SetTexture(CIRCLE)
hl:SetVertexColor(1, 0.9, 0.6, 0.18)
hl:SetPoint("CENTER")
hl:SetSize(SIZE - 3, SIZE - 3)

-- On the rim of its parent: the Minimap, or the stand-in holding its spot (MinimapButton.lua:12-23).
-- Strata and level too: SetParent (the takeover's round trip) gives it its parent's.
local function Place()
	local home = button:GetParent()
	local a, r = math.rad(Game.saved.buttonAngle or ANGLE), home:GetWidth() / 2 + RIM
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(home:GetFrameLevel() + 8)
	button:ClearAllPoints()
	button:SetPoint("CENTER", home, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local Follow = Runtime.Wrap("game: button drag", function()
	local home = button:GetParent()
	local mx, my = home:GetCenter()
	local s = home:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	Game.saved.buttonAngle = math.deg(math.atan2(cy / s - my, cx / s - mx)) % 360 -- /: never 0 (an effective scale is > 0)
	Place()
end)

button:SetScript("OnClick", Runtime.Wrap("game: button", function() Game.Hooked("toggle") end))
button:SetScript("OnEnter", Runtime.Wrap("game: button tip", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText(TIP, 1, 1, 1, 1, true)
	GameTooltip:Show()
end))
button:SetScript("OnLeave", Runtime.Wrap("game: button left", function(self) Game.HideTooltip(self) end))
button:SetScript("OnDragStart", Runtime.Wrap("game: button drag start", function(self)
	Game.HideTooltip(self)
	self:SetScript("OnUpdate", Follow)
end))
button:SetScript("OnDragStop", Runtime.Wrap("game: button drag stop", function(self) self:SetScript("OnUpdate", nil) end))

-- Shown per View; placed again when it shows and when the takeover lets go.
local shown, engaged = false, false
Game.Apply("button", function(view)
	local on, e = view.button, Game.minimap.engaged
	if on == shown and e == engaged then return end
	if on and (not shown or not e) then Place() end
	shown, engaged = on, e
	button:SetShown(on)
end)

-- The addon compartment's entry: the TOC names this global for the client to call.
MagicMapAtlasOnAddonCompartmentClick = Runtime.Wrap("game: compartment", function() Game.Hooked("toggle") end)
