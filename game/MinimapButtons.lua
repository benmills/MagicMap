-- The Minimap's buttons, for the gear's Minimap buttons submenu (ui/Menus.lua): the takeover (game/Minimap.lua)
-- hides them with the Minimap and its cluster, so they're offered there, one row each; none on the map's edge.
-- Game.MinimapButtons() is obs.buttons (game/parts/Buttons.lua; types/observation.lua MM.ObsButton): { id, name,
-- icon, blizzard? } by name, Blizzard's last; looked for again every SCAN s and on entering the world, a new list
-- only when one comes, goes or changes its name or icon:
--   LibDBIcon-1.0's (LibStub): each registered launcher's label (else its name) and icon
--   the addon compartment's (AddonCompartmentFrame.registeredAddons): its text and icon; not MagicMap's own, nor a
--     LibDBIcon launcher's copy there (its name or label, compared without colours, case, spaces or punctuation)
--   any other named Button an addon hung on the Minimap (not a map pin: game/Minimap.lua's IsMinimapPin; one an addon,
--     none for an addon its launcher already lists), the stand-in holding its children, MinimapBackdrop or the
--     cluster: shown, not protected, its global name not Blizzard's (issecurevariable: the addon that made it); its
--     name that addon's title (else its own, trimmed); its icon the texture it draws (its icon, else its art)
--   Blizzard's the takeover hides: the calendar (GameTimeFrame, while it's enabled) and the clock
--     (TimeManagerClockButton)
-- Game.ClickButton(id, button): the button command's, what a click on it does: the launcher's OnClick(its LibDBIcon
-- button, button), the entry's func as the compartment's menu calls it, the button's Click(button).
-- Game.ButtonTooltip(owner, anchor, id): the tooltip command's: the launcher's OnTooltipShow on GameTooltip (else
-- its OnEnter(owner)), the entry's funcOnEnter(owner); false: the one shown goes (OnLeave, funcOnLeave).

local ADDON, ns = ...
local Game, Runtime = ns.Game, ns.Runtime

local SCAN = 3 -- s
local LDB_PREFIX = "LibDBIcon10_"
local CLOCK_ICON = "Interface\\Icons\\INV_Misc_PocketWatch_01"
local CALENDAR_ICON = "Interface\\Icons\\INV_Misc_Note_06"

local list -- the last handed over
local acts = {} -- id -> what a click does: { obj, frame } (a launcher), { entry }, { button }
local dirty = true

Runtime.Every(SCAN, "game.buttons scan", function() dirty = true end)
Runtime.On("PLAYER_ENTERING_WORLD", "game.buttons", function() dirty = true end)

local function Plain(s) return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
-- A name as two rows for one addon compare it: no colours, case, spaces or punctuation ("Leatrix_Plus", "Leatrix Plus").
local function Key(s) return (Plain(s):lower():gsub("[^%w]", "")) end

-- A texture's art as a row's icon: "A:<atlas>", a file or a FileDataID.
local function Art(t)
	if type(t) ~= "table" or not t.GetObjectType or t:GetObjectType() ~= "Texture" then return nil end
	local a = t:GetAtlas()
	if a and a ~= "" then return "A:" .. a end
	local f = t:GetTexture()
	if f and f ~= "" then return f end
end

-- What a button draws: its icon, its normal texture, else its first shown art (ARTWORK first: over its backing).
local function Icon(b)
	local i = Art(b.icon) or Art(b.Icon) or Art(b.GetNormalTexture and b:GetNormalTexture())
	if i then return i end
	local regions, other = { b:GetRegions() }, nil
	for _, r in ipairs(regions) do
		if r:GetObjectType() == "Texture" and r:IsShown() then
			local art = Art(r)
			if art and r:GetDrawLayer() == "ARTWORK" then return art end
			other = other or art
		end
	end
	return other
end

local function Atlased(icon)
	if type(icon) == "string" and C_Texture.GetAtlasInfo(icon) then return "A:" .. icon end
	return icon
end

-- An addon's own button's name: its addon's title, else its name without the usual decoration.
local function Named(name, addon)
	local title = addon and C_AddOns.GetAddOnMetadata(addon, "Title")
	if title and title ~= "" then return Plain(title) end
	local n = name:gsub("^" .. LDB_PREFIX, ""):gsub("_?[Mm]ini[Mm]ap_?[Bb]utton$", ""):gsub("_?[Bb]utton$", "")
	return n ~= "" and n or name
end

local function ByName(a, b)
	if (a.blizzard or false) ~= (b.blizzard or false) then return not a.blizzard end
	local x, y = Plain(a.name):lower(), Plain(b.name):lower()
	if x ~= y then return x < y end
	return a.id < b.id
end

local function Scan()
	local out, ids, frames, names, addons = {}, {}, {}, {}, {} -- names: Key()s listed; addons: an addon with a row
	local function Add(id, name, icon, act, blizzard)
		if ids[id] or names[Key(name)] then return end
		ids[id], names[Key(name)] = act, true
		out[#out + 1] = { id = id, name = name, icon = icon, blizzard = blizzard }
	end
	local lib = LibStub and LibStub("LibDBIcon-1.0", true)
	for name, b in pairs(lib and lib.objects or {}) do
		local obj = b.dataObject
		frames[b] = true
		if obj and obj.OnClick then
			Add("ldb:" .. name, obj.label or name, Atlased(obj.icon), { obj = obj, frame = b })
			names[Key(name)] = true -- (its compartment copy may go by either)
		end
	end
	local cf = AddonCompartmentFrame
	for _, e in ipairs(cf and cf.registeredAddons or {}) do
		local text = e.text and Plain(e.text)
		if text and text ~= ADDON and e.func then
			Add("cmp:" .. text, e.text, Atlased(e.icon), { entry = e })
		end
	end
	local function Look(parent)
		if not parent then return end
		for _, b in ipairs({ parent:GetChildren() }) do
			local name = b:GetName()
			if name and not frames[b] and b:GetObjectType() == "Button" and b:IsShown() and not b:IsProtected()
				and not Game.IsMinimapPin(b) then -- (a map pin on the Minimap: Questie's quests, HereBeDragons' and GatherMate's)
				frames[b] = true
				local secure, addon = issecurevariable(name)
				if not secure and addon ~= ADDON and not (addon and (addons[addon] or names[Key(addon)])) then -- (an addon's
					-- one button; none for an addon already listed by its launcher)
					if addon then addons[addon] = true end
					Add("btn:" .. name, Named(name, addon), Icon(b), { button = b })
				end
			end
		end
	end
	Look(Minimap)
	Look(MagicMapMinimapStandIn)
	Look(MinimapBackdrop)
	Look(MinimapCluster)
	Look(MinimapCluster and MinimapCluster.MinimapContainer)
	if GameTimeFrame and GameTimeFrame:IsEnabled() then
		Add("blz:calendar", "Calendar", Art(GameTimeFrame.StateTexture) or CALENDAR_ICON, { button = GameTimeFrame }, true)
	end
	if TimeManagerClockButton then Add("blz:clock", "Clock", CLOCK_ICON, { button = TimeManagerClockButton }, true) end
	table.sort(out, ByName)
	return out, ids
end

local function Same(a, b)
	if not b or #a ~= #b then return false end
	for i, x in ipairs(a) do
		local y = b[i]
		if x.id ~= y.id or x.name ~= y.name or x.icon ~= y.icon then return false end
	end
	return true
end

function Game.MinimapButtons()
	if not dirty then return list end
	dirty = false
	local out, ids = Scan()
	acts = ids
	if not Same(out, list) then list = out end
	return list
end

function Game.ClickButton(id, button)
	local a = acts[id]
	if not a then return end
	button = button or "LeftButton"
	if a.obj then
		a.obj.OnClick(a.frame, button)
	elseif a.entry then
		a.entry.func(nil, { buttonName = button }, nil) -- (as the compartment's own menu calls it: MenuUtil's callback)
	else
		a.button:Click(button)
	end
end

local tip -- the one whose tooltip is shown: { act, owner }
function Game.ButtonTooltip(owner, anchor, id)
	if tip then
		local a, o = tip[1], tip[2]
		tip = nil
		if a.obj and not a.obj.OnTooltipShow and a.obj.OnLeave then
			a.obj.OnLeave(o)
		elseif a.entry and a.entry.funcOnLeave then
			a.entry.funcOnLeave(o)
		else
			Game.HideTooltip(o)
		end
	end
	local a = owner and acts[id]
	if not a then return end
	if a.obj and a.obj.OnTooltipShow then
		Game.Tooltip(owner, anchor or "ANCHOR_RIGHT")
		a.obj.OnTooltipShow(GameTooltip)
		GameTooltip:Show()
	elseif a.obj and a.obj.OnEnter then
		a.obj.OnEnter(owner)
	elseif a.entry and a.entry.funcOnEnter then
		a.entry.funcOnEnter(owner)
	else
		return
	end
	tip = { a, owner }
end
