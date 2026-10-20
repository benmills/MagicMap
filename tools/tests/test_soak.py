"""The M5 exit's 10-minute soak (docs/v1-plan.md M5.1) on the priced clock: a first login's map (small on the
Minimap's spot, 384 px a tile), every layer on (those off by default too), scripts (a)-(e)'s shapes (docs/playtest.md) in rounds of
~160 s, each ending where it began:

  (a) zoom bursts (every notch a tick, the glide stacking) and slow ticks, flings, follow back on, grow and
      shrink, a walk east and back at 800;
  (b) 25 quests about you (one followed, their areas, 130 to pick up), a count ticking every 2 s, a looting
      burst of QUEST_LOG_UPDATE, pins hovered, one clicked to follow and again to stop, the wheel 60 -> 384;
  (c) a waypoint a tile east: its route, ridden toward and back, cleared;
  (d) a hearth to Stormwind: its trade district with the party of four about you, every layer toggled off and
      on, a building (indoors), a member dead and back; a hearth home;
  (e) Questie's world and minimap pins and GatherMate's (HereBeDragons) all along; the big map out to the
      continent, drags there, back in to 140 and 384, shrunk.

  test_soak: the Lua heap after a full collect where each script ends, the last round's against the one
    before (flat: what a round leaves behind, ≤ GROWTH_KB); no job left queued at rest; the session, logged
    out, through tools/telemetry.py --budgets as a play-test's: 8/8 (docs/runtime.md: at rest p95 ≤ 1 ms, p99
    ≤ 5, moving p95 ≤ 5, none over 8, Lua allocation ≤ 50 KB/s, 0 errors...) and perf.slow, perf.gaps, taint,
    art and sensor empty; each round past the first ≤ 50 KB/s too.
"""
import telemetry
from test_addon import boot, errors
from test_blips import put_blips, stub_services
from test_quest_areas import FREE, OFFERS, stretch
from test_quests import SETUP

ROUNDS = 4  # ~160 s each: the 1st grows the pools (regions kept for good, as the client's), the 2nd and 3rd
            # each canvas's (a layer's two, swapped) at each script's zooms; the 4th as the 3rd
GROWTH_KB = 64  # a round's leftovers, after a full collect (the heap is ~60 MB)

# Questie's pins in Elwynn (world: x, y, flag; minimap: x, y) about Goldshire (0.42, 0.56 on 1429).
QUESTIE = """local sim, G = ...
local q = sim.LoadQuestie()
sim.FireEvent("ADDON_LOADED", "Questie")
for i = 1, 30 do
    local icon = sim.QuestieIcon({ Type = i % 4 == 0 and "complete" or "available", Id = 2000 + i })
    q:AddWorldMapIconMap(G.Questie, icon, 1429, 0.2 + (i % 6) * 0.08, 0.35 + math.floor(i / 6) * 0.08, i % 3 == 0 and 3 or 0)
end
for i = 1, 10 do
    local icon = sim.QuestieIcon({ Type = "available", Id = 2100 + i })
    q:AddMinimapIconMap(G.Questie, icon, 1429, 0.38 + (i % 5) * 0.02, 0.53 + math.floor(i / 5) * 0.03)
end"""

# Each script of a round, ending where it began (Goldshire, the map small, following, at its zoom then). Round():
# the heap after a full collect at each script's end, and the round's seconds; Jobs(): those made or woken not done.
DRIVE = """local sim, ns, G = ...
local view, M, Engine = ns.UI.Window.view, ns.UI.Motion, ns.UI.Engine
local me, units = sim.player, sim.units
local HOME = { col = me.col, row = me.row } -- (and zoom: the first round's start)
-- The party of four about you; quest 1000's count ticking every 2 s.
local frame, tick = 0, sim.onStep
sim.onStep = function(elapsed)
    tick(elapsed)
    for i = 1, 4 do
        local u = units["party" .. i]
        u.col, u.row = me.col + 0.004 * i * (i % 2 == 0 and 1 or -1), me.row + 0.003 * i
    end
    frame = frame + 1
    if frame % 120 == 0 then
        local o = sim.quests[1000].objectives[1]
        o.numFulfilled = (o.numFulfilled + 1) % 8
        o.text = "Kobold slain: " .. o.numFulfilled .. "/8"
        sim.FireEvent("QUEST_LOG_UPDATE")
    end
end
-- Every job made or woken, by handle (weak: done ones go).
local made, Job, Wake = setmetatable({}, { __mode = "k" }), ns.Runtime.Job, ns.Runtime.Wake
ns.Runtime.Job = function(...) local j = Job(...); made[j] = true; return j end
ns.Runtime.Wake = function(j, ...) made[j] = true; return Wake(j, ...) end
function Jobs()
    local out = {}
    for j in pairs(made) do
        if not j.done then out[#out + 1] = j.name end
    end
    return out
end

local function Wheel(d, n, gap) for _ = 1, n do sim.Wheel(view, d); sim.Run(gap) end end
local function Walk(seconds, facing, speed)
    me.facing, me.speed = facing, speed
    sim.Run(seconds)
    me.speed = 0
end
local EAST, WEST, NORTH, SOUTH = 3 * math.pi / 2, math.pi / 2, 0, math.pi
local function Home()
    M.SetZoom(HOME.zoom)
    M.SetFollow(true)
    sim.Run(2)
end
local function Hearth(col, row)
    me.col, me.row = col, row
    sim.FireEvent("PLAYER_ENTERING_WORLD", false, false)
    sim.Run(6) -- (its grace: 5 s)
end
local function Click(col, row)
    G.Over(col, row)
    sim.Step()
    sim.Click(view, "LeftButton", sim.cursorX, sim.cursorY, "screen")
    sim.Run(0.5)
end
-- Every gear layer on (those off by default too: graveyards), each toggled off and on in (d).
local layers = {}
for name in pairs(Engine.defaults) do
    Engine.SetLayer(name, true)
    layers[#layers + 1] = name
end
table.sort(layers)

local scripts = {}
scripts[1] = function() -- (a), from 384
    Wheel(1, 8, 0.03); sim.Run(1); Wheel(-1, 8, 0.03); sim.Run(1) -- a burst in (to 800), out
    Wheel(-1, 6, 0.3); sim.Run(1); Wheel(1, 6, 0.3); sim.Run(1) -- a tick at a time, to 80 and back
    for i = 1, 4 do -- flings
        sim.Drag(view, i % 2 == 0 and 120 or -120, i <= 2 and 60 or -60, 6)
        sim.Run(1.5)
    end
    M.SetFollow(true); sim.Run(1)
    for _ = 1, 2 do sim.Press("M"); sim.Run(1.5); sim.Press("M"); sim.Run(1.5) end -- grow, shrink
    Wheel(1, 6, 0.3); sim.Run(1) -- 800: the tear walk's
    Walk(8, EAST, 7); Walk(8, WEST, 7)
    Home()
end
scripts[2] = function() -- (b)
    sim.FireScript(view, "OnEnter", false)
    for i = 0, 4 do G.Over(31.95 + (i - 2) * 0.35, 49.15 + i * 0.3); sim.Run(1) end -- hovering pins
    Click(31.95, 49.75); Click(31.95, 49.75) -- follow quest 1012, then stop
    sim.FireScript(view, "OnLeave", false)
    sim.superTracked = 1012; sim.FireEvent("SUPER_TRACKING_CHANGED"); sim.Run(1)
    for _ = 1, 180 do sim.FireEvent("QUEST_LOG_UPDATE"); sim.Step() end -- a looting burst
    sim.Run(2)
    Wheel(-1, 7, 0.3); sim.Run(1); Wheel(1, 3, 0.3); sim.Run(1); Wheel(1, 4, 0.3); sim.Run(1) -- 60 -> 140 -> 384
    Home()
end
scripts[3] = function() -- (c)
    ns.Game.Command({ kind = "waypoint", pos = { inst = 0, col = HOME.col + 1, row = HOME.row } })
    sim.Run(3)
    Walk(10, EAST, 14); sim.Run(2); Walk(10, WEST, 14)
    ns.Game.Command({ kind = "waypoint", pos = false })
    sim.Run(2)
    Home()
end
scripts[4] = function() -- (d)
    Hearth(31.4, 47.6) -- Stormwind's trade district
    Walk(5, NORTH, 7); Walk(5, EAST, 7)
    for _, name in ipairs(layers) do Engine.SetLayer(name, false); sim.Run(0.1); Engine.SetLayer(name, true); sim.Run(0.1) end
    sim.indoors = true; sim.Run(3); sim.indoors = false; sim.Run(1)
    units.party2.dead = true; sim.Run(3); units.party2.dead = nil
    Walk(5, WEST, 7); Walk(5, SOUTH, 7)
    Hearth(HOME.col, HOME.row)
    Home()
end
scripts[5] = function() -- (e)
    sim.Press("M"); sim.Run(1.5)
    Wheel(-1, 12, 0.3); sim.Run(2) -- the continent (16)
    for i = 1, 4 do sim.Drag(view, i % 2 == 0 and 200 or -200, i <= 2 and 80 or -80, 30); sim.Run(1) end
    M.SetFollow(true); sim.Run(1)
    Wheel(1, 8, 0.3); sim.Run(2) -- 140
    Wheel(1, 4, 0.3); sim.Run(2) -- 384
    sim.Press("M"); sim.Run(1.5)
    Home()
end
function Round()
    local heap, t0 = {}, sim.time
    HOME.zoom = HOME.zoom or ns.UI.Camera.cam.zoom
    for i = 1, #scripts do
        scripts[i]()
        collectgarbage("collect")
        heap[i] = collectgarbage("count")
    end
    return heap, sim.time - t0
end"""


def soak():
    """The soak, priced from past login's grace, then logged out: (L, sim, ns, rounds: each (heaps, seconds, KB/s,
    {name: KB/s}), the jobs left)."""
    L, sim, ns = boot("MagicMap2DB = nil")  # a first login's: shown, small on the Minimap's spot
    G = L.globals()
    L.execute(FREE, sim)
    L.execute(SETUP, sim, ns)
    stub_services(L, ns)
    put_blips(L, sim, ns, [("Mailbox", 40, 20), ("Mailbox", -50, -70), ("Peacebloom", -60, 30), ("Innkeeper Belm", 10, -5)])
    kinds = [["monster", "Kobold slain: 1/8", 1, 8, False], ["item", "Candle: 2/8", 2, 8, False],
             ["event", "Scout the mine", 0, 1, False]]
    quests = [{"id": 1000 + i, "title": f"Quest {i}", "level": 6 + i % 5, "col": 31.95 + (i % 5 - 2) * 0.35,
               "row": 49.75 + (i // 5 - 2) * 0.3, "objectives": [kinds[i % 3]],
               **({} if i < 15 and i % 3 != 2 else {"area": 0.02 + i % 3 * 0.01})} for i in range(25)]
    sim.superTracked = 1012
    G.Quests(L.table_from([L.table_from({k: L.table_from([L.table_from(o) for o in v]) if k == "objectives" else v
                                         for k, v in q.items()}) for q in quests]))
    L.execute(OFFERS, sim, ns, 5)
    for i in range(1, 5):
        sim.units[f"party{i}"] = L.table_from({"name": f"Member{i}", "class": "MAGE", "level": 8,
                                               "guid": f"Player-1-0000000{i + 1}", "col": 31.95, "row": 49.75})
    sim.group = L.table_from([f"party{i}" for i in range(1, 5)])
    sim.vignetteAtlas = "VignetteKillElite"
    L.execute(QUESTIE, sim, G)
    L.execute(DRIVE, sim, ns, G)
    sim.Run(6)  # past login's grace and the first open's
    sim.Price(True)
    rounds = []
    for _ in range(ROUNDS):
        done = stretch(L, ns)
        heap, secs = G.Round()
        rounds.append((list(heap.values()), secs, *done()))
    sim.Run(3)
    sim.Price(False)
    sim.FireEvent("PLAYER_LOGOUT")
    return L, sim, ns, rounds, list(G.Jobs().values())


def test_soak():
    L, sim, ns, rounds, jobs = soak()
    by = ns.Runtime.FrameStats().byState
    print(f"soak: {sum(r[1] for r in rounds):.0f} s priced; by round, the heap after a full collect where each script ends, "
          "Lua allocation and its top makers: " + "; ".join(
              " ".join(f"{kb / 1024:.2f}" for kb in r[0]) + f" MB, {r[2]} KB/s {sorted(r[3].items(), key=lambda kv: -kv[1])[:4]}"
              for r in rounds)
          + "; " + ", ".join(f"{k} {v.frames} frames p95 {v.p95} p99 {v.p99} max {v.max}" for k, v in sorted(by.items())))
    db = telemetry.py(L.globals().MagicMap2DB)
    gate = telemetry.budgets(telemetry.sessions_of(db), list((db["telemetry"].get("errors") or {}).values()))
    grew = [round(b - a) for a, b in zip(rounds[-2][0], rounds[-1][0])]
    assert sum(r[1] for r in rounds) >= 600 and {"small", "big", "zoom", "drag"} <= set(by.keys())
    assert max(grew) <= GROWTH_KB, grew
    assert not jobs, jobs
    assert gate == 0 and all(r[2] <= 50 for r in rounds[1:]), [r[2] for r in rounds]
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
