-- Keys Blizzard owns, caught for UI (types/view.lua HookedInput; spike MinimapMode.lua:130-133, 195-202):
--   M (ToggleWorldMap) while our window is shown: the world map it just opened is hidden again, and
--     UI hears "worldmap" (it grows or shrinks the window). M closing Blizzard's map (opened by L,
--     the quest log) is left alone; so is M in combat, where hiding it is blocked (spike-bugs K2):
--     Blizzard's opens as usual.
--   Escape while big: a catcher in UISpecialFrames is shown, and Escape closing it is "escape".
-- What's caught (game/Button.lua's "toggle" too) is handed over as obs.hooked, its own part:
-- everything since the last observe, each a constant table.
-- /mma check combat answers the M1 gate's question for the guard (the spike has none,
-- MinimapMode.lua:198-201): in combat, Blizzard's map open, it hides it once as M would and says
-- whether it hid and whether the client blocked us (a block is taint's too: game/Telemetry.lua).

local ADDON, ns = ...
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

local probe -- a check waiting for the client's word: { hid, blocked }
local function Blocked(_, addon, fn)
	if probe and addon == ADDON then probe.blocked = tostring(fn) end
end
Runtime.On("ADDON_ACTION_BLOCKED", "game: check combat", Blocked)
Runtime.On("ADDON_ACTION_FORBIDDEN", "game: check combat", Blocked)
Game.Slash("check combat", "in combat, Blizzard's map open (M): is hiding it blocked? (M's guard, spike-bugs K2)", function()
	if not (InCombatLockdown() and WorldMapFrame:IsShown()) then
		return Game.Print("check combat: in combat, open Blizzard's map (M), then again")
	end
	probe = {}
	HideUIPanel(WorldMapFrame)
	probe.hid = not WorldMapFrame:IsShown()
	Runtime.After(1, "game: check combat", function()
		Runtime.Trace("check", { e = "combat", hid = probe.hid, blocked = probe.blocked or false })
		Game.Print(string.format("check combat: HideUIPanel(WorldMapFrame) %s; the client %s", probe.hid and "hid it" or
			"left it open", probe.blocked and ("blocked " .. probe.blocked) or "blocked nothing"))
		probe = nil
	end)
end)
