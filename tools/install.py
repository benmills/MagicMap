#!/usr/bin/env python3
"""Install this checkout into a WoW client for testing: deletes the installed
MagicMap from <wow>/<flavor>/Interface/AddOns and copies in what the game
loads (MagicMap.toc and the files it lists), straight from the working tree,
so uncommitted changes are included. /reload in game to pick them up.

  python3 tools/install.py                  # the flavor MagicMap is installed in
  python3 tools/install.py _classic_ptr_    # a specific flavor folder
  python3 tools/install.py --wow "D:/Games/World of Warcraft" _ptr_

The WoW folder defaults to $MAGICMAP_WOW, else the standard install location.
With no flavor, it uses the one flavor that already has MagicMap installed
(and lists the choices if that's none or several).
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from luacheck import toc_files  # noqa: E402

ADDON = "MagicMap"
DEFAULT_WOW = {
    "darwin": "/Applications/World of Warcraft",
    "win32": r"C:\Program Files (x86)\World of Warcraft",
}


def flavors(wow: str) -> list[str]:
    """Flavor folders (_retail_, _classic_ptr_, ...) in a WoW install."""
    return sorted(d for d in os.listdir(wow)
                  if d.startswith("_") and d.endswith("_") and os.path.isdir(os.path.join(wow, d)))


def addon_dir(wow: str, flavor: str) -> str:
    return os.path.join(wow, flavor, "Interface", "AddOns", ADDON)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("flavor", nargs="?", help="flavor folder, e.g. _classic_ptr_ (default: where it's installed)")
    parser.add_argument("--wow", default=os.environ.get("MAGICMAP_WOW") or DEFAULT_WOW.get(sys.platform),
                        help="World of Warcraft folder (default: $MAGICMAP_WOW or the standard location)")
    parser.add_argument("--no-check", action="store_true", help="skip the Lua check before installing")
    ns = parser.parse_args()

    if not ns.wow or not os.path.isdir(ns.wow):
        sys.exit(f"no WoW folder at {ns.wow!r}; pass --wow or set MAGICMAP_WOW")
    available = flavors(ns.wow)
    flavor = ns.flavor
    if not flavor:
        installed = [f for f in available if os.path.isdir(addon_dir(ns.wow, f))]
        if len(installed) != 1:
            which = "several flavors" if installed else "no flavor"
            sys.exit(f"{ADDON} is installed in {which}; pick one: tools/install.py <flavor>\n"
                     f"  flavors: {', '.join(available) or '(none)'}"
                     + (f"\n  installed in: {', '.join(installed)}" if installed else ""))
        flavor = installed[0]
    if flavor not in available:
        sys.exit(f"no flavor folder {flavor!r} in {ns.wow}; flavors: {', '.join(available) or '(none)'}")
    addons = os.path.join(ns.wow, flavor, "Interface", "AddOns")
    if not os.path.isdir(addons):
        sys.exit(f"{addons} doesn't exist; has this flavor been run once?")

    if not ns.no_check and subprocess.call([sys.executable, os.path.join(ROOT, "tools", "luacheck.py")],
                                           stdout=subprocess.DEVNULL) != 0:
        sys.exit("luacheck found problems (python3 tools/luacheck.py); not installing. --no-check to install anyway")

    files = ["MagicMap.toc"] + toc_files()
    missing = [f for f in files if not os.path.isfile(os.path.join(ROOT, f))]
    if missing:
        sys.exit(f"missing from the checkout: {', '.join(missing)}")

    dest = addon_dir(ns.wow, flavor)
    if os.path.islink(dest):
        sys.exit(f"{dest} is a symlink (already points at a checkout); remove it first if you want a copy")
    if os.path.exists(dest):
        # Only ever delete something that is MagicMap.
        if not os.path.isfile(os.path.join(dest, "MagicMap.toc")):
            sys.exit(f"{dest} doesn't look like MagicMap (no MagicMap.toc); not deleting it")
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
    print("/reload in game to load it")


if __name__ == "__main__":
    main()
