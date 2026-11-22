-- Under Blizzard's minimap (Settings > General > Window > Minimap look: Blizzard's): Blizzard's own minimap stays on
-- screen where Edit Mode puts it, its ring, zone bar, buttons, clock and other addons' rim buttons all its own, and
-- the small map is drawn under it in place of its ground (View.under: game/Minimap.lua keeps the cluster shown, the
-- Minimap's ground off, its blips round over our map). It pans and zooms as ours always does; Blizzard's + and -
-- zoom it (hooked "zoomIn", "zoomOut": ui/BigMap.lua). The big map (M) is MagicMap's as ever.
-- While under (Under.on: the look Blizzard's, the minimap ours, the window small, the Minimap's spot known):
--   * the window sits on the Minimap's spot at its size, a strata under the cluster's (Blizzard's chrome over the
--     map and its blips), not moved nor resized (Under.Rect, ui/BigMap.lua; Window's moves check Under.on)
--   * MagicMap's chrome goes: the border, the title line and its buttons, the grip, our + and -; the gear stays, in
--     the window's top left corner (outside the round, under Blizzard's ring), shown as the buttons are on hover
--   * the map is round: a circle mask on the view, added to every region a layer makes (Under.Mask, called by each
--     maker: the backdrop, the ground's pictures, tiles, buildings, pins, groups, the line's dots) while the look is
--     Blizzard's (Under.styled), on none otherwise: a mask has a drawing cost the square map needn't pay. Big, it's a
--     square over the whole view. Quest areas (QuestPOIFrames draw nothing a mask takes) aren't drawn under it
--     (ui/Areas.lua); font strings take no mask (the small map draws none but a group's count).
--     A Line takes no mask in this client (it has no AddMaskTexture): the line's legs keep inside the round
--     themselves (ui/Path.lua).

local _, ns = ...
local UI, Runtime = ns.UI, ns.Runtime
local Window, Chrome = UI.Window, UI.Chrome
local frame, view = Window.frame, Window.view

local SQUARE = "Interface\\ChatFrame\\ChatFrameBackground" -- plain white: a mask that hides nothing
local LOWER = { LOW = "BACKGROUND", MEDIUM = "LOW", HIGH = "MEDIUM", DIALOG = "HIGH" } -- a strata, the one under it
local RESET_AT = 0.5 -- the reset and pin's column (above where our + stood) this far out toward the round's lower right

local Under = { on = false, styled = false }
UI.Under = Under

---------------------------------------------------------------------------
-- The mask
---------------------------------------------------------------------------

local mask = view:CreateMaskTexture()
mask:SetSnapToPixelGrid(false) -- (as what it masks: the map moves by fractions of a pixel)
mask:SetTexelSnappingBias(0)
mask:SetAllPoints()
mask:SetTexture(SQUARE)
local masked = setmetatable({}, { __mode = "k" }) -- every region a maker handed: the mask goes on and off with the look

-- A region on the map (a texture or a line): masked while the look is Blizzard's. Returns it.
function Under.Mask(r)
	masked[r] = true
	if Under.styled then r:AddMaskTexture(mask) end
	return r
end
Under.Mask(Window.backdrop)
Under.Mask(Window.curtain)

local function MaskAll(on)
	for r in pairs(masked) do
		if on then r:AddMaskTexture(mask) else r:RemoveMaskTexture(mask) end
	end
end

---------------------------------------------------------------------------
-- Where it sits, and what of MagicMap's chrome shows
---------------------------------------------------------------------------

-- The strata under Blizzard's cluster's (its own: there's none under BACKGROUND).
function Under.Strata(homeStrata) return LOWER[homeStrata] or homeStrata end

-- Small, the map would go under Blizzard's minimap: the look Blizzard's, the minimap ours, the Minimap's spot known.
function Under.Wants()
	return Under.styled and UI.Replace.Get("minimap") and UI.BigMap.home ~= nil
end

-- The Minimap's spot in the window's units (UI.BigMap.home: Game's, UIParent units), or nil.
function Under.Rect()
	local h = UI.BigMap.home
	if not h then return nil end
	local k = UIParent:GetEffectiveScale() / frame:GetEffectiveScale() -- /: never 0 (an effective scale is > 0)
	return h.left * k, h.top * k, h.w * k, h.h * k
end

-- The view's place: inside the border's insets, or (under) the whole window.
local function ViewPoints(under)
	view:ClearAllPoints()
	if under then
		view:SetAllPoints()
	else
		local insets = Chrome.border.insets
		view:SetPoint("TOPLEFT", insets[1], -insets[2])
		view:SetPoint("BOTTOMRIGHT", -insets[3], insets[4])
	end
end

local function Buttons(under, r)
	local C = UI.Controls
	C.zoomIn:SetShown(not under)
	C.zoomOut:SetShown(not under)
	local gear = C.gear
	gear:ClearAllPoints()
	if under then
		-- (the reset and pin stand above where our + would: toward the round's lower right, inside it)
		C.zoomIn:ClearAllPoints()
		C.zoomIn:SetPoint("CENTER", view, "CENTER", r * RESET_AT, -r * RESET_AT)
		gear:SetParent(Chrome.overlay)
		gear:SetPoint("TOPLEFT", view, "TOPLEFT", 0, 0)
	else
		C.Home()
		gear:SetParent(Chrome.band)
		gear:SetPoint("RIGHT", C.mode, "LEFT", -6, 0)
	end
	gear:SetFrameLevel(gear:GetParent():GetFrameLevel() + 1)
end

local laid -- the look laid out: nil, false (MagicMap's) or the round's radius
local function Layout()
	local r = Under.on and math.min(view:GetWidth(), view:GetHeight()) / 2 or false
	if r == laid then return end
	local was = laid
	laid = r
	local under = r ~= false
	if (was ~= nil and was ~= false) ~= under or was == nil then
		Chrome.border:SetShown(not under)
		Chrome.band:SetShown(not under)
		Chrome.grip:SetShown(not (under or Window.locked))
		ViewPoints(under)
	end
	mask:ClearAllPoints()
	if under then
		mask:SetTexture(Chrome.CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetSize(2 * r, 2 * r)
		mask:SetPoint("CENTER", view, "CENTER")
	else
		mask:SetTexture(SQUARE)
		mask:SetAllPoints(view)
	end
	Buttons(under, r or 0)
end

-- Each frame (Window's draw step, after the grow's): under while the look is Blizzard's, the minimap ours, the
-- window small (not big, nor shrinking back) and the Minimap's spot known; then on its spot.
function Under.Step()
	local BigMap = UI.BigMap
	local on = Under.Wants() and not BigMap.big and not BigMap.Small() or false
	if on ~= Under.on then
		Under.on = on
		Runtime.Trace("map", on and "under" or "own chrome")
		if not on and not BigMap.big and not BigMap.Small() then BigMap.Restore() end -- (not a grow: it's leaving)
	end
	if on then
		local strata = Under.Strata(BigMap.homeStrata)
		if frame:GetFrameStrata() ~= strata then frame:SetFrameStrata(strata) end
		local l, t, w, h = Under.Rect()
		if math.abs((frame:GetLeft() or 0) - l) > 0.01 or math.abs((frame:GetTop() or 0) - t) > 0.01
			or math.abs(frame:GetWidth() - w) > 0.01 or math.abs(frame:GetHeight() - h) > 0.01 then
			frame:ClearAllPoints()
			frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
			frame:SetSize(w, h)
		end
	end
	Layout()
end

local function Style(look)
	local styled = look == "blizzard"
	if styled == Under.styled then return end
	Under.styled = styled
	MaskAll(styled)
end

UI.Feel.Add("general", "Window", {
	{ key = "general.look", kind = "select", label = "Minimap look", default = "magicmap",
		options = { { "MagicMap", "magicmap" }, { "Blizzard's", "blizzard" } }, apply = Style,
		tip = "MagicMap: the small map in MagicMap's square frame, wherever you put it and at any size. Blizzard's: "
			.. "Blizzard's own minimap stays where it is, with its ring, zone name, buttons and clock, and MagicMap's "
			.. "map is drawn inside it, still panned and zoomed as ever. The big map is the same in both." },
})
