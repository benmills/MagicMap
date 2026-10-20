"""Quest pins on the simulated client (docs/v1-plan.md M2.4: ui/Quests.lua, ui/QuestTooltip.lua, the
clicks in ui/Areas.lua), end to end from the sim's quest log through Game's parts and Model:

  test_quest_pins: StylePin's quest forms (S46): in progress, the in-progress atlas over the number disc
    tinted its difficulty, the objective's icon inside, its count; ready to turn in, the turn-in atlas;
    22 px, the one you follow 26 in its halo (S43, S44); quests to pick up at 18, their tooltip (F40).
  test_quest_follow: a click on a pin follows its quest (the follow Command, Blizzard's super-tracked
    quest back in the next observation, its pin 26 in the halo), again stops; a click on an area with
    no pin under it follows its quest; a pin over another quest's area wins (F31). Each frame one pin a
    quest.
  test_quest_pins_each_frame: one pin a quest every frame (the harness's invariants, T.Invariants, after
    each step) through the wheel, drags, the big map, the follow moving, an offer taken into the log and
    the log abandoned (F26).
  test_quest_tooltip: the tooltip's lines in QuestInfo.lua's order and type (S63): the tag and group
    size on the facts line, ≤3 droppers lowest first and how many more, Turn in to, the click hint; a
    met dropper's portrait (the tooltip Command) the frame the tooltip is built; without QuestieDB's
    data, no dropper, source or turn-in lines (F28).
"""
from test_addon import boot, errors

SETUP = """
local Sim, ns = ...
local Atlas = ns.Atlas
Sim.atlases["UI-QuestIcon-TurnIn-Normal"], Sim.atlases.QuestNormal = true, true
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
	local items = { [772] = { name = "Large Candle", icon = 133750, npcDrops = { 9001, 9002, 9003, 9004, 9005 },
		objectDrops = {}, vendors = {} } }
	local npcs = { [9001] = { name = "Candle Thief", minLevel = 6, maxLevel = 8 },
		[9002] = { name = "Tunnel Rat", minLevel = 4, maxLevel = 5 }, [9003] = { name = "Wick Keeper", minLevel = 7, maxLevel = 7, rank = 1 },
		[9004] = { name = "Old Mole", minLevel = 0, maxLevel = 0 }, [9005] = { name = "Deep Digger", minLevel = 12, maxLevel = 14, rank = 4 },
		[9301] = { name = "Candle Taker" } }
	local quests = { [60] = { objectives = { { kind = "item", id = 772 } }, finishedBy = { npcs = { 9301 }, objects = {} } } }
	Atlas.Item = function(id) return items[id] end
	local npc = Atlas.Npc -- (the rest Atlas's: SpawnsIn's, the town services' gathering)
	Atlas.Npc = function(id) return npcs[id] or npc(id) end
	Atlas.Object = function() return nil end
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
    # In progress, followed: the disc tinted orange (level 11 at 8), the objective's icon in it, the atlas
    # over it; 26 in its halo; its count under it.
    p = pin(ns, G, "Quests", 52)
    assert S[p].width == 26 and S[p.ring].atlas == "UI-QuestPoi-QuestNumber" and rgba(p.ring) == [1, 0.5, 0.25, 1]
    assert S[p.inner].texture == 135274 and abs(S[p.inner].width - 26 * 0.56) < 1e-9 and vis(p.inner)
    assert S[p.icon].atlas == "Quest-In-Progress-Icon-yellow" and abs(S[p.icon].width - 26 * 0.62) < 1e-9
    assert vis(p.glow) and S[p.glow].width == 40 and S[p.count].text == "2/8"
    # Ready to turn in: its atlas, 22, no halo, no count.
    p = pin(ns, G, "Quests", 106)
    assert S[p].width == 22 and S[p.icon].atlas == "UI-QuestIcon-TurnIn-Normal" and S[p.icon].width == 22
    assert not vis(p.ring) and not vis(p.glow) and p.count is None
    # To pick up (the sim's offer on Elwynn): 18; its tooltip, the quest and "Quest to pick up", small and grey.
    p, tip, view = pin(ns, G, "Offers", 70), G.GameTooltip, ns.UI.Window.view
    assert S[p].width == 18 and S[p.icon].atlas == "QuestNormal"
    e = ns.Model.Known("offers")[0][1]
    G.Over(e.pos.col, e.pos.row)
    sim.FireScript(view, "OnEnter", False)
    sim.Step()
    lines = [S[tip.GetLeftLine(tip, i)].text for i in range(1, tip.NumLines(tip) + 1)]
    assert S[tip].shown and lines == ["Wolves Across the Border", "|cff9d9d9dQuest to pick up|r"]
    assert L.eval("rawequal")(S[tip.GetLeftLine(tip, 2)].fontObject, G.GameTooltipTextSmall)
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_quest_follow():
    # Grouping off (ui/Cluster.lua): the quests' own pins are what these clicks are on, not a pill of them.
    L, sim, ns, G = client([FRONTIER, GOLD], before="local _, ns = ...\nns.UI.saved.cluster = false")
    view, Model = ns.UI.Window.view, ns.Model
    sim.FireScript(view, "OnEnter", False)

    def followed():
        return {e.quest for e in known(ns, "quests") if e.followed}

    def click(col, row):
        G.Over(col, row)
        sim.Step()  # (the pin under it found)
        sim.Click(view, "LeftButton", sim.cursorX, sim.cursorY, "screen")
        sim.Run(0.2)
        # one pin a quest, on the one canvas shown
        lay = ns.UI.Quests
        keys = [lay.front.pools.pin["keys"][i] for i in range(1, lay.front.pools.pin.n + 1)]
        assert sorted(keys) == ["quest:47", "quest:52"] and sum(c.alpha > 0 for c in lay.canvases.values()) == 1

    click(31.8, 49.7)  # Frontier's pin, in Gold Dust's area: the pin wins
    assert sim.superTracked == 52 and sim.watched == 52 and followed() == {52}
    p = pin(ns, G, "Quests", 52)
    assert sim.state[p].width == 26 and sim.state[p.glow].shown
    click(31.8, 49.7)  # again: none
    assert sim.superTracked == 0 and followed() == set() and sim.state[pin(ns, G, "Quests", 52)].width == 22
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
MOB = "|T135274:14:14:0:0:64:64:5:59:5:59|t"
ELITE = "|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:14:14|t"


def test_quest_tooltip():
    L, sim, ns, G = client([dict(CANDLES, tag="Group", group=3)])
    tip, S, same = G.GameTooltip, sim.state, L.eval("rawequal")
    sim.units.mouseover = L.table_from({"name": "Tunnel Rat", "guid": "Creature-0-1-0-1-9002-0000000001"})
    sim.FireEvent("UPDATE_MOUSEOVER_UNIT")  # met: Game draws its portrait from then on
    G.Over(31.95, 49.6)
    sim.FireScript(ns.UI.Window.view, "OnEnter", False)
    sim.Step()
    p = pin(ns, G, "Quests", 60)
    assert S[tip].shown and same(tip.GetOwner(tip), p) and S[p.inner].texture == 133750  # (its item's icon)

    def lines():
        return [(S[tip.GetLeftLine(tip, i)].text, same(S[tip.GetLeftLine(tip, i)].fontObject, G.GameTooltipTextSmall))
                for i in range(1, tip.NumLines(tip) + 1)]
    disc = "|TInterface\\CharacterFrame\\TempPortraitAlphaMask:14:14:0:0:64:64:0:64:0:64:0:0:0|t"
    want = [
        ("Kobold Candles", False),
        ("|cff9d9d9dLevel|r |cffffd1007|r|cff9d9d9d" + SEP + "|r|cffff8040Group (3)|r", True),  # its tag (F28)
        ("Large Candle: 3/8", False),
        ("    |cff9d9d9dDropped by|r", True),
        ("    " + MOB + " |cffffffffOld Mole|r", True),  # not met: its sword
        ("    " + disc + " |cffffffffTunnel Rat|r |cff3fbf3f4-5|r", True),  # met: its portrait over a dark disc
        ("    " + ELITE + " |cffffffffWick Keeper|r |cffffd1007|r |cff9d9d9dElite|r", True),
        ("    |cff9d9d9d(+2 more)|r", True),
        (" ", True),
        ("|cff9d9d9dTurn in to|r Candle Taker", True),
        ("|cff9d9d9dClick to follow|r", True),
    ]
    # The frame the tooltip is built: the tooltip Commands carried out in Game's apply step, after UI's.
    assert lines() == want
    assert any(v.portrait == "Creature-0-1-0-1-9002-0000000001" and v.shown for v in S.values())
    assert list(S[tip.GetLeftLine(tip, 1)].textColor.values()) == [1, 0.82, 0]
    assert list(S[tip.GetLeftLine(tip, 10)].textColor.values()) == [0.85, 0.85, 0.85]
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))

    # Booted without QuestieDB's files (Atlas's own empty indexes, as CI's checkout): the pin, its tooltip
    # without droppers, sources or turn-in.
    L, sim, ns, G = client([CANDLES], data=False)
    assert ns.Data.Quests is None and ns.Data.Npcs is None
    tip, S = G.GameTooltip, sim.state
    G.Over(31.95, 49.6)
    sim.FireScript(ns.UI.Window.view, "OnEnter", False)
    sim.Step()
    p = pin(ns, G, "Quests", 60)
    assert S[p.inner].texture == 133633 and S[p.count].text == "3/8"  # an item QuestieDB doesn't know
    assert [S[tip.GetLeftLine(tip, i)].text for i in range(1, tip.NumLines(tip) + 1)] == [
        "Kobold Candles", "|cff9d9d9dLevel|r |cffffd1007|r", "Large Candle: 3/8", " ", "|cff9d9d9dClick to follow|r"]
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
