// Everything shown comes from the server's Atlas calls; this file only draws.
// Allow twice the source pixels on screen, including retina density. A CSS-only
// limit would stretch each source pixel six times on a DPR3 phone.
const CHUNKS = 16,
  MIN_ZOOM = 4,
  MIN_3D_ZOOM = 64, // px a tile: 3D no further out, so a phone keeps 60 fps (README)
  TEXELS = 512,
  MAX_STRETCH = 2;
const maxZoom = () => TEXELS * MAX_STRETCH / (dpr || 1);
const minZoom = () => (state.mode === "3d" ? MIN_3D_ZOOM : MIN_ZOOM);
let out3D = false; // a zoom asked for less than 3D allows: back to 2D once it settles (app.js)
const $ = (id) => document.getElementById(id);
const canvas = $("map"),
  ctx = canvas.getContext("2d"),
  readout = $("readout");
const state = {
  inst: 1,
  camera: null,
  mode: "2d",
  desiredMode: "2d",
  yaw: 0,
  tilt: 45,
  selection: null,
  sources: [],
  tools: new Set(),
  labelTiers: new Set(["zone", "town", "subzone"]),
  flyover: false,
};
let viewState,
  terrainQuality,
  mapMotion,
  requests,
  terrain = null,
  world = null, // /api/maps: the one map, its parts each map's place on it
  assets = null,
  modeSeq = 0,
  terrainLoading = false,
  restoring = false;
const modulesReady = Promise.all([
  import("./view-state.mjs"),
  import("./terrain-quality.mjs"),
  import("./map-motion.mjs"),
]).then(([m, quality, motion]) => {
  viewState = m;
  terrainQuality = quality;
  mapMotion = motion;
  requests = new m.Requests();
});
async function get(path, options = {}) {
  const r = await fetch(path, options);
  if (!r.ok) throw Error(`${path.split("?")[0]}: ${r.status}`);
  return r.json();
}
function notice(message) {
  $("status").textContent = message;
  $("status").hidden = !message;
}
function fail(error) {
  if (error.name !== "AbortError") notice(error.message || String(error));
}
function run(fn) {
  return (...args) =>
    Promise.resolve()
      .then(() => fn(...args))
      .catch(fail);
}
const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
const rgb = (c) => `rgb(${c.map((v) => Math.round(v * 255)).join(",")})`;
let W,
  H,
  dpr,
  bg = "#000",
  tiles = [],
  walk = null,
  marker = null;

// The place under the pointer (and a tap's marker): only zoomed in this far; from afar it's noise.
const READOUT_ZOOM = 24; // px a tile

function resize() {
  // CSS owns the large viewport behind Safari's translucent controls. Measure
  // that surface rather than shrinking it to the currently visible viewport.
  const rect = canvas.getBoundingClientRect();
  W = rect.width;
  H = rect.height;
  dpr = terrainQuality.renderDensity(W, H, devicePixelRatio || 1);
  const width = Math.max(1, Math.round(W * dpr)), height = Math.max(1, Math.round(H * dpr));
  // Visual viewport changes need not replace the backing surface. Reallocating
  // an unchanged canvas clears it and needlessly changes its compositing state.
  if (canvas.width !== width) canvas.width = width;
  if (canvas.height !== height) canvas.height = height;
  draw();
  settled();
  placeSheets();
}

// Pointer events use client coordinates; drawing/picking use canvas coordinates.
// They differ when Safari pans the visual viewport, including keyboard changes.
function mapPoint(clientX, clientY) {
  const rect = canvas.getBoundingClientRect();
  return { x: (clientX - rect.left) * W / rect.width, y: (clientY - rect.top) * H / rect.height };
}

// Atlas.Camera.ScreenToTile / TileToScreen / ZoomAt, per frame.
// Small view interface: projection, ground picking, bounds, and fit share Atlas tile coordinates.
const flatView = {
  project: (c, r) => [
    (c - state.camera.cx) * state.camera.zoom + W / 2,
    (r - state.camera.cy) * state.camera.zoom + H / 2,
  ],
  pick: (x, y) => [
    state.camera.cx + (x - W / 2) / state.camera.zoom,
    state.camera.cy + (y - H / 2) / state.camera.zoom,
  ],
  bounds: () => [...flatView.pick(0, 0), ...flatView.pick(W, H)],
  fit: (points, w, h) =>
    viewState.fitBounds(
      [
        Math.min(...points.map((p) => p.col)),
        Math.min(...points.map((p) => p.row)),
        Math.max(...points.map((p) => p.col)),
        Math.max(...points.map((p) => p.row)),
      ],
      w,
      h,
    ),
};
const activeView = () => (state.mode === "3d" && terrain ? terrain : flatView);
const toTile = (x, y) => activeView().pick(x, y) || activeView().plane(x, y);
const toScreen = (c, r) => activeView().project(c, r);
const view = () => activeView().bounds();
const snap = (v) => Math.round(v * dpr) / dpr; // to a device pixel
// The tile under (x, y) stays there; with (x1, y1), it moves there (a pinch's midpoint).
function zoomAt(x, y, zoom, x1 = x, y1 = y) {
  const locked = terrain?.focusLocked;
  if (state.mode === "3d") terrain.focusLocked = true;
  const [c, r] = toTile(x, y);
  const height =
    state.mode === "3d" ? (terrain.sample(c, r)?.height ?? terrain.focus) : 0;
  // Pushing out against 3D's limit (a wheel or button at it; a pinch: navigation.js).
  out3D = state.mode === "3d" && zoom < MIN_3D_ZOOM && state.camera.zoom <= MIN_3D_ZOOM * 1.01;
  zoom = clamp(zoom, minZoom(), maxZoom());
  state.camera = { ...state.camera, zoom };
  if (state.mode === "3d")
    terrain.setView(state.camera, W, H, state.yaw, state.tilt);
  // Use the touched point's elevation: picking again after zoom can hit a
  // different part of a hillside and slide the original point out from under it.
  const [nc, nr] =
    state.mode === "3d" ? terrain.plane(x1, y1, height) : flatView.pick(x1, y1);
  state.camera.cx += c - nc;
  state.camera.cy += r - nr;
  if (state.mode === "3d" && !locked) finishGroundPan();
}

function finishGroundPan() {
  if (state.mode !== "3d" || !terrain) return;
  terrain.setView(state.camera, W, H, state.yaw, state.tilt);
  const center = terrain.pick(W / 2, H / 2);
  const ground = center && terrain.sample(...center);
  if (ground) {
    // Rebase onto the ground under the screen centre without moving any pixels.
    // Recomputing elevation mid-drag would make a tilted hillside slip under a finger.
    // The eye stays put, so the new focus, nearer or farther along the centre's ray, is that much bigger or smaller.
    const near = terrain.point(center[0], center[1], ground.height)[3];
    state.camera = { ...state.camera, cx: center[0], cy: center[1], zoom: state.camera.zoom * near };
    terrain.focus = ground.height;
  }
  terrain.focusLocked = false;
  terrain.setView(state.camera, W, H, state.yaw, state.tilt);
}

let pending = false;
function draw() {
  if (state.camera && !pending) {
    pending = true;
    requestAnimationFrame(frame);
  }
}

function frame() {
  pending = false;
  // Browsers can change page/display density without a window resize event.
  // Reconcile at the drawing boundary so an old backing cannot remain scaled.
  if (dpr !== terrainQuality.renderDensity(W, H, devicePixelRatio || 1)) resize();
  // Old shared cameras and density changes use the same limit as gestures.
  state.camera.zoom = clamp(state.camera.zoom, minZoom(), maxZoom());
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  if (state.mode === "3d") {
    terrain.setView(state.camera, W, H, state.yaw, state.tilt);
    terrain.interacting =
      pts.size > 0 || motion !== null || wheelTimer !== null;
    terrain.render(state.tools);
    ctx.clearRect(0, 0, W, H);
  } else if (!terrainLoading && assets) drawTiles();
  else {
    ctx.fillStyle = bg;
    ctx.fillRect(0, 0, W, H);
  }
  if (
    state.mode === "2d" &&
    terrain?.inst === state.inst &&
    (state.tools.has("elevation") ||
      state.tools.has("slope") ||
      state.tools.has("contours") ||
      profilePoints.length ||
      $("profile").getAttribute("aria-pressed") === "true")
  ) {
    terrain.setView(state.camera, W, H, 0, 0);
    terrain.interacting =
      pts.size > 0 || motion !== null || wheelTimer !== null;
    terrain.render(state.tools);
  }
  drawAnalysis();
  if (walk) drawWalk();
  if (state.mode === "2d" && typeof MapArt === "object") MapArt.draw(ctx, toScreen, state.camera.zoom, world.parts, draw); // (mapart.js)
  // Pins: where they'll be drawn first, so labels keep clear of them; quieter at continent zoom,
  // where names win; pins a name covers aren't drawn.
  const quiet = pinQuiet(),
    onScreen = [];
  for (const p of state.mode === "3d" ? [] : pins) { // (3D shows the land, and names: no pins)
    if (!pinVisible(p)) continue;
    const [x, y] = toScreen(p.col, p.row);
    if (x > -20 && x < W + 20 && y > -20 && y < H + 20)
      onScreen.push([p, x, y]);
  }
  const covered = layerOn.has("labels")
    ? drawLabels(
        onScreen.map(([p, x, y]) => pinBox(p, x, y, quiet.s)),
      )
    : new Set();
  drawnPins = onScreen.filter((_, i) => !covered.has(i)).map(([p]) => p);
  ctx.globalAlpha = quiet.a;
  for (const [i, [p, x, y]] of onScreen.entries()) {
    if (covered.has(i)) continue; // under a name that wins over it
    drawMapPin(ctx, p, x, y, quiet.s);
  }
  ctx.globalAlpha = 1;
  if (highlight) drawHighlight();
  if (marker) {
    const [x, y] = toScreen(marker[0], marker[1]);
    ctx.beginPath();
    ctx.moveTo(x - 5, y);
    ctx.lineTo(x + 5, y);
    ctx.moveTo(x, y - 5);
    ctx.lineTo(x, y + 5);
    ctx.lineWidth = 2;
    ctx.strokeStyle = "#10201b66";
    ctx.stroke();
    ctx.lineWidth = 1;
    ctx.strokeStyle = "#f0ead0b3";
    ctx.stroke();
  }
}
