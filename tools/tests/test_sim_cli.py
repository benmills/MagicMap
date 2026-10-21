"""tools/sim.py's command line: a session scripted, the map opened, zoomed, dragged and walked
with past login's grace, a blip placed, and what it reports."""
import json
import os
import re
import subprocess
import sys

from sim import TESTS


def test_cli():
    script = "blip Mailbox 40 20; slash /mm toggle; run 6; wheel 3; run 1; drag 100 0 10; walk 2 east; perf; layers\n"
    script += "lua local f = sim.frame; return f, ns.UI ~= nil"
    got = subprocess.run([sys.executable, os.path.join(os.path.dirname(TESTS), "sim.py"), "--priced", "--run", script],
                         capture_output=True, text=True)
    assert got.returncode == 0, got.stdout + got.stderr
    out = got.stdout
    by_state = out.split("\nbyState: ")[1].split("\n")[0]
    assert "> perf\nframes " in out and '"zoom"' in by_state and "\nslowest calls" in out
    assert "> layers\ntiles " in out and re.search(r" blips [1-9]", out)  # (the blip; with QuestieDB's data, the town services)
    frame, ui = json.loads(out.split("return f, ns.UI ~= nil\n")[1])
    assert frame > 9 * 60 and ui
