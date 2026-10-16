#!/bin/sh
# Everything CI runs (.github/workflows/check.yml): luacheck (globals, TOC,
# boundaries), lint_div (no `/` that may be 0: spike-bugs E3), then the tests,
# twice: as plain Lua, and strict (MM_STRICT=1: `/` by 0 raises, as the client's).
# Sets up .venv (gitignored) on first use.
#
#   tools/check.sh            # all of it
#   tools/check.sh -k smoke   # pytest arguments pass through
#   MM_CLOCK_SCALE=4 tools/check.sh   # the sim's real clock 4x slow (a CI runner): no test may notice
set -eu
cd "$(dirname "$0")/.."
if [ ! -x .venv/bin/python ]; then
	python3 -m venv .venv
	.venv/bin/pip install -q -r tools/requirements-dev.txt
fi
.venv/bin/python tools/luacheck.py
.venv/bin/python tools/lint_div.py
.venv/bin/python -m pytest tools/tests -q -p no:cacheprovider "$@"
MM_STRICT=1 .venv/bin/python -m pytest tools/tests -q -p no:cacheprovider "$@"
