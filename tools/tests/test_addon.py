"""The addon's Lua: compile + globals check, and the headless smoke test
(each scenario on each simulated client flavor)."""
import subprocess
import sys

import pytest

import luacheck
import smoketest


def test_luacheck():
    result = subprocess.run([sys.executable, luacheck.__file__], capture_output=True, text=True)
    assert result.returncode == 0, result.stdout


@pytest.mark.parametrize("flavor", smoketest.FLAVORS)
@pytest.mark.parametrize("scenario", smoketest.scenario_names())
def test_smoke(flavor, scenario):
    problems = smoketest.run(flavor, scenario)
    assert not problems, "\n\n".join(problems)
