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
const tileOverview = { image: null, bounds: null, started: false };
const tileFade = new Map();
const tileReducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
let overviewController = null;
import("./tile-stream.mjs").then(({ TileStream }) => {
  tileStream = new TileStream(draw, 4);
  draw();
}).catch(fail);

// The tile's art on a canvas of its own (one we can size and free).
function bake(img) {
  const n = img.width, c = h("canvas", { width: n, height: n });
  c.getContext("2d").drawImage(img, 0, 0);
  return c;
}

function resetTileImages() {
  tileStream?.clear();
  overviewController?.abort();
  overviewController = null;
  tileOverview.image?.close();
  Object.assign(tileOverview, { image: null, bounds: null, started: false });
  for (const c of baked.values()) c.width = c.height = 0;
  baked.clear(); used.clear(); tileFade.clear(); bakedPx = 0;
}

// One small picture of the whole map under the tiles, while they load.
async function loadTileOverview() {
  if (tileOverview.started || !assets) return;
  tileOverview.started = true;
  const controller = overviewController = new AbortController();
  const epoch = requests.epoch;
  let image;
  try {
    const response = await fetch(`sea/world.webp?v=${encodeURIComponent(assets.version)}`,
      { signal: controller.signal, priority: "low" });
    if (!response.ok) return;
    image = await createImageBitmap(await response.blob());
    if (controller.signal.aborted || epoch !== requests.epoch || image.width * image.height > 4e6) return;
    tileOverview.image = image;
    tileOverview.bounds = [0, 0, 92, 64]; // (the world's, at 24 px a tile: baked from its tiles)
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
    baked.delete(id); used.delete(id); tileFade.delete(id);
    bakedPx -= c.width * c.height; c.width = c.height = 0; // frees it now on iOS
  }
}

// The wanted copy if baked, else any other of the tile's (sharper first) while it loads.
function tileImage(t, size, previous = false) {
  const id = `${state.inst}:${t.key}@${size}`, c = baked.get(id);
  if (c && !previous) { baked.delete(id); baked.set(id, c); used.set(id, frameNo); return c; }
  for (const s of [...SIZES].reverse()) {
    if (s === size) continue;
    const other = baked.get(`${state.inst}:${t.key}@${s}`);
    if (other) { used.set(`${state.inst}:${t.key}@${s}`, frameNo); return other; }
  }
}

// Tile (c, r)'s square on screen, its edges on device pixels so neighbours share them (no seams).
function tileRect(c, r) {
  const [x, y] = toScreen(c, r), sx = snap(x), sy = snap(y);
  return [sx, sy, snap(x + state.camera.zoom) - sx, snap(y + state.camera.zoom) - sy];
}

// The backdrop, then the land, centre first, so a slow connection fills in from where you're looking.
function drawTiles() {
  frameNo++;
  const drawable = tiles.filter((t) => !t.sea && (!assets || assets.tiles.includes(t.key)));
  ctx.fillStyle = bg; ctx.fillRect(0, 0, W, H);
  const [c0, r0, c1, r1] = view(), size = want();
  const vis = drawable.filter((t) => t.col + 1 >= c0 && t.col <= c1 && t.row + 1 >= r0 && t.row <= r1);
  vis.sort((a, b) => Math.hypot(a.col + .5 - state.camera.cx, a.row + .5 - state.camera.cy) - Math.hypot(b.col + .5 - state.camera.cx, b.row + .5 - state.camera.cy));
  const epoch = requests.epoch;
  const jobs = vis.flatMap((t, priority) => {
    const id = `${state.inst}:${t.key}@${size}`;
    if (baked.has(id)) return [];
    const path = url(t, size);
    return [{ key: id, priority,
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
          tileFade.set(id, performance.now());
        } finally { image.close(); }
      },
      discard: (image) => image.close(),
    }];
  });
  tileStream?.update(jobs);
  tileStream?.commit(2, 3);
  loadTileOverview();
  ctx.imageSmoothingQuality = "high";
  for (const t of vis) {
    const rect = tileRect(t.col, t.row);
    if (tileOverview.image) {
      const [left, top, right, bottom] = tileOverview.bounds;
      const image = tileOverview.image, sx = image.width / (right - left), sy = image.height / (bottom - top);
      if (t.col >= left && t.col + 1 <= right && t.row >= top && t.row + 1 <= bottom)
        ctx.drawImage(image, (t.col - left) * sx, (t.row - top) * sy, sx, sy, ...rect);
    }
    const img = tileImage(t, size);
    if (img) {
      const since = tileFade.get(`${state.inst}:${t.key}@${size}`);
      const blend = tileReducedMotion.matches || since == null ? 1 : Math.min(1, (performance.now() - since) / 140);
      const previous = blend < 1 && tileImage(t, size, true);
      if (previous) ctx.drawImage(previous, ...rect);
      ctx.globalAlpha = blend;
      ctx.drawImage(img, ...rect);
      ctx.globalAlpha = 1;
      if (blend < 1) draw();
    }
  }
  evict();
}

async function loadTiles() {
  resetTileImages();
  const ticket = requests.ticket("tiles");
  const t = await get(`/api/tiles?inst=${state.inst}`);
  if (!requests.current(ticket)) return;
  tiles = t.tiles.map((x) => ({ ...x, col: Math.floor(x.key / 64), row: x.key % 64 }));
}
