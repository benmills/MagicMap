-- The base picture: the continent as one stylised flat picture (Data/Base.lua, Textures/Base*.blp, tools/
-- gen_base.py: land a colour a zone from the tiles' own mean, water the backdrop's, a crisp coast), one
-- texture on the view under every layer. Two jobs. Under the tiles, always: a fast zoom or a flick that
-- outruns the tiles' layout shows ground, not the dark backdrop (the tiles' seams too: a hairline between two
-- shows the zone's colour). And from FAR px a tile out, in their place: the tiles hidden and not laid out
-- (one region instead of ~1,800: the far zoom's cost), the picture the baked 42-51 px a tile there is
-- (1:1 or better; the mips below). The crossfade: the picture is already there, the tiles' frame fades out over
-- FADE_S and, the layer idle (Engine: its canvases emptied, no layout), stays out; from NEAR it lays out and
-- fades in once it has a canvas. FAR and NEAR a ratio apart, so a zoom hovering at one doesn't flap.
-- Placed from the camera each frame, not laid out: the part of the picture in the view, as a sub-rectangle
-- of the texture (its texture coordinates), at (the tile rect - the camera's centre) x zoom, so no offset
-- grows past the view's size however far in, and it moves with the camera in the frame it moves (the tiles'
-- canvases scale to the zoom the same frame: ui/Engine.lua Put). Unsnapped, as the tiles are.

local _, ns = ...
local UI, Atlas = ns.UI, ns.Atlas
local Window, Camera, Engine = UI.Window, UI.Camera, UI.Engine

local FAR, NEAR = 24, 26 -- px a tile: the tiles hidden under FAR, laid out again over NEAR
local FADE_S = 0.18 -- the tiles' crossfade
local Base = { FAR = FAR }
UI.Base = Base

local tex = Window.view:CreateTexture(nil, "BACKGROUND", nil, -7) -- over the backdrop (-8), under every layer's frame
tex:SetSnapToPixelGrid(false)
tex:SetTexelSnappingBias(0)
tex:Hide()

local far = false -- the camera is under FAR (NEAR, once it has been)
local alpha, at = 1, nil -- the tiles layer's frame alpha; the time of its last step
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

-- The tiles layer's frame, faded toward 1 (near) or 0 (far) at 1 / FADE_S a second; it starts rising once
-- the layout has laid it out (a canvas shown: its first layout lands in a frame or two).
local function Fade(now, up)
	local tiles = UI.Tiles
	local dt = at and math.min(now - at, 0.1) or 0
	at = now
	local to = up and (tiles.front and 1 or 0) or 0
	if alpha < to then
		alpha = math.min(to, alpha + dt / FADE_S)
	elseif alpha > to then
		alpha = math.max(to, alpha - dt / FADE_S)
	end
	tiles.frame:SetAlpha(alpha)
end

-- Each frame (Window's draw step, before Engine.Draw): the picture placed, the tiles' fade stepped.
function Base.Draw(inst, cam, w, h)
	local has = Atlas.Base(inst) ~= nil
	if not has then
		far = false
	elseif far then
		far = cam.zoom < NEAR
	else
		far = cam.zoom < FAR
	end
	Place(inst, cam, w, h)
	if alpha ~= 1 or far then Fade(GetTime(), not far) else at = nil end
end

function Base.Shown() return file ~= nil end -- (the tests)

-- The tiles layer not laid out: the camera far out and the tiles faded away (Engine: idle, its canvases emptied).
UI.Tiles.idle = function() return far and alpha == 0 end
