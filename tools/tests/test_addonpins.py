"""Other addons' HereBeDragons pins on our map, on the sim (docs/v1-plan.md M4.2, game/AddonPins.lua):
world pins past 48 px a tile only those flagged for continents, none drawn for the library's own map
alone (-1) or bigger than 128 px, none of Questie's turn-ins our quests layer shows; minimap pins on a
host of Game's on the minimap socket, centred on you at the Minimap's view, each where the library
puts it, so on its spot on our map, out of sight under Rotate Minimap, off your map and for a renamed
copy whose world pins we host, back on the Minimap at release.
Game reads UI's View: its sockets (ui/Sockets.lua) and layers. The world pins' round trip and Questie's scale: replays/R-G6.lua, R-G6b.lua; the hidden host
while there's no minimap socket: R-G6c.lua."""
from test_addon import boot, errors

# Questie's world pins in Elwynn: (Type, Id, flag, size px).
PINS = {"world": ("available", 70, 3, 16), "continent": ("available", 71, 2, 16), "parent": ("available", 72, 1, 16),
        "zone": ("available", 73, 0, 16), "own": ("available", 74, -1, 16), "big": ("available", 75, 3, 129),
        "128": ("available", 76, 3, 128), "turnIn": ("complete", 62, 3, 16), "notDone": ("complete", 60, 3, 16),
        "offer": ("available", 62, 3, 16)}


def world_pins(L, sim, q):
    icons = {}
    for i, (name, (kind, qid, flag, px)) in enumerate(PINS.items()):
        icon = sim.QuestieIcon(L.table_from({"Type": kind, "Id": qid}))
        icon.SetSize(icon, px, px)
        q.AddWorldMapIconMap(q, L.globals().Questie, icon, 1429, 0.3 + 0.02 * i, 0.5, flag)
        icons[name] = icon
    return icons


def hosted(L, icons, canvas):
    same = L.eval("rawequal")
    return sorted(n for n, icon in icons.items() if same(icon.GetParent(icon).GetParent(icon.GetParent(icon)), canvas))


def test_world_pins():
    """The show rules: at 96 px a tile all but the library's own map's, the frame bigger than a pin and
    the turn-in our quests layer shows; zoomed out past 48, the continent's alone; the quests layer off,
    Questie's turn-in again."""
    L, sim, ns = boot()
    sim.Slash("/mm toggle")
    sim.Run(3)
    q = sim.LoadQuestie()
    sim.FireEvent("ADDON_LOADED", "Questie")
    view = ns.UI.View()
    icons = world_pins(L, sim, q)
    canvas = view.sockets.world.frame
    sim.Run(0.5)
    assert ns.Game.obs.quests[2].id == 62 and ns.Game.obs.quests[2].complete
    assert hosted(L, icons, canvas) == ["128", "continent", "notDone", "offer", "parent", "world", "zone"]

    ns.UI.Motion.SetZoom(40)  # a continent's
    sim.Step()
    sim.Step()
    assert view.sockets.world.zoom == 40
    sim.Run(0.5)
    assert hosted(L, icons, canvas) == ["128", "continent", "notDone", "offer", "world"]
    ns.UI.Motion.SetZoom(48)
    sim.Run(0.5)
    assert hosted(L, icons, canvas) == ["128", "continent", "notDone", "offer", "parent", "world", "zone"]

    ns.UI.Engine.SetLayer("quests", False)  # ours off: Questie's turn-in is the one shown, by the next regular pass
    sim.Run(1.1)
    assert "turnIn" in hosted(L, icons, canvas)
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_minimap_pins():
    """GatherMate's herb (the shared copy) and Questie's (renamed) minimap pins through every host."""
    L, sim, ns = boot()
    sim.Slash("/mm toggle")
    sim.Run(3)
    q = sim.LoadQuestie()
    sim.FireEvent("ADDON_LOADED", "Questie")
    socket = ns.UI.View().sockets.minimap
    G, same = L.globals(), L.eval("rawequal")
    quest = sim.QuestieIcon(L.table_from({"Type": "available", "Id": 70}))
    q.AddMinimapIconMap(q, G.Questie, quest, 1429, 0.29, 0.56)
    world = sim.QuestieIcon(L.table_from({"Type": "available", "Id": 70}))  # its world pin: we host it
    q.AddWorldMapIconMap(q, G.Questie, world, 1429, 0.29, 0.56, 3)
    herb, frame, Atlas = sim.gatherPin, socket.frame, ns.Atlas
    sim.Run(0.5)
    host = herb.GetParent(herb)

    def spot(pin):  # its centre in the socket frame's units, from its TOPLEFT
        x, y = pin.GetCenter(pin)
        return x - frame.GetLeft(frame), y - frame.GetTop(frame)

    # Around you on the socket at the Minimap's view, the herb where our map has its spot.
    you = ns.Model.you
    z = socket.zoom
    hx, hy = spot(host)
    assert same(host.GetParent(host), frame) and herb.IsVisible(herb)
    assert abs(hx - you.col * z) < 1e-6 and abs(hy + you.row * z) < 1e-6
    assert host.GetWidth(host) == int(2 * G.C_Minimap.GetViewRadius() / Atlas.TILE_YARDS * z + 0.5)
    m = sim.maps[1429]  # the sim's Elwynn, where it put the herb
    col, row = m[5] + (m[7] - m[5]) * 0.297, m[6] + (m[8] - m[6]) * 0.546
    x, y = spot(herb)
    print(f"the herb {x - col * z:.2f}, {y + row * z:.2f} px off its spot at {z} px a tile")
    assert abs(x - col * z) < 0.6 and abs(y + row * z) < 0.6
    assert host.GetZoom(host) == G.Minimap.GetZoom(G.Minimap) and herb.GetFrameLevel(herb) > host.GetFrameLevel(host)

    # Questie's: its world pins hosted, they'd repeat them; its layer off, around you too.
    assert not same(quest.GetParent(quest), host) and not quest.IsVisible(quest)
    ns.UI.Engine.SetLayer("addon:Questie", False)
    sim.Step()
    assert same(quest.GetParent(quest), host) and quest.IsVisible(quest)

    # Rotate Minimap: the library turns them with your facing, our map doesn't: out of sight.
    sim.cvars.rotateMinimap = "1"
    sim.Step()
    assert not herb.IsVisible(herb) and not quest.IsVisible(quest)
    sim.cvars.rotateMinimap = "0"
    sim.Step()
    assert same(herb.GetParent(herb), host) and herb.IsVisible(herb)

    # The map shown isn't yours: they're around you, not on it.
    sim.Slash("/mm map 36")
    sim.Run(0.5)
    assert socket.inst == 36 and same(herb.GetParent(herb), host) and not herb.IsVisible(herb)
    sim.Slash("/mm follow")
    sim.Run(0.5)
    assert socket.inst == 0 and herb.IsVisible(herb)

    mm = G.Minimap

    sim.Slash("/mm toggle")  # released: back on the Minimap (at its home), placed there again
    sim.Step()
    assert not ns.Game.minimap.engaged and same(q.Minimap, mm) and same(sim.hbdPins.Minimap, mm)
    assert same(herb.GetParent(herb), mm) and herb.IsVisible(herb) and not host.IsShown(host)
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
