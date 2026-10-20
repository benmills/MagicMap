-- Game: the only system that touches the WoW API, other addons and
-- SavedVariables. This file: load and check MagicMap2DB, login, loading screens.
--
-- Saved data belongs to the system that owns it: Game.Load(owner, fn, spec) calls
-- fn(saved) once it's loaded (at once if it already is). It never hands over
-- garbage (docs/runtime.md "Saved data"): spec = { version, defaults, optional, migrate(saved, from) };
-- not a table: reset; older: migrate, else defaults filled; newer (a downgrade):
-- left untouched on disk and this session runs on defaults; a top-level key of
-- the wrong type gets its default (an optional one, nil). The version is kept as saved._v.

local ADDON, ns = ...
local Game = ns.Game or {}; ns.Game = Game
local Runtime = ns.Runtime

local loaders = {}
local NONE = {}

function Game.Print(msg) print("|cff66ccffMagicMap|r " .. msg) end -- diagnostics: checks, bench, shots

-- The user's chat line, as UI.Print's (v1-plan §4 Chat; Core.lua:44-46): what a Command says back.
function Game.Say(msg) print("|cffffd100MagicMap|r: " .. msg) end

local function Copy(v)
	if type(v) ~= "table" then return v end
	local t = {}
	for k, x in pairs(v) do t[k] = Copy(x) end
	return t
end

-- The owner's saved table, checked against spec.
local function Open(owner, spec)
	spec = spec or {}
	local db, version, defaults = Game.db, spec.version or 1, spec.defaults or {}
	local saved = db[owner]
	local from = type(saved) == "table" and saved._v or 0
	if type(saved) ~= "table" or type(from) ~= "number" then
		if saved ~= nil then Runtime.Trace("saved", { owner = owner, e = "reset", was = type(saved) }) end
		saved, from = {}, 0
		db[owner] = saved
	end
	if from > version then
		Runtime.Trace("saved", { owner = owner, e = "newer", v = from })
		saved = { _v = version } -- not db[owner]: the newer build's data stays as it was
	elseif from < version and spec.migrate and next(saved) then
		local ok = Runtime.Wrap("load " .. owner .. " (migrate)", function() spec.migrate(saved, from); return true end)()
		if not ok then
			wipe(saved)
			Runtime.Trace("saved", { owner = owner, e = "reset", was = from })
		end
	end
	for k, d in pairs(defaults) do
		if type(saved[k]) ~= type(d) then saved[k] = Copy(d) end
	end
	for k, t in pairs(spec.optional or NONE) do
		if saved[k] ~= nil and type(saved[k]) ~= t then
			Runtime.Trace("saved", { owner = owner, e = "dropped", key = k, was = type(saved[k]) })
			saved[k] = nil
		end
	end
	saved._v = version
	return saved
end

function Game.Load(owner, fn, spec)
	fn = Runtime.Wrap("load " .. owner, fn, false)
	if Game.db then
		fn(Open(owner, spec))
	else
		loaders[#loaders + 1] = { owner, fn, spec }
	end
end

-- Game's own part (types/saved.lua MM.SavedGame): the minimap button's angle (game/Button.lua), tracking it turned off,
-- /mm indoor's reports (game/Renderer.lua).
Game.Load("Game", function(saved) Game.saved = saved end,
	{ version = 1, defaults = { trackingOff = {} }, optional = { buttonAngle = "number", indoorDebug = "boolean" } })

Runtime.On("ADDON_LOADED", "game.loaded", function(_, name)
	if name ~= ADDON then return end
	if type(MagicMap2DB) ~= "table" then MagicMap2DB = {} end -- absent, or not ours
	Game.db = MagicMap2DB
	for _, l in ipairs(loaders) do l[2](Open(l[1], l[3])) end
	loaders = nil
end)

Runtime.On("PLAYER_LOGIN", "game.login", function()
	Runtime.boot.login = { t = debugprofilestop(), mem = collectgarbage("count") }
end)

-- Login, /reload and every loading screen: the frames after it are expected to be slow.
Runtime.On("PLAYER_ENTERING_WORLD", "game.enter", function(_, login, reload)
	Runtime.Grace((login or reload) and "login" or "loading", 5)
	Runtime.Trace("enter", (login and "login") or (reload and "reload") or "loading")
end)
