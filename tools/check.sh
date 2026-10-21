#!/bin/sh
# Everything CI runs (.github/workflows/check.yml): lint_div (no `/` that may be 0:
# spike-bugs E3), then the tests (luacheck among them: test_luacheck), twice and
# side by side: as plain Lua, and strict (MM_STRICT=1: `/` by 0 raises, as the
# client's). Each pass spread over half the CPUs (pytest-xdist); their output
# printed in turn. Sets up .venv (gitignored) on first use.
#
#   tools/check.sh                    # all of it: before committing
#   tools/check.sh --quick            # lint_div and the plain pass alone: while iterating
#   tools/check.sh -k smoke           # pytest arguments pass through (both modes); --quick -k: one process
#   tools/check.sh --quick -n0 -s     # one process, the tests' prints shown
#   PYTEST_XDIST_AUTO_NUM_WORKERS=4 tools/check.sh   # 4 workers in all, not the CPUs: several checks at once
#   UPDATE_GOLDEN=1 tools/check.sh    # the goldens rewritten: the passes one after the other
#   MM_CLOCK_SCALE=4 tools/check.sh   # the sim's real clock 4x slow (a CI runner): no test may notice
set -eu
cd "$(dirname "$0")/.."
[ -x .venv/bin/python ] || python3 -m venv .venv
.venv/bin/python -c "import xdist" 2>/dev/null || .venv/bin/pip install -q -r tools/requirements-dev.txt
.venv/bin/python tools/lint_div.py
if [ "${1:-}" = --quick ]; then
	shift
	# -k picks a few tests: starting workers costs more than they save.
	case " $* " in *" -k"*) n=0 ;; *) n=auto ;; esac
	exec .venv/bin/python -m pytest tools/tests -q -p no:cacheprovider -n "$n" "$@"
fi
# Half the workers each.
n=$(( (${PYTEST_XDIST_AUTO_NUM_WORKERS:-$(getconf _NPROCESSORS_ONLN)} + 1) / 2 ))
logs=$(mktemp -d)
plain='' strict='' fail=0
trap 'rm -rf "$logs"' EXIT
trap 'kill $plain $strict 2>/dev/null; exit 1' INT TERM
.venv/bin/python -m pytest tools/tests -q -p no:cacheprovider -n "$n" --basetemp "$logs/plain-tmp" "$@" >"$logs/plain" 2>&1 &
plain=$!
# UPDATE_GOLDEN=1: the plain pass rewrites the goldens before the strict one reads them.
[ -z "${UPDATE_GOLDEN:-}" ] || { wait $plain || fail=1; plain=''; }
MM_STRICT=1 .venv/bin/python -m pytest tools/tests -q -p no:cacheprovider -n "$n" --basetemp "$logs/strict-tmp" "$@" >"$logs/strict" 2>&1 &
strict=$!
[ -z "$plain" ] || wait $plain || fail=1
echo "== plain"
cat "$logs/plain"
wait $strict || fail=1
echo "== strict (MM_STRICT=1)"
cat "$logs/strict"
exit $fail
