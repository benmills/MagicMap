#!/bin/sh
# A zip of a committed ref: dist/MagicMap-<ref>.zip, one MagicMap/
# folder to drop into Interface/AddOns, its TOC stamped as the ref's build
# (## Version and ## X-Stamped: tools/install.py's stamp, game/Validate.lua's
# one build's log). Only what's committed, so not the gitignored
# QuestieDB-derived data (the game skips TOC files it can't find).
#
#   tools/package.sh          # HEAD
#   tools/package.sh v0.1.0
set -eu
ref=${1:-HEAD}
cd "$(dirname "$0")/.."
mkdir -p dist
out="$PWD/dist/MagicMap-$ref.zip"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
git archive --prefix=MagicMap/ "$ref" MagicMap.toc Data Textures atlas runtime game model ui | tar -x -C "$tmp"
python3 tools/install.py --stamp "$tmp/MagicMap/MagicMap.toc" "$(git describe --always "$ref")"
rm -f "$out"
(cd "$tmp" && python3 -m zipfile -c "$out" MagicMap)
echo "dist/MagicMap-$ref.zip"
