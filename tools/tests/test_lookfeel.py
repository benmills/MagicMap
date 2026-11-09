"""The settings window (ui/Feel.lua) on the simulated client: opened from the gear (Settings…) or /mm feel, built once,
a sidebar of pages and the chosen one (the last kept: UI.saved.feelPage); each kind of row works and resets: a slider
(its steppers, its live value), a toggle, the client's dropdown, colour swatches and the client's colour picker (a
custom "#rrggbb"), a list (chosen and ordered: a page declared once the window is built); rows shown only while what
they depend on is on; a row's undo mark, a page's Reset and Reset all lit only while there's something to reset;
Escape (UISpecialFrames) hides it; the client's Settings entry (game/Options.lua) opens it; every page laid out tidy
(rows inside the page, labels within their column, nothing overlapping), on the client's controls' art and without
it; the rule (ui/Feel.lua's header): every setting read or saved is declared, with a page, a tip and a default;
every setting kept across a /reload. No errors."""
import os
import re

from test_addon import boot, errors
from test_gear import SETTINGS, gear, sub
from sim import TEST_LOOK, TEST_UI_DEFAULTS, TESTS, harness
from sim import drawn as sim_drawn

ROOT = os.path.join(TESTS, "..", "..")


def _open(sim, ns):
    sim.Slash("/mm toggle")
    sim.Run(1)
    return ns.UI.Feel


def _tab(L, Feel, title):
    """A sidebar row by its page's title."""
    return L.eval("""function(frame, title)
        for _, c in ipairs({ frame:GetChildren() }) do
            if c.text and c.sel and c.text:GetText() == title then return c end
        end
    end""")(Feel.frame, title)


def _shown(f):
    return f.IsShown(f)


def test_lookfeel():
    L, sim, ns = boot(TEST_UI_DEFAULTS)
    UI, saved = ns.UI, L.globals().MagicMap2DB.UI
    _open(sim, ns)

    # From the gear: the window, shown, DIALOG strata, named for Escape, on General (the first); only that page built.
    root, _ = gear(sim, ns)
    sub(root, SETTINGS).onSelect()
    sim.Step()
    Feel, f = UI.Feel, UI.Feel.frame
    same = L.eval("function(a, b) return a == b end")
    assert _shown(f) and f.GetFrameStrata(f) == "DIALOG" and same(sim.Named("MagicMapFeel"), f)
    assert list(Feel.pages.keys()) == ["general"] and saved.feelPage == "general"
    w = Feel.widgets
    assert w["general.follow"].check.GetChecked(w["general.follow"].check) is True
    assert not Feel.resets.general.IsEnabled(Feel.resets.general) and not Feel.resetAll.IsEnabled(Feel.resetAll)

    # A page's row: its page shown and built, the last one's hidden, kept. The progress bar off: its opacity's and
    # colour's rows hidden; on, shown.
    sim.Click(_tab(L, Feel, "Quest pill"))
    assert saved.feelPage == "pills" and not _shown(Feel.pages["general"]) and _shown(Feel.pages["pills"])
    Feel.Set("pills.questBar", False)
    r = w["pills.barAlpha"]
    assert not _shown(r.row) and not _shown(w["pills.barColor"].row)
    sim.Click(w["pills.questBar"].check)
    assert Feel.Get("pills.questBar") is True and _shown(r.row) and _shown(w["pills.barColor"].row)
    # A slider: its value beside it; the undo mark and Reset lit.
    r = w["pills.alpha"]
    s, text = r.slider, r.text
    assert abs(s.GetValue(s) - 0.35) < 1e-9 and text.GetText(text) == "35%" and not _shown(r.undo)
    s.SetValue(s, 0.52)  # (snapped to its step)
    assert abs(Feel.Get("pills.alpha") - 0.5) < 1e-9 and text.GetText(text) == "50%" and _shown(r.undo)
    assert Feel.resets.pills.IsEnabled(Feel.resets.pills) and Feel.resetAll.IsEnabled(Feel.resetAll)
    sim.Click(r.steps[2])  # the forward stepper: a step on
    assert abs(Feel.Get("pills.alpha") - 0.55) < 1e-9 and text.GetText(text) == "55%"
    sim.Click(r.undo)  # back to its default
    assert abs(Feel.Get("pills.alpha") - 0.35) < 1e-9 and not _shown(r.undo) and abs(s.GetValue(s) - 0.35) < 1e-9
    rev = Feel.rev

    # The tracking line's style: the client's dropdown, a radio per style; saved in feel, Get returns it, rev moved.
    Feel.Open("path")
    style = w["path.style"].drop
    assert style.Text.GetText(style.Text) == "Dashed" and not w["path.glow"].check.GetChecked(w["path.glow"].check)
    sim.Click(style)
    styles = {e.text: e for e in sim.MenuItems("radio").values()}
    assert list(styles) == ["Dotted", "Dashed", "Solid"] and styles["Dashed"].isSelected() is True
    sim.Pick(styles["Dotted"])
    assert sim.menu is None and Feel.Get("path.style") == "dotted" and saved.feel["path.style"] == "dotted" and Feel.rev > rev
    assert style.Text.GetText(style.Text) == "Dotted" and _shown(w["path.style"].undo)
    Feel.Set("path.style", "dashed")  # back to the default: its key gone, the table with it, the dropdown back
    assert saved.feel is None and style.Text.GetText(style.Text) == "Dashed"

    # Its colour: a swatch a preset, the chosen one ringed gold; Custom… the client's colour picker, a "#rrggbb"
    # shown in a swatch of its own; cancelled, the colour it had.
    color = w["path.color"]
    ring = lambda sw: sw.SwatchBg.GetVertexColor(sw.SwatchBg)[:3]  # noqa: E731
    swatch = {sw.value: sw for sw in color.swatches.values()}
    assert list(swatch) == ["Parchment", "Gold", "White", "Sky", "Mint", "Rose"]
    assert ring(swatch["Gold"]) == (1, 0.82, 0) and ring(swatch["Sky"]) == (1, 1, 1) and not _shown(color.custom)
    sim.Click(swatch["Sky"])
    assert Feel.Get("path.color") == "Sky" and ring(swatch["Sky"]) == (1, 0.82, 0) and ring(swatch["Gold"]) == (1, 1, 1)
    picker = L.globals().ColorPickerFrame
    sim.Click(color.pick)
    assert _shown(picker) and Feel.Get("path.color") == "Sky"  # (opening sets the colour it opens on: kept)
    sim.PickColor(0.2, 0.4, 0.6)
    assert Feel.Get("path.color") == "#336699" and _shown(color.custom) and ring(swatch["Sky"]) == (1, 1, 1)
    sim.ColorCancel()
    assert Feel.Get("path.color") == "Sky" and not _shown(picker) and not _shown(color.custom)
    sim.Click(color.pick)
    sim.PickColor(0.2, 0.4, 0.6)
    sim.ColorOkay()
    assert saved.feel["path.color"] == "#336699" and ns.UI.Feel.RGB(ns.UI.Path.COLORS, "#336699")[1][2] == 0.4
    sim.Click(color.undo)
    assert Feel.Get("path.color") == "Gold" and saved.feel is None

    # A row that depends on another: the outline's colour only while the outline is on.
    edge = w["path.edgeColor"].row
    assert not _shown(edge)
    sim.Click(w["path.edge"].check)
    assert Feel.Get("path.edge") is True and _shown(edge)

    # A check and a map slider: live. The arrow's size follows "arrow.scale".
    sim.Click(w["path.glow"].check)
    assert Feel.Get("path.glow") is True and saved.feel["path.glow"] is True
    Feel.Open("map")
    arrow = UI.You.arrow
    size = arrow.GetWidth(arrow)
    w["arrow.scale"].slider.SetValue(w["arrow.scale"].slider, 1.5)
    assert abs(arrow.GetWidth(arrow) - size * 1.5) < 1e-6 and saved.feel["arrow.scale"] == 1.5
    reset = Feel.resets.map
    sim.Click(reset)  # this page's: the arrow back, the line's glow left
    assert abs(arrow.GetWidth(arrow) - size) < 1e-6 and saved.feel["path.glow"] is True and not reset.IsEnabled(reset)

    # Reset all: every page's, the widgets back on the defaults (the outline's colour hidden again).
    sim.Click(Feel.resetAll)
    assert saved.clusterTune is None and saved.feel is None and not Feel.resetAll.IsEnabled(Feel.resetAll)
    assert not w["path.glow"].check.GetChecked(w["path.glow"].check) and not _shown(edge)

    # Escape hides it (the client's CloseSpecialWindows); /mm feel shows it again on the last page, the same frame.
    assert sim.Escape()[0] and not _shown(f)
    sim.Slash("/mm feel")
    assert _shown(f) and same(UI.Feel.frame, f) and saved.feelPage == "map"
    sim.Slash("/mm feel")
    assert not _shown(f)
    sim.Slash("/mm feel pins")
    assert _shown(f) and saved.feelPage == "pins"
    sim.Run(1)
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


# A page declared once the window is built (as a feature that loads late would): its tab added in order, the window
# as tall as its pages need; a list setting (chosen and ordered, its options' icons) and a select whose options
# come from a function and carry icons; a row shown while a function says; a default another setting gives.
LATE = """local Sim, ns = ...
local Feel = ns.UI.Feel
for i = 1, 3 do Feel.Page({ key = "late" .. i, title = "Late " .. i, icon = "Interface\\\\Icons\\\\INV_Misc_Map_01", order = 80 + i }) end
Feel.Page({ key = "order", title = "Order", icon = "Interface\\\\Icons\\\\INV_Misc_Map_01", order = 25, tip = "A test page." })
Feel.Add("order", "Shown", {
	{ key = "order.what", kind = "list", ordered = true, label = "Lines", default = "zone,quest", tip = "What shows, in order.",
		options = { { "Zone", "zone", "A:checkmark-minimal" }, { "Quest", "quest", 134400 }, { "Coords", "coords" } } },
	{ key = "order.icon", kind = "select", label = "Icon", default = "a", tip = "An icon.",
		options = function() return { { "First", "a", 134400 }, { "Second", "b", "A:checkmark-minimal" } } end },
	{ key = "order.more", kind = "toggle", label = "More", default = false, tip = "Shown while Coords is chosen.",
		when = function() for _, v in ipairs(Feel.List("order.what")) do if v == "coords" then return true end end end },
	{ key = "order.size", kind = "slider", label = "Size", min = 0.5, max = 2, step = 0.05, pct = true, tip = "Icon size's, till set.",
		default = function() return Feel.Get("icons.scale") end, apply = function(v) ns.lateSize = v end },
})
"""


def test_settings_kinds_and_late_pages():
    L, sim, ns = boot(TEST_UI_DEFAULTS)
    Feel, saved = _open(sim, ns), L.globals().MagicMap2DB.UI
    Feel.Open("general")
    h = Feel.frame.GetHeight(Feel.frame)
    L.execute(LATE, sim, ns)
    titles = [p.title for p in Feel.Pages().values()]
    assert titles[:4] == ["General", "Map", "Frame title", "Order"] and titles[-1] == "Diagnostics" and len(titles) == 13
    assert Feel.frame.GetHeight(Feel.frame) == h  # (room for 14 in the sidebar: 13 fit as it is)
    sim.Click(_tab(L, Feel, "Order"))
    w = Feel.widgets
    lst, more = w["order.what"], w["order.more"].row
    lines = lambda: [(re.sub(r"\|[AT].*?\|[at]  ", "", ln.text.GetText(ln.text)), ln.check.GetChecked(ln.check))  # noqa: E731
                     for ln in lst.lines.values()]
    assert lines() == [("Zone", True), ("Quest", True), ("Coords", False)] and not _shown(more)
    sim.Click(lst.lines[3].check)  # Coords chosen: last; the row that waits on it shown
    assert Feel.Get("order.what") == "zone,quest,coords" and _shown(more) and saved.feel["order.what"] == "zone,quest,coords"
    assert list(Feel.List("order.what").values()) == ["zone", "quest", "coords"]
    up = lst.lines[3].up
    assert _shown(up) and not _shown(lst.lines[1].up) and not _shown(lst.lines[3].down)
    sim.Click(up)  # Coords before Quest
    assert Feel.Get("order.what") == "zone,coords,quest" and lines()[1] == ("Coords", True)
    sim.Click(lst.lines[1].check)  # Zone off: to the end, unchosen
    assert Feel.Get("order.what") == "coords,quest" and lines() == [("Coords", True), ("Quest", True), ("Zone", False)]
    icon = w["order.icon"].drop
    sim.Click(icon)
    radios = list(sim.MenuItems("radio").values())
    assert [r.text for r in radios] == ["|T134400:16:16:0:0:64:64:5:59:5:59|t  First", "|A:checkmark-minimal:16:16|a  Second"]
    sim.Pick(radios[1])
    assert Feel.Get("order.icon") == "b" and icon.Text.GetText(icon.Text).endswith("Second")
    sim.Click(Feel.resets.order)
    assert saved.feel is None and lines()[:2] == [("Zone", True), ("Quest", True)] and not _shown(more)
    assert Feel.Get("order.icon") == "a"
    # A saved value no longer offered is dropped at load (an option gone, a slider's out of range, a wrong type).
    saved.feel = L.table_from({"path.style": "plaid", "path.color": "Plaid", "arrow.scale": 9, "sea.on": "yes",
                               "icons.scale": 0.8, "ring.color": "#abcdef", "gone.key": 1})
    Feel.Loaded()
    assert dict(saved.feel.items()) == {"icons.scale": 0.8, "ring.color": "#abcdef", "gone.key": 1}
    # An override inheriting another setting: its row and apply follow that one until it's set; its undo hands it back.
    Feel.ResetAll()
    size = w["order.size"].slider
    Feel.Set("icons.scale", 1.2)
    assert abs(size.GetValue(size) - 1.2) < 1e-9 and ns.lateSize == 1.2 and saved.feel["order.size"] is None
    Feel.Set("order.size", 0.8)
    Feel.Set("icons.scale", 1.1)
    assert Feel.Get("order.size") == 0.8 and ns.lateSize == 0.8 and _shown(w["order.size"].undo)
    sim.Click(w["order.size"].undo)
    assert Feel.Get("order.size") == 1.1 and ns.lateSize == 1.1 and abs(size.GetValue(size) - 1.1) < 1e-9
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_settings_pages_apply_and_reset():
    """Every page's settings apply (Get returns the new value, saved in feel; Grouping's in clusterTune) and its Reset
    (or Reset all) puts each back on its default, the saved table gone; an owner's switch stays as it is. On a
    client without the settings panel's art (its checkbox, slider, divider, the undo icon): the old files', no
    errors."""
    L, sim, ns = boot(TEST_UI_DEFAULTS)
    for a in ("checkbox-minimal", "Minimal_SliderBar_Button", "common-icon-undo", "auctionhouse-ui-filter-redx",
              "Options_HorizontalDivider", "minimal-scrollbar-arrow-top"):
        sim.atlases[a] = None
    Feel, saved = _open(sim, ns), L.globals().MagicMap2DB.UI
    pages = [p.key for p in Feel.Pages().values()]
    assert pages == ["general", "map", "title", "pins", "pills", "tracking", "path", "areas", "diag"]
    for p in pages:
        Feel.Open(p)
    assert sorted(Feel.pages.keys()) == sorted(pages)
    other = L.eval("""function(Feel, k)
        local v = Feel.Get(k.key)
        if k.kind == "toggle" then return not v end
        if k.kind == "slider" then return v ~= k.max and k.max or k.min end
        local list = k.options or k.colors
        if type(list) == "function" then list = list() end
        for _, o in ipairs(list) do if o[1] ~= v and o[2] ~= v then return k.colors and o[1] or o[2] end end
    end""")
    changed = []
    defaults = {k.key: Feel.Get(k.key) for k in Feel.Entries().values()}  # (before any: an inherited one follows another)
    for k in Feel.Entries().values():
        if k.keep or k.kind == "button" or k.page is False:  # (no page: no page's Reset)
            continue
        v = other(Feel, k)
        Feel.Set(k.key, v)
        assert Feel.Get(k.key) == v, k.key
        changed.append(k.key)
    assert len(changed) > 40 and saved.feel is not None
    switch = saved.cluster
    sim.Run(1)
    for p in pages:
        Feel.Reset(p)
    assert saved.feel is None and saved.cluster == switch
    for key in changed:
        assert Feel.Get(key) == defaults[key], key
    for key in changed:  # the same by Reset all
        Feel.Set(key, other(Feel, Feel.Entry(key)))
    Feel.ResetAll()
    assert saved.feel is None
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_settings_layout():
    """Each page as the client lays it out (the sim's anchors): every shown row inside the page's width, under the
    one before it; a row's label within its column (the sim's text widths) and its controls inside the row; the
    sidebar's titles within it. The longest page fits without scrolling; Pins with every row opened (+) scrolls, its
    rows within its width (#16: that page alone)."""
    L, sim, ns = boot(TEST_UI_DEFAULTS)
    Feel = _open(sim, ns)
    pages = [(p, False) for p in Feel.Pages().values()]
    pages.append((next(p for p in Feel.Pages().values() if p.key == "pins"), True))
    for p, opened in pages:
        if p.key in ("path", "pills"):  # (every row shown: their dependents' switches on)
            for k in Feel.Entries().values():
                if k.page == p.key and k.kind == "toggle":
                    ns.UI.Feel.Set(k.key, True)
        Feel.Open(p.key)
        if opened:  # Pins with every family and type opened (+): its rows fit, the page scrolls (#16: this page alone)
            n = 0
            for w in Feel.widgets.values():
                if w.opener and w.k.page == "pins":
                    w.opener.Click(w.opener)
                    n += 1
            assert n >= 18, n
        bad = L.eval("""function(Feel, p, Rect, opened)
            local out = {}
            local page = Feel.pages[p.key]
            local pl, pb, pw, ph = Rect(page)
            if opened then pb, ph = -1e9, 2e9 end -- (scrolled: the rows past its foot inside its width)
            local function inside(what, r, l, b, w, h)
                local x, y, rw, rh = Rect(r)
                if not x then out[#out + 1] = what .. ": no rect"; return end
                if x < l - 0.5 or y < b - 0.5 or x + rw > l + w + 0.5 or y + rh > b + h + 0.5 then
                    out[#out + 1] = string.format("%s: %.1f,%.1f %.1fx%.1f outside %.1f,%.1f %.1fx%.1f", what, x, y, rw, rh, l, b, w, h)
                end
            end
            local last
            for _, it in ipairs(p.items) do
                local name = it.header or it.k.key
                if it.f:IsShown() then
                    local rl, rb, rw, rh = Rect(it.f)
                    inside(name, it.f, pl, pb, pw, ph)
                    if last and rb + rh > last + 0.5 then out[#out + 1] = name .. ": over the one before" end
                    last = rb
                    for _, r in ipairs({ it.f:GetChildren() }) do
                        if r:IsShown() then inside(name .. " control", r, rl, rb, rw, rh) end
                    end
                    local label = it.w and it.w.label
                    if label and label:GetStringWidth() > label:GetWidth() then out[#out + 1] = name .. ": label too long" end
                end
            end
            local scrolls = Feel.pages[p.key] and p.bar and p.bar:IsShown()
            if scrolls and not opened then out[#out + 1] = p.key .. ": scrolls" end
            if opened and not scrolls then out[#out + 1] = p.key .. ": opened, yet no scroll" end
            local tw = p.tab.text:GetStringWidth() + 30
            if tw > p.tab:GetWidth() then out[#out + 1] = p.key .. ": tab title too long" end
            return out
        end""")(Feel, p, sim.Rect, opened)
        assert not list(bad.values()), (p.key, opened, list(bad.values()))
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_blizzard_settings_entry():
    """The client's Settings API (stubbed: the sim lacks it): MagicMap registers a canvas and an add-on category;
    its button closes the client's Options and opens the window. Without the API, nothing is registered."""
    stub = """CALLS = {}
Settings = { RegisterCanvasLayoutCategory = function(panel, name) CALLS.canvas = { panel = panel, name = name }; return { name = name } end,
	RegisterAddOnCategory = function(cat) CALLS.addon = cat end }
SettingsPanel = CreateFrame("Frame")
SettingsPanel:Show()"""
    L, sim, ns = boot(TEST_UI_DEFAULTS)
    assert L.globals().Settings is None  # (the sim has none: game/Options.lua made nothing)
    G = L.globals()
    L.execute(stub)
    path = os.path.join(ROOT, "game", "Options.lua")  # (loaded again, now there is one)
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


# Feel.Get("...") / Feel.Set("...") (or F.Get, UI.Feel.Get) with a literal key, in the addon's code (a key built
# from parts, "areas." .. k, is the run's to check: below).
LITERAL = re.compile(r"""\b(?:Feel|F)\.(?:Get|Set|Default|List)\(\s*["']([\w.]+)["']\s*[,)]""")


def test_settings_declared():
    """The rule (ui/Feel.lua's header; docs/development.md "How to add a setting"): every key the code reads or sets
    by name (a literal in ui/ or game/, the tests' saved look: sim.TEST_LOOK), and every key read while the map
    and every page are shown, is declared; every declared setting has a page there is, a label and a tip, and but
    an action a default its control can show (a slider's on its range and step, a select's or colour's offered)."""
    L, sim, ns = boot(TEST_UI_DEFAULTS)
    Feel = ns.UI.Feel
    used = set(re.findall(r'\["([\w.]+)"\]', TEST_LOOK))
    for folder in ("ui", "game"):
        for name in sorted(os.listdir(os.path.join(ROOT, folder))):
            if name.endswith(".lua"):
                with open(os.path.join(ROOT, folder, name), encoding="utf-8") as fh:
                    used |= set(LITERAL.findall(fh.read()))
    assert len(used) >= 12
    assert not [k for k in used if Feel.Entry(k) is None], sorted(k for k in used if Feel.Entry(k) is None)

    asked = L.eval("""function(Feel)
        local asked, get = {}, Feel.Get
        Feel.Get = function(key) asked[key] = true; return get(key) end
        return asked
    end""")(Feel)
    sim.Slash("/mm toggle")
    sim.Run(2)
    for p in Feel.Pages().values():
        Feel.Open(p.key)
    sim.Run(1)
    assert len(list(asked.keys())) > 30
    assert not [k for k in asked.keys() if Feel.Entry(k) is None], sorted(k for k in asked.keys() if Feel.Entry(k) is None)

    bad = L.eval("""function(Feel)
        local out, pages = {}, {}
        for _, p in ipairs(Feel.Pages()) do pages[p.key] = true end
        for _, k in ipairs(Feel.Entries()) do
            local d = Feel.Default(k.key)
            local function no(why) out[#out + 1] = k.key .. ": " .. why end
            if k.page ~= false and not pages[k.page] then no("no page " .. tostring(k.page)) end
            if type(k.tip) ~= "string" or #k.tip < 8 then no("no tip") end
            if type(k.label) ~= "string" or k.label == "" then no("no label") end
            if k.kind ~= "button" and d == nil then no("no default") end
            if k.kind == "slider" and d ~= nil then
                local n = (d - k.min) / k.step
                if d < k.min or d > k.max or math.abs(n - math.floor(n + 0.5)) > 1e-6 then no("default off its slider") end
            end
            local list = k.kind == "color" and k.colors or k.kind == "select" and type(k.options) == "table" and k.options
            if list then
                local found = false
                for _, o in ipairs(list) do found = found or (k.colors and o[1] or o[2]) == d end
                if not found then no("default not offered") end
            end
        end
        return out
    end""")(Feel)
    assert not list(bad.values()), list(bad.values())
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


# Every setting but the actions, each to a valid value other than its own: (key, value) sorted.
# But general.follow: the camera's state more than a setting (ui/Motion.lua's idle return follows you again 6 s
# after the map is left alone, as the MVP's MinimapMode.lua:20), so it doesn't hold even within a session; and the
# pins' show switches (Settings > Pins: every one flipped hides every pin, and the pins drawn are what's compared).
CHANGED = """local SKIP = { ["general.follow"] = true }
return function(Feel)
    local out = {}
    for _, k in ipairs(Feel.Entries()) do
        local key = k.key
        if key:match("^pins%..*%.show$") then SKIP[key] = true end
        local v, new = Feel.Get(key), nil
        if k.kind == "toggle" then
            new = not v
        elseif k.kind == "slider" then
            new = v + k.step <= k.max + 1e-9 and v + k.step or v - k.step
            new = math.floor(new * 1000 + 0.5) / 1000
        elseif k.kind == "select" or k.kind == "color" then
            local o = k.colors or (type(k.options) == "function" and k.options() or k.options)
            for _, opt in ipairs(o) do
                local val = k.colors and opt[1] or opt[2]
                if new == nil and val ~= v then new = val end
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


def _map_shown(sim, ns):
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
    L, sim, ns = boot(TEST_UI_DEFAULTS)
    T = harness(L)
    sim.Slash("/mm toggle")
    sim.Run(1)
    changed = [(c[1], c[2]) for c in L.execute(CHANGED)(ns.UI.Feel).values()]
    assert len(changed) >= 40, changed
    for key, v in changed:
        ns.UI.Feel.Set(key, v)
    _map_shown(sim, ns)  # (Replace minimap off hides the map: /mm shows it)
    keys = [k for k, _ in changed]
    before = _settings(ns, keys)
    assert before == dict(changed), {k: (v, before[k]) for k, v in changed if before[k] != v}
    pins = _drawn(T, sim, ns)
    assert pins and not errors(sim, ns), errors(sim, ns)
    L0, sim0, ns0 = boot(TEST_UI_DEFAULTS)  # (the settings show in what's drawn: icon size, grouping)
    _map_shown(sim0, ns0)
    assert _drawn(harness(L0), sim0, ns0) != pins

    sim.FireEvent("PLAYER_LOGOUT")
    saved = "MagicMap2DB = " + L.eval("function(path) return assert(loadfile(path))() end")(
        os.path.join(TESTS, "replay.lua")).Dump(L.globals().MagicMap2DB)
    L2, sim2, ns2 = boot(saved, reload=True)
    T2 = harness(L2)
    _map_shown(sim2, ns2)
    after = _settings(ns2, keys)
    assert after == before, {k: (before[k], after[k]) for k in keys if after[k] != before[k]}
    assert _drawn(T2, sim2, ns2) == pins
    assert not errors(sim2, ns2), errors(sim2, ns2)
