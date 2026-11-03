// Pins: the game's own map icons, cut by tools/export_icons.py into demo/icons (one sheet + a
// manifest). Which icon a pin gets is a UI choice, so the table is here; export_icons.py reads it
// to export exactly these. A value is a UiTextureAtlasMember name, all cut from ObjectIconsAtlas
// (1121272) in this build; the addon draws one with tex:SetAtlas(name). A POI uses its own Icon:
// cell N of Interface/Minimap/POIIcons (136441), 14 cells of 18 px a row; the addon:
// tex:SetTexture(136441); tex:SetTexCoord(x / 256, (x + 18) / 256, y / 512, (y + 18) / 512)
// with x = N % 14 * 18, y = floor(N / 14) * 18 (the game's GetPOITextureCoords).
const GAME_ICON = {
  flight: {
    A: "taxinode_alliance",
    H: "taxinode_horde",
    AH: "taxinode_neutral",
    none: "taxinode_neutral",
  },
  dungeon: { dungeon: "dungeon", raid: "raid", battleground: "battlemaster" },
  service: {
    innkeeper: "innkeeper",
    flightmaster: "flightmaster",
    banker: "banker",
    auctioneer: "auctioneer",
    stablemaster: "stablemaster",
    battlemaster: "battlemaster",
    trainer: "profession",
    repair: "repair",
  },
  quest: "questnormal",
  rare: { 4: "vignettekill", 2: "vignettekillelite" },
  mail: "mailbox",
  herb: "professions_tracking_herb",
  ore: "professions_tracking_ore",
};
// Drawn size per layer, px (the icon's longer side), near the game's map and minimap icons.
const PIN_SIZE = {
  flight: 18,
  poi: 18,
  dungeon: 20,
  rare: 15,
  service: 14,
  quest: 18,
  mail: 14,
  herb: 14,
  ore: 14,
};
const PIN_R = Object.fromEntries(
  Object.entries(PIN_SIZE).map(([k, s]) => [k, s / 2]),
); // half a pin's box, px
// Icons that don't show a faction themselves sit on a soft glow of its colour (the addon: a
// feathered disc texture under the icon, SetVertexColor per faction).
const FACTION = { A: "#4a8cff", H: "#ff4d40", AH: "#f2c94c" },
  TINTED = new Set(["service", "quest"]);
const FACTION_NAME = { A: "Alliance", H: "Horde", AH: "Alliance & Horde" };
const SERVICE_NAME = {
  innkeeper: "Inn",
  flightmaster: "Flight master",
  banker: "Bank",
  auctioneer: "Auction",
  stablemaster: "Stable",
  battlemaster: "Battlemaster",
  trainer: "Trainer",
  repair: "Repair",
};
const RANK = { 1: "Elite", 2: "Rare elite", 3: "Boss", 4: "Rare" };
const LAYERS = [
  // id, name, shown from this zoom (px per tile), a sample pin for the legend
  ["flight", "Flight points", 0, { faction: "A" }],
  ["poi", "Points of interest", 0, { icon: 6 }],
  ["dungeon", "Dungeon entrances", 0, { mark: "dungeon" }],
  ["rare", "Rare locations", 60, { mark: 4 }],
  ["service", "Town services", 60, { mark: "innkeeper" }],
  ["quest", "Quest givers", 160, {}],
  ["mail", "Mailboxes", 160, {}],
  ["herb", "Herbs", 256, {}],
  ["ore", "Ore", 256, {}],
];
const layerOn = new Set(["flight", "poi", "dungeon", "service", "labels"]);
const shown = (id) =>
  layerOn.has(id) && state.camera.zoom >= LAYERS.find((l) => l[0] === id)[2];
const pinVisible = (p) => p.kind === "group" ? p.members.some((m) => shown(m.layer)) : shown(p.layer);
let pins = [],
  drawnPins = [],
  highlight = null,
  iconSheet,
  ICONS;

// The sheet and its manifest ({ key: [x, y, w, h] }); pins wait for both.
async function loadIcons() {
  const img = new Image();
  img.src = "icons/icons.png";
  [{ icons: ICONS }] = await Promise.all([
    get("icons/icons.json"),
    img.decode(),
  ]);
  iconSheet = img;
}
function iconOf(layer, p) {
  const m = GAME_ICON[layer];
  if (layer === "poi") return `poi:${p.icon}`;
  if (layer === "flight") return m[p.faction] || m.none;
  return typeof m === "string" ? m : m[p.mark];
}
const glows = {};
function glow(f) {
  if (!glows[f]) {
    const c = h("canvas", { width: 64, height: 64 }),
      g = c.getContext("2d"),
      gr = g.createRadialGradient(32, 32, 0, 32, 32, 32);
    gr.addColorStop(0, FACTION[f] + "a0");
    gr.addColorStop(0.55, FACTION[f] + "60");
    gr.addColorStop(1, FACTION[f] + "00");
    g.fillStyle = gr;
    g.fillRect(0, 0, 64, 64);
    glows[f] = c;
  }
  return glows[f];
}
// An icon centred on (x, y) at scale s, on whole device pixels; pixel-exact sizes stay unsmoothed.
function drawPin(g, layer, p, x, y, s = 1) {
  const size = PIN_SIZE[layer] * s,
    rect = ICONS?.[iconOf(layer, p)];
  if (!iconSheet || !rect) {
    g.beginPath();
    g.arc(x, y, 6 * s, 0, Math.PI * 2);
    g.fillStyle = "#eac985";
    g.fill();
    g.strokeStyle = "#182324";
    g.stroke();
    return;
  }
  const [sx, sy, sw, sh] = rect;
  if (TINTED.has(layer) && FACTION[p.faction])
    g.drawImage(
      glow(p.faction),
      x - size * 0.65,
      y - size * 0.65,
      size * 1.3,
      size * 1.3,
    );
  const k = size / Math.max(sw, sh),
    w = sw * k,
    ht = sh * k;
  g.imageSmoothingEnabled = !Number.isInteger(k * dpr);
  g.imageSmoothingQuality = "high";
  g.drawImage(
    iconSheet,
    sx,
    sy,
    sw,
    sh,
    snap(x - w / 2),
    snap(y - ht / 2),
    w,
    ht,
  );
}
// Like the addon's compact pill: three slots, with +N replacing the last
// when crowded. Membership is returned by the settled request, never rebuilt
// while painting a gesture or flyover frame.
function groupLayout(p, s = 1) {
  const more = p.count > 3, icons = more ? 2 : p.count;
  const moreWidth = more ? Math.max(15, String(p.count - icons).length * 6 + 7) : 0;
  return { icons, more, moreWidth: moreWidth * s,
    width: (4 + icons * 12 + (icons - 1) + (more ? moreWidth + 1 : 0)) * s, height: 14 * s };
}
function pinBox(p, x, y, s = 1) {
  const { width, height } = p.kind === "group"
    ? groupLayout(p, s)
    : { width: PIN_SIZE[p.layer] * s, height: PIN_SIZE[p.layer] * s };
  return [x - width / 2, y - height / 2, x + width / 2, y + height / 2,
    p.kind === "group" ? "group" : p.layer];
}
function drawMapPin(g, p, x, y, s = 1) {
  if (p.kind !== "group") return drawPin(g, p.layer, p, x, y, s);
  const { icons, more, moreWidth, width, height } = groupLayout(p, s);
  const left = x - width / 2;
  g.save();
  g.beginPath();
  g.roundRect(left, y - height / 2, width, height, 3 * s);
  g.fillStyle = "rgba(0,0,0,.35)";
  g.fill();
  for (let i = 0; i < icons; i++) {
    const member = p.members[i];
    drawPin(g, member.layer, member, left + (8 + i * 13) * s, y, 12 * s / PIN_SIZE[member.layer]);
  }
  if (more) {
    g.font = `600 ${9 * s}px system-ui,sans-serif`;
    g.textAlign = "center";
    g.textBaseline = "middle";
    g.fillStyle = "#fff2d4";
    g.fillText(`+${p.count - icons}`, left + width - 2 * s - moreWidth / 2, y);
  }
  g.restore();
}
// A fine cross marks highlighted database locations without obscuring the map.
function drawRing(g, x, y, s = 1) {
  g.beginPath();
  g.moveTo(x - 5 * s, y);
  g.lineTo(x + 5 * s, y);
  g.moveTo(x, y - 5 * s);
  g.lineTo(x, y + 5 * s);
  g.lineWidth = 2.3 * s;
  g.strokeStyle = "#10201b66";
  g.stroke();
  g.lineWidth = 1.2 * s;
  g.strokeStyle = "#f5deb3b3";
  g.stroke();
}
// Highlighted spawns (and, for a flight point, lines to where it flies).
function drawHighlight() {
  if (highlight.from) {
    const [x0, y0] = toScreen(...highlight.from);
    ctx.beginPath();
    for (const p of highlight.pts) {
      const [x, y] = toScreen(p.col, p.row);
      ctx.moveTo(x0, y0);
      ctx.lineTo(x, y);
    }
    ctx.setLineDash([6, 5]);
    ctx.lineWidth = 2.5;
    ctx.strokeStyle = "rgba(12,8,4,.25)";
    ctx.stroke(); // dark casing
    ctx.lineWidth = 1;
    ctx.strokeStyle = "rgba(245,222,179,.6)";
    ctx.stroke();
    ctx.setLineDash([]);
  }
  const s = highlight.pts.length > 40 ? 0.65 : 1; // many: smaller crosses
  for (const p of highlight.pts) {
    const [x, y] = toScreen(p.col, p.row);
    if (x < -20 || x > W + 20 || y < -20 || y > H + 20) continue;
    drawRing(ctx, x, y, s);
  }
}
// The pin (or highlighted spawn) under a point, if any: the nearest within a finger's reach.
function pinAt(x, y, reach) {
  let best = null,
    bd = reach;
  const consider = (p) => {
    const [px, py] = toScreen(p.col, p.row),
      box = p.kind === "group" ? pinBox(p, px, py) : [px, py, px, py],
      d = Math.hypot(Math.max(box[0] - x, 0, x - box[2]), Math.max(box[1] - y, 0, y - box[3]));
    if (d <= bd) {
      bd = d;
      best = p;
    }
  };
  if (highlight) highlight.pts.forEach(consider);
  if (!best) drawnPins.forEach((p) => pinVisible(p) && consider(p));
  return best;
}

// Pins for the view, once it settles: only layers shown at this zoom.
let pinTimer,
  pinSeq = 0,
  pinLimitMessage = "";
function refreshPins() {
  clearTimeout(pinTimer);
  const ticket = requests.ticket("pins");
  pinTimer = setTimeout(
    run(async () => {
      const want = LAYERS.filter((l) => shown(l[0]))
          .map((l) => l[0])
          .reverse(),
        seq = ++pinSeq; // dense layers drawn first, under
      renderLayers();
      if (!want.length) {
        pins = [];
        if (pinLimitMessage && $("status").textContent === pinLimitMessage) notice("");
        pinLimitMessage = "";
        draw();
        return;
      }
      const [c0, r0, c1, r1] = view();
      const got = await get(
        `/api/pins?c0=${c0}&r0=${r0}&c1=${c1}&r1=${r1}&zoom=${state.camera.zoom}&layers=${want.join(",")}&groups=1`,
      );
      if (seq === pinSeq && requests.current(ticket)) {
        pins = Array.isArray(got) ? got : got.pins;
        if (pinLimitMessage && $("status").textContent === pinLimitMessage) notice("");
        pinLimitMessage = got.omitted ? `${got.omitted} more database locations in this view. Zoom in to see them.` : "";
        if (pinLimitMessage) notice(pinLimitMessage);
        draw();
      }
    }),
    200,
  );
}
function settled() {
  if (!state.camera || !requests) return;
  if (out3D) leave3D();
  refreshWalk();
  refreshPins();
  saveView();
  settleReadout();
}
