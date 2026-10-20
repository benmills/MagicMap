// Tiles and the sea around them: which copy to draw, baked once, within a pixel budget.
// Shares the page's globals (cam, ctx, dpr, toScreen, ...): classic scripts, one scope.

// The sea (Atlas.Sea / Data/Sea.lua, made by tools/gen_sea.py). The tiles' art is drawn as it is, its
// own water included; the sea continues it where there is no art: off the tiles, and over the art's
// open-sea tiles (TileColor sea[]: flat, not drawn). The addon draws it with plain textures, and this
// draws the same:
//   1. per sea cell in view: a tiling water texture (grey, mean `gain`), variant Atlas.SeaVariant(col,
//      row): any variant fits beside any other (they share their edges). World-anchored, one repeat per
//      tile (SetTexCoord the whole texture). Here: one pattern fill per variant, the cells as one path.
//   2. over them, one texture filling the view: variant 0, SetTexture(path, "REPEAT", "REPEAT") with
//      SetTexCoord scaled by the zoom to a repeat every `macro` tiles, turned a quarter, at alpha
//      `macroAlpha`: the repeat stops lining up with the cells.
//   3. the tint map (the sea's colour / gain, 4 px a tile: the art's water along each coast, spreading
//      out to the art's open-sea colour, a little darker and gently varied far out) with
//      SetBlendMode("MOD") over the view; past its rect, its border colour `far` (CLAMP).
//   4. the tiles' art; on a coast tile AddMaskTexture(feather_<code>.tga): its sides facing the sea
//      fade out over `feather` of a tile into the sea under it. The masks are baked by gen_sea.py
//      (FEATHER); here they're made from SEA_STYLE.feather, for tuning.
// A map without a sea: the art on its backdrop colour.
const SEA_STYLE = {
  detail: 1,        // 0..1: the water texture's contrast (1: as sampled from the art's seabed)
  macro: 2.7,       // tiles per repeat of the second layer
  macroAlpha: 0.35,
  variants: true,   // false: variant 0 in every cell (to see the repetition the variants hide)
  // Colour-matched tiles (the addon's gear option, off by default): the tile's tint, the coast fade
  // and the sea's tint map. Off: the art plain, the sea its own water texture (no colour data).
  tint: false,
  feather: 0.15,    // tiles: the coast's fade; gen_sea.py FEATHER = 0.15
};

// Tiles: the smallest copy that's still sharp at this zoom (64, 128, 256, or the 512 original),
// baked once (tint, coast fade), kept within a pixel budget so a phone's canvas memory holds.
const SIZES = [64, 128, 256, 512], BUDGET = 40e6, MAX_LOADING = 12;
const baked = new Map(); // "key@size" -> canvas, oldest use first
let bakedPx = 0, loading = 0, frameNo = 0;
// The sea of INST, or null: { rect, far, gain, variants, coast: Map key -> code, tint: img,
// ocean: [variant][lod] -> img }
let sea = null;
const OCEAN_SIZES = [32, 64, 128, 256], CELLS_MIN_PX = 48; // device px a tile: below, one fill
const used = new Map(); // "key@size" -> frameNo last drawn
const want = () => SIZES.find((s) => s >= cam.zoom * dpr) || 512;
const url = (key, size) => size === 512 ? `tiles/${INST}/${key}.webp` : `tiles/${INST}/${size}/${key}.webp`;
const smoothstep = (e0, e1, x) => { const t = Math.min(1, Math.max(0, (x - e0) / (e1 - e0))); return t * t * (3 - 2 * t); };

// A coast tile's fade (gen_sea.py feather_mask): alpha 0 at each side the code names (bits 1 l, 2 r,
// 4 t, 8 b), 1 within `feather`; a corner bit (16 tl, 32 tr, 64 bl, 128 br) cuts that corner round.
const masks = new Map(); // code -> 64px canvas
function featherMask(code) {
  const id = `${code}/${SEA_STYLE.feather}`;
  if (masks.has(id)) return masks.get(id);
  const n = 64, c = h("canvas", { width: n, height: n }), g = c.getContext("2d"), img = g.createImageData(n, n), f = SEA_STYLE.feather;
  for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) {
    const u = (x + 0.5) / n, v = (y + 0.5) / n;
    const l = smoothstep(0, f, u), r = smoothstep(0, f, 1 - u), t = smoothstep(0, f, v), b = smoothstep(0, f, 1 - v);
    let a = 1;
    if (code & 1) a *= l; if (code & 2) a *= r; if (code & 4) a *= t; if (code & 8) a *= b;
    if (code & 16) a *= Math.max(t, l); if (code & 32) a *= Math.max(t, r);
    if (code & 64) a *= Math.max(b, l); if (code & 128) a *= Math.max(b, r);
    const i = (y * n + x) * 4;
    img.data[i] = img.data[i + 1] = img.data[i + 2] = 255; img.data[i + 3] = Math.round(255 * a);
  }
  g.putImageData(img, 0, 0);
  masks.set(id, c);
  return c;
}

// The tile's art (tinted: texel * m + a), and with the sea its coast fade.
function bake(t, img) {
  const n = img.width, c = h("canvas", { width: n, height: n }), g = c.getContext("2d");
  g.drawImage(img, 0, 0);
  if (SEA_STYLE.tint && t.tint) {
    g.globalCompositeOperation = "multiply"; g.fillStyle = rgb(t.tint.slice(0, 3)); g.fillRect(0, 0, n, n);
    g.globalCompositeOperation = "lighter"; g.fillStyle = rgb(t.tint.slice(3)); g.fillRect(0, 0, n, n);
  }
  const code = SEA_STYLE.tint && sea && sea.coast.get(t.key);
  if (code) {
    g.globalCompositeOperation = "destination-in"; g.imageSmoothingQuality = "high";
    g.drawImage(featherMask(code), 0, 0, n, n);
  }
  return c;
}

function load(t, size, id) {
  baked.set(id, null); loading++;
  const img = new Image();
  img.onload = img.onerror = () => {
    img.onload = img.onerror = null; loading--;
    if (!img.naturalWidth) { baked.set(id, false); return draw(); } // missing: don't ask again
    const c = bake(t, img);
    baked.set(id, c); bakedPx += c.width * c.height;
    img.src = "";
    evict(); draw();
  };
  img.src = url(t.key, size);
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
  const id = `${t.key}@${size}`, c = baked.get(id);
  if (c) { baked.delete(id); baked.set(id, c); used.set(id, frameNo); return c; }
  if (c === undefined && loading < MAX_LOADING) load(t, size, id);
  for (const s of [...SIZES].reverse()) {
    const other = baked.get(`${t.key}@${s}`);
    if (other) { used.set(`${t.key}@${s}`, frameNo); return other; }
  }
}

// Atlas.SeaVariant (Lua's % is floored: so is this).
const mod = (a, m) => ((a % m) + m) % m;
function seaVariant(col, row) {
  if (!SEA_STYLE.variants) return 0;
  let h = mod(col * 1619 + row * 31337 + 1013, 65521);
  h = mod(h * h + col * 7, 65521);
  return h % sea.variants;
}

// A variant's pattern at the copy that suits `px` device pixels a repeat, anchored so a repeat is
// `tiles` tiles (turned a quarter if `turn`) from world (0, 0), or `at`.
const patterns = new Map();
function oceanPattern(v, px, tiles, turn, at = [0, 0]) {
  const size = OCEAN_SIZES.find((s) => s >= px) || 256, id = `${v}@${size}`;
  let p = patterns.get(id);
  if (!p) {
    const img = sea.ocean[v][size];
    if (!img.naturalWidth) return null;
    p = ctx.createPattern(img, "repeat"); patterns.set(id, p);
  }
  const k = cam.zoom * tiles / size, [x, y] = toScreen(...at);
  p.setTransform(turn ? new DOMMatrix([0, k, -k, 0, x, y]) : new DOMMatrix([k, 0, 0, k, x, y]));
  return p;
}

// Tile (c, r)'s square on screen, its edges on device pixels so neighbours share them (no seams).
function tileRect(c, r) {
  const [x, y] = toScreen(c, r), sx = snap(x), sy = snap(y);
  return [sx, sy, snap(x + cam.zoom) - sx, snap(y + cam.zoom) - sy];
}

// The sea under the whole view: the cells' textures, the larger layer, the tint.
function drawSea(drawn) {
  const s = SEA_STYLE, g = Math.round(sea.gain * 255);
  ctx.fillStyle = `rgb(${g},${g},${g})`; ctx.fillRect(0, 0, W, H);
  ctx.globalAlpha = s.detail;
  const px = cam.zoom * dpr;
  if (px < CELLS_MIN_PX) { // too small for the variants to matter: one fill
    const p = oceanPattern(0, px, 1, false);
    if (p) { ctx.fillStyle = p; ctx.fillRect(0, 0, W, H); }
  } else {
    const [c0, r0, c1, r1] = view(), paths = [];
    for (let c = Math.floor(c0); c <= Math.floor(c1); c++) for (let r = Math.floor(r0); r <= Math.floor(r1); r++) {
      const key = c * 64 + r;
      if (c >= 0 && c < 64 && r >= 0 && r < 64 && drawn.has(key) && !(s.tint && sea.coast.has(key))) continue; // under art
      (paths[seaVariant(c, r)] ||= new Path2D()).rect(...tileRect(c, r));
    }
    paths.forEach((path, v) => { const p = oceanPattern(v, px, 1, false); if (p) { ctx.fillStyle = p; ctx.fill(path); } });
  }
  const macro = oceanPattern(0, px * s.macro, s.macro, true, [0.37, 0.61]);
  if (macro) { ctx.globalAlpha = s.detail * s.macroAlpha; ctx.fillStyle = macro; ctx.fillRect(0, 0, W, H); }
  ctx.globalAlpha = 1;
  if (!s.tint) return;
  ctx.globalCompositeOperation = "multiply";
  const [c0, r0, c1, r1] = sea.rect, [x0, y0] = toScreen(c0, r0), [x1, y1] = toScreen(c1, r1);
  const outside = new Path2D(); outside.rect(0, 0, W, H); outside.rect(x0, y0, x1 - x0, y1 - y0);
  ctx.fillStyle = rgb(sea.far); ctx.fill(outside, "evenodd");
  if (sea.tint.naturalWidth) { ctx.imageSmoothingEnabled = true; ctx.drawImage(sea.tint, x0, y0, x1 - x0, y1 - y0); }
  ctx.globalCompositeOperation = "source-over";
}

// The sea (or the backdrop), then the land, centre first, so a slow connection fills in from where
// you're looking.
function drawTiles() {
  frameNo++;
  const drawable = sea ? tiles.filter((t) => !t.sea) : tiles;
  if (sea) drawSea(new Set(drawable.map((t) => t.key)));
  else { ctx.fillStyle = bg; ctx.fillRect(0, 0, W, H); }
  const [c0, r0, c1, r1] = view(), size = want();
  const vis = drawable.filter((t) => t.col + 1 >= c0 && t.col <= c1 && t.row + 1 >= r0 && t.row <= r1);
  vis.sort((a, b) => Math.hypot(a.col + .5 - cam.cx, a.row + .5 - cam.cy) - Math.hypot(b.col + .5 - cam.cx, b.row + .5 - cam.cy));
  ctx.imageSmoothingQuality = "high";
  for (const t of vis) {
    const img = tileImage(t, size);
    if (img) ctx.drawImage(img, ...tileRect(t.col, t.row));
  }
}

async function loadTiles() {
  const [t, s] = await Promise.all([get(`/api/tiles?inst=${INST}`), get(`/api/sea?inst=${INST}`)]);
  tiles = t.tiles.map((x) => ({ ...x, col: Math.floor(x.key / 64), row: x.key % 64 }));
  if (!s) return;
  const image = (src) => { const i = new Image(); i.onload = draw; i.src = src; return i; };
  sea = { ...s, coast: new Map(Object.entries(s.coast).map(([k, c]) => [+k, c])),
    tint: image(`tiles/${INST}/ocean_tint.png`),
    ocean: Array.from({ length: s.variants }, (_, v) => Object.fromEntries(OCEAN_SIZES.map((n) =>
      [n, image(n === 256 ? `tiles/${INST}/ocean${v}.webp` : `tiles/${INST}/${n}/ocean${v}.webp`)]))) };
}
