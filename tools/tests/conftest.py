import os
import sys

import pytest

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import fixtures  # noqa: E402

# The slowest first, so that under xdist (tools/check.sh) none starts last and holds the run up.
FIRST = ("test_data_diet", "test_replay[G6b]", "test_script_a_priced", "test_borders", "test_luacheck",
         "test_replay[D3]", "test_replay[P7]")


def pytest_collection_modifyitems(items):
    items.sort(key=lambda item: item.name not in FIRST)


@pytest.fixture(scope="session")
def world(tmp_path_factory):
    """A synthetic local install (see fixtures.build_world)."""
    install = str(tmp_path_factory.mktemp("install"))
    fixtures.build_world(install)
    return install
