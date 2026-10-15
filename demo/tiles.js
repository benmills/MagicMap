// Tiles and the sea under them: which copy to draw, baked once, within a pixel budget.
// Shares the page's globals (cam, ctx, dpr, toScreen, ...): classic scripts, one scope.

// The sea (Atlas.Sea / Data/Sea.lua, made by tools/gen_sea.py from the terrain's ocean and depth).
// The addon draws it with plain textures, and this draws the same:
//   1. the ocean: a solid texture of `deep` under the map (SetColorTexture).
//   2. per coast tile: its mask (128px: grey = shelf, alpha = land) with SetBlendMode("DISABLE") and
//      vertex colour shallow - deep, then a solid `deep` with SetBlendMode("ADD"):
//      sea = deep + shelf * (shallow - deep), shallow over the shelf, deep further out.
//   3. the tile's art (tinted by vertex colour) with the mask as its MaskTexture (AddMaskTexture):
//      land shows, the art's own water becomes our sea, and the coast fades over FEATHER yards.
//   Open-sea tiles draw no art; other tiles are all land, drawn as they are.
// colours: null = the map's own, sampled from the art's water. shelf and feather are baked into the
// masks by gen_sea.py (SHELF, FEATHER); other values here remap the baked ones (for tuning only:
// the addon would regenerate the masks with them).
const SEA_STYLE = {
  deep: null,       // [r, g, b] 0..1: open water
  shallow: null,    // [r, g, b] 0..1: over the shelf, at the shore
  shelf: 28,        // yards: shelf = exp(-depth / shelf); gen_sea.py SHELF = 28
  feather: 2,       // the coast's softness, Gaussian sigma in mask px (~4 yd); gen_sea.py FEATHER = 2
};
const BAKED_SHELF = 28, BAKED_FEATHER = 2;

// Tiles: the smallest copy that's still sharp at this zoom (64, 128, 256, or the 512 original),
// baked once (tint, sea or water), kept within a pixel budget so a phone's canvas memory holds.
const SIZES = [64, 128, 256, 512], BUDGET = 40e6, MAX_LOADING = 12;
const baked = new Map(); // "key@size" (+ "b" before) -> canvas, oldest use first
let bakedPx = 0, loading = 0, frameNo = 0;
let sea = null; // { deep, shallow, masks: Set, open: Set } for INST, or null: no sea there
const used = new Map(); // "key@size" -> frameNo last drawn
const want = () => SIZES.find((s) => s >= cam.zoom * dpr) || 512;
const url = (key, size) => size === 512 ? `tiles/${INST}/${key}.webp` : `tiles/${INST}/${size}/${key}.webp`;
const withSea = () => !before && sea;
const canvas2d = (w) => { const c = document.createElement("canvas"); c.width = c.height = w; return c; };

// Remaps from the baked shelf and feather to SEA_STYLE's, as 256-entry tables.
// Shelf: exp(-d / a) ** (a / b) = exp(-d / b). Coast: the baked alpha is Phi(distance / BAKED_FEATHER).
const erf = (x) => { // Abramowitz & Stegun 7.1.26
  const t = 1 / (1 + 0.3275911 * Math.abs(x));
  const y = 1 - ((((1.061405429 * t - 1.453152027) * t + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * Math.exp(-x * x);
  return x < 0 ? -y : y;
};
const phi = (x) => 0.5 * (1 + erf(x / Math.SQRT2));
function phiInv(p) { let lo = -8, hi = 8; for (let i = 0; i < 40; i++) { const m = (lo + hi) / 2; if (phi(m) < p) lo = m; else hi = m; } return lo; }
let luts = null;
function seaLuts() {
  const key = `${SEA_STYLE.shelf}/${SEA_STYLE.feather}`;
  if (luts && luts.key === key) return luts;
  const shelf = new Float32Array(256), land = new Uint8ClampedArray(256), k = BAKED_FEATHER / SEA_STYLE.feather;
  for (let i = 0; i < 256; i++) {
    shelf[i] = (i / 255) ** (BAKED_SHELF / SEA_STYLE.shelf);
    land[i] = i === 0 || i === 255 ? i : 255 * phi(phiInv(i / 255) * k);
  }
  return (luts = { key, shelf, land });
}

// A coast tile's sea mask (red = shelf, green = land; see export_tiles.py) as two mask-sized canvases:
// the sea's colour, and the land as alpha.
function seaLayers(mask) {
  const n = mask.width, color = canvas2d(n), land = canvas2d(n);
  const cg = color.getContext("2d", { willReadFrequently: true });
  cg.drawImage(mask, 0, 0);
  const px = cg.getImageData(0, 0, n, n), d = px.data, al = new ImageData(n, n), a = al.data;
  const { shelf, land: lut } = seaLuts(), deep = sea.deep, sh = sea.shallow;
  for (let i = 0; i < d.length; i += 4) {
    const s = shelf[d[i]];
    a[i] = a[i + 1] = a[i + 2] = 255; a[i + 3] = lut[d[i + 1]];
    for (let k = 0; k < 3; k++) d[i + k] = 255 * (deep[k] + s * (sh[k] - deep[k]));
  }
  cg.putImageData(px, 0, 0);
  land.getContext("2d").putImageData(al, 0, 0);
  return [color, land];
}

// The tile's art (tinted), then before: the backdrop over its water (Textures/Water); with the sea:
// the art through the land on the sea's colour.
function bake(t, img, mask, seaMask) {
  const n = img.width, c = canvas2d(n), g = c.getContext("2d");
  g.drawImage(img, 0, 0);
  if (t.tint) { // texel * m + a
    g.globalCompositeOperation = "multiply"; g.fillStyle = rgb(t.tint.slice(0, 3)); g.fillRect(0, 0, n, n);
    g.globalCompositeOperation = "lighter"; g.fillStyle = rgb(t.tint.slice(3)); g.fillRect(0, 0, n, n);
  }
  if (mask) { // the backdrop colour where the mask says so
    const m = canvas2d(n), mg = m.getContext("2d");
    mg.drawImage(mask, 0, 0, n, n);
    mg.globalCompositeOperation = "source-in"; mg.fillStyle = bg; mg.fillRect(0, 0, n, n);
    g.globalCompositeOperation = "source-over"; g.drawImage(m, 0, 0);
    m.width = m.height = 0;
  }
  if (!seaMask) return c;
  const [color, land] = seaLayers(seaMask), out = canvas2d(n), og = out.getContext("2d");
  og.imageSmoothingQuality = g.imageSmoothingQuality = "high";
  og.drawImage(color, 0, 0, n, n);
  g.globalCompositeOperation = "destination-in"; g.drawImage(land, 0, 0, n, n);
  og.drawImage(c, 0, 0);
  for (const x of [c, color, land]) x.width = x.height = 0;
  return out;
}

function load(t, size, id) {
  baked.set(id, null); loading++;
  const img = new Image(), seaMask = withSea() && sea.masks.has(t.key) ? new Image() : null;
  const mask = !withSea() && t.water ? new Image() : null;
  let n = 1 + !!mask + !!seaMask;
  const done = () => {
    if (--n) return;
    loading--;
    if (!img.naturalWidth) { baked.set(id, false); return draw(); } // missing: don't ask again
    const c = bake(t, img, mask, seaMask);
    baked.set(id, c); bakedPx += c.width * c.height;
    for (const x of [img, mask, seaMask]) if (x) x.src = "";
    evict(); draw();
  };
  img.onload = img.onerror = done; img.src = url(t.key, size);
  if (mask) { mask.onload = mask.onerror = done; mask.src = `tiles/${INST}/water_${t.key}.png`; }
  if (seaMask) { seaMask.onload = seaMask.onerror = done; seaMask.src = `tiles/${INST}/sea_${t.key}.webp`; }
}

function evict() {
  for (const [id, c] of baked) {
    if (bakedPx <= BUDGET) break;
    if (!c || used.get(id) === frameNo) continue;
    baked.delete(id); used.delete(id);
    bakedPx -= c.width * c.height; c.width = c.height = 0; // frees it now on iOS
  }
}

// The wanted copy if baked, else any other of the tile's (sharper first) while it loads.
function tileImage(t, size) {
  const mode = withSea() ? "" : "b", id = `${t.key}@${size}${mode}`, c = baked.get(id);
  if (c) { baked.delete(id); baked.set(id, c); used.set(id, frameNo); return c; }
  if (c === undefined && loading < MAX_LOADING) load(t, size, id);
  for (const s of [...SIZES].reverse()) {
    const other = baked.get(`${t.key}@${s}${mode}`);
    if (other) { used.set(`${t.key}@${s}${mode}`, frameNo); return other; }
  }
}

// The sea (or before: the backdrop), then the land, centre first, so a slow connection fills in from
// where you're looking.
function drawTiles() {
  ctx.fillStyle = withSea() ? rgb(sea.deep) : bg; ctx.fillRect(0, 0, W, H);
  const [c0, r0] = toTile(0, 0), [c1, r1] = toTile(W, H), size = want();
  const open = (t) => withSea() ? sea.open.has(t.key) : t.sea;
  const vis = tiles.filter((t) => !open(t) && t.col + 1 >= c0 && t.col <= c1 && t.row + 1 >= r0 && t.row <= r1);
  vis.sort((a, b) => Math.hypot(a.col + .5 - cam.cx, a.row + .5 - cam.cy) - Math.hypot(b.col + .5 - cam.cx, b.row + .5 - cam.cy));
  ctx.imageSmoothingQuality = "high";
  for (const t of vis) {
    const img = tileImage(t, size);
    if (!img) continue;
    const [x, y] = toScreen(t.col, t.row);
    // Snap edges to device pixels so neighbours share them (no hairline seams).
    const sx = Math.round(x * dpr) / dpr, sy = Math.round(y * dpr) / dpr;
    const ex = Math.round((x + cam.zoom) * dpr) / dpr, ey = Math.round((y + cam.zoom) * dpr) / dpr;
    ctx.drawImage(img, sx, sy, ex - sx, ey - sy);
  }
}

async function loadTiles() {
  const [t, s] = await Promise.all([get(`/api/tiles?inst=${INST}`), get(`/api/sea?inst=${INST}`)]);
  tiles = t.tiles.map((x) => ({ ...x, col: Math.floor(x.key / 64), row: x.key % 64 }));
  sea = s && { deep: SEA_STYLE.deep || s.deep, shallow: SEA_STYLE.shallow || s.shallow,
    masks: new Set(s.masks), open: new Set(s.open) };
}
