"""Where game files come from: a local install (CASC) or wago.tools. Both
give the same interface, so every generator can run from either.

    src = open_source("local", install="/Applications/World of Warcraft", product="wow_classic_beta")
    src = open_source("wago", product="wow_classic_era")
    src.version             # "1.15.7.61582"
    src.prefetch(fdids)     # optional batching hint
    src.read(fdid)          # bytes, or None if unavailable
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

from .casc import CascStore

WAGO = "https://wago.tools/api"


class Source:
    product: str
    version: str

    def prefetch(self, fdids) -> None:
        pass

    def read(self, fdid: int) -> bytes | None:
        raise NotImplementedError


class LocalSource(Source):
    def __init__(self, install: str, product: str):
        self.store = CascStore(install, product)
        self.product = product
        self.version = self.store.version
        print(f"build: {self.store.build_name}", file=sys.stderr)

    def prefetch(self, fdids) -> None:
        self.store.resolve(fdids)

    def read(self, fdid: int) -> bytes | None:
        return self.store.read(fdid)


class WagoSource(Source):
    """Files from wago.tools' CASC proxy, cached on disk per version (game
    files for a given version never change)."""

    def __init__(self, product: str, version: str | None = None, cache_dir: str | None = None):
        self.product = product
        self.version = version or self.latest_version(product)
        root = cache_dir or os.environ.get("MAGICMAP_CACHE") or os.path.expanduser("~/.cache/magicmap")
        self.cache_dir = os.path.join(root, "wago", self.version)

    @staticmethod
    def latest_version(product: str) -> str:
        with urllib.request.urlopen(f"{WAGO}/builds") as r:
            builds = json.load(r)
        entries = builds.get(product)
        if not entries:
            raise SystemExit(f"product {product} not on wago.tools")
        return entries[0]["version"]

    def read(self, fdid: int) -> bytes | None:
        path = os.path.join(self.cache_dir, f"{fdid}.bin")
        if os.path.exists(path):
            with open(path, "rb") as f:
                return f.read()
        try:
            with urllib.request.urlopen(f"{WAGO}/casc/{fdid}?version={self.version}") as r:
                data = r.read()
        except urllib.error.HTTPError:
            return None
        if not data:
            return None
        os.makedirs(self.cache_dir, exist_ok=True)
        with open(path + ".tmp", "wb") as f:
            f.write(data)
        os.replace(path + ".tmp", path)
        return data


def open_source(kind: str, product: str, install: str | None = None) -> Source:
    if kind == "local":
        if not install:
            raise SystemExit("local mode needs an install path")
        return LocalSource(install, product)
    if kind == "wago":
        return WagoSource(product)
    raise SystemExit(f"unknown source {kind!r} (local or wago)")


def add_source_args(parser) -> None:
    """Shared CLI: `local INSTALL PRODUCT` or `wago PRODUCT`."""
    parser.add_argument("mode", choices=["local", "wago"])
    parser.add_argument("args", nargs="+", metavar="INSTALL PRODUCT | PRODUCT")


def source_from_args(parser, ns) -> Source:
    if ns.mode == "local":
        if len(ns.args) != 2:
            parser.error("local needs INSTALL PRODUCT")
        return open_source("local", ns.args[1], install=ns.args[0])
    if len(ns.args) != 1:
        parser.error("wago needs PRODUCT")
    return open_source("wago", ns.args[0])
