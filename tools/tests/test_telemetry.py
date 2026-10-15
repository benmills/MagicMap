"""tools/telemetry.py on the fixture SavedVariables, with a fake client folder holding the shot's
screenshot, a log line that mentions the addon and one from the spike (another addon's error while
ours was loaded, spike-bugs E1): every section prints; --budgets judges the newest perf."""
import os
import time

import telemetry

FIXTURE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures", "MagicMapAtlas.lua")


def test_telemetry_fixture(tmp_path, capsys):
    flavor = tmp_path / "_classic_beta_"
    (flavor / "Screenshots").mkdir(parents=True)
    (flavor / "Logs").mkdir()
    (flavor / "Screenshots" / "WoWScrnShot_101426_112000.jpg").write_bytes(b"")
    now = time.strftime("%-m/%-d %H:%M:%S.000")
    (flavor / "Logs" / "General.log").write_text(
        f"{now}  [E][Lua] Lua Error: Interface/AddOns/MagicMapAtlas/ui/Tiles.lua:88: boom\n"
        "[Interface/AddOns/MagicMapAtlas/ui/Tiles.lua]:88: in function <...>\n"
        f"{now}  [E][Lua] Lua Error: Interface/AddOns/MagicMap/Layers.lua:1473: bad argument #2 to 'min'\n"
        "[Interface/AddOns/MagicMap/Layers.lua]:1473: in function <...>\n"
        f"{now}  [N][Console] unrelated\n")
    assert telemetry.main(["--wow", str(tmp_path), "--sv", FIXTURE, "--trace", "3"]) == 0
    out = capsys.readouterr().out
    for want in ("== sessions (2)", "#2 7aa8b30-dirty", "x37 ui.tiles.step", "ui/Tiles.lua:88: in function",
                 "[error]", "zone Westfall / Sentinel Hill", "trace (last 3 of 6)",
                 "f9118 +402398ms layout tiles end {ms=11.4 regions=36}",
                 str(flavor / "Screenshots" / "WoWScrnShot_101426_112000.jpg"),
                 "subzone: atlas '' | game 'Sentinel Hill'", "x1 General.log: [E][Lua] Lua Error",
                 "p95 0.8 p99 4.3 max 11.2, 2 over, graces login 96.4 map 31.5", "slow: map: labels x3",
                 "SHARED MagicMap: ", "General.log: [E][Lua] Lua Error: Interface/AddOns/MagicMap/Layers.lua:1473"):
        assert want in out, want
    assert "unrelated" not in out and "Blizzard_SharedXMLBase" not in out
    assert telemetry.main(["--wow", str(tmp_path), "--sv", FIXTURE, "--budgets"]) == 1
    out = capsys.readouterr().out
    for want in ("PASS  frame cost p95", "FAIL  frame cost max (outside graces)    11.20 ms (limit 8)",
                 "PASS  first map open", "FAIL  load (Data + Atlas)", "FAIL  errors per hour"):
        assert want in out, (want, out)
