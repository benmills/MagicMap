#!/bin/sh
# Everything CI runs (.github/workflows/check.yml): luacheck (globals, TOC,
# boundaries), lint_div (no `/` that may be 0: spike-bugs E3), then the tests,
# twice and side by side: as plain Lua, and strict (MM_STRICT=1: `/` by 0 raises,
# as the client's). Each pass spread over CPUs (pytest-xdist); their output
# printed in turn. Sets up .venv (gitignored) on first use.
#
#   tools/check.sh                    # all of it: before committing
#   tools/check.sh --quick            # luacheck, lint_div and the plain pass alone: while iterating
#   tools/check.sh -k smoke           # pytest arguments pass through (both modes)
#   tools/check.sh --quick -n0 -s     # one process, the tests' prints shown
#   MM_CLOCK_SCALE=4 tools/check.sh   # the sim's real clock 4x slow (a CI runner): no test may notice
set -eu
cd "$(dirname "$0")/.."
[ -x .venv/bin/python ] || python3 -m venv .venv
.venv/bin/python -c "import xdist" 2>/dev/null || .venv/bin/pip install -q -r tools/requirements-dev.txt
.venv/bin/python tools/luacheck.py
.venv/bin/python tools/lint_div.py
if [ "${1:-}" = --quick ]; then
	shift
	exec .venv/bin/python -m pytest tools/tests -q -p no:cacheprovider -n auto "$@"
fi
# Half the CPUs each.
n=$(( ($(getconf _NPROCESSORS_ONLN) + 1) / 2 ))
logs=$(mktemp -d)
trap 'rm -rf "$logs"' EXIT
.venv/bin/python -m pytest tools/tests -q -p no:cacheprovider -n "$n" "$@" >"$logs/plain" 2>&1 &
plain=$!
MM_STRICT=1 .venv/bin/python -m pytest tools/tests -q -p no:cacheprovider -n "$n" "$@" >"$logs/strict" 2>&1 &
strict=$!
fail=0
wait $plain || fail=1
echo "== plain"
cat "$logs/plain"
wait $strict || fail=1
echo "== strict (MM_STRICT=1)"
cat "$logs/strict"
exit $fail
