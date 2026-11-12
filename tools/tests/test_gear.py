"""The gear menu on the simulated client (ui/Menus.lua), as the spike's (GearMenu.lua, Layers.lua:30-71,
2154-2207): Map (the names, quests, places, rares and party, a
divider between) and Other addons, each layer a checkbox with its tip (white title, gold body) that keeps the menu
open, its icon beside it, a sub-option indented and greyed while its parent is off, each group's row with its n/total;
Tracking, Blizzard's tracking types alone, and Keep tracking; then Use Blizzard's minimap (while ours replaces it) and
Reset to defaults; the minimap's buttons are the AddOns button's (a row each that clicks it:
test_gear_minimap_buttons); then one row, Settings…, which opens the settings window
(ui/Feel.lua: test_lookfeel.py holds what was the Settings submenu), the same small and big. Every row works: a layer's toggle empties and redraws what it draws (and View.layers, for Game's:
Questie's borrowed pins) and is saved, the changed keys only, across a /reload; a layer off by
default stays so until turned on; rows in the spike's order whenever added; each setting does what it says;
a tracking type's box sends Game its Command (test_gear_tracking); /mm layers."""
import re

from test_addon import boot, errors
from fixtures import lua_tools
from sim import TEST_UI

LAYERS = {"Zone labels": "labels", "Quests": "quests", "Quest areas": "questAreas",
          "Rares & treasures": "rares"}
SETTINGS = "Settings\u2026".encode("utf-8").decode("latin-1")  # the row's label, as the sim's Lua (latin-1) reads it
WHITE, GOLD = (1, 1, 1), (1, 0.82, 0)
SEEN = ("MagicMap2DB.Model = MagicMap2DB.Model or { _v = 1, rares = { [0] = { ['npc:1'] = "
        "{ name = 'Rare', npcID = 1, col = 31.97, row = 49.74, t = 1792077412 } } } }")  # a rare you've seen
ICON = "Interface\\Icons\\INV_Misc_Map_01"  # Game's minimap button (game/Button.lua)


def shown(saved=None):
    """The map shown over one of each layer's things near you: a rare you've seen (Model's
    saved part), Questie's pin in Elwynn. (L, sim, ns, the pin)."""
    L, sim, ns = boot((saved or TEST_UI) + "\n" + SEEN)
    G = L.globals()
    q = sim.LoadQuestie()
    sim.FireEvent("ADDON_LOADED", "Questie")
    pin = sim.QuestieIcon()
    q.AddWorldMapIconMap(q, G.Questie, pin, 1429, 0.5, 0.5, G.HBD_PINS_WORLDMAP_SHOW_WORLD)
    sim.Slash("/mm toggle")
    sim.Run(3)
    return L, sim, ns, pin


def layer(ns, name):
    return next(lay for lay in ns.UI.Engine.layers.values() if lay.name == name)


def drawn(lay):
    """The regions a layer shows: its front canvas's, at alpha 1."""
    c = lay.front
    return sum(p.n for p in c.pools.values()) if c and c.alpha == 1 else 0


def gear(sim, ns):
    """Click the gear: the menu's root, and its rows by text."""
    sim.Click(ns.UI.Controls.gear)
    return sim.menu, {plain(e.text): e for e in sim.MenuItems().values() if e.text}


def addons(sim, ns):
    """Open the AddOns button's menu (the minimap's buttons): its root, and its rows by text."""
    ns.UI.Menus.AddOns(ns.UI.Controls.addons)
    sim.Step()
    return sim.menu, {plain(e.text): e for e in sim.MenuItems().values() if e.text}


def plain(text):
    """A row's text without its icon (|A...|a or |T...|t markup) and the spaces after it, and without colour
    codes (a group's dimmed "n/total" stays: "Map  3/5")."""
    return text and re.sub(r"\|c[0-9a-f]{8}|\|r|\|[AT].*?\|[at] *", "", text)


def items(d):
    """Each row's (kind, text): a group's "  n/total" left out (count() reads it)."""
    return [(e.kind, re.sub(r"  \d+/\d+$", "", plain(e.text) or "") or None) for e in d["items"].values()]


def count(sim, ns, title):
    """A group's row as the gear draws it now: its title and n/total."""
    root, _ = gear(sim, ns)
    return plain(sub(root, title).text)


def sub(root, title):
    """The row titled so (a group's count after its title)."""
    return next(e for e in root["items"].values() if (plain(e.text) or "").partition("  ")[0] == title)


def tip(L, row):
    """The lines a row's tooltip writes: (text, r, g, b)."""
    t = L.eval("""function(fn)
        local t = { lines = {} }
        function t:SetText(s, r, g, b) self.lines[#self.lines + 1] = { s, r, g, b } end
        function t:AddLine(s, r, g, b) self.lines[#self.lines + 1] = { s, r, g, b } end
        fn(t)
        return t.lines
    end""")(row.tooltip)
    return [tuple(line.values()) for line in t.values()]


def hosted(L, pin, ns):
    """Questie's pin on Game's holder, on the world socket."""
    return L.eval("function(pin, socket) return pin:GetParent():GetParent() == socket end")(pin, ns.UI.Sockets.world.frame)


def rim_button(L, sim):
    return L.eval("""function(Sim, icon)
        for _, f in ipairs(Sim.Frames()) do
            for _, r in ipairs({ f:GetRegions() }) do
                if r.GetTexture and r:GetTexture() == icon then return f end
            end
        end
    end""")(sim, ICON)


def test_gear():
    L, sim, ns, pin = shown()
    G, UI, Game = L.globals(), ns.UI, ns.Game
    view, saved, f = UI.View(), G.MagicMap2DB.UI, UI.Window.frame
    refresh = G.MenuResponse.Refresh

    # The tree: a submenu per group with layers, a divider, Settings; small and big alike.
    root, rows = gear(sim, ns)
    assert items(root) == [("button", "Map"), ("button", "Tracking"), ("button", "Keep tracking: Find Herbs"),
                           ("button", "Default zoom"), ("button", "Other addons"), ("divider", None),
                           ("button", "Use Blizzard's minimap"),
                           ("button", "Reset to defaults"), ("divider", None), ("button", SETTINGS)]
    assert items(sub(root, "Map")) == [("checkbox", "All map"), ("divider", None), ("checkbox", "Zone labels"),
                                       ("divider", None), ("checkbox", "Quests"), ("checkbox", "Quest areas"),
                                       ("divider", None), ("checkbox", "Flight points"), ("checkbox", "Dungeons & raids"),
                                       ("checkbox", "Graveyards"), ("checkbox", "Points of interest"),
                                       ("divider", None), ("checkbox", "Rares & treasures"), ("checkbox", "Party & raid")]
    assert items(sub(root, "Tracking")) == [("checkbox", "Find Herbs"), ("checkbox", "Mailbox"), ("checkbox", "Innkeeper")]
    assert items(sub(root, "Other addons")) == [("checkbox", "All other addons"), ("divider", None), ("checkbox", "Questie")]  # (GatherMate2's minimap pins only: none)
    assert plain(sub(root, "Map").text) == "Map  7/9"  # (graveyards and points of interest off till turned on)
    # Default zoom (the small map's alone): Auto, then a radio a Blizzard zoom it reaches; a pick goes there.
    zooms = sub(root, "Default zoom")
    radios = [r for r in zooms["items"].values() if r.kind == "radio"]
    auto = UI.DefaultZoom()
    assert plain(radios[0].text).startswith("Auto (") and radios[0].isSelected() and len(radios) > 2
    n = len(radios) - 1  # (the closest it reaches; Auto's the one before)
    assert radios[n].onSelect() == refresh
    sim.Run(2)
    steps = ns.Model.minimap.steps
    assert UI.Feel.Get("zoom.default") == n and UI.DefaultZoom() == steps[n] != auto
    assert abs(UI.Camera.cam.zoom - steps[n]) < 0.01 and radios[n].isSelected() and not radios[0].isSelected()
    assert radios[0].onSelect() == refresh
    sim.Run(2)
    assert UI.Feel.Get("zoom.default") == 0 and UI.DefaultZoom() == auto

    sim.Press("M")
    sim.Run(1)
    big, _ = gear(sim, ns)
    assert items(big) == [i for i in items(root) if i != ("button", "Default zoom")]

    # Tips: white title, gold body.
    assert tip(L, rows["Zone labels"]) == [("Zone labels",) + WHITE, ("Names of zones and sub-zones.",) + GOLD]
    assert tip(L, rows["Questie"]) == [("Questie",) + WHITE,
                                       ("Map pins Questie puts on the world map, shown here too.",) + GOLD]

    # Each layer (on the big map: zone names show there only): on, its things drawn; off, gone from the next frame (the menu stays open); on, back.
    root, rows = gear(sim, ns)
    assert Game.minimap.engaged and view.layers["addon:Questie"] and hosted(L, pin, ns)
    for text, name in LAYERS.items():
        lay, row = layer(ns, name), rows[text]
        assert row.isSelected() is True and drawn(lay) > 0, name
        assert row.onSelect() == refresh
        sim.Step()
        assert row.isSelected() is False and drawn(lay) == 0 and saved.layers[name] is False, name
        if name == "rares":
            assert not ns.UI.Engine.LayerOn("vignettes")  # (one row: the live ones too)
        assert row.onSelect() == refresh
        sim.Run(1)
        assert row.isSelected() is True and drawn(lay) > 0 and saved.layers[name] is None, name
    assert Game.minimap.engaged

    # Questie's pins: given back while its layer's off, borrowed again when on.
    row, frame = rows["Questie"], view.frame
    assert row.onSelect() == refresh
    sim.Step()  # View.layers from the next frame, View.frame with it (types/view.lua)
    assert view.layers["addon:Questie"] is None and view.frame > frame
    # The world socket's zoom, set in place: View.frame stamped the frame it lands (Game re-places its pins
    # then); and the window's place the frame it moves.
    world, zoom = view.sockets.world, view.sockets.world.zoom
    ns.UI.Motion.ZoomStep(1)
    while world.zoom == zoom:
        frame = view.frame
        sim.Step()
    assert view.frame == ns.Runtime.frames and view.frame > frame
    sim.Run(0.5)
    UI.Window.frame.ClearAllPoints(UI.Window.frame)
    UI.Window.frame.SetPoint(UI.Window.frame, "TOPLEFT", G.UIParent, "TOPLEFT", 50, -50)
    frame = view.frame
    sim.Step()
    assert view.frame == ns.Runtime.frames and view.frame > frame
    sim.Run(1.1)
    assert not hosted(L, pin, ns) and row.isSelected() is False
    row.onSelect()
    sim.Run(1.1)
    assert hosted(L, pin, ns) and row.isSelected() is True

    # A sub-option (a later package's row): indented, clickable only while its parent is on.
    UI.Menus.Layer(L.table_from({"key": "child", "label": "Sub-option", "group": "map", "parent": "labels",
                                 "tip": "A sub-option."}))
    root, rows = gear(sim, ns)
    child = rows["     Sub-option"]
    rows_ = items(sub(root, "Map"))
    assert rows_[rows_.index(("checkbox", "Zone labels")) + 1] == ("checkbox", "     Sub-option") and child.IsEnabled(child)
    rows["Zone labels"].onSelect()
    assert not child.IsEnabled(child)

    sim.Press("M")  # (small again)
    sim.Run(1)

    # Settings… (its page's rows: test_lookfeel.py). The minimap button and Reset window position, through the window:
    # Game's button hidden, and shown again; the window back on the minimap's spot, following.
    button = rim_button(L, sim)
    assert button.IsShown(button)
    UI.Feel.Set("general.button", False)
    sim.Step()
    assert saved.button is False and view.button is False and not button.IsShown(button)
    UI.Feel.Set("general.button", True)
    sim.Step()
    assert saved.button and button.IsShown(button)
    UI.Motion.SetFollow(False)
    P = L.globals().UIParent  # (its default spot: 234 by 219 at the screen's top right, 15 in, 73 down)
    home = {"left": P.GetWidth(P) - 15 - 234, "top": P.GetHeight(P) - 73, "w": 234, "h": 219}
    f.ClearAllPoints(f)
    f.SetPoint(f, "TOPLEFT", P, "BOTTOMLEFT", 600, 800)
    assert (f.GetLeft(f), f.GetTop(f)) != (home["left"], home["top"])
    UI.Feel.Open("general")
    w = UI.Feel.widgets["general.resetpos"].button
    sim.Click(w)
    sim.Step()
    assert (f.GetLeft(f), f.GetTop(f), f.GetWidth(f), f.GetHeight(f)) == (home["left"], home["top"], home["w"], home["h"])
    assert UI.Camera.follow
    UI.Feel.frame.Hide(UI.Feel.frame)
    # Use Blizzard's minimap: ours hidden, the Minimap Blizzard's again, the button on it.
    _, rows = gear(sim, ns)
    assert rows["Use Blizzard's minimap"].onSelect() is None
    sim.Step()
    assert not f.IsShown(f) and saved.shown is False and not Game.minimap.engaged and button.IsVisible(button)
    sim.Slash("/mm toggle")
    sim.Run(1)
    _, rows = gear(sim, ns)
    UI.Feel.Set("general.button", False)
    rows["Questie"].onSelect()
    sim.Slash("/mm toggle")
    sim.Step()
    perf = ns.Runtime.Perf()[0]["map: gear pick"]
    assert perf.n == 15 and perf.over == 0, (perf.n, perf.max)  # (two of them the Default zoom picks)
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))

    # /reload: the changed keys only (quest areas and the rest went off and on again, from the gear or
    # /mm layer), each still in effect.
    sim.Slash("/mm layer questAreas")
    sim.Slash("/mm layer questAreas")
    sim.FireEvent("PLAYER_LOGOUT")
    assert dict(saved.layers.items()) == {"labels": False, "addon:Questie": False}
    L, sim, ns, pin = shown("MagicMap2DB = " + lua_tools(L).Dump(G.MagicMap2DB))
    saved, view = L.globals().MagicMap2DB.UI, ns.UI.View()
    assert dict(saved.layers.items()) == {"labels": False, "addon:Questie": False}
    assert saved.button is False and view.button is False
    assert drawn(layer(ns, "labels")) == 0 and drawn(layer(ns, "tiles")) > 0
    assert view.layers["addon:Questie"] is None and not hosted(L, pin, ns)
    _, rows = gear(sim, ns)
    assert [rows[t].isSelected() for t in ("Zone labels", "Quest areas", "Questie")] == [False, True, False]
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


# Stubbed as typed (wave 4a's, beside this one): obs.tracking as M4.1's part hands it (types/observation.lua
# MM.ObsTracking: a new table on change) and its tracking Command carried out on it; the run Command (/mm
# <line>, as typed) recorded, flipping its owners' states: UI's saved debug, Game's indoor reports
# (obs.minimap), Runtime's recording.
STUBS = """function(ns, sent, ran)
    local cur = {
        { id = 8, name = "Flight Master", texture = 136456, active = true, kind = "duplicate" },
        { id = 2383, name = "Find Herbs", texture = 136456, active = true },
        { id = 65536, name = "Track Quest POIs", texture = 136456, active = true, kind = "duplicate" },
        { id = 8192, name = "Points of Interest", texture = 136456, active = false, kind = "duplicate" },
        { id = 64, name = "Mailbox", texture = 136459, active = true },
        { id = 128, name = "Innkeeper", texture = 136458, active = true },
        { id = 2, name = "Banker", texture = 136453, active = true },
        { id = 4194304, name = "Banker", texture = 136453, active = false }, -- (the client lists two: #21)
    }
    ns.Game.Part("tracking", function() return cur end)
    ns.Game.Handle("tracking", function(c)
        sent[#sent + 1] = c
        local new = {}
        for i, t in ipairs(cur) do
            new[i] = { id = t.id, name = t.name, texture = t.texture, kind = t.kind, active = t.active }
            if t.id == c.id then new[i].active = c.on end
        end
        cur = new
    end)
    ns.Game.Handle("run", function(c)
        ran[#ran + 1] = c.line
        local g = ns.Game.saved
        if c.line == "debug" then ns.UI.saved.debug = not ns.UI.saved.debug end
        if c.line == "indoor" then g.indoorDebug = not g.indoorDebug or nil end -- (game/parts/Interior.lua's)
        if c.line == "perf" then ns.Runtime.recording = not ns.Runtime.recording end
    end)
end"""


def test_gear_tracking():
    """Tracking (GearMenu.lua:9-26), in Nearby: Blizzard's types but those ours replace, each a box that sends Game the
    tracking Command and shows the click till Game's next Observation says so; two of one name and icon one box (#21). The Diagnostics page's rows run
    their /mm command, a box showing its command's state. /mm layers
    (Layers.lua:2196-2207): each group's layers, on green, off grey, a sub-option grey while its parent's off."""
    L, sim, ns = boot()
    refresh, sent, ran = L.globals().MenuResponse.Refresh, L.table(), L.table()
    L.eval(STUBS)(ns, sent, ran)
    sim.Slash("/mm toggle")
    sim.Run(1)

    # Tracking, under the Tracking group's rows: the client's order, the duplicates (flight, quest POIs, POIs) left out, a name
    # and icon the client lists twice one box.
    root, rows = gear(sim, ns)
    assert items(sub(root, "Tracking")) == [("checkbox", "Find Herbs"), ("checkbox", "Mailbox"),
                                            ("checkbox", "Innkeeper"), ("checkbox", "Banker")]
    mail = rows["Mailbox"]
    assert mail.isSelected() is True and mail.onSelect() == refresh
    assert mail.isSelected() is False and len(sent) == 0  # the click shown; Game's in its next input step
    sim.Step()
    assert [(c.kind, c.id, c.on) for c in sent.values()] == [("tracking", 64, False)]
    assert ns.Model.tracking[5].active is False and mail.isSelected() is False
    mail.onSelect()
    mail.onSelect()  # twice before Game's step: both sent, in order, the box as the last asked
    assert mail.isSelected() is False
    sim.Step()
    assert [c.on for c in sent.values()] == [False, True, False] and mail.isSelected() is False
    assert rows["Find Herbs"].isSelected() is True and rows["Innkeeper"].isSelected() is True

    # The one Banker box: on only while both are; a click sets both (the one that's off), the next clears both.
    bank = rows["Banker"]
    assert bank.isSelected() is False
    bank.onSelect()
    sim.Step()
    assert [(c.id, c.on) for c in sent.values()][3:] == [(4194304, True)] and bank.isSelected() is True
    bank.onSelect()
    sim.Step()
    assert [(c.id, c.on) for c in sent.values()][4:] == [(2, False), (4194304, False)] and bank.isSelected() is False

    # Diagnostics (the settings window's page, once the gear's Advanced): each row its /mm command; a box shows the
    # click, then its state.
    UI = ns.UI
    UI.Feel.Open("diag")
    w = UI.Feel.widgets
    checked = lambda k: w[k].check.GetChecked(w[k].check)  # noqa: E731
    assert not checked("diag.debug") and "diag.indoor" not in w  # (indoor reports: /mm indoor alone)
    sim.Click(w["diag.debug"].check)
    sim.Step()
    sim.Slash("/mm indoor")
    sim.Step()
    assert ns.UI.saved.debug and ns.Model.minimap.indoorDebug
    for key in ("diag.record", "diag.top", "diag.mem"):
        sim.Click(w[key].button)
        sim.Step()
    assert list(ran.values()) == ["debug", "perf", "perf top", "perf mem"]
    ns.Runtime.recording = False

    # /mm layers.
    sim.Slash("/mm layer questAreas")
    sim.Slash("/mm layer rares")
    sim.Slash("/mm layer flight")  # (a gear row's: the places layer draws its kind)
    sim.Slash("/mm layers")
    on, off = "|cff33ff33%s|r".__mod__, "|cff888888%s|r".__mod__
    assert sim.prints[len(sim.prints)] == (
        "|cffffd100MagicMap|r: layers: "
        f"|cffffd100Map:|r {on('zoneLabels')}, {on('quests')}, {off('questAreas')}, {off('flight')}, {on('dungeons')}, "
        f"{off('graveyards')}, {off('areaPOIs')}, {off('rares')}, {on('group')}. Toggle them from the gear. "
        "Shift-click: /way at cursor. Ctrl-click: set waypoint. Ctrl-right-click: clear it.")
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


COMPARTMENT = """local G, got = ...
local reg = G.AddonCompartmentFrame.registeredAddons
reg[#reg + 1] = { text = "Details", icon = "Interface\\\\Icons\\\\INV_Misc_Book_09",
    func = function(_, input) got[#got + 1] = input.buttonName end }
reg[#reg + 1] = { text = "SomeAddon", func = function() got[#got + 1] = "copy" end } -- (LibDBIcon's copy of its own)
"""


def test_gear_minimap_buttons():
    """Minimap buttons (#19): the buttons the takeover hides with the Minimap, a row each, its icon and name: LibDBIcon's
    launchers, the addon compartment's (not MagicMap's own, nor a launcher's copy), another addon's named button on its
    rim; Blizzard's calendar and clock after a divider. A click (left or right) does what the button's does, from Game's
    next step (the button Command); hovering one shows its own tooltip, leaving hides it. With none, "None found", greyed."""
    L, sim, ns, pin = shown()
    G = L.globals()
    assert ns.Game.minimap.engaged  # (the Minimap and its cluster hidden: these with them)
    sim.LoadLibDBIcon()
    rim = sim.RimButton("AtlasLootMinimapButton", "AtlasLoot", "Interface\\Icons\\INV_Box_01")
    got = L.table()
    L.execute(COMPARTMENT, G, got)
    sim.Run(3.5)  # (looked for again every 3 s)
    root, rows = addons(sim, ns)
    assert items(root) == [("title", "AddOns"), ("button", "AtlasLoot"), ("button", "Details"), ("button", "Some Addon"),
                                                   ("divider", None), ("button", "Calendar"), ("button", "Clock")]
    assert rows["Some Addon"].text.startswith("|TInterface\\Icons\\INV_Misc_Bag_08:16:16|t")
    assert rows["Calendar"].text.startswith("|A:ui-hud-minimap-calendar-button:16:16|a")

    rows["Some Addon"].onSelect()
    assert len(sim.ldb.clicks) == 0  # Game's, in its next step
    sim.Step()
    c = sim.ldb.clicks[1]
    same = L.eval("function(a, b) return a == b end")
    assert same(c.frame, sim.minimapButton) and c.button == "LeftButton"  # (its own LibDBIcon button, as LibDBIcon calls it)
    rows["Details"].onSelect(None, L.table_from({"buttonName": "RightButton"}))
    rows["AtlasLoot"].onSelect()
    rows["Calendar"].onSelect()
    rows["Clock"].onSelect()
    sim.Step()
    assert list(got.values()) == ["RightButton"] and list(rim.clicks.values()) == ["LeftButton"]
    assert sim.opened.calendar == 1 and sim.opened.clock == 1

    # Its tooltip: the launcher's OnTooltipShow on GameTooltip, at the row; gone as the pointer leaves.
    row, tt = rows["Some Addon"], G.GameTooltip
    owner = L.eval("CreateFrame('Button', nil, UIParent)")
    row.onEnter(owner)
    sim.Step()
    assert tt.IsShown(tt) and tt.IsOwned(tt, owner) and sim.ldb.tips == 1
    row.onLeave(owner)
    sim.Step()
    assert not tt.IsShown(tt)

    # None: a greyed row.
    G.GameTimeFrame.Disable(G.GameTimeFrame)
    G.TimeManagerClockButton = None
    G.LibStub.libs["LibDBIcon-1.0"] = None  # (its button, still on the rim, is then another addon's: hidden too)
    for b in (rim, sim.minimapButton):
        b.Hide(b)
    G.AddonCompartmentFrame.registeredAddons = L.table()
    sim.Run(3.5)
    root, rows = addons(sim, ns)
    none = rows["None found"]
    assert items(root) == [("title", "AddOns"), ("button", "None found")] and not none.IsEnabled(none)
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_gear_groups_and_reset():
    """A group's "All" box turns its layers all on, or all off when they all were; Reset to defaults puts every layer back."""
    L, sim, ns, pin = shown()
    E = ns.UI.Engine
    root, rows = gear(sim, ns)
    assert count(sim, ns, "Map") == "Map  7/9"  # (Graveyards and points of interest are off by default)
    rows["All map"].onSelect()  # (not all on, so all on)
    assert E.LayerOn("flight") and E.LayerOn("graveyards") and E.LayerOn("quests")
    assert count(sim, ns, "Map") == "Map  9/9"
    rows["All map"].onSelect()
    assert not E.LayerOn("flight") and not E.LayerOn("quests")
    assert count(sim, ns, "Map") == "Map  0/9"
    rows["Reset to defaults"].onSelect()
    assert E.LayerOn("quests") and E.LayerOn("flight") and not E.LayerOn("graveyards")  # (off by default)
    assert count(sim, ns, "Map") == "Map  7/9"
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_gear_settings():
    """Settings…: one button (the menu closes) that opens the settings window (ui/Feel.lua: test_lookfeel.py), with its tip."""
    L, sim, ns, pin = shown()
    root, _ = gear(sim, ns)
    row = sub(root, SETTINGS)
    assert tip(L, row)[0] == (SETTINGS,) + WHITE and tip(L, row)[1][0].startswith("MagicMap's settings window")
    assert row.onSelect() is None
    f = ns.UI.Feel.frame
    assert f.IsShown(f) and f.GetFrameStrata(f) == "DIALOG"
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
