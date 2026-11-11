-- obs.build (types/observation.lua), once: the client's build, as Data/Tiles.lua's version writes it ("1.60.1.70532"). UI's art that
-- fits only one build reads it (ui/Repaint.lua, the AI repaints); on another, one chat line says why they're off, at the first observe.

local _, ns = ...
local Atlas, Game, Runtime = ns.Atlas, ns.Game, ns.Runtime

local build

Game.Part("build", function()
	if build then return nil end
	local v, b = GetBuildInfo()
	build = v .. "." .. b
	local want = Atlas.RepaintBuild()
	if want and not Atlas.RepaintFits(build) then
		Game.Say("the map's art repairs are off: they were checked on game build " .. want .. ", this is " .. build .. ". An update of MagicMap brings them back.")
		Runtime.Trace("repaint", { e = "off", want = want, have = build })
	end
	return build
end)
