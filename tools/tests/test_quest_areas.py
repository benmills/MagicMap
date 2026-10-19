"""Quest areas on the simulated client (docs/v1-plan.md M2.4: ui/Areas.lua), end to end from the sim's
quest log (its blobs: Sim.blobShapes) through Game's parts and Inside, and Model:

  test_quest_areas: one QuestPOIFrame a map and style in the client's art (S53): the quest you follow
    filled blue over the rest, kill rust, gather green, other blue; each quest drawn into its frame's rect
    as laid out (L1); an estimate only for a kill or collect quest the game draws no area for, one for two
    within 0.6 r (S54); out of sight while the zoom moves, back where it lands (P5); the gear's toggles.
  test_quest_area_hover: an area under the cursor lit on top (HOVER) with its quest's tooltip, built once a
    hover (spike-bugs G7); a pin's tooltip wins, its quest lit; off both, neither.
  test_quests_priced: 25 quests with areas, the big map, the wheel and drags on the priced clock: the
    budgets by map state (docs/runtime.md).
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


def test_quests_priced():
    """Script (b)'s quest hub, 25 quests about you each with its area (one followed), the big map: the wheel
    in and out and drags on the priced clock. At rest p95 <= 1 ms, moving p95 <= 5 ms, none over 8."""
    kinds = [["monster", "Kobold slain: 1/8", 1, 8, False], ["item", "Candle: 2/8", 2, 8, False],
             ["event", "Scout the mine", 0, 1, False]]
    quests = [{"id": 1000 + i, "title": f"Quest {i}", "level": 6 + i % 5, "col": 31.95 + (i % 5 - 2) * 0.35,
               "row": 49.75 + (i // 5 - 2) * 0.3, "objectives": [kinds[i % 3]], "area": 0.02 + i % 3 * 0.01}
              for i in range(25)]
    L, sim, ns, G = client(quests, followed=1012)
    assert len(ns.Model.Known("quests")[0]) == 25
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
    assert not errors(sim, ns), errors(sim, ns)
