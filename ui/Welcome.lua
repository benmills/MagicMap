-- The welcome (first click of the minimap button, the addon compartment or /mm while nothing's been chosen;
-- /mm welcome any time): a small dialog of the client's ButtonFrameTemplate, as ui/Feel.lua's (DIALOG strata,
-- clamped, dragged by its header; game/Hooks.lua names it in UISpecialFrames, so Escape closes it) asking
-- what MagicMap replaces (ui/Replace.lua): four large cards, one chosen (the first, recommended, to begin
-- with), and Continue, which saves the choice (Replace.Set, both keys) and opens the map as it says: small on
-- the Minimap's spot if the minimap is replaced, else big. Escape or the close button saves nothing and
-- changes nothing: the next click asks again. Built on the first open. API: Welcome.Open(), Welcome.Toggle().

local _, ns = ...
local UI, Runtime = ns.UI, ns.Runtime
local Command = ns.Game.Command

local Welcome = {}
UI.Welcome = Welcome

local WIDTH, PAD, HEADER, CARD, GAP = 400, 16, 26, 56, 8 -- px: the frame's width, its margin, its header bar, a card, between cards

-- icon, name, one line, minimap, worldmap
local CHOICES = {
	{ icon = "Interface\\Icons\\INV_Misc_Map_01", name = "Minimap and world map", minimap = true, worldmap = true, recommended = true,
		text = "Our small map takes the minimap's place, and M opens our big map." },
	{ icon = "Interface\\Icons\\INV_Misc_Spyglass_02", name = "Minimap only", minimap = true, worldmap = false,
		text = "Our small map takes the minimap's place; M is Blizzard's world map." },
	{ icon = "Interface\\Icons\\INV_Misc_Map02", name = "World map only", minimap = false, worldmap = true,
		text = "Blizzard's minimap stays; M opens our big map." },
	{ icon = "Interface\\Icons\\INV_Misc_Gear_01", name = "Neither \226\128\148 open it from this button", minimap = false, worldmap = false,
		text = "Blizzard's minimap and world map stay; the button opens our map." },
}

local frame, cards, picked
local function Script(f, name, what, fn) f:SetScript(name, Runtime.Wrap(what, fn)) end

local function Text(parent, font, text)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFontObject(font)
	fs:SetText(text)
	return fs
end

local function Pick(i)
	picked = i
	for j, c in ipairs(cards) do
		c.mark:SetShown(j == i)
		c.back:SetColorTexture(j == i and 0.35 or 0.1, j == i and 0.28 or 0.1, j == i and 0.05 or 0.1, j == i and 0.9 or 0.7)
	end
end

local function Card(i, y)
	local c = CHOICES[i]
	local b = CreateFrame("Button", nil, frame)
	b:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, y)
	b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, y)
	b:SetHeight(CARD)
	b.back = b:CreateTexture(nil, "BACKGROUND")
	b.back:SetAllPoints()
	local hi = b:CreateTexture(nil, "HIGHLIGHT")
	hi:SetAllPoints()
	hi:SetColorTexture(1, 1, 1, 0.08)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetSize(38, 38)
	icon:SetPoint("LEFT", b, "LEFT", 8, 0)
	icon:SetTexture(c.icon)
	b.mark = b:CreateTexture(nil, "OVERLAY")
	b.mark:SetSize(24, 24)
	b.mark:SetPoint("RIGHT", b, "RIGHT", -8, 0)
	b.mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	local name = Text(b, GameFontNormal, c.name .. (c.recommended and "  |cff40ff40(Recommended)|r" or ""))
	name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -3)
	name:SetPoint("RIGHT", b.mark, "LEFT", -6, 0)
	name:SetJustifyH("LEFT")
	local line = Text(b, GameFontHighlightSmall, c.text)
	line:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
	line:SetPoint("RIGHT", b.mark, "LEFT", -6, 0)
	line:SetJustifyH("LEFT")
	Script(b, "OnClick", "welcome: pick", function() Pick(i) end)
	return b
end

-- Continue: both keys saved, the dialog closed, the map open as the choice says.
local function Continue()
	local c = CHOICES[picked or 1]
	frame:Hide()
	UI.Replace.Set("worldmap", c.worldmap)
	UI.Replace.Set("minimap", c.minimap) -- (minimap on shows the small map)
	local window = UI.Window.frame
	if not window:IsShown() then window:Show() end -- (neither or world map only: shown, it grows big)
end

local function Build()
	frame = CreateFrame("Frame", "MagicMapWelcome", UIParent, "ButtonFrameTemplate")
	Welcome.frame = frame
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:SetWidth(WIDTH)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
	ButtonFrameTemplate_HidePortrait(frame)
	ButtonFrameTemplate_HideButtonBar(frame)
	local title = frame.TitleText or frame.TitleContainer and frame.TitleContainer.TitleText
	if title then
		title:SetText("Welcome to MagicMap")
	else
		title = Text(frame, GameFontNormal, "Welcome to MagicMap")
		title:SetPoint("TOP", frame, "TOP", 0, -7)
	end
	if not frame.CloseButton then
		local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
		frame.CloseButton = close
	end
	Script(frame.CloseButton, "OnClick", "welcome: close", function() frame:Hide() end)
	local header = CreateFrame("Frame", nil, frame)
	header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, 0)
	header:SetHeight(HEADER)
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton")
	Script(header, "OnDragStart", "welcome: move", function() frame:StartMoving() end)
	Script(header, "OnDragStop", "welcome: move", function() frame:StopMovingOrSizing() end)

	local y = -HEADER - 10
	local intro = Text(frame, GameFontHighlight, "A better map for the minimap, the world map, or both. What should it replace?")
	intro:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, y)
	intro:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, y)
	intro:SetJustifyH("LEFT")
	y = y - 34
	cards = {}
	for i = 1, #CHOICES do
		cards[i] = Card(i, y)
		y = y - CARD - GAP
	end
	local go = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	go:SetSize(110, 24)
	go:SetText("Continue")
	go:SetPoint("TOP", frame, "TOP", 0, y - 4)
	Script(go, "OnClick", "welcome: continue", Continue)
	y = y - 36
	local note = Text(frame, GameFontHighlightSmall, "You can change this anytime in Settings.")
	note:SetTextColor(0.6, 0.6, 0.6)
	note:SetPoint("TOP", frame, "TOP", 0, y)
	frame:SetHeight(-y + 14 + PAD)
	frame:Hide()
end

function Welcome.Open()
	if not frame then Build() end
	Pick(1) -- (the recommended one, each time it asks)
	frame:Show()
end

function Welcome.Toggle()
	if frame and frame:IsShown() then frame:Hide() else Welcome.Open() end
end

Command({ kind = "slash", name = "welcome", help = "the first-run welcome: what MagicMap replaces", fn = Welcome.Open })
