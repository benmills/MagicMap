import os
import sys

import pytest

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import fixtures  # noqa: E402

# The slowest first, so that under xdist (tools/check.sh) none starts last and holds the run up.
FIRST = ("test_soak", "test_zoom_look", "test_replay[P3b]", "test_camera_as_spike", "test_replay_no_data[P3b]",
         "test_script_a_priced", "test_replay[P1]", "test_replay[G6b]", "test_replay_no_data[P1]", "test_data_diet",
         "test_quests_ticks", "test_replay[D3]", "test_replay_no_data[G6b]", "test_replay[P7]", "test_luacheck")


def pytest_collection_modifyitems(items):
    items.sort(key=lambda item: FIRST.index(item.name) if item.name in FIRST else len(FIRST))


@pytest.fixture(scope="session")
def world(tmp_path_factory):
    """A synthetic local install (see fixtures.build_world)."""
    install = str(tmp_path_factory.mktemp("install"))
    fixtures.build_world(install)
    return install
