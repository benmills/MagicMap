"""Blizzard's mail indicator on our map while the takeover hides its cluster (#23, game/Chrome.lua), and our minimap
button as a LibDBIcon launcher for button collectors such as HidingBar (#24, game/Button.lua)."""
from sim import TEST_UI, errors, load as boot


def test_mail_indicator():
    """Engaged, Blizzard's IndicatorFrame hangs at our map's top right, shown; released, back where it was."""
    L, sim, ns = boot()
    sim.Slash("/mm toggle")
    sim.Run(1)
    G, same = L.globals(), L.eval("rawequal")
    f, host = G.MinimapCluster.IndicatorFrame, ns.UI.Chrome.indicators
    assert ns.Game.minimap.engaged and same(f.GetParent(f), host) and f.IsVisible(f)
    sim.Slash("/mm toggle")
    sim.Run(1)
    p, rel, _, x, y = f.GetPoint(f, 1)
    assert not ns.Game.minimap.engaged and same(f.GetParent(f), G.MinimapCluster)
    assert p == "TOPRIGHT" and same(rel, G.Minimap) and (x, y) == (24, -37)
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_launcher():
    """With LibDataBroker and LibDBIcon loaded by another addon, MagicMap is a launcher LibDBIcon draws (our own button
    hidden, our angle kept); its click toggles the map; the gear's switch hides it; our AddOns menu doesn't list it.
    Without them, our own button, named for a collector's grab."""
    L, sim, ns = boot(TEST_UI + "\nSim.LoadLDB()")
    G = L.globals()
    ours, icon = G.MagicMapMinimapButton, G.LibDBIcon10_MagicMap
    assert icon is not None and not ours.IsShown(ours)
    assert ns.Game.saved.ldbIcon.minimapPos is not None
    sim.Run(1)
    assert icon.IsShown(icon) or ns.Game.minimap.engaged  # (shown, or waiting on the stand-in with the rest)
    shown = ns.UI.Window.frame.IsShown(ns.UI.Window.frame)
    icon.Click(icon, "LeftButton")
    sim.Run(0.5)
    assert ns.UI.Window.frame.IsShown(ns.UI.Window.frame) != shown
    ns.UI.Feel.Set("general.button", False)
    sim.Run(0.5)
    assert ns.Game.saved.ldbIcon.hide is True
    rows = ns.Game.MinimapButtons() or L.table()
    assert all(r.id != "ldb:MagicMap" for r in rows.values())
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))

    L, sim, ns = boot()
    assert L.globals().MagicMapMinimapButton is not None and L.globals().LibDBIcon10_MagicMap is None
