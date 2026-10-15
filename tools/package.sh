#!/bin/sh
# A zip of a committed ref: dist/MagicMapAtlas-<ref>.zip, one MagicMapAtlas/
# folder to drop into Interface/AddOns. Only what's committed, so not the
# gitignored QuestieDB-derived data (the game skips TOC files it can't find).
#
#   tools/package.sh          # HEAD
#   tools/package.sh v0.1.0
set -eu
ref=${1:-HEAD}
cd "$(dirname "$0")/.."
mkdir -p dist
out="dist/MagicMapAtlas-$ref.zip"
git archive --format=zip --prefix=MagicMapAtlas/ -o "$out" "$ref" MagicMapAtlas.toc Data Textures atlas runtime game model ui
echo "$out"
