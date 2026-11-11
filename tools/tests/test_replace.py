"""What MagicMap replaces (ui/Replace.lua, ui/Welcome.lua): the minimap and the world map, each on or off.
A new install replaces nothing and the first click on the button shows the welcome (Escape: nothing chosen,
it asks again; Continue: the recommended both, the small map on the Minimap's spot); an existing player is
migrated to what they had; each mode engages what it says: our small map shown from login (minimap: Blizzard's Minimap
ours only then), M ours (worldmap), the button opening our big map as a window of its own (neither), the Minimap cluster back exactly
when ours closes."""
from test_addon import boot, errors


def saved(replace):
    return "MagicMap2DB = { UI = { _v = 1, replace = { minimap = %s, worldmap = %s } } }" % tuple(str(r).lower() for r in replace)


def parts(L, sim):
    G = L.globals()
    return G, (lambda: G.WorldMapFrame.IsShown(G.WorldMapFrame)), (lambda: G.MinimapCluster.IsShown(G.MinimapCluster))


def button(L, sim, text):
    return L.eval("""function(Sim, text)
        for _, f in ipairs(Sim.Frames()) do
            if f.GetObjectType and f:GetObjectType() == "Button" and f:GetText() == text then return f end
        end
    end""")(sim, text)


def test_welcome_first_click():
    L, sim, ns = boot("MagicMap2DB = nil")
    UI = ns.UI
    G, world, cluster = parts(L, sim)
    win, welcome = UI.Window.frame, lambda: UI.Welcome.frame and UI.Welcome.frame.IsShown(UI.Welcome.frame)  # noqa: E731
    sim.Run(2)
    # A new install: nothing replaced, nothing of ours shown, the Minimap Blizzard's, no dialog at login.
    assert not UI.Replace.Chosen() and not UI.Replace.Get("minimap") and not UI.Replace.Get("worldmap")
    assert not win.IsShown(win) and not welcome() and cluster() and not ns.Game.minimap.engaged
    sim.Press("M")
    sim.Step()
    assert world() and not win.IsShown(win)  # M is Blizzard's
    sim.Press("M")
    ns.Game.Hooked("toggle")  # the button (or the compartment's entry)
    sim.Run(0.2)
    assert welcome() and not win.IsShown(win) and not UI.Replace.Chosen()
    assert sim.Escape()[0] and not welcome() and not UI.Replace.Chosen()  # Escape: no choice, nothing changed
    ns.Game.Hooked("toggle")
    sim.Run(0.2)
    assert welcome() and UI.Welcome.frame.TitleText.GetText(UI.Welcome.frame.TitleText) == "Welcome to MagicMap"
    sim.Click(button(L, sim, "Continue"))  # the recommended one: both
    sim.Run(1)
    assert UI.Replace.Chosen() and UI.Replace.Get("minimap") and UI.Replace.Get("worldmap") and not welcome()
    assert win.IsShown(win) and not UI.BigMap.big and ns.Game.minimap.engaged and ns.UI.saved.welcome is None
    sim.Press("M")
    sim.Run(0.5)
    assert UI.BigMap.big and not world()
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_migration():
    # 2.0 players keep what they had; a new install's second login isn't taken for one of them.
    L, sim, ns = boot("MagicMap2DB = { UI = { _v = 1, minimap = 'blizzard', worldmap = false } }")
    assert ns.UI.saved.replace.minimap is False and ns.UI.saved.replace.worldmap is False and ns.UI.saved.worldmap is None
    L, sim, ns = boot("MagicMap2DB = { UI = { _v = 1 } }")
    assert ns.UI.Replace.Get("minimap") and ns.UI.Replace.Get("worldmap")
    L, sim, ns = boot("MagicMap2DB = nil")
    sim.Run(1)
    from fixtures import lua_tools
    L2, sim2, ns2 = boot("MagicMap2DB = " + lua_tools(L).Dump(L.globals().MagicMap2DB))
    assert not ns2.UI.Replace.Chosen()


def test_modes():
    # minimap only: our small map from login, M is Blizzard's, the grow button still grows ours.
    L, sim, ns = boot(saved((True, False)))
    UI, big = ns.UI, ns.UI.BigMap
    G, world, cluster = parts(L, sim)
    win = UI.Window.frame
    sim.Run(2)
    assert win.IsShown(win) and ns.Game.minimap.engaged and not cluster()
    sim.Press("M")
    sim.Step()
    assert world() and not big.big
    sim.Press("M")
    sim.Click(UI.Controls.mode)
    sim.Run(0.5)
    assert big.big
    UI.Replace.Set("minimap", False)  # off, big: it stays till closed, then hidden (no small state)
    assert win.IsShown(win) and big.big
    assert sim.Escape()[0]
    sim.Run(0.5)
    assert not win.IsShown(win) and not ns.Game.minimap.engaged and cluster() and G.MinimapCluster.GetAlpha(G.MinimapCluster) == 1

    # world map only: hidden at login, Blizzard's minimap; M opens ours big, Escape hides it and gives the Minimap back.
    L, sim, ns = boot(saved((False, True)))
    UI, big = ns.UI, ns.UI.BigMap
    G, world, cluster = parts(L, sim)
    win = UI.Window.frame
    sim.Run(2)
    assert not win.IsShown(win) and cluster() and not ns.Game.minimap.engaged
    sim.Press("M")
    sim.Run(1)
    # (Blizzard's minimap left as it is: not replaced, ours never takes it)
    assert not world() and win.IsShown(win) and big.big and not ns.Game.minimap.engaged and cluster()
    assert sim.Escape()[0]
    sim.Run(1)
    assert not win.IsShown(win) and not big.big and cluster() and not ns.Game.minimap.engaged
    assert G.MinimapCluster.GetAlpha(G.MinimapCluster) == 1
    sim.Press("M")  # again, and M closes it
    sim.Run(1)
    assert big.big
    sim.Press("M")
    sim.Run(1)
    assert not win.IsShown(win) and cluster()
    UI.Replace.Set("minimap", True)  # live: the small map appears on the Minimap's spot
    sim.Run(1)
    assert win.IsShown(win) and not big.big and ns.Game.minimap.engaged

    # neither: Blizzard's both; the button opens and closes ours, big.
    L, sim, ns = boot(saved((False, False)))
    UI, big = ns.UI, ns.UI.BigMap
    G, world, cluster = parts(L, sim)
    win = UI.Window.frame
    sim.Run(2)
    sim.Press("M")
    sim.Step()
    assert world() and not win.IsShown(win)
    sim.Press("M")
    ns.Game.Hooked("toggle")
    sim.Run(1)
    assert win.IsShown(win) and big.big and not world() and not ns.Game.minimap.engaged and cluster()
    ns.Game.Hooked("toggle")
    sim.Run(1)
    assert not win.IsShown(win) and cluster() and not ns.Game.minimap.engaged
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
