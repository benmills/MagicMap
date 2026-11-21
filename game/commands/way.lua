-- way (types/view.lua MM.CmdWay): the chat box opened holding "/way <zone> <x> <y>" for pos, not
-- sent; nothing where no zone's map has it.

local _, ns = ...
local Atlas, Game = ns.Atlas, ns.Game

Game.Handle("way", function(c)
	local z = Atlas.ZoneMapAt(c.pos.inst, c.pos.col, c.pos.row)
	if not z then return end
	local open = ChatFrame_OpenChat or ChatFrameUtil.OpenChat -- (whichever the client has)
	open(string.format("/way %s %.1f %.1f", z.name, z.x * 100, z.y * 100))
end)
