"""The pin store (ui/Pins.lua) on the simulated client: one store diffed by id (200 pins, one changed:
that pin alone re-set; the rev bumped with nothing changed, or left as it is: none); StylePin's forms
(a)-(d) and count; a pin's tooltip (built once a hover, its lines small and grey, hidden off it with
its fonts back), a click on it (its popup), and a drag over it panning the map; the pin inventory (Settings > Pins: every type a
row and Blizzard's art) and its choices on the map and in a group's pill."""
import os

from sim import TESTS
from test_addon import boot, errors

ROOT = os.path.join(TESTS, "..", "..")

# A test kind's layer: n pins about the view's centre (Known-shaped), each its look; t.rev its rev.
LAYER = """function(Pins, n, cx, cy, looks)
    local t = { rev = 1, list = {}, looks = looks }
    for i = 1, n do
        t.list[i] = { key = "t" .. i, kind = "test", name = "Pin " .. i, text = "Line " .. i, live = true,
            pos = { inst = 0, col = cx + (i % 20 - 10) * 0.01, row = cy + (math.floor(i / 20) - 5) * 0.01 } }
    end
    t.layer = Pins.Layer("test", 7, function(put)
        for i, e in ipairs(t.list) do put(e, t.looks[(i - 1) % #t.looks + 1]) end
    end, function() return t.rev end)
    return t
end"""

# Widget calls on each key's pin (its frame and regions), both canvases.
CALLS = """function(layer)
    local out = {}
    for _, c in ipairs(layer.canvases) do
        local p = c.pools.pin
        for i = 1, p and p.out or 0 do
            local o, n = p[i], 0
            for _, r in ipairs({ o, o.icon, o.ring, o.inner, o.count }) do n = n + (Sim.callsOn[r] or 0) end
            local k = p.keys[i]
            out[k] = (out[k] or 0) + n
        end
    end
    return out
end"""


def shown(L, sim, ns, looks, n=1):
    sim.Slash("/mm toggle")
    sim.Run(1)
    cam = ns.UI.Camera.cam
    t = L.eval(LAYER)(ns.UI.Pins, n, cam.cx, cam.cy, L.table_from([L.table_from(x) for x in looks]))
    sim.Run(0.5)
    return t


def test_pin_store_diff():
    L, sim, ns = boot()
    t = shown(L, sim, ns, [{"icon": L.table_from({"texture": 136459})}], 200)
    calls = L.eval(CALLS)
    lay = t.layer
    assert lay.front.pools.pin.n == 200
    t.rev = 2  # the other canvas laid out too: both show the 200
    sim.Run(0.5)
    assert lay.canvases[1].pools.pin.n == lay.canvases[2].pools.pin.n == 200

    def changed(run):
        before = dict(calls(lay).items())
        started = lay.started
        run()
        after = dict(calls(lay).items())
        return [k for k in after if after[k] != before.get(k, 0)], lay.started != started

    def bump():
        t.rev += 1
        sim.Run(0.5)
    assert changed(bump) == ([], True)  # laid out again, every pin kept as it stood
    assert changed(lambda: sim.Run(1)) == ([], False)  # unchanged rev: no layout
    t.list[5].pos.col += 0.02
    assert changed(bump) == (["t5"], True)  # one changed: that one re-set
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_stylepin():
    L, sim, ns = boot()
    under = L.table_from({"atlas": "Quest-In-Progress-Icon-yellow", "under": "UI-QuestPoi-QuestNumber",
                          "tint": L.table_from([1, 0.5, 0.25]), "inner": 133730})
    looks = [
        {"icon": L.table_from({"texture": 136459})},  # (a)
        {"icon": L.table_from({"atlas": "Professions_Tracking_Herb"})},  # (b)
        {"size": 22, "icon": under, "count": "2/5"},  # (c), its count
        {"size": 10, "icon": L.table_from({"color": L.table_from([1, 0.82, 0])})},  # (d)
        {"icon": L.table_from({"atlas": "no-such-atlas", "color": L.table_from([0.4, 0.9, 0.3])})},  # (d): no atlas
    ]
    t = shown(L, sim, ns, looks, 5)
    S, pins = sim.state, t.layer.front.pools.pin
    got = {pins["keys"][i]: pins[i] for i in range(1, pins.n + 1)}
    vis = lambda r: r is not None and S[r].shown

    a, b, c, d, e = (got["t%d" % i] for i in range(1, 6))
    assert S[a.icon].texture == 136459 and S[a.icon].width == 14 and not vis(a.ring)
    assert S[b.icon].atlas == "Professions_Tracking_Herb" and S[b.icon].width == 14 and not vis(b.ring)
    # (c): the disc tinted, the objective icon in it shaded, the atlas over it at 0.62; the count
    assert S[c.ring].atlas == "UI-QuestPoi-QuestNumber" and list(S[c.ring].vertex.values()) == [1, 0.5, 0.25, 1]
    assert S[c.inner].texture == 133730 and abs(S[c.inner].width - 22 * 0.56) < 1e-9 and vis(c.inner)
    assert list(S[c.inner].vertex.values()) == [0.55, 0.55, 0.55, 1]
    assert S[c.icon].atlas == "Quest-In-Progress-Icon-yellow" and abs(S[c.icon].width - 22 * 0.62) < 1e-9
    assert S[c.count].text == "2/5" and S[c.count].points[1].point == "TOP" and S[c.count].points[1].y == 2
    # (d): a dot of its colour on a dark ring
    for p, size, col in ((d, 10, [1, 0.82, 0]), (e, 14, [0.4, 0.9, 0.3])):
        assert vis(p.ring) and list(S[p.ring].vertex.values()) == [0, 0, 0, 0.9] and S[p.ring].width == size * 0.6 + 3
        assert list(S[p.icon].vertex.values()) == col + [1] and S[p.icon].width == size * 0.6

    # Restyled in place (rev 3: the first canvas's pins again): (c) its count done; (a) a dot.
    t.looks[3].count = None
    t.looks[1].icon = L.table_from({"color": L.table_from([1, 1, 1])})
    t.rev = 2
    sim.Run(0.5)
    t.rev = 3
    sim.Run(0.5)
    pins = t.layer.front.pools.pin
    got = {pins["keys"][i]: pins[i] for i in range(1, pins.n + 1)}
    assert S[got["t3"].count].text is None
    assert vis(got["t1"].ring) and S[got["t1"].icon].texture == "Interface\\CharacterFrame\\TempPortraitAlphaMask"
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_pin_tooltip_click_drag():
    L, sim, ns = boot()
    G, Pins, view, cam = L.globals(), ns.UI.Pins, ns.UI.Window.view, ns.UI.Camera.cam
    t = shown(L, sim, ns, [{"icon": L.table_from({"texture": 136459})}])
    t.list[1].pos.col, t.list[1].pos.row = cam.cx, cam.cy  # under the view's centre
    t.rev = 2
    sim.Run(0.5)
    tip, S = G.GameTooltip, sim.state
    pin = t.layer.front.pools.pin[1]
    assert not S[pin].mouse  # the view takes every click and drag: no pin catches the mouse

    owners = sim.calls.SetOwner or 0
    sim.MoveCursorTo(view)
    sim.Run(0.2)
    assert not S[tip].shown  # the view hasn't the mouse yet (the client's OnEnter: nothing over it took it)
    sim.FireScript(view, "OnEnter", False)
    sim.Run(0.5)
    line = S[tip].lines
    same = L.eval("function(a, b) return a == b end")
    assert S[tip].shown and same(S[tip].owner, pin) and Pins.Hovered()[0].key == "t1" and Pins.Hovered()[1] == "test"
    assert S[line[1]].text == "Pin 1" and S[line[2]].text == "Line 1"
    assert list(S[line[2]].textColor.values()) == [0x9d / 255] * 3  # (ui/Tip.lua's DIM)
    assert same(S[line[2]].fontObject, G.GameTooltipTextSmall)
    assert sim.calls.SetOwner - owners == 1  # built once a hover, not each frame

    sim.Click(view, "LeftButton")  # a click on the view (ui/Window.lua's release): the pin under it, its popup
    pop = ns.UI.Popup
    assert pop.IsOpen() and not S[tip].shown and S[S[pop.frame].lines[1]].text == "Pin 1"
    assert [b.label for b in pop.buttons.values()] == ["Track", "Path to"]

    cx = cam.cx
    sim.Drag(view, 80, 0)  # the map moves with the cursor: the pin with it
    assert not ns.UI.Camera.follow and abs(cam.cx - (cx - 80 / cam.zoom)) < 1e-6
    sim.Run(0.2)
    assert S[tip].shown and Pins.Hovered()[0].key == "t1"

    sim.cursorX = sim.cursorX + 40  # off it: hidden, its fonts back
    sim.Step()
    assert not S[tip].shown and Pins.Hovered() is None and same(S[line[2]].fontObject, G.GameTooltipText)
    assert not Pins.Tap("LeftButton")
    sim.cursorX = sim.cursorX - 40  # back on it, then a button over the view takes the mouse: hidden
    sim.Step()
    assert S[tip].shown
    sim.FireScript(view, "OnLeave", False)
    assert not S[tip].shown and Pins.Hovered() is None
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


# The cursor over tile (col, row) of the map shown (test_quests.py's).
OVER = """function(ns, col, row)
    local view, cam = ns.UI.Window.view, ns.UI.Camera.cam
    local w, h = ns.UI.Window.Size()
    local x, y = ns.Atlas.Camera.TileToScreen(cam, w, h, col, row)
    local s = view:GetEffectiveScale()
    Sim.cursorX, Sim.cursorY = (view:GetLeft() + x) * s, (view:GetTop() - y) * s
end"""


def test_track_icon():
    """A click on a blip opens its popup (ui/Popup.lua, ui/Track.lua's Actions): Track and Path to. Track sets the user waypoint at
    it (the sim's C_Map), the gold arrow alone shows the way (ui/Guide.lua: no line), the waypoint's own pin stays
    away and the title's target is the icon; Path to, from tracking, switches to the line (the waypoint kept, the
    arrow gone), Track back again; Stop ends either. The mode survives a /reload (UI.saved.path, the game keeping
    its waypoint). The waypoint cleared elsewhere (the map's menu) ends the tracking too."""
    from sim import put_blips
    from test_blips import lua_tools
    L, sim, ns = boot()
    UI, S, view = ns.UI, sim.state, ns.UI.Window.view
    put_blips(L, sim, ns, [("Mailbox", 80, 40)])  # 89 yd: 16 px at 96, the arrow's ride in past the pin's
    sim.Slash("/mm toggle")
    sim.Run(3)
    b = next(e for e in ns.Model.Known("blips")[0].values() if e.name == "Mailbox")
    arrow = UI.Guide.arrow

    def drawn(lay):
        c = lay.front
        return c is not None and c.alpha == 1 and c.pools.pin is not None and c.pools.pin.n or 0

    def click(rows, pick, button="LeftButton"):
        L.eval(OVER)(ns, b.pos.col, b.pos.row)
        sim.FireScript(view, "OnEnter", False)
        sim.Step()
        sim.menu = None
        sim.Click(view, button, sim.cursorX, sim.cursorY, "screen")
        pop = UI.Popup
        assert pop.IsOpen() and sim.menu is None and S[S[pop.frame].lines[1]].text == "Mailbox"
        assert [b.label for b in pop.buttons.values()] == list(rows)
        sim.FireScript(next(b for b in pop.buttons.values() if b.label == pick), "OnClick", "LeftButton", False)
        assert not pop.IsOpen()
        sim.FireScript(view, "OnLeave", False)
        sim.Run(1)

    UI.Motion.SetZoom(400)  # (the icon 67 px off: the arrow in reach)
    click(("Track", "Path to"), "Track")
    assert sim.waypoint is not None and UI.saved.tracked.key == b.key and UI.saved.path is None
    assert drawn(UI.Waypoint) == 0 and UI.You.Target()[0] == "Mailbox"
    assert UI.Path.pieces == 0 and S[arrow].shown and S[arrow].alpha > 0.5
    click(("Stop tracking", "Path to"), "Path to")
    assert sim.waypoint is not None and UI.saved.tracked.key == b.key and UI.saved.path is not None
    assert UI.Path.pieces > 0 and not S[arrow].shown
    click(("Track", "Stop pathing"), "Track")
    assert UI.saved.path is None and UI.Path.pieces == 0 and S[arrow].shown
    click(("Stop tracking", "Path to"), "Path to")
    # A /reload: the mode saved, the game's waypoint kept.
    sim.FireEvent("PLAYER_LOGOUT")
    wp = sim.waypoint
    db = lua_tools(L).Dump(L.globals().MagicMap2DB)
    L2, sim2, ns2 = boot(f"MagicMap2DB = {db}\nSim.waypoint = UiMapPoint.CreateFromCoordinates({wp.uiMapID}, "
                         f"{wp.position.x}, {wp.position.y})", reload=True)
    sim2.Slash("/mm toggle")
    sim2.Run(3)
    assert ns2.UI.saved.path is not None and ns2.UI.saved.tracked.key == b.key and ns2.UI.Path.pieces > 0
    assert not sim2.state[ns2.UI.Guide.arrow].shown and not errors(sim2, ns2), errors(sim2, ns2)
    click(("Track", "Stop pathing"), "Stop pathing", "RightButton")  # a right click: the same popup
    assert sim.waypoint is None and UI.saved.tracked is None and UI.saved.path is None
    assert UI.Path.pieces == 0 and not S[arrow].shown
    click(("Track", "Path to"), "Track")
    assert sim.waypoint is not None and drawn(UI.Waypoint) == 0
    ns.Game.Command(L.table_from({"kind": "waypoint", "pos": False}))  # cleared elsewhere: the tracking ends
    sim.Run(1.5)  # (the arrow faded out)
    assert UI.saved.tracked is None and not S[arrow].shown
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


MAP_ART = ("Base", "Sea", "Repaint", "Patch")  # Textures/: the map art alone (the base, the sea, the repaints)


def test_pin_inventory():
    """#16: every pin type (ui/PinTypes.lua) has its row in Settings > Pins, in a family the page lists, and draws
    with Blizzard's art (an atlas, a FileDataID or a client path: never the addon's own files), as does every icon it
    offers; every pin the map draws has a type (Goldshire's quests, offers, places and vignette, blips of each kind,
    your corpse); your arrow is the Minimap's own; the addon's Textures/ hold only the map art, and no ui/ or game/
    file names one."""
    from sim import put_blips
    L, sim, ns = boot()
    Types, Feel = ns.UI.PinTypes, ns.UI.Feel
    families = {f.key for f in Types.FAMILIES.values()}

    def blizzard(art):
        if isinstance(art, (int, float)):
            return True
        return isinstance(art, str) and (art.startswith("A:") or art.isdigit()
                                         or art.startswith("Interface\\") and not art.startswith("Interface\\AddOns"))

    types = list(Types.list.values())
    assert len(types) >= 30
    for t in types:
        assert t.family in families and Feel.Entry(f"pins.{t.id}.show").art is not None, t.id
        icon = t.look.icon
        art = icon.atlas and "A:" + icon.atlas or icon.texture
        assert blizzard(art) or (art is None and icon.color is not None), (t.id, art)  # (a dot: the client's circle)
        for o in (t.icons or L.table_from([])).values():
            assert blizzard(o[2]), (t.id, o[2])
    assert {f"pins.{f}.show" for f in families} <= {k.key for k in Feel.Entries().values()}

    put_blips(L, sim, ns, [("Mailbox", 40, 20), ("Peacebloom", -40, 30), ("Innkeeper Belm", 60, -20),
                           ("Hai'zan", -50, -30), ("K'waii", 30, -50), ("Glimmerleaf", -20, 50)])
    sim.Slash("/mm toggle")
    sim.Run(4)
    sim.player.dead = True  # (a corpse)
    sim.Run(2)
    Types.untyped = 0
    ns.UI.Feel.Set("pins.all.alpha", 0.95)  # (every layer laid out again)
    sim.Run(2)
    assert Types.untyped == 0, Types.untyped

    st = sim.state[ns.UI.You.arrow]
    assert st.atlas == "ui-hud-minimap-arrow-player" and st.texture is None
    assert all(f.startswith(MAP_ART) for f in os.listdir(os.path.join(ROOT, "Textures")))
    for folder in ("ui", "game"):
        for name in os.listdir(os.path.join(ROOT, folder)):
            if name.endswith(".lua"):
                with open(os.path.join(ROOT, folder, name), encoding="utf-8") as fh:
                    assert "Textures\\\\" not in fh.read(), name
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_pin_types_apply():
    """Settings > Pins on the map: a type's icon (Blizzard's other art), its family's size (the type's own once set),
    its opacity, hidden (a type, then all pins: a family and a type follow until set); back on Reset. In a group's
    pill: its icon as chosen, kept apart once it may not group, none once hidden."""
    from test_quests import FRONTIER, LOVERS, client
    L, sim, ns, G = client([FRONTIER, LOVERS])

    def pin(ns, G, layer, quest):  # (laid out this time: a parked one keeps its key)
        p = getattr(ns.UI, layer).front.pools.pin
        i = p.at[f"quest:{quest}"]
        return p[i] if i is not None and i <= p.n else None
    S, Feel = sim.state, ns.UI.Feel

    def set_(key, v):
        Feel.Set(key, v)
        sim.Run(0.5)
    p = pin(ns, G, "Quests", 106)
    assert S[p].width == 19 and S[p.icon].atlas == "questturnin" and S[p].alpha == 1
    set_("pins.turnin.icon", "A:questrepeatableturnin")
    assert S[pin(ns, G, "Quests", 106).icon].atlas == "questrepeatableturnin"
    set_("pins.quests.size", 2)  # (the tests' icon size is 100%)
    assert S[pin(ns, G, "Quests", 52)].width == 48 and S[pin(ns, G, "Quests", 106)].width == 38
    set_("pins.turnin.size", 1)
    assert S[pin(ns, G, "Quests", 52)].width == 48 and S[pin(ns, G, "Quests", 106)].width == 19
    set_("pins.turnin.alpha", 0.5)
    assert S[pin(ns, G, "Quests", 106)].alpha == 0.5 and S[pin(ns, G, "Quests", 52)].alpha == 1
    set_("pins.quest.show", False)
    assert pin(ns, G, "Quests", 52) is None and pin(ns, G, "Quests", 106) is not None
    set_("pins.all.show", False)
    assert pin(ns, G, "Quests", 106) is None and pin(ns, G, "Offers", 70) is None
    set_("pins.turnin.show", True)
    assert pin(ns, G, "Quests", 106) is not None and pin(ns, G, "Offers", 70) is None
    Feel.Reset("pins")
    sim.Run(0.5)
    p = pin(ns, G, "Quests", 106)
    assert not [k for k, _ in (ns.UI.saved.feel or L.table_from({})).items() if k.startswith("pins.")]
    assert abs(S[p].width - 19 * 1.2) < 1e-9 and S[p.icon].atlas == "questturnin" and S[p].alpha == 1  # (Pin size back to 120%)
    assert pin(ns, G, "Quests", 52) is not None and pin(ns, G, "Offers", 70) is not None

    # A group's pill (test_cluster.py's five at one spot, rares).
    ns.UI.saved.cluster = True
    ns.UI.Cluster.Set("slots", 8)  # (every member's icon in the pill)
    Feel.Set("pins.rare.big", "always")  # (at the big map's zone-wide view: else only zoomed in)
    sim.Press("M")
    sim.Run(1)
    cam = ns.UI.Camera.cam
    t = L.eval("""function(Pins, cx, cy)
        local t = { list = {} }
        for i = 1, 5 do
            t.list[i] = { key = "r" .. i, name = "Rare " .. i, pos = { inst = 0, col = cx, row = cy } }
        end
        local look = { size = 15, icon = { texture = 137008 }, type = "rare" }
        t.layer = Pins.Layer("raretest", 7, function(put)
            for _, e in ipairs(t.list) do put(e, look) end
        end, function() return 1 end, { cluster = true })
        return t
    end""")(ns.UI.Pins, cam.cx, cam.cy)
    sim.Run(0.5)
    pills = next(lay for lay in ns.UI.Engine.layers.values() if lay.name == "clusters")

    def ours():  # the pill holding them: its icons' art
        pool = pills.front.pools.pill
        for i in range(1, (pool.n if pool else 0) + 1):
            o = pool[i]
            ms = o.cluster and list(o.cluster.members.values())
            if ms and any(m[1].key == "r1" for m in ms):  # (its icons in its members' order: ours alone)
                ics = list(o.icons.values())
                return {S[ics[i].icon].atlas or S[ics[i].icon].texture
                        for i, m in enumerate(ms) if str(m[1].key).startswith("r") and i < len(ics)}

    def alone():
        c = t.layer.front
        return c.pools.pin.n if c and c.alpha > 0 and c.pools.pin else 0
    assert ours() == {137008} and alone() == 0
    set_("pins.rare.icon", "A:vignettekill")
    assert ours() == {"vignettekill"}
    set_("pins.rare.group", False)
    assert ours() is None and alone() == 5
    set_("pins.rare.show", False)
    assert ours() is None and alone() == 0
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_saved_sizes_kept():
    """A player's sizes from before #16: Icon size (icons.scale) is Pin size, as it was; Quest icon size
    (quests.scale, a factor on it) becomes In progress's and Ready to turn in's own size (snapped to the slider's
    step), the old key gone; quests to pick up follow Pin size, as they did."""
    L, sim, ns = boot()
    Feel = ns.UI.Feel
    ns.UI.saved.feel = L.table_from({"icons.scale": 1.2, "quests.scale": 1.3})
    Feel.Loaded()
    assert dict(ns.UI.saved.feel.items()) == {"icons.scale": 1.2, "pins.quest.size": 1.6, "pins.turnin.size": 1.6}
    assert Feel.Get("pins.offer.size") == 1.2 and Feel.Get("pins.quests.size") == 1.2
    assert ns.UI.PinTypes.Of("turnin").size == 1.6 and ns.UI.PinTypes.Of("offer").size == 1.2
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))



def test_big_map_zoomed_in():
    """On the big map, zoomed out, a vendor's pin is hidden and a flight point's and a quest's show; zoomed in, the
    vendor's shows too (faded in past the threshold); the minimap shows it at any zoom."""
    L, sim, ns = boot()
    ns.UI.Feel.Set("pins.all.big", "zoomed")  # (the default: the tests' look has every pin always)
    sim.Slash("/mm toggle")
    sim.Run(1.5)
    UI = ns.UI
    cam = UI.Camera.cam
    t = L.eval("""function(Pins, cx, cy)
        local t = { list = {} }
        for i, ty in ipairs({ "food", "flight", "quest" }) do
            t.list[i] = { key = ty, name = ty, pos = { inst = 0, col = cx + i * 0.01, row = cy } }
            t.list[i].look = { size = 15, icon = { texture = 137008 }, type = ty }
        end
        t.layer = Pins.Layer("bigtest", 7, function(put)
            for _, e in ipairs(t.list) do put(e, e.look) end
        end, function() return 1 end)
        return t
    end""")(UI.Pins, cam.cx, cam.cy)

    def shown(zoom):  # the keys whose pins show at zoom: laid out, their frame (a zoom's own) not faded out
        UI.Motion.SetZoom(zoom)
        sim.Run(1)
        c = t.layer.front
        p = c.pools.pin
        return {p[i].entry.key for i in range(1, p.n + 1) if c.alpha > 0 and p[i].on.alpha > 0}
    assert shown(30) == {"food", "flight", "quest"}  # (the minimap: every pin)
    sim.Press("M")
    sim.Run(1.5)
    w = UI.Window.Size()[0]
    z = w * ns.Atlas.TILE_YARDS / UI.Feel.Get("pins.zoomIn")  # (the view this many yards across)
    assert shown(z / 2) == {"flight", "quest"}
    assert shown(z * 1.5) == {"food", "flight", "quest"}
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
