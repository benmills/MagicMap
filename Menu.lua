-- Minimal self-contained popup menu attached to any button. Blizzard's menu
-- APIs differ between Classic (UIDropDownMenu) and Retail (MenuUtil), so we
-- roll our own. Opens upward (or "down"), right-aligned to the button, or "downleft", left-aligned.
--
--   local menu = ns.AttachMenu(button, width [, "down" | "downleft"])
--   menu.getItems = function() return { { text = "A", value = 1, selected = true }, ... } end
--   menu.onSelect = function(value, text) end
--   menu.keepOpen = true -- checklist mode: items may set checked = true|false

local ADDON, ns = ...

local ROW_HEIGHT = 18
local MAX_ROWS = 18

local openMenu -- only one open at a time

function ns.IsMenuOpen() return openMenu ~= nil end

local function MakeBackground(f)
	local edge = f:CreateTexture(nil, "BACKGROUND", nil, -2)
	edge:SetAllPoints()
	edge:SetColorTexture(0.55, 0.42, 0.25, 0.9)
	local bg = f:CreateTexture(nil, "BACKGROUND", nil, -1)
	bg:SetPoint("TOPLEFT", 1, -1)
	bg:SetPoint("BOTTOMRIGHT", -1, 1)
	bg:SetColorTexture(0.05, 0.04, 0.03, 0.96)
end

function ns.AttachMenu(button, width, direction)
	local menu = {}

	local list = CreateFrame("Frame", nil, button)
	list:SetFrameStrata("DIALOG")
	list:SetToplevel(true)
	if direction == "down" then
		list:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -6)
	elseif direction == "downleft" then
		list:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -6)
	else
		list:SetPoint("BOTTOMRIGHT", button, "TOPRIGHT", 0, 6)
	end
	list:SetWidth(width)
	list:EnableMouse(true)
	list:EnableMouseWheel(true)
	list:Hide()
	MakeBackground(list)

	local rows = {}
	local items = {}
	local offset = 0

	local function Refresh()
		local visible = math.min(#items, MAX_ROWS)
		list:SetHeight(visible * ROW_HEIGHT + 4)
		for i = 1, MAX_ROWS do
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
		local maxOffset = math.max(0, #items - MAX_ROWS)
		offset = math.max(0, math.min(maxOffset, offset - delta * 3))
		Refresh()
	end)

	-- Close when clicking anywhere else.
	list:SetScript("OnUpdate", function()
		if (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
			and not list:IsMouseOver() and not button:IsMouseOver() then
			list:Hide()
		end
	end)
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
				offset = math.max(0, math.min(i - 1, #items - MAX_ROWS))
				break
			end
		end
		Refresh()
		list:Show()
		openMenu = menu
	end

	button:HookScript("OnClick", function() menu:Toggle() end)
	return menu
end
