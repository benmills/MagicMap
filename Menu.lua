-- Menus are the client's own (MenuUtil). Opened through here, they count as
-- open for the controls that opened them, so those don't fade out under them.

local ADDON, ns = ...

local clientMenu -- the last menu opened

function ns.IsMenuOpen()
	return clientMenu ~= nil and clientMenu:IsShown()
end

function ns.OpenClientMenu(owner, generator)
	clientMenu = MenuUtil.CreateContextMenu(owner, generator)
	return clientMenu
end
