#!/bin/sh
# The release zip of a committed ref, one MagicMap/ folder to drop into Interface/AddOns, with LICENSE and
# NOTICE.md: dist/MagicMap-<ref>.zip. Everything committed ships, the quest data from QuestieDB and Questie
# too (GPLv3: D1, NOTICE.md).
# The TOC is stamped (## X-Stamped: game/Validate.lua's one build's log).
# A tag v<x> must be the TOC's ## Version, which it keeps; another ref's ## Version becomes the ref's build.
# Each zip is then unzipped into a scratch AddOns folder and loaded in the sim from there, a first login
# (every TOC file there, the notice once without the data, never with it; grow, zoom, drag, shrink): 0
# errors, or no zip.
#
#   tools/package.sh          # HEAD
#   tools/package.sh v2.0.0
set -eu
ref=${1:-HEAD}
cd "$(dirname "$0")/.."
root=$PWD
py=$( [ -x .venv/bin/python ] && echo "$root/.venv/bin/python" || echo python3 )
rev=$(git describe --always "$ref")
version=$(git show "$ref:MagicMap.toc" | sed -n 's/^## Version: *//p' | tr -d '\r')
case $ref in
v*) [ "v$version" = "$ref" ] || { echo "tag $ref doesn't match the TOC's ## Version $version" >&2; exit 1; } ;;
*) version=$rev ;;
esac
mkdir -p dist
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

build() {  # $1 its build's stamp
	dir="$tmp/zip"
	mkdir -p "$dir"
	git archive --prefix=MagicMap/ "$ref" MagicMap.toc LICENSE NOTICE.md Data Textures atlas runtime game model ui | tar -x -C "$dir"
	toc="$dir/MagicMap/MagicMap.toc"
	"$py" tools/install.py --stamp "$toc" "$1"
	sed "s/^## Version: .*/## Version: $version/" "$toc" > "$toc.new" && mv "$toc.new" "$toc"
	out="dist/MagicMap-$ref.zip"
	rm -f "$out"
	(cd "$dir" && "$py" -m zipfile -c "$root/$out" MagicMap)
	mkdir "$tmp/AddOns"
	"$py" -m zipfile -e "$out" "$tmp/AddOns"
	"$py" - "$tmp/AddOns/MagicMap" 1 <<'EOF' || { rm -f "$out"; exit 1; }
import os, sys
sys.path.insert(0, "tools")
import luacheck
root, data = sys.argv[1], bool(sys.argv[2])
luacheck.ROOT, luacheck.TOC = root, os.path.join(root, "MagicMap.toc")
import sim
want = [f for f in luacheck.toc_files() if data or f not in sim.QUESTIE] + ["Textures/PlayerArrow.tga", "Textures/GlowRing.tga", "LICENSE", "NOTICE.md"]
missing = [f for f in want if not os.path.isfile(os.path.join(root, f))]
extra = [f for f in sim.QUESTIE if not data and os.path.exists(os.path.join(root, f))]
s = sim.boot(saved="MagicMap2DB = nil")
s.run(6); s.press("M"); s.run(2); s.wheel(-6); s.run(2); s.drag(200, 80); s.run(2); s.press("M"); s.run(8)
s.slash("/mm help"); s.slash("/mm toggle"); s.run(1); s.slash("/mm toggle"); s.run(2)
notices = sum("QuestieDB isn't loaded" in str(p) for p in s.sim.prints.values())
errors = s.errors() + [f"missing {f}" for f in missing] + [f"not ours to ship: {f}" for f in extra]
if notices != (0 if data else 1):
    errors.append(f"the no-data notice {notices} times")
shown = s.lua("return ns.UI.Window.frame:IsShown()")
print(f"  {os.path.basename(os.path.dirname(root))} in the sim: {len(want)} files, the map "
      f"{'shown' if shown else 'hidden'}, {notices} no-data notice, {len(errors)} errors")
for e in errors:
    print("  " + e)
sys.exit(1 if errors else 0)
EOF
	echo "$out ($(grep '^## X-Stamped' "$toc"))"
}

build "$rev"
