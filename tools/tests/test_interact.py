"""The map's interactions on the simulated client (docs/v1-plan.md M3.4: ui/Menus.lua, ui/ZoneInfo.lua, ui/Window.lua's
input), as the spike's (Core.lua:1161-1240, 1247-1416, 1698-1735; Layers.lua:1786-1811, 1996-2122; ZoneInfo.lua):

  test_picker: the title's click opens the map picker: Continents (300 tiles or more), Other maps, Instances by
    kind and the continent their entrance is on, a lone group's level skipped; a pick shows the map whole, following
    off; a drag of the title picks nothing (F4, S60).
  test_map_and_zone: /mm map alone lists the maps, by id or name shows one whole; an instance's map shown whole has
    no arrow, line to your waypoint, blips, borders or names (the exit's instance-map scenario); /mm zone flies to a zone (0.55 s, fit
    0.92, following off), with the spike's messages (F18).
  test_zone_hover: big (or off your map) with more than one zone in view, the zone under the cursor lit, its name
    and its border (S34, S36's hover); a click flies there in 0.55 s, following off; a quest's area isn't clickable
    while zone clicks are on offer, a pin still is (F17).
  test_modified_clicks: Ctrl-click a waypoint there, Ctrl-right-click none, Shift-click the /way line (the waypoint
    and way Commands, carried out by Game's handlers: M3.2's); none off the zones' maps, where the press is the
    map's (F35, F36).
  test_inspector: the right-click menu: Waypoint here, Clear waypoint (one set, wherever), Follow me as they apply; big, it leads with the
    zone, its subzone and coordinates, its levels against yours, how far (5 yd steps close, 10 further, thousands
    with commas) and which way from you, at most 2 quests whose areas hold the spot (F37, F38, S62).
"""
from test_addon import errors
from test_quest_areas import CANDLES_NEAR, HOGGER
from test_quests import FRONTIER, GOLD, client

SEP = "|cff808080  ·  |r".encode("utf-8").decode("latin-1")  # the inspector's (the sim's Lua strings: latin-1)


def items(d):
    return [(e.kind, e.text) for e in d["items"].values()]


def sub(d, text):
    return next(e for e in d["items"].values() if e.text == text)


def near(a, b, eps=1e-6):
    return all(abs(x - y) < eps for x, y in zip(a, b))


def sea(L, ns):
    """A spot in view on no zone's map."""
    return L.eval("""function(ns)
        local cam, w, h = ns.UI.Camera.cam, ns.UI.Window.Size()
        for x = 10, w - 10, 10 do
            for y = 10, h - 10, 10 do
                local col, row = ns.Atlas.Camera.ScreenToTile(cam, w, h, x, y)
                if not ns.Atlas.ZoneMapAt(ns.UI.Camera.inst, col, row) then return col, row end
            end
        end
    end""")(ns)


def cam(ns):
    c = ns.UI.Camera.cam
    return c.cx, c.cy, c.zoom


def fit(L, ns, r, margin):
    """Where Motion fits tile rect r at margin (atlas/Camera.lua)."""
    w, h = ns.UI.Window.Size()
    return L.eval("function(ns, r, w, h, m) return ns.Atlas.Camera.Fit(r.col0, r.row0, r.col1, r.row1, w, h, m, 16, 800) end")(
        ns, r, w, h, margin)


def test_picker():
    L, sim, ns, G = client([])
    hit, UI = ns.UI.Title.hit, ns.UI
    sim.FireScript(hit, "OnClick", "LeftButton", False)
    root = sim.menu
    assert items(root) == [("title", "Continents"), ("radio", "Eastern Kingdoms"), ("radio", "Kalimdor"),
                           ("button", "Other maps"), ("divider", None), ("title", "Instances"), ("button", "Dungeons"),
                           ("button", "Raids")]
    assert ("radio", "Azshara Crater") in items(sub(root, "Other maps"))
    dungeons = sub(root, "Dungeons")
    assert items(dungeons) == [("button", "Eastern Kingdoms"), ("button", "Kalimdor"), ("button", "Other")]
    assert items(sub(dungeons, "Eastern Kingdoms")) == [("radio", n) for n in ("Deadmines", "Scarlet Monastery",
                                                                               "Scholomance", "Shadowfang Keep", "Stratholme")]
    assert items(sub(sub(root, "Raids"), "Eastern Kingdoms")) == [("radio", "Blackwing Lair"), ("radio", "Zul'Gurub")]
    ek, kalimdor = sub(root, "Eastern Kingdoms"), sub(root, "Kalimdor")
    assert ek.isSelected() and not kalimdor.isSelected()
    # Picked: Kalimdor whole (its continent's rect at fit 1), following off.
    assert kalimdor.onSelect() == G.MenuResponse.Close
    sim.Run(0.5)
    r = ns.Atlas.MapRect(ns.Atlas.Continent(1))
    assert UI.Camera.inst == 1 and not UI.Camera.follow and near(cam(ns), fit(L, ns, r, 1.0))
    # The title dragged: the window moves, no menu.
    sim.menu = None
    for script in ("OnDragStart", "OnDragStop", "OnClick"):
        sim.FireScript(hit, script, "LeftButton", False)
    assert sim.menu is None
    sim.FireScript(hit, "OnClick", "LeftButton", False)
    assert sim.menu is not None and sub(sim.menu, "Kalimdor").isSelected()
    # Instances of one continent only: no continent level under their kind; no raids, no Raids.
    L.execute("""local ns = ...
        local maps = { { inst = 0, name = "Eastern Kingdoms" }, { inst = 33, name = "Shadowfang Keep", kind = "dungeon", continent = 0 },
            { inst = 36, name = "Deadmines", kind = "dungeon", continent = 0 } }
        ns.Atlas.Maps = function() return maps end""", ns)
    sim.FireScript(hit, "OnClick", "LeftButton", False)
    assert items(sim.menu) == [("title", "Continents"), ("radio", "Eastern Kingdoms"), ("divider", None),
                               ("title", "Instances"), ("button", "Dungeons")]
    assert items(sub(sim.menu, "Dungeons")) == [("radio", "Deadmines"), ("radio", "Shadowfang Keep")]
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_map_and_zone():
    L, sim, ns, G = client([], shown=False)
    UI, A = ns.UI, ns.Atlas

    def said():
        return sim.prints[len(sim.prints)]

    sim.Slash("/mm map")
    assert said().startswith("|cffffd100MagicMap|r: usage: /mm map <id|name>  (0=Eastern Kingdoms, 1=Kalimdor, "
                             "33=Shadowfang Keep, 36=Deadmines,")
    # By name, the window hidden: shown, Kalimdor whole.
    sim.Slash("/mm map kalimdor")
    sim.Run(1)
    assert UI.Window.frame.IsShown(UI.Window.frame) and UI.Camera.inst == 1 and not UI.Camera.follow
    # Back on you, a waypoint at Lakeshire: the line to it, the edge arrow where it leaves the view.
    UI.Motion.SetFollow(True)
    UI.Motion.SetZoom(96)
    L.execute("(...).Game.Command({ kind = 'waypoint', pos = { inst = 0, col = 36.09, row = 49.28 } })", ns)
    sim.Run(1)
    assert UI.Path.pieces > 0 and sim.state[UI.Path.edge].shown
    # An instance's map by id: its tiles whole; no arrow (you're not on it), line, blips, borders or names.
    sim.Slash("/mm map 36")
    sim.Run(2)
    c0, r0, c1, r1 = A.TileBounds(36)
    assert UI.Camera.inst == 36 and near(cam(ns), fit(L, ns, {"col0": c0, "row0": r0, "col1": c1, "row1": r1}, 1.0))
    live = {lay.name: sum(p.n for p in lay.front.pools.values()) if lay.front else 0
            for lay in UI.Engine.layers.values()}
    assert live.pop("tiles") > 0 and not any(live.values()), live
    assert not sim.state[UI.You.arrow].shown
    assert UI.Path.pieces == 0 and not sim.state[UI.Path.edge].shown
    # A zone by part of its name, the map shown's first, then by map: flown to.
    sim.Slash("/mm zone westf")
    westfall = next(z for z in A.Zones(0).values() if z.name == "Westfall")
    sim.Run(0.3)
    assert UI.Camera.inst == 0 and not near(cam(ns), fit(L, ns, westfall, 0.92))
    sim.Run(0.3)
    assert near(cam(ns), fit(L, ns, westfall, 0.92)) and not UI.Camera.follow
    # Off your map, not hovering: the title names the zone flown to, big too, till another map's shown
    # (Core.lua:1071, 1125, 1302).
    title = lambda: UI.Title.title.GetText(UI.Title.title)  # noqa: E731
    sim.cursorX, sim.cursorY = 100, 100
    sim.Slash("/mm map 0")
    sim.Slash("/mm map kalimdor")
    sim.Slash("/mm zone durotar")
    sim.Run(1)
    view = UI.Window.view
    assert UI.Camera.inst == 1 and not view.IsMouseOver(view) and title() == "Durotar"
    sim.Press("M")
    sim.Run(1)
    assert title() == "Durotar"
    sim.Slash("/mm map 0")
    sim.Run(0.2)
    sim.Slash("/mm map 1")
    sim.Run(0.2)
    assert title() == "Kalimdor"
    sim.Press("M")
    sim.Run(1)
    sim.Slash("/mm zone nowhere")
    assert said() == "|cffffd100MagicMap|r: no zone matching 'nowhere'"
    sim.Slash("/mm zone")
    assert said().startswith("|cffffd100MagicMap|r: /mm [toggle] | follow | map <id|name> | zone <name> |")
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_zone_hover():
    L, sim, ns, G = client([GOLD])
    UI, S, view = ns.UI, sim.state, ns.UI.Window.view
    L.execute("""local Sim, ns = ...
        -- The hovered zone's border on the borders' shown canvas (its Lines over theirs: sublevel 3); the
        -- zone names lit.
        function Lit()
            local c, n, lit = ns.UI.Borders.front, 0, {}
            for _, r in ipairs(Sim.state[c].regions) do
                if Sim.state[r].sublevel == 3 then
                    n = n + 1
                    Line = r
                end
            end
            local names = ns.UI.Labels.front.pools.label
            for i = 1, names.n do
                if names[i].color[4] == 1 then lit[#lit + 1] = names[i].text end
            end
            return n, table.concat(lit, ",")
        end""", sim, ns)
    sim.FireScript(view, "OnEnter", False)
    G.Over(32.6, 49.9)  # Elwynn, your map at the minimap's size: no zone to click
    sim.Run(0.3)
    assert G.Lit() == (0, "")
    sim.Press("M")
    sim.Run(1)
    z = UI.Camera.cam.zoom
    G.Over(32.6, 49.9)
    sim.Run(0.3)
    n, names = G.Lit()
    assert n > 10 and names == "ELWYNN FOREST"
    line = S[G.Line]
    assert list(line.color.values()) == [1, 0.84, 0.4, 0.95] and line.thickness == max(1.6, min(2.4, z / 100))
    assert line.sublevel == 3 and line.layer == "ARTWORK" and line.snap is False
    label = next(fs for fs in UI.Labels.front.pools.label.values() if getattr(fs, "text", None) == "ELWYNN FOREST")
    assert list(label.color.values()) == [1, 1, 0.9, 1]  # (its colour, as ui/Labels.lua keeps it)
    G.Over(35.9, 51.3)  # Deadwind Pass: Elwynn back as it was
    sim.Run(0.3)
    assert G.Lit()[1] == "DEADWIND PASS" and list(label.color.values()) == [1, 0.9, 0.7, 0.75]
    # Zoomed in on one zone's heart: nothing to click.
    G.Over(32.6, 49.9)
    sim.Run(0.3)
    UI.Motion.SetZoom(600)
    sim.Run(1)
    assert G.Lit() == (0, "")
    UI.Motion.SetZoom(z)
    sim.Run(1)

    # A click on Gold Dust's area (no pin under it): not the quest's, while zone clicks are on offer, but the zone's:
    # flown to, fit 0.92, in 0.55 s, following off. Held still, nothing lit (Core.lua:1323, 1349); the press's zone flown to.
    G.Over(32.15, 49.7)
    sim.Run(0.3)
    assert G.Lit()[1] == "ELWYNN FOREST"
    sim.buttonsDown["LeftButton"] = True
    sim.FireScript(view, "OnMouseDown", "LeftButton")
    sim.Run(0.2)
    assert G.Lit() == (0, "") and not UI.Motion.Dragging()
    sim.buttonsDown["LeftButton"] = None
    sim.FireScript(view, "OnMouseUp", "LeftButton")
    sim.Step()
    elwynn = ns.Atlas.MapRect(1429)
    sim.Run(0.4)
    assert not UI.Camera.follow and not near(cam(ns), fit(L, ns, elwynn, 0.92))
    sim.Run(0.2)
    assert near(cam(ns), fit(L, ns, elwynn, 0.92)) and sim.superTracked == 0
    # Its pin is still its quest's.
    G.Over(GOLD["col"], GOLD["row"])
    sim.Run(0.3)
    sim.Click(view, "LeftButton", sim.cursorX, sim.cursorY, "screen")
    sim.Run(0.2)
    assert sim.superTracked == 47 and near(cam(ns), fit(L, ns, elwynn, 0.92))
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_modified_clicks():
    L, sim, ns, G = client([])
    UI, mods, view, obs = ns.UI, sim.modifiers, ns.UI.Window.view, ns.Game.obs
    said = len(sim.prints)

    def click(button, col, row, key):
        mods[key] = True
        G.Over(col, row)
        sim.Click(view, button, sim.cursorX, sim.cursorY, "screen")  # (Game's input step carries it out)
        mods[key] = None

    before = cam(ns)
    click("LeftButton", 32.5, 49.6, "ctrl")
    w = obs.waypoint
    assert sim.waypoint.uiMapID == 1429 and w.inst == 0 and near((w.col, w.row), (32.5, 49.6), 1e-3)
    click("RightButton", 32.5, 49.6, "ctrl")
    assert sim.waypoint is None and obs.waypoint is False and sim.menu is None
    click("LeftButton", 31.0, 50.2, "shift")
    x, y = ns.Atlas.TileToMap(1429, 31.0, 50.2)
    way = sim.chat.split(" ")
    assert way[:3] == ["/way", "Elwynn", "Forest"] and near((float(way[3]), float(way[4])), (x * 100, y * 100), 0.1)
    sim.chat = None
    click("RightButton", 31.0, 50.2, "shift")
    assert sim.chat is None and sim.waypoint is None and sim.menu is None and cam(ns) == before and UI.Camera.follow
    # Off the zones' maps (the sea, further out): nothing taken, the press the map's.
    UI.Motion.SetZoom(30)
    sim.Run(0.5)
    col, row = sea(L, ns)
    click("LeftButton", col, row, "ctrl")
    assert sim.waypoint is None and len(sim.prints) == said
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_inspector():
    L, sim, ns, G = client([GOLD, HOGGER, CANDLES_NEAR, FRONTIER], followed=176)
    UI, view, obs = ns.UI, ns.UI.Window.view, ns.Game.obs
    # Every area and cell explored, as Game's sweep would hand them over (obs.explored, obs.exploredCells): line 2
    # names the spot's (test_world_layers: the explored and landmark lines).
    L.execute("local ns, all = ..., setmetatable({}, { __index = function() return true end })\n"
              "local rows = setmetatable({}, { __index = function() return all end })\n"
              "local cells = setmetatable({}, { __index = function() return rows end })\n"
              "ns.Game.Part('explored', function() return all end)\n"
              "ns.Game.Part('exploredCells', function() return cells end)", ns)

    def menu(col, row):
        G.Over(col, row)
        sim.Click(view, "RightButton", sim.cursorX, sim.cursorY, "screen")
        return items(sim.menu) if sim.menu else None

    # Small: the actions alone.
    assert menu(32.28, 49.65) == [("button", "Waypoint here")]
    sim.Press("M")
    sim.Run(1)
    gold, grey, white, dim = "|cffffd100", "|cffa8a8a8", "|cffffffff", "|cff808080"
    # In Gold Dust's area alone: Hogger's pin is in none (you follow Hogger; it isn't listed).
    lines = menu(32.28, 49.65)
    assert lines == [
        ("title", gold + "Elwynn Forest|r"),
        ("title", white + "Crystal Lake|r" + SEP + grey + "48.5, 63.7|r"),
        ("title", grey + "Level|r |cff40c0401-10|r" + SEP + white + "185 yd|r " + grey + "E of you|r"),
        ("title", grey + "Quest|r |cffffd100[7] Gold Dust Exchange|r"),
        ("title", grey + "Graveyard|r " + white + "Goldshire|r" + SEP + grey + "310 yd W|r"),  # (M4.1's places)
        ("divider", None), ("button", "Waypoint here")]
    # Quest areas off: no area drawn there (its parent off: Layers.lua:82-87, 2297).
    UI.Engine.SetLayer("questAreas", False)
    sim.Run(0.5)
    assert [t for _, t in menu(32.28, 49.65) if t and "Quest|r" in t] == []
    UI.Engine.SetLayer("questAreas", True)
    sim.Run(1)
    assert len([t for _, t in menu(32.28, 49.65) if t and "Quest|r" in t]) == 1
    # How far: 5 yd steps close by, 10 further out, thousands apart; here: "You're here".
    assert menu(32.45, 49.75)[2][1].endswith(white + "270 yd|r " + grey + "E of you|r")
    assert menu(34.95, 49.75)[2][1].endswith(white + "1,600 yd|r " + grey + "E of you|r")
    assert menu(31.9, 49.7)[2][1].endswith(white + "40 yd|r " + grey + "NW of you|r")
    assert menu(31.95, 49.75)[2][1].endswith(grey + "You're here|r")
    # Westfall, its levels above yours (8): red.
    assert menu(29.0, 50.5)[2][1].startswith(grey + "Level|r |cffff60409-18|r")
    # Waypoint here: the game's waypoint at the spot (the waypoint Command, Game's handler).
    menu(32.5, 49.6)
    sub(sim.menu, "Waypoint here").onSelect()
    sim.Step()  # (carried out in Game's input step)
    w = obs.waypoint
    assert sim.waypoint.uiMapID == 1429 and near((w.col, w.row), (32.5, 49.6), 1e-3)
    # A waypoint known (Model's): Clear waypoint; not following: Follow me, which flies back to you.
    UI.Motion.SetFollow(False)
    lines = menu(32.5, 49.6)
    assert lines[-3:] == [("button", "Waypoint here"), ("button", "Clear waypoint"), ("button", "Follow me")]
    sub(sim.menu, "Clear waypoint").onSelect()
    sim.Step()
    assert sim.waypoint is None and obs.waypoint is False and len(ns.Model.Known("waypoint")[0]) == 0
    assert ("button", "Clear waypoint") not in menu(32.5, 49.6)
    # One on a map Atlas hasn't (a mine's own): no pin, but Clear waypoint (Layers.lua:2080-2081).
    sim.waypoint = L.eval("UiMapPoint.CreateFromCoordinates")(1601, 0.5, 0.5)
    sim.FireEvent("USER_WAYPOINT_UPDATED")
    sim.Step()
    assert obs.waypoint is False and ("button", "Clear waypoint") in menu(32.5, 49.6)
    sub(sim.menu, "Clear waypoint").onSelect()
    sim.Step()
    assert sim.waypoint is None and ("button", "Clear waypoint") not in menu(32.5, 49.6)
    menu(32.5, 49.6)
    sub(sim.menu, "Follow me").onSelect()
    sim.Run(0.7)
    assert UI.Camera.follow
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
