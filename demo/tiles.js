// Tiles and the sea under them: which copy to draw, baked once, within a pixel budget.
// Shares the page's globals (cam, ctx, dpr, toScreen, ...): classic scripts, one scope.

// Tiles: the smallest copy that's still sharp at this zoom (64, 128, 256, or the 512 original),
// baked once (tint, water), kept within a pixel budget so a phone's canvas memory holds.
const SIZES = [64, 128, 256, 512], BUDGET = 40e6, MAX_LOADING = 12;
const baked = new Map(); // "key@size" -> canvas, oldest use first
let bakedPx = 0, loading = 0, frameNo = 0;
const used = new Map(); // "key@size" -> frameNo last drawn
const want = () => SIZES.find((s) => s >= cam.zoom * dpr) || 512;
const url = (key, size) => size === 512 ? `tiles/${INST}/${key}.webp` : `tiles/${INST}/${size}/${key}.webp`;

function bake(t, img, mask) {
  const c = document.createElement("canvas");
  c.width = c.height = img.width;
  const g = c.getContext("2d");
  g.drawImage(img, 0, 0);
  if (t.tint) { // texel * m + a
    g.globalCompositeOperation = "multiply"; g.fillStyle = rgb(t.tint.slice(0, 3)); g.fillRect(0, 0, c.width, c.height);
    g.globalCompositeOperation = "lighter"; g.fillStyle = rgb(t.tint.slice(3)); g.fillRect(0, 0, c.width, c.height);
  }
  if (mask) { // the backdrop colour where the mask says so
    const m = document.createElement("canvas");
    m.width = m.height = c.width;
    const mg = m.getContext("2d");
    mg.drawImage(mask, 0, 0, m.width, m.height);
    mg.globalCompositeOperation = "source-in"; mg.fillStyle = bg; mg.fillRect(0, 0, m.width, m.height);
    g.globalCompositeOperation = "source-over"; g.drawImage(m, 0, 0);
    m.width = m.height = 0;
  }
  return c;
}

function load(t, size) {
  const id = `${t.key}@${size}`;
  baked.set(id, null); loading++;
  const img = new Image(), mask = t.water ? new Image() : null;
  let n = mask ? 2 : 1;
  const done = () => {
    if (--n) return;
    loading--;
    if (!img.naturalWidth) { baked.set(id, false); return draw(); } // missing: don't ask again
    const c = bake(t, img, mask);
    baked.set(id, c); bakedPx += c.width * c.height;
    img.src = ""; if (mask) mask.src = "";
    evict(); draw();
  };
  img.onload = img.onerror = done; img.src = url(t.key, size);
  if (mask) { mask.onload = mask.onerror = done; mask.src = `tiles/${INST}/water_${t.key}.png`; }
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
  if (c === undefined && loading < MAX_LOADING) load(t, size);
  for (const s of [...SIZES].reverse()) {
    const other = baked.get(`${t.key}@${s}`);
    if (other) { used.set(`${t.key}@${s}`, frameNo); return other; }
  }
}

// The land, centre first, so a slow connection fills in from where you're looking.
function drawTiles() {
  ctx.fillStyle = bg; ctx.fillRect(0, 0, W, H);
  const [c0, r0] = toTile(0, 0), [c1, r1] = toTile(W, H), size = want();
  const vis = tiles.filter((t) => !t.sea && t.col + 1 >= c0 && t.col <= c1 && t.row + 1 >= r0 && t.row <= r1);
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
  const t = await get(`/api/tiles?inst=${INST}`);
  tiles = t.tiles.map((x) => ({ ...x, col: Math.floor(x.key / 64), row: x.key % 64 }));
}
