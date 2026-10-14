import os
import sys

import pytest

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import fixtures  # noqa: E402


@pytest.fixture(scope="session")
def world(tmp_path_factory):
    """A synthetic local install (see fixtures.build_world)."""
    install = str(tmp_path_factory.mktemp("install"))
    fixtures.build_world(install)
    return install
