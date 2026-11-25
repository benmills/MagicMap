-- The base picture: the continent as one stylised flat picture (Data/Base.lua, Textures/Base*.blp, tools/
-- gen_base.py: land a colour a zone from the tiles' own mean, water the backdrop's, a crisp coast), one
-- texture on the view under every layer: the underlay only. The tiles are always the map, at every zoom;
-- the picture shows through where they aren't (yet): a fast zoom or a flick that outruns the tiles' layout,
-- tiles not yet loaded, the tiles' seams (a hairline between two shows the zone's colour), so what shows
-- is ground, not the dark backdrop. Nothing switches over to it, however far out.
-- Placed from the camera each frame, not laid out: the part of the picture in the view, as a sub-rectangle
-- of the texture (its texture coordinates), at (the tile rect - the camera's centre) x zoom, so no offset
-- grows past the view's size however far in, and it moves with the camera in the frame it moves (the tiles'
-- canvases scale to the zoom the same frame: ui/Engine.lua Put). Unsnapped, as the tiles are.

local _, ns = ...
local UI, Atlas = ns.UI, ns.Atlas
local Window = UI.Window

local Base = {}
UI.Base = Base

local tex = Window.view:CreateTexture(nil, "BACKGROUND", nil, -7) -- over the backdrop (-8), under every layer's frame
tex:SetSnapToPixelGrid(false)
tex:SetTexelSnappingBias(0)
tex:Hide()

local file = nil -- what the texture shows
local ki, kx, ky, kz, kw, kh -- where it stands: nothing moved, nothing set

local function Hide()
	if file then
		tex:Hide()
		file = nil
	end
end

-- The picture placed for the camera cam in a view w x h, or hidden (no picture of this map, none in the view).
local function Place(inst, cam, w, h)
	local b = Atlas.Base(inst)
	if not b then return Hide() end
	local z = cam.zoom
	local hw, hh = w / 2 / z, h / 2 / z -- /: never 0 (zoom >= MIN_ZOOM)
	local c0, r0 = math.max(b.c0, cam.cx - hw), math.max(b.r0, cam.cy - hh)
	local c1, r1 = math.min(b.c1, cam.cx + hw), math.min(b.r1, cam.cy + hh)
	if c0 >= c1 or r0 >= r1 then return Hide() end
	if file and ki == inst and kx == cam.cx and ky == cam.cy and kz == z and kw == w and kh == h then return end
	if file ~= b.file then
		tex:SetTexture(Atlas.ROOT .. b.file, "CLAMP", "CLAMP", "TRILINEAR")
		file = b.file
	end
	local u, v = b.px / b.w, b.px / b.h -- /: never 0 (a texture's size)
	tex:SetTexCoord((c0 - b.c0) * u, (r0 - b.r0) * v, (c0 - b.c0) * u, (r1 - b.r0) * v, (c1 - b.c0) * u,
		(r0 - b.r0) * v, (c1 - b.c0) * u, (r1 - b.r0) * v)
	tex:SetPoint("TOPLEFT", Window.view, "TOPLEFT", w / 2 + (c0 - cam.cx) * z, -(h / 2 + (r0 - cam.cy) * z))
	tex:SetSize((c1 - c0) * z, (r1 - r0) * z)
	tex:Show()
	ki, kx, ky, kz, kw, kh = inst, cam.cx, cam.cy, z, w, h
end

-- Each frame (Window's draw step, before Engine.Draw): the picture placed.
function Base.Draw(inst, cam, w, h) Place(inst, cam, w, h) end

function Base.Shown() return file ~= nil end -- (the tests)
