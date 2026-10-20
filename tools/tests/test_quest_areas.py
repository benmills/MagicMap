"""Quest areas on the simulated client (docs/v1-plan.md M2.4: ui/Areas.lua), end to end from the sim's
quest log (its blobs: Sim.blobShapes) through Game's parts and Inside, and Model:

  test_quest_areas: one QuestPOIFrame a map and style in the client's art (S53): the quest you follow
    filled blue over the rest, kill rust, gather green, other blue; each quest drawn into its frame's rect
    as laid out (L1); out of sight while the zoom moves, back where it lands (P5); the gear's toggles.
  test_quest_area_hover: an area under the cursor lit on top (HOVER) with its quest's tooltip, built once a
    hover (spike-bugs G7), up through a zoom and with the cursor on something standing on the view; a pin's
    tooltip wins, its quest lit; off both, neither.
  test_quest_area_big_zone: a 12-tile zone at the clamp (Stranglethorn at zoom 800, 9,572 px wide), flown to
    from Elwynn and wheeled in about you: its frame on one anchor, laid out in its map's rect, each quest
    drawn there (L1).
  test_quests_priced: 25 quests with areas, the big map, the wheel and drags on the priced clock: the
    budgets by map state (docs/runtime.md).
  test_quests_first_open: script (b)'s hub, the map's first open past login's grace (b12), priced: its
    slowest frame within the budget (50 ms).
  test_quests_storm: QUEST_LOG_UPDATE every frame for 10 s with 25 quests and 130 to pick up, nothing
    changing (a looting burst), the map shown and hidden: Lua allocation over the storm alone within its
    budget (50 KB/s), the zones and offers not read again, and nothing for quests while the map is
    hidden (Game reads them once it shows).
  test_quests_ticks: a count ticking every 2 s, with QUEST_POI_UPDATE each time and without: within the
    budget over the stretch, the game's areas' version a new list of the same entries.
The sim's C_ calls make their tables anew each call, as the client's do (wowsim.lua Fresh): the garbage
measured is the client's too.
"""
from test_addon import errors
from test_quests import CANDLES, FRONTIER, GOLD, LOVERS, client, known

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
          "objectives": [["monster", "Hogger slain: 0/1", 0, 1, False]]}
CANDLES_NEAR = dict(CANDLES, col=32.45, row=49.6)
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

    # A zoom: out of sight from its first frame till it lands, then each drawn where it's laid out.
    sim.Wheel(view, 1)
    sim.Step()
    assert A.frame.GetAlpha(A.frame) == 0
    sim.Run(1)
    assert A.frame.GetAlpha(A.frame) == 1 and blobs(sim, ns) == want

    # The gear's: quests off (their areas with them), then areas off.
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
    sim.cursorX = sim.cursorY = 0  # (off the view)
    sim.Step()
    assert not S[tip].shown
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
    # Onto something standing on the view there (a control, another addon's pin: the view's OnLeave): still
    # over the view's rect, the area lit and its tooltip up (the spike's viewport:IsMouseOver()).
    sim.FireScript(view, "OnLeave", False)
    sim.Run(0.5)
    assert S[tip].shown and S[tip.GetLeftLine(tip, 1)].text == "Gold Dust Exchange" and built[1] == 3 and lit() == [47]
    G.Over(33.0, 49.3)  # off both
    sim.Step()
    assert not S[tip].shown and lit() == []
    sim.cursorX = sim.cursorY = 0  # off the view
    sim.Step()
    assert not S[tip].shown and lit() == []
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_quest_area_big_zone():
    """Stranglethorn's areas (12 tiles by 8: 9,572 px by 6,382 at zoom 800), the map shown at Elwynn's hub, you
    flown to Stranglethorn's south and the wheel in to the clamp about you: its frame on one anchor as the
    point of its rect nearest the canvas's origin moves (two would size it: 515 by 114 px, found at the M2
    gate; the spike's PlaceBlob clears them, Layers.lua:808), laid out in its map's rect, each quest drawn
    there; no anchor on the map past 4,096 px (the harness's T.Anchors)."""
    import sim as tools_sim
    c0, r0, c1, r1 = 27.836, 52.941, 39.801, 60.918  # Data/UiMaps.lua's 1434

    def at(x, y):
        return c0 + (c1 - c0) * x, r0 + (r1 - r0) * y
    quests = [{"id": 9000 + i, "title": f"Quest {i}", "level": 7, "map": 1434, "col": at(x, y)[0], "row": at(x, y)[1],
               "objectives": [["monster", "Raptor slain: 0/5", 0, 5, False]], "area": 0.03}
              for i, (x, y) in enumerate(((0.1, 0.1), (0.5, 0.5), (0.9, 0.9)))]
    L, sim, ns, G = client(quests)
    tools_sim.harness(L).Anchors(sim, ns, L.eval("CreateFrame('Frame'):CreateLine()"))
    S, A, view, cam = sim.state, ns.UI.Areas.layer, ns.UI.Window.view, ns.UI.Camera.cam
    sim.player.col, sim.player.row = at(0.9, 0.9)  # (from Elwynn: a flight's end)
    sim.Run(2)
    for _ in range(16):
        sim.Wheel(view, 1)
        sim.Run(0.1)
    sim.Run(2)
    p = A.front.pools.blob
    assert cam.zoom == 800 and A.frame.GetAlpha(A.frame) == 1 and p.n == 1
    f = p[1]
    laid, r = S[f].laid, ns.Atlas.MapRect(1434)
    assert len(S[f].points) == 1
    assert abs(laid[3] - (r.col1 - r.col0) * 800) < 1e-6 and abs(laid[4] - (r.row1 - r.row0) * 800) < 1e-6, list(laid.values())
    assert sorted(S[f].blobs.keys()) == [9000, 9001, 9002]
    assert all(list(d.values()) == list(laid.values()) for d in S[f].blobs.values())
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
    """Script (b)'s quest hub, 25 quests about you (one followed; 10 kill or collect quests with no area),
    the big map: the wheel in and out and drags on the priced clock, twice. At rest p95 <= 1 ms, moving
    p95 <= 5 ms, none over 8, no call over its budget nor a layout's stretch past it. And the Lua allocation over
    that stretch alone at the client's prices (FREE: the sim's widget state left out, ~335 KB/s of the 425 the sim
    read there before M1.15): the first time, its garbage <= 50 KB/s, and all of it held under 100 so a pool that
    grows shows (the borders' Lines at the zooms new to the session, the town services gathered as the view comes
    to them: kept, made once a session, docs/runtime.md); once more, all of it <= 50 KB/s."""
    kinds = [["monster", "Kobold slain: 1/8", 1, 8, False], ["item", "Candle: 2/8", 2, 8, False],
             ["event", "Scout the mine", 0, 1, False]]
    quests = [{"id": 1000 + i, "title": f"Quest {i}", "level": 6 + i % 5, "col": 31.95 + (i % 5 - 2) * 0.35,
               "row": 49.75 + (i // 5 - 2) * 0.3, "objectives": [kinds[i % 3]],
               **({} if i < 15 and i % 3 != 2 else {"area": 0.02 + i % 3 * 0.01})} for i in range(25)]
    L, sim, ns, G = client(quests, followed=1012, before=RAW + "\n" + FREE)
    assert len(ns.Model.Known("quests")[0]) == 25
    L.execute("""local sim, ns = ...
        local view = ns.UI.Window.view
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
        function WheelAndDrags()
            for _ = 1, 2 do Wheel(1, 4, 0.4); sim.Run(1); Wheel(-1, 4, 0.4); sim.Run(1) end
            for i = 1, 4 do Drag(i % 2 == 0 and 30 or -30, 10, 20); sim.Run(1.5) end
        end""", sim, ns)
    first = kept_stretch(L, sim, ns, G.WheelAndDrags)
    again = kept_stretch(L, sim, ns, G.WheelAndDrags)
    sim.Price(False)
    fs = ns.Runtime.FrameStats()
    by = {k: v for k, v in fs.byState.items()}
    top = lambda by: ", ".join(f"{k} {v}" for k, v in sorted(by.items(), key=lambda kv: -kv[1])[:4])
    print(f"25 quests, priced: {fs.frames} frames, p95 {fs.p95} max {fs.max}; "
          + ", ".join(f"{k} {v.frames} p95 {v.p95} p99 {v.p99}" for k, v in sorted(by.items()))
          + f"; the wheel and drags at the client's prices: {first[0]} KB/s, {first[2]} of it kept, garbage"
          f" {first[0] - first[2]:.1f} ({top(first[1])}); once more {again[0]} ({top(again[1])})")
    assert by["big"].p95 <= 1 and by["big"].p99 <= 5 and by["zoom"].p95 <= 5 and by["drag"].p95 <= 5 and fs.max <= 8
    assert not list(fs.slow.values()) and not list(fs.gaps.values()), (list(fs.slow.values()), list(fs.gaps.values()))
    assert first[0] - first[2] <= 50 and first[0] <= 100 and again[0] <= 50, (first, again)
    assert not errors(sim, ns), errors(sim, ns)


# What the client's widget calls allocate in its Lua heap: nothing (C functions; a region's own table aside). The
# sim's keep their state in Lua tables (wowsim.lua S[region]: ~750 bytes a region made, more as it's set), which
# made the pools' first growth the biggest maker (borders, tiles: ~100 KB/s over the soak's first round; ~335 of
# test_quests_priced's wheel and drags' 425 before M1.15). Taken
# out of collectgarbage("count") as LUA_PRICE takes its hook's (tools/sim.py), so Runtime's KB is ours and the
# C_ API's tables' (the client's, as in game); a script a call fires (OnShow, OnSizeChanged) counts as ours.
FREE = """local sim = ...
local gc = collectgarbage
local kb, depth, inner = 0, 0, 0
collectgarbage = function(opt, ...)
    if opt == "count" then return gc("count") - kb end
    local a, b = gc(opt, ...)
    if opt == "collect" then kb = 0 end
    return a, b
end
local function Free(fn)
    return function(...)
        if depth > 0 then return fn(...) end
        depth = 1
        local k0, i0 = gc("count"), inner
        local a, b, c, d, e, f, g, h = fn(...)
        kb, depth = kb + gc("count") - k0 - (inner - i0), 0
        return a, b, c, d, e, f, g, h
    end
end
local fire = sim.FireScript
sim.FireScript = function(...)
    if depth == 0 then return fire(...) end
    local k0 = gc("count")
    depth = 0
    fire(...)
    depth, inner = 1, inner + gc("count") - k0
end
local done = {}
local function Methods(obj)
    local m = getmetatable(obj).__index
    while m and not done[m] do
        done[m] = true
        for name, fn in pairs(m) do
            if type(fn) == "function" then m[name] = Free(fn) end
        end
        m = getmetatable(m) and getmetatable(m).__index
    end
end
local f = CreateFrame("Frame")
for _, t in ipairs({ "Button", "CheckButton", "Cooldown", "EditBox", "GameTooltip", "QuestPOIFrame", "ScrollFrame", "Slider", "StatusBar" }) do
    local ok, o = pcall(CreateFrame, t)
    if ok then Methods(o) end
end
Methods(f); Methods(f:CreateTexture()); Methods(f:CreateLine()); Methods(f:CreateFontString())
for _, o in ipairs(sim.Frames()) do Methods(o) end
CreateFrame = Free(CreateFrame)"""

# The heap's own count (FREE's leaves the sim's widget state out): what a full collect keeps.
RAW = "local sim = ...; sim.gc = collectgarbage"


def kept_stretch(L, sim, ns, run):
    """run() at the client's prices (RAW, then FREE, loaded): (KB/s over it, {name: KB/s}, the KB/s of it a full
    collect keeps after: the pools grown, what Model gathered; made once a session, garbage the rest)."""
    L.execute('collectgarbage("collect"); collectgarbage("stop")')
    raw0, t0 = sim.gc("count"), sim.time
    done = stretch(L, ns)
    run()
    kb, by = done()
    simkb = sim.gc("count") - L.eval('collectgarbage("count")')
    L.execute('collectgarbage("restart"); collectgarbage("collect")')
    return kb, by, round((sim.gc("count") - raw0 - simkb) / (sim.time - t0), 1)


# A stretch's Lua allocation outside graces: FrameStats' sums and each name's KB now.
SNAP = """function(ns)
    local fs, kb = ns.Runtime.FrameStats(), {}
    for name, p in pairs(ns.Runtime.Perf()) do kb[name] = p.kb end
    return fs.kb, fs.kbSecs, kb
end"""


def stretch(L, ns):
    """Call before a stretch; what it returns, after: (KB/s, {name: KB/s}) over the stretch alone
    (FrameStats' kbPerSec and alloc average the whole run, the idle frames before it too)."""
    snap = L.eval(SNAP)
    kb0, s0, names0 = snap(ns)
    names0 = dict(names0.items())

    def done():
        kb1, s1, names1 = snap(ns)
        secs = s1 - s0
        return (round((kb1 - kb0) / secs, 1),
                {k: round((v - names0.get(k, 0)) / secs, 1) for k, v in names1.items() if v > names0.get(k, 0)})
    return done


def hub(shown=True):
    """Script (b)'s hub: 25 quests about you, kill, collect and scout, each with an area; 130 to pick up (once
    the map shows: Game reads them then)."""
    kinds = [["monster", "Kobold slain: 1/8", 1, 8, False], ["item", "Candle: 2/8", 2, 8, False],
             ["event", "Scout the mine", 0, 1, False]]
    quests = [{"id": 1000 + i, "title": f"Quest {i}", "level": 6 + i % 5, "col": 31.95 + (i % 5 - 2) * 0.35,
               "row": 49.75 + (i // 5 - 2) * 0.3, "objectives": [kinds[i % 3]], "area": 0.02 + i % 3 * 0.01}
              for i in range(25)]
    L, sim, ns, G = client(quests, followed=1012, shown=shown)
    L.execute(OFFERS, sim, ns, 5)
    sim.Run(0.5)
    assert not shown or len(known(ns, "quests")) == 25 and len(known(ns, "offers")) == 130
    return L, sim, ns, G


def test_quests_first_open():
    L, sim, ns, G = hub(shown=False)
    sim.Price(True)
    sim.Run(10)  # past login's grace
    sim.Slash("/mm toggle")  # small, at the default zoom
    sim.Run(3)  # past its grace (2 s)
    fs = ns.Runtime.FrameStats()
    print(f"the first open, 25 quests and 130 to pick up, priced: {fs.grace.map} ms, its slowest call "
          f"{fs.graceTop.map.top} {fs.graceTop.map.topMs} ms")
    assert len(known(ns, "quests")) == 25 and len(known(ns, "offers")) == 130 and fs.grace.map <= 50
    assert not errors(sim, ns), errors(sim, ns)


def test_quests_storm():
    for hidden in (False, True):
        L, sim, ns, G = hub()
        sim.Price(True)
        sim.Run(10)  # past the graces
        if hidden:
            sim.Slash("/mm toggle")
            sim.Run(1)
        sim.Slash("/mm mark b11 before")
        done = stretch(L, ns)
        L.execute("local sim = ...; for _ = 1, 600 do sim.FireEvent('QUEST_LOG_UPDATE'); sim.Step() end", sim)
        kb, by = done()
        sim.Slash("/mm mark b11 storm")
        print(f"storm, map {'hidden' if hidden else 'shown'}: {kb} KB/s; game.part quests "
              f"{by.get('game.part quests', 0)}, offers {by.get('game.part offers', 0)}; {by}")
        # Shown: the objectives read again each 0.3 s (the client's tables: ~11 KB for 25), no zone nor offer.
        assert kb <= 50 and by.get("game.part quests", 0) <= (0 if hidden else 40) and not by.get("game.part offers")
        # b11 in game: the mark after the storm reads the storm alone (from the mark before it).
        marks = L.globals().MagicMap2DB.telemetry.marks
        a = marks[len(marks)].alloc
        top = {t.name: t.kbPerSec for t in a.top.values()}
        assert a.secs == 10 and abs(a.kbPerSec - kb) <= 0.1 and abs(top.get("game.part quests", 0) - by.get("game.part quests", 0)) <= 0.1
        assert not errors(sim, ns), errors(sim, ns)


def test_quests_ticks():
    L, sim, ns, G = hub()
    sim.Price(True)
    sim.Run(10)  # past the graces
    tick = L.eval("""function(sim, poi)
        local o = sim.quests[1000].objectives[1]
        for i = 1, 1800 do -- 30 s
            if i % 120 == 0 then
                o.numFulfilled = (o.numFulfilled + 1) % 8
                o.text = "Kobold slain: " .. o.numFulfilled .. "/8"
                sim.FireEvent("QUEST_LOG_UPDATE")
                if poi then sim.FireEvent("QUEST_POI_UPDATE") end
            end
            sim.Step()
        end
    end""")
    same = L.eval("rawequal")
    tick(sim, False)  # (both canvases of each layer laid out once)
    for poi in (False, True):
        entries, before = known(ns, "quests"), ns.Model.Known("quests")[0].poi
        done = stretch(L, ns)
        tick(sim, poi)
        kb, by = done()
        print(f"a count every 2 s, {'with' if poi else 'without'} QUEST_POI_UPDATE: {kb} KB/s; {by}")
        assert kb <= 50 and not by.get("game.part offers")
        sim.Run(0.5)  # (the last tick read)
        now = known(ns, "quests")
        assert now[0].count == f"{sim.quests[1000].objectives[1].numFulfilled}/8"
        # The game's areas' version: on the list; the quests the count didn't touch keep their entries.
        assert ns.Model.Known("quests")[0].poi == ((before or 0) + 15 if poi else before)
        assert all(same(a, b) for a, b in zip(entries[1:], now[1:]))
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
