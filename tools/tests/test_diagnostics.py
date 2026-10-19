"""The spike's diagnostics (M4.6, parity F54): /mma blips, tiles, landmarks, debug, perf, perf top, perf mem
print as the spike's do (Core.lua, Blips.lua, Landmarks.lua, Perf.lua); an unknown name or zone alone
answers with its one usage line; the gear's Advanced runs the same code (the `run` Command); the title's
debug line (Core.lua:1305-1313)."""
import re

import sim as S

SAY = "|cffffd100MagicMapAtlas|r: "
USAGE = SAY + ("/mma [toggle] | follow | map <id|name> | zone <name> | icon | tiles | tint | layers | landmarks"
               " | blips | indoor | perf | debug | reset")
DEBUG = re.compile(r"\|cff777777(\d+)_(\d+)  (\d+|-)  zoom (\d+)  layout [\d.]+ ms / (\d+) lines  1\.60\.1\.70450\|r$")


def said(s, line):
    """What `line` printed."""
    n = len(s.sim.prints)
    s.slash(line)
    s.step()
    return [s.sim.prints[i] for i in range(n + 1, len(s.sim.prints) + 1)]


def test_commands():
    s = S.boot()
    s.blips([("Mailbox", 40, 20)])
    s.slash("/mma toggle")
    s.run(6)
    blips = said(s, "/mma blips")  # (the square as the sensor refined it, from 8)
    assert re.fullmatch(re.escape(SAY) + r"blips: 1 known, answer square \d\.\d\d screen units each way", blips[0])
    assert blips[1:] == [SAY + "  Mailbox +40.0E +20.0N"]
    tiles = said(s, "/mma tiles")
    assert len(tiles) == 1 and tiles[0].startswith(SAY + "tile set: wow_classic_beta 1.60.1.70450. Maps: Eastern "
                                                   "Kingdoms (736), Kalimdor (988), Shadowfang Keep (25),")
    assert said(s, "/mma landmarks") == [SAY + "0 rares remembered. Target one, or pass one the game shows, and it'll "
                                               "appear on the map."]
    s.lua("ns.Game.db.Model.rares[0] = { ['npc:61'] = { name = 'Thuros Lightfingers', col = 32, row = 49, t = 0 } }")
    assert said(s, "/mma landmarks") == [SAY + "1 rares remembered"]
    top = said(s, "/mma perf top")
    assert top == [SAY + "perf: MagicMapAtlas against your other addons, right now",
                   SAY + "  client profiler: MagicMapAtlas 0.050 ms/frame recently, peak 0.1 ms; all addons 0.400 ms/frame",
                   SAY + "  busiest addons: Questie 0.200, |cffffd100MagicMapAtlas 0.050|r",
                   SAY + "  memory: MagicMapAtlas 2400 KB (#3 of 3); biggest: Questie 48000 KB, Details 9000 KB, "
                         "|cffffd100MagicMapAtlas 2400 KB|r"]
    mem = said(s, "/mma perf mem")
    assert mem[0] == SAY + "perf mem: MagicMapAtlas 2400 KB, 2400 KB after a full collection (0 KB was garbage)"
    assert re.fullmatch(re.escape(SAY) + r"  objects: \d+ FontString \(\d+ in use\), \d+ Texture \(\d+ in use\), "
                        r"\d+ Line \(\d+ in use\), \d+ tiles drawn, \d+ spare", mem[1]), mem[1]
    # An unknown name, zone alone: the spike's one line; /mma help lists every name, the rebuild's too.
    assert said(s, "/mma nothing") == [USAGE] and said(s, "/mma zone") == [USAGE]
    listed = said(s, "/mma help")
    assert len(listed) == len(s.ns.Game.commands) + 1 and any(" /mma perf load - " in p for p in listed)
    # The gear's Advanced: the same code, through the run Command.
    s.lua("ns.Game.Command({ kind = 'run', line = 'perf top' })")
    n = len(s.sim.prints)
    s.step()
    assert [s.sim.prints[i] for i in range(n + 1, len(s.sim.prints) + 1)] == top
    assert not s.errors()


def test_perf_record():
    """10 s of play recorded, then the spike's report: frames, our cost, the borders' layouts, where the time
    went, the comparison. Again while recording: it stops early."""
    s = S.boot()
    s.slash("/mma toggle")
    s.run(6)
    assert said(s, "/mma perf") == [SAY + "perf: recording 10 s; pan and zoom around (/mma perf again to stop early)"]
    assert s.ns.Runtime.recording
    n = len(s.sim.prints)
    s.wheel(3)
    s.drag(300, 0, 20)
    s.run(10)
    report = [s.sim.prints[i] for i in range(n + 1, len(s.sim.prints) + 1)]
    assert not s.ns.Runtime.recording
    assert re.fullmatch(re.escape(SAY) + r"perf: 600 frames in 10\.0 s, 60 fps, worst frame 17 ms, 0 hitches \(>33 ms\)",
                        report[0]), report[0]
    assert report[1].startswith(SAY + "  map script: ") and "ms/frame on average" in report[1]
    m = re.fullmatch(re.escape(SAY) + r"  borders: (\d+) builds \(\d+ ms each\), (\d+) extensions, (\d+) frames "
                     r"\((\d+)%\) showing past them", report[2])
    assert m and int(m[1]) >= 1, report[2]  # (the wheel's zoom: a build)
    assert report[3].startswith(SAY + "  all of MagicMapAtlas's scripts and events: ")
    where = report[4:12]
    assert all(re.fullmatch(re.escape(SAY) + r"    .+  \d+\.\d{3} ms/frame \(max \d+\.\d ms(, \d+ calls)?\)", w)
               for w in where), where
    assert any("map: borders" in w for w in where)
    assert report[12].startswith(SAY + "  client profiler: ") and report[-1].startswith(SAY + "  memory: ")
    said(s, "/mma perf")
    s.run(1)
    stopped = said(s, "/mma perf")
    assert stopped[0].startswith(SAY + "perf: 6") and " frames in 1." in stopped[0] and not s.ns.Runtime.recording
    assert not s.errors()


def test_debug_line():
    """/mma debug: the subtitle ends in the grey debug part (the view's centre's tile, else the hovered one's),
    saved; again, gone."""
    s = S.boot()
    s.slash("/mma toggle")
    s.run(1)
    sub = s.ns.UI.Title.subtitle
    assert not DEBUG.search(sub.GetText(sub))
    assert said(s, "/mma debug") == [SAY + "debug info on"] and s.ns.UI.saved.debug
    s.run(0.1)
    cam = s.ns.UI.Camera.cam
    m = DEBUG.search(sub.GetText(sub))
    assert m, sub.GetText(sub)
    col, row, fdid, zoom, lines = int(m[1]), int(m[2]), m[3], int(m[4]), int(m[5])
    assert (col, row, zoom) == (int(cam.cx), int(cam.cy), int(cam.zoom)) and lines > 0
    assert fdid == str(s.ns.Atlas.Tiles(0)[col * 64 + row])
    s.sim.MoveCursorTo(s.ns.UI.Window.view, 0.95, 0.5)  # hovering: the tile under the cursor
    s.run(0.1)
    m = DEBUG.search(sub.GetText(sub))
    assert m and int(m[1]) > col, sub.GetText(sub)
    assert said(s, "/mma debug") == [SAY + "debug info off"] and not s.ns.UI.saved.debug
    s.run(0.1)
    assert not DEBUG.search(sub.GetText(sub))
    assert not s.errors()
