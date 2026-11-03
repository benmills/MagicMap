#!/usr/bin/env python3
"""Export outdoor ADT terrain for the web explorer, without changing Atlas formats.

.venv/bin/python demo/export_terrain.py local INSTALL wowf --inst 0
.venv/bin/python demo/export_terrain.py wago wowf --version 1.60.1.70707 --inst 0

Exports a coarse mesh covering every available root ADT and a native fan mesh for
close inspection. Hole bits are respected at both resolutions. Source version
must exactly match Data/Tiles.lua. No buildings, liquids or collision are inferred.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import struct
import sys
from urllib.request import Request, urlopen
from urllib.error import HTTPError

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from atlas_lua import load_atlas  # noqa: E402
from mmtools.formats import adt_chunks, iter_chunks, wdt_maid  # noqa: E402
from mmtools.maps import MAP_DB2, read_maps  # noqa: E402
from mmtools.sources import add_source_args, source_from_args, WagoSource  # noqa: E402
from export_preview import build_preview  # noqa: E402


class PinnedWagoSource(WagoSource):
    """Pinned, cached source with an explicit tool user agent and bounded requests."""
    def read(self, fdid):
        path = Path(self.cache_dir) / f'{fdid}.bin'
        if path.is_file():
            return path.read_bytes()
        req = Request(f'https://wago.tools/api/casc/{fdid}?version={self.version}',
                      headers={'User-Agent': 'MagicMap-demo-asset-exporter/1'})
        try:
            with urlopen(req, timeout=30) as response:
                data = response.read()
        except HTTPError as error:
            if error.code == 404:
                return None
            raise
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return data


def holes(buf):
    """Demo-only ADT hole masks; shared WMO/ADT reader stays owned by indoor work."""
    out = {}
    for magic, off, size in iter_chunks(buf):
        if magic != b'MCNK' or size < 128:
            continue
        flags, ix, iy = struct.unpack_from('<III', buf, off)
        if flags & 0x10000:  # high-resolution holes: 8 rows of 8 bits at 0x14
            mask = struct.unpack_from('<Q', buf, off + 0x14)[0]
        else:
            low = struct.unpack_from('<H', buf, off + 0x3c)[0]
            mask = sum(1 << (y*8+x) for y in range(8) for x in range(8) if low & (1 << ((y//2)*4+x//2)))
        out[ix, iy] = mask
    return out


def mesh(buf, key, coarse=False, step=None):
    col, row = divmod(key, 64)
    vertices, indices = [], []
    masks = holes(buf)
    for ch in adt_chunks(buf):
        if ch.heights is None or not (0 <= ch.ix < 16 and 0 <= ch.iy < 16):
            continue
        base, mask = len(vertices), masks.get((ch.ix, ch.iy), 0)
        if coarse or step:
            stride = step or 8
            for y in range(0, 8, stride):
                for x in range(0, 8, stride):
                    if any(mask & (1 << (qy*8+qx)) for qy in range(y,y+stride) for qx in range(x,x+stride)):
                        continue
                    base = len(vertices)
                    for vx, vy in [(x,y),(x+stride,y),(x+stride,y+stride),(x,y+stride)]:
                        vertices.append((col+(ch.ix+vx/8)/16,row+(ch.iy+vy/8)/16,ch.z+ch.heights[vy*17+vx]))
                    indices.extend(base+i for i in (0,1,2,0,2,3))
        else:
            for y in range(17):
                for x in range(8 if y % 2 else 9):
                    vertices.append((col+(ch.ix+(x+(y%2)/2)/8)/16, row+(ch.iy+y/16)/16,
                                     ch.z+ch.heights[(y//2)*17 + (9 if y%2 else 0)+x]))
            for y in range(8):
                for x in range(8):
                    if mask & (1 << (y*8+x)):
                        continue
                    a = y*17+x
                    # Native MCVT diamond centre: four fans, no diagonal approximation.
                    indices.extend(base+i for i in (a,a+1,a+9,a+1,a+18,a+9,a+18,a+17,a+9,a+17,a,a+9))
    return vertices, indices


def write_mesh(path, vertices, indices):
    with path.open('wb') as f:
        f.write(struct.pack('<4sII', b'MMT1', len(vertices), len(indices)))
        for v in vertices:
            f.write(struct.pack('<3f', *v))
        if indices:
            f.write(struct.pack(f'<{len(indices)}I', *indices))


def compatible(product, version, atlas):
    if product not in ('wowf', 'wow_classic_beta') or not version.startswith('1.60.'):
        raise ValueError('Expected WoW Forever (wowf or wow_classic_beta) 1.60.x')
    if (product, version) != (atlas.Data.Tiles.product, atlas.Data.Tiles.version):
        raise ValueError(f'Source must match Atlas: {atlas.Data.Tiles.product} {atlas.Data.Tiles.version}')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    add_source_args(ap)
    ap.add_argument('--force',action='store_true',help='Rebuild even matching complete exports')
    ap.add_argument('--jobs', type=int, default=6, help='parallel source reads (1–12)')
    ap.add_argument('--inst', action='append', type=int)
    ap.add_argument('--all', action='store_true')
    ap.add_argument('--version', help='Pinned wago build (required in wago mode)')
    ap.add_argument('-o', '--out', default=str(ROOT/'demo'/'terrain'))
    ap.add_argument('--tiles',type=Path,default=ROOT/'demo'/'tiles',help='Matching map imagery for whole-map previews')
    ns = ap.parse_args()
    if ns.mode == 'wago':
        if not ns.version or len(ns.args) != 1:
            ap.error('wago needs PRODUCT and --version')
        src = PinnedWagoSource(ns.args[0], version=ns.version, cache_dir=str(ROOT/'.cache-assets'))
    else:
        src = source_from_args(ap, ns)
    _, atlas = load_atlas()
    compatible(src.product, src.version, atlas)
    data = src.read(MAP_DB2)
    if data is None:
        ap.error('Map.db2 unavailable')
    for m in read_maps(data):
        if m.kind or (not ns.all and m.inst not in (ns.inst or [0])):
            continue
        wdt = src.read(m.wdt)
        if wdt is None:
            continue
        out = Path(ns.out)/str(m.inst)
        out.mkdir(parents=True, exist_ok=True)
        rows = []
        previous = {}
        if not ns.force and (out/'manifest.json').is_file():
            old = json.loads((out/'manifest.json').read_text())
            if (old.get('product'),old.get('version'),old.get('format')) == (src.product,src.version,'magicmap-terrain-v1'):
                previous = {t['key']:t for t in old['tiles'] if all(lod in t['lods'] and (out/t['lods'][lod]).is_file() for lod in ('coarse','detail','native'))}
        adts = {k:v.root_adt for k,v in wdt_maid(wdt).items() if v.root_adt}
        src.prefetch(adts.values())
        def read(pair):
            key, fdid = pair
            return key, None if key in previous else src.read(fdid)
        pool = ThreadPoolExecutor(max_workers=max(1, min(12, ns.jobs)))
        for key, buf in pool.map(read, sorted(adts.items())):
            if key in previous:
                rows.append(previous[key])
                continue
            if buf is None:
                continue
            native, triangles = mesh(buf, key)
            if not native or not triangles:
                continue
            coarse, faces = mesh(buf,key,True)
            detail, detail_faces = mesh(buf,key,step=2)
            write_mesh(out/f'{key}-detail.mmt', detail, detail_faces)
            write_mesh(out/f'{key}.mmt', native, triangles)
            write_mesh(out/f'{key}-coarse.mmt', coarse, faces)
            rows.append({'key':key,'min':min(v[2] for v in native),'max':max(v[2] for v in native),
                         'lods':{'coarse':f'{key}-coarse.mmt','detail':f'{key}-detail.mmt','native':f'{key}.mmt'}})
            if len(rows) % 32 == 0:
                print(f'{m.name}: {len(rows)}/{len(adts)}', flush=True)
        pool.shutdown()
        result = {'format':'magicmap-terrain-v1','product':src.product,'version':src.version,'inst':m.inst,
                  'groundOnly':True,'tiles':rows,'expectedTiles':len(adts)}
        preview = build_preview(out,ns.tiles/str(m.inst),result)
        if preview:
            result['preview'] = preview
        tmp = out/'manifest.json.tmp'
        tmp.write_text(json.dumps(result, separators=(',', ':'))+'\n')
        tmp.replace(out/'manifest.json')
        print(f'{m.name}: {len(rows)}/{len(adts)} terrain tiles -> {out}')


if __name__ == '__main__':
    main()
