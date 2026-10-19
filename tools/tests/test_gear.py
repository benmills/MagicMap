"""The gear menu on the simulated client (ui/Menus.lua), as the spike's (GearMenu.lua, Layers.lua:30-71,
2154-2207): a submenu per group of layers with any (Map, Quests, Places, People, Other addons so far), each layer
a checkbox with its tip (white title, gold body) that keeps the menu open, a sub-option indented and
greyed while its parent is off; Tracking; a divider; then Settings: Map (Colour-matched tiles), Minimap
(Minimap button, Reset position, Use Blizzard's minimap), Advanced (Diagnostics, Performance), the same small
and big. Every row works: a layer's toggle empties and redraws what it draws (and View.layers, for Game's: the
blip sensor, Questie's borrowed pins) and is saved, the changed keys only, across a /reload; a layer off by
default stays so until turned on; rows in the spike's order whenever added; each setting does what it says;
a tracking type's box and Advanced's rows send Game their Commands (test_gear_tracking_advanced); /mma layers."""
from test_addon import boot, errors
from test_blips import lua_tools, put_blips, stub_services
from sim import TEST_UI

LAYERS = {"Zone labels": "labels", "Zone borders": "borders", "Quests": "quests", "Quest areas": "questAreas",
          "Quests to pick up": "offers", "Minimap blips": "blips", "Rares you've seen": "rares"}
SETTINGS = [("title", "Map"), ("checkbox", "Colour-matched tiles"), ("divider", None), ("title", "Minimap"),
            ("checkbox", "Minimap button"), ("button", "Reset position"), ("button", "Use Blizzard's minimap"),
            ("divider", None), ("button", "Advanced")]
ADVANCED = [("title", "Diagnostics"), ("checkbox", "Debug info in the title"), ("checkbox", "Indoor maps"),
            ("divider", None), ("title", "Performance"), ("checkbox", "Record 10 seconds"),
            ("button", "Compare with other addons"), ("button", "Memory breakdown")]
WHITE, GOLD = (1, 1, 1), (1, 0.82, 0)
SEEN = ("MagicMapAtlasDB.Model = MagicMapAtlasDB.Model or { _v = 1, blips = {}, rares = { [0] = { ['npc:1'] = "
        "{ name = 'Rare', npcID = 1, col = 31.97, row = 49.74, t = 1792077412 } } } }")  # a rare you've seen
ICON = "Interface\\Icons\\INV_Misc_Map_01"  # Game's minimap button (game/Button.lua)


def shown(saved=None):
    """The map shown over one of each layer's things near you: a mailbox blip, a rare you've seen (Model's
    saved part), Questie's pin in Elwynn. (L, sim, ns, the pin)."""
    L, sim, ns = boot((saved or TEST_UI) + "\n" + SEEN)
    G = L.globals()
    stub_services(L, ns)
    put_blips(L, sim, ns, [("Mailbox", 40, 20)])
    q = sim.LoadQuestie()
    sim.FireEvent("ADDON_LOADED", "Questie")
    pin = sim.QuestieIcon()
    q.AddWorldMapIconMap(q, G.Questie, pin, 1429, 0.5, 0.5, G.HBD_PINS_WORLDMAP_SHOW_WORLD)
    sim.Slash("/mma toggle")
    sim.Run(3)
    return L, sim, ns, pin


def layer(ns, name):
    return next(lay for lay in ns.UI.Engine.layers.values() if lay.name == name)


def drawn(lay):
    """The regions a layer shows: its front canvas's, at alpha 1."""
    c = lay.front
    return sum(p.n for p in c.pools.values()) if c and c.alpha == 1 else 0


def gear(sim, ns):
    """Click the gear: the menu's root, and its rows by text."""
    sim.Click(ns.UI.Controls.gear)
    return sim.menu, {e.text: e for e in sim.MenuItems().values() if e.text}


def items(d):
    return [(e.kind, e.text) for e in d["items"].values()]


def sub(root, title):
    return next(e for e in root["items"].values() if e.text == title)


def tip(L, row):
    """The lines a row's tooltip writes: (text, r, g, b)."""
    t = L.eval("""function(fn)
        local t = { lines = {} }
        function t:SetText(s, r, g, b) self.lines[#self.lines + 1] = { s, r, g, b } end
        function t:AddLine(s, r, g, b) self.lines[#self.lines + 1] = { s, r, g, b } end
        fn(t)
        return t.lines
    end""")(row.tooltip)
    return [tuple(line.values()) for line in t.values()]


def hosted(L, pin, ns):
    """Questie's pin on Game's holder, on the world socket."""
    return L.eval("function(pin, socket) return pin:GetParent():GetParent() == socket end")(pin, ns.UI.Sockets.world.frame)


def rim_button(L, sim):
    return L.eval("""function(Sim, icon)
        for _, f in ipairs(Sim.Frames()) do
            for _, r in ipairs({ f:GetRegions() }) do
                if r.GetTexture and r:GetTexture() == icon then return f end
            end
        end
    end""")(sim, ICON)


def test_gear():
    L, sim, ns, pin = shown()
    G, UI, Game = L.globals(), ns.UI, ns.Game
    view, saved, f = UI.View(), G.MagicMapAtlasDB.UI, UI.Window.frame
    refresh, same = G.MenuResponse.Refresh, L.eval("function(a, b) return a == b end")

    # The tree: a submenu per group with layers, a divider, Settings; small and big alike.
    root, rows = gear(sim, ns)
    assert items(root) == [("button", "Map"), ("button", "Quests"), ("button", "Places"), ("button", "People"),
                           ("button", "You"), ("button", "Other addons"), ("button", "Tracking"), ("divider", None),
                           ("button", "Settings")]
    assert items(sub(root, "Map")) == [("checkbox", "Zone labels"), ("checkbox", "Zone borders"),
                                       ("checkbox", "Shade unexplored")]
    assert items(sub(root, "Quests")) == [("checkbox", "Quests"), ("checkbox", "Quest areas"),
                                          ("checkbox", "     Estimate missing areas"), ("checkbox", "Quests to pick up")]
    assert items(sub(root, "Places")) == [("checkbox", "Flight points"), ("checkbox", "Dungeon entrances"),
                                          ("checkbox", "Graveyards"), ("checkbox", "Points of interest"),
                                          ("checkbox", "Minimap blips")]
    assert items(sub(root, "People")) == [("checkbox", "Party & raid"), ("checkbox", "Rares you've seen"),
                                          ("checkbox", "Live rares & treasures")]
    assert items(sub(root, "You")) == [("checkbox", "Corpse"), ("checkbox", "Waypoint")]
    assert items(sub(root, "Other addons")) == [("checkbox", "Questie")]  # (GatherMate2's minimap pins only: none)
    assert items(sub(root, "Settings")) == SETTINGS and items(sub(sub(root, "Settings"), "Advanced")) == ADVANCED
    sim.Press("M")
    sim.Run(1)
    big, _ = gear(sim, ns)
    assert items(big) == items(root) and items(sub(big, "Settings")) == SETTINGS
    sim.Press("M")
    sim.Run(1)

    # Tips: white title, gold body.
    assert tip(L, rows["Zone labels"]) == [("Zone labels",) + WHITE, ("Names of zones and sub-zones.",) + GOLD]
    assert tip(L, rows["Questie"]) == [("Questie",) + WHITE,
                                       ("Map pins Questie puts on the world map, shown here too.",) + GOLD]
    assert tip(L, rows["Colour-matched tiles"])[0] == ("Colour-matched tiles",) + WHITE

    # Each layer: on, its things drawn; off, gone from the next frame (the menu stays open); on, back.
    root, rows = gear(sim, ns)
    assert view.layers.blips and Game.minimap.sensor and view.layers["addon:Questie"] and hosted(L, pin, ns)
    for text, name in LAYERS.items():
        lay, row = layer(ns, name), rows[text]
        assert row.isSelected() is True and drawn(lay) > 0, name
        assert row.onSelect() == refresh
        sim.Step()
        assert row.isSelected() is False and drawn(lay) == 0 and saved.layers[name] is False, name
        if name == "blips":
            assert view.layers.blips is None and not Game.minimap.sensor
        assert row.onSelect() == refresh
        sim.Run(1)
        assert row.isSelected() is True and drawn(lay) > 0 and saved.layers[name] is None, name
    assert view.layers.blips and Game.minimap.sensor

    # Questie's pins: given back while its layer's off, borrowed again when on.
    row, frame = rows["Questie"], view.frame
    assert row.onSelect() == refresh
    sim.Step()  # View.layers from the next frame, View.frame with it (types/view.lua)
    assert view.layers["addon:Questie"] is None and view.frame > frame
    # The world socket's zoom, set in place: View.frame stamped the frame it lands (Game re-places its pins
    # then); and the window's `still` (the blip sensor's) the frame it flips.
    world, zoom = view.sockets.world, view.sockets.world.zoom
    ns.UI.Motion.ZoomStep(1)
    while world.zoom == zoom:
        frame = view.frame
        sim.Step()
    assert view.frame == ns.Runtime.frames and view.frame > frame
    sim.Run(0.5)
    UI.Window.frame.ClearAllPoints(UI.Window.frame)
    UI.Window.frame.SetPoint(UI.Window.frame, "TOPLEFT", G.UIParent, "TOPLEFT", 50, -50)
    sim.Step()
    assert not view.window.still
    frame = view.frame
    sim.Step()
    assert view.window.still and view.frame > frame
    sim.Run(1.1)
    assert not hosted(L, pin, ns) and row.isSelected() is False
    row.onSelect()
    sim.Run(1.1)
    assert hosted(L, pin, ns) and row.isSelected() is True

    # A sub-option (a later package's row): indented, clickable only while its parent is on.
    UI.Menus.Layer(L.table_from({"key": "child", "label": "Sub-option", "group": "map", "parent": "labels",
                                 "tip": "A sub-option."}))
    root, rows = gear(sim, ns)
    child = rows["     Sub-option"]
    assert items(sub(root, "Map"))[-1] == ("checkbox", "     Sub-option") and child.IsEnabled(child)
    rows["Zone labels"].onSelect()
    assert not child.IsEnabled(child)

    # A layer off by default (ui/Shade.lua's: the spike's Shade unexplored, Layers.lua:37): in the spike's
    # place in its group, before a row added after it, off until turned on, saved only while it isn't.
    root, rows = gear(sim, ns)
    assert [t for _, t in items(sub(root, "Map"))] == ["Zone labels", "Zone borders", "Shade unexplored",
                                                       "     Sub-option"]
    shade = rows["Shade unexplored"]
    assert shade.isSelected() is False and saved.layers["unexplored"] is None
    shade.onSelect()
    assert shade.isSelected() is True and saved.layers["unexplored"] is True
    shade.onSelect()
    assert shade.isSelected() is False and saved.layers["unexplored"] is None

    # Settings. Colour-matched tiles: the tiles laid out again, plain.
    tiles = layer(ns, "tiles")
    front = tiles.front
    assert rows["Colour-matched tiles"].isSelected() is True and rows["Colour-matched tiles"].onSelect() == refresh
    sim.Run(1)
    assert saved.tint is False and not same(tiles.front, front) and rows["Colour-matched tiles"].isSelected() is False
    # Minimap button: Game's button hidden, and shown again.
    button = rim_button(L, sim)
    assert button.IsShown(button)
    assert rows["Minimap button"].onSelect() == refresh
    sim.Step()
    assert saved.button is False and view.button is False and not button.IsShown(button)
    rows["Minimap button"].onSelect()
    sim.Step()
    assert saved.button and button.IsShown(button)
    # Reset position: back on the minimap's spot, following (a button: the menu closes, the client's default).
    UI.Motion.SetFollow(False)
    home = UI.BigMap.home
    assert (f.GetLeft(f), f.GetTop(f)) != (home.left, home.top)
    assert rows["Reset position"].onSelect() is None
    sim.Step()
    assert (f.GetLeft(f), f.GetTop(f), f.GetWidth(f), f.GetHeight(f)) == (home.left, home.top, home.w, home.h)
    assert UI.Camera.follow
    # Use Blizzard's minimap: ours hidden, the Minimap Blizzard's again, the button on it.
    _, rows = gear(sim, ns)
    assert rows["Use Blizzard's minimap"].onSelect() is None
    sim.Step()
    assert not f.IsShown(f) and saved.shown is False and not Game.minimap.engaged and button.IsVisible(button)
    sim.Slash("/mma toggle")
    sim.Run(1)
    _, rows = gear(sim, ns)
    rows["Minimap button"].onSelect()
    rows["Questie"].onSelect()
    sim.Slash("/mma toggle")
    sim.Step()
    perf = ns.Runtime.Perf()[0]["map: gear pick"]
    assert perf.n == 26 and perf.over == 0, (perf.n, perf.max)
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))

    # /reload: the changed keys only (borders and the rest went off and on again, from the gear or
    # /mma layer), each still in effect.
    sim.Slash("/mma layer borders")
    sim.Slash("/mma layer borders")
    sim.FireEvent("PLAYER_LOGOUT")
    assert dict(saved.layers.items()) == {"labels": False, "addon:Questie": False}
    L, sim, ns, pin = shown("MagicMapAtlasDB = " + lua_tools(L).Dump(G.MagicMapAtlasDB))
    saved, view = L.globals().MagicMapAtlasDB.UI, ns.UI.View()
    assert dict(saved.layers.items()) == {"labels": False, "addon:Questie": False}
    assert saved.tint is False and saved.button is False and view.button is False
    assert drawn(layer(ns, "labels")) == 0 and drawn(layer(ns, "borders")) > 0
    assert view.layers["addon:Questie"] is None and not hosted(L, pin, ns)
    _, rows = gear(sim, ns)
    assert [rows[t].isSelected() for t in ("Zone labels", "Zone borders", "Questie", "Colour-matched tiles",
                                           "Minimap button")] == [False, True, False, False, False]
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


# Stubbed as typed (wave 4a's, beside this one): obs.tracking as M4.1's part hands it (types/observation.lua
# MM.ObsTracking: a new table on change) and its tracking Command carried out on it; the run Command (/mma
# <line>, as typed) recorded, flipping its owners' states: UI's saved debug, Game's indoor reports
# (obs.minimap), Runtime's recording.
STUBS = """function(ns, sent, ran)
    local cur = {
        { id = 8, name = "Flight Master", texture = 136456, active = true, kind = "duplicate" },
        { id = 2383, name = "Find Herbs", texture = 136456, active = true },
        { id = 65536, name = "Track Quest POIs", texture = 136456, active = true, kind = "duplicate" },
        { id = 8192, name = "Points of Interest", texture = 136456, active = false, kind = "duplicate" },
        { id = 64, name = "Mailbox", texture = 136459, active = true },
        { id = 128, name = "Innkeeper", texture = 136458, active = true },
    }
    ns.Game.Part("tracking", function() return cur end)
    ns.Game.Handle("tracking", function(c)
        sent[#sent + 1] = c
        local new = {}
        for i, t in ipairs(cur) do
            new[i] = { id = t.id, name = t.name, texture = t.texture, kind = t.kind, active = t.active }
            if t.id == c.id then new[i].active = c.on end
        end
        cur = new
    end)
    ns.Game.Handle("run", function(c)
        ran[#ran + 1] = c.line
        local g = ns.Game.saved
        if c.line == "debug" then ns.UI.saved.debug = not ns.UI.saved.debug end
        if c.line == "indoor" then g.indoorDebug = not g.indoorDebug or nil end -- (game/Renderer.lua's)
        if c.line == "perf" then ns.Runtime.recording = not ns.Runtime.recording end
    end)
end"""


def test_gear_tracking_advanced():
    """Tracking (GearMenu.lua:9-26): Blizzard's types but those ours replace, each a box that sends Game the
    tracking Command and shows the click till Game's next Observation says so. Settings > Advanced
    (GearMenu.lua:33-46): each row runs its /mma command, a box showing its command's state. /mma layers
    (Layers.lua:2196-2207): each group's layers, on green, off grey, a sub-option grey while its parent's off."""
    L, sim, ns = boot()
    refresh, sent, ran = L.globals().MenuResponse.Refresh, L.table(), L.table()
    L.eval(STUBS)(ns, sent, ran)
    sim.Slash("/mma toggle")
    sim.Run(1)

    # Tracking: the client's order, the duplicates (flight, quest POIs, POIs) left out.
    root, rows = gear(sim, ns)
    assert items(sub(root, "Tracking")) == [("checkbox", "Find Herbs"), ("checkbox", "Mailbox"),
                                            ("checkbox", "Innkeeper")]
    mail = rows["Mailbox"]
    assert mail.isSelected() is True and mail.onSelect() == refresh
    assert mail.isSelected() is False and len(sent) == 0  # the click shown; Game's in its next input step
    sim.Step()
    assert [(c.kind, c.id, c.on) for c in sent.values()] == [("tracking", 64, False)]
    assert ns.Model.tracking[5].active is False and mail.isSelected() is False
    mail.onSelect()
    mail.onSelect()  # twice before Game's step: both sent, in order, the box as the last asked
    assert mail.isSelected() is False
    sim.Step()
    assert [c.on for c in sent.values()] == [False, True, False] and mail.isSelected() is False
    assert rows["Find Herbs"].isSelected() is True and rows["Innkeeper"].isSelected() is True

    # Advanced: each row its /mma command; a box shows the click, then its state.
    adv = {e.text: e for e in sub(sub(root, "Settings"), "Advanced")["items"].values() if e.text}
    assert tip(L, adv["Debug info in the title"]) == [
        ("Debug info in the title",) + WHITE, ("Tile, zoom and layout timings next to the zone name.",) + GOLD]
    assert tip(L, adv["Indoor maps"])[1][0].startswith("Says in chat which map you're on indoors")
    assert tip(L, adv["Record 10 seconds"])[1][0] == "Times every part of MagicMap while you play, then prints a summary."
    for text in ("Debug info in the title", "Indoor maps", "Record 10 seconds"):
        row = adv[text]
        assert row.isSelected() is False and row.onSelect() == refresh and row.isSelected() is True, text
        sim.Step()
        assert row.isSelected() is True, text
    assert ns.UI.saved.debug and ns.Model.minimap.indoorDebug and ns.Runtime.recording
    ns.Runtime.recording = False  # its 10 seconds up
    assert adv["Record 10 seconds"].isSelected() is False
    assert adv["Compare with other addons"].onSelect() is None and adv["Memory breakdown"].onSelect() is None
    sim.Step()
    assert list(ran.values()) == ["debug", "indoor", "perf", "perf top", "perf mem"]

    # /mma layers.
    sim.Slash("/mma layer questAreas")
    sim.Slash("/mma layer rares")
    sim.Slash("/mma layers")
    on, off = "|cff33ff33%s|r".__mod__, "|cff888888%s|r".__mod__
    assert sim.prints[len(sim.prints)] == (
        "|cffffd100MagicMapAtlas|r: layers: "
        f"|cffffd100Map:|r {on('zoneLabels')}, {on('zoneBorders')}, {off('unexplored')}; "
        f"|cffffd100Quests:|r {on('quests')}, {off('questAreas')}, {off('questAreasApprox')}, {on('offers')}; "
        f"|cffffd100Places:|r {on('flight')}, {on('dungeons')}, {off('graveyards')}, {on('areaPOIs')}, {on('blips')}; "
        f"|cffffd100People:|r {on('group')}, {off('rares')}, {on('vignettes')}; "
        f"|cffffd100You:|r {on('corpse')}, {on('waypoint')}. Toggle them from the gear. "
        "Shift-click: /way at cursor. Ctrl-click: set waypoint. Ctrl-right-click: clear it.")
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
