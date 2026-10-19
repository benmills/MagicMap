"""Quest pins on the simulated client (docs/v1-plan.md M2.4: ui/Quests.lua, ui/QuestTooltip.lua, the
clicks in ui/Areas.lua), end to end from the sim's quest log through Game's parts and Model:

  test_quest_pins: StylePin's quest forms (S46): in progress, the in-progress atlas over the number disc
    tinted its difficulty, the objective's icon inside, its count; ready to turn in, the turn-in atlas;
    22 px, the one you follow 26 in its halo (S43, S44); quests to pick up at 18, their tooltip (F40).
  test_quest_follow: a click on a pin follows its quest (the follow Command, Blizzard's super-tracked
    quest back in the next observation, its pin 26 in the halo), again stops; a click on an area with
    no pin under it follows its quest; a pin over another quest's area wins (F31). Each frame one pin a
    quest.
  test_quest_tooltip: the tooltip's lines in QuestInfo.lua's order and type (S63): the tag and group
    size on the facts line, ≤3 droppers lowest first and how many more, Turn in to, the click hint; a
    met dropper's portrait (the tooltip Command); without QuestieDB's data, no dropper, source or
    turn-in lines (F28).
"""
from test_addon import boot, errors

SETUP = """
local Sim, ns = ...
local Atlas = ns.Atlas
Sim.atlases["UI-QuestIcon-TurnIn-Normal"], Sim.atlases.QuestNormal = true, true
Sim.units.player.level = 8
-- The sim's quest log: Quests{ { id, title, level, col, row (its pin on Elwynn), complete?, objectives =
-- { { type, text, have, need, finished } }, area = r? (its objective area: a circle about the pin, r
-- map-normalized), tag?, group? } }.
function Quests(list)
	Sim.quests = {}
	for _, q in ipairs(list) do
		local x, y = Atlas.TileToMap(1429, q.col, q.row)
		local objectives = {}
		for i, o in ipairs(q.objectives or {}) do
			objectives[i] = { type = o[1], text = o[2], numFulfilled = o[3], numRequired = o[4], finished = o[5] }
		end
		Sim.quests[q.id] = { title = q.title, level = q.level, map = 1429, x = x, y = y, complete = q.complete == true,
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
-- QuestieDB's rows for the quests here, as Atlas has them (made up: CI has none); nil: no data at all.
function Data(on)
	local items = { [772] = { name = "Large Candle", icon = 133750, npcDrops = { 9001, 9002, 9003, 9004, 9005 },
		objectDrops = {}, vendors = {} } }
	local npcs = { [9001] = { name = "Candle Thief", minLevel = 6, maxLevel = 8 },
		[9002] = { name = "Tunnel Rat", minLevel = 4, maxLevel = 5 }, [9003] = { name = "Wick Keeper", minLevel = 7, maxLevel = 7, rank = 1 },
		[9004] = { name = "Old Mole", minLevel = 0, maxLevel = 0 }, [9005] = { name = "Deep Digger", minLevel = 12, maxLevel = 14, rank = 4 },
		[9301] = { name = "Candle Taker" } }
	local quests = { [60] = { objectives = { { kind = "item", id = 772 } }, finishedBy = { npcs = { 9301 }, objects = {} } } }
	Atlas.Item = function(id) return on and items[id] end
	Atlas.Npc = function(id) return on and npcs[id] end
	Atlas.Object = function() return nil end
	Atlas.Quest = function(id) return on and quests[id] end
end
"""

FRONTIER = {"id": 52, "title": "Protect the Frontier", "level": 11, "col": 31.8, "row": 49.7,
            "objectives": [["monster", "Prowler slain: 2/8", 2, 8, False]], "area": 0.02}
GOLD = {"id": 47, "title": "Gold Dust Exchange", "level": 7, "col": 32.0, "row": 49.7,
        "objectives": [["item", "Gold Dust: 0/10", 0, 10, False]], "area": 0.05}  # its area holds Frontier's pin
LOVERS = {"id": 106, "title": "Young Lovers", "level": 6, "col": 32.1, "row": 49.85, "complete": True}
CANDLES = {"id": 60, "title": "Kobold Candles", "level": 7, "col": 31.95, "row": 49.6,
           "objectives": [["item", "Large Candle: 3/8", 3, 8, False]]}


def client(quests, data=True, followed=0, saved=None, before=None):
    L, sim, ns = boot(saved)
    L.execute(SETUP, sim, ns)
    if before:
        L.execute(before, sim, ns)
    G = L.globals()
    G.Data(data)
    sim.superTracked = followed
    G.Quests(L.table_from([L.table_from({k: L.table_from([L.table_from(o) for o in v]) if k == "objectives" else v
                                         for k, v in q.items()}) for q in quests]))
    sim.Slash("/mma toggle")
    sim.Run(1.5)
    return L, sim, ns, G


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
    L, sim, ns, G = client([FRONTIER, GOLD])
    view, Model = ns.UI.Window.view, ns.Model
    sim.FireScript(view, "OnEnter", False)

    def followed():
        return {e.quest for e in Model.Known("quests")[0].values() if e.followed}

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
    want = [
        ("Kobold Candles", False),
        ("|cff9d9d9dLevel|r |cffffd1007|r|cff9d9d9d" + SEP + "|r|cffff8040Group (3)|r", True),  # its tag (F28)
        ("Large Candle: 3/8", False),
        ("    |cff9d9d9dDropped by|r", True),
        ("    " + MOB + " |cffffffffOld Mole|r", True),
        ("    " + MOB + " |cffffffffTunnel Rat|r |cff3fbf3f4-5|r", True),
        ("    " + ELITE + " |cffffffffWick Keeper|r |cffffd1007|r |cff9d9d9dElite|r", True),
        ("    |cff9d9d9d(+2 more)|r", True),
        (" ", True),
        ("|cff9d9d9dTurn in to|r Candle Taker", True),
        ("|cff9d9d9dClick to follow|r", True),
    ]
    assert lines() == want
    assert list(S[tip.GetLeftLine(tip, 1)].textColor.values()) == [1, 0.82, 0]
    assert list(S[tip.GetLeftLine(tip, 10)].textColor.values()) == [0.85, 0.85, 0.85]
    sim.Step()  # the tooltip Commands, in Game's input step: the met one's portrait over a dark disc
    rat = S[tip.GetLeftLine(tip, 6)].text
    assert rat.startswith("    |TInterface\\CharacterFrame\\TempPortraitAlphaMask:14:14:") and rat.endswith(
        "|t |cffffffffTunnel Rat|r |cff3fbf3f4-5|r")
    assert lines()[4] == want[4]  # not met: its sword
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))

    # No QuestieDB data: the pin, its tooltip without droppers, sources or turn-in.
    L, sim, ns, G = client([CANDLES], data=False)
    tip, S = G.GameTooltip, sim.state
    G.Over(31.95, 49.6)
    sim.FireScript(ns.UI.Window.view, "OnEnter", False)
    sim.Step()
    p = pin(ns, G, "Quests", 60)
    assert S[p.inner].texture == 133633 and S[p.count].text == "3/8"  # an item QuestieDB doesn't know
    assert [S[tip.GetLeftLine(tip, i)].text for i in range(1, tip.NumLines(tip) + 1)] == [
        "Kobold Candles", "|cff9d9d9dLevel|r |cffffd1007|r", "Large Candle: 3/8", " ", "|cff9d9d9dClick to follow|r"]
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
