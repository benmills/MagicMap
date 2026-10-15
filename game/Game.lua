-- Game: the only system that touches the WoW API, other addons and
-- SavedVariables. This file: load and init MagicMapAtlasDB, login.
--
-- Saved data belongs to the system that owns it: Game.Load(owner, fn) calls
-- fn(MagicMapAtlasDB[owner]) once it's loaded (at once if it already is).

local ADDON, ns = ...
local Game = ns.Game or {}; ns.Game = Game
local Runtime = ns.Runtime

local loaders = {}

function Game.Print(msg) print("|cff66ccffMagicMap Atlas|r " .. msg) end

function Game.Load(owner, fn)
	fn = Runtime.Wrap("load " .. owner, fn)
	if Game.db then
		Game.db[owner] = Game.db[owner] or {}
		fn(Game.db[owner])
	else
		loaders[#loaders + 1] = { owner, fn }
	end
end

Runtime.On("ADDON_LOADED", "game.loaded", function(_, name)
	if name ~= ADDON then return end
	MagicMapAtlasDB = MagicMapAtlasDB or {}
	Game.db = MagicMapAtlasDB
	for _, l in ipairs(loaders) do
		Game.db[l[1]] = Game.db[l[1]] or {}
		l[2](Game.db[l[1]])
	end
	loaders = nil
end)

Runtime.On("PLAYER_LOGIN", "game.login", function()
	Runtime.boot.login = { t = debugprofilestop(), mem = collectgarbage("count") }
end)
