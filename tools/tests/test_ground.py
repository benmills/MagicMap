"""The ground layers at the spike's look and cost (docs/v1-plan.md M1.4: ui/Borders.lua, Labels.lua,
Tiles.lua, You.lua) on the simulated client. Borders: a zone border's segment is 2 Lines (its shadow
from zoom 60, then it) and a subzone's 1 (from zoom 140); a dead end at most 4 dashes; never more
than 3000 Lines, the whole of the Eastern Kingdoms at zoom 4 included. Labels: zones in capitals,
10 pt, up to zoom 450; subzones 9 pt, by size from 120, 220 and 400; none touching another; a name
new to the view fades in. Tiles: /mma tint and the gear's "Colour-matched tiles" lay them out again
plain, and back. You: the arrow, on your map only.

  .venv/bin/python -m pytest tools/tests/test_ground.py -s   # prints the borders' Lines by zoom
"""
from test_addon import boot, errors

CAP = 3000
TARREN_MILL, KHARANOS = (33.689, 32.051), (32.904, 42.474)  # Data/Labels.lua's towns


def shown(big=False):
    L, sim, ns = boot()
    sim.Slash("/mma toggle")
    sim.Run(3)
    if big:
        sim.Press("M")
        sim.Run(1)
    ns.UI.Motion.SetFollow(False)
    return L, sim, ns


def layer(ns, name):
    return next(lay for lay in ns.UI.Engine.layers.values() if lay.name == name)


def look(sim, ns, at, zoom):
    """The camera at tile `at`, zoom, settled and every layer laid out there."""
    cam = ns.UI.Camera.cam
    cam.cx, cam.cy = at
    ns.UI.Motion.SetZoom(zoom)
    sim.Run(2)
    for lay in ns.UI.Engine.layers.values():
        assert lay.front.zoom == zoom and not lay.busy, lay.name


def lines(front):
    return {k: front.pools[k].n if front.pools[k] else 0 for k in ("shadow", "line", "sub")}


# Of the lines drawn over the canvas's region: the ends that fade (a dead end: fadeStart, fadeEnd > 0).
FADING = """function(Atlas, c, inst)
    local r, n = c.region, 0
    for _, l in ipairs(Atlas.BorderLines(inst, c.zoom)) do
        local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
        for i = 5, #l, 2 do
            x0, x1, y0, y1 = math.min(x0, l[i]), math.max(x1, l[i]), math.min(y0, l[i + 1]), math.max(y1, l[i + 1])
        end
        if not (x1 < r[1] or x0 > r[3] or y1 < r[2] or y0 > r[4]) then
            n = n + (l[3] > 0 and 1 or 0) + (l[4] > 0 and 1 or 0)
        end
    end
    return n
end"""


def test_borders():
    L, sim, ns = shown(big=True)
    borders, fading = layer(ns, "borders"), L.eval(FADING)
    S = sim.state
    trace = L.eval("""function(R)
        local got, trace = {}, R.Trace
        R.Trace = function(kind, d)
            if kind == "layout" and d.layer == "borders" and d.e == "end" then got.ms = d.ms end
            if kind == "swap" and d.layer == "borders" then got.swap = d.ms end
            return trace(kind, d)
        end
        return got
    end""")(ns.Runtime)
    perf = ns.Runtime.Perf()[0]["map: borders"]
    for name, at in (("Tarren Mill", TARREN_MILL), ("Kharanos", KHARANOS)):
        counts = []
        for zoom in (16, 30, 60, 100, 140, 200, 300, 500, 800):
            perf.max = 0
            sim.Price(True)  # (docs/evidence/perf-m0.md's prices)
            look(sim, ns, at, zoom)
            sim.Price(False)
            front = borders.front
            n = lines(front)
            assert set(k for k in front.pools.keys()) <= {"shadow", "line", "sub"}
            # 2 Lines a zone border's segment (the shadow from zoom 60), 1 a subzone's (from 140).
            assert n["shadow"] == (n["line"] if zoom >= 60 else 0) and (zoom >= 140 or n["sub"] == 0), (zoom, n)
            assert sum(n.values()) < CAP, (name, zoom, n)  # (the cap never cuts a view short here)
            # A dead end's dashes: at most 4 an end, each 5 px or less, faded (Layers.lua:1531-1580).
            dashes = 0
            for i in range(1, n["line"] + 1):
                st = S[front.pools.line[i]]
                if st.color[4] < 0.6:
                    s, e = st.startPoint, st.endPoint
                    assert ((e[3] - s[3]) ** 2 + (e[4] - s[4]) ** 2) ** 0.5 <= 5 + 1e-9
                    dashes += 1
            assert dashes <= 4 * fading(ns.Atlas, front, 0), (zoom, dashes)
            counts.append(f"{zoom} {sum(n.values())} ({n['line']} + {n['shadow']} + {n['sub']}; {trace.ms:.0f} ms,"
                          f" {perf.max:.1f} a frame, swap {trace.swap:.2f})")
            assert perf.max <= 8 and trace.swap <= 4
        print(f"borders, big window, {name}: Lines by zoom (zone + shadow + subzone; the layout priced: in all,"
              " its slowest frame, its swap):\n  " + "\n  ".join(counts))

    # The whole of the Eastern Kingdoms at zoom 4 (its coarsest level, the band within 0.15 tiles).
    n = L.eval("""function(UI, view)
        local c = CreateFrame("Frame", nil, view)
        c.pools, c.made, c.ox, c.oy, c.zoom = {}, 0, 32, 32, 4
        UI.Borders.build(c, 0, 4, 0, 0, 64, 64)
        local n = 0
        for _, p in pairs(c.pools) do n = n + p.n end
        return n
    end""")(ns.UI, ns.UI.Window.view)
    print(f"borders: the Eastern Kingdoms whole at zoom 4: {n} Lines")
    assert 0 < n <= CAP
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def placed(sim, front):
    """The labels a layout placed: (text, size, weight, x0, y0, x1, y1) in canvas px; weight: the
    name's land chunks (ui/Labels.lua, from Data/Labels.lua's size)."""
    S, out = sim.state, []
    pool = front.pools.label
    for i in range(1, (pool.n if pool else 0) + 1):
        fs = pool[i]
        st = S[fs]
        p = st.points[1]
        w, h = fs.GetStringWidth(fs), fs.GetStringHeight(fs)
        out.append((st.text, st.font[2], fs.label.weight, p.x - w / 2, -p.y - h / 2, p.x + w / 2, -p.y + h / 2))
    return out


def test_labels():
    L, sim, ns = shown()
    labels, S = layer(ns, "labels"), sim.state
    font = L.globals().GameFontNormal.GetFont(None)[0]
    counts = []
    for zoom in (100, 200, 500):
        look(sim, ns, KHARANOS, zoom)
        got = placed(sim, labels.front)
        zones = [t for t, size, *_ in got if size == 10]
        subs = [w for _, size, w, *_ in got if size == 9]
        assert len(zones) + len(subs) == len(got)
        pool = labels.front.pools.label
        assert all(t == t.upper() for t in zones) and all(S[pool[i]].font[1] == font for i in range(1, len(got) + 1))
        if zoom == 100:  # zones, no subzone yet (from 120)
            assert zones and not subs
        if zoom == 200:  # zones, and the subzones of weight 40 or more
            assert zones and subs and min(subs) >= 40
        if zoom == 500:  # past 450 no zone; the smaller subzones too (from 220, 400)
            assert not zones and min(subs) < 40
        boxes = [b[3:] for b in got]
        for i, a in enumerate(boxes):  # none touching another
            for b in boxes[i + 1:]:
                assert a[0] >= b[2] or a[2] <= b[0] or a[1] >= b[3] or a[3] <= b[1], (a, b)
        counts.append(f"{zoom}: {len(zones)} zones, {len(subs)} subzones")
    print("labels at Kharanos, " + "; ".join(counts))

    # Panned away: the names new to the view fade in over 0.2 s; one kept from the last layout doesn't.
    cam = ns.UI.Camera.cam
    before = {t for t, *_ in placed(sim, labels.front)}
    cam.cx = cam.cx + 3
    for _ in range(30):
        sim.Step()
        if not labels.busy and labels.front.zoom == 500 and {t for t, *_ in placed(sim, labels.front)} != before:
            break
    pool = labels.front.pools.label
    alphas = {S[pool[i]].text: S[pool[i]].alpha for i in range(1, pool.n + 1)}
    fresh = [t for t in alphas if t not in before]
    assert fresh and all(alphas[t] < 1 for t in fresh) and all(alphas[t] == 1 for t in alphas if t in before)
    sim.Run(0.25)
    assert all(S[pool[i]].alpha == 1 for i in range(1, pool.n + 1))
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_tint():
    L, sim, ns = shown()
    tiles, saved = layer(ns, "tiles"), L.globals().MagicMapAtlasDB.UI
    S = sim.state

    def drawn():
        """The art laid out: tinted, coast-masked (Elwynn and Westfall's coast are in view)."""
        p, tinted, masked = tiles.front.pools.art, 0, 0
        for i in range(1, p.n + 1):
            t = p[i]
            v = S[t].vertex
            tinted += v is not None and (v[1], v[2], v[3]) != (1, 1, 1)
            masked += bool(t.masked)
        return p.n, tinted, masked

    n, _, masked = drawn()
    assert saved.tint and masked > 0
    front = tiles.front
    sim.Slash("/mma tint")  # off: the art plain, laid out again
    sim.Run(1)
    assert saved.tint is False and tiles.front != front and drawn()[1:] == (0, 0)
    assert sim.prints[len(sim.prints)].endswith("tile colour correction off")
    # The gear's "Colour-matched tiles" runs the same: on again, the coasts fade.
    sim.Click(ns.UI.Controls.gear)
    item = next(e for e in sim.MenuItems().values() if e.text == "Colour-matched tiles")
    assert item.isSelected() is False
    item.onSelect()
    sim.Run(1)
    assert saved.tint and drawn()[2] == masked and sim.prints[len(sim.prints)].endswith("tile colour correction on")

    # A map with no colour data says so (every map with tiles has some: Data/TileColor.lua, as a newer
    # client's map might not).
    ns.Atlas.Data.TileColor[0] = None
    sim.Slash("/mma tint")
    sim.Slash("/mma tint")
    assert sim.prints[len(sim.prints)].endswith("tile colour correction on (no data for this map)")
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_arrow():
    """Core.lua:155-175: the arrow 22 * 64 / 45 px (Textures/PlayerArrow.tga, 64 px around the
    Minimap's 45 px art), over every layer, unsnapped; none while another map shows (and none while
    your position is withheld: test_spike_bugs.py R-K5)."""
    L, sim, ns = shown()
    arrow, view = ns.UI.You.arrow, ns.UI.Window.view
    S = sim.state
    st = S[arrow]
    assert arrow.IsShown(arrow) and st.texture == "Interface\\AddOns\\MagicMapAtlas\\Textures\\PlayerArrow"
    assert abs(st.width - 22 * 64 / 45) < 1e-9 and st.snap is False and st.bias == 0
    overlay = arrow.GetParent(arrow)
    assert overlay.GetFrameLevel(overlay) - view.GetFrameLevel(view) == 10
    ns.UI.Motion.FitMap(1)  # Kalimdor: not where you are
    sim.Run(0.5)
    assert not arrow.IsShown(arrow)
    ns.UI.Motion.SetFollow(True, True)
    sim.Run(1)
    assert arrow.IsShown(arrow) and ns.UI.Camera.inst == 0
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
