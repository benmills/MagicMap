"""Bounded, mtime-aware compression cache for text and terrain responses.

HTTP content encoding keeps the MMT1 format and existing asset URLs unchanged.
WebP/PNG images are already compressed and are never recompressed here.
"""
from functools import lru_cache
import gzip
from pathlib import Path

COMPRESSIBLE = {'.mmt', '.js', '.mjs', '.css', '.html', '.json'}


def accepts_gzip(header):
    for part in header.split(','):
        name, *params = part.strip().lower().split(';')
        if name != 'gzip':
            continue
        try:
            return all(float(p.strip()[2:]) > 0 for p in params if p.strip().startswith('q='))
        except ValueError:
            return False
    return False


@lru_cache(maxsize=64)
def compressed_file(path, mtime_ns, size):
    # The timestamp and size are part of the cache key, including on redeploy.
    return gzip.compress(Path(path).read_bytes(), compresslevel=4, mtime=0)
