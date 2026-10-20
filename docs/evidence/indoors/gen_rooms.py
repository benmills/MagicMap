# Per room: its floor as a 4-yd grid in the building's own coordinates, from its pictures' alpha
# (pictures are axis-aligned there, 2 px a yard, from the room box's min corner).
from render import *
import collections
CELL = 4
by = collections.defaultdict(list)
for r in rows: by[r[1]].append(r)
out = ['local _, ns = ...',
       '-- The building: file-space position (x, z) and yaw (radians), as place() in the mockup.',
       'ns.wmo = { x = %.3f, z = %.3f, t = %.6f }' % (m['pos'][0], m['pos'][2], math.radians(m['rot'][1] - 90)),
       '-- [room] = { zmin, zmax, x0, y0, cols, rows, mask }: mask a string, one char a 4-yd cell, row by row',
       '-- from y0 upward, "1" where the room has floor.', 'ns.rooms = {']
for gi, rs in sorted(by.items()):
    g = groups[gi]
    x0, y0 = g['mn'][0], g['mn'][1]
    cols = int(math.ceil((g['mx'][0] - x0) / CELL)); nrows = int(math.ceil((g['mx'][1] - y0) / CELL))
    grid = [[0] * cols for _ in range(nrows)]
    for r in rs:
        pic = Image.open(io.BytesIO(read(r[4]))).convert('RGBA'); pw, ph = pic.size
        a = pic.getchannel('A'); px = a.load()
        bx, byy = r[2], r[3] - 256
        for py in range(ph):
            for qx in range(pw):
                if px[qx, py] > 0:
                    lx = 128 * bx + qx / 2; ly = 128 * byy + (ph - 1 - py) / 2
                    c, rr = int(lx // CELL), int(ly // CELL)
                    if 0 <= c < cols and 0 <= rr < nrows: grid[rr][c] = 1
    mask = ''.join('1' if v else '0' for row_ in grid for v in row_)
    out.append('  [%d] = { %.1f, %.1f, %.2f, %.2f, %d, %d, "%s" },' % (gi, g['mn'][2], g['mx'][2], x0, y0, cols, nrows, mask))
out.append('}')
open('addon/MagicMapIndoorTest/Rooms.lua', 'w').write('\n'.join(out) + '\n')
print(len(by), 'rooms', sum(len(l) for l in out) // 1024, 'KB')
