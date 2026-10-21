from common import *
from mmtools.db2 import read_wdc5
root = read(7801267)
info, groups, gfids, _ = wmo_root(root)
ch = {mm: (o, s) for mm, o, s in iter_chunks(root)}
print('gfid', len(gfids), 'groups', len(groups))
# GFID: per group, possibly several LOD files; take the first nGroups
gid = {}
for i in range(len(groups)):
    b = read(gfids[i])
    if not b: continue
    for mm, o, s in iter_chunks(b):
        if mm == b'MOGP':
            flags = struct.unpack_from('<I', b, o + 8)[0]
            ps, pc = struct.unpack_from('<HH', b, o + 36)
            uid = struct.unpack_from('<I', b, o + 56)[0]
            gid[uid] = i
            groups[i]['portals'] = (ps, pc); groups[i]['gflags'] = flags
            break
area = {}
for r in read_wdc5(read(1355528), string_fields=(0,)):
    if r[3] == 20884 and r[5] in gid: area[gid[r[5]]] = r[1] or ''
o, s = ch[b'MOPV']; V = [struct.unpack_from('<3f', root, o + 12 * k) for k in range(s // 12)]
o, s = ch[b'MOPT']; PT = [struct.unpack_from('<HH4f', root, o + 20 * k) for k in range(s // 20)]
o, s = ch[b'MOPR']; PR = [struct.unpack_from('<HHhH', root, o + 8 * k) for k in range(s // 8)]
links = collections.defaultdict(set) if False else {}
import collections
by_portal = collections.defaultdict(list)
for pi, g, side, _ in PR: by_portal[pi].append(g)
print('rooms with area names', len(area), 'portals', len(PT), 'refs', len(PR))
for i in (65, 88, 90, 96, 101, 103, 64, 79):
    ps, pc = groups[i].get('portals', (0, 0))
    others = sorted({g for pi, g, side, _ in PR[ps:ps + pc]})
    print(i, repr(area.get(i)), 'z %.0f..%.0f' % (groups[i]['mn'][2], groups[i]['mx'][2]), 'portals to', others)
pickle.dump(dict(area=area, V=V, PT=PT, PR=PR, portals={i: g.get('portals') for i, g in enumerate(groups)}), open('meta.pkl', 'wb'))
names = collections.Counter(area.values()); print(names)
