"""The web demo's server answers from Atlas over the fixture readers."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "demo"))

import server  # noqa: E402


def test_at_elwynn():
    assert server.Atlas.Continent(0) == 1415 and server.Atlas.Continent(1) == 1414
    a = server.at({"inst": "0", "col": "32.378", "row": "49.024"})
    assert a["zone"]["name"] == "Elwynn Forest" and a["zone"]["mapID"] == 1429
    assert a["walk"]["class"] == 1
