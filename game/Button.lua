-- The minimap button (spike MinimapButton.lua, UI.lua:81-125 CreateRoundButton): on the Minimap's
-- rim, dragged round it (its angle saved: SavedGame.buttonAngle), shown while View.button. A click,
-- or the addon compartment's entry (the TOC's AddonCompartmentFunc), is "toggle" for UI
-- (obs.hooked, game/Hooks.lua): it shows or hides the map. It hangs on the Minimap, so while the
-- takeover has it, it waits hidden on the stand-in with the rest (game/Minimap.lua).

local _, ns = ...
local Game, Runtime = ns.Game, ns.Runtime

-- The geometry of LibDBIcon-1.0's button (createButton): a 31 button, its tracking border 53 at
-- TOPLEFT (the one border, the ring round the icon), the background 20 at (7,-5), the icon 17 at
-- (7,-6), its centre 80 from a 140 Minimap's middle: RIM past the Minimap's half width.
local SIZE, RIM = 31, 10
local ANGLE = 215         -- degrees, until dragged (Core.lua:28)
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask" -- UI.lua:6: the icon's round mask
local RING = "Interface\\Minimap\\MiniMap-TrackingBorder"
local BACK = "Interface\\Minimap\\UI-Minimap-Background"
local HIGHLIGHT = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"
local ICON = "Interface\\Icons\\INV_Misc_Map_01"                  -- MinimapButton.lua:8
-- Its tip (MinimapButton.lua:10, in the map's tips' look: ui/Tip.lua): its name; a click's plain, a drag isn't.
local TITLE, DRAG = "MagicMap", "Drag to move"

local button = CreateFrame("Button", nil, Minimap)
button:SetSize(SIZE, SIZE)
button:RegisterForDrag("LeftButton")
button:SetHighlightTexture(HIGHLIGHT)
button:Hide()

local bg = button:CreateTexture(nil, "BACKGROUND")
bg:SetTexture(BACK)
bg:SetSize(20, 20)
bg:SetPoint("TOPLEFT", 7, -5)

local icon = button:CreateTexture(nil, "ARTWORK")
icon:SetTexture(ICON)
icon:SetSize(17, 17)
icon:SetPoint("TOPLEFT", 7, -6)
local mask = button:CreateMaskTexture()
mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
mask:SetAllPoints(icon)
icon:AddMaskTexture(mask)

local ring = button:CreateTexture(nil, "OVERLAY")
ring:SetTexture(RING)
ring:SetSize(53, 53)
ring:SetPoint("TOPLEFT")

-- On the rim of its parent: the Minimap, or the stand-in holding its spot, at MEDIUM 8 levels
-- above it (MinimapButton.lua:12-23).
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
	Game.Tooltip(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(TITLE, 1, 1, 1)
	Game.TooltipFact(DRAG)
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
MagicMap_OnAddonCompartmentClick = Runtime.Wrap("game: compartment", function() Game.Hooked("toggle") end)
