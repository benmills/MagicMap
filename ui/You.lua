-- You on the map: your arrow (Core.lua:155-175, 795-819), the Minimap's own arrow art with its shadow
-- softened (Textures/PlayerArrow.tga: tools/gen_arrow.py), the size the Minimap draws it, unsnapped
-- so it turns smoothly, over every layer. None while the map shown isn't yours, while the client
-- withholds where you are (Model.you stale: an instance's), or without a facing.

local _, ns = ...
local UI = ns.UI
local Atlas, Runtime = ns.Atlas, ns.Runtime
local Camera, Window = UI.Camera, UI.Window
local Maths = Atlas.Camera

local SIZE = 22 * 64 / 45 -- the texture, for a 22-unit arrow (Core.lua:169)

local You = {}
UI.You = You

-- Over the layers and the world socket (+8): the spike's overlay, +8 over its tiles (Core.lua:158).
local overlay = CreateFrame("Frame", nil, Window.view)
overlay:SetAllPoints()
overlay:SetFrameLevel(Window.view:GetFrameLevel() + 10)
local arrow = overlay:CreateTexture(nil, "OVERLAY")
arrow:SetTexture(Atlas.ROOT .. "Textures\\PlayerArrow")
arrow:SetSize(SIZE, SIZE)
arrow:SetSnapToPixelGrid(false)
arrow:SetTexelSnappingBias(0)
arrow:Hide()
You.arrow = arrow

-- Each frame while shown, after the map's draw: only what changed is applied (an idle frame makes
-- no widget calls for it).
Runtime.Step("ui", "map: you", function()
	local you = ns.Model.you
	if you and you.col and not you.stale and you.facing and you.inst == Camera.inst then
		local w, h = Window.Size()
		local x, y = Maths.TileToScreen(Camera.cam, w, h, you.col, you.row)
		if arrow.x ~= x or arrow.y ~= y then
			arrow.x, arrow.y = x, y
			arrow:SetPoint("CENTER", overlay, "TOPLEFT", x, -y)
		end
		if arrow.facing ~= you.facing then
			arrow.facing = you.facing
			arrow:SetRotation(you.facing)
		end
		if not arrow.shown then arrow.shown = true; arrow:Show() end
	elseif arrow.shown then
		arrow.shown = false
		arrow:Hide()
	end
end, { shownOnly = Window.frame })
