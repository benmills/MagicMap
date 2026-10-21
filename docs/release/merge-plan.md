# M6.2: bringing 2.0.0 into ~/code/MagicMap

The user's call, at the very end (D8: blunt is fine, the old history may go). Nothing here has been
run. Every write to ~/code/MagicMap and every push is the user's.

Where things stand (2026-10-19):

- **This repo** (`~/code/magic-map`, origin `benmills/magic-map-atlas-temp`): `main`, with the local tag
  `v2.0.0` (not pushed). Its history (~270 commits) never held the QuestieDB-derived Data (gitignored:
  `git log --all -- Data/Npcs.lua` is empty), so it can go public as it is.
- **The spike** (`~/code/MagicMap`, origin `git@github.com:benmills/MagicMap.git`): checked out on
  `sensor` (0c71e2b), clean. `main` (ae11aba) is 18 commits past `v1.0.0` (6a1188c); `sensor` is 17 past
  `main`, both pushed. Its tags `v0.1.0-alpha`, `v1.0.0-beta`, `v1.0.0` and their GitHub releases stay.
- **Both**: `.github/workflows/check.yml` runs `tools/check.sh` (2.0.0's replaces the spike's). Neither
  has a LICENSE (a release needs one: the user's). README media: 2.0.0's README shows
  `docs/zoomable-minimap.gif` and `docs/minimap-to-big-map.gif`, 1.0's (the same files), until new ones.

## First, either way

```sh
# 2.0.0 is what main is (re-tag after any fix since the tag, and package again)
cd ~/code/magic-map
git status --short                                   # nothing
[ "$(git rev-parse v2.0.0^{commit})" = "$(git rev-parse main)" ] || { git tag -f v2.0.0 main && tools/package.sh v2.0.0; }

# The spike's last code tagged, and 2.0.0 fetched into it
cd ~/code/MagicMap
git status --short                                   # nothing
git fetch origin
git tag -a spike-1.0.0 -m "MagicMap 1.x's last code (v1.0.0 and the sensor branch past it), before 2.0.0" origin/sensor
git remote add rebuild ~/code/magic-map
git fetch --no-tags rebuild refs/tags/v2.0.0:refs/tags/v2.0.0
```

## Option A: replace the tree, keeping history

One merge commit on `main` whose tree is 2.0.0's, with 1.x's history as its first parent and the
rebuild's as its second: `git log` shows both, `git blame` follows the rebuild's files into its history.

```sh
cd ~/code/MagicMap
git switch main
git merge --ff-only origin/sensor                    # main takes the sensor branch's 17 commits
git merge --allow-unrelated-histories --no-commit -s ours v2.0.0
git read-tree -u --reset v2.0.0                      # the index and working tree become 2.0.0's
git commit -m "MagicMap 2.0.0: the rebuild replaces 1.x's tree (D8)"
[ "$(git rev-parse HEAD^{tree})" = "$(git rev-parse v2.0.0^{tree})" ] && echo "2.0.0's tree"
git remote remove rebuild
```

## Option B: a fresh start

`main` becomes the rebuild's own history; 1.x's commits stay reachable only from `spike-1.0.0`, its
release tags and the `sensor` branch (delete that too for a clean list of branches).

```sh
cd ~/code/MagicMap
git switch -C main v2.0.0                            # main = the rebuild's history, ending at 2.0.0
git remote remove rebuild
```

Squashed instead (one commit, no rebuild history either): `git switch --orphan fresh && git read-tree -u
--reset v2.0.0 && git commit -m "MagicMap 2.0.0" && git branch -M fresh main`.

## Then, either way

```sh
cd ~/code/MagicMap
.venv/bin/pip install -q -r tools/requirements-dev.txt   # 1.x's .venv lacks the rebuild's packages
tools/check.sh                                       # green: without the QuestieDB-derived Data its tests skip, as CI
for f in Npcs Objects Items Quests BlipServices; do ln -sf ~/code/magic-map/Data/$f.lua Data/; done  # to package here
git log --oneline -3; git status --short             # nothing: dist/*.zip, .venv and those links are gitignored

# The pushes (A: a fast-forward; B: main is rewritten)
git push origin main spike-1.0.0 v2.0.0              # option A
git push --force-with-lease=main:ae11aba origin main && git push origin spike-1.0.0 v2.0.0   # option B
git push origin --delete sensor                      # optional: its commits are under spike-1.0.0
```

Exit (v1-plan M6.2): CI green on `benmills/MagicMap` (check.yml on the push), `spike-1.0.0` reachable
there. The GitHub release itself (D7: notes in dist/RELEASE_NOTES-v2.0.0.md, the zip D1 allows) and
archiving `magic-map-atlas-temp` come after.
