"""Model alone (plain Lua, tools/tests/replay.lua) on the fixture streams: Known("quests") and
Known("offers") (docs/v1-plan.md M2.3).

  test_quests_model: the quests stream (fixtures/streams/quests.lua), Inside from its areas: each
    pin's kind (in progress, ready to turn in, followed), inner icon, count and need; an estimate
    only for a kill, collect or interact quest the game draws no area for, asked a frame on; what
    Atlas knows (DATA: made-up rows, not QuestieDB's): at most 3 droppers lowest first and how
    many more, the objects it's in, who sells it, who takes it in; an unchanged quest keeps its
    entry and isn't asked again.
  test_quests_model_colours: the quest log's difficulty colours (S47), quests' and droppers'.
  test_quests_model_merge: no areas at all: an estimate each, shared within 0.6 r (F30).
  test_quests_model_no_data: no QuestieDB data: the same pins, no droppers, sources or turn-in.
  test_offers_model: the offers stream: one a quest, none in your log (F40).
"""
from lupa import lua51

from test_blips import ROOT, lua_tools

# Made-up rows in Data's formats (docs/atlas-data.md), for the quests in the stream.
DATA = """return {
    formats = { Npcs = 1, Objects = 1, Items = 1, Quests = 1, ItemIcons = 1 },
    ItemIcons = { [772] = 133750, [773] = 133848 },
    Items = { -- name, npcDrops, objectDrops, itemDrops, vendors
        [772] = { "Large Candle", { 9001, 9002, 9003, 9004, 9005 } },
        [773] = { "Gold Dust", nil, { 9101, 9102, 9103 } },
        [1931] = { "Huge Gnoll Claw", nil, nil, nil, { 9201 } },
    },
    Npcs = { -- name, subName, minLevel, maxLevel, rank
        [9001] = { "Candle Thief", nil, 6, 8 },
        [9002] = { "Tunnel Rat", nil, 4, 5 },
        [9003] = { "Wick Keeper", nil, 7, 7, 1 },
        [9004] = { "Old Mole", nil, 0, 0 },
        [9005] = { "Deep Digger", nil, 12, 14, 4 },
        [9201] = { "Claw Trader" },
        [9301] = { "Candle Taker" },
    },
    Objects = { [9101] = { "Dusty Crate" }, [9102] = { "Gold Chip" }, [9103] = { "Old Chest" }, [9401] = { "Drop Box" } },
    Quests = { -- name, level, requiredLevel, faction, races, classes, startedBy, finishedBy
        [60] = { "Kobold Candles", 7, nil, nil, nil, nil, nil, { { 9301 } } },
        [176] = { "Wanted:  \\"Hogger\\"", 11, nil, nil, nil, nil, nil, { nil, { 9401 } } },
    },
}"""
RED, ORANGE, YELLOW, GREEN, GREY = (1, 0.1, 0.1), (1, 0.5, 0.25), (1, 0.82, 0), (0.25, 0.75, 0.25), (0.5, 0.5, 0.5)
ACTIVE, TURN_IN = "Quest-In-Progress-Icon-yellow", "UI-QuestIcon-TurnIn-Normal"
CANDLES, GOLD, MINE, FRONTIER, HOGGER, LOVERS, CLEANUP, JASPER = 60, 47, 62, 52, 176, 106, 7, 76


def setup(data=True, areas=True):
    L = lua51.LuaRuntime(unpack_returned_tuples=True)
    tools = lua_tools(L)
    stream = tools.Stream(ROOT, "quests")
    model = tools.Model(ROOT, L.execute(DATA) if data else None)
    model.Load(L.eval("{ _v = 1, rares = {}, blips = {} }"))
    # Inside from the stream's areas (or none), each ask noted.
    oracles, asks = L.eval("""function(o) local asks = {}
        return { Inside = function(q, c, r) asks[#asks + 1] = q return o.Inside(q, c, r) end }, asks end""")(
        tools.Oracles(stream if areas else L.table()))
    return L, stream, model, oracles, asks


def known(model, kind="quests"):
    entries, rev = model.Known(kind)
    return {e.quest: e for e in entries.values()}, rev


def rgb(e):
    return e.color and tuple(e.color.values())


def test_quests_model():
    L, stream, model, oracles, asks = setup()
    same = L.eval("function(a, b) return a == b end")
    model.Observe(stream[1], oracles)  # log1, frame 1: asked, not answered
    q, rev = known(model)
    assert sorted(q) == sorted([CANDLES, GOLD, MINE, FRONTIER, HOGGER, LOVERS, CLEANUP]) and rev == 1
    assert list(asks.values()) == [CANDLES, GOLD, FRONTIER, HOGGER]  # kill, collect, interact: not event, not done
    assert not any(e.estimate for e in q.values())

    c = q[CANDLES]
    assert (c.key, c.kind, c.name, c.live, c.level, c.followed, c.complete) == \
        ("quest:60", "quests", "Kobold Candles", True, 7, True, False)
    assert (c.pos.col, c.pos.row, c.areaMap) == (31.775, 50.39, 1429)
    assert (c.icon.atlas, c.count, c.inner.texture, c.need, rgb(c)) == (ACTIVE, "3/8", 133750, "gather", YELLOW)
    assert (q[GOLD].inner.texture, q[GOLD].count) == (133848, "0/10")
    assert (q[FRONTIER].inner.texture, q[FRONTIER].count, q[FRONTIER].need) == (135274, "2/8", "kill")
    assert (q[HOGGER].inner.texture, q[HOGGER].count, rgb(q[HOGGER])) == (133633, None, ORANGE)  # a claw: no icon known
    assert (q[MINE].inner, q[MINE].count, q[MINE].need) == (None, None, "other")
    for done in (LOVERS, CLEANUP):
        e = q[done]
        assert (e.icon.atlas, e.complete, e.count, e.inner, e.need, e.objectives) == (TURN_IN, True, None, None, None, None)
    assert rgb(q[CLEANUP]) == GREY

    # Tooltip lines: droppers lowest level first, 3 and how many more; else objects; else vendors.
    o = c.objectives[1]
    assert (o.text, o.finished, o.more) == ("Large Candle: 3/8", False, 2)
    drops = [(m.npc, m.name, m.lo, m.hi, m.color and tuple(m.color.values()), m.rank) for m in o.drops.values()]
    assert drops == [(9004, "Old Mole", None, None, None, None), (9002, "Tunnel Rat", 4, 5, GREEN, None),
                     (9003, "Wick Keeper", 7, 7, YELLOW, "Elite")]
    assert (q[GOLD].objectives[1]["from"], q[GOLD].objectives[1].drops) == ("Dusty Crate, Gold Chip (+1 more)", None)
    assert q[HOGGER].objectives[1].sold == "Claw Trader"
    assert [(x.text, x.finished, x.drops) for x in q[FRONTIER].objectives.values()] == \
        [("Prowler slain: 2/8", False, None), ("Young Forest Bear slain: 0/5", False, None)]
    assert (c.turnIn, q[HOGGER].turnIn, q[GOLD].turnIn) == ("Candle Taker", "Drop Box", None)  # an npc, else an object

    # Answered a frame on: the game draws an area for all but Hogger's; only that entry is new.
    model.Observe(stream[2], oracles)
    q2, rev = known(model)
    assert rev == 2 and len(asks) == 8 and sorted(list(asks.values())[4:]) == sorted([CANDLES, GOLD, FRONTIER, HOGGER])
    h = q2[HOGGER]
    assert same(h.estimate, h.pos) and not any(e.estimate for e in q2.values() if e.quest != HOGGER)
    assert all(same(q[k], q2[k]) for k in q if k != HOGGER) and not same(q[HOGGER], h)

    model.Observe(stream[3], oracles)  # 4/8: that quest alone changes, asked again
    q3, rev = known(model)
    assert rev == 3 and q3[CANDLES].count == "4/8" and list(asks.values())[8:] == [CANDLES]
    assert all(same(q2[k], q3[k]) for k in q2 if k != CANDLES)
    model.Observe(stream[4], oracles)  # its answer: an area still
    assert known(model)[1] == 3 and len(asks) == 10

    model.Observe(stream[5], oracles)  # the follow moves
    q5, rev = known(model)
    assert (q5[CANDLES].followed, q5[MINE].followed, rev) == (False, True, 4)
    model.Observe(stream[6], oracles)  # the mine done: its pin at the turn-in
    m = known(model)[0][MINE]
    assert (m.icon.atlas, m.complete, m.pos.col, m.pos.row) == (TURN_IN, True, 31.862, 49.748)
    model.Observe(stream[7], oracles)  # handed in, another taken
    q7, rev = known(model)
    assert sorted(q7) == sorted([CANDLES, GOLD, FRONTIER, HOGGER, LOVERS, CLEANUP, JASPER]) and rev == 6
    assert len(asks) == 12  # nothing asked but the changed
    model.Observe(stream[8], oracles)  # loading: not known, the last belief stands
    model.Observe(stream[9], oracles)
    assert known(model)[1] == 6
    model.Observe(stream[10], oracles)  # abandoned: known and empty
    assert known(model)[0] == {} and known(model)[1] == 7


def test_quests_model_colours():
    L, stream, model, oracles, _ = setup()
    level = L.eval("""function(obs, frame, level)
        local o = {} for k, v in pairs(obs) do o[k] = v end
        o.frame, o.you = frame, setmetatable({ level = level }, { __index = obs.you })
        return o end""")
    model.Observe(stream[1], oracles)
    model.Observe(level(stream[1], 2, 4), oracles)
    q = known(model)[0]
    assert [rgb(q[k]) for k in (HOGGER, FRONTIER, CANDLES, LOVERS)] == [RED, RED, ORANGE, YELLOW]  # +7, +6, +3, +2
    model.Observe(level(stream[1], 3, 13), oracles)
    q = known(model)[0]
    assert [rgb(q[k]) for k in (HOGGER, CANDLES, CLEANUP)] == [YELLOW, GREEN, GREY]  # -2, -6, -11 (trivial)
    drops = {m.name: m.color and tuple(m.color.values()) for m in q[CANDLES].objectives[1].drops.values()}
    assert drops == {"Old Mole": None, "Tunnel Rat": GREY, "Wick Keeper": GREY}  # 8, 6 below you: past 5 (3: green)


def test_quests_model_merge():
    L, stream, model, oracles, _ = setup(areas=False)
    same = L.eval("function(a, b) return a == b end")
    model.Observe(stream[1], oracles)
    model.Observe(stream[2], oracles)
    q = known(model)[0]
    est = {k: e.estimate for k, e in q.items() if e.estimate}
    assert sorted(est) == sorted([CANDLES, GOLD, FRONTIER, HOGGER])  # not the mine (go there), nor the done
    assert same(est[CANDLES], q[CANDLES].pos) and same(est[GOLD], est[CANDLES])  # 0.025, 0.09 tiles apart: one disc
    assert same(est[FRONTIER], q[FRONTIER].pos) and same(est[HOGGER], q[HOGGER].pos)


def test_quests_model_no_data():
    L, stream, model, oracles, _ = setup(data=False)
    model.Observe(stream[1], oracles)
    model.Observe(stream[2], oracles)
    q = known(model)[0]
    assert len(q) == 7 and q[HOGGER].estimate
    assert (q[CANDLES].inner.texture, q[CANDLES].count) == (133633, "3/8")  # the bag: no item known
    o = q[CANDLES].objectives[1]
    assert (o.text, o.drops, o.more, o["from"], o.sold) == ("Large Candle: 3/8", None, None, None, None)
    assert not any(e.turnIn for e in q.values())


def test_offers_model():
    L = lua51.LuaRuntime(unpack_returned_tuples=True)
    tools = lua_tools(L)
    stream = tools.Stream(ROOT, "offers")
    model = tools.Model(ROOT)
    model.Load(L.eval("{ _v = 1, rares = {}, blips = {} }"))
    oracles, same = tools.Oracles(stream), L.eval("function(a, b) return a == b end")
    seen = []
    for i in range(1, len(stream) + 1):
        model.Observe(stream[i], oracles)
        offers, rev = known(model, "offers")
        seen.append((sorted(offers), rev))
        if i == 2:
            first = offers
            f = offers[40]
            assert (f.key, f.kind, f.name, f.line, f.live, f.icon.atlas, f.text) == \
                ("quest:40", "offers", "A Fishy Peril", "The Lost Guards", True, "QuestNormal", "Quest to pick up")
            assert (f.pos.col, f.pos.row) == (31.863, 49.806) and offers[88].line is None
        if i == 4:
            assert all(same(first[k], offers[k]) for k in offers)
    assert seen == [([], 0), ([40, 83, 85, 88], 1), ([40, 83, 85, 88], 1), ([83, 85, 88], 2),
                    ([22, 36, 64, 83, 85, 88], 3), ([22, 36, 64, 83, 85, 88], 3), ([], 4)]

    # In your log (in progress): not offered; offered twice: once.
    obs = L.eval("""function(obs, offers) local o = {} for k, v in pairs(obs) do o[k] = v end
        local twice = {} for _, x in ipairs(offers) do twice[#twice + 1] = x end
        twice[#twice + 1] = offers[1]
        o.offers, o.quests = twice, { { id = 88, title = "Princess Must Die!", complete = false, followed = false, objectives = {} } }
        return o end""")(stream[len(stream)], stream[5].offers)
    model.Observe(obs, oracles)
    offers, rev = known(model, "offers")
    assert sorted(offers) == [22, 36, 64, 83, 85] and rev == 5
