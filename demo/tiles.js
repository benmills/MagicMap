// Tiles: which copy to draw, kept within a pixel budget. As the addon draws them: Blizzard's art as it
// is, on the map's backdrop colour (its own dark water: Data/Tiles.lua's bg); open-sea tiles (one flat
// colour, the backdrop's) aren't drawn.
// Shares the page's globals (state.camera, ctx, dpr, toScreen, ...): classic scripts, one scope.

// Tiles: the smallest copy that's still sharp at this zoom (64, 128, 256, or the 512 original), kept
// within a pixel budget so a phone's canvas memory holds.
const SIZES = [64, 128, 256, 512], BUDGET = 40e6;
const baked = new Map(); // "key@size" -> canvas, oldest use first
let bakedPx = 0, frameNo = 0, tileStream;
const used = new Map(); // "key@size" -> frameNo last drawn
const want = () => terrainQuality?.textureResolution(state.camera.zoom, dpr) || 512;
const url = (t, size) => (size === 512 ? `tiles/${t.inst}/${t.src}.webp` : `tiles/${t.inst}/${size}/${t.src}.webp`) + `?v=${encodeURIComponent(assets?.version || "legacy")}`;
const tileOverview = { image: null, bounds: null, started: false, at: 0 };
const tileReducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
let overviewController = null;
import("./tile-stream.mjs").then(({ TileStream }) => {
  tileStream = new TileStream(draw, 16); // (HTTP/2 and 3: one connection carries them all)
  draw();
}).catch(fail);

// The tile's art on a canvas of its own (one we can size and free), with when it came (its fade in).
function bake(img) {
  const n = img.width, c = h("canvas", { width: n, height: n });
  c.getContext("2d").drawImage(img, 0, 0);
  c.bornAt = performance.now();
  return c;
}

function resetTileImages() {
  tileStream?.clear();
  overviewController?.abort();
  overviewController = null;
  tileOverview.image?.close();
  Object.assign(tileOverview, { image: null, bounds: null, started: false, at: 0 });
  for (const c of baked.values()) c.width = c.height = 0;
  baked.clear(); used.clear(); bakedPx = 0;
}

// One small picture of the whole map under the tiles, while they load: the first thing drawn (index.html asks for it
// before any script runs), so the view is never empty.
async function loadTileOverview() {
  if (tileOverview.started || !world) return;
  tileOverview.started = true;
  const controller = overviewController = new AbortController();
  const epoch = requests.epoch;
  let image;
  try {
    const response = await (early("sea/world.webp") || fetch("sea/world.webp", { signal: controller.signal, priority: "high" }));
    if (!response.ok) return;
    image = await createImageBitmap(await response.blob());
    if (controller.signal.aborted || epoch !== requests.epoch || image.width * image.height > 4e6) return;
    tileOverview.image = image;
    tileOverview.at = performance.now();
    tileOverview.bounds = [0, 0, world.bounds[2], world.bounds[3]]; // (at 24 px a tile: demo/bake_world.py world)
    image = null;
    draw();
  } catch (_) {
    // The overview is optional: failures leave normal tile requests working.
  } finally {
    image?.close();
  }
}

function evict() {
  for (const [id, c] of baked) {
    if (bakedPx <= BUDGET) break;
    if (!c || used.get(id) === frameNo) continue;
    baked.delete(id); used.delete(id);
    bakedPx -= c.width * c.height; c.width = c.height = 0; // frees it now on iOS
  }
}

// A tile's block: its quick copy among 8 x 8 tiles' in one picture (demo/export_blocks.py), where the map has them.
const BLOCK = 8, BLOCK_PX = 64;
function blockOf(t) {
  const col = Math.floor(t.src / 64), row = t.src % 64, bx = Math.floor(col / BLOCK), by = Math.floor(row / BLOCK);
  return { id: `b${t.inst}:${bx}_${by}`, path: `tiles/${t.inst}/b${BLOCK}/${bx}_${by}.webp?v=${encodeURIComponent(assets?.version || "legacy")}`,
    sx: (col % BLOCK) * BLOCK_PX, sy: (row % BLOCK) * BLOCK_PX };
}
const hasBlocks = (t) => !!assets?.blocks?.includes(t.inst);

// What to draw for a tile: [picture, source x, y, side]: the wanted copy if baked, else another of the tile's
// (sharper first), else its block's part, while it loads. previous: the one under the wanted copy fading in.
function tileImage(t, size, previous = false) {
  const id = `${t.key}@${size}`, c = baked.get(id);
  if (c && !previous) { baked.delete(id); baked.set(id, c); used.set(id, frameNo); return [c, 0, 0, c.width]; }
  for (const s of [...SIZES].reverse()) {
    if (s === size) continue;
    const other = baked.get(`${t.key}@${s}`);
    if (other) { used.set(`${t.key}@${s}`, frameNo); return [other, 0, 0, other.width]; }
  }
  if (hasBlocks(t)) {
    const b = blockOf(t), pic = baked.get(b.id);
    if (pic) { used.set(b.id, frameNo); return [pic, b.sx, b.sy, BLOCK_PX]; }
  }
}

// Tile (c, r)'s square on screen, its edges on device pixels so neighbours share them (no seams).
function tileRect(c, r) {
  const [x, y] = toScreen(c, r), sx = snap(x), sy = snap(y);
  return [sx, sy, snap(x + state.camera.zoom) - sx, snap(y + state.camera.zoom) - sy];
}

const SMALL = SIZES[0], RING = 0.35; // the quick copy; tiles past the view fetched ahead, as a share of its width
let available = null, availableOf = null; // assets.tiles as a Set
const fadeIn = (since, ms) => (tileReducedMotion.matches || !since ? 1 : Math.min(1, (performance.now() - since) / ms));

// A fetch of one picture, baked under id when it comes.
function job(id, path, priority, epoch) {
  return { key: id, priority,
    run: async (signal) => {
      const response = await fetch(path, { signal, priority: priority < 2 ? "high" : "auto" });
      if (!response.ok) throw Error(`Tile ${response.status}`);
      return createImageBitmap(await response.blob());
    },
    apply: (image) => {
      try {
        if (epoch !== requests.epoch) return;
        const c = bake(image);
        baked.set(id, c); bakedPx += c.width * c.height;
      } finally { image.close(); }
    },
    discard: (image) => image.close(),
  };
}

// The backdrop, then the land, centre first, so a slow connection fills in from where you're looking: first the
// quick copies (64 px: the blocks holding the view, a few requests for a screenful), then the sharp tiles, then
// the same for a ring past the view. Zoomed out to where 64 px is sharp enough, the blocks are all it draws.
function drawTiles() {
  frameNo++;
  if (assets && availableOf !== assets) { available = new Set(assets.tiles); availableOf = assets; }
  const drawable = assets ? tiles.filter((t) => !t.sea && available.has(t.key)) : [];
  ctx.fillStyle = bg; ctx.fillRect(0, 0, W, H);
  const [c0, r0, c1, r1] = view(), size = want();
  const m = Math.max(1, (c1 - c0) * RING);
  const near = (t, pad) => t.col + 1 >= c0 - pad && t.col <= c1 + pad && t.row + 1 >= r0 - pad && t.row <= r1 + pad;
  const dist = (t) => Math.hypot(t.col + .5 - state.camera.cx, t.row + .5 - state.camera.cy);
  const vis = drawable.filter((t) => near(t, 0)).sort((a, b) => dist(a) - dist(b));
  const ring = drawable.filter((t) => near(t, m) && !near(t, 0)).sort((a, b) => dist(a) - dist(b));
  const has = (t) => SIZES.some((s) => baked.has(`${t.key}@${s}`));
  const n = vis.length + ring.length, epoch = requests.epoch, jobs = new Map();
  const want1 = (id, path, priority) => { if (!baked.has(id) && !jobs.has(id)) jobs.set(id, job(id, path, priority, epoch)); };
  const quick = (list, base) => list.forEach((t, i) => {
    if (hasBlocks(t)) { if (size === SMALL || !has(t)) { const b = blockOf(t); want1(b.id, b.path, base + i); } }
    else if (size > SMALL && !has(t)) want1(`${t.key}@${SMALL}`, url(t, SMALL), base + i);
  });
  const sharp = (list, base) => list.forEach((t, i) => {
    if (!(size === SMALL && hasBlocks(t))) want1(`${t.key}@${size}`, url(t, size), base + i);
  });
  quick(vis, 0);
  sharp(vis, n);
  quick(ring, 2 * n);
  if (size <= 256) sharp(ring, 3 * n);
  tileStream?.update([...jobs.values()]);
  tileStream?.commit(6, 4);
  loadTileOverview();
  ctx.imageSmoothingQuality = "high";
  if (tileOverview.image) { // the whole map at once (its ocean too), the part in view, under the tiles as they come
    const [left, top, right, bottom] = tileOverview.bounds, image = tileOverview.image;
    const a = fadeIn(tileOverview.at, 220);
    if (a < 1) { ctx.globalAlpha = a; draw(); }
    const sx = image.width / (right - left), sy = image.height / (bottom - top);
    const a0 = Math.max(left, c0), b0 = Math.max(top, r0), a1 = Math.min(right, c1), b1 = Math.min(bottom, r1);
    if (a1 > a0 && b1 > b0) {
      const [x, y] = toScreen(a0, b0);
      ctx.drawImage(image, (a0 - left) * sx, (b0 - top) * sy, (a1 - a0) * sx, (b1 - b0) * sy,
        x, y, (a1 - a0) * state.camera.zoom, (b1 - b0) * state.camera.zoom);
    }
    ctx.globalAlpha = 1;
  }
  for (const t of vis) {
    const rect = tileRect(t.col, t.row);
    const img = tileImage(t, size);
    if (img) {
      const blend = fadeIn(img[0].bornAt, 140); // (over the copy it replaces, or the stand-in)
      let previous = blend < 1 && tileImage(t, size, true);
      if (previous && previous[0] === img[0]) previous = null;
      if (previous) ctx.drawImage(previous[0], previous[1], previous[2], previous[3], previous[3], ...rect);
      ctx.globalAlpha = blend;
      ctx.drawImage(img[0], img[1], img[2], img[3], img[3], ...rect);
      ctx.globalAlpha = 1;
      if (blend < 1) draw();
    }
  }
  evict();
}

async function loadTiles() {
  resetTileImages();
  const ticket = requests.ticket("tiles");
  const t = await get("/api/tiles");
  if (!requests.current(ticket)) return;
  tiles = t.tiles.map((x) => ({ ...x, col: Math.floor(x.key / 64), row: x.key % 64 }));
}
