from common import *
from mmtools.db2 import read_wdc5
import collections
rows = read_wdc5(read(1323241), relation=True)
by_wmo = collections.defaultdict(list)
for r in rows: by_wmo[r[-1]].append(r)
for name, wdt_id in (('Eastern Kingdoms', 775971), ('Kalimdor', 782779)):
    wdt = wdt_maid(read(wdt_id))
    place_ = {}
    for k, t in wdt.items():
        if not t.obj0: continue
        b = read(t.obj0)
        if not b: continue
        for m in modf(b): place_[m['uid']] = m
    fids = collections.Counter(m['fid'] for m in place_.values())
    pics = 0; with_pics = 0; textures = set(); per = []
    for fid, n in fids.items():
        b = read(fid)
        if not b: continue
        try: info, groups, _, _ = wmo_root(b)
        except Exception as e: continue
        rs = by_wmo.get(info['wmoID'], [])
        if rs:
            with_pics += n; pics += n * len(rs); textures.update(r[4] for r in rs)
            per.append((len(rs), n, fid, info['wmoID']))
    per.sort(reverse=True)
    print(name, 'placements', len(place_), 'distinct wmo', len(fids), 'placements with pictures', with_pics, 'pictures placed', pics, 'distinct textures', len(textures))
    print('  biggest', per[:8])
    print('  placements by picture count', collections.Counter(min(p[0], 10) for p in per for _ in range(p[1])))
