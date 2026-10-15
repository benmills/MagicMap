// Zone borders, and the zone under the pointer highlighted. Shares the page's globals
// (cam, ctx, toScreen, ...): classic scripts, one scope.
//
// Drawn only as the addon can draw it, with WoW primitives:
// - a border is one Line region per segment (SetStartPoint / SetEndPoint, SetThickness,
//   SetColorTexture or a white texture + SetVertexColor, alpha); no joins or caps, so here
//   each segment is its own butt-capped stroke too. The halo is wider, darker Lines under them
//   all; a fading end is that stretch cut into short Lines of falling alpha and thickness.
// - the highlight's edge is Lines along the zone's outline rings; its fill would be a
//   solid-colour texture under a MaskTexture of the zone's shape (baked offline from the same
//   rings), or the rings ear-clipped into triangles, each a texture made triangular with
//   SetVertexOffset. Here, an even-odd canvas fill of the rings stands in for either.
// The data are already smooth (tools/gen_borders.py): nothing is smoothed here.

// Every tunable. Steps apply from their zoom (px per tile) up, until the next.
const BORDER_STYLE = {
  steps: [ // width: the light line; halo: [[extra width, alpha], ...] dark Lines under it, widest first
    { zoom: 0, width: 1.0, alpha: 0.6, halo: [[3.0, 0.16], [1.8, 0.3]] },
    { zoom: 40, width: 1.3, alpha: 0.7, halo: [[4.0, 0.16], [2.4, 0.32]] },
    { zoom: 120, width: 1.7, alpha: 0.78, halo: [[5.5, 0.15], [3.0, 0.34]] },
    { zoom: 300, width: 2.2, alpha: 0.82, halo: [[7.0, 0.14], [3.8, 0.36]] },
  ],
  color: [255, 216, 140], // warm light
  haloColor: [12, 8, 4],
  fadeMinPx: 12, // a fading end fades over its length over water, but at least this far
  fadePiecePx: 4, // ...in pieces this long (one Line each)
  minSegmentPx: 1.5, // closer points merge (far out, many segments would be sub-pixel)
  highlight: {
    fill: [255, 228, 170, 0.1],
    edge: [255, 244, 214], edgeAlpha: 0.95, edgeExtra: 0.6, // edge = the step's width + this
    haloAlpha: 1.25, // the step's halo alpha, times this, under the edge
  },
};

let borderLevels = null, farZoom = 0;
let zoneHighlight = null; // { zone, rings } (rings: point lists), or null
const outlines = new Map(); // zone areaID -> Promise of rings

// Each line with its bounds in tiles, to skip those out of view.
function prepLines(raw) {
  return raw.map(([a, b, fadeStart, fadeEnd, ...pts]) => {
    const cs = pts.filter((_, i) => i % 2 === 0), rs = pts.filter((_, i) => i % 2 === 1);
    return { a, b, fadeStart, fadeEnd, pts, c0: Math.min(...cs), c1: Math.max(...cs), r0: Math.min(...rs), r1: Math.max(...rs) };
  });
}

async function loadBorders() {
  const b = await get(`/api/borders?inst=${INST}`);
  borderLevels = { near: prepLines(b.lines), far: prepLines(b.far) };
  farZoom = b.farZoom;
}

// The zone to highlight (its areaID), or none; inspect() sets it from the readout's ZoneAt.
async function setZoneHighlight(zone) {
  if ((zoneHighlight && zoneHighlight.zone) === zone) return;
  if (!zone) { zoneHighlight = null; draw(); return; }
  if (!outlines.has(zone)) outlines.set(zone, get(`/api/zone-outline?inst=${INST}&zone=${zone}`).then((o) => o.rings));
  const pending = { zone, rings: null };
  zoneHighlight = pending;
  const rings = await outlines.get(zone);
  if (zoneHighlight === pending) { pending.rings = rings; draw(); }
}

const borderStep = () => BORDER_STYLE.steps.reduce((s, x) => (cam.zoom >= x.zoom ? x : s));
const rgba = (c, a) => `rgba(${c[0]},${c[1]},${c[2]},${a})`;

// Screen points of a tile-space polyline, merging points closer than minSegmentPx (ends kept).
function screenPts(pts, closed) {
  const out = [], min2 = BORDER_STYLE.minSegmentPx ** 2, n = pts.length / 2;
  for (let k = 0; k < n; k++) {
    const [x, y] = toScreen(pts[k * 2], pts[k * 2 + 1]), m = out.length;
    if (!m || k === n - 1 || (x - out[m - 2]) ** 2 + (y - out[m - 1]) ** 2 >= min2) out.push(x, y);
  }
  if (closed) out.push(out[0], out[1]);
  return out;
}

// One Line: a butt-capped segment.
function seg(x1, y1, x2, y2) { ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke(); }

// A polyline as Lines, of width w and colour c at alpha a; fs / fe px fade out at its start / end.
function polyline(p, w, c, a, fs, fe) {
  ctx.lineCap = "butt";
  let total = 0;
  for (let i = 2; i < p.length; i += 2) total += Math.hypot(p[i] - p[i - 2], p[i + 1] - p[i - 1]);
  fs = Math.min(fs, total / 2); fe = Math.min(fe, total / 2);
  const fade = (d) => Math.min(1, fs ? d / fs : 1, fe ? (total - d) / fe : 1);
  let along = 0;
  for (let i = 2; i < p.length; i += 2) {
    const x1 = p[i - 2], y1 = p[i - 1], x2 = p[i], y2 = p[i + 1], d = Math.hypot(x2 - x1, y2 - y1);
    if (along >= fs && along + d <= total - fe) {
      ctx.lineWidth = w; ctx.strokeStyle = rgba(c, a); seg(x1, y1, x2, y2);
    } else {
      const n = Math.max(1, Math.ceil(d / BORDER_STYLE.fadePiecePx));
      for (let k = 0; k < n; k++) {
        const f = fade(along + d * (k + 0.5) / n);
        if (f < 0.05) continue;
        ctx.lineWidth = w * (0.6 + 0.4 * f); ctx.strokeStyle = rgba(c, a * f);
        seg(x1 + (x2 - x1) * k / n, y1 + (y2 - y1) * k / n, x1 + (x2 - x1) * (k + 1) / n, y1 + (y2 - y1) * (k + 1) / n);
      }
    }
    along += d;
  }
}

function drawBorders() {
  if (!borderLevels) return;
  const [c0, r0, c1, r1] = view();
  const vis = (cam.zoom < farZoom ? borderLevels.far : borderLevels.near).filter((l) => !(l.c1 < c0 || l.c0 > c1 || l.r1 < r0 || l.r0 > r1));
  const s = borderStep(), hs = BORDER_STYLE.highlight;
  const rings = zoneHighlight && zoneHighlight.rings && zoneHighlight.rings.map((r) => screenPts(r, true));
  if (rings) {
    ctx.beginPath();
    for (const r of rings) { ctx.moveTo(r[0], r[1]); for (let i = 2; i < r.length; i += 2) ctx.lineTo(r[i], r[i + 1]); ctx.closePath(); }
    ctx.fillStyle = rgba(hs.fill, hs.fill[3]); ctx.fill("evenodd");
  }
  const lines = vis.map((l) => ({ p: screenPts(l.pts), fs: l.fadeStart && Math.max(l.fadeStart * cam.zoom, BORDER_STYLE.fadeMinPx),
    fe: l.fadeEnd && Math.max(l.fadeEnd * cam.zoom, BORDER_STYLE.fadeMinPx) }));
  // Halos first, all of them, so no halo darkens a neighbour's light line where they meet.
  for (const [w, a] of s.halo) for (const l of lines) polyline(l.p, w + s.width, BORDER_STYLE.haloColor, a, l.fs, l.fe);
  if (rings) for (const [w, a] of s.halo) for (const r of rings) polyline(r, w + s.width + hs.edgeExtra, BORDER_STYLE.haloColor, a * hs.haloAlpha, 0, 0);
  for (const l of lines) polyline(l.p, s.width, BORDER_STYLE.color, s.alpha, l.fs, l.fe);
  if (rings) for (const r of rings) polyline(r, s.width + hs.edgeExtra, hs.edge, hs.edgeAlpha, 0, 0);
}
