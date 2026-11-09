"""Quest pins on the simulated client (docs/v1-plan.md M2.4: ui/Quests.lua, ui/QuestTooltip.lua, the
clicks in ui/Areas.lua), end to end from the sim's quest log through Game's parts and Model:

  test_quest_pins: StylePin's quest forms: in progress, Blizzard's in-progress atlas alone (no disc behind it),
    its count; 24 px, the one you follow the same, glowing; ready to turn in and quests to pick up none of ours
    (Blizzard's blips).
  test_quest_follow: a click on a pin opens its popup (ui/Popup.lua, ui/Track.lua's Actions): "Track" follows its quest
    (the follow Command, Blizzard's super-tracked quest back in the next observation, its pin glowing), "Stop
    tracking" stops; "Path to" follows it with the line, "Track" then switches back, "Stop
    pathing" stops; a click on an area with no pin under it follows its quest; a pin over another quest's
    area wins (F31). Each frame one pin a quest.
  test_quest_pins_each_frame: one pin a quest every frame (the harness's invariants, T.Invariants, after
    each step) through the wheel, drags, the big map, the follow moving, an offer taken into the log and
    the log abandoned (F26).
  test_quest_tooltip: the tooltip's lines in QuestInfo.lua's order and type (S63): the level in a pill beside
    the title (under it for a long one), the tag and group size on the facts line, the object an item is in
    (never who drops it), no line for who takes it in, no hint; a click grows it into the popup in its place:
    the same lines, then a divider and the pin's buttons; it stays till a button, a click off it or Escape;
    without QuestieDB's data, no source lines (F28).
"""
from test_addon import boot, errors

SETUP = """
local Sim, ns = ...
local Atlas = ns.Atlas
Sim.atlases["UI-QuestIcon-TurnIn-Normal"], Sim.atlases.QuestNormal, Sim.atlases.questturnin = true, true, true
Sim.units.player.level = 8
-- The sim's quest log: Quests{ { id, title, level, col, row (its pin on Elwynn, or map), complete?, objectives =
-- { { type, text, have, need, finished } }, area = r? (its objective area: a circle about the pin, r
-- map-normalized), tag?, group?, map? } }.
function Quests(list)
	Sim.quests = {}
	for _, q in ipairs(list) do
		local map = q.map or 1429
		local x, y = Atlas.TileToMap(map, q.col, q.row)
		local objectives = {}
		for i, o in ipairs(q.objectives or {}) do
			objectives[i] = { type = o[1], text = o[2], numFulfilled = o[3], numRequired = o[4], finished = o[5] }
		end
		Sim.quests[q.id] = { title = q.title, level = q.level, map = map, x = x, y = y, complete = q.complete == true,
			objectives = objectives, tag = q.tag, group = q.group }
		Sim.blobShapes[q.id] = q.area and { x, y, q.area } or nil
	end
	Sim.FireEvent("QUEST_LOG_UPDATE")
end
-- The cursor over tile (col, row) of the map shown.
function Over(col, row)
	local view, cam = ns.UI.Window.view, ns.UI.Camera.cam
	local w, h = ns.UI.Window.Size()
	local x, y = Atlas.Camera.TileToScreen(cam, w, h, col, row)
	local s = view:GetEffectiveScale()
	Sim.cursorX, Sim.cursorY = (view:GetLeft() + x) * s, (view:GetTop() - y) * s
end
-- The pin a layer shows for key.
function PinOf(layer, key)
	local p = layer.front.pools.pin
	return p[p.at[key]]
end
-- QuestieDB's rows for the quests here, as Atlas has them (made up: CI has none).
function Data()
	local items = { [772] = { name = "Large Candle", icon = 133750, npcDrops = { 9001, 9002 }, objectDrops = { 9101 },
		vendors = {} } }
	local npcs = { [9001] = { name = "Candle Thief", minLevel = 6, maxLevel = 8 }, [9301] = { name = "Candle Taker" } }
	local objects = { [9101] = { name = "Candle Crate" } }
	local quests = { [60] = { objectives = { { kind = "item", id = 772 } }, finishedBy = { npcs = { 9301 }, objects = {} } } }
	Atlas.Item = function(id) return items[id] end
	local npc = Atlas.Npc -- (the rest Atlas's: SpawnsIn's, the town services' gathering)
	Atlas.Npc = function(id) return npcs[id] or npc(id) end
	Atlas.Object = function(id) return objects[id] end
	Atlas.Quest = function(id) return quests[id] end
end
"""

FRONTIER = {"id": 52, "title": "Protect the Frontier", "level": 11, "col": 31.8, "row": 49.7,
            "objectives": [["monster", "Prowler slain: 2/8", 2, 8, False]], "area": 0.02}
GOLD = {"id": 47, "title": "Gold Dust Exchange", "level": 7, "col": 32.0, "row": 49.7,
        "objectives": [["item", "Gold Dust: 0/10", 0, 10, False]], "area": 0.05}  # its area holds Frontier's pin
LOVERS = {"id": 106, "title": "Young Lovers", "level": 6, "col": 32.1, "row": 49.85, "complete": True}
CANDLES = {"id": 60, "title": "Kobold Candles", "level": 7, "col": 31.95, "row": 49.6,
           "objectives": [["item", "Large Candle: 3/8", 3, 8, False]]}


def client(quests, data=True, followed=0, saved=None, before=None, shown=True):
    """data: QuestieDB's rows for these quests, made up (Data); False: booted without QuestieDB's files at all.
    shown: the map shown small at once (in login's grace), its quests read."""
    L, sim, ns = boot(saved, data=data)
    L.execute(SETUP, sim, ns)
    if before:
        L.execute(before, sim, ns)
    G = L.globals()
    if data:
        G.Data()
    sim.superTracked = followed
    G.Quests(L.table_from([L.table_from({k: L.table_from([L.table_from(o) for o in v]) if k == "objectives" else v
                                         for k, v in q.items()}) for q in quests]))
    if shown:
        sim.Slash("/mm toggle")
        sim.Run(1.5)
    return L, sim, ns, G


def known(ns, kind):
    """Known(kind)'s entries (the list's own fields, as the quests' poi, left out)."""
    t = ns.Model.Known(kind)[0]
    return [t[i] for i in range(1, len(t) + 1)]


def pin(ns, G, layer, quest):
    return G.PinOf(getattr(ns.UI, layer), f"quest:{quest}")


def test_quest_pins():
    L, sim, ns, G = client([FRONTIER, LOVERS], followed=52)
    S = sim.state
    vis = lambda r: r is not None and S[r].shown
    rgba = lambda r: list(S[r].vertex.values())
    # In progress, followed: as the world map's: the dots at full size on the quest disc, untinted; 24, glowing; its count under it.
    p = pin(ns, G, "Quests", 52)
    assert S[p].width == 24 and S[p.icon].atlas == "Quest-In-Progress-Icon-yellow" and S[p.icon].width == 24
    assert vis(p.glow) and S[p.glow].atlas == "UI-QuestPoi-OuterGlow"  # (what you follow: its glow, not a size)
    assert vis(p.ring) and S[p.ring].atlas == "UI-QuestPoi-QuestNumber" and rgba(p.ring) == [1, 1, 1, 1]
    assert not vis(p.inner) and rgba(p.icon) == [1, 1, 1, 1]
    assert p.count is None  # (small: no count under it; its progress is in the pill and its tooltip)
    # Big: its name under it, in the subzone names' size, solid, in its difficulty's colour (its entry's).
    ns.UI.BigMap.Toggle()
    sim.Run(1.5)
    p = pin(ns, G, "Quests", 52)
    font, size, _ = ns.UI.LabelsSub()
    assert S[p.count].shown and S[p.count].text == "Protect the Frontier" and S[p.count].font[1] == font
    c = p.count.style[3]  # (the colour it was set to: the sim keeps no text colour)
    e = p.entry.color
    assert S[p.count].font[2] == size and [c[1], c[2], c[3]] == [e[1], e[2], e[3]] and (c[2], c[3]) != (1, 1)  # (not white)
    # Ready to turn in, and quests to pick up: none of ours (Blizzard's "?" and "!" blips draw them).
    assert pin(ns, G, "Quests", 106) is None and ns.UI.Offers is None
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_quest_follow():
    # Grouping off (ui/Cluster.lua): the quests' own pins are what these clicks are on, not a pill of them.
    L, sim, ns, G = client([FRONTIER, GOLD], before="local _, ns = ...\nns.UI.saved.cluster = false")
    view, Model = ns.UI.Window.view, ns.Model
    sim.FireScript(view, "OnEnter", False)

    def followed():
        return {e.quest for e in known(ns, "quests") if e.followed}

    QT = ns.UI.Popup

    def click(col, row, row_text=None, button="LeftButton", rows=None):
        """A click there (either button: the same); on a pin, its popup opens: its button row_text picked (rows:
        its first two, Open in quest log after them; default row_text, Path to)."""
        G.Over(col, row)
        sim.Step()  # (the pin under it found)
        sim.menu = None
        sim.Click(view, button, sim.cursorX, sim.cursorY, "screen")
        if row_text:
            shown = list(QT.buttons.values())
            assert all(b.IsShown(b) for b in shown)
            assert QT.IsOpen() and [b.label for b in shown] == list(rows or (row_text, "Path to")) + ["Open in quest log"]
            b = next(b for b in shown if b.label == row_text)
            sim.FireScript(b, "OnClick", "LeftButton", False)
            assert not QT.IsOpen()
        else:
            assert sim.menu is None and not QT.IsOpen()
        sim.Run(0.2)
        # one pin a quest, on the one canvas shown
        lay = ns.UI.Quests
        keys = [lay.front.pools.pin["keys"][i] for i in range(1, lay.front.pools.pin.n + 1)]
        assert sorted(keys) == ["quest:47", "quest:52"] and sum(c.alpha > 0 for c in lay.canvases.values()) == 1

    click(31.8, 49.7, "Track")  # Frontier's pin, in Gold Dust's area: the pin wins
    assert sim.superTracked == 52 and sim.watched == 52 and followed() == {52}
    sim.cursorX, sim.cursorY = 5, 5  # off the window: the tracked quest's pill stays, at full alpha
    sim.Run(1)
    assert ns.UI.Controls.questLine.IsShown(ns.UI.Controls.questLine) and ns.UI.Controls.questLine.GetAlpha(ns.UI.Controls.questLine) == 1
    # The Quest pill settings: the name alone, then the pill off, live; back on.
    Feel, line = ns.UI.Feel, ns.UI.Controls.questLine
    text = lambda: " ".join(sim.state[r].text for r in line.GetRegions(line) if sim.state[r].text)
    assert "/" in text() or "ready" in text()
    Feel.Set("pills.quest", "name")
    assert text() == "Protect the Frontier"
    Feel.Set("pills.questShow", "off")
    assert not line.IsShown(line)
    Feel.Set("pills.questShow", "followed")
    Feel.Set("pills.quest", Feel.Default("pills.quest"))
    assert line.IsShown(line)
    p = pin(ns, G, "Quests", 52)
    assert sim.state[p].width == 24 and sim.state[p.glow].shown
    # The pill, while it shows the followed quest, is its pin: its tooltip on a hover, its popup on a click.
    pill, tip = ns.UI.Controls.questLine, G.GameTooltip
    sim.FireScript(pill, "OnEnter", False)
    assert sim.state[tip].shown and sim.state[tip.GetLeftLine(tip, 1)].text.endswith("Protect the Frontier")
    sim.menu = None
    sim.FireScript(pill, "OnMouseUp", "RightButton")
    assert sim.menu is None and QT.IsOpen() and not sim.state[tip].shown
    assert [b.label for b in QT.buttons.values()] == ["Stop tracking", "Path to", "Open in quest log"]
    sim.FireScript(QT.buttons[3], "OnClick", "LeftButton", False)  # Open in quest log: the client's (the sim's L opens the world map)
    sim.Run(0.2)
    assert G.WorldMapFrame.IsShown(G.WorldMapFrame)
    G.ToggleQuestLog()
    sim.FireScript(pill, "OnLeave", False)
    sim.FireScript(view, "OnEnter", False)
    click(31.8, 49.7, "Stop tracking", "RightButton")  # again (a right click, the same popup): none
    assert sim.superTracked == 0 and followed() == set() and sim.state[pin(ns, G, "Quests", 52)].width == 24
    # Path to it: followed, the line (ui/Path.lua) not the arrow; Track switches back (still followed), Path
    # to again, then Stop pathing: none.
    click(31.8, 49.7, "Path to", rows=("Track", "Path to"))
    assert sim.superTracked == 52 and ns.UI.saved.path.quest == 52 and ns.UI.Track.Pathed(Model.Target())
    click(31.8, 49.7, "Track", rows=("Track", "Stop pathing"))
    assert sim.superTracked == 52 and ns.UI.saved.path is None and not ns.UI.Track.Pathed(Model.Target())
    click(31.8, 49.7, "Path to", rows=("Stop tracking", "Path to"))
    click(31.8, 49.7, "Stop pathing", rows=("Track", "Stop pathing"))
    assert sim.superTracked == 0 and followed() == set() and ns.UI.saved.path is None
    sim.Run(2)  # (the framing, in close by the quest, glides back out)
    click(32.15, 49.7)  # Gold Dust's area, no pin under it
    assert sim.superTracked == 47 and followed() == {47}
    click(32.15, 49.7)
    assert sim.superTracked == 0 and followed() == set()
    click(33.0, 49.3)  # neither
    assert sim.superTracked == 0
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_quest_pins_each_frame():
    import sim as tools_sim
    L, sim, ns, G = client([FRONTIER, GOLD, LOVERS, CANDLES], followed=52)
    T = tools_sim.harness(L)
    L.execute("""local sim, ns, T = ...
        local step = sim.Step
        sim.Step = function(elapsed) step(elapsed); T.Invariants(sim, ns) end""", sim, ns, T)
    view, Known = ns.UI.Window.view, ns.Model.Known
    L.execute("""local sim, ns = ...
        local view = ns.UI.Window.view
        for _ = 1, 3 do sim.Wheel(view, 1); sim.Run(0.1) end
        sim.Run(1)
        for _ = 1, 3 do sim.Wheel(view, -1); sim.Run(0.1) end
        sim.Run(1)
        for i = 1, 3 do sim.Drag(view, i % 2 == 0 and 60 or -60, 20, 10); sim.Run(0.5) end""", sim, ns)
    for quest in (47, 60, 0):  # the follow moves (Blizzard's tracker), then none
        sim.superTracked = quest
        sim.FireEvent("SUPER_TRACKING_CHANGED")
        sim.Run(0.5)
    # The sim's offer 70 taken into the log: a quest's pin, not an offer's; then the log abandoned.
    assert 70 in {e.quest for e in known(ns, "offers")}
    sim.quests[70] = L.table_from({"title": "Wolves Across the Border", "level": 6, "map": 1429, "x": 0.36, "y": 0.55,
                                   "complete": False, "objectives": L.table()})
    sim.FireEvent("QUEST_LOG_UPDATE")
    sim.Run(1)
    assert 70 in {e.quest for e in known(ns, "quests")} and 70 not in {e.quest for e in known(ns, "offers")}
    sim.Press("M")
    sim.Run(1)
    sim.Wheel(view, -1)
    sim.Run(1)
    sim.quests = L.table()
    sim.FireEvent("QUEST_LOG_UPDATE")
    sim.Run(1)
    assert not known(ns, "quests") and 70 in {e.quest for e in known(ns, "offers")}
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


SEP = "  \u00b7  ".encode("utf-8").decode("latin-1")  # the facts line's joins, as the sim's Lua (latin-1) reads them


def test_quest_tooltip():
    L, sim, ns, G = client([dict(CANDLES, tag="Group", group=3)])
    tip, S, same, view = G.GameTooltip, sim.state, L.eval("rawequal"), ns.UI.Window.view
    G.Over(31.95, 49.6)
    sim.FireScript(view, "OnEnter", False)
    sim.Step()
    p = pin(ns, G, "Quests", 60)
    assert S[tip].shown and same(tip.GetOwner(tip), p)

    def lines(t):
        return [(S[t.GetLeftLine(t, i)].text, same(S[t.GetLeftLine(t, i)].fontObject, G.GameTooltipTextSmall))
                for i in range(1, t.NumLines(t) + 1)]
    content = [
        ("Kobold Candles", False),  # its level beside it, in a pill
        ("|cff9d9d9dGroup 3|r", True),  # its tag (F28), a fact; no level here
        ("Large Candle: 3/8", True),
        ("    |cff9d9d9dFrom|r |cffffffffCandle Crate|r", True),  # where it's found; its droppers never named
    ]  # (and no line for who takes it in, no hint)
    assert lines(tip) == content
    level = tip.GetRightLine(tip, 1)
    assert S[level].text == "|cffffd1007|r  " and same(S[level].fontObject, G.GameTooltipTextSmall)
    assert list(S[tip.GetLeftLine(tip, 1)].textColor.values()) == [1, 0.82, 0]
    pill = [r for r in tip.GetRegions(tip) if S[r].type == "Texture" and S[r].shown]
    assert len(pill) == 3 and all(S[r].texture == "Interface\\CharacterFrame\\TempPortraitAlphaMask" for r in pill)

    # A click: the tooltip grows into the popup where it stood, the same lines, then the pin's buttons; the hover's
    # tooltip gone (and kept away while the popup stands).
    QT = ns.UI.Popup
    pop, top = QT.frame, (tip.GetLeft(tip), tip.GetTop(tip))
    sim.Click(view, "LeftButton", sim.cursorX, sim.cursorY, "screen")
    assert QT.IsOpen() and not S[tip].shown and sim.menu is None
    assert (pop.GetLeft(pop), pop.GetTop(pop)) == top
    rows = ["Track", "Path to", "Open in quest log"]
    got = lines(pop)
    assert got[:-3] == content and got[-3] == (" ", True) and got[-1] == (" ", False)  # (the divider's, the buttons')
    assert got[-2][0].strip() == "" and len(got[-2][0]) >= 4  # (the buttons' line: as wide as they are)
    shown = list(QT.buttons.values())
    assert all(b.IsShown(b) for b in shown) and [b.label for b in shown] == rows
    # small buttons: Blizzard's red panel buttons, the tracked arrow and the boot before Track and Path; the micro menu's quest log
    assert [S[b.glyph].atlas for b in shown[:2]] == ["Navigation-Tracked-Arrow", "flightpath"]
    assert [S[b.word].text for b in shown[:2]] == ["Track", "Path"]  # Blizzard's red panel buttons, a word each
    assert S[S[shown[2]]["normal"]].atlas == "hud-microbutton-Quest-Up"
    sim.Run(1)  # sticky: no hover takes it away
    assert QT.IsOpen() and not S[tip].shown
    assert sim.Press("ESCAPE") and not QT.IsOpen()
    sim.Click(view, "LeftButton", sim.cursorX, sim.cursorY, "screen")  # again, where it last stood
    assert QT.IsOpen() and (pop.GetLeft(pop), pop.GetTop(pop)) == top
    G.Over(31.5, 49.9)
    assert not pop.IsMouseOver(pop)
    sim.Click(view, "LeftButton", sim.cursorX, sim.cursorY, "screen")  # a click off it
    assert not QT.IsOpen()
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))

    # A long title: the pill still beside it, on its line. Booted without QuestieDB's files (Atlas's own empty indexes, as CI's
    # checkout): no sources.
    L, sim, ns, G = client([dict(CANDLES, title="The Unusually Long Name of the Kobold Candles of Elwynn Forest")], data=False)
    assert ns.Data.Quests is None and ns.Data.Npcs is None
    tip, S = G.GameTooltip, sim.state
    G.Over(31.95, 49.6)
    sim.FireScript(ns.UI.Window.view, "OnEnter", False)
    sim.Step()
    p = pin(ns, G, "Quests", 60)
    assert p.count is None
    assert [S[tip.GetLeftLine(tip, i)].text for i in range(1, tip.NumLines(tip) + 1)] == [
        "The Unusually Long Name of the Kobold Candles of Elwynn Forest", "Large Candle: 3/8"]
    assert S[tip.GetRightLine(tip, 1)].text == "|cffffd1007|r  "
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
