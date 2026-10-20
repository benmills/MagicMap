from common import *
from PIL import Image, ImageEnhance, ImageFilter
import io, sys
S = 2.0  # output px per yard
TILE = 533.3333
m = find_if(); info, groups, _, _ = wmo_root(read(7801267))
rows = pickle.load(open('if_rows.pkl', 'rb'))
pad = 80
X0, Z0 = m['mn'][0] - pad, m['mn'][2] - pad
X1, Z1 = m['mx'][0] + pad, m['mx'][2] + pad
W, H = int((X1 - X0) * S), int((Z1 - Z0) * S)
def terrain():
    wdt = wdt_maid(read(775971))
    out = Image.new('RGBA', (W, H), (0, 0, 0, 255))
    for col in range(int(X0 // TILE), int(X1 // TILE) + 1):
        for row in range(int(Z0 // TILE), int(Z1 // TILE) + 1):
            t = wdt.get(col * 64 + row)
            if not t or not t.minimap: continue
            im = Image.open(io.BytesIO(read(t.minimap))).convert('RGBA')
            px = int(TILE * S) + 1
            im = im.resize((px, px), Image.BILINEAR)
            out.alpha_composite(im, (int((col * TILE - X0) * S), int((row * TILE - Z0) * S))) if (col*TILE-X0)>=0 and (row*TILE-Z0)>=0 else out.paste(im, (int((col * TILE - X0) * S), int((row * TILE - Z0) * S)), im)
    return out
def pictures(filter_fn=lambda g: True, flipy=False):
    layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    items = []
    for r in rows:
        g = groups[r[1]]
        if not filter_fn(g): continue
        items.append((g['mn'][2], r, g))
    for _, r, g in sorted(items, key=lambda e: e[0]):
        pic = Image.open(io.BytesIO(read(r[4]))).convert('RGBA')
        pw, ph = pic.size
        bx, by = r[2], r[3] - 256
        x0, y0 = g['mn'][0] + 128 * bx, g['mn'][1] + 128 * by
        # picture pixel -> local: x = x0 + px/2 ; y = y0 + (ph - py)/2 (or flipped)
        def loc(px, py):
            return (x0 + px / 2, y0 + (py / 2 if flipy else (ph - py) / 2))
        def out(px, py):
            lx, ly = loc(px, py)
            fx, _, fz = place(m, lx, ly, 0)
            return ((fx - X0) * S, (fz - Z0) * S)
        o00, o10, o01 = out(0, 0), out(pw, 0), out(0, ph)
        # forward affine: o = o00 + (o10-o00)*px/pw + (o01-o00)*py/ph ; invert for PIL
        a, b = (o10[0] - o00[0]) / pw, (o01[0] - o00[0]) / ph
        c, d = (o10[1] - o00[1]) / pw, (o01[1] - o00[1]) / ph
        det = a * d - b * c
        ia, ib, ic, id_ = d / det, -b / det, -c / det, a / det
        corners = [o00, o10, o01, out(pw, ph)]
        minx, miny = int(min(p[0] for p in corners)), int(min(p[1] for p in corners))
        maxx, maxy = int(max(p[0] for p in corners)) + 1, int(max(p[1] for p in corners)) + 1
        bw, bh = maxx - minx, maxy - miny
        tx, ty = minx - o00[0], miny - o00[1]
        data = (ia, ib, ia * tx + ib * ty, ic, id_, ic * tx + id_ * ty)
        warped = pic.transform((bw, bh), Image.AFFINE, data, resample=Image.BILINEAR)
        layer.alpha_composite(warped, (max(0, minx), max(0, miny))) if minx >= 0 and miny >= 0 else None
    return layer
if __name__ == '__main__':
    terr = terrain()
    terr.convert('RGB').save('0-terrain.png')
    pics = pictures()
    Image.alpha_composite(Image.new('RGBA', (W, H), (0, 0, 0, 255)), pics).convert('RGB').save('1-pictures-on-black.png')
    dim = ImageEnhance.Brightness(terr).enhance(0.35)
    Image.alpha_composite(dim, pics).convert('RGB').save('2-over-dim-terrain.png')
    Image.alpha_composite(terr, pics).convert('RGB').save('3-over-terrain.png')
    print(W, H)
