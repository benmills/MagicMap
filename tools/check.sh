#!/bin/sh
# Everything CI runs (.github/workflows/check.yml): luacheck (globals, TOC,
# boundaries) then the tests. Sets up .venv (gitignored) on first use.
#
#   tools/check.sh            # all of it
#   tools/check.sh -k smoke   # pytest arguments pass through
set -eu
cd "$(dirname "$0")/.."
if [ ! -x .venv/bin/python ]; then
	python3 -m venv .venv
	.venv/bin/pip install -q -r tools/requirements-dev.txt
fi
.venv/bin/python tools/luacheck.py
.venv/bin/python -m pytest tools/tests -q -p no:cacheprovider "$@"
