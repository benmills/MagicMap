#!/bin/sh
# Everything CI runs: the globals check and the test suite. Sets up .venv
# (gitignored) on first use.
#
#   tools/check.sh            # all of it
#   tools/check.sh -k minimap # pytest arguments pass through
set -eu
cd "$(dirname "$0")/.."
if [ ! -x .venv/bin/python ]; then
	python3 -m venv .venv
	.venv/bin/pip install -q -r tools/requirements-dev.txt
fi
.venv/bin/python tools/luacheck.py
.venv/bin/python -m pytest tools/tests -q -p no:cacheprovider "$@"
