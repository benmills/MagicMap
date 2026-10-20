-- Art: every atlas, file and font UI draws with, by name, and Game's minimap button's (all the
-- chrome you see). Checked against the client once after login's grace and on /mm check
-- art; each miss traces "art" (its name). Forever lacks some art other clients have, and a
-- missing name draws nothing, silently (spike-bugs L2, L5). A name UI starts using goes here.
-- Not listed: data's art (tile FileDataIDs: generated, K4), our own
-- Textures\PlayerArrow (ui/You.lua: an addon's file, not the client's; L5's restart hazard) and
-- the client's own tracking icons (whatever C_Minimap names).

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
		"deathrecap-icon-tombstone", "ui-questpoi-questnumber-2x", -- ui/You.lua: your corpse on the quest pins' disc
		"Waypoint-MapPin-Tracked",                                 -- ui/You.lua: your waypoint
		"questnormal", "questturnin",                              -- ui/Quests.lua, model/Blips.lua: quests to pick up ("!"), turn-ins ("?")
		"quest-in-progress-icon-yellow-2x",                        -- ui/Quests.lua: a quest in progress, over the disc (model/Quests.lua)
		"dungeon", "raid",                                         -- ui/Places.lua: dungeon and raid entrances
		"taxinode_alliance", "taxinode_horde", "taxinode_neutral", -- ui/Places.lua: flight points
		"poi-graveyard-neutral",                                   -- ui/Places.lua: graveyards
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
		"Interface\\Minimap\\PartyRaidBlipsV2",                  -- ui/Group.lua: party and raid members
		"Interface\\Minimap\\Tracking\\Herbalism", "Interface\\Minimap\\Tracking\\Mining", -- ui/Blips.lua: gathering nodes (a fallback)
		136441,                                                  -- ui/Places.lua: POIIcons, the area POIs the client gives no atlas for
	},
	fonts = { "Fonts\\FRIZQT__.TTF", "Fonts\\MORPHEUS.TTF" }, -- ui/Labels.lua: GameFontNormal's (enUS), and the zones' Morpheus
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

-- The first of names the client has, as a look's icon (Pins' StylePin): a file path (one with a
-- backslash) as a texture, else an atlas. None the client has: no icon, so a dot. A fresh table each
-- call (the caller sets its colour).
local known = {}
function Art.Icon(...)
	for i = 1, select("#", ...) do
		local name = select(i, ...)
		if name then
			local file = name:find("\\", 1, true) ~= nil
			if known[name] == nil then known[name] = file and Has(name) or not file and HasAtlas(name) or false end
			if known[name] then return file and { texture = name } or { atlas = name } end
		end
	end
	return {}
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
