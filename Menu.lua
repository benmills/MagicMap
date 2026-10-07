-- Minimal self-contained popup menu attached to any button. Blizzard's menu
-- APIs differ between Classic (UIDropDownMenu) and Retail (MenuUtil), so we
-- roll our own. Opens upward (or "down"), right-aligned to the button, or "downleft", left-aligned.
--
--   local menu = ns.AttachMenu(button, width [, "down" | "downleft"])
--   menu.getItems = function() return { { text = "A", value = 1, selected = true }, ... } end
--   menu.onSelect = function(value, text) end
--   menu.keepOpen = true -- checklist mode: items may set checked = true|false
--   menu.maxRows = 30   -- taller than the default before it scrolls
-- Items may also set disabled (headings), indent (levels) and tip (hover tooltip).
--
-- Or a context menu at the cursor, owned by any frame (not opened by its clicks):
--   ns.OpenMenuAtCursor(owner, width, items, onSelect)

local ADDON, ns = ...

local ROW_HEIGHT = 18
local MAX_ROWS = 18

local openMenu -- only one open at a time
local clientMenu -- the last one opened with ns.OpenClientMenu

function ns.IsMenuOpen()
	return openMenu ~= nil or (clientMenu and clientMenu.IsShown and clientMenu:IsShown()) or false
end

-- The client's own context menu (MenuUtil, where it exists), counted as open
-- like ours so the controls that opened it don't fade under it.
function ns.OpenClientMenu(owner, generator)
	clientMenu = MenuUtil.CreateContextMenu(owner, generator)
	return clientMenu
end

local function RowOnEnter(self)
	local tip = self.item and self.item.tip
	if not tip then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(tip, 1, 1, 1, 1, true)
	GameTooltip:Show()
end
local function RowOnLeave(self)
	if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end

local function MakeBackground(f)
	local edge = f:CreateTexture(nil, "BACKGROUND", nil, -2)
	edge:SetAllPoints()
	edge:SetColorTexture(0.55, 0.42, 0.25, 0.9)
	local bg = f:CreateTexture(nil, "BACKGROUND", nil, -1)
	bg:SetPoint("TOPLEFT", 1, -1)
	bg:SetPoint("BOTTOMRIGHT", -1, 1)
	bg:SetColorTexture(0.05, 0.04, 0.03, 0.96)
end

-- The list itself, owned by `button`; anchoring is up to the caller.
local function NewMenu(button, width)
	local menu = {}

	local list = CreateFrame("Frame", nil, button)
	list:SetFrameStrata("DIALOG")
	list:SetToplevel(true)
	list:SetClampedToScreen(true)
	menu.list = list
	list:SetWidth(width)
	list:EnableMouse(true)
	list:EnableMouseWheel(true)
	list:Hide()
	MakeBackground(list)

	local rows = {}
	local items = {}
	local offset = 0

	local function Refresh()
		local maxRows = menu.maxRows or MAX_ROWS
		local visible = math.min(#items, maxRows)
		list:SetHeight(visible * ROW_HEIGHT + 4)
		for i = 1, maxRows do
			local row = rows[i]
			local item = items[i + offset]
			if i <= visible and item then
				if not row then
					row = CreateFrame("Button", nil, list)
					row:SetHeight(ROW_HEIGHT)
					row:SetPoint("TOPLEFT", 2, -2 - (i - 1) * ROW_HEIGHT)
					row:SetPoint("TOPRIGHT", -2, -2 - (i - 1) * ROW_HEIGHT)
					row:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
					row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
					row.text:SetPoint("LEFT", 6, 0)
					row.text:SetPoint("RIGHT", -6, 0)
					row.text:SetJustifyH("LEFT")
					row.text:SetWordWrap(false)
					row:SetScript("OnEnter", RowOnEnter)
					row:SetScript("OnLeave", RowOnLeave)
					row:SetScript("OnClick", function(self)
						local it = self.item
						if menu.keepOpen then
							-- Checklist mode: toggle in place and stay open.
							if it and not it.disabled and menu.onSelect then menu.onSelect(it.value, it.text) end
							items = menu.getItems and menu.getItems() or {}
							Refresh()
							return
						end
						list:Hide()
						if it and not it.disabled and menu.onSelect then menu.onSelect(it.value, it.text) end
					end)
					rows[i] = row
				end
				row.item = item
				row.text:SetPoint("LEFT", 6 + (item.indent or 0) * 14, 0)
				-- Disabled rows (headings, info) don't light up or take clicks.
				row:EnableMouse(not item.disabled)
				if item.divider and not row.rule then
					row.rule = row:CreateTexture(nil, "ARTWORK")
					row.rule:SetHeight(1)
					row.rule:SetPoint("LEFT", 6, 0)
					row.rule:SetPoint("RIGHT", -6, 0)
					row.rule:SetColorTexture(0.55, 0.42, 0.25, 0.7)
				end
				if row.rule then row.rule:SetShown(item.divider == true) end
				if item.checked ~= nil then
					row.text:SetText((item.checked and "|cff33ff33[x]|r " or "|cff888888[ ]|r ") .. item.text)
				else
					row.text:SetText(item.text)
				end
				if item.disabled then
					row.text:SetTextColor(0.5, 0.5, 0.5)
				elseif item.selected then
					row.text:SetTextColor(1, 0.82, 0)
				else
					row.text:SetTextColor(1, 1, 1)
				end
				row:Show()
			elseif row then
				row:Hide()
			end
		end
	end

	list:SetScript("OnMouseWheel", function(_, delta)
		local maxOffset = math.max(0, #items - (menu.maxRows or MAX_ROWS))
		offset = math.max(0, math.min(maxOffset, offset - delta * 3))
		Refresh()
	end)

	-- Close when clicking anywhere else.
	list:SetScript("OnUpdate", ns.Timed("menu", function()
		if (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
			and not list:IsMouseOver() and (menu.atCursor or not button:IsMouseOver()) then
			list:Hide()
		end
	end))
	list:SetScript("OnHide", function() if openMenu == menu then openMenu = nil end end)

	function menu:Close() list:Hide() end
	function menu:IsOpen() return list:IsShown() end
	function menu:Toggle()
		if list:IsShown() then
			list:Hide()
			return
		end
		if openMenu then openMenu:Close() end
		items = menu.getItems and menu.getItems() or {}
		-- Start scrolled so the selected item is visible.
		offset = 0
		for i, it in ipairs(items) do
			if it.selected then
				offset = math.max(0, math.min(i - 1, #items - (menu.maxRows or MAX_ROWS)))
				break
			end
		end
		Refresh()
		list:Show()
		openMenu = menu
	end

	return menu
end

function ns.AttachMenu(button, width, direction)
	local menu = NewMenu(button, width)
	local list = menu.list
	if direction == "down" then
		list:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -6)
	elseif direction == "downleft" then
		list:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -6)
	else
		list:SetPoint("BOTTOMRIGHT", button, "TOPRIGHT", 0, 6)
	end
	button:HookScript("OnClick", function() menu:Toggle() end)
	return menu
end

local cursorMenus = {} -- owner -> menu
function ns.OpenMenuAtCursor(owner, width, items, onSelect)
	local menu = cursorMenus[owner]
	if not menu then
		menu = NewMenu(owner, width)
		menu.atCursor = true -- a click on the owner closes it too
		cursorMenus[owner] = menu
	end
	menu:Close()
	menu.list:SetWidth(width) -- one menu per owner, sized for each use
	menu.getItems = function() return items end
	menu.onSelect = onSelect
	local scale = UIParent:GetEffectiveScale()
	local x, y = GetCursorPosition()
	menu.list:ClearAllPoints()
	menu.list:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
	menu:Toggle()
	return menu
end
