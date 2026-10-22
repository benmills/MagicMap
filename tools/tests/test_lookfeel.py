"""The Look & feel dialog (ui/Feel.lua) on the simulated client: opened from the gear (Settings > Advanced >
Look & feel…) or /mm feel, built once; a grouping slider sets its tunable through UI.Cluster (saved as
clusterTune), a tracking-line pick is saved in UI.saved.feel (Feel.Get returns it, Feel.rev moves), a map
slider reaches its setter live; Reset all clears both and the widgets follow; Escape (UISpecialFrames) hides it;
no errors."""
from test_addon import boot, errors
from test_gear import FEEL, gear, sub
from sim import TEST_UI


def test_lookfeel():
    L, sim, ns = boot(TEST_UI)
    UI, saved = ns.UI, L.globals().MagicMap2DB.UI
    sim.Slash("/mm toggle")
    sim.Run(1)

    # From the gear: the dialog, shown, DIALOG strata, named for Escape; the widgets show the defaults.
    root, _ = gear(sim, ns)
    sub(sub(sub(root, "Settings"), "Advanced"), FEEL).onSelect()
    sim.Step()
    Feel, f = UI.Feel, UI.Feel.frame
    same = L.eval("function(a, b) return a == b end")
    assert f.IsShown(f) and f.GetFrameStrata(f) == "DIALOG" and same(sim.Named("MagicMapFeel"), f)
    w = Feel.widgets
    assert w["group.range"].slider.GetValue(w["group.range"].slider) == 24 and w["group.range"].text.GetText(w["group.range"].text) == "24 px"
    assert w["path.style"].button.GetText(w["path.style"].button) == "Dotted" and w["path.glow"].check.GetChecked(w["path.glow"].check)
    rev = Feel.rev

    # A grouping slider: UI.Cluster's tunable, saved as clusterTune (as before), nothing in saved.feel.
    s = w["group.range"].slider
    s.SetValue(s, 33)  # (snapped to its step)
    assert UI.Cluster.Get("range") == 32 and saved.clusterTune.range == 32 and saved.feel is None
    assert Feel.Get("group.range") == 32 and w["group.range"].text.GetText(w["group.range"].text) == "32 px"

    # A tracking-line pick: the client's menu, a radio per style; saved in feel, Get returns it, rev moved.
    sim.Click(w["path.style"].button)
    styles = {e.text: e for e in sim.MenuItems("radio").values()}
    assert list(styles) == ["Dotted", "Dashed", "Solid"] and styles["Dotted"].isSelected() is True
    styles["Dashed"].onSelect()
    assert Feel.Get("path.style") == "dashed" and saved.feel["path.style"] == "dashed" and Feel.rev > rev
    assert w["path.style"].button.GetText(w["path.style"].button) == "Dashed"
    # Back to the default: its key gone, the table with it.
    Feel.Set("path.style", "dotted")
    assert saved.feel is None

    # A check and a map slider: live. The arrow's size follows "arrow.scale"; the pills' alpha "pills.alpha".
    sim.Click(w["path.glow"].check)
    assert Feel.Get("path.glow") is False and saved.feel["path.glow"] is False
    arrow = UI.You.arrow
    size = arrow.GetWidth(arrow)
    w["arrow.scale"].slider.SetValue(w["arrow.scale"].slider, 1.5)
    assert abs(arrow.GetWidth(arrow) - size * 1.5) < 1e-6 and saved.feel["arrow.scale"] == 1.5

    # Reset all: both stores cleared, the widgets back on the defaults, the arrow too.
    sim.Click(Feel.resetAll)
    assert saved.clusterTune is None and saved.feel is None and UI.Cluster.Get("range") == 24
    assert s.GetValue(s) == 24 and w["path.glow"].check.GetChecked(w["path.glow"].check) and abs(arrow.GetWidth(arrow) - size) < 1e-6

    # Escape hides it (the client's CloseSpecialWindows); /mm feel shows it again, the same frame.
    assert sim.Escape()[0] and not f.IsShown(f)
    sim.Slash("/mm feel")
    assert f.IsShown(f) and same(UI.Feel.frame, f)
    sim.Slash("/mm feel")
    assert not f.IsShown(f)
    sim.Run(1)
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
