"""The ground layers at the spike's look and cost (docs/v1-plan.md M1.4: ui/Labels.lua, Tiles.lua, You.lua) on the
simulated client. Labels: zones in capitals, 10 pt, up to zoom 450; subzones 7 pt (9 at Subzone size 80%), by size from 120, 220 and 400;
none touching another; a name new to the view fades in. Tiles: an open-sea tile isn't drawn (the backdrop shows).
You: the arrow, on your map only.
"""
from test_addon import boot, errors

KHARANOS = (32.904, 42.474)  # the town's AreaPOI spot


def shown(big=False):
    L, sim, ns = boot()
    sim.Slash("/mm toggle")
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
        assert not lay.on or lay.front.zoom == zoom and not lay.busy, lay.name


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
    L, sim, ns = shown(big=True)  # (names on the big map only)
    labels, S = layer(ns, "labels"), sim.state
    font = L.globals().GameFontNormal.GetFont(None)[0]
    title = "Fonts\\MORPHEUS.TTF"
    counts = []
    for zoom in (100, 200, 500):
        look(sim, ns, KHARANOS, zoom)
        got = placed(sim, labels.front)
        pool = labels.front.pools.label
        faces = [S[pool[i]].font for i in range(1, len(got) + 1)]  # path, size, flags: as drawn
        zone = [f[1] == title for f in faces]  # a font as drawn: (path, size, flags), 1-based from Python
        zones = [t for (t, *_), z in zip(got, zone) if z]
        subs = [w for (_, _, w, *_), z in zip(got, zone) if not z]
        assert len(zones) + len(subs) == len(got)
        # Zones in Morpheus, mixed case, 11.5 to 22 pt, an outline at 12 or less; subzones in the body face, 7 pt, no outline.
        assert all(t != t.upper() for t in zones) and all(11.5 <= f[2] <= 22 for f, z in zip(faces, zone) if z)
        assert all(f[1] == font and f[2] == 7 and f[3] == "" for f, z in zip(faces, zone) if not z)  # (9 pt at Subzone size 80%)
        assert all(f[3] == ("OUTLINE" if f[2] <= 12 else "") for f, z in zip(faces, zone) if z)
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
    # (at 500 every name is a subzone: its opacity, Subzone opacity's 45%, is the name's own alpha, the fade's end)
    near = lambda a, b: abs(a - b) < 1e-6
    assert fresh and all(alphas[t] < 0.45 for t in fresh) and all(near(alphas[t], 0.45) for t in alphas if t in before)
    sim.Run(0.25)
    assert all(near(S[pool[i]].alpha, 0.45) for i in range(1, pool.n + 1))
    ns.UI.Feel.Set("labels.subAlpha", 0.3)  # (laid out again: the names at their new opacity)
    sim.Run(0.5)
    pool = labels.front.pools.label
    assert pool.n and all(near(S[pool[i]].alpha, 0.3) for i in range(1, pool.n + 1) if S[pool[i]].shown)
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_open_sea():
    """An open-sea tile (Data/TileColor.lua's sea[]: the backdrop's colour) isn't drawn: the backdrop shows."""
    L, sim, ns = shown()
    tiles = layer(ns, "tiles")
    key = L.eval("function(D) for k in pairs(D.TileColor[0].sea) do return k end end")(ns.Atlas.Data)
    look(sim, ns, (key // 64 + 0.5, key % 64 + 0.5), 200)
    p = tiles.front.pools
    fdid = ns.Atlas.Tiles(0)[key]
    assert all(p.art[i].fdid != fdid for i in range(1, p.art.n + 1))
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_map_art():
    """The ocean, on its switch; a sea tile's water of ours."""
    L, sim, ns = shown()
    tiles, labels = layer(ns, "tiles"), layer(ns, "labels")
    S = sim.state
    look(sim, ns, (40.2, 40.8), 200)
    sea = ns.UI.Sea
    assert sea.frame.GetFrameLevel(sea.frame) > tiles.front.GetFrameLevel(tiles.front) and sea.frame.GetFrameLevel(sea.frame) < labels.frame.GetFrameLevel(labels.frame)
    assert sea.Shown(), "the ocean, on by default"
    ns.UI.Feel.Set("sea.on", False)
    sim.Run(0.1)
    assert not sea.Shown()
    ns.UI.Feel.Set("sea.on", True)
    look(sim, ns, (30.5, 55.5), 200)  # the sea tile that left a block in the sea: water of ours
    p = tiles.front.pools.art
    assert any("Patch0_30_55" in str(S[p[i]].texture) for i in range(1, p.n + 1))
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def repaint_shown(build=None):
    """The map over a repaint on a client of that build (default: the one Data/Repaint.lua names; the sim's own is another)."""
    L, sim, ns = boot()
    v, b = (build or ns.Data.Repaint.build).rsplit(".", 1)
    L.globals().GetBuildInfo = L.eval(f"""function() return "{v}", "{b}", "Sep 1 2026", 16001 end""")
    sim.Slash("/mm toggle")
    sim.Run(3)
    ns.UI.Motion.SetFollow(False)
    look(sim, ns, EK1, 200)
    sim.Run(1)
    return L, sim, ns


def repaints(ns, tiles=None):
    tiles = tiles or layer(ns, "tiles")
    p = tiles.front.pools.repaint
    return [p[i] for i in range(1, p.n + 1)] if p else []


EK1 = (38.5, 25.5)  # ek1a and ek1b meet here


def test_repaint():
    """The AI repaints, with the tiles on their canvas: over the ocean, under the names, later places over earlier."""
    L, sim, ns = repaint_shown()
    tiles, labels, S = layer(ns, "tiles"), layer(ns, "labels"), sim.state
    pieces = repaints(ns)
    assert pieces, "repaints near one, on by default"
    frame = pieces[0].GetParent(pieces[0])
    assert L.eval("rawequal")(frame.GetParent(frame), tiles.front)
    assert ns.UI.Sea.frame.GetFrameLevel(ns.UI.Sea.frame) < frame.GetFrameLevel(frame) < labels.frame.GetFrameLevel(labels.frame)
    subs = {str(S[t].texture).split("\\")[-1].split("_")[0]: S[t].sublevel for t in pieces}
    assert subs["Repaintek1b"] > subs["Repaintek1a"]
    z = ns.UI.Camera.cam.zoom
    assert all(S[t].layer == "ARTWORK" and abs(S[t].width - z) <= 1 and S[t].snap is False for t in pieces)

    ns.UI.Feel.Set("repaint.on", False)
    sim.Run(1)
    assert not repaints(ns), "none with the setting off"
    ns.UI.Feel.Set("repaint.on", True)
    sim.Run(1)
    assert repaints(ns), "back with it on"
    look(sim, ns, (32, 49.75), 200)  # Elwynn: none near
    sim.Run(1)
    assert not repaints(ns)
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_repaint_other_build():
    """A client on another build: the raw map, whatever the setting; said once; no errors."""
    L, sim, ns = repaint_shown("9.9.9.1")
    assert ns.UI.Feel.Get("repaint.on") is True and not repaints(ns)
    look(sim, ns, (40, 41), 200)
    sim.Run(1)
    assert not repaints(ns)
    said = [p for p in sim.prints.values() if "art repairs are off" in str(p)]
    assert len(said) == 1 and "9.9.9.1" in str(said[0])
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_repaint_later_build():
    """A later build of the version they were stamped on keeps them (its tiles checked unchanged so far); an earlier
    one doesn't (Atlas.RepaintFits)."""
    L, sim, ns = boot()
    v, b = ns.Data.Repaint.build.rsplit(".", 1)
    fits = ns.Atlas.RepaintFits
    assert fits(f"{v}.{int(b) + 26}") and fits(f"{v}.{b}") and not fits(f"{v}.{int(b) - 1}") and not fits(f"9.9.9.{b}")
    L, sim, ns = repaint_shown(f"{v}.{int(b) + 26}")
    assert repaints(ns) and not [p for p in sim.prints.values() if "art repairs are off" in str(p)]


def test_dxt5_round_trip():
    """DXT5 keeps a soft edge and its colours, through what the map tools read a BLP with; a mip for each halving."""
    import struct

    import numpy as np

    from mmtools.blp import write_blp, write_blp_dxt5
    from mmtools.mapgrid import blp_rgba
    y, x = np.mgrid[0:64, 0:64]
    rgba = np.dstack((x * 4, y * 4, np.full_like(x, 90), np.clip((x - 16) * 8, 0, 255))).astype(np.uint8)
    blp = write_blp_dxt5(rgba)
    enc, depth, kind, mips, w, h = struct.unpack_from("<BBBBII", blp, 8)
    assert (enc, depth, kind, mips, w, h) == (2, 8, 7, 1, 64, 64)
    sizes = struct.unpack_from("<16I", blp, 20 + 64)
    assert list(sizes[:7]) == [16 * 16 * 16, 8 * 8 * 16, 4 * 4 * 16, 2 * 2 * 16, 16, 16, 16] and not any(sizes[7:])
    back = np.asarray(blp_rgba(blp)).astype(int)
    assert back.shape == rgba.shape
    a = rgba.astype(int)
    assert np.abs(back[..., 3] - a[..., 3]).max() <= 12, "the soft edge"
    assert back[:, :12, 3].max() == 0 and back[:, 56:, 3].min() == 255, "clear stays clear, solid solid"
    shows = a[..., 3] > 0
    assert np.abs(back[..., :3] - a[..., :3])[shows].mean() < 4, "the colours"
    assert struct.unpack_from("<BBBB", write_blp([(1, 1, bytes(3))]), 8) == (2, 0, 0, 1), "DXT1's as it was"


def test_arrow():
    """Core.lua:155-175: the arrow 22 px, the Minimap's own (its atlas, ui-hud-minimap-arrow-player: #16), over every
    layer, unsnapped; none while another map shows (and none while your position is withheld: test_spike_bugs.py R-K5)."""
    L, sim, ns = shown()
    arrow, view = ns.UI.You.arrow, ns.UI.Window.view
    S = sim.state
    st = S[arrow]
    assert arrow.IsShown(arrow) and st.atlas == "ui-hud-minimap-arrow-player"
    assert st.width == 22 and st.snap is False and st.bias == 0
    overlay = arrow.GetParent(arrow)
    assert overlay.GetFrameLevel(overlay) - view.GetFrameLevel(view) == 18
    ns.UI.Motion.FitMap(1)  # Kalimdor: not where you are
    sim.Run(0.5)
    assert not arrow.IsShown(arrow)
    ns.UI.Motion.SetFollow(True, True)
    sim.Run(1)
    assert arrow.IsShown(arrow) and ns.UI.Camera.inst == 0
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
