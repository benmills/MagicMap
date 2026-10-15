#!/usr/bin/env python3
"""Install this checkout into a WoW client for testing: replaces
<wow>/<flavor>/Interface/AddOns/MagicMapAtlas with what the game loads
(MagicMapAtlas.toc, the files it lists and the Textures/ tree), straight from
the working tree, so uncommitted changes and the gitignored QuestieDB-derived
data (when generated) are included. /reload in game to pick up Lua changes
(new files, the TOC or new textures need a client restart).

  python3 tools/install.py                    # _classic_beta_ (WoW Forever)
  python3 tools/install.py _classic_ptr_      # another flavor folder
  python3 tools/install.py --wow "D:/Games/World of Warcraft"

The WoW folder defaults to $MAGICMAP_WOW, else the standard install location.
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from luacheck import existing_toc_files, toc_files  # noqa: E402

ADDON = "MagicMapAtlas"
DEFAULT_WOW = {
    "darwin": "/Applications/World of Warcraft",
    "win32": r"C:\Program Files (x86)\World of Warcraft",
}


def texture_files() -> list[str]:
    out = []
    for dirpath, dirnames, filenames in os.walk(os.path.join(ROOT, "Textures")):
        dirnames.sort()
        out += [os.path.relpath(os.path.join(dirpath, f), ROOT) for f in sorted(filenames) if not f.startswith(".")]
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("flavor", nargs="?", default="_classic_beta_", help="flavor folder (default: _classic_beta_)")
    parser.add_argument("--wow", default=os.environ.get("MAGICMAP_WOW") or DEFAULT_WOW.get(sys.platform),
                        help="World of Warcraft folder (default: $MAGICMAP_WOW or the standard location)")
    parser.add_argument("--no-check", action="store_true", help="skip the Lua check before installing")
    ns = parser.parse_args()

    addons = os.path.join(ns.wow or "", ns.flavor, "Interface", "AddOns")
    if not os.path.isdir(addons):
        sys.exit(f"no {addons}; pass --wow / a flavor folder (has this flavor been run once?)")
    if not ns.no_check and subprocess.call([sys.executable, os.path.join(ROOT, "tools", "luacheck.py")],
                                           stdout=subprocess.DEVNULL) != 0:
        sys.exit("luacheck found problems (tools/luacheck.py); not installing. --no-check to install anyway")

    listed = existing_toc_files()
    skipped = sorted(set(toc_files()) - set(listed))
    files = [f"{ADDON}.toc"] + listed + texture_files()
    missing = [f for f in files if not os.path.isfile(os.path.join(ROOT, f))]
    if missing:
        sys.exit(f"missing from the checkout: {', '.join(missing)}")

    dest = os.path.join(addons, ADDON)
    if os.path.islink(dest):
        sys.exit(f"{dest} is a symlink (already points at a checkout); remove it first if you want a copy")
    if os.path.exists(dest):
        if not os.path.isfile(os.path.join(dest, f"{ADDON}.toc")):  # only ever delete our own
            sys.exit(f"{dest} doesn't look like {ADDON} (no {ADDON}.toc); not deleting it")
        shutil.rmtree(dest)
    for f in files:
        target = os.path.join(dest, f)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.copy2(os.path.join(ROOT, f), target)

    try:
        rev = subprocess.check_output(["git", "-C", ROOT, "describe", "--always", "--dirty"], text=True).strip()
    except (OSError, subprocess.CalledProcessError):
        rev = "?"
    print(f"installed {ADDON} {rev} ({len(files)} files) into {dest}")
    if skipped:
        print(f"not generated (gitignored), so left out: {', '.join(skipped)} (tools/gen_questie.py)")
    if os.path.isdir(os.path.join(addons, "MagicMap")):
        print("disable the MagicMap spike addon while testing this one: they share the MagicMap_* data globals")
    print("/reload in game (a restart for new files or textures); /mma lists the commands")


if __name__ == "__main__":
    main()
