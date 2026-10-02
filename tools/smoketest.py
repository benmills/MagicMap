#!/usr/bin/env python3
"""Load MagicMap in a simulated WoW client and drive it, headlessly.

Runs each scenario in tools/tests/scenarios.lua on a fresh simulated client
(tools/tests/wowsim.lua) for each flavor, and reports every Lua error the
addon raised and every failed expectation. It's no substitute for the game,
but it executes the code: nil calls, typos, bad arithmetic and wrong
assumptions about API shapes show up here first.

  python3 tools/smoketest.py                      # all flavors, all scenarios
  python3 tools/smoketest.py --flavor era minimap_mode

Needs `pip install lupa`.
"""
from __future__ import annotations

import argparse
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TESTS = os.path.join(ROOT, "tools", "tests")
FLAVORS = ["forever", "era", "retail"]

sys.path.insert(0, os.path.join(ROOT, "tools"))
from luacheck import toc_files  # noqa: E402


def new_client(flavor: str):
    try:
        from lupa import lua51
    except ImportError:
        sys.exit("smoketest needs Lua 5.1 from the lupa package: pip install lupa")
    L = lua51.LuaRuntime(encoding="latin-1", unpack_returned_tuples=True)
    L.globals().SIM_FLAVOR = flavor
    sim = L.eval("function(path) return assert(loadfile(path))() end")(os.path.join(TESTS, "wowsim.lua"))
    return L, sim


def boot(L, sim):
    """Load the TOC's files as the game does (each gets the addon name and a
    shared namespace), then log in."""
    ns = L.table()
    load = L.eval("""function(path, ns)
        local chunk, err = loadfile(path)
        if not chunk then error(err, 0) end
        return Sim.Call("loading " .. path:match("[^/]+$"), chunk, "MagicMap", ns)
    end""")
    for f in toc_files():
        load(os.path.join(ROOT, f), ns)
    sim.FireEvent("ADDON_LOADED", "MagicMap")
    sim.FireEvent("PLAYER_LOGIN")
    sim.FireEvent("PLAYER_ENTERING_WORLD", True, False)
    sim.Run(1)
    return ns


def scenario_names() -> list[str]:
    L, sim = new_client("forever")
    scenarios = L.eval("function(path, ...) return assert(loadfile(path))(...) end")(
        os.path.join(TESTS, "scenarios.lua"), sim, L.table(), lambda *a: None)
    return sorted(scenarios.keys())


def run(flavor: str, name: str) -> list[str]:
    """Problems from one scenario on one flavor (empty: it passed)."""
    L, sim = new_client(flavor)
    ns = boot(L, sim)
    failures: list[str] = []

    def check(cond, msg):
        if not cond:
            failures.append(f"expected: {msg}")

    scenarios = L.eval("function(path, ...) return assert(loadfile(path))(...) end")(
        os.path.join(TESTS, "scenarios.lua"), sim, ns, check)
    sim.Call(f"scenario {name}", scenarios[name])
    errors = [str(e) for e in sim.errors.values()]
    return errors + failures


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--flavor", choices=FLAVORS, action="append", help="default: all")
    parser.add_argument("scenarios", nargs="*", help="default: all")
    parser.add_argument("-v", "--verbose", action="store_true", help="full tracebacks")
    ns = parser.parse_args()
    names = ns.scenarios or scenario_names()
    failed = 0
    for flavor in ns.flavor or FLAVORS:
        for name in names:
            problems = run(flavor, name)
            print(f"{'ok  ' if not problems else 'FAIL'} {flavor:8} {name}")
            for p in problems:
                text = p if ns.verbose else p.split("\nstack traceback:")[0]
                print("     " + text.replace("\n", "\n     "))
            failed += bool(problems)
    print(f"{failed} failed" if failed else "all passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
