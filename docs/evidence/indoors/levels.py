from render import *
from PIL import ImageChops
def n(im): return im.histogram()[255] if im.mode == 'L' else im.convert('L').histogram()[255]
masks = {}
for gi in sorted(set(r[1] for r in rows)):
    a = pictures(lambda g, gi=gi: g['i'] == gi).getchannel('A').point(lambda v: 255 if v > 0 else 0)
    if a.getbbox(): masks[gi] = a
cover = Image.new('L', (W, H), 0); two = Image.new('L', (W, H), 0); stack = Image.new('L', (W, H), 0)
pairs = {}
gs = list(masks)
for i, a in enumerate(gs):
    two = ImageChops.lighter(two, ImageChops.darker(cover, masks[a]))
    cover = ImageChops.lighter(cover, masks[a])
    for b in gs[i + 1:]:
        ov = ImageChops.darker(masks[a], masks[b])
        k = n(ov)
        if not k: continue
        A, B = groups[a], groups[b]
        sep = max(A['mn'][2], B['mn'][2]) - min(A['mx'][2], B['mx'][2])
        pairs[(a, b)] = (k, round(sep), [round(A['mn'][2]), round(A['mx'][2])], [round(B['mn'][2]), round(B['mx'][2])])
        if sep > -2: stack = ImageChops.lighter(stack, ov)
c = n(cover)
print('rooms with pictures', len(masks), 'covered px', c)
print('2+ rooms overlap: %.1f%%' % (100 * n(two) / c))
print('one room wholly above another: %.1f%%' % (100 * n(stack) / c))
for k, v in sorted(pairs.items(), key=lambda e: -e[1][0])[:12]:
    print(k, v)
vis = Image.merge('RGB', (cover.point(lambda v: v * 0.35), cover.point(lambda v: v * 0.35), cover.point(lambda v: v * 0.35)))
vis.paste((230, 160, 40), mask=two); vis.paste((230, 40, 40), mask=stack)
vis.resize((800, 800)).save('4-overlap.png')
