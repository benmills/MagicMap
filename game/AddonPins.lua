-- Other addons' pins on our map. Addons put pins on Blizzard's world map and Minimap through
-- HereBeDragons-Pins-2.0, each through its copy in LibStub (a renamed one: HereBeDragons<Addon>-Pins-2.0),
-- Questie's (12.8 on) a module of its own loader (Scan).
-- World pins: while our window shows a world socket (View.sockets.world) and Blizzard's world map is
-- closed, Game borrows the pin frames of each addon whose layer is on ("addon:<key>") onto the socket,
-- and gives each back where it was (parent, points, shown, level) when that stops: a frame is in one
-- place only, and the library takes back the ones it shows itself. One it has placed again meanwhile is
-- left be. Ours is a zone map close up and a continent's zoomed out, so past CONTINENT_ZOOM only pins
-- flagged for continents come; pins for their own zone map alone (Questie's -1, its route lines), frames
-- bigger than pins, and Questie's "?" or "!" where our quests or offers layer shows the same are never
-- borrowed. A Questie log is thousands of pins, so borrowing, giving back and re-placing at a new zoom
-- are jobs (NEWS_MS a frame with something to show soon, else JOB_MS; 2400 SetPoints are ~0.7 ms
-- in the client), each kind on one Runtime.Worker made at load (the regular pass runs every second the
-- map is shown: a job made for each would be a coroutine, a closure and a handle of garbage a second),
-- the holder see-through until done so no pin shows at the old zoom's place.
-- Minimap pins: while the takeover has the Minimap, each copy draws instead on a host of Game's that
-- answers what the library asks a minimap, around you on View.sockets.minimap; out of sight without that
-- socket (on the overlay they'd take the mouse over our map), under Rotate Minimap (the library turns
-- them, our map stays north up), with the addon's layer off, and for a renamed copy whose world pins we
-- host. Released: back on the Minimap (Game.MinimapPinsHome, game/Minimap.lua's undo).
-- In combat none of it: borrowing a pin, giving one back and moving a library to another host all run the pins'
-- addon's code from ours (its show and hide scripts, the library itself), and what that may not do in combat (let
-- clicks through a frame: SetPassThroughButtons) the client blames on us, the addon whose code began the call chain.
-- A pass running stops, the pins hosted stay where they are, placed at each new zoom (SetPoint runs no one's code),
-- and the first frame out of combat does what's owed.
-- Game.Addons(): obs.addons (game/parts/Addons.lua), a new list only when it changed.

local _, ns = ...
local Atlas, Game, Runtime = ns.Atlas, ns.Game, ns.Runtime

local PINS_MAJOR = "^HereBeDragons(.*)%-Pins%-2%.0$"
local SHOW_CONTINENT = 2 -- HBD_PINS_WORLDMAP_SHOW_CONTINENT
local CONTINENT_ZOOM = 48 -- px a tile: zoomed out further, we're showing a continent
local MAX_SIZE = 128 -- px; bigger frames are drawn for Blizzard's canvas, not as pins
local SYNC_SOON, SYNC_EVERY = 0.1, 1 -- s after the library adds or removes pins; regardless
local JOB_MS, NEWS_MS = 0.25, 1 -- ms a frame of a pass: the regular one; one with news
local OUTDOOR_WIDEST = 466 + 2 / 3 -- yd across the Minimap's view at zoom 0 outdoors
local NONE = {}

local copies, hooks = {}, {} -- { lib, tag (the renamed part: "Questie") }; lib -> { [method] = the function hooked }
local hosted, seen = {}, {} -- icon -> { home, points, shown, level, fixed, socket, inst, col, row }
local on, turnIns, offers = {}, {}, {} -- the pass's addon layers on: "addon:<key>" -> true; quests whose turn-in
-- we show; quests to pick up we show
local socket, inst, zoom -- where they're hosted: the holder on the socket's frame, instance and zoom
local holders = {} -- socket frame -> its holder
local open, dirty, syncAt = false, true, 0 -- open: a socket to host them on (the hosted are given back while it isn't)
local job -- the pass running or last run: its worker (workers[kind]; kind = "borrow" | "give back" | "place")
local workers = {} -- kind -> its Runtime.Worker
local passLevel, passContinent -- the borrow pass's: the pins' frame level; zoomed out past CONTINENT_ZOOM
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
local Listed = Runtime.Wrap("game.addon pins: minimap", function() listDirty = true end)
local METHODS = { AddWorldMapIconWorld = World, AddWorldMapIconMap = World, RemoveWorldMapIcon = World,
	RemoveAllWorldMapIcons = World, AddMinimapIconWorld = Listed, AddMinimapIconMap = Listed,
	RemoveMinimapIcon = Listed, RemoveAllMinimapIcons = Listed }

-- Every copy in LibStub (it has no events: at login, when an addon loads, when our window opens),
-- and Questie's own: since 12.8 a module of its loader, not in LibStub (its
-- Libs/HereBeDragons/HereBeDragons-Pins-2.0.lua: QuestieLoader:CreateModule("HBDPins"); the same tables
-- and methods), read from the loader's table (ImportModule would make one where there's none).
-- A newer minor loading over a copy redefines its methods, dropping our hooks: hooked again.
local function Adopt(lib, tag)
	if type(lib) ~= "table" or type(lib.worldmapPinRegistry) ~= "table" then return end
	local h = hooks[lib]
	if not h then
		h = {}
		hooks[lib] = h
		copies[#copies + 1] = { lib = lib, tag = tag }
	end
	for m, fn in pairs(METHODS) do
		if type(lib[m]) == "function" and lib[m] ~= h[m] then
			hooksecurefunc(lib, m, fn)
			h[m], dirty, listDirty = lib[m], true, true
		end
	end
end
local function Scan()
	if LibStub then -- (none: no addon brought one)
		for major, lib in LibStub:IterateLibraries() do
			local tag = major:match(PINS_MAJOR)
			if tag then Adopt(lib, (tag:gsub("^[-_ ]+", ""))) end
		end
	end
	local loader = type(QuestieLoader) == "table" and rawget(QuestieLoader, "_modules")
	if type(loader) == "table" then Adopt(rawget(loader, "HBDPins"), "Questie") end
end
Runtime.On("ADDON_LOADED", "game.addon pins: loaded", Scan)

-- Every copy: { lib, tag }; rescan: one loaded since too (game/Minimap.lua: a pin travels with the Minimap).
function Game.PinLibs(rescan)
	if rescan then Scan() end
	return copies
end

-- The addon behind a pin: a renamed copy is its addon's; in the shared copy, the ref it
-- registered under (an AceAddon, a string).
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

-- World pins ------------------------------------------------------------------------------

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

-- A socket frame's holder: a 1x1 frame of ours at its TOPLEFT, the pins' parent.
local function Holder(frame)
	local h = holders[frame]
	if not h then
		h = CreateFrame("Frame", nil, frame)
		h:SetSize(1, 1)
		h:SetPoint("TOPLEFT")
		holders[frame] = h
	end
	return h
end

-- The hosted pins at the zoom: a pass (one at a time: a borrow it stops goes on after), the holder
-- see-through meanwhile (none hosted: at once). One the library has taken back is left be (Sync
-- finds it and borrows it anew).
local function Replace()
	if Running("borrow") then dirty = true end
	Stop()
	if not next(hosted) then socket:SetAlpha(1); return end
	socket:SetAlpha(0) -- (see-through, not hidden: hiding thousands of pins is a long frame; a zoom's moment)
	job = workers.place
	Runtime.Wake(job, NEWS_MS)
end

-- The place pass: every pin hosted here at the socket's zoom, then the holder seen again.
local function PlaceAll()
	for icon, rec in pairs(hosted) do
		if rec.socket == socket and icon:GetParent() == socket then Place(icon, rec) end
		Runtime.Yield()
	end
	socket:SetAlpha(1)
end

-- A Questie turn-in for a quest whose turn-in our quests layer shows, or its "!" for one our
-- offers layer shows (the same "!" at the same quest giver: theirs over ours, it would take our pin's mouse).
local function Repeats(icon)
	local d = rawget(icon, "data")
	if type(d) ~= "table" then return false end
	return d.Type == "complete" and turnIns[d.Id] == true or d.Type == "available" and offers[d.Id] == true
end

-- One its addon has faded out (Questie's: its texture's alpha 0, which it shows no tooltip for): unseen, it would
-- still take the mouse from our pins under it, so it isn't borrowed (one borrowed is given back).
local function Faded(icon)
	if icon:GetAlpha() == 0 then return true end
	local t = rawget(icon, "texture")
	return type(t) == "table" and rawget(t, "a") == 0
end

-- Borrow what should be on the socket, give back what shouldn't (another socket's or map's too:
-- not seen here), at the pass's level and zoom band (passLevel, passContinent).
local function Sync()
	local level, continent = passLevel, passContinent
	wipe(seen)
	for _, copy in ipairs(copies) do
		local pins = copy.lib.worldmapPins
		for ref, icons in pairs(copy.lib.worldmapPinRegistry) do
			if on["addon:" .. Key(copy, ref)] then
				for icon in pairs(icons) do
					local data = pins[icon]
					local flag = data and data.worldMapShowFlag
					if data and data.instanceID == inst and flag >= 0 and (flag >= SHOW_CONTINENT or not continent)
						and not Repeats(icon) and not Faded(icon) then
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

-- An addon's layer toggled since the last pass started.
local function Toggled(layers)
	for k, v in pairs(layers) do
		if v and not on[k] and k:find("^addon:") then return true end
	end
	for k in pairs(on) do
		if not layers[k] then return true end
	end
	return false
end

-- Each kind of pass runs on its own worker: fn again each time it's woken.
for kind, fn in pairs({ borrow = Sync, ["give back"] = GiveBack, place = PlaceAll }) do
	local w = Runtime.Worker("game.addon pins: " .. kind, function()
		while true do
			fn()
			Runtime.Idle()
		end
	end, JOB_MS)
	w.kind = kind
	workers[kind] = w
end

-- A pass of a kind (one at a time: the one running stops; a worker stopped mid-run starts anew).
local function Pass(kind, ms)
	Stop()
	job = workers[kind]
	Runtime.Wake(job, ms)
end

-- No socket to host them on: what's hosted is given back (in combat: once it's over; called each frame meanwhile).
local function Close()
	if open then
		open = false
		if not next(hosted) then Stop() end
	end
	if next(hosted) and not Running("give back") and not InCombatLockdown() then Pass("give back", NEWS_MS) end
end

-- Each frame: given back while closed; borrowed at once on opening or a new socket or map, then
-- after an addon's layer is toggled, the library adds or removes pins or the zoom crosses
-- CONTINENT_ZOOM, and every SYNC_EVERY. In combat neither: a pass of either stopped, to start again after.
local function WorldPins(view)
	local s = view.sockets.world
	local combat = InCombatLockdown()
	if combat and (Running("borrow") or Running("give back")) then
		dirty = true
		Stop()
	end
	if not (view.window.shown and s) or WorldMapFrame:IsShown() then return Close() end
	if not open then Scan() end -- (LibStub has no events: look again)
	local t = GetTime()
	if not open or Holder(s.frame) ~= socket or s.inst ~= inst then
		open, socket, inst, zoom, syncAt, dirty = true, Holder(s.frame), s.inst, s.zoom, -SYNC_EVERY, true
		Replace()
	elseif s.zoom ~= zoom then -- (the socket's zoom changes where the view comes to rest)
		if (s.zoom < CONTINENT_ZOOM) ~= (zoom < CONTINENT_ZOOM) then dirty = true end
		zoom = s.zoom
		Replace()
	end
	dirty = dirty or Toggled(view.layers)
	if not combat and not Running() and ((dirty and t - syncAt >= SYNC_SOON) or t - syncAt >= SYNC_EVERY) then
		local ms = dirty and NEWS_MS or JOB_MS
		dirty, syncAt = false, t
		wipe(on)
		for k, v in pairs(view.layers) do
			if v and k:find("^addon:") then on[k] = true end
		end
		wipe(turnIns) -- (Questie's "?" of a quest whose "?" ours shows: once, ours)
		if view.layers.quests then
			for _, q in ipairs(Game.obs.quests or NONE) do
				if q.complete and q.pin.inst == inst then turnIns[q.id] = true end
			end
		end
		wipe(offers) -- (its "!" likewise)
		if view.layers.offers then
			for _, o in ipairs(Game.obs.offers or NONE) do
				if o.pos.inst == inst then offers[o.questID] = true end
			end
		end
		passLevel, passContinent = s.level or s.frame:GetFrameLevel() + 1, zoom < CONTINENT_ZOOM
		if Any() then Pass("borrow", ms) end
	end
end

-- Minimap pins ----------------------------------------------------------------------------

-- A host answers what the library asks a minimap.
local function Host()
	local f = CreateFrame("Frame", nil, UIParent)
	f:Hide()
	f.GetZoom = function() return Minimap:GetZoom() end
	f.GetZoomLevels = function() return Minimap:GetZoomLevels() end
	f.SetZoom = function(_, z) Minimap:SetZoom(z) end
	return f
end
local hidden, around = Host(), Host() -- out of sight; the Minimap's view around you on the minimap socket
hidden:SetSize(1, 1)
local ours = { [hidden] = true, [around] = true }
local placed = {} -- around as placed: frame, level, x, y, d
local resized = false -- around sized anew since the libraries on it were last told
local owed = false -- released in combat: the copies still on ours, to go back on the Minimap once it's over

-- They must still clear the map's layers.
local function Raise(lib, host)
	local level = host:GetFrameLevel()
	for pin in pairs(lib.minimapPins) do
		if pin:GetFrameLevel() <= level then pin:SetFrameLevel(level + 1) end
	end
end

-- Around you on the socket, the Minimap's view in its pixels: its diameter in yards at the socket's
-- zoom. True if sized anew: the library, which re-reads a host's size
-- only now and then, is told again.
local function Around(s, you)
	local f, z = s.frame, s.zoom
	local r = C_Minimap.GetViewRadius()
	if issecretvalue(r) or r <= 0 then r = OUTDOOR_WIDEST / 2 end
	local d = math.floor(2 * r / Atlas.TILE_YARDS * z + 0.5)
	local x, y, level = you.col * z, -you.row * z, s.level or f:GetFrameLevel() + 1
	if placed.frame ~= f then
		placed.frame, placed.x, placed.level = f, nil, nil
		around:SetParent(f)
	end
	if placed.level ~= level then
		placed.level = level
		around:SetFrameLevel(level)
	end
	if placed.x ~= x or placed.y ~= y then
		placed.x, placed.y = x, y
		around:ClearAllPoints()
		around:SetPoint("CENTER", f, "TOPLEFT", x, y)
	end
	if not around:IsShown() then around:Show() end
	if d == placed.d then return false end
	placed.d = d
	around:SetSize(d, d)
	return true
end

-- Whether an addon drawing minimap pins through this copy is on: its layer on (the gear's Other addons), or no
-- row to turn it off (an addon with no world pins: GatherMate's minimap pins alone). A renamed copy's one addon,
-- else any of those its registry holds.
local function On(key, layers)
	local e = byKey[key]
	return not (e and e.world) or layers["addon:" .. key] ~= nil
end
local function AnyOn(copy, layers)
	Game.Addons() -- (byKey up to date: a new list only when it changed)
	if copy.tag ~= "" then return On(copy.tag, layers) end
	for ref, icons in pairs(copy.lib.minimapPinRegistry) do
		if next(icons) and On(Key(copy, ref), layers) then return true end
	end
	return false
end

-- Each frame while engaged: each copy drawing on the Minimap or ours on the host it should be on:
-- out of sight with its layer off (a switch off hides all of an addon's pins), or
-- its world pins hosted instead. In combat each stays on the host it has (a host sized anew: its library re-reads
-- the size in its own time).
local Home
local function MinimapPins(view)
	local m = Game.minimap
	local combat = InCombatLockdown()
	if not m.engaged then
		if owed and not combat then Home() end
		return
	end
	owed = false
	local s, you, host = view.sockets.minimap, Game.obs.you, hidden
	if s and you.col and you.inst == s.inst then
		host = around
		if Around(s, you) then resized = true end
	elseif s then
		host = around
		if around:IsShown() then around:Hide() end -- (off your map: its pins are around you, not on the map shown)
	end
	local rotated = C_CVar.GetCVar("rotateMinimap") == "1"
	for _, copy in ipairs(copies) do
		local lib = copy.lib
		if lib.Minimap == Minimap or ours[lib.Minimap] then -- (not FarmHud's)
			local to = host
			if rotated or not AnyOn(copy, view.layers) or copy.tag ~= "" and open and view.layers["addon:" .. copy.tag] then
				to = hidden
			end
			if not combat and (lib.Minimap ~= to or (resized and to == around)) then
				lib:SetMinimapObject(to)
				Raise(lib, to)
			end
		end
	end
	if not combat then resized = false end
end

-- Released: every copy on one of ours back on the Minimap (game/Minimap.lua's undo, once it's back); in combat,
-- once it's over (MinimapPins), unless the takeover has the Minimap again by then.
function Home()
	owed = false
	for _, copy in ipairs(copies) do
		if ours[copy.lib.Minimap] then copy.lib:SetMinimapObject(Minimap) end
	end
	around:Hide()
	wipe(placed)
end
function Game.MinimapPinsHome()
	if InCombatLockdown() then owed = true else Home() end
end

Game.Apply("addon pins", function(view)
	WorldPins(view)
	MinimapPins(view)
end)

-- Blizzard's world map gets them back as it opens.
local function Login()
	Scan()
	WorldMapFrame:HookScript("OnShow", Runtime.Wrap("game.addon pins: world map", Close))
end
Runtime.On("PLAYER_LOGIN", "game.addon pins: login", Login)
