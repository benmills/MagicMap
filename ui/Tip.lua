-- One look for every tip the map shows (GameTooltip's, the popup's: ui/Popup.lua).
-- A hover tip: the thing's name as the title (the client's white, but where colour means something: a quest's
-- difficulty, a member's class), then its facts in small type, wrapping, in one grey (DIM), what matters in
-- white, parts of a line apart by SEP; the first says what it is ("Herbalism", "Flight point", "Rare"), a status
-- ("Not in sight", "Nearby now") a line of its own. No hint lines. A control's: its title alone (Label). A
-- description (the settings window's rows, the gear's): Blizzard's white title, gold body, its default in DIM
-- (Describe). A menu row's icon: Mark.
-- Small type is set through Small, each font string its font back when its tooltip hides or clears (Watch: once a
-- tooltip; GameTooltip here). Nothing here measures a tooltip's own regions: the client answers their widths and
-- places secret (12.x).

local _, ns = ...
local UI, Runtime = ns.UI, ns.Runtime

local Tip = {}
UI.Tip = Tip

Tip.DIM, Tip.WHITE = "|cff9d9d9d", "|cffffffff" -- QuestInfo.lua:180
Tip.GREY = 0x9d / 255 -- DIM as a colour (AddLine's)
Tip.SEP = Tip.DIM .. "  ·  |r"
local GOLD = { 1, 0.82, 0 } -- a description's body (GearMenu.lua:69-72)

-- A tooltip's font strings by name (TextLeft3, TextRight1), found once each.
local regions = setmetatable({}, { __mode = "k" })
function Tip.Region(tip, name)
	local t = regions[tip]
	if not t then
		t = {}
		regions[tip] = t
	end
	if not t[name] then
		local full = tip:GetName() .. name
		for _, r in ipairs({ tip:GetRegions() }) do
			if r:GetName() == full then t[name] = r end
		end
	end
	return t[name]
end
-- Its last line's left font string.
function Tip.Last(tip) return Tip.Region(tip, "TextLeft" .. tip:NumLines()) end

-- fs in small type, its font back when its tooltip hides or clears.
local styled = {} -- fs -> its font object before
function Tip.Small(fs)
	if not styled[fs] then styled[fs] = fs:GetFontObject() end
	fs:SetFontObject(GameTooltipTextSmall)
end

-- A fact under the title: small, wrapping, DIM (a part coloured itself keeps its colour).
function Tip.Fact(tip, text)
	tip:AddLine(text, Tip.GREY, Tip.GREY, Tip.GREY, true)
	Tip.Small(Tip.Last(tip))
end

local cleared = {} -- fn(tip): more to put back when a tooltip clears (ui/QuestTooltip.lua's level pill)
function Tip.OnClear(fn) cleared[#cleared + 1] = fn end
local function Cleared(tip)
	for fs, font in pairs(styled) do
		if fs:GetParent() == tip then
			fs:SetFontObject(font)
			styled[fs] = nil
		end
	end
	for _, fn in ipairs(cleared) do fn(tip) end
end
function Tip.Watch(tip)
	local fn = Runtime.Wrap("map: tip cleared", Cleared)
	tip:HookScript("OnHide", fn)
	tip:HookScript("OnTooltipCleared", fn)
end
Tip.Watch(GameTooltip)

-- A description on tooltip (shown by the caller, or a menu's): white title, gold body, then extra (its default) in DIM.
function Tip.Describe(tooltip, title, body, extra)
	tooltip:SetText(title, 1, 1, 1)
	if body then tooltip:AddLine(body, GOLD[1], GOLD[2], GOLD[3], true) end
	if extra then tooltip:AddLine(extra, Tip.GREY, Tip.GREY, Tip.GREY, true) end
end

-- A control's tip: its title alone, right of it (left where the screen's edge is near), or anchor.
local ROOM = 160 -- px past its right edge: room for a short tip
function Tip.Label(owner, text, anchor)
	if not anchor then
		local r, s = owner:GetRight(), owner:GetEffectiveScale()
		anchor = r and r * s + ROOM > UIParent:GetRight() * UIParent:GetEffectiveScale() and "ANCHOR_LEFT" or "ANCHOR_RIGHT"
	end
	GameTooltip:SetOwner(owner, anchor)
	GameTooltip:SetText(text, 1, 1, 1)
	GameTooltip:Show()
end

-- A menu row's icon before its name: 16 px, an Interface\Icons file's border cropped (5:59), an atlas whole (if this
-- client has it), two spaces after; "" for none.
function Tip.Mark(icon)
	if not icon then return "" end
	if type(icon) == "string" and icon:sub(1, 2) == "A:" then
		return C_Texture.GetAtlasInfo(icon:sub(3)) and "|A:" .. icon:sub(3) .. ":16:16|a  " or ""
	end
	return "|T" .. icon .. ":16:16:0:0:64:64:5:59:5:59|t  "
end
