#!/bin/sh
# Release zips of a committed ref, each one MagicMap/ folder to drop into Interface/AddOns:
#   dist/MagicMap-<ref>-no-questie-data.zip    what's committed: no QuestieDB-derived Data (the game skips TOC
#                                              files it can't find; game/NoData.lua says so in one chat line)
#   dist/MagicMap-<ref>-with-questie-data.zip  + this checkout's gitignored Data/Npcs, Objects, Items, Quests and
#                                              BlipServices (tools/gen_questie.py), when they're here
# Which one ships is D1's (QuestieDB declares no licence): the user's call before any upload.
# The TOC is stamped (## X-Stamped: game/Validate.lua's one build's log; the data makes a build of its own).
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
questie="Data/Npcs.lua Data/Objects.lua Data/Items.lua Data/Quests.lua Data/BlipServices.lua"
mkdir -p dist
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

build() {  # $1 the variant, $2 its build's stamp, $3 the Data files added
	dir="$tmp/$1"
	mkdir -p "$dir"
	git archive --prefix=MagicMap/ "$ref" MagicMap.toc Data Textures atlas runtime game model ui | tar -x -C "$dir"
	for f in $3; do cp "$f" "$dir/MagicMap/$f"; done
	toc="$dir/MagicMap/MagicMap.toc"
	"$py" tools/install.py --stamp "$toc" "$2"
	sed "s/^## Version: .*/## Version: $version/" "$toc" > "$toc.new" && mv "$toc.new" "$toc"
	out="dist/MagicMap-$ref-$1.zip"
	rm -f "$out"
	(cd "$dir" && "$py" -m zipfile -c "$root/$out" MagicMap)
	mkdir "$tmp/AddOns-$1"
	"$py" -m zipfile -e "$out" "$tmp/AddOns-$1"
	"$py" - "$tmp/AddOns-$1/MagicMap" "$3" <<'EOF' || { rm -f "$out"; exit 1; }
import os, sys
sys.path.insert(0, "tools")
import luacheck
root, data = sys.argv[1], bool(sys.argv[2])
luacheck.ROOT, luacheck.TOC = root, os.path.join(root, "MagicMap.toc")
import sim
want = [f for f in luacheck.toc_files() if data or f not in sim.QUESTIE] + ["Textures/PlayerArrow.tga", "Textures/GlowRing.tga"]
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

build no-questie-data "$rev" ""
if ls $questie >/dev/null 2>&1; then
	build with-questie-data "$rev+questie-data" "$questie"
else
	echo "no QuestieDB-derived Data here (tools/gen_questie.py): the no-data zip alone"
fi
