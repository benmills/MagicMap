"""Small and big (ui/BigMap.lua) on the simulated client: M (Model.hooked "worldmap", as Game's hook
hands it on) or the red button grows the window to 0.7 of the screen, centred, HIGH, the minimap's
home corner faded out (View.window.homeAlpha), on you 1.5 further out but never past your zone (fit
0.92); M, the button or Escape (hooked "escape") shrink it back to its small rect and zoom. /mm reset
is refused while big. A still press while it grows is a click. Spike-bugs L3: M again mid-shrink
still comes back to the small rect. L4: logging out or hiding while big (moved meanwhile, or grown
mid-chase) keeps the small rect and zoom; a moved and sized window stays put through hiding and a
reload."""
from test_addon import boot, errors
from test_blips import lua_tools
from test_chrome import SEP, fresh, rect


def near(a, b, px=1):
    return all(abs(x - y) <= px for x, y in zip(a, b))


def test_bigmap():
    L, sim, ns = fresh()
    UI, G = ns.UI, L.globals()
    f, big, view, cam = UI.Window.frame, UI.BigMap, UI.View(), lambda: UI.Camera.cam  # noqa: E731
    saved = G.MagicMap2DB.UI
    t = UI.Title
    sim.Run(0.5)
    small, zoom = rect(f), cam().zoom

    # M: big, HIGH, centred at 0.7 of the screen, the home corner faded; on you, further out.
    sim.Press("M")  # Game hides Blizzard's map again: "worldmap" through Model the next frame
    sim.Step()
    assert big.big and view.window.big and f.GetFrameStrata(f) == "HIGH"
    sim.Run(0.4)
    assert near(rect(f), (288, 918, 1344, 756), 1e-6) and view.window.homeAlpha == 0
    assert abs(cam().zoom - zoom / 1.5) < 1e-9 and UI.Camera.follow
    x, y = ns.Atlas.TileToMap(1429, ns.Model.you.col, ns.Model.you.row)
    sim.cursorX, sim.cursorY = 10, 10
    sim.Run(0.1)
    assert t.subtitle.GetText(t.subtitle) == "Goldshire" + SEP + "%.1f, %.1f" % (x * 100, y * 100)  # big: coordinates
    sim.Slash("/mm reset")
    assert sim.prints[len(sim.prints)].endswith("reset: shrink the map back first (M)") and big.big

    # Escape: back to the small rect and zoom, the minimap's strata, the home corner back.
    assert sim.Escape()[0]  # Game's catcher: "escape"
    sim.Run(0.4)
    assert not big.big and rect(f) == small and abs(cam().zoom - zoom) < 1e-9 and f.GetFrameStrata(f) == "LOW"
    assert view.window.homeAlpha == 1 and not view.window.big
    assert not sim.Escape()[0]  # small: nothing
    sim.Run(0.3)
    assert rect(f) == small

    # L3: M, M mid-shrink, M, M: back on the small rect.
    for wait in (0.5, 0.05, 1, 1):
        sim.Press("M")
        sim.Run(wait)
    assert near(rect(f), small) and not big.big and abs(cam().zoom - zoom) < 1e-9

    # Your zone (you.uiMap: Elwynn Forest) bounds the zoom out; the red button grows and shrinks too.
    UI.Camera.cam = L.table_from({"cx": cam().cx, "cy": cam().cy, "zoom": 150})
    assert ns.Model.you.uiMap == 1429  # (game/parts/You.lua)
    sim.Click(UI.Controls.mode)
    sim.Run(0.4)
    r = ns.Atlas.MapRect(1429)
    vw, vh = UI.Window.Size()
    fit = min(vw / (r.col1 - r.col0), vh / (r.row1 - r.row0)) * 0.92
    assert big.big and fit > 150 / 1.5 and abs(cam().zoom - fit) < 1e-9
    sim.Click(UI.Controls.mode)
    sim.Run(0.4)
    assert not big.big and near(rect(f), small) and abs(cam().zoom - 150) < 1e-9

    # A still press while it grows is a click: the window moving under the cursor isn't a drag.
    sim.Press("M")
    sim.Step()
    sim.MoveCursorTo(UI.Window.view)
    sim.buttonsDown["LeftButton"] = True
    sim.FireScript(UI.Window.view, "OnMouseDown", "LeftButton")
    sim.Run(0.2)
    sim.buttonsDown["LeftButton"] = None
    sim.FireScript(UI.Window.view, "OnMouseUp", "LeftButton")
    assert UI.Camera.follow and not UI.Motion.Dragging()
    sim.Press("M")
    sim.Run(0.4)
    assert not big.big and near(rect(f), small) and abs(cam().zoom - 150) < 1e-9

    # L4: logging out while big keeps the small rect and the zoom a wheel's chase was headed for, though
    # the big window was dragged; hidden while big, it comes back small.
    sim.Wheel(UI.Window.view, -1)
    sim.Step()
    sim.Press("M")
    sim.Run(0.4)
    sim.FireScript(f, "OnDragStart", "LeftButton")
    f.ClearAllPoints(f)
    f.SetPoint(f, "TOPLEFT", G.UIParent, "BOTTOMLEFT", 300, 950)
    sim.FireScript(f, "OnDragStop")
    sim.FireEvent("PLAYER_LOGOUT")
    goal = 150 / 1.3
    assert near(tuple(saved.window[k] for k in ("left", "top", "w", "h")), small) and abs(saved.zoom - goal) < 1e-9
    sim.Slash("/mm toggle")
    assert not f.IsShown(f) and not big.big and near(rect(f), small) and abs(cam().zoom - goal) < 1e-9
    sim.Slash("/mm toggle")
    sim.Run(0.2)
    assert f.IsShown(f) and near(rect(f), small) and f.GetFrameStrata(f) == "LOW" and view.window.homeAlpha == 1

    # Moved and sized, it stays put through hiding and showing, and a reload.
    f.ClearAllPoints(f)
    f.SetPoint(f, "TOPLEFT", G.UIParent, "BOTTOMLEFT", 600, 800)
    f.SetSize(f, 240, 240)
    UI.Window.Moved()
    zoom = cam().zoom
    sim.Slash("/mm toggle")
    sim.Slash("/mm toggle")
    sim.Run(0.2)
    assert rect(f) == (600, 800, 240, 240)
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
    sim.FireEvent("PLAYER_LOGOUT")
    L2, sim2, ns2 = boot("MagicMap2DB = " + lua_tools(L).Dump(G.MagicMap2DB))
    sim2.Run(0.2)
    f2 = ns2.UI.Window.frame
    assert f2.IsShown(f2) and rect(f2) == (600, 800, 240, 240) and abs(ns2.UI.Camera.cam.zoom - zoom) < 1e-9
    assert not errors(sim2, ns2), "\n\n".join(errors(sim2, ns2))
