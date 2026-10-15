-- Keys Blizzard owns, caught for UI (types/view.lua HookedInput; spike MinimapMode.lua:130-133, 195-202):
--   M (ToggleWorldMap) while our window is shown: the world map it just opened is hidden again, and
--     UI hears "worldmap" (it grows or shrinks the window). M closing Blizzard's map (opened by L,
--     the quest log) is left alone; so is M in combat, where hiding it is blocked (spike-bugs K2):
--     Blizzard's opens as usual.
--   Escape while big: a catcher in UISpecialFrames is shown, and Escape closing it is "escape".
-- What's caught (game/Button.lua's "toggle" too) is handed over as obs.hooked, its own part:
-- everything since the last observe, each a constant table.

local _, ns = ...
local Game, Runtime = ns.Game, ns.Runtime

local INPUT = { worldmap = { kind = "worldmap" }, escape = { kind = "escape" }, toggle = { kind = "toggle" } }
local caught, handed = {}, {}
local shown, big = false, false -- the window, as the last apply read View

function Game.Hooked(kind) caught[#caught + 1] = INPUT[kind] end

Game.Part("hooked", function()
	caught, handed = wipe(handed), caught
	return handed
end)

hooksecurefunc("ToggleWorldMap", Runtime.Wrap("game: M", function()
	if not shown or not WorldMapFrame:IsShown() or InCombatLockdown() then return end
	HideUIPanel(WorldMapFrame)
	Game.Hooked("worldmap")
end))

local catcher = CreateFrame("Frame", "MagicMapAtlasEscape", UIParent) -- (UISpecialFrames takes names)
catcher:Hide()
tinsert(UISpecialFrames, catcher:GetName())
-- Hidden by Escape while big; Apply hides it only once big is over.
catcher:SetScript("OnHide", Runtime.Wrap("game: escape", function()
	if big then Game.Hooked("escape") end
end))

Game.Apply("hooks", function(view)
	local w = view.window
	shown, big = w.shown, w.big
	if catcher:IsShown() ~= big then catcher:SetShown(big) end
end)
