"""tools/sim.py's command line: a session scripted, the map opened, zoomed, dragged and walked
with, and what it reports."""
import os
import subprocess
import sys

from sim import TESTS


def test_cli():
    script = "slash /mma toggle; run 3; wheel 3; run 1; drag 100 0 10; walk 2 east; perf; layers; lua return (...).frame"
    got = subprocess.run([sys.executable, os.path.join(os.path.dirname(TESTS), "sim.py"), "--priced", "--run", script],
                         capture_output=True, text=True)
    assert got.returncode == 0, got.stdout + got.stderr
    out = got.stdout
    assert "> perf\nframes " in out and "\nbyState: " in out and "\nslowest calls" in out
    assert "> layers\ntiles " in out and int(out.split("> lua return (...).frame\n")[1]) > 6 * 60
