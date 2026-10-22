-- The client's own Settings entry (Game menu -> Options -> AddOns -> MagicMap): a canvas with a line and an
-- "Open MagicMap Settings" button. The settings themselves are UI's window (ui/Feel.lua); the button runs
-- /mm feel open (Game.Run: the same as typing it), after closing the client's Options, which would cover it
-- (not in combat: HideUIPanel is protected there). Only where the client has the modern Settings API
-- (Settings.RegisterCanvasLayoutCategory, RegisterAddOnCategory); without it, nothing is made. The canvas's
-- widgets are made when it first shows, so the entry costs one empty frame until then.

local _, ns = ...
local Game, Runtime = ns.Game, ns.Runtime

if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end

local panel = CreateFrame("Frame")
panel.name = "MagicMap"
panel:Hide()

local made
panel:SetScript("OnShow", Runtime.Wrap("game: options shown", function()
	if made then return end
	made = true
	local line = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	line:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
	line:SetWidth(520)
	line:SetJustifyH("LEFT")
	line:SetText("MagicMap's settings are in a window of their own, with a category on its left for each part of the map.")
	local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	open:SetSize(200, 24)
	open:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, -12)
	open:SetText("Open MagicMap Settings")
	open:SetScript("OnClick", Runtime.Wrap("game: options open", function()
		if SettingsPanel and SettingsPanel:IsShown() and not InCombatLockdown() then HideUIPanel(SettingsPanel) end
		Game.Run("feel open")
	end))
end))

Game.category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
Settings.RegisterAddOnCategory(Game.category)
