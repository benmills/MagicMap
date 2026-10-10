#!/bin/sh
# Build the release zip from a git tag: dist/MagicMap-<tag>.zip, holding one
# MagicMap/ folder ready to drop into Interface/AddOns. Files marked
# export-ignore in .gitattributes (tools/, dotfiles) are left out.
#
#   tools/package.sh v1.0.0
set -eu
tag=${1:?usage: tools/package.sh <tag>}
cd "$(dirname "$0")/.."

# The tag must exist and match the TOC's version (v<version>).
git rev-parse -q --verify "refs/tags/$tag" >/dev/null || { echo "no tag $tag" >&2; exit 1; }
version=$(git show "$tag:MagicMap.toc" | sed -n 's/^## Version: *//p' | tr -d '\r')
[ "v$version" = "$tag" ] || { echo "tag $tag doesn't match the TOC version $version" >&2; exit 1; }

python3 tools/luacheck.py >/dev/null

mkdir -p dist
out="dist/MagicMap-$tag.zip"
git archive --format=zip --prefix=MagicMap/ -o "$out" "$tag"
echo "$out"
