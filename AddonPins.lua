-- Other addons' world-map pins on our map. Addons put pins on Blizzard's
-- world map through HereBeDragons-Pins-2.0 (Questie through its own renamed
-- copy, HereBeDragonsQuestie-Pins-2.0). While our map is open we borrow the
-- addon's own pin frames, so their art, tooltips, clicks and filters stay the
-- addon's, and place them on our map by their world position; they go back
-- where the library left them when our map closes, the addon's layer is
-- turned off, or Blizzard's world map opens (a frame can only be in one place,
-- and that map is the library's).
--
-- How the library holds them: its data provider gives each pin on Blizzard's
-- current map a pin frame on the map's canvas and parents the addon's frame
-- (the "icon") to it; releasing that pin parents the icon to UIParent, hidden.
-- So we note where an icon was when we took it and put it back there: on its
-- pin if that pin still holds it, else where it was, hidden as it was. If the
-- library re-places an icon meanwhile (a new pin, a map refresh), it has
-- taken it back and we leave it be, then borrow it again on the next pass.
--
-- Show rules: the library shows a pin on its own zone map, and on parent,
-- continent or world maps per its flag. Our map is a zone map close up and a
-- continent map zoomed out, so zoomed out (CONTINENT_ZOOM) only pins flagged
-- for continents stay; pins for the zone map alone (Questie's -1, its route
-- lines, drawn for Blizzard's canvas) never come.
--
-- Also here: finding every copy of the library, for MinimapBlips.lua, which
-- hosts each copy's minimap pins.

local ADDON, ns = ...
local state = ns.state

local PINS_MAJOR = "^HereBeDragons(.*)%-Pins%-2%.0$"
local KNOWN = { "HereBeDragons-Pins-2.0", "HereBeDragonsQuestie-Pins-2.0" } -- if LibStub can't list its libraries
local SHOW_CONTINENT = 2   -- HBD_PINS_WORLDMAP_SHOW_CONTINENT
local CONTINENT_ZOOM = 48  -- px per tile: zoomed out further, we're showing a continent
local MAX_SIZE = 128       -- px; bigger frames are drawn for Blizzard's canvas, not as pins
local SYNC_SOON = 0.1      -- s after the library adds or removes pins
local SYNC_EVERY = 1       -- s regardless, to catch pins the library took back

---------------------------------------------------------------------------
-- The copies of HereBeDragons-Pins-2.0
---------------------------------------------------------------------------

local copies = {} -- { lib, major, tag (the renamed part: "Questie"), core }
local libs = {}   -- the libs alone, for MinimapBlips
local known = {}  -- lib -> copy
local MarkDirty, RegisterLayers

local function AddCopy(major, lib)
	if type(lib) ~= "table" or known[lib] then return end
	local tag = major:match(PINS_MAJOR)
	if not tag then return end
	local copy = { lib = lib, major = major, tag = (tag:gsub("^[-_ ]+", "")),
		core = LibStub(major:gsub("%-Pins%-2%.0$", "-2.0"), true) }
	known[lib] = copy
	copies[#copies + 1] = copy
	libs[#libs + 1] = lib
	-- Hear about pins added and removed (a newer copy loading over this one
	-- drops these hooks; the regular pass still catches up).
	for _, method in ipairs({ "AddWorldMapIconWorld", "AddWorldMapIconMap", "RemoveWorldMapIcon", "RemoveAllWorldMapIcons" }) do
		if type(lib[method]) == "function" then hooksecurefunc(lib, method, function() MarkDirty() end) end
	end
end

-- LibStub has no events: look again at login, when an addon loads, when our
-- map opens and when the Minimap joins it.
local scanned = false
local function Scan()
	scanned = true
	if not LibStub then return end
	if type(LibStub) == "table" and type(LibStub.libs) == "table" then
		for major, lib in pairs(LibStub.libs) do
			if type(major) == "string" then AddCopy(major, lib) end
		end
	else
		for _, major in ipairs(KNOWN) do AddCopy(major, LibStub(major, true)) end
	end
	if RegisterLayers then RegisterLayers() end
end

-- Every copy's library table (rescan: look for new ones first).
function ns.HBDPinLibs(rescan)
	if rescan or not scanned then Scan() end
	return libs
end

---------------------------------------------------------------------------
-- One menu layer per addon
---------------------------------------------------------------------------

-- The addon behind a pin: a renamed copy is its addon's (Questie's); in the
-- shared copy, the `ref` the addon registered under (an AceAddon, a string).
local function AddonName(copy, ref)
	if copy.tag ~= "" then return copy.tag end
	if type(ref) == "string" and ref ~= "" then return ref end
	if type(ref) == "table" then
		if type(ref.name) == "string" and ref.name ~= "" then return ref.name end
		if type(ref.GetName) == "function" then
			local ok, name = pcall(ref.GetName, ref)
			if ok and type(name) == "string" and name ~= "" then return name end
		end
	end
	return "Other"
end

local layerOf = {} -- addon name -> layer key, once registered
local Sync

local function Register(name)
	local key = layerOf[name]
	if key then return key end
	key = "addon:" .. name
	layerOf[name] = key
	if ns.AddLayer then
		ns.AddLayer({ key = key, label = name == "Other" and "Other addons' pins" or name, group = "addons", default = true,
			tip = "Map pins " .. (name == "Other" and "other addons put" or name .. " puts") .. " on the world map, shown here too.",
			onToggle = function() Sync() end })
	end
	return key
end

-- A renamed copy is its addon, there or not yet with pins; in the shared
-- copy, each addon once it has pins.
function RegisterLayers()
	for _, copy in ipairs(copies) do
		if copy.tag ~= "" then
			Register(copy.tag)
		elseif type(copy.lib.worldmapPinRegistry) == "table" then
			for ref, icons in pairs(copy.lib.worldmapPinRegistry) do
				if type(icons) == "table" and next(icons) then Register(AddonName(copy, ref)) end
			end
		end
	end
end

local function LayerOn(key)
	if not ns.AddLayer then return true end -- no menu for it yet: always on
	return ns.LayerEnabled(key)
end

---------------------------------------------------------------------------
-- Hosting
---------------------------------------------------------------------------

-- With our pins, above quest areas and below your arrow; the viewport clips it.
local host = CreateFrame("Frame", "MagicMapAddonPins", ns.layerFrames.pins)
host:SetAllPoints()

local hosted = {} -- icon -> { home, points, shown, level, fixed, col, row }
local spot = {}   -- icon -> { x, y, inst, col, row }: its tile position, while its data is unchanged
local seen = {}
local placedZoom

local function WorldMapShown() return WorldMapFrame and WorldMapFrame:IsShown() end

local function Active()
	return ns.frame:IsShown() and state.map ~= nil and not WorldMapShown()
end

-- World yards (HereBeDragons' x is UnitPosition's west axis, y its north) to tiles.
local function Spot(icon, data)
	local s = spot[icon]
	if not s or s.x ~= data.x or s.y ~= data.y or s.inst ~= data.instanceID then
		s = s or {}
		s.x, s.y, s.inst = data.x, data.y, data.instanceID
		s.col, s.row = ns.WorldToTile(data.y, data.x)
		spot[icon] = s
	end
	return s
end

local function Place(icon, rec, z)
	icon:SetPoint("CENTER", ns.tileCanvas, "TOPLEFT", rec.col * z, -rec.row * z)
end

local function SetLevel(icon, level, fixed)
	if fixed and icon.SetFixedFrameLevel then icon:SetFixedFrameLevel(false) end
	icon:SetFrameLevel(level)
	if fixed and icon.SetFixedFrameLevel then icon:SetFixedFrameLevel(true) end
end

local function Claim(icon)
	local rec = {
		home = icon:GetParent(), points = {}, shown = icon:IsShown(), level = icon:GetFrameLevel(),
		fixed = icon.HasFixedFrameLevel and icon:HasFixedFrameLevel() or false,
	}
	for i = 1, icon:GetNumPoints() do rec.points[i] = { icon:GetPoint(i) } end
	icon:SetParent(host)
	SetLevel(icon, host:GetFrameLevel() + 1, rec.fixed)
	icon:ClearAllPoints()
	icon:Show() -- as the library does when it places one (an addon's own hiding still holds)
	hosted[icon] = rec
	return rec
end

local function Restore(icon, rec)
	hosted[icon] = nil
	if icon:GetParent() ~= host then return end -- the library has placed it since
	local home = rec.home
	icon:ClearAllPoints()
	if home and home.icon == icon then
		-- Still its pin's on Blizzard's map: back on the pin, as the library puts it.
		icon:SetParent(home)
		icon:SetPoint("CENTER", home, "CENTER")
	else
		icon:SetParent(home or UIParent)
		for _, p in ipairs(rec.points) do
			if p[2] ~= host and p[2] ~= ns.tileCanvas then icon:SetPoint(unpack(p)) end
		end
		if not rec.shown then icon:Hide() end
	end
	SetLevel(icon, rec.level, rec.fixed)
end

local function ReleaseAll()
	for icon, rec in pairs(hosted) do Restore(icon, rec) end
end

-- Borrow what should be on our map, give back what shouldn't.
function Sync()
	if not Active() then
		ReleaseAll()
		return
	end
	wipe(seen)
	local z = state.zoom
	local continent = z < CONTINENT_ZOOM
	local rezoomed = z ~= placedZoom
	local level = host:GetFrameLevel() + 1
	for _, copy in ipairs(copies) do
		local pins, registry = copy.lib.worldmapPins, copy.lib.worldmapPinRegistry
		if type(pins) == "table" and type(registry) == "table" then
			for ref, icons in pairs(registry) do
				if type(icons) == "table" and next(icons) then
					if LayerOn(Register(AddonName(copy, ref))) then
						for icon in pairs(icons) do
							local data = pins[icon]
							local flag = data and (data.worldMapShowFlag or 0)
							if data and data.instanceID == state.map and flag >= 0 and (flag >= SHOW_CONTINENT or not continent)
								and type(icon) == "table" and icon.SetParent then
								local s = Spot(icon, data)
								local rec = hosted[icon]
								if rec and icon:GetParent() ~= host then
									hosted[icon], rec = nil, nil -- the library took it back: borrow it afresh
								end
								if rec or (icon:GetWidth() <= MAX_SIZE and icon:GetHeight() <= MAX_SIZE) then
									seen[icon] = true
									rec = rec or Claim(icon)
									if rezoomed or rec.col ~= s.col or rec.row ~= s.row then
										rec.col, rec.row = s.col, s.row
										Place(icon, rec, z)
									end
									if icon:GetFrameLevel() ~= level then SetLevel(icon, level, rec.fixed) end
								end
							end
						end
					end
				end
			end
		end
	end
	for icon, rec in pairs(hosted) do
		if not seen[icon] then Restore(icon, rec) end
	end
	for icon in pairs(spot) do
		if not hosted[icon] then spot[icon] = nil end
	end
	placedZoom = z
end

-- Panning moves the tiles' canvas, and the pins with it; zooming moves each.
local function OnViewChanged()
	local z = state.zoom
	if z == placedZoom then return end
	if (z < CONTINENT_ZOOM) ~= (placedZoom and placedZoom < CONTINENT_ZOOM) then
		Sync()
		return
	end
	placedZoom = z
	for icon, rec in pairs(hosted) do Place(icon, rec, z) end
end

local dirty, sinceSync = true, 0
function MarkDirty() dirty = true end

host:SetScript("OnUpdate", function(_, elapsed)
	sinceSync = sinceSync + (elapsed or 0)
	if (dirty and sinceSync >= SYNC_SOON) or sinceSync >= SYNC_EVERY then
		dirty, sinceSync = false, 0
		Sync()
	end
end)

ns.On("ViewChanged", OnViewChanged)
ns.On("MapChanged", function() Sync() end)
ns.frame:HookScript("OnShow", function()
	Scan()
	dirty, sinceSync = true, SYNC_SOON
end)
ns.frame:HookScript("OnHide", ReleaseAll)

-- Blizzard's world map gets them back while it's open.
local hookedWorldMap = false
local function HookWorldMap()
	if hookedWorldMap or not WorldMapFrame then return end
	hookedWorldMap = true
	WorldMapFrame:HookScript("OnShow", ReleaseAll)
	WorldMapFrame:HookScript("OnHide", function() dirty = true end)
end
HookWorldMap()

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function()
	HookWorldMap()
	Scan()
	dirty = true
end)

-- For tests and /mm debugging: what's on our map now.
function ns.HostedAddonPins() return hosted end
