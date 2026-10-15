"""tools/telemetry.py on the fixture SavedVariables (every field docs/telemetry.md lists, an older
session without the M0 ones), with a fake client folder holding the shot's screenshot, a log line
that mentions the addon and one from the spike (another addon's error while ours was loaded,
spike-bugs E1), and reference shots: every section prints; --budgets judges the newest perf and
names an owner for each FAIL; --compare puts two sessions side by side.
Then the sim writes it: walking with the map open, a mark carries the 120-frame motion ring, a shot
its stamp, the session our memory after GC, a taint, an art miss, layout stats and the bench; the
reader reads what it wrote."""
import os
import time

import telemetry
from test_addon import boot, errors

FIXTURE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures", "MagicMapAtlas.lua")


def client(tmp_path):
    flavor = tmp_path / "_classic_beta_"
    (flavor / "Screenshots").mkdir(parents=True)
    (flavor / "Logs").mkdir()
    (tmp_path / "refs").mkdir()
    return flavor


def test_telemetry_fixture(tmp_path, capsys):
    flavor = client(tmp_path)
    (flavor / "Screenshots" / "WoWScrnShot_101426_112000.jpg").write_bytes(b"")
    for ref in ("ref-sentinel-384-small.jpg", "ref-kharanos-1024-small.png"):
        (tmp_path / "refs" / ref).write_bytes(b"")
    now = time.strftime("%-m/%-d %H:%M:%S.000")
    (flavor / "Logs" / "General.log").write_text(
        f"{now}  [E][Lua] Lua Error: Interface/AddOns/MagicMapAtlas/ui/Tiles.lua:88: boom\n"
        "[Interface/AddOns/MagicMapAtlas/ui/Tiles.lua]:88: in function <...>\n"
        f"{now}  [E][Lua] Lua Error: Interface/AddOns/MagicMap/Layers.lua:1473: bad argument #2 to 'min'\n"
        "[Interface/AddOns/MagicMap/Layers.lua]:1473: in function <...>\n"
        f"{now}  [N][Console] unrelated\n")
    base = ["--wow", str(tmp_path), "--sv", FIXTURE, "--refs", str(tmp_path / "refs")]
    assert telemetry.main(base + ["--trace", "3"]) == 0
    out = capsys.readouterr().out
    for want in ("== sessions (2)", "#2 7aa8b30-dirty", "x37 ui.tiles.step", "ui/Tiles.lua:88: in function",
                 "[error]", "zone Westfall / Sentinel Hill", "trace (last 3 of 6)",
                 "f9118 +402398ms layout {e=end layer=tiles ms=11.4 regions=36}",
                 "tiles      f9109 -> f9118 11.4 ms 36 regions | end->swap +1 f +17 ms",
                 str(flavor / "Screenshots" / "WoWScrnShot_101426_112000.jpg"),
                 "subzone: atlas '' | game 'Sentinel Hill'", "x1 General.log: [E][Lua] Lua Error",
                 "p95 0.8 p99 5.4 max 11.2, 2 over, graces gc 88.2 login 96.4 map 31.5", "slow: map: labels x3",
                 "ours 71 MB (39 at load), after GC",
                 "SHARED MagicMap: ", "General.log: [E][Lua] Lua Error: Interface/AddOns/MagicMap/Layers.lua:1473",
                 # perf: alloc, gaps, ledger, by state, memory, layouts, bench
                 "game.observe                    180.2 KB/s  max 12.4 KB/call  5400 calls",
                 "map: borders 14.2 ms (x3)", "ui/Borders.lua:88", "f9118 11.2 ms  top map: borders  [layout x2, swap x1, gap x1, spike x1]",
                 "zoom         900    0.6    2.1    9.8   11.2", "39.2 MB at load, 70.8 MB at logout",
                 "graces (slowest frame; its slowest call): gc 88.2 ms (game.telemetry 87.9 ms), login 96.4 ms"
                 " (game.loaded 60.2 ms), map 31.5 ms (map: labels 16.3 ms)",
                 "swap tiles       n 40    lag=0 live=36 ms=0.4 parked=0 scale=1.3 x=33012 y=25510",
                 "swap borders     n 38    lag=0 live=1012 ms=6.2 parked=0", "canvas.SetScale@1000live         2000 µs",
                 # kept, marks' motion and shot stamp, shot pairing
                 "taint {e=blocked fn=Minimap:Hide()}", "art redbutton-expand-c60",
                 "motion (4 frames f14999-f15002, 0.07 s)", "crossed col 32|33 f15001",
                 "shot zoom 384 camera 33.0002,48.1 inst 0 view 320x203 at 1588,1012 small; UI scale 0.711, screen 2700x1518.8",
                 f"reference {tmp_path / 'refs' / 'ref-sentinel-384-small.jpg'}",
                 "reference shots with no shot mark (1): kharanos-1024-small"):
        assert want in out, want
    assert "unrelated" not in out and "Blizzard_SharedXMLBase" not in out
    assert telemetry.main(base + ["--budgets"]) == 1
    out = capsys.readouterr().out
    for want in ("PASS  frame cost p95", "FAIL  frame cost p99                     5.40 ms (limit 5)",
                 "owner: state 'zoom' worst at p99 9.8 ms; map: borders slowest in 2 of the 3 worst frames"
                 " (worst f9118 11.2 ms: layout borders, swap borders 6.2 ms 1012 live, gap map: borders);"
                 " job map: borders ran 14.2 ms between yields; swap borders 6.2 ms max, 1012 live (stats)",
                 "FAIL  frame cost max (outside graces)    11.20 ms (limit 8)",
                 "owner: map: borders 10.4 ms in the worst frame f9118 (11.2 ms; with layout borders,"
                 " swap borders 6.2 ms 1012 live, gap map: borders); swap borders 6.2 ms max, 1012 live (stats)",
                 "PASS  first map open", "FAIL  load (Data + Atlas)", "owner: Data + Atlas at load: 37.3 MB",
                 "FAIL  our memory at logout, after GC     70.80 MB",
                 "owner: Data + Atlas: 39.2 MB at load after GC; +31.6 MB by logout (top allocator game.observe)",
                 "FAIL  Lua allocation (outside graces)    274.30 KB/s",
                 "owner: game.observe 180.2 KB/s (66%), map: borders 60.1 KB/s (22%)",
                 "FAIL  errors per hour", "owner: ui.tiles.step x37",
                 "FAIL  perf.slow  1", "owner: map: labels x3", "FAIL  perf.gaps  1", "owner: map: borders 14.2 ms between yields (x3)",
                 "FAIL  taint      1", "owner: {e=blocked fn=Minimap:Hide()}", "FAIL  art        1", "PASS  sensor     0"):
        assert want in out, (want, out)
    assert "== perf" not in out and "owner: bench" not in out and "job bench" not in out  # its overruns and gaps are the bench
    # the first open's owner: its grace's slowest call; older sessions: perf.slow without the bench
    assert telemetry.owner_open({"graceTop": {"map": {"top": "map: labels", "topMs": 16.3}},
                                 "slow": [{"name": "bench: regions", "max": 68}]}, {}, []).startswith("map: labels (16.3 ms")
    assert telemetry.owner_open({"slow": [{"name": "bench: regions", "max": 68}, {"name": "map: labels", "max": 56.2}]},
                                {}, []).startswith("map: labels (slowest call, 56.2 ms")
    assert telemetry.main(base + ["--budgets", "--trace"]) == 1
    out = capsys.readouterr().out
    for want in ("== perf", "        f9118 +402398ms swap {layer=borders live=1012 ms=6.2 parked=0 scale=1 x=-12 y=40}", "== kept", "== marks (2)",
                 "f15001 +1101200ms dt 33.3 cam 33.0002,48.1 z384 320x203 you 33.0002,48.1  step +0.23,+0.00 px  you-cam +0.00,+0.00 px |col",
                 "trace (all 6)"):
        assert want in out, (want, out)
    assert telemetry.main(base + ["--compare", "1", "2"]) == 0
    out = capsys.readouterr().out
    for want in ("A #1 7aa8b30 build", "B #2 7aa8b30-dirty", "frame cost max (outside graces) (ms)          27.20      11.20     -16.00",
                 "frame cost p99 (ms)                            4.50       5.40      +0.90",
                 "frames                                         5100      17890     +12790",
                 "ours at load, after GC (MB)                       -      39.16", "alloc game.observe (KB/s)                         -     180.20",
                 "bench canvas.SetScale@1000live (µs)               -       2000"):
        assert want in out, (want, out)


SAVE = """function(v)
    local out = {}
    local function put(x)
        local t = type(x)
        if t == "table" then
            out[#out + 1] = "{"
            for k, y in pairs(x) do
                if type(y) ~= "function" then
                    out[#out + 1] = "[" .. (type(k) == "string" and string.format("%q", k) or tostring(k)) .. "]="
                    put(y)
                    out[#out + 1] = ","
                end
            end
            out[#out + 1] = "}"
        elseif t == "string" then out[#out + 1] = string.format("%q", x)
        elseif t == "number" or t == "boolean" then out[#out + 1] = tostring(x)
        else out[#out + 1] = "nil" end
    end
    put(v)
    return "MagicMapAtlasDB = " .. table.concat(out)
end"""


def test_telemetry_sim(tmp_path, capsys):
    L, sim, ns = boot()
    sim.Slash("/mma map")
    sim.player.speed = 7  # yd/s, north: the map follows
    sim.Run(11)  # past the first open's grace and ourKBLoad (10 s after login)
    sim.FireEvent("ADDON_ACTION_BLOCKED", "MagicMapAtlas", "Minimap:Hide()")
    sim.FireEvent("ADDON_ACTION_FORBIDDEN", "MagicMapAtlas", "Minimap:Hide()")
    sim.FireEvent("ADDON_ACTION_BLOCKED", "SomeAddon", "CastSpellByName()")
    ns.Runtime.Trace("art", "redbutton-expand-c60")  # as /mma check art reports a miss (game/Bench.lua)
    ns.Game.Bench = L.eval("{ result = { build = '1.60.1.70009', t = 1, ops = { CreateLine = { n = 1000, ms = 21, us = 21 } } } }")
    sim.Slash("/mma mark mid-walk")
    sim.Slash("/mma shot kharanos-1024-small tear")
    sim.Step()
    sim.FireEvent("PLAYER_LOGOUT")
    tel = L.globals().MagicMapAtlasDB.telemetry
    s = tel.sessions[1]
    marks = {m.kind: m for m in tel.marks.values()}
    walk, shot = marks["mark"], marks["shot"]
    ring = list(walk.motion.values())
    assert len(ring) == 120 and [r.f for r in ring] == list(range(walk.frame - 119, walk.frame + 1))
    assert ring[-1].py < ring[0].py and all(r.cx == r.px and r.cy == r.py for r in ring)  # walking north, followed
    assert ring[-1].zoom == ns.UI.Camera.cam.zoom and ring[-1].w > 0 and ring[-1].h > 0
    a = shot.shot
    assert shot.note == "kharanos-1024-small tear" and a.zoom == ns.UI.Camera.cam.zoom and a.uiScale == 1
    assert a.w > 0 and a.left is not None and a.screenW == 1920 and a.big is False and len(shot.motion) == 120
    p = s.perf
    assert p.ourKBLoad == 2400 and p.ourKB == 2400 and p.grace.gc is not None  # the sim's GetAddOnMemoryUsage
    assert p.graceTop.map.top.startswith("map: ")  # opened during login's grace: the first open's frames are map's
    assert [(e.k, e.d if isinstance(e.d, str) else e.d.fn) for e in s.kept.values()] == [
        ("taint", "Minimap:Hide()"), ("taint", "Minimap:Hide()"), ("art", "redbutton-expand-c60")]
    assert [m.note for m in tel.marks.values() if m.kind == "taint"] == ["blocked Minimap:Hide()"]  # the first only
    assert s.stats["layout tiles"].n >= 1 and s.stats["layout tiles"].regions > 0 and s.stats["swap tiles"].lag == 0
    swap = s.stats["swap borders"]  # each swap's own cost and what it shows (M1.3: parked)
    assert swap.ms is not None and swap.live > 0 and swap.parked == 0
    assert s.bench["1.60.1.70009"].ops.CreateLine.us == 21
    assert not errors(sim, ns), errors(sim, ns)

    sv = tmp_path / "MagicMapAtlas.lua"
    sv.write_text(L.eval(SAVE)(L.globals().MagicMapAtlasDB), encoding="latin-1")
    client(tmp_path)
    base = ["--wow", str(tmp_path), "--sv", str(sv), "--refs", str(tmp_path / "refs")]
    assert telemetry.main(base + ["--trace"]) == 0
    out = capsys.readouterr().out
    for want in ("[mark]", "mid-walk", "motion (120 frames", "[shot]", "shot zoom 96", "screen 1920x1080",
                 "taint {e=blocked fn=Minimap:Hide()}", "art redbutton-expand-c60", "memory (ours, after a full collect): 2.3 MB at load",
                 "layout tiles", "bench 1.60.1.70009", "CreateLine", "reference NONE for kharanos-1024-small"):
        assert want in out, want
    telemetry.main(base + ["--budgets"])
    out = capsys.readouterr().out
    assert "our memory at logout, after GC" in out and "FAIL  taint      2" in out and "FAIL  art        1" in out
