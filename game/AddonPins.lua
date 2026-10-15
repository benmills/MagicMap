-- Other addons' world-map pins on our map: the spike's AddonPins.lua, thin (M4.2 adds the
-- continent filter, Questie's repeats of our turn-ins and the minimap pins). Addons put pins on
-- Blizzard's world map through HereBeDragons-Pins-2.0, each through its copy in LibStub
-- (Questie's renamed: HereBeDragonsQuestie-Pins-2.0). While our window is shown with a world
-- socket (View.sockets.world) and Blizzard's world map isn't, Game borrows the pin frames
-- ("icons") of each addon whose layer is on (View.layers "addon:<key>") onto the socket at their
-- world position; each goes back where it was (parent, points, shown, level) when our window
-- hides, the socket goes or moves frame or map, its layer goes off, or Blizzard's world map opens
-- (a frame is in one place only, and that map is the library's: it takes back the ones it shows
-- itself). One the library has placed again meanwhile is the library's: left be. Pins drawn for
-- its own zone map alone (Questie's -1, its route lines) and frames bigger than pins aren't
-- borrowed. A Questie log is thousands of pins, so borrowing and giving back is a Runtime.Job,
-- JOB_MS a frame; the library adding or removing world pins cancels a borrowing pass (it walks
-- the library's tables) and starts another SYNC_SOON later.
-- Game.Addons(): obs.addons (game/parts/Addons.lua), a new list only when it changed.

local _, ns = ...
local Atlas, Game, Runtime = ns.Atlas, ns.Game, ns.Runtime

local PINS_MAJOR = "^HereBeDragons(.*)%-Pins%-2%.0$" -- AddonPins.lua:30
local MAX_SIZE = 128 -- px; bigger frames are drawn for Blizzard's canvas, not as pins (AddonPins.lua:34)
local SYNC_SOON, SYNC_EVERY = 0.1, 1 -- s after the library adds or removes pins; regardless (AddonPins.lua:35-36)
local JOB_MS = 1 -- ms a frame of borrowing or giving back

local copies, hooks = {}, {} -- { lib, tag (the renamed part: "Questie") }; lib -> { [method] = the function hooked }
local hosted, seen = {}, {} -- icon -> { home, points, shown, level, fixed, socket, inst, col, row }
local socket, inst, zoom -- where they're hosted: the socket's frame, instance and zoom
local open, dirty, syncAt = false, true, 0
local job -- the pass running: { kind = "borrow" | "give back" } on Runtime's job handle
local list, byKey, listDirty = {}, {}, true -- obs.addons, by key

-- A world pin added or removed: borrow again soon (a pass walking the library's tables stops:
-- they changed under it); a minimap pin: only the list.
local function Running(kind) return job and not (job.done or job.cancelled) and (kind == nil or job.kind == kind) end
local function Stop(kind)
	if Running(kind) then Runtime.Cancel(job) end
end
local World = Runtime.Wrap("game.addon pins: changed", function()
	dirty, listDirty = true, true
	Stop("borrow")
end)
local Minimap = Runtime.Wrap("game.addon pins: minimap", function() listDirty = true end)
local METHODS = { AddWorldMapIconWorld = World, AddWorldMapIconMap = World, RemoveWorldMapIcon = World,
	RemoveAllWorldMapIcons = World, AddMinimapIconWorld = Minimap, AddMinimapIconMap = Minimap,
	RemoveMinimapIcon = Minimap, RemoveAllMinimapIcons = Minimap }

-- Every copy in LibStub (it has no events: at login, when an addon loads, when our window opens).
-- A newer minor loading over a copy redefines its methods, dropping our hooks: hooked again
-- (AddonPins.lua:55-56).
local function Scan()
	if not LibStub then return end -- no addon brought one (spike-bugs E4)
	for major, lib in LibStub:IterateLibraries() do
		local tag = major:match(PINS_MAJOR)
		if tag then
			local h = hooks[lib]
			if not h then
				h = {}
				hooks[lib] = h
				copies[#copies + 1] = { lib = lib, tag = (tag:gsub("^[-_ ]+", "")) }
			end
			for m, fn in pairs(METHODS) do
				if type(lib[m]) == "function" and lib[m] ~= h[m] then
					hooksecurefunc(lib, m, fn)
					h[m], dirty, listDirty = lib[m], true, true
				end
			end
		end
	end
end
Runtime.On("ADDON_LOADED", "game.addon pins: loaded", Scan)

-- Every copy: { lib, tag }; rescan: one loaded since too (game/Minimap.lua hosts their minimap pins).
function Game.PinLibs(rescan)
	if rescan then Scan() end
	return copies
end

-- The addon behind a pin: a renamed copy is its addon's; in the shared copy, the ref it
-- registered under (an AceAddon, a string) (AddonPins.lua:89-101).
local function Key(copy, ref)
	if copy.tag ~= "" then return copy.tag end
	if type(ref) == "string" and ref ~= "" then return ref end
	if type(ref) == "table" and type(ref.name) == "string" and ref.name ~= "" then return ref.name end
	return "Other"
end

local function Entry(new, keys, key)
	local e = keys[key]
	if not e then
		e = { key = key, name = key == "Other" and "Other addons' pins" or key, world = false, minimap = false }
		keys[key] = e
		new[#new + 1] = e
	end
	return e
end

-- A renamed copy is its addon, pins or not yet; in the shared copy, each addon once it has pins.
function Game.Addons()
	if not listDirty then return list end
	listDirty = false
	local new, keys = {}, {}
	for _, copy in ipairs(copies) do
		if copy.tag ~= "" then Entry(new, keys, copy.tag) end
		for ref, icons in pairs(copy.lib.worldmapPinRegistry) do
			if next(icons) then Entry(new, keys, Key(copy, ref)).world = true end
		end
		for ref, icons in pairs(copy.lib.minimapPinRegistry) do
			if next(icons) then Entry(new, keys, Key(copy, ref)).minimap = true end
		end
	end
	local same = #new == #list
	for i = 1, same and #new or 0 do
		local e, o = new[i], byKey[new[i].key]
		if not (o and o.world == e.world and o.minimap == e.minimap) then same = false end
	end
	if not same then list, byKey = new, keys end
	return list
end

-- Hosting -------------------------------------------------------------------------------

local function SetLevel(icon, level, fixed)
	if fixed then icon:SetFixedFrameLevel(false) end
	icon:SetFrameLevel(level)
	if fixed then icon:SetFixedFrameLevel(true) end
end

local function Claim(icon, level)
	local rec = { home = icon:GetParent(), points = {}, shown = icon:IsShown(), level = icon:GetFrameLevel(),
		fixed = icon:HasFixedFrameLevel(), socket = socket, inst = inst }
	for i = 1, icon:GetNumPoints() do rec.points[i] = { icon:GetPoint(i) } end
	icon:SetParent(socket)
	SetLevel(icon, level, rec.fixed)
	icon:ClearAllPoints()
	icon:Show() -- as the library does when it places one
	hosted[icon] = rec
	return rec
end

-- Where it was; one the library has placed since is the library's, but its level is still ours.
local function Restore(icon, rec)
	hosted[icon] = nil
	if icon:GetParent() == rec.socket then
		icon:SetParent(rec.home)
		icon:ClearAllPoints()
		for _, p in ipairs(rec.points) do icon:SetPoint(unpack(p)) end
		icon:SetShown(rec.shown)
	end
	SetLevel(icon, rec.level, rec.fixed)
end

-- Give back those not on this socket and map (all, while closed).
local function GiveBack()
	for icon, rec in pairs(hosted) do
		if not open or rec.socket ~= socket or rec.inst ~= inst then Restore(icon, rec) end
		Runtime.Yield()
	end
end

local function Place(icon, rec)
	icon:SetPoint("CENTER", socket, "TOPLEFT", rec.col * zoom, -rec.row * zoom)
end

-- Borrow what should be on the socket, give back what shouldn't.
local function Sync(layers, level)
	GiveBack()
	wipe(seen)
	for _, copy in ipairs(copies) do
		local pins = copy.lib.worldmapPins
		for ref, icons in pairs(copy.lib.worldmapPinRegistry) do
			if layers["addon:" .. Key(copy, ref)] then
				for icon in pairs(icons) do
					local data = pins[icon]
					if data and data.instanceID == inst and data.worldMapShowFlag >= 0 then
						local rec = hosted[icon]
						if rec and icon:GetParent() ~= socket then Restore(icon, rec); rec = nil end -- the library took it back
						if rec or (icon:GetWidth() <= MAX_SIZE and icon:GetHeight() <= MAX_SIZE) then
							seen[icon] = true
							rec = rec or Claim(icon, level)
							if icon:GetFrameLevel() ~= level then SetLevel(icon, level, rec.fixed) end -- (the window raised)
							local col, row = Atlas.WorldToTile(data.y, data.x) -- (HBD's x is west, y north)
							if col ~= rec.col or row ~= rec.row then
								rec.col, rec.row = col, row
								Place(icon, rec)
							end
						end
					end
					Runtime.Yield()
				end
			end
		end
	end
	for icon, rec in pairs(hosted) do
		if not seen[icon] then Restore(icon, rec) end
		Runtime.Yield()
	end
end

-- Any world pins to borrow or give back (a pass is a job: nothing to do, none made).
local function Any()
	if next(hosted) then return true end
	for _, copy in ipairs(copies) do
		for _, icons in pairs(copy.lib.worldmapPinRegistry) do
			if next(icons) then return true end
		end
	end
	return false
end

local function Pass(kind, fn)
	Stop()
	job = Runtime.Job("game.addon pins: " .. kind, fn, JOB_MS)
	job.kind = kind
end

local function Close()
	if not open then return end
	open = false
	if next(hosted) then Pass("give back", GiveBack) else Stop() end
end

-- Each frame: given back while closed; borrowed at once on opening or a new socket or map, then
-- after the library adds or removes pins, and every SYNC_EVERY (pins it took back, layers toggled).
Game.Apply("addon pins", function(view)
	local s = view.sockets.world
	if not (view.window.shown and s) or WorldMapFrame:IsShown() then return Close() end
	if not open then Scan() end -- (LibStub has no events: look again)
	local t = GetTime()
	if not open or s.frame ~= socket or s.inst ~= inst then
		open, socket, inst, zoom, syncAt = true, s.frame, s.inst, s.zoom, -SYNC_EVERY
		Stop()
	elseif s.zoom ~= zoom then -- (the socket's zoom changes where the view comes to rest)
		zoom = s.zoom
		for icon, rec in pairs(hosted) do
			if rec.socket == socket then Place(icon, rec) end
		end
	end
	if not Running("borrow") and ((dirty and t - syncAt >= SYNC_SOON) or t - syncAt >= SYNC_EVERY) then
		dirty, syncAt = false, t
		local layers, level = view.layers, s.level or socket:GetFrameLevel() + 1
		if Any() then Pass("borrow", function() Sync(layers, level) end) end
	end
end)

-- Blizzard's world map gets them back as it opens.
local function Login()
	Scan()
	WorldMapFrame:HookScript("OnShow", Runtime.Wrap("game.addon pins: world map", Close))
end
Runtime.On("PLAYER_LOGIN", "game.addon pins: login", Login)
