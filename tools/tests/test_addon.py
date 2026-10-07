"""The addon's Lua: compile + globals check, and the headless smoke test
(each scenario on the simulated WoW Forever client)."""
import subprocess
import sys

import pytest

import luacheck
import smoketest


def test_luacheck():
    result = subprocess.run([sys.executable, luacheck.__file__], capture_output=True, text=True)
    assert result.returncode == 0, result.stdout


@pytest.mark.parametrize("scenario", smoketest.scenario_names())
def test_smoke(scenario):
    problems = smoketest.run(scenario)
    assert not problems, "\n\n".join(problems)
