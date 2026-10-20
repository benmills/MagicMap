"""The window's chrome on the simulated client (ui/Window.lua, Chrome.lua, Controls.lua, Title.lua,
Menus.lua): a first login shows it on the minimap's spot, square, 200 yd across, at the minimap's
strata; Forever's oversized edge atlases (spike-bugs L2) leave the view's inset at 2..6 px and the
zoom buttons clear of the grip; the template's own parts are hidden; the controls fade in and out
over 0.15 s (kept while a menu is open); the tips; the title; resizing keeps the yards across (the
gear's rows: test_gear.py)."""
from test_addon import boot, errors

SPAN_TILES = 200 / (1600 / 3)  # 200 yd across the small window (MinimapMode.lua:25)
SEP = "  \u00b7  ".encode("utf-8").decode("latin-1")  # the title's joins, as the sim's Lua (latin-1) reads them


def fresh():
    """A first login (no saved data): Game reads the minimap's spot, the sim's Minimap's rect
    (obs.minimap.home, with its cluster's strata), and Model hands it on to BigMap.home."""
    L, sim, ns = boot("MagicMap2DB = {}")
    mm = L.globals().Minimap
    spot = (mm.GetLeft(mm), mm.GetTop(mm), mm.GetWidth(mm), mm.GetHeight(mm))
    sim.Step()
    home = ns.UI.BigMap.home
    assert (home.left, home.top, home.w, home.h) == spot and ns.UI.BigMap.homeStrata == "LOW"
    return L, sim, ns


def rect(f):
    return f.GetLeft(f), f.GetTop(f), f.GetWidth(f), f.GetHeight(f)


def box(r):
    left, bottom = r.GetLeft(r), r.GetBottom(r)
    return left, bottom, left + r.GetWidth(r), bottom + r.GetHeight(r)


def test_chrome():
    L, sim, ns = fresh()
    UI, G = ns.UI, L.globals()
    f, view, c, ctl = UI.Window.frame, UI.Window.view, UI.Chrome, UI.Controls
    saved = G.MagicMap2DB.UI

    # On the minimap's spot (the sim's: 140 square at the screen's top right), its strata, saved.
    spot = UI.BigMap.home
    home = (spot.left, spot.top, 140, 140)
    assert f.IsShown(f) and rect(f) == home and f.GetFrameStrata(f) == "LOW"
    assert abs(UI.Camera.cam.zoom - 140 / SPAN_TILES) < 1e-9 and UI.Camera.follow
    sim.Step()
    assert tuple(saved.window[k] for k in ("left", "top", "w", "h")) == home and saved.zoom == UI.Camera.cam.zoom
    assert ns.Game.minimap.engaged  # (Game takes the Minimap under it)

    # L2: the border's edges claim 200 px; the view stops 2..6 px in, the zoom buttons clear of the grip.
    left, top, w, h = rect(f)
    vl, vt, vw, vh = rect(view)
    insets = (vl - left, top - vt, left + w - vl - vw, vt - vh - (top - h))
    assert all(2 <= i <= 6 for i in insets), insets
    zo, grip = box(ctl.zoomOut), box(c.grip)
    assert zo[1] >= grip[3] or zo[2] <= grip[0], (zo, grip)
    # Levels over the frame's (Core.lua:142-153); the template's own parts hidden.
    base = f.GetFrameLevel(f)
    assert [x.GetFrameLevel(x) - base for x in (c.border, c.band, c.controls, c.grip)] == [505, 515, 518, 520]
    assert not f.NineSlice.IsShown(f.NineSlice) and not f.CloseButton.IsShown(f.CloseButton)
    assert all(x.IsShown(x) for x in (view, c.border, c.band, c.controls, c.grip))

    # Title: at the screen's top, below the map; where you are, coordinates only while hovered.
    t = UI.Title
    text = lambda: (t.title.GetText(t.title), t.subtitle.GetText(t.subtitle))  # noqa: E731
    assert text() == ("Elwynn Forest", "Goldshire") and t.title.GetPoint(t.title)[2] == "BOTTOMLEFT"
    sim.MoveCursorTo(view)
    sim.Run(0.1)
    x, y = ns.Atlas.TileToMap(1429, ns.Model.you.col, ns.Model.you.row)
    assert text() == ("Elwynn Forest", "Goldshire" + SEP + "%.1f, %.1f" % (x * 100, y * 100))
    sim.subzone = "Lion's Pride Inn"  # the client's subzone (inside the inn), not the terrain chunk's area
    sim.FireEvent("ZONE_CHANGED_INDOORS")
    sim.Run(0.1)
    assert text() == ("Elwynn Forest", "Lion's Pride Inn" + SEP + "%.1f, %.1f" % (x * 100, y * 100))

    # Hover reveal: out over 0.15 s once the mouse leaves, in again as it comes back.
    alpha = lambda: ctl.mode.GetAlpha(ctl.mode)  # noqa: E731
    assert alpha() == 1 and c.controls.GetAlpha(c.controls) == 1
    sim.cursorX, sim.cursorY = 100, 100
    sim.Step(0.075)
    assert abs(alpha() - 0.5) < 1e-9
    sim.Run(0.1)
    assert alpha() == 0 and c.controls.GetAlpha(c.controls) == 0 and c.grip.GetAlpha(c.grip) == 0
    sim.MoveCursorTo(view)
    sim.Step(0.075)
    sim.Step(0.075)
    assert alpha() == 1 and abs(c.grip.GetAlpha(c.grip) - 0.8) < 1e-9

    # Tips: after 0.35 s, fading in over 0.12 s, gone after 2.5 s or on leaving.
    tip = ctl.tip
    sim.MoveCursorTo(ctl.follow)
    sim.FireScript(ctl.follow, "OnEnter", False)
    sim.Run(0.3)
    assert tip.IsShown(tip) and tip.GetAlpha(tip) == 0
    sim.Run(0.1)
    assert ctl.tipText.GetText(ctl.tipText) == "Following" and 0 < tip.GetAlpha(tip) < 1
    sim.Run(0.1)
    assert tip.GetAlpha(tip) == 1
    sim.Run(2.4)
    assert not tip.IsShown(tip)
    sim.FireScript(ctl.follow, "OnEnter", False)
    sim.Step()
    sim.FireScript(ctl.follow, "OnLeave", False)
    assert not tip.IsShown(tip)

    # A menu open keeps the controls shown (the gear's rows: test_gear.py).
    sim.Click(ctl.gear)
    sim.cursorX, sim.cursorY = 100, 100
    sim.Run(0.3)
    assert alpha() == 1 and sim.menu
    sim.menu = None
    sim.Run(0.3)
    assert alpha() == 0
    sim.MoveCursorTo(view)
    sim.Run(0.3)

    # Resizing the small window keeps the yards across it; away from the screen's top the title is above.
    zoom = UI.Camera.cam.zoom
    f.ClearAllPoints(f)
    f.SetPoint(f, "TOPLEFT", G.UIParent, "BOTTOMLEFT", 600, 800)
    f.SetSize(f, 280, 210)
    assert abs(UI.Camera.cam.zoom - zoom * 210 / 140) < 1e-9
    assert t.title.GetPoint(t.title)[2] == "TOPLEFT" and ctl.mode.GetPoint(ctl.mode)[2] == "TOPRIGHT"
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
