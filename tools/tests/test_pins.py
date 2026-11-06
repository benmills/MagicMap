"""The pin store (ui/Pins.lua) on the simulated client: one store diffed by id (200 pins, one changed:
that pin alone re-set; the rev bumped with nothing changed, or left as it is: none); StylePin's forms
(a)-(d) and count; a pin's tooltip (built once a hover, its lines small and grey, hidden off it with
its fonts back), a click on it, and a drag over it panning the map."""
from test_addon import boot, errors

# A test kind's layer: n pins about the view's centre (Known-shaped), each its look; t.rev its rev.
LAYER = """function(Pins, n, cx, cy, looks)
    local t = { rev = 1, list = {}, looks = looks, clicks = {} }
    for i = 1, n do
        t.list[i] = { key = "t" .. i, kind = "test", name = "Pin " .. i, text = "Line " .. i, live = true,
            pos = { inst = 0, col = cx + (i % 20 - 10) * 0.01, row = cy + (math.floor(i / 20) - 5) * 0.01 } }
    end
    t.layer = Pins.Layer("test", 7, function(put)
        for i, e in ipairs(t.list) do put(e, t.looks[(i - 1) % #t.looks + 1]) end
    end, function() return t.rev end,
        { click = function(e, button) t.clicks[#t.clicks + 1] = e.key .. " " .. button end })
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
    assert list(S[line[2]].textColor.values()) == [0.85] * 3
    assert same(S[line[2]].fontObject, G.GameTooltipTextSmall)
    assert sim.calls.SetOwner - owners == 1  # built once a hover, not each frame

    sim.Click(view, "LeftButton")  # a click on the view (ui/Window.lua's release): the pin under it
    assert list(t.clicks.values()) == ["t1 LeftButton"]

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
    """A click on a blip opens the track menu (ui/Track.lua): Track and Path to. Track sets the user waypoint at
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
        items = [(e.kind, e.text) for e in sim.MenuItems().values()]
        assert items[:3] == [("title", "Mailbox")] + [("button", r) for r in rows], items  # (then the map's rows)
        assert ("button", "Waypoint here") not in items
        next(e for e in sim.MenuItems("button").values() if e.text == pick).onSelect()
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
    click(("Track", "Stop pathing"), "Stop pathing", "RightButton")  # a right click: the same menu
    assert sim.waypoint is None and UI.saved.tracked is None and UI.saved.path is None
    assert UI.Path.pieces == 0 and not S[arrow].shown
    click(("Track", "Path to"), "Track")
    assert sim.waypoint is not None and drawn(UI.Waypoint) == 0
    ns.Game.Command(L.table_from({"kind": "waypoint", "pos": False}))  # cleared elsewhere: the tracking ends
    sim.Run(1.5)  # (the arrow faded out)
    assert UI.saved.tracked is None and not S[arrow].shown
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
