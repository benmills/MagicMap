"""The sim's fidelity (tools/tests/wowsim.lua, docs/v1-plan.md M0.6) in one scenario: what
it charges, defers, sizes, zeroes, hosts, refuses, raises and walks like the client. And each
fixture observation stream (fixtures/streams/<part>.lua) replayed through Model alone:
shaped as types/observation.lua says, taken without an error whatever Model doesn't
merge yet.

  .venv/bin/python -m pytest tools/tests/test_sim.py -s   # prints the priced sensor's cost
"""
import os

import pytest
from lupa import lua51

import fixtures
from test_addon import TESTS, boot, errors
from test_blips import ROOT, lua_tools


def test_fidelity():
    L = lua51.LuaRuntime(encoding="latin-1", unpack_returned_tuples=True)
    sim = L.eval("function(path) return assert(loadfile(path))() end")(os.path.join(TESTS, "wowsim.lua"))
    G = L.globals()
    sim.Clock = L.eval("function() return 0 end")  # only what's priced moves the clock

    # Priced (off by default, docs/evidence/perf-m0.md): 100 probes 0.2 ms; a frame's Show per region it
    # makes visible (a line dearer), and its own Show, Hide, SetScale, SetAlpha a little per region under it.
    probes = L.eval("""function(n)
        local t0 = debugprofilestop()
        for _ = 1, n do Minimap:UpdateMouseoverAtPoint(0, 0); C_TooltipInfo.GetMinimapMouseover() end
        return debugprofilestop() - t0
    end""")
    assert probes(100) == 0
    sim.Price(True)
    assert abs(probes(100) - 0.2) < 1e-9
    regions = L.eval("""function()
        local f = CreateFrame("Frame", nil, UIParent)
        for _ = 1, 50 do f:CreateTexture() end
        local child = CreateFrame("Frame", nil, f)
        for _ = 1, 50 do child:CreateLine():Hide() end -- hidden ones pay a little
        for _ = 1, 10 do child:CreateLine() end
        f:Hide()
        local function ms(fn) local t0 = debugprofilestop(); fn(); return debugprofilestop() - t0 end
        return ms(function() f:Show() end), ms(function() f:Show() end), ms(function() f:SetScale(0.5) end),
            ms(function() f:SetScale(0.5) end), ms(function() f:SetAlpha(0) end), ms(function() f:Hide() end)
    end""")()
    # 50 textures and 10 lines shown: 50 x 0.02 + 10 x 0.035, and 110 under at 0.004 us.
    assert [round(ms, 6) for ms in regions] == [1.35044, 0, 0.0011, 0, 0.00044, 0.0022], regions
    sim.Price(False)

    # GetMinimapMouseover allocates: a fresh TooltipData each answer; nothing there: nil, after as much
    # garbage (~0.35 KB a probe in game, answer or not).
    hit = L.eval("""function()
        local north, west = UnitPosition("player")
        Sim.minimapBlips = { { "Mailbox", north, west } }
        Minimap:SetUsingSoftCursor(true)
        local l, b, w, h = Minimap:GetRect()
        Minimap:UpdateMouseoverAtPoint(l + w / 2, b + h / 2)
        local a, b2 = C_TooltipInfo.GetMinimapMouseover(), C_TooltipInfo.GetMinimapMouseover()
        Minimap:UpdateMouseoverAtPoint(l + 2, b + 2)
        collectgarbage("stop")
        local kb = collectgarbage("count")
        local miss = C_TooltipInfo.GetMinimapMouseover()
        kb = collectgarbage("count") - kb
        collectgarbage("restart")
        Minimap:SetUsingSoftCursor(false)
        return a ~= b2 and a.lines ~= b2.lines and a.lines[1].leftText == "Mailbox" and a.lines[1].leftColor ~= nil, miss,
            kb > 0.3
    end""")()
    assert hit == (True, None, True)

    # The view radius is 0 while a new zoom applies (E3/E6): the frame it's set in and the next.
    radius = L.eval("function() return C_Minimap.GetViewRadius() end")
    assert radius() == 466.67 / 2
    G.Minimap.SetZoom(G.Minimap, 3)
    zooming = [radius()]
    sim.Step()
    zooming.append(radius())
    sim.Step()
    zooming.append(radius())
    G.Minimap.SetZoom(G.Minimap, 3)  # the same zoom: no change
    assert zooming + [radius()] == [0, 0, 266.67 / 2, 266.67 / 2], zooming
    G.Minimap.SetZoom(G.Minimap, 0)
    sim.Run(0.1)

    # L1: a QuestPOI blob hit only after the next layout frame, and only once drawn again then.
    hits = L.eval("""function()
        local poi, got = CreateFrame("QuestPOIFrame", nil, UIParent), {}
        poi:SetPoint("TOPLEFT", 100, -100)
        poi:SetSize(400, 300)
        Sim.blobShapes[60] = { 0.5, 0.5, 0.1 }
        poi:DrawBlob(60, true)
        got[1] = poi:UpdateMouseOverTooltip(0.5, 0.5) or false -- not laid out
        Sim.Step()
        got[2] = poi:UpdateMouseOverTooltip(0.5, 0.5) or false -- laid out, but drawn into nothing
        poi:DrawBlob(60, true)
        got[3] = poi:UpdateMouseOverTooltip(0.5, 0.5) or false
        poi:SetSize(800, 600)
        poi:DrawBlob(60, true) -- into the old rect
        Sim.Step()
        got[4] = poi:UpdateMouseOverTooltip(0.5, 0.5) or false -- (its blob is off in the corner)
        poi:DrawBlob(60, true)
        got[5] = poi:UpdateMouseOverTooltip(0.5, 0.5) or false
        return got
    end""")()
    assert list(hits.values()) == [False, False, 60, False, 60], list(hits.values())

    # L2: Forever's edge atlases at their reported 200 px, by GetAtlasInfo and SetAtlas(name, true).
    edge = L.eval("""function()
        local t = UIParent:CreateTexture()
        t:SetAtlas("!UI-Frame-Metal-EdgeLeft", true)
        local plain = UIParent:CreateTexture()
        plain:SetSize(4, 4)
        plain:SetAtlas("!UI-Frame-Metal-EdgeRight")
        return t:GetWidth(), C_Texture.GetAtlasInfo("_UI-Frame-Metal-EdgeBottom").height, plain:GetWidth()
    end""")()
    assert edge == (200, 200, 4)
    assert sim.atlases["!UI-Frame-Metal-EdgeLeft"][1] == 200  # a scenario can mock or remove one

    # HereBeDragons-Pins-2.0: the shared copy (GatherMate's pin) and Questie's renamed one.
    questie = sim.LoadQuestie()
    pins = L.eval("""function(q)
        local libs = {}
        for name in LibStub:IterateLibraries() do libs[#libs + 1] = name end
        table.sort(libs)
        local gather = select(2, Sim.gatherPin:GetPoint()) == Minimap and Sim.gatherPin:IsShown()
        local _, _, _, gx = Sim.gatherPin:GetPoint()
        Sim.player.col = Sim.player.col + 0.02
        Sim.Step()
        local _, _, _, gx2 = Sim.gatherPin:GetPoint()
        Sim.player.col = Sim.player.col - 0.02
        local icon = Sim.QuestieIcon({ Type = "complete", Id = 60 })
        q:AddWorldMapIconMap(Questie, icon, 1429, 0.35, 0.55, HBD_PINS_WORLDMAP_SHOW_CURRENT)
        local world = icon:GetParent():GetParent() == WorldMapFrame.canvas and icon:IsShown()
        q:RemoveWorldMapIcon(Questie, icon)
        local back = icon:GetParent() == UIParent and not icon:IsShown()
        local mini = Sim.QuestieIcon({ Type = "available", Id = 70 })
        q:AddMinimapIconMap(Questie, mini, 1429, 0.29, 0.56)
        local onMinimap = mini:GetParent() == Minimap and mini:IsShown()
        local host = CreateFrame("Frame", nil, UIParent)
        host:SetSize(300, 300)
        host:SetPoint("CENTER")
        host.GetZoom = function() return 0 end
        q:SetMinimapObject(host)
        return table.concat(libs, " "), gather, gx2 < gx, world, back, onMinimap,
            mini:GetParent() == host and select(2, mini:GetPoint()) == host
    end""")(questie)
    assert pins == ("HereBeDragons-Pins-2.0 HereBeDragonsQuestie-2.0 HereBeDragonsQuestie-Pins-2.0",
                    True, True, True, True, True, True), pins

    # K2: in combat, insecure calls changing a protected frame are refused and logged; a key press isn't.
    blocked = L.eval("""function()
        local got = {}
        local f = CreateFrame("Frame")
        f:RegisterEvent("ADDON_ACTION_BLOCKED")
        f:SetScript("OnEvent", function(_, _, addon, call) got.event = addon .. " " .. call end)
        got.protected = { MinimapCluster:IsProtected() }
        got.implicit = { UIParent:IsProtected() }
        got.minimap = Minimap:IsProtected()
        Sim.inCombat = true
        MinimapCluster:Hide()
        got.cluster = MinimapCluster:IsShown()
        hooksecurefunc("ToggleWorldMap", function() WorldMapFrame:Hide() end) -- an addon's hook
        Sim.Press("M") -- the client's own Show goes through; the hook's Hide doesn't
        got.shown = WorldMapFrame:IsShown()
        Sim.inCombat = false
        MinimapCluster:Hide()
        got.after = MinimapCluster:IsShown()
        got.calls = {}
        for i, c in ipairs(Sim.protectedCalls) do got.calls[i] = c.call end
        return got
    end""")()
    assert list(blocked.protected.values()) == [True, True] and list(blocked.implicit.values()) == [True, False]
    assert blocked.minimap is False and blocked.cluster and blocked.shown and not blocked.after
    assert list(blocked.calls.values()) == ["MinimapCluster:Hide()", "WorldMapFrame:Hide()"], list(blocked.calls.values())
    assert blocked.event == "MagicMap WorldMapFrame:Hide()"

    # GetPlayerFacing's way (radians counter-clockwise from north): you walk east facing 3pi/2, west at pi/2.
    walked = L.eval("""function()
        local p, got = Sim.player, {}
        for i, f in ipairs({ 3 * math.pi / 2, math.pi / 2, 0 }) do
            local col, row = p.col, p.row
            p.facing, p.speed = f, 7
            Sim.Step()
            p.speed = 0
            got[i] = { p.col - col > 1e-6, p.col - col < -1e-6, row - p.row > 1e-6 }
        end
        return got
    end""")()
    assert [list(w.values()) for w in walked.values()] == [[True, False, False], [False, True, False], [False, False, True]]

    # Strict (opt-in): x/0 raises as in WoW's Lua; strings, comments and other maths untouched.
    sim.Strict(True)
    strict = L.eval("""function()
        local f = assert(loadstring("local a, b = ...\\nreturn a / b, '1/2', [[3/4]], a/b^2, -a / -b -- 5/6"))
        local ok, err = pcall(f, 1, 0)
        return err, f(1, 2)
    end""")()
    sim.Strict(False)
    assert "Division by zero" in strict[0] and strict[1:] == (0.5, "1/2", "3/4", 0.25, 0.5), strict
    assert L.eval("assert(loadstring('return 1/0'))()") == float("inf")

    # The addon on the priced clock (reported, not judged: M1.5 brings the sensor to budget).
    L, sim, ns = boot()
    sim.Price(True)
    sim.Run(1)
    sim.Slash("/mm toggle")
    sim.Run(3)
    observe = ns.Runtime.Perf()[0]["game.observe"]
    print(f"priced: game.observe max {observe.max:.1f} ms, {observe.ms / observe.n:.2f} ms a frame over {observe.n} frames")
    assert not errors(sim, ns), errors(sim, ns)


# types/observation.lua: each part's required fields, per element.
REQUIRED = {
    "quests": ("id", "title", "complete", "followed", "objectives"),
    "offers": ("questID", "name", "pos"),
    "group": ("id", "name"),
    "places": ("key", "kind", "pos", "name"),
    "vignettes": ("id", "name", "pos", "rare"),
    "tracking": ("id", "name", "texture", "active"),
}
POS = {"offers": "pos", "places": "pos", "vignettes": "pos", "group": "pos", "quests": "pin"}  # the last two may be nil
OBJECTIVES = {"monster", "item", "object", "event", "log", "progressbar", "reputation", "other"}


def is_pos(p):
    return p is not None and isinstance(p.inst, int) and all(isinstance(v, (int, float)) for v in (p.col, p.row))


@pytest.mark.parametrize("name", fixtures.streams())
def test_stream(name):
    L = lua51.LuaRuntime(unpack_returned_tuples=True)
    tools = lua_tools(L)
    stream = tools.Stream(ROOT, name)
    model = tools.Model(ROOT)
    model.Load(L.eval("{ _v = 1, rares = {}, blips = {} }"))
    oracles = tools.Oracles(stream)
    carried = 0
    for i in range(1, len(stream) + 1):
        obs = stream[i]
        assert obs.frame and obs.t is not None and obs.you is not None and obs.hooked is not None, (name, i)
        part = obs[name]
        carried += part is not None
        for e in (part.values() if part is not None and name in REQUIRED else []):
            assert all(e[k] is not None for k in REQUIRED[name]), (name, i, dict(e))
            if name in POS:
                p = e[POS[name]]
                assert is_pos(p) or p is None and name in ("group", "quests"), (name, i)
            assert all(o.type in OBJECTIVES and o.text is not None and o.finished is not None
                       for o in (e.objectives.values() if name == "quests" else [])), (name, i)
        if name in ("corpse", "waypoint"):
            assert part is False or is_pos(part), (name, i)
        if name == "explored":
            assert all(isinstance(k, int) and isinstance(v, bool) for k, v in part.items()), (name, i)
        model.Observe(obs, oracles)
    assert carried >= 3, name
    last = stream[len(stream)].you
    assert (model.you.col, model.you.row, model.you.stale) == (last.col, last.row, False)
    if name == "quests":
        area = stream.areas[60]
        assert (oracles.Inside(60, area.col, area.row), oracles.Inside(60, area.col + 1, area.row),
                oracles.Inside(176, area.col, area.row)) == (True, False, None)
