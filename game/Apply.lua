-- Apply phase: Game acts on View (types/view.lua). Game.Apply(name, fn) runs
-- fn(view) every frame as its own step, "game.<name>", in registration order
-- (the Minimap takeover: game/Minimap.lua). view is UI.View() when Game knows
-- its `v`; otherwise, or UI.View failing, SAFE: Blizzard's minimap, nothing borrowed.

local _, ns = ...
local Game, Runtime = ns.Game, ns.Runtime

local SAFE = { v = 1, frame = 0, minimap = "blizzard", renderer = "ours", inst = 0, -- types/view.lua SAFE_VIEW
	window = { shown = false, big = false, still = false, strata = "LOW", level = 0, homeAlpha = 1 },
	layers = {}, sockets = {}, button = true }

local function View()
	local ok, view = pcall(ns.UI.View)
	if not ok or type(view) ~= "table" or view.v ~= 1 then return SAFE end
	return view
end

function Game.Apply(name, fn)
	Runtime.Step("apply", "game." .. name, function() fn(View()) end)
end

-- The instance the map shows while it's shown, false while it's hidden (nil: no apply yet), as of the
-- last apply: what Game's parts read of View (they register no apply step: tools/luacheck.py).
Game.Apply("view", function(view) Game.shownInst = view.window.shown and view.inst end)
