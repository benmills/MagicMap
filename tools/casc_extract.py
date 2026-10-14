#!/usr/bin/env python3
"""Extract files by FileDataID from a local WoW install, for one product
(e.g. wow_classic_beta = WoW Forever). Writes OUTDIR/<fdid>.bin.

  python3 tools/casc_extract.py "/Applications/World of Warcraft" wow_classic_beta OUTDIR 1349477 775971
  python3 tools/casc_extract.py --ckeys INSTALL PRODUCT - 1349477   # just print content keys
"""
from __future__ import annotations

import argparse
import os
import sys

from mmtools.casc import CascStore


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--ckeys", action="store_true", help="print each file's content key instead of extracting")
    parser.add_argument("install")
    parser.add_argument("product")
    parser.add_argument("outdir")
    parser.add_argument("fdids", nargs="+", type=int)
    ns = parser.parse_args()
    store = CascStore(ns.install, ns.product)
    print(f"build: {store.build_name}", file=sys.stderr)
    store.resolve(ns.fdids)
    if ns.ckeys:
        for fdid in ns.fdids:
            print(f"{fdid}\t{store.ckey(fdid) or '-'}")
        return
    os.makedirs(ns.outdir, exist_ok=True)
    missing = 0
    for fdid in ns.fdids:
        if store.ckey(fdid) is None:
            print(f"{fdid}\tnot in root")
            missing += 1
            continue
        data = store.read(fdid)
        if data is None:
            print(f"{fdid}\tnot in local storage")
            missing += 1
            continue
        with open(os.path.join(ns.outdir, f"{fdid}.bin"), "wb") as f:
            f.write(data)
        print(f"{fdid}\t{len(data)} bytes\tckey {store.ckey(fdid)}")
    sys.exit(1 if missing == len(ns.fdids) else 0)


if __name__ == "__main__":
    main()
