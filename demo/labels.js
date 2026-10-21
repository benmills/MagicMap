// Map names. Shares the page's globals (cam, ctx, toScreen, ...): classic scripts, one scope.
//
// Atlas.Labels ranks every name (continent, zone, town, subzone, poi); this draws them as a
// typographic hierarchy: each tier has a zoom band, a face, size, tracking, case, colour and a
// soft drop shadow. Placement goes in rank order: a name that would touch a name already placed, or a pin
// it doesn't win over (a tier's over / covers), is dropped; pins it wins over aren't drawn. Labels
// fade in and out; both the bands and the collision test have hysteresis (a shown label keeps its
// place a little longer than a new one would win it), so zooming doesn't flicker.
//
// Fonts. The addon uses the game's own: Morpheus for continent and zone titles, Friz Quadrata
// (FRIZQT__) for the rest. Neither is on the web, so the demo uses lookalikes from Google Fonts:
//   Cinzel (titles): carved, Roman-inscription capitals like Morpheus's, and its lowercase *are*
//     small capitals, so "Elwynn Forest" is set as true small caps with no font feature needed.
//   Marcellus (body): a flared, glyphic serif (strokes swelling into wedge terminals) much like
//     Friz Quadrata, at text sizes too.
// Both fall back to serif system faces (Trajan / Palatino / Georgia).
//
// How the addon draws the same thing, with WoW primitives only:
//   - one FontString per placed label, from a pool; SetFont(file, size, flags) per tier and size
//     (Morpheus / FRIZQT__); SetTextColor and SetAlpha for colour, tier opacity and the fade.
//   - case: string.upper for body names (titles are mixed case); small caps: two FontStrings (capitals at full size, the rest
//     upper-cased at ~0.8 size) or a baked small-caps font file.
//   - tracking: FontStrings have no letter-spacing (SetSpacing is line spacing). Either bake it
//     into the font file (a tracked copy of Morpheus), or lay titles out a glyph per FontString
//     (fine for the dozen or so titles on screen). Body labels use no tracking for this reason.
//   - no italics: a FontString can't be slanted, so subzones are told apart by size, colour and
//     opacity, never by italic.
//   - the shadow: SetShadowColor(0, 0, 0, .85) + SetShadowOffset(1, 1), a soft drop shadow; names
//     of 12 px and under also get a thin dark outline ("OUTLINE" is the hard stroke this replaces).
//   - placement and fades are plain Lua over the same rects (GetStringWidth for widths).

const TITLE_FONT = "Cinzel, 'Trajan Pro', 'Palatino Linotype', Palatino, Georgia, serif";
const BODY_FONT = "Marcellus, 'Friz Quadrata TT', 'Palatino Linotype', Palatino, Georgia, serif";

const LABEL_STYLE = {
  fadeMs: 240,     // a full fade in or out
  bandPad: 0.18,   // a shown label stays until zoom leaves its band by this share (hysteresis)
  pad: 3,          // px a new label must keep clear of placed labels and pins
  keepPad: -2,     // px a shown label may overlap others before it gives way (hysteresis)
  margin: 40,      // px off screen a label still counts as on it
  // Per tier: zoom band [from, to) in px per tile; size: px, or { k, min, max } where
  // px = k * (the area's side on screen), clamped; over: below this zoom the name wins over every
  // pin (hiding the pins under it); covers: pin layers it always wins over; any other pin it keeps
  // clear of; fit: at most this share of the view's width (a phone); track: letter-spacing in em;
  // caps: "small" | null (mixed case; "small" sets lowercase as small caps).
  tiers: {
    continent: { zoom: [0, 26], over: 26, fit: 0.8, font: TITLE_FONT, weight: 700, size: { k: 0.1, min: 15, max: 22 }, track: 0.28,
      caps: null, color: "#f2dfae", alpha: 0.92 },
    zone: { zoom: [6, 320], over: 40, covers: ["rare", "quest", "mail", "herb", "ore"], font: TITLE_FONT, weight: 700, size: { k: 0.085, min: 11.5, max: 22 }, track: 0.12,
      caps: null, color: "#ffe3a1", alpha: 0.95 },
    town: { zoom: [30, Infinity], covers: ["rare", "mail", "herb", "ore"], font: BODY_FONT, weight: 400, size: 12.5, track: 0,
      caps: null, color: "#fbf6ea", alpha: 0.9 },
    subzone: { zoom: [72, Infinity], covers: ["mail", "herb", "ore"], font: BODY_FONT, weight: 400, size: { k: 0.1, min: 10.5, max: 13 }, track: 0.04,
      caps: null, color: "rgb(232,219,196)", alpha: 0.78 },
    poi: { zoom: [150, Infinity], covers: ["mail", "herb", "ore"], font: BODY_FONT, weight: 400, size: 10.5, track: 0,
      caps: null, color: "#d6ccb6", alpha: 0.68 },
  },
  // Every name: a soft dark drop shadow, and a thin dark outline at 12 px and under.
  shadow: { color: "rgba(0,0,0,.85)", offset: 1, blur: 2 },
  outline: { maxSize: 12, width: 1, color: "rgba(10,6,0,.9)" },
  // Pins at continent zoom: scaled and faded so the names carry the map, easing back to full
  // size and opacity between these zooms.
  pins: { quietZoom: [14, 48], scale: 0.62, alpha: 0.6 },
};

let labels = [];
const labelState = new Map(); // rank -> { a: opacity 0..1, on, spot: candidate index }
let labelClock = 0;

// Canvas text silently uses a fallback until a web font has loaded, so the map waits for both.
async function loadLabels() {
  [{ labels }] = await Promise.all([get(`/api/labels?inst=${INST}`),
    ...[`700 20px Cinzel`, `400 20px Marcellus`].map((f) => document.fonts.load(f))]);
}

// How quiet pins are at this zoom: { s: scale, a: opacity }.
function pinQuiet() {
  const { quietZoom: [z0, z1], scale, alpha } = LABEL_STYLE.pins;
  const t = clamp(Math.log(cam.zoom / z0) / Math.log(z1 / z0), 0, 1);
  return { s: scale + (1 - scale) * t, a: alpha + (1 - alpha) * t };
}

function labelSize(l, st) {
  const s = st.size;
  if (typeof s === "number") return s;
  return Math.round(clamp(s.k * l.size * cam.zoom, s.min, s.max) * 2) / 2; // half-px steps: fewer re-measures
}

function inBand(st, on) {
  const [lo, hi] = st.zoom, k = on ? 1 + LABEL_STYLE.bandPad : 1;
  return cam.zoom >= lo / k && cam.zoom < hi * k;
}

// Set the context up for a tier at a size; the text's width (measured once per font and text).
const widths = new Map();
function setFont(text, st, size) {
  ctx.font = `${st.weight} ${size}px ${st.font}`;
  ctx.fontVariantCaps = st.caps === "small" ? "small-caps" : "normal";
  ctx.letterSpacing = `${(st.track * size).toFixed(2)}px`;
  const key = `${ctx.font}${ctx.fontVariantCaps}|${ctx.letterSpacing}|${text}`;
  if (!widths.has(key)) widths.set(key, ctx.measureText(text).width);
  return widths.get(key);
}

// Where a label may sit, relative to its anchor, in order of preference: centred on it, then
// above / below; a town or landmark beside its pin (right, left, above, below).
function spots(l, w, h) {
  if (l.tier === "town" || l.tier === "poi") {
    const g = PIN_R.poi + LABEL_STYLE.pad; // clear of its own pin
    return [[0, 0], [g + w / 2, 0], [-g - w / 2, 0], [0, -g - h / 2], [0, g + h / 2]];
  }
  const dx = Math.min(w * 0.35, 40), dy = h * 1.1;
  return [[0, 0], [0, -dy], [0, dy], [dx, 0], [-dx, 0], [dx, -dy], [-dx, -dy], [dx, dy], [-dx, dy]];
}

const clear = (b, boxes, pad) => !boxes.some((o) => b[0] - pad < o[2] && b[2] + pad > o[0] && b[1] - pad < o[3] && b[3] + pad > o[1]);

// pinBoxes: the screen rects of the pins drawn this frame, [x0, y0, x1, y1, layer]. Returns the
// indices of those a name covers, for the caller not to draw.
function drawLabels(pinBoxes) {
  const covered = new Set();
  const now = performance.now(), step = labelClock ? Math.min(100, now - labelClock) / LABEL_STYLE.fadeMs : 1;
  labelClock = now;
  const boxes = [], blockers = {}, m = LABEL_STYLE.margin; // blockers: per tier, the pins it keeps clear of
  let fading = false;
  ctx.save();
  ctx.textAlign = "center"; ctx.textBaseline = "middle"; ctx.lineJoin = "round";
  for (const l of labels) {
    const st = LABEL_STYLE.tiers[l.tier];
    let s = labelState.get(l.rank);
    if (!s) { s = { a: 0, on: false, spot: 0 }; labelState.set(l.rank, s); }
    const [ax, ay] = toScreen(l.col, l.row);
    if (ax < -300 - m || ax > W + 300 + m || ay < -m - 60 || ay > H + m + 60) continue; // far off: keep its state
    const text = l.text;
    let size = labelSize(l, st), w = setFont(text, st, size);
    if (st.fit && w > W * st.fit) { size = Math.floor(size * W * st.fit / w); w = setFont(text, st, size); }
    const h = size * 1.15;
    let want = inBand(st, s.on), at = null;
    if (want) {
      const cands = spots(l, w, h), order = [s.spot, ...cands.keys()];
      const pad = s.on ? LABEL_STYLE.keepPad : LABEL_STYLE.pad, over = cam.zoom < (st.over || 0);
      const wins = (p) => over || st.covers?.includes(p[4]);
      const blocking = over ? [] : (blockers[l.tier] ??= pinBoxes.filter((p) => !wins(p)));
      for (const i of order) {
        const x = ax + cands[i][0], y = ay + cands[i][1], b = [x - w / 2, y - h / 2, x + w / 2, y + h / 2];
        if (!clear(b, boxes, pad) || !clear(b, blocking, pad)) continue;
        pinBoxes.forEach((p, j) => { if (wins(p) && !clear(b, [p], 0)) covered.add(j); });
        at = [x, y]; boxes.push(b); s.spot = i;
        break;
      }
      want = !!at;
    }
    s.on = want;
    s.a = clamp(s.a + (want ? step : -step), 0, 1);
    if (s.a !== (want ? 1 : 0)) fading = true;
    if (s.a === 0) continue;
    if (!at) { const c = spots(l, w, h)[s.spot]; at = [ax + c[0], ay + c[1]]; } // fading out where it was
    drawLabel(text, at[0], at[1] + size * 0.04, st, size, s.a);
  }
  ctx.restore();
  if (fading) draw();
  return covered;
}

function drawLabel(text, x, y, st, size, a) {
  const sh = LABEL_STYLE.shadow, ol = LABEL_STYLE.outline;
  ctx.globalAlpha = a * st.alpha;
  if (size <= ol.maxSize) { // the thin outline, under the glyphs
    ctx.lineWidth = ol.width; ctx.strokeStyle = ol.color; ctx.strokeText(text, x, y);
  }
  ctx.shadowColor = sh.color; ctx.shadowOffsetX = sh.offset; ctx.shadowOffsetY = sh.offset; ctx.shadowBlur = sh.blur;
  ctx.fillStyle = st.color; ctx.fillText(text, x, y);
  ctx.shadowColor = "transparent"; ctx.shadowOffsetX = 0; ctx.shadowOffsetY = 0; ctx.shadowBlur = 0;
}

