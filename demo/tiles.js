// Tiles: which copy to draw, kept within a pixel budget. As the addon draws them: Blizzard's art as it
// is, on the map's backdrop colour (its own dark water: Data/Tiles.lua's bg); open-sea tiles (one flat
// colour, the backdrop's) aren't drawn.
// Shares the page's globals (cam, ctx, dpr, toScreen, ...): classic scripts, one scope.

// Tiles: the smallest copy that's still sharp at this zoom (64, 128, 256, or the 512 original), kept
// within a pixel budget so a phone's canvas memory holds.
const SIZES = [64, 128, 256, 512], BUDGET = 40e6, MAX_LOADING = 12;
const baked = new Map(); // "key@size" -> canvas, oldest use first
let bakedPx = 0, loading = 0, frameNo = 0;
const used = new Map(); // "key@size" -> frameNo last drawn
const want = () => SIZES.find((s) => s >= cam.zoom * dpr) || 512;
const url = (key, size) => size === 512 ? `tiles/${INST}/${key}.webp` : `tiles/${INST}/${size}/${key}.webp`;

// The tile's art on a canvas of its own (one we can size and free).
function bake(img) {
  const n = img.width, c = h("canvas", { width: n, height: n });
  c.getContext("2d").drawImage(img, 0, 0);
  return c;
}

function load(t, size, id) {
  baked.set(id, null); loading++;
  const img = new Image();
  img.onload = img.onerror = () => {
    img.onload = img.onerror = null; loading--;
    if (!img.naturalWidth) { baked.set(id, false); return draw(); } // missing: don't ask again
    const c = bake(img);
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

// Tile (c, r)'s square on screen, its edges on device pixels so neighbours share them (no seams).
function tileRect(c, r) {
  const [x, y] = toScreen(c, r), sx = snap(x), sy = snap(y);
  return [sx, sy, snap(x + cam.zoom) - sx, snap(y + cam.zoom) - sy];
}

// The backdrop, then the land, centre first, so a slow connection fills in from where you're looking.
function drawTiles() {
  frameNo++;
  const drawable = tiles.filter((t) => !t.sea);
  ctx.fillStyle = bg; ctx.fillRect(0, 0, W, H);
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
  const t = await get(`/api/tiles?inst=${INST}`);
  tiles = t.tiles.map((x) => ({ ...x, col: Math.floor(x.key / 64), row: x.key % 64 }));
}
