import sys, struct, pickle, os
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../tools'))
from mmtools.sources import open_source
from mmtools.formats import iter_chunks, wdt_maid
_src = None
CACHE = os.path.join(os.path.dirname(__file__), 'cache')
os.makedirs(CACHE, exist_ok=True)
def read(fdid):
    global _src
    p = os.path.join(CACHE, str(fdid))
    if os.path.exists(p): return open(p, 'rb').read()
    if _src is None: _src = open_source('local', 'wow_classic_beta', install='/Applications/World of Warcraft')
    b = _src.read(fdid)
    if b is not None: open(p, 'wb').write(b)
    return b
def modf(buf):
    out = []
    for magic, off, size in iter_chunks(buf):
        if magic == b'MODF':  # reversed magic
            for i in range(size // 64):
                v = struct.unpack_from('<II3f3f3f3fHHHH', buf, off + i * 64)
                out.append(dict(fid=v[0], uid=v[1], pos=v[2:5], rot=v[5:8], mn=v[8:11], mx=v[11:14], flags=v[14], scale=v[17]))
    return out
def wmo_root(buf):
    ch = {m: (o, s) for m, o, s in iter_chunks(buf)}
    o, s = ch[b'MOHD']
    h = struct.unpack_from('<8II6fHH', buf, o)
    info = dict(nGroups=h[1], wmoID=h[8], bbox=h[9:15], flags=h[15])
    names = b''
    if b'MOGN' in ch:
        o2, s2 = ch[b'MOGN']; names = buf[o2:o2 + s2]
    def name(off):
        if off < 0 or off >= len(names): return ''
        return names[off:names.index(b'\0', off)].decode('latin1')
    groups = []
    o, s = ch[b'MOGI']
    for i in range(s // 32):
        f, *bb, no = struct.unpack_from('<I6fi', buf, o + i * 32)
        groups.append(dict(i=i, flags=f, mn=bb[:3], mx=bb[3:], name=name(no)))
    gfids = []
    if b'GFID' in ch:
        o, s = ch[b'GFID']; gfids = list(struct.unpack_from(f'<{s//4}I', buf, o))
    return info, groups, gfids, [m for m in ch]
import math
def place(m, lx, ly, lz, rot_off=-90.0, sx=1, sy=-1):
    """WMO-local point -> file space (x, y, z), y up. Noggit's: T(pos) Ry(rot.y + rot_off), local (x, z, -y)."""
    t = math.radians(m['rot'][1] + rot_off)
    vx, vy, vz = sx * lx, lz, sy * ly
    s = m['scale'] / 1024
    x = m['pos'][0] + s * (vx * math.cos(t) + vz * math.sin(t))
    z = m['pos'][2] + s * (-vx * math.sin(t) + vz * math.cos(t))
    return x, m['pos'][1] + s * vy, z
def find_if():
    wdt = wdt_maid(read(775971))
    for m in modf(read(wdt[33 * 64 + 40].obj0)):
        if m['fid'] == 7801267: return m
