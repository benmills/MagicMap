"""The window's chrome on the simulated client (ui/Window.lua, Chrome.lua, Controls.lua, Title.lua,
Menus.lua): a first login shows it on the minimap's spot, square, 200 yd across, at the minimap's
strata; Forever's oversized edge atlases (spike-bugs L2) leave the view's inset at 2..6 px and the
zoom buttons clear of the grip; the template's own parts are hidden; the controls fade in and out
over 0.15 s (kept while a menu is open); the tips; the title; resizing keeps the yards across (the
gear's rows: test_gear.py)."""
import time

from test_addon import boot, errors

SPAN_TILES = 200 / (1600 / 3)  # 200 yd across the small window (MinimapMode.lua:25)
SEP = "  \u00b7  ".encode("utf-8").decode("latin-1")  # the title's joins, as the sim's Lua (latin-1) reads them


def fresh():
    """A first login (no saved data): Game reads the minimap's spot, the sim's Minimap's rect
    (obs.minimap.home, with its cluster's strata), and Model hands it on to BigMap.home."""
    L, sim, ns = boot("MagicMap2DB = { UI = { _v = 1 } }")
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

    # Tips: after 0.35 s, a GameTooltip of the button's name alone, right of it (ui/Tip.lua's Label); gone on leaving.
    tip = G.GameTooltip
    sim.MoveCursorTo(ctl.zoomIn)
    sim.FireScript(ctl.zoomIn, "OnEnter", False)
    sim.Run(0.3)
    assert not tip.IsOwned(tip, ctl.zoomIn)
    sim.Run(0.1)
    assert tip.IsShown(tip) and tip.IsOwned(tip, ctl.zoomIn) and tip.NumLines(tip) == 1
    assert sim.state[tip.GetLeftLine(tip, 1)].text == "Zoom in"
    sim.FireScript(ctl.zoomIn, "OnLeave", False)
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


def test_title_pieces():
    """The title's pieces (#19), as its settings page (Frame title) chooses and orders them, at rest and on hover, the first the
    title: the local and the server's time (Game's: Model.clock) as Blizzard's clock shows them (its 24-hour box) or as
    set; day or night, the minimap's own picture; coordinates first. The defaults are today's text (test_chrome)."""
    L, sim, ns = boot()
    G, UI = L.globals(), ns.UI
    t, Feel, view = UI.Title, UI.Feel, UI.Window.view
    text = lambda: (t.title.GetText(t.title), t.subtitle.GetText(t.subtitle))  # noqa: E731
    now = 1792077412
    G.time = L.eval("function() return %d end" % now)
    sim.gameTime[1], sim.gameTime[2] = 20, 7  # (night)
    sim.Slash("/mm toggle")
    sim.cursorX, sim.cursorY = 1, 1
    sim.Run(1.5)
    assert text() == ("Elwynn Forest", "Goldshire")

    lt = time.localtime(now)
    h12 = "%d:%02d %s" % (lt.tm_hour % 12 or 12, lt.tm_min, "AM" if lt.tm_hour < 12 else "PM")
    Feel.Set("title.rest", "daynight,zone,server,time")
    sim.Run(1.5)
    assert text() == ("|A:UI-HUD-Minimap-NightCycle:14:14|a", "Elwynn Forest" + SEP + "8:07 PM" + SEP + h12)
    ring, same = t.ring, L.eval("rawequal")  # Diel.lua's gold ring round the picture: the title's first, at its left
    p = ring.GetPoint(ring, 1)
    assert ring.IsShown(ring) and ring.GetAtlas(ring) == "UI-HUD-Minimap-Frame-Cycle"
    assert same(p[1], t.title) and (p[0], p[2], p[3], p[4]) == ("CENTER", "LEFT", 7, 0)
    sim.cvars.timeMgrUseMilitaryTime = "1"  # Blizzard's clock at 24 hours
    sim.gameTime[1] = 9
    sim.Run(1.5)
    h24 = "%d:%02d" % (lt.tm_hour, lt.tm_min)
    assert text() == ("|A:UI-HUD-Minimap-DayCycle:14:14|a", "Elwynn Forest" + SEP + "9:07" + SEP + h24)
    Feel.Set("title.clock", "12")
    sim.Run(0.1)
    assert text()[1] == "Elwynn Forest" + SEP + "9:07 AM" + SEP + h12
    Feel.Set("title.rest", "zone,subzone,daynight")  # in the subtitle: the ring follows the picture there
    sim.Run(0.1)
    p = ring.GetPoint(ring, 1)
    assert ring.IsShown(ring) and same(p[1], t.subtitle) and p[3] > 7
    Feel.Set("title.rest", "zone,subzone")
    sim.Run(0.1)
    assert not ring.IsShown(ring)

    # On hover: coordinates first, then the zone.
    Feel.Set("title.hover", "coords,zone")
    sim.MoveCursorTo(view)
    sim.Run(0.1)
    x, y = ns.Atlas.TileToMap(1429, ns.Model.you.col, ns.Model.you.row)
    assert text() == ("%.1f, %.1f" % (x * 100, y * 100), "Elwynn Forest")
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
