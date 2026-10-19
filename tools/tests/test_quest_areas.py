"""Quest areas on the simulated client (docs/v1-plan.md M2.4: ui/Areas.lua), end to end from the sim's
quest log (its blobs: Sim.blobShapes) through Game's parts and Inside, and Model:

  test_quest_areas: one QuestPOIFrame a map and style in the client's art (S53): the quest you follow
    filled blue over the rest, kill rust, gather green, other blue; each quest drawn into its frame's rect
    as laid out (L1); an estimate only for a kill or collect quest the game draws no area for, one for two
    within 0.6 r (S54); out of sight while the zoom moves, back where it lands (P5); the gear's toggles.
  test_quest_area_hover: an area under the cursor lit on top (HOVER) with its quest's tooltip, built once a
    hover (spike-bugs G7), up through a zoom; a pin's tooltip wins, its quest lit; off both, neither.
  test_quest_area_answers: whether the game draws an area at a pin (HasArea), frame by frame from a log
    change: a quest with an area never estimated, one without from its answer (Inside after deferred
    layout: the client draws a blob into a rect it laid out at a frame's end); a pin in another quest's
    area, none (Layers.lua:928-937); an area that comes with QUEST_POI_UPDATE takes the estimate's place
    and its frame is drawn again; asks past a frame's budget answered over the next frames.
  test_quests_priced: 25 quests with areas, the big map, the wheel and drags on the priced clock: the
    budgets by map state (docs/runtime.md).
  test_quests_storm: QUEST_LOG_UPDATE every frame for 10 s with 25 quests, nothing changing (a looting
    burst), the map shown and hidden: Lua allocation within its budget (50 KB/s), and none for quests
    while the map is hidden (Game reads them once it shows).
"""
from test_addon import errors
from test_quests import CANDLES, FRONTIER, GOLD, LOVERS, client

# QuestPOIFrame's setters, kept on the sim's state for the test (the sim's are no-ops).
RECORD = """local Sim = ...
local POI = getmetatable(CreateFrame("QuestPOIFrame")).__index
for _, k in ipairs({ "SetFillTexture", "SetBorderTexture", "SetFillAlpha", "SetBorderAlpha", "SetBorderScalar" }) do
	local fn = POI[k]
	POI[k] = function(self, v) Sim.state[self][k] = v; return fn(self, v) end
end"""

MINE = {"id": 62, "title": "The Fargodeep Mine", "level": 7, "col": 31.7, "row": 49.95,
        "objectives": [["event", "Scout through the Fargodeep Mine", 0, 1, False]], "area": 0.03}
HOGGER = {"id": 176, "title": "Wanted: Hogger", "level": 11, "col": 32.4, "row": 49.55,
          "objectives": [["monster", "Hogger slain: 0/1", 0, 1, False]]}  # no area: an estimate
CANDLES_NEAR = dict(CANDLES, col=32.45, row=49.6)  # no area either, within 0.6 r of Hogger's: the same one
ART = "Interface\\WorldMap\\UI-"
STYLES = {  # fill, border, width, its art, over the canvas
    "followed": (32, 120, 0.8, ART + "QuestBlob-Inside", 2), "kill": (0, 85, 0.6, ART + "ArchaeologyBlob-Inside", 1),
    "gather": (0, 55, 0.6, ART + "BonusObjectiveBlob-Inside", 1), "other": (0, 85, 0.6, ART + "QuestBlob-Inside", 1)}


def blobs(sim, ns):
    """The front's frames: {quests drawn: (fill, border, width, art, level over the canvas, drawn as laid out)}."""
    S, A = sim.state, ns.UI.Areas.layer
    p, out = A.front.pools.blob, {}
    for i in range(1, p.n + 1):
        f = p[i]
        st, laid = S[f], S[f].laid
        right = all(list(d.values()) == list(laid.values()) for d in st.blobs.values())
        out[tuple(sorted(st.blobs.keys()))] = (st.SetFillAlpha, st.SetBorderAlpha, st.SetBorderScalar, st.SetFillTexture,
                                               f.GetFrameLevel(f) - A.front.GetFrameLevel(A.front), right)
    return out


def test_quest_areas():
    L, sim, ns, G = client([FRONTIER, GOLD, MINE, HOGGER, CANDLES_NEAR, LOVERS], followed=52, before=RECORD)
    A, S, E, view = ns.UI.Areas.layer, sim.state, ns.UI.Engine, ns.UI.Window.view
    want = {(52,): STYLES["followed"] + (True,), (176,): STYLES["kill"] + (True,), (47, 60): STYLES["gather"] + (True,),
            (62,): STYLES["other"] + (True,)}
    assert blobs(sim, ns) == want and A.frame.GetAlpha(A.frame) == 1
    # One estimate for Hogger and Candles (the first's pin): a faint disc 110 yd across, 18 dashes.
    spots = A.front.pools.spot
    assert spots.n == 1
    o, r = spots[1], 110 / 533.33 * ns.UI.Camera.cam.zoom
    assert abs(o.acol - CANDLES_NEAR["col"]) < 1e-6 and abs(o.arow - CANDLES_NEAR["row"]) < 1e-6
    assert list(S[o.disc].vertex.values()) == [1, 0.85, 0.4, 0.05] and abs(S[o].width - 2 * r) < 1e-9
    assert len(o.dashes) == 18 and all(S[d].thickness == 1.5 and list(S[d].color.values()) == [1, 0.85, 0.4, 0.35]
                                       for d in o.dashes.values())

    # A zoom: out of sight from its first frame till it lands, then each drawn where it's laid out.
    sim.Wheel(view, 1)
    sim.Step()
    assert A.frame.GetAlpha(A.frame) == 0
    sim.Run(1)
    assert A.frame.GetAlpha(A.frame) == 1 and blobs(sim, ns) == want

    # The gear's: estimates off, then quests off (their areas with them), then areas off.
    E.SetLayer("questAreasApprox", False)
    sim.Run(0.5)
    assert A.front.pools.spot.n == 0 and len(blobs(sim, ns)) == 4
    E.SetLayer("quests", False)
    sim.Run(0.5)
    assert A.front.pools.blob.n == 0
    E.SetLayer("quests", True)
    E.SetLayer("questAreas", False)
    sim.Run(0.5)
    assert A.front is None
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_quest_area_hover():
    L, sim, ns, G = client([FRONTIER, GOLD], before=RECORD)
    tip, S, view, same = G.GameTooltip, sim.state, ns.UI.Window.view, L.eval("rawequal")
    built = L.eval("""function(tip) local n = { 0 }
        tip.SetOwner = function(self, ...) n[1] = n[1] + 1; return getmetatable(self).__index.SetOwner(self, ...) end
        return n end""")(tip)

    def lit():
        """The quests the lit frame (HOVER's alphas) shows."""
        for f in sim.Frames().values():
            if f.GetObjectType(f) == "QuestPOIFrame" and S[f].SetFillAlpha == 40 and f.IsVisible(f):
                assert S[f].SetBorderAlpha == 150 and S[f].SetBorderScalar == 0.8
                return sorted(S[f].blobs.keys())
        return []

    sim.FireScript(view, "OnEnter", False)
    G.Over(32.15, 49.7)  # Gold Dust's area, no pin under it
    sim.Run(0.5)
    assert S[tip].shown and S[tip.GetLeftLine(tip, 1)].text == "Gold Dust Exchange" and built[1] == 1
    assert not same(tip.GetOwner(tip), ns.UI.Quests.front.pools.pin[1]) and lit() == [47]
    # A wheel tick with the cursor on it (east of the pin): the layer out of sight till the zoom lands, the
    # tooltip up throughout, built once.
    sim.Wheel(view, 1)  # (at the view's centre)
    G.Over(32.25, 49.7)
    up, hid = [], 0
    for _ in range(40):
        sim.Step()
        up.append(S[tip].shown and S[tip.GetLeftLine(tip, 1)].text == "Gold Dust Exchange")
        hid += ns.UI.Areas.layer.frame.GetAlpha(ns.UI.Areas.layer.frame) == 0
    assert hid > 5 and all(up) and built[1] == 1, (hid, up)
    G.Over(31.8, 49.7)  # Frontier's pin, in Gold Dust's area: its tooltip, its quest lit
    sim.Run(0.5)
    assert S[tip.GetLeftLine(tip, 1)].text == "Protect the Frontier" and built[1] == 2 and lit() == [52]
    G.Over(32.15, 49.7)  # back: the area's again, once
    sim.Run(0.5)
    assert S[tip.GetLeftLine(tip, 1)].text == "Gold Dust Exchange" and built[1] == 3
    G.Over(33.0, 49.3)  # off both
    sim.Step()
    assert not S[tip].shown and lit() == []
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_quest_area_answers():
    L, sim, ns, G = client([LOVERS], before=RECORD)
    S, A = sim.state, ns.UI.Areas.layer

    def estimates():
        return {e.quest for e in ns.Model.Known("quests")[0].values() if e.estimate}

    def spots():
        p = A.front.pools.spot
        return p.n if p else 0

    def drawn(quest):
        """UI's frames that show quest's blob, drawn where they're laid out."""
        p = A.front.pools.blob
        return [p[i] for i in range(1, p.n + 1) if S[p[i]].blobs and quest in S[p[i]].blobs]

    # A kill quest with an area and one without, and a kill quest with none whose pin is in Gold Dust's.
    add = L.eval("""function(Sim, Atlas, id, col, row, area, kind)
        local x, y = Atlas.TileToMap(1429, col, row)
        Sim.quests[id] = { title = "Quest " .. id, level = 7, map = 1429, x = x, y = y, complete = false,
            objectives = { { type = kind or "monster", text = "x: 0/5", numFulfilled = 0, numRequired = 5, finished = false } } }
        Sim.blobShapes[id] = area and { x, y, area } or nil
    end""")
    add(sim, ns.Atlas, 52, 31.8, 49.7, 0.02)
    add(sim, ns.Atlas, 176, 32.4, 49.55)
    add(sim, ns.Atlas, 47, 32.0, 49.7, 0.05, "item")
    add(sim, ns.Atlas, 53, 31.95, 49.72)  # in Gold Dust's area, none of its own
    sim.FireEvent("QUEST_LOG_UPDATE")
    seen = []
    for _ in range(40):
        sim.Step()
        seen.append(estimates())
    assert not any(52 in e or 47 in e or 53 in e for e in seen), seen
    first = next(i for i, e in enumerate(seen) if 176 in e)
    assert 15 <= first <= 25 and all(176 in e for e in seen[first:])  # the 0.3 s coalesce, then its answer
    assert spots() == 1

    # Hogger's area comes later (QUEST_POI_UPDATE): the estimate goes, its area drawn in its stead.
    x, y = ns.Atlas.TileToMap(1429, 32.4, 49.55)
    sim.blobShapes[176] = L.table_from([x, y, 0.02])
    assert drawn(176)  # (drawn before too: the client draws nothing for a quest without an area)
    for c in A.canvases.values():  # both canvases' frames forget what they drew
        p = c.pools.blob
        for i in range(1, (p.n if p else 0) + 1):
            S[p[i]].blobs = L.table()
    sim.FireEvent("QUEST_POI_UPDATE")
    sim.Run(1)
    assert 176 not in estimates() and spots() == 0 and ns.Game.oracles.HasArea(176)
    f = drawn(176)
    assert f and list(S[f[0]].blobs[176].values()) == list(S[f[0]].laid.values())

    # A frame's asks past its budget (a planted 0.5 ms a draw): nil, asked again till every one answers.
    for i in range(16):
        add(sim, ns.Atlas, 2000 + i, 30.5 + i % 4 * 0.5, 49 + i // 4 * 0.4, 0.02)
    L.execute("""local Sim = ...
        local POI = getmetatable(CreateFrame("QuestPOIFrame")).__index
        local draw = POI.DrawBlob
        POI.DrawBlob = function(self, ...) Sim.Spend(0.5); return draw(self, ...) end""", sim)
    sim.Price(True)
    sim.Run(8)  # past the graces
    sim.FireEvent("QUEST_LOG_UPDATE")
    sim.Run(3)
    sim.Price(False)
    assert not estimates() & set(range(2000, 2016))
    slow = [(x.name, x.max) for x in ns.Runtime.FrameStats().slow.values() if x.name.startswith(("game.oracle", "model"))]
    assert not slow, slow
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


# Quests to pick up on every zone of the Eastern Kingdoms, n a zone (the sim's log has 1).
OFFERS = """local sim, ns, n = ...
    local id = 5000
    for _, z in ipairs(ns.Atlas.Zones(0)) do
        local list = {}
        for i = 1, n do
            id = id + 1
            list[i] = { questID = id, questName = "Offer " .. id, questLineName = "", questLineID = 1, x = 0.1 + i % 4 * 0.2,
                y = 0.1 + math.floor(i / 4) * 0.25, isHidden = false, inProgress = false }
        end
        sim.offers[z.uiMapID] = list
    end
    sim.FireEvent("QUESTLINE_UPDATE", true)"""


def test_quests_priced():
    """Script (b)'s quest hub, 25 quests about you (one followed; 10 kill or collect quests with no area: their
    estimates), the big map: the wheel in and out and drags on the priced clock. At rest p95 <= 1 ms, moving
    p95 <= 5 ms, none over 8, no call over its budget nor a layout's stretch past it."""
    kinds = [["monster", "Kobold slain: 1/8", 1, 8, False], ["item", "Candle: 2/8", 2, 8, False],
             ["event", "Scout the mine", 0, 1, False]]
    quests = [{"id": 1000 + i, "title": f"Quest {i}", "level": 6 + i % 5, "col": 31.95 + (i % 5 - 2) * 0.35,
               "row": 49.75 + (i // 5 - 2) * 0.3, "objectives": [kinds[i % 3]],
               **({} if i < 15 and i % 3 != 2 else {"area": 0.02 + i % 3 * 0.01})} for i in range(25)]
    L, sim, ns, G = client(quests, followed=1012)
    assert len(ns.Model.Known("quests")[0]) == 25
    assert sum(1 for e in ns.Model.Known("quests")[0].values() if e.estimate) == 10
    L.execute("""local sim, ns = ...
        local view, M = ns.UI.Window.view, ns.UI.Motion
        sim.Press("M")
        sim.Price(true)
        sim.Run(12) -- past the graces
        local function Wheel(d, n, gap) for _ = 1, n do sim.Wheel(view, d); sim.Run(gap) end end
        local function Drag(dx, dy, frames)
            sim.MoveCursorTo(view)
            sim.buttonsDown.LeftButton = true
            sim.FireScript(view, "OnMouseDown", "LeftButton")
            for _ = 1, frames do sim.cursorX, sim.cursorY = sim.cursorX + dx, sim.cursorY + dy; sim.Step() end
            sim.buttonsDown.LeftButton = nil
            sim.FireScript(view, "OnMouseUp", "LeftButton")
        end
        for _ = 1, 2 do Wheel(1, 4, 0.4); sim.Run(1); Wheel(-1, 4, 0.4); sim.Run(1) end
        for i = 1, 4 do Drag(i % 2 == 0 and 30 or -30, 10, 20); sim.Run(1.5) end
        sim.Price(false)""", sim, ns)
    fs = ns.Runtime.FrameStats()
    by = {k: v for k, v in fs.byState.items()}
    print(f"25 quests, priced: {fs.frames} frames, p95 {fs.p95} max {fs.max}; "
          + ", ".join(f"{k} {v.frames} p95 {v.p95} p99 {v.p99}" for k, v in sorted(by.items())))
    assert by["big"].p95 <= 1 and by["big"].p99 <= 5 and by["zoom"].p95 <= 5 and by["drag"].p95 <= 5 and fs.max <= 8
    assert not list(fs.slow.values()) and not list(fs.gaps.values()), (list(fs.slow.values()), list(fs.gaps.values()))
    assert not errors(sim, ns), errors(sim, ns)


def test_quests_storm():
    kinds = [["monster", "Kobold slain: 1/8", 1, 8, False], ["item", "Candle: 2/8", 2, 8, False],
             ["event", "Scout the mine", 0, 1, False]]
    quests = [{"id": 1000 + i, "title": f"Quest {i}", "level": 6 + i % 5, "col": 31.95 + (i % 5 - 2) * 0.35,
               "row": 49.75 + (i // 5 - 2) * 0.3, "objectives": [kinds[i % 3]], "area": 0.02 + i % 3 * 0.01}
              for i in range(25)]
    for hidden in (False, True):
        L, sim, ns, G = client(quests, followed=1012)
        sim.Price(True)
        sim.Run(10)  # past the graces
        if hidden:
            sim.Slash("/mma toggle")
            sim.Run(1)
        L.execute("local sim = ...; for _ = 1, 600 do sim.FireEvent('QUEST_LOG_UPDATE'); sim.Step() end", sim)
        fs = ns.Runtime.FrameStats()
        alloc = {a.name: a.kbPerSec for a in fs.alloc.values()}
        print(f"storm, map {'hidden' if hidden else 'shown'}: {fs.kbPerSec} KB/s; game.part quests "
              f"{alloc.get('game.part quests', 0)}, offers {alloc.get('game.part offers', 0)}")
        assert fs.kbPerSec <= 50 and alloc.get("game.part quests", 0) <= (0 if hidden else 25)
        assert not errors(sim, ns), errors(sim, ns)


def test_offers_priced():
    """5 quests to pick up a zone over the Eastern Kingdoms (130; offers have no minimum zoom, as the spike's
    Layers.lua:636-664) with 25 quests, the big map: the wheel out to the continent and back, drags there, on
    the priced clock. No layout's stretch past its budget, no frame over 8 ms; the one call over its budget is
    the draw moving every offer at the continent's zoom, held to 2.5 ms (the counted clock's 3 us a SetPoint,
    ~10x the client's: docs/runtime.md)."""
    quests = [{"id": 1000 + i, "title": f"Quest {i}", "level": 7, "col": 31.95 + (i % 5 - 2) * 0.35,
               "row": 49.75 + (i // 5 - 2) * 0.3, "objectives": [["monster", "Kobold slain: 1/8", 1, 8, False]],
               "area": 0.02} for i in range(25)]
    L, sim, ns, G = client(quests)
    L.execute(OFFERS, sim, ns, 5)
    sim.Run(0.5)
    assert len(ns.Model.Known("offers")[0]) == 130
    L.execute("""local sim, ns = ...
        local view = ns.UI.Window.view
        sim.Press("M")
        sim.Price(true)
        sim.Run(12) -- past the graces
        local function Wheel(d, n, gap) for _ = 1, n do sim.Wheel(view, d); sim.Run(gap) end end
        Wheel(-1, 10, 0.6)
        sim.Run(1)
        for i = 1, 3 do sim.Drag(view, i % 2 == 0 and 300 or -300, 100, 20); sim.Run(1) end
        Wheel(1, 10, 0.6)
        sim.Run(1)
        sim.Price(false)""", sim, ns)
    fs = ns.Runtime.FrameStats()
    slow = {x.name: x.max for x in fs.slow.values()}
    by = {k: v for k, v in fs.byState.items()}
    print(f"130 offers, priced: max {fs.max}; slow {slow}; " + ", ".join(f"{k} p95 {v.p95}" for k, v in sorted(by.items())))
    assert not list(fs.gaps.values()) and fs.max <= 8 and set(slow) <= {"map: draw"} and slow.get("map: draw", 0) <= 2.5
    assert not errors(sim, ns), errors(sim, ns)
