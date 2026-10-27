"""The settings window (ui/Feel.lua) on the simulated client: opened from the gear (Settings…) or /mm feel, built once,
a sidebar of categories and the page of the chosen one (the last kept: UI.saved.feelPage); a grouping slider sets its
tunable through UI.Cluster (saved as clusterTune), a tracking-line pick is saved in UI.saved.feel (Feel.Get returns it,
Feel.rev moves), a map slider reaches its setter live; Reset all clears both and the widgets follow; Escape
(UISpecialFrames) hides it; each page's settings apply and its Reset puts them back; the client's Settings entry
(game/Options.lua) opens it; no errors."""
import os

from test_addon import boot, errors
from test_gear import SETTINGS, gear, sub
from sim import TEST_UI, TESTS, harness
from sim import drawn as sim_drawn


def test_lookfeel():
    L, sim, ns = boot(TEST_UI)
    UI, saved = ns.UI, L.globals().MagicMap2DB.UI
    sim.Slash("/mm toggle")
    sim.Run(1)

    # From the gear: the window, shown, DIALOG strata, named for Escape, on General (the first); only that page built.
    root, _ = gear(sim, ns)
    sub(root, SETTINGS).onSelect()
    sim.Step()
    Feel, f = UI.Feel, UI.Feel.frame
    same = L.eval("function(a, b) return a == b end")
    assert f.IsShown(f) and f.GetFrameStrata(f) == "DIALOG" and same(sim.Named("MagicMapFeel"), f)
    assert list(Feel.pages.keys()) == ["general"] and saved.feelPage == "general"
    w = Feel.widgets
    assert w["general.follow"].check.GetChecked(w["general.follow"].check) is True

    # A category's row: its page shown and built, the last one's hidden, kept.
    sim.Click(_tab(L, Feel, "Grouping"))
    assert saved.feelPage == "group" and not Feel.pages["general"].IsShown(Feel.pages["general"])
    assert Feel.pages["group"].IsShown(Feel.pages["group"])
    assert w["group.range"].slider.GetValue(w["group.range"].slider) == 24 and w["group.range"].text.GetText(w["group.range"].text) == "24 px"
    rev = Feel.rev

    # A grouping slider: UI.Cluster's tunable, saved as clusterTune (as before), nothing in saved.feel.
    s = w["group.range"].slider
    s.SetValue(s, 33)  # (snapped to its step)
    assert UI.Cluster.Get("range") == 32 and saved.clusterTune.range == 32 and saved.feel is None
    assert Feel.Get("group.range") == 32 and w["group.range"].text.GetText(w["group.range"].text) == "32 px"

    # A tracking-line pick: the client's menu, a radio per style; saved in feel, Get returns it, rev moved.
    Feel.Open("path")
    w = Feel.widgets
    assert w["path.style"].button.GetText(w["path.style"].button) == "Dotted" and w["path.glow"].check.GetChecked(w["path.glow"].check)
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
    Feel.Open("map")
    w = Feel.widgets
    arrow = UI.You.arrow
    size = arrow.GetWidth(arrow)
    w["arrow.scale"].slider.SetValue(w["arrow.scale"].slider, 1.5)
    assert abs(arrow.GetWidth(arrow) - size * 1.5) < 1e-6 and saved.feel["arrow.scale"] == 1.5

    # Reset all: both stores cleared, the widgets back on the defaults, the arrow too.
    sim.Click(Feel.resetAll)
    assert saved.clusterTune is None and saved.feel is None and UI.Cluster.Get("range") == 24
    assert s.GetValue(s) == 24 and w["path.glow"].check.GetChecked(w["path.glow"].check) and abs(arrow.GetWidth(arrow) - size) < 1e-6

    # Escape hides it (the client's CloseSpecialWindows); /mm feel shows it again on the last page, the same frame.
    assert sim.Escape()[0] and not f.IsShown(f)
    sim.Slash("/mm feel")
    assert f.IsShown(f) and same(UI.Feel.frame, f) and saved.feelPage == "map"
    sim.Slash("/mm feel")
    assert not f.IsShown(f)
    sim.Slash("/mm feel icons")
    assert f.IsShown(f) and saved.feelPage == "icons"
    sim.Run(1)
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def _tab(L, Feel, title):
    """A sidebar row by its category's name."""
    return L.eval("""function(frame, title)
        for _, c in ipairs({ frame:GetChildren() }) do
            if c.text and c.sel and c.text:GetText() == title then return c end
        end
    end""")(Feel.frame, title)


def test_settings_pages_apply_and_reset():
    """Every page's sliders and checks apply (Get returns the new value, saved in feel; a switch of its owner's is the
    owner's) and its Reset (or Reset all) puts each back on its default, the saved table gone; every row has its tip."""
    L, sim, ns = boot(TEST_UI)
    UI, saved, Feel = ns.UI, L.globals().MagicMap2DB.UI, ns.UI.Feel
    sim.Slash("/mm toggle")
    sim.Run(1)
    pages = ["general", "map", "icons", "path", "areas", "group", "diag"]
    for p in pages:
        Feel.Open(p)
    assert sorted(Feel.pages.keys()) == sorted(pages)
    changed, defaults = [], {}
    for key, wd in Feel.widgets.items():
        k = wd.k
        assert k.tip and k.label, key
        if k.get or k.kind not in ("slider", "check"):
            continue  # (an owner's switch, an action, a pick: path.style's is above)
        default = defaults[key] = Feel.Get(key)
        v = (k.max if default != k.max else k.min) if k.kind == "slider" else not default
        Feel.Set(key, v)
        assert Feel.Get(key) == v, key
        changed.append(key)
    assert len(changed) > 25 and saved.feel is not None and saved.clusterTune is not None
    sim.Run(1)
    for p in pages:
        Feel.Reset(p)
    assert saved.feel is None and saved.clusterTune is None
    for key in changed:
        assert Feel.Get(key) == defaults[key], key
    # The same by Reset all.
    for key in changed:
        k = Feel.widgets[key].k
        default = Feel.Get(key)
        Feel.Set(key, (k.max if default != k.max else k.min) if k.kind == "slider" else not default)
    Feel.ResetAll()
    assert saved.feel is None and saved.clusterTune is None
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_blizzard_settings_entry():
    """The client's Settings API (stubbed: the sim lacks it): MagicMap registers a canvas and an add-on category;
    its button closes the client's Options and opens the window. Without the API, nothing is registered."""
    stub = """CALLS = {}
Settings = { RegisterCanvasLayoutCategory = function(panel, name) CALLS.canvas = { panel = panel, name = name }; return { name = name } end,
	RegisterAddOnCategory = function(cat) CALLS.addon = cat end }
SettingsPanel = CreateFrame("Frame")
SettingsPanel:Show()"""
    L, sim, ns = boot(TEST_UI)
    assert L.globals().Settings is None  # (the sim has none: game/Options.lua made nothing)
    G = L.globals()
    L.execute(stub)
    path = os.path.join(TESTS, "..", "..", "game", "Options.lua")  # (loaded again, now there is one)
    L.eval("function(path, ns) return assert(loadfile(path))('MagicMap', ns) end")(path, ns)
    assert G.CALLS.canvas.name == "MagicMap" and G.CALLS.addon.name == "MagicMap"
    panel = G.CALLS.canvas.panel
    panel.Show(panel)
    sim.Step()
    button = L.eval("""function(panel)
        for _, c in ipairs({ panel:GetChildren() }) do
            if c.GetText and c:GetText() == "Open MagicMap Settings" then return c end
        end
    end""")(panel)
    button.GetScript(button, "OnClick")(button)  # (the panel isn't placed: no cursor to click it with)
    sim.Step()
    f = ns.UI.Feel.frame
    assert f.IsShown(f)
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


# Every setting of ui/Feel.lua's KEYS but the buttons, each to a valid value other than its own: (key, value) sorted.
# KEYS is Feel's local: read through Feel.Get's upvalue BY_KEY (no hook in the addon for a test).
# But general.follow: the camera's state more than a setting (ui/Motion.lua's idle return follows you again 6 s
# after the map is left alone, as the MVP's MinimapMode.lua:20), so it doesn't hold even within a session.
CHANGED = """local SKIP = { ["general.follow"] = true }
return function(Feel)
    local by
    for i = 1, 50 do
        local name, v = debug.getupvalue(Feel.Get, i)
        if name == nil then break end
        if name == "BY_KEY" then by = v end
    end
    local out = {}
    for key, k in pairs(assert(by, "Feel.Get has no BY_KEY")) do
        local v, new = Feel.Get(key), nil
        if k.kind == "check" then
            new = not v
        elseif k.kind == "slider" then
            new = v + k.step <= k.max + 1e-9 and v + k.step or v - k.step
            new = math.floor(new * 1000 + 0.5) / 1000
        elseif k.kind == "pick" then
            local o = type(k.options) == "function" and k.options() or k.options
            for _, opt in ipairs(o) do
                if new == nil and opt[2] ~= v then new = opt[2] end
            end
        end
        if new ~= nil and not SKIP[key] then out[#out + 1] = { key, new } end
    end
    table.sort(out, function(a, b) return a[1] < b[1] end)
    return out
end"""


def _settings(ns, keys):
    return {k: ns.UI.Feel.Get(k) for k in keys}


def _drawn(T, sim, ns):
    """What's drawn, comparable across clients: (layer, key, name, icon, size, x, y), positions to 0.5 px."""
    out = []
    for d in sim_drawn(T, sim, ns):
        held = tuple(sorted((m["src"], str(m["key"])) for m in d.get("members", [])))
        out.append((d["layer"], str(d["key"]), d.get("name"), str(d.get("icon")), round(d["size"] * 2) / 2,
                    round(d["x"] * 2) / 2, round(d["y"] * 2) / 2, held))
    return sorted(out)


def _shown(sim, ns):
    """The map shown (/mm toggle if it isn't), laid out."""
    sim.Run(1)
    w = ns.UI.Window.frame
    if not w.IsShown(w):
        sim.Slash("/mm toggle")
    sim.Run(3)
    assert w.IsShown(w)


def test_reload_keeps_every_setting():
    """T3: every setting changed, logged out (PLAYER_LOGOUT), the saved data dumped and a fresh client booted from
    it as /reload enters (PLAYER_ENTERING_WORLD false, true): Feel.Get the same for every key, and the same pins
    drawn (T.Drawn)."""
    L, sim, ns = boot(TEST_UI)
    T = harness(L)
    sim.Slash("/mm toggle")
    sim.Run(1)
    changed = [(c[1], c[2]) for c in L.execute(CHANGED)(ns.UI.Feel).values()]
    assert len(changed) >= 30, changed
    for key, v in changed:
        ns.UI.Feel.Set(key, v)
    _shown(sim, ns)  # (Replace minimap off hides the map: /mm shows it)
    keys = [k for k, _ in changed]
    before = _settings(ns, keys)
    assert before == dict(changed), {k: (v, before[k]) for k, v in changed if before[k] != v}
    pins = _drawn(T, sim, ns)
    assert pins and not errors(sim, ns), errors(sim, ns)
    L0, sim0, ns0 = boot(TEST_UI)  # (the settings show in what's drawn: icon size, grouping)
    _shown(sim0, ns0)
    assert _drawn(harness(L0), sim0, ns0) != pins

    sim.FireEvent("PLAYER_LOGOUT")
    saved = "MagicMap2DB = " + L.eval("function(path) return assert(loadfile(path))() end")(
        os.path.join(TESTS, "replay.lua")).Dump(L.globals().MagicMap2DB)
    L2, sim2, ns2 = boot(saved, reload=True)
    T2 = harness(L2)
    _shown(sim2, ns2)
    after = _settings(ns2, keys)
    assert after == before, {k: (before[k], after[k]) for k in keys if after[k] != before[k]}
    assert _drawn(T2, sim2, ns2) == pins
    assert not errors(sim2, ns2), errors(sim2, ns2)
