-- way (types/view.lua MM.CmdWay): the chat box opened holding "/way <zone> <x> <y>" for pos, not
-- sent; nothing where no zone's map has it (Layers.lua:2074-2077, 2102-2117).

local _, ns = ...
local Game = ns.Game

Game.Handle("way", function(c)
	local z = Game.WaypointZone(c.pos)
	if not z then return end
	local open = ChatFrame_OpenChat or ChatFrameUtil.OpenChat -- (whichever the client has: Layers.lua:2075)
	open(string.format("/way %s %.1f %.1f", z.name, z.x * 100, z.y * 100))
end)
