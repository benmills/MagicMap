-- The ocean (Data/Sea.lua, tools/gen_sea.py): one picture round the continent, over the tiles, where their water is near-black;
-- past it, the same deep colour, the window's backdrop (ui/Window.lua). Placed for the camera each frame, as the base picture
-- (ui/Base.lua), nothing set if nothing moved. Switched by Feel's "sea.on".

local _, ns = ...
local UI = ns.UI
local Atlas, Window = ns.Atlas, ns.UI.Window

local LEVEL = 3 -- over the tiles' canvas (ui/Engine.lua: its layer's level 1, its child), under the buildings (4)

local frame = CreateFrame("Frame", nil, Window.view)
frame:SetAllPoints()
frame:SetFrameLevel(Window.view:GetFrameLevel() + LEVEL)
local tex = frame:CreateTexture(nil, "ARTWORK")
tex:SetSnapToPixelGrid(false)
tex:SetTexelSnappingBias(0)
tex:Hide()

local Sea = {}
UI.Sea = Sea

local on, file = true, nil
local ki, kx, ky, kz, kw, kh -- where it stands

local function Hide()
	if file then
		tex:Hide()
		file = nil
	end
end

function Sea.Set(v)
	if v == on then return end
	on = v
	if not v then Hide() end
	if Window.Backdrop then Window.Backdrop() end
end

-- The colour behind the map: the ocean's, where there is one (nil: the map's own).
function Sea.Deep(inst)
	local s = on and Atlas.Sea(inst)
	return s and Atlas.SeaDeep()
end

-- Each frame (Window's draw step): the picture placed for the camera cam in a view w x h, or hidden.
function Sea.Draw(inst, cam, w, h)
	local b = on and Atlas.Sea(inst)
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
	tex:SetTexCoord((c0 - b.c0) * u, (c1 - b.c0) * u, (r0 - b.r0) * v, (r1 - b.r0) * v)
	tex:SetPoint("TOPLEFT", Window.view, "TOPLEFT", w / 2 + (c0 - cam.cx) * z, -(h / 2 + (r0 - cam.cy) * z))
	tex:SetSize((c1 - c0) * z, (r1 - r0) * z)
	tex:Show()
	ki, kx, ky, kz, kw, kh = inst, cam.cx, cam.cy, z, w, h
end

function Sea.Shown() return file ~= nil end -- (the tests)
Sea.frame = frame
