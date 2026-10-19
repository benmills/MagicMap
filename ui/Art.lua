-- Art: every atlas, file and font UI draws with, by name, and Game's minimap button's (all the
-- chrome you see). Checked against the client once after login's grace and on /mma check
-- art; each miss traces "art" (its name). Forever lacks some art other clients have, and a
-- missing name draws nothing, silently (spike-bugs L2, L5). A name UI starts using goes here.
-- Not listed: data's art (tile FileDataIDs, Textures\Sea: generated, K4), our own
-- Textures\PlayerArrow (ui/You.lua: an addon's file, not the client's; L5's restart hazard, as
-- Sea's) and the client's own tracking icons (whatever C_Minimap names).

local _, ns = ...
local UI, Runtime = ns.UI, ns.Runtime
local Command = ns.Game.Command

local Art = {
	-- A name, or a chain as its button tries it (the first the client has): a chain is a miss
	-- only when none of it is there, named by its first.
	atlases = {
		"vignettekill", "vignettekillelite",                       -- ui/Rares.lua (model/Rares.lua ICON)
		"Professions_Tracking_Herb", "Professions_Tracking_Ore",   -- ui/Blips.lua: gathering nodes (game/Blips.lua GATHER)
		"UI-Frame-Metal-CornerBottomLeft", "UI-Frame-Metal-CornerBottomRight", -- ui/Chrome.lua: the border
		"_UI-Frame-Metal-EdgeBottom", "!UI-Frame-Metal-EdgeLeft", "!UI-Frame-Metal-EdgeRight",
		-- ui/Controls.lua: the mode button, the spike's chains (Core.lua:282-286). Forever draws the
		-- second of each: GetAtlasInfo takes an element's name, and redbutton-expand-c60 is only a
		-- member of element redbutton-expand (an art variant, as -2x is: UiTextureAtlasMember 38936).
		{ "redbutton-expand-c60", "redbutton-expand" },
		{ "redbutton-expand-pressed-c60", "redbutton-expand-pressed" },
		{ "redbutton-highlight-c60", "redbutton-highlight" },
		"ui-hud-minimap-zoom-in", "ui-hud-minimap-zoom-in-down", "ui-hud-minimap-zoom-in-mouseover", -- the zoom buttons
		"ui-hud-minimap-zoom-out", "ui-hud-minimap-zoom-out-down", "ui-hud-minimap-zoom-out-mouseover",
		"ui-hud-minimap-arrow-player",                             -- the follow toggle
		"deathrecap-icon-tombstone", "UI-QuestPoi-QuestNumber",    -- ui/You.lua: your corpse on the quest pins' disc
		"Waypoint-MapPin-Tracked",                                 -- ui/You.lua: your waypoint
	},
	files = {
		"Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up",        -- ui/Chrome.lua: the grip
		"Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight",
		"Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down",
		"Interface\\WorldMap\\Gear_64",                           -- ui/Controls.lua: the gear
		"Interface\\CharacterFrame\\TempPortraitAlphaMask",       -- CIRCLE: ui/Chrome.lua, ui/Blips.lua (dots); game/Button.lua
		"Interface\\HUD\\UIMinimap2xC60", "Interface\\Icons\\INV_Misc_Map_01", -- game/Button.lua: ring, icon
		136458, 136453, 136452, 136466, 136454, 136463, 136455, 136465, 136459, -- ui/Blips.lua: services (game/Blips.lua SERVICE)
		"Interface\\Minimap\\ROTATING-MINIMAPGUIDEARROW",        -- ui/Path.lua: the edge arrow
	},
	fonts = { "Fonts\\FRIZQT__.TTF" }, -- ui/Labels.lua: GameFontNormal's (enUS)
}
UI.Art = Art

local GRACE = 6 -- s after the first frame (login or /reload: each loads us anew): past login's grace (5 s, game/Game.lua)

-- A path the client resolves; a FileDataID a texture takes (the client has no lookup by id).
local probe = UIParent:CreateTexture()
probe:Hide()
local function Has(file)
	if type(file) == "string" then return GetFileIDFromPath(file) ~= nil end
	return probe:SetTexture(file) ~= false
end

-- An atlas, or any atlas of a chain.
local function HasAtlas(a)
	if type(a) == "string" then return C_Texture.GetAtlasInfo(a) ~= nil end
	for _, name in ipairs(a) do
		if C_Texture.GetAtlasInfo(name) then return true end
	end
	return false
end

-- A font as ui/Labels.lua loads it: SetFont, on a font string of its own. One the client can't
-- load leaves it without a font (GetFont nil), as it would leave a label: drawn as nothing.
-- Not GetFileIDFromPath: that answers nil for fonts the client has (Fonts\FRIZQT__.TTF is its
-- file 615960: the M0 gate's two font misses).
local fonts = {}
local function HasFont(file)
	local fs = fonts[file]
	if not fs then
		fs = UIParent:CreateFontString()
		fs:Hide()
		fonts[file] = fs
	end
	fs:SetFont(file, 12, "")
	return fs:GetFont() == file
end

-- The names the client lacks, each traced.
local function Check()
	local misses = {}
	for _, a in ipairs(Art.atlases) do
		if not HasAtlas(a) then misses[#misses + 1] = type(a) == "table" and a[1] or a end
	end
	for _, file in ipairs(Art.files) do
		if not Has(file) then misses[#misses + 1] = tostring(file) end
	end
	for _, font in ipairs(Art.fonts) do
		if not HasFont(font) then misses[#misses + 1] = font end
	end
	for _, m in ipairs(misses) do Runtime.Trace("art", m) end
	return misses
end

local function Report(misses)
	print(misses[1] and "  art missing: " .. table.concat(misses, ", ")
		or string.format("  art: all %d there", #Art.atlases + #Art.files + #Art.fonts))
end

-- Armed on the first frame (timers run there), not on a game event: only Game registers those.
Runtime.After(0, "ui: art arm", function()
	Runtime.After(GRACE, "ui: art check", function()
		local misses = Check()
		if misses[1] then Report(misses) end
	end)
end)

Command({ kind = "slash", name = "check art", help = "the atlases, files and fonts UI draws with: any the client lacks",
	fn = function() Report(Check()) end })
