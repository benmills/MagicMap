"""In combat the client refuses an addon's code some calls on any frame (SetPassThroughButtons: Blizzard's map canvas
makes it on every pin it hands out, pin addons on their own pins) and blames the addon whose code began the call
chain: the "MagicMap has been blocked from an action only available to the Blizzard UI" prompt. So in combat MagicMap
runs none of another addon's code, nor Blizzard's map: other addons' pins are neither borrowed nor given back, their
pin library isn't moved to another host, a click from our AddOns menu and the quest log both wait; all of it done as
combat ends. The pins already on the map stay, placed at each new zoom."""
from test_addon import boot, errors

# Another addon, as a scenario's own code (not MagicMap's call chain: what it does itself is its to answer for):
# Lib(tag) its renamed copy of the pin library, which sets each minimap pin up again on a new host (SetMinimapObject);
# Pin() one of its icons, set up each time it's shown; its button on the Minimap's rim, set up at each click. A setup
# is the call the client refuses in combat; .setups and .clicks count them.
OTHER = """function()
    local other = { setups = 0, clicks = 0 }
    local function Setup(frame)
        frame:SetPassThroughButtons("RightButton")
        other.setups = other.setups + 1
    end
    function other.Lib(tag)
        local lib = Sim.HBDPins("HereBeDragons" .. tag .. "-Pins-2.0")
        local set = lib.SetMinimapObject
        function lib:SetMinimapObject(host)
            set(self, host)
            for icon in pairs(self.minimapPins) do Setup(icon) end
        end
        return lib
    end
    function other.Pin()
        local icon = CreateFrame("Button", nil, UIParent)
        icon:SetSize(16, 16)
        icon:Hide()
        icon:SetScript("OnShow", Setup)
        return icon
    end
    other.button = Sim.RimButton("PassPinsMinimapButton", "PassPins")
    other.button:SetScript("OnClick", function(self)
        Setup(self)
        other.clicks = other.clicks + 1
    end)
    return other
end"""


def test_combat_runs_no_one_elses_code():
    L, sim, ns = boot()
    sim.Slash("/mm toggle")
    ns.UI.Window.frame.SetSize(ns.UI.Window.frame, 300, 300)
    sim.Run(3)
    other, same = L.eval(OTHER)(), L.eval("rawequal")
    world, mini = other.Lib("PassPins"), other.Lib("PassMini")
    sim.FireEvent("ADDON_LOADED", "PassPins")
    view = ns.UI.View()
    canvas = view.sockets.world.frame

    def hosted(icon):
        holder = icon.GetParent(icon)
        return same(holder.GetParent(holder), canvas) and icon.IsVisible(icon)

    def blocked():
        return [c.call for c in sim.protectedCalls.values()]

    def said(text):
        return any(text in str(line) for line in sim.prints.values())

    def fight(on):
        sim.inCombat = on
        sim.FireEvent("PLAYER_REGEN_DISABLED" if on else "PLAYER_REGEN_ENABLED")

    first, herb = other.Pin(), other.Pin()
    world.AddWorldMapIconMap(world, "PassPins", first, 1429, 0.30, 0.5, 3)
    mini.AddMinimapIconMap(mini, "PassMini", herb, 1429, 0.297, 0.546)
    sim.Run(3.5)  # (borrowed; the rim's buttons are looked for every 3 s)
    host = herb.GetParent(herb)
    assert hosted(first) and same(host.GetParent(host), view.sockets.minimap.frame) and herb.IsVisible(herb)

    # A fight with the small map shown: the addon adds a pin, the map zooms (its minimap pins' host is sized anew each
    # frame of the glide: the library would be told again), and its button is clicked from our AddOns menu.
    fight(True)
    setups, x = other.setups, first.GetCenter(first)
    second = other.Pin()
    world.AddWorldMapIconMap(world, "PassPins", second, 1429, 0.32, 0.5, 3)
    ns.UI.Motion.SetZoom(64)
    ns.UI.Menus.AddOns(ns.UI.Controls.addons)
    sim.Step()
    row = next(e for e in sim.MenuItems("button").values() if "PassPins" in e.text)
    row.onSelect()
    sim.Run(2.5)
    assert blocked() == [], blocked()
    assert other.setups == setups and other.clicks == 0
    assert hosted(first) and first.GetCenter(first) != x and not hosted(second)  # (the one hosted: at the new zoom)
    assert said("PassPins: clicked when combat ends")
    fight(False)
    sim.Run(1.5)
    assert hosted(second) and other.clicks == 1 and other.setups >= setups + 3  # (the pin, the library, the click)

    # The quest log from a quest pin's popup is Blizzard's map, opened by our code: its canvas would set up every pin.
    fight(True)
    ns.Game.Command(L.table_from({"kind": "questlog", "quest": 62}))
    sim.Run(0.5)
    frame = L.globals().WorldMapFrame
    assert blocked() == [], blocked()
    assert not frame.IsShown(frame) and said("the quest log opens when combat ends")
    fight(False)
    sim.Run(0.5)
    assert frame.IsShown(frame) and blocked() == []
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
