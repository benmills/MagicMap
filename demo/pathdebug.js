// Pathing debug (Advanced > Pathing Debug; tools=path in the link): the addon's walk grid and route search, shown
// to find where they're wrong. While it's on, the walk grid is always drawn, a tap sets a route's ends (start, then
// goal; a third starts again) and runs the addon's own search on them (atlas/Route.lua via /api/route), the map
// zooms in much closer (PATH_ZOOM: a 4-yd square some 40 px), and a panel in the top left holds the layers, the
// route's numbers and, under the mouse, the cell and square it's over. Layers (the panel's menu, remembered in this
// browser): each chunk's class, the crossings it lacks, cut-off pockets (regions other than the map's biggest:
// Data/WalkRegions.lua), the connectors (tools/walk_links.json), the 4-yd squares under each chunk (baked by
// demo/export_walkquads.py; their slope by a rule and a limit you pick, to try another than gen_walk's), and the
// search: every node it closed (dark to bright, in order), its node path, the addon's line, its box.
//
// A/B: two walks, 3.1's (v=31: demo/walk31, frozen) and the proposal's (v=2: the tree's atlas). The panel's toggle
// picks the one drawn (grid and route); a route runs on both and the panel puts their numbers side by side. 3.1's
// nodes are chunks (filled squares); v2's are parts of chunks (dots at their positions, edges between them). The
// side and the route's ends are in the link (pv, pa, pb: view-state.mjs), so a link opens a case. Cases
// (walk_cases.json) and a sweep's table (walk_sweep.json, if there is one) are in the panel: a click runs one.
const PATH_LAYERS = [
  ["cells", "Cell classes", true],
  ["crossings", "Missing crossings (black edges; 3.1)", true],
  ["parts", "Parts and their edges (v2)", true],
  ["regions", "Cut-off pockets", true],
  ["links", "Connectors", true],
  ["quads", "4-yd squares (zoom in)", true],
  ["searched", "Nodes searched", true],
  ["astar", "A*'s node path", true],
  ["abstract", "The tile-graph path (v2)", true],
  ["line", "The addon's line", true],
  ["box", "Search box", false],
  ["dim", "Dim the map", false],
];
const PATH_SIDES = [["31", "3.1"], ["2", "v2"]];
const CELL_FILL = ["rgba(255,65,65,.35)", "rgba(50,210,110,.16)", "rgba(60,150,255,.3)", "rgba(255,145,30,.45)"];
const NODE_FILL = ["#ff5a5a", "#4fe08a", "#5aa8ff", "#ffa040"];
const CLASS_NAMES = ["blocked", "land", "water", "magma/slime"];
const QUAD_MIN_ZOOM = 640; // px a tile: a square 5 px, its layer worth drawing
const PARTS_MIN_ZOOM = 768; // px a tile: a chunk 48 px, its parts and edges worth drawing
const pathPrefs = (() => {
  const p = { layers: Object.fromEntries(PATH_LAYERS.map(([k, , on]) => [k, on])), rule: "plane", max: 60 };
  try {
    Object.assign(p, JSON.parse(localStorage.getItem("mm.pathDebug") || "{}"));
  } catch {}
  return p;
})();
const savePathPrefs = () => {
  try {
    localStorage.setItem("mm.pathDebug", JSON.stringify(pathPrefs));
  } catch {}
};
const layer = (k) => pathPrefs.layers[k] !== false;
let walkTimer,
  pathSide = "2", // the walk drawn: "31" or "2"
  routePoints = [],
  routeGot = null, // { "31": /api/route's answer, "2": … } as each arrives
  pathCases = null, // walk_cases.json, walk_sweep.json: null not asked yet, false none
  pathSweep = null;
const pathOn = () => state.tools.has("path");

// The link's part (view-state.mjs pv, pa, pb), and a link's restored.
const pathLink = () => (pathOn() ? { v: pathSide, points: routePoints } : null);
function pathRestore(p) {
  if (!p) return;
  pathSide = p.v;
  routePoints = pathOn() ? p.points.slice(0, 2) : [];
  routeGot = null;
  renderPathPanel();
  if (pathOn()) {
    refreshWalk();
    if (routePoints.length === 2) findRoute();
  }
}

// The walk grid around the view (/api/walk: classes, regions, connectors; v2's parts), fetched once the view settles.
function refreshWalk() {
  clearTimeout(walkTimer);
  const ticket = requests.ticket("walk");
  if (!pathOn()) {
    walk = null;
    return;
  }
  walkTimer = setTimeout(
    run(async () => {
      const q = view().map((v, i) => clamp(Math.floor(v * CHUNKS) + (i > 1 ? 1 : 0), 0, (i % 2 ? 64 : 128) * CHUNKS)); // (the world is wider than a map: the Eastern Kingdoms at +45)
      if ((q[2] - q[0]) * (q[3] - q[1]) > 40000) {
        walk = null;
        draw();
        notice("Zoom in for the walk grid (at most 40,000 cells).");
        return;
      }
      const got = await get(`/api/walk?c0=${q[0]}&r0=${q[1]}&c1=${q[2]}&r1=${q[3]}&v=${pathSide}`);
      if (requests.current(ticket) && pathOn()) {
        walk = got.error ? null : got;
        if (got.error) notice(got.error);
        draw();
      }
    }),
    150,
  );
}
// A chunk's cell: 3.1's { v (class + 4 east + 8 south), region }, or v2's { cls, parts }.
const walkAt = (gc, gr) => {
  const j = gr - walk?.r0, i = gc - walk?.c0;
  if (!walk || j < 0 || i < 0 || j >= walk.rows.length || i >= walk.rows[0].length) return null;
  if (walk.api === "2") return { cls: parseInt(walk.rows[j][i], 16), parts: parseInt(walk.parts[j][i], 16) };
  return { v: parseInt(walk.rows[j][i], 16), region: walk.regions[j][i] };
};

// The 4-yd squares: a world tile's bytes (demo/export_walkquads.py), and drawn once to a 128 px canvas a square a
// pixel, again only when the slope rule or limit changes.
const quadTiles = new Map(); // world tile key -> { bytes, canvas, drawnFor } | "loading" | null (none baked)
let quadsMissing = false;
function quadTile(col, row) {
  const key = col * 64 + row;
  if (quadTiles.has(key)) return quadTiles.get(key);
  const t = tiles.find((x) => x.key === key);
  if (!t) {
    quadTiles.set(key, null);
    return null;
  }
  quadTiles.set(key, "loading");
  fetch(`walkquads/${t.inst}/${t.src}.bin`)
    .then(async (r) => {
      if (!r.ok) throw Error(r.status);
      const raw = new Response(r.body.pipeThrough(new DecompressionStream("gzip")));
      quadTiles.set(key, { bytes: new Uint8Array(await raw.arrayBuffer()), inst: t.inst, src: t.src });
      draw();
    })
    .catch(() => {
      quadTiles.set(key, null);
      quadsMissing = true;
      renderPathPanel();
    });
  return "loading";
}
const steepOf = (b, i) => b[i + (pathPrefs.rule === "plane" ? 1 : 2)];
function quadCanvas(q) {
  const want = `${pathPrefs.rule}/${pathPrefs.max}`;
  if (q.canvas && q.drawnFor === want) return q.canvas;
  const c = (q.canvas ||= document.createElement("canvas"));
  c.width = c.height = 128;
  const g = c.getContext("2d"),
    img = g.createImageData(128, 128),
    b = q.bytes;
  for (let ch = 0; ch < 256; ch++)
    for (let k = 0; k < 64; k++) {
      const i = (ch * 64 + k) * 3,
        x = (ch % 16) * 8 + (k % 8),
        y = Math.floor(ch / 16) * 8 + Math.floor(k / 8),
        o = (y * 128 + x) * 4,
        f = b[i];
      let rgba = null;
      if (f === 255) rgba = null;
      else if (f & 4) rgba = [200, 40, 220, 170]; // a hole: no ground
      else if (f & 2) rgba = [255, 140, 20, 150];
      else if (f & 1) rgba = [40, 110, 255, 120];
      else if (steepOf(b, i) > pathPrefs.max) rgba = [235, 30, 30, 140];
      if (rgba) img.data.set(rgba, o);
    }
  g.putImageData(img, 0, 0);
  q.drawnFor = want;
  return c;
}

function drawPathDebug() {
  const s = 1 / CHUNKS,
    zoom = state.camera.zoom,
    quadsOn = layer("quads") && zoom >= QUAD_MIN_ZOOM,
    v2 = walk?.api === "2";
  if (layer("dim")) {
    ctx.fillStyle = "rgba(0,0,0,.45)";
    ctx.fillRect(0, 0, W, H);
  }
  const cell = (gc, gr) => {
    const [x0, y0] = toScreen(gc * s, gr * s),
      [x1, y1] = toScreen((gc + 1) * s, (gr + 1) * s);
    return [x0, y0, x1, y1];
  };
  const off = (x, y, m = 0) => x < -m || y < -m || x > W + m || y > H + m;
  if (walk) {
    ctx.save();
    ctx.globalAlpha = quadsOn ? 0.35 : 1;
    walk.rows.forEach((row, j) => {
      for (let i = 0; i < row.length; i++) {
        const v = parseInt(row[i], 16),
          [x0, y0, x1, y1] = cell(walk.c0 + i, walk.r0 + j);
        if (x0 > W || y0 > H || x1 < 0 || y1 < 0) continue;
        if (layer("cells")) {
          ctx.fillStyle = CELL_FILL[v % 4];
          ctx.fillRect(x0, y0, x1 - x0, y1 - y0);
        }
        const rg = v2 ? 0 : walk.regions[j][i];
        if (layer("regions") && rg > 1) {
          ctx.fillStyle = `hsla(${(rg * 137) % 360},90%,60%,.45)`;
          ctx.fillRect(x0, y0, x1 - x0, y1 - y0);
        }
      }
    });
    ctx.restore();
  }
  if (quadsOn) {
    ctx.save();
    ctx.imageSmoothingEnabled = false;
    const [c0, r0, c1, r1] = view();
    for (let col = Math.floor(c0); col < Math.ceil(c1); col++)
      for (let row = Math.floor(r0); row < Math.ceil(r1); row++) {
        const q = quadTile(col, row);
        if (!q || q === "loading") continue;
        const [x0, y0] = toScreen(col, row),
          [x1, y1] = toScreen(col + 1, row + 1);
        ctx.drawImage(quadCanvas(q), x0, y0, x1 - x0, y1 - y0);
      }
    ctx.restore();
  }
  if (walk && !v2) {
    if (layer("crossings")) {
      ctx.strokeStyle = "rgba(0,0,0,.75)";
      ctx.lineWidth = zoom >= 1024 ? 2.5 : 1;
      ctx.beginPath();
      walk.rows.forEach((row, j) => {
        for (let i = 0; i < row.length; i++) {
          const v = parseInt(row[i], 16);
          if (!(v & 3)) continue;
          const [x0, y0, x1, y1] = cell(walk.c0 + i, walk.r0 + j);
          if (x0 > W || y0 > H || x1 < 0 || y1 < 0) continue;
          if (!(v & 4)) {
            ctx.moveTo(x1, y0);
            ctx.lineTo(x1, y1);
          }
          if (!(v & 8)) {
            ctx.moveTo(x0, y1);
            ctx.lineTo(x1, y1);
          }
        }
      });
      ctx.stroke();
    }
    if (layer("regions") && zoom >= 1024) {
      ctx.font = "11px system-ui";
      ctx.fillStyle = "#fff";
      walk.rows.forEach((row, j) => {
        for (let i = 0; i < row.length; i++) {
          const rg = walk.regions[j][i];
          if (rg <= 1) continue;
          const [x0, y0] = cell(walk.c0 + i, walk.r0 + j);
          if (x0 > -20 && y0 > -20 && x0 < W && y0 < H) ctx.fillText(`r${rg}`, x0 + 3, y0 + 12);
        }
      });
    }
  }
  if (walk && v2 && layer("parts") && zoom >= PARTS_MIN_ZOOM && walk.graph) {
    // v2's parts graph: two-way edges grey, one-way (drops) red with an arrowhead; each part a dot, its class's
    // colour, ringed in its region's when that's a cut-off pocket.
    ctx.lineWidth = 1.2;
    for (const [ax, ay, bx, by, , oneway] of walk.edges) {
      const a = toScreen(ax, ay), b = toScreen(bx, by);
      if (off(...a, 200) && off(...b, 200)) continue;
      ctx.strokeStyle = oneway ? "rgba(255,90,90,.85)" : "rgba(235,235,235,.55)";
      ctx.beginPath();
      ctx.moveTo(...a);
      ctx.lineTo(...b);
      ctx.stroke();
      if (oneway) {
        const t = Math.atan2(b[1] - a[1], b[0] - a[0]), m = [(a[0] + b[0] * 2) / 3, (a[1] + b[1] * 2) / 3];
        ctx.fillStyle = "rgba(255,90,90,.95)";
        ctx.beginPath();
        ctx.moveTo(m[0] + 7 * Math.cos(t), m[1] + 7 * Math.sin(t));
        ctx.lineTo(m[0] + 6 * Math.cos(t + 2.5), m[1] + 6 * Math.sin(t + 2.5));
        ctx.lineTo(m[0] + 6 * Math.cos(t - 2.5), m[1] + 6 * Math.sin(t - 2.5));
        ctx.fill();
      }
    }
    ctx.font = "11px system-ui";
    for (const [, x, y, cls, rg, p] of walk.nodes) {
      const [sx, sy] = toScreen(x, y);
      if (off(sx, sy, 10)) continue;
      ctx.beginPath();
      ctx.arc(sx, sy, 4, 0, 2 * Math.PI);
      ctx.fillStyle = NODE_FILL[cls % 4];
      ctx.fill();
      if (layer("regions") && rg > 1) {
        ctx.strokeStyle = `hsl(${(rg * 137) % 360},90%,60%)`;
        ctx.lineWidth = 2.5;
        ctx.stroke();
        if (zoom >= 1536) {
          ctx.fillStyle = "#fff";
          ctx.fillText(`r${rg}`, sx + 6, sy - 5);
        }
      }
      if (zoom >= 3072) {
        ctx.fillStyle = "rgba(255,255,255,.8)";
        ctx.fillText(String(p), sx + 6, sy + 10);
      }
    }
  }
  if (walk && layer("links"))
    for (const l of walk.links) {
      const a = toScreen((l.a[0] + 0.5) * s, (l.a[1] + 0.5) * s),
        b = toScreen((l.b[0] + 0.5) * s, (l.b[1] + 0.5) * s);
      ctx.strokeStyle = "#d58cff";
      ctx.lineWidth = 3;
      ctx.setLineDash([2, 4]);
      ctx.beginPath();
      ctx.moveTo(...a);
      ctx.lineTo(...b);
      ctx.stroke();
      ctx.setLineDash([]);
      for (const p of [a, b]) {
        ctx.beginPath();
        ctx.arc(...p, 5, 0, 2 * Math.PI);
        ctx.fillStyle = "#d58cff";
        ctx.fill();
      }
      ctx.font = "12px system-ui";
      ctx.fillStyle = "#f3dcff";
      ctx.fillText(l.name + (l.oneway ? " (one way)" : ""), (a[0] + b[0]) / 2 + 8, (a[1] + b[1]) / 2);
    }
  const g = routeGot?.[pathSide];
  if (g && !g.error) {
    // 3.1's nodes are chunks (each point a chunk's centre: its square filled); v2's are parts (a dot each).
    const chunky = g.api !== "2";
    const mark = ([x, y], r = 3) => {
      if (chunky) {
        const [x0, y0, x1, y1] = cell(Math.floor(x * CHUNKS), Math.floor(y * CHUNKS));
        if (x0 > W || y0 > H || x1 < 0 || y1 < 0) return;
        ctx.fillRect(x0, y0, Math.max(1, x1 - x0), Math.max(1, y1 - y0));
      } else {
        const [sx, sy] = toScreen(x, y);
        if (off(sx, sy, 10)) return;
        ctx.beginPath();
        ctx.arc(sx, sy, r, 0, 2 * Math.PI);
        ctx.fill();
      }
    };
    const polyline = (ps) => {
      ctx.beginPath();
      ps.forEach((p, i) => (i ? ctx.lineTo(...toScreen(...p)) : ctx.moveTo(...toScreen(...p))));
    };
    const n = g.closed.length;
    if (layer("searched"))
      for (let i = 0; i < n; i++) {
        ctx.fillStyle = `hsla(${230 - (i / n) * 180},80%,55%,${chunky ? 0.28 : 0.6})`;
        mark(g.closed[i], 3);
      }
    if (layer("box") && g.box) {
      const [bx0, by0] = toScreen(g.box[0], g.box[1]),
        [bx1, by1] = toScreen(g.box[2], g.box[3]);
      ctx.setLineDash([4, 4]);
      ctx.strokeStyle = "rgba(255,255,255,.6)";
      ctx.lineWidth = 1;
      ctx.strokeRect(bx0, by0, bx1 - bx0, by1 - by0);
      ctx.setLineDash([]);
    }
    if (layer("astar")) {
      ctx.fillStyle = "rgba(90,235,255,.55)";
      if (chunky) for (const p of g.raw) mark(p);
      else {
        polyline(g.raw);
        ctx.strokeStyle = "rgba(90,235,255,.8)";
        ctx.lineWidth = 3;
        ctx.stroke();
        for (const p of g.raw) mark(p, 3.5);
      }
    }
    if (layer("abstract") && g.abstract) {
      polyline(g.abstract);
      ctx.strokeStyle = "rgba(255,80,220,.85)";
      ctx.lineWidth = 2;
      ctx.setLineDash([3, 3]);
      ctx.stroke();
      ctx.setLineDash([]);
      ctx.fillStyle = "#ff50dc";
      for (const p of g.abstract) {
        const [sx, sy] = toScreen(...p);
        ctx.fillRect(sx - 4, sy - 4, 8, 8);
      }
    }
    if (layer("line") && g.way.length) {
      polyline(g.way);
      ctx.strokeStyle = "rgba(20,12,4,.8)";
      ctx.lineWidth = 5;
      ctx.stroke();
      polyline(g.way);
      ctx.strokeStyle = g.partial ? "#ff9a3c" : "#ffd24c";
      ctx.lineWidth = 2.5;
      ctx.setLineDash([8, 5]);
      ctx.stroke();
      ctx.setLineDash([]);
      ctx.fillStyle = "#fff";
      for (const p of g.turns.slice(1, -1)) {
        const [x, y] = toScreen(...p);
        ctx.fillRect(x - 2, y - 2, 4, 4);
      }
    }
    ctx.strokeStyle = "#fff";
    ctx.lineWidth = 1.5;
    for (const [x, y] of [...g.snapped, ...(g.instead ? [g.instead] : [])]) {
      if (chunky) {
        const [x0, y0, x1, y1] = cell(Math.floor(x * CHUNKS), Math.floor(y * CHUNKS));
        ctx.strokeRect(x0, y0, x1 - x0, y1 - y0);
      } else {
        ctx.beginPath();
        ctx.arc(...toScreen(x, y), 8, 0, 2 * Math.PI);
        ctx.stroke();
      }
    }
  }
  for (const p of routePoints) drawRing(ctx, ...toScreen(...p), 0.6);
}

// A tap: a route's start, then its goal (a third starts again).
function pathTap(x, y) {
  const [c, r] = toTile(x, y);
  routePoints.push([c, r]);
  if (routePoints.length > 2) routePoints = [[c, r]];
  routeGot = null;
  renderPathPanel();
  draw();
  saveView();
  if (routePoints.length === 2) findRoute();
}
// The route on both walks, each drawn as it comes.
function findRoute() {
  const [[c0, r0], [c1, r1]] = routePoints,
    ticket = requests.ticket("route"),
    got = (routeGot = {});
  renderPathPanel();
  for (const [v] of PATH_SIDES)
    get(`/api/route?c0=${c0}&r0=${r0}&c1=${c1}&r1=${r1}&v=${v}`)
      .catch((e) => (e.name === "AbortError" ? null : { error: e.message || String(e) }))
      .then((answer) => {
        if (!answer || !requests.current(ticket) || routeGot !== got) return;
        got[v] = answer;
        renderPathPanel();
        draw();
      });
}
// The A/B toggle: the other walk drawn, the route kept (both sides' answers are in already).
function pathShow(v) {
  if (v === pathSide) return;
  pathSide = v;
  walk = null;
  refreshWalk();
  renderPathPanel();
  draw();
  saveView();
}

// What's under the mouse: its map, chunk and square.
let hoverFrame = 0,
  hoverAt = null;
function pathHover(x, y) {
  hoverAt = toTile(x, y);
  if (!hoverFrame)
    hoverFrame = requestAnimationFrame(() => {
      hoverFrame = 0;
      renderHover();
    });
}
function renderHover() {
  const el = $("pathHover");
  if (!hoverAt) return void (el.textContent = "");
  const [c, r] = hoverAt,
    col = Math.floor(c),
    row = Math.floor(r),
    gc = Math.floor(c * CHUNKS),
    gr = Math.floor(r * CHUNKS),
    t = tiles.find((x) => x.key === col * 64 + row),
    w = walkAt(gc, gr);
  if (!t) return void (el.textContent = "Off the map.");
  const dc = col - Math.floor(t.src / 64),
    dr = row - (t.src % 64),
    real = [gc - dc * CHUNKS, gr - dr * CHUNKS];
  const name = world.parts.find((p) => p.inst === t.inst)?.name || `map ${t.inst}`;
  let text = `${name} · chunk ${real[0]}, ${real[1]} · tile ${(c - dc).toFixed(3)}, ${(r - dr).toFixed(3)}`;
  if (w && "v" in w)
    text += `\n${CLASS_NAMES[w.v % 4]} · crosses east ${w.v & 4 ? "yes" : "no"}, south ${w.v & 8 ? "yes" : "no"} · ${w.region ? (w.region === 1 ? "main region" : `cut-off pocket r${w.region}`) : "nowhere to stand"}`;
  else if (w) {
    text += `\n${CLASS_NAMES[w.cls % 4]} (its biggest part) · ${w.parts} part${w.parts === 1 ? "" : "s"}`;
    const here = (walk.nodes || []).filter((n) => n[6] === gc && n[7] === gr);
    for (const [id, , , cls, rg, p] of here)
      text += `\n  part ${p} (node ${id}): ${CLASS_NAMES[cls % 4]} · ${rg ? (rg === 1 ? "main region" : `region r${rg}`) : "no region"}`;
  }
  const q = quadTiles.get(col * 64 + row);
  if (q && q !== "loading") {
    const qx = Math.floor((c - col) * 128),
      qy = Math.floor((r - row) * 128),
      i = ((Math.floor(qy / 8) * 16 + Math.floor(qx / 8)) * 64 + (qy % 8) * 8 + (qx % 8)) * 3,
      f = q.bytes[i];
    if (f !== 255)
      text += `\nsquare ${qx % 8}, ${qy % 8}: slope ${q.bytes[i + 1]}° (plane), steepest triangle ${q.bytes[i + 2]}°${f & 1 ? " · deep water" : ""}${f & 2 ? " · magma/slime" : ""}${f & 4 ? " · terrain hole" : ""}`;
  }
  el.textContent = text;
}

// The route's numbers, both walks side by side (the one drawn highlighted), then the drawn one's details.
const sideName = (v) => PATH_SIDES.find(([k]) => k === v)[1];
function routeNumbers(g) {
  const yd = (v) => `${Math.round(v).toLocaleString()} yd`;
  if (!g) return { result: "…", yards: "", ratio: "", nodes: "", ms: "" };
  if (g.error) return { result: "error", yards: "", ratio: "", nodes: "", ms: "" };
  return {
    result: (!g.found ? "no way" : g.partial ? "partial" : "found") + (g.capped ? ", capped" : ""),
    yards: g.found ? yd(g.yards) : "–",
    ratio: g.ratio != null ? `×${g.ratio.toFixed(2)}` : "–",
    nodes: g.nodes.toLocaleString() + (g.nodes2 != null ? ` + ${g.nodes2.toLocaleString()} L2` : ""),
    ms: `${g.ms} ms`,
  };
}
function renderPathPanel() {
  const panel = $("pathDebug");
  panel.hidden = !pathOn();
  if (!pathOn()) return;
  for (const b of $("pathAB").querySelectorAll("button")) b.setAttribute("aria-pressed", String(b.dataset.v === pathSide));
  const el = $("pathRoute");
  el.replaceChildren();
  const hint = quadsMissing ? " The 4-yd squares aren't baked here (demo/export_walkquads.py)." : "";
  if (routePoints.length < 2) {
    el.textContent = (routePoints.length ? "Tap where to go." : "Tap where to start, then where to go.") + hint;
    renderCases();
    return;
  }
  if (!routeGot) return renderCases();
  const nums = Object.fromEntries(PATH_SIDES.map(([v]) => [v, routeNumbers(routeGot[v])]));
  const table = h("table", { className: "ab" },
    h("thead", {}, h("tr", {}, h("th", {}), ...PATH_SIDES.map(([v, label]) =>
      h("th", { className: v === pathSide ? "shown" : "" }, label)))),
    h("tbody", {}, ...[["Result", "result"], ["Distance", "yards"], ["vs straight", "ratio"], ["Searched", "nodes"], ["Time", "ms"]].map(
      ([label, k]) => h("tr", {}, h("th", {}, label), ...PATH_SIDES.map(([v]) =>
        h("td", { className: v === pathSide ? "shown" : "" }, nums[v][k]))))));
  el.append(table);
  const g = routeGot[pathSide];
  if (g) {
    const yd = (v) => `${Math.round(v).toLocaleString()} yd`;
    const rows = g.error
      ? [["Error", g.error]]
      : [
          ["Result", (!g.found
            ? "No way: the addon draws a straight line."
            : g.partial
              ? "Partial: as near as it gets, then straight on (orange)."
              : "Found.") + (g.capped ? ` Gave up at ${g.maxNodes.toLocaleString()} nodes.` : "")],
          ...(g.regions
            ? [["Regions", `start r${g.regions[0]}, goal r${g.regions[1]}: no walk joins them, so no search${g.instead ? "; routed to the nearest node in yours" : ", none near enough"}`]]
            : []),
          ["Searched", `${g.nodes.toLocaleString()} nodes, ${g.ms} ms here (in game ~${Math.max(1, Math.round(g.nodes / 25 / 60))} s at 1 ms a frame)`],
          ["Straight", yd(g.straight)],
          ["Path", `${g.raw.length} nodes, ${Math.max(0, g.turns.length - 2)} turns${g.abstract ? `; tile graph ${g.abstract.length} nodes` : ""}`],
        ];
    const dl = h("dl", {});
    for (const [k, v] of rows) dl.append(h("dt", {}, k), h("dd", {}, v));
    el.append(h("p", { className: "drawn" }, `Drawn: ${sideName(pathSide)}`), dl);
    if (pathSide === "2" && g.api && g.api !== "2")
      el.append(h("p", {}, "v2's runtime isn't in the tree yet: v2 is the tree's walk on 3.1's API (the same as 3.1 until it lands)."));
  }
  if (hint) el.append(h("p", {}, hint));
  renderCases();
}

// Cases (walk_cases.json) and a sweep (walk_sweep.json: tools/walk_sweep.py --json): fetched once the panel opens.
// Their points are each map's own tile coordinates (Route.Find's, as tools/walk_cases.json has them: moved here by
// the map's offset), or the world's as /api/route takes them with "space": "world" at the top of the file.
function loadCases() {
  if (pathCases !== null) return;
  pathCases = pathSweep = false;
  const json = (path) => fetch(path, { cache: "no-cache" }).then((r) => (r.ok ? r.json() : false)).catch(() => false);
  Promise.all([json("walk_cases.json"), json("walk_sweep.json")]).then(([c, s]) => {
    pathCases = c;
    pathSweep = s;
    renderCases();
  });
}
function onWorld(inst, p, space) {
  if (space === "world") return p;
  const [dx, dy] = world.parts.find((x) => x.inst === inst)?.offset || [0, 0];
  return [p[0] + dx, p[1] + dy];
}
function runCase(inst, a, b, space) {
  a = onWorld(inst, a, space);
  b = onWorld(inst, b, space);
  routePoints = [a, b];
  routeGot = null;
  const goal = viewState.fitBounds(
    [Math.min(a[0], b[0]), Math.min(a[1], b[1]), Math.max(a[0], b[0]), Math.max(a[1], b[1])], W, H, 0.6);
  flyTo(goal, 500);
  findRoute();
  draw();
  saveView();
}
const fmt = (v) =>
  v == null
    ? ""
    : Array.isArray(v)
      ? v.map(fmt).join(", ")
      : typeof v === "object"
        ? JSON.stringify(v)
        : typeof v === "number" && !Number.isInteger(v)
          ? v.toFixed(2)
          : String(v);
function renderCases() {
  const box = $("pathCases");
  if (!pathOn() || !box) return;
  loadCases();
  const list = $("pathCaseList");
  list.replaceChildren();
  const cases = pathCases?.cases || (Array.isArray(pathCases) ? pathCases : []);
  box.hidden = !cases.length && !pathSweep;
  box.querySelector("summary").title = pathCases?.about || ""; // (the file's notes: on hover, not in the way)
  const recorded = (r) => r && [r.result, r.yards != null && `${Math.round(r.yards)} yd`, r.ratio != null && `×${fmt(r.ratio)}`, r.nodes != null && `${r.nodes} nodes`].filter(Boolean).join(" · ");
  for (const c of cases) {
    const b = h("button", { className: "case", title: c.note || "" },
      h("b", {}, c.name || "case"),
      c.note ? h("span", {}, c.note) : null,
      c.v31 ? h("span", { className: "rec" }, `3.1: ${recorded(c.v31)}`) : null,
      c.v2 ? h("span", { className: "rec" }, `v2: ${recorded(c.v2)}`) : null);
    b.onclick = () => runCase(c.inst, c.a, c.b, pathCases.space);
    list.append(b);
  }
  const sweep = $("pathSweep");
  sweep.replaceChildren();
  sweep.hidden = !pathSweep;
  if (!pathSweep) return;
  // Rows as arrays under "columns", or as tools/walk_sweep.py writes them: objects (name, inst, a, b, kind, zone, …)
  // with s[side] = an array under "columns" (one set of columns a side).
  const rows = pathSweep.rows || [],
    cols = pathSweep.columns || [],
    sides = [...new Set(rows.flatMap((r) => (r && !Array.isArray(r) && r.s ? Object.keys(r.s) : [])))],
    flat = ["name", "inst", "kind", "zone"].filter((k) => rows.some((r) => r && !Array.isArray(r) && k in r)),
    head = rows.some((r) => !Array.isArray(r)) ? [...flat, ...sides.flatMap((s) => cols.map((c) => `${s} ${c}`))] : cols,
    cells = (r) => (Array.isArray(r) ? r : [...flat.map((k) => r[k]), ...sides.flatMap((s) => cols.map((_, i) => r.s?.[s]?.[i]))]),
    ends = (r) => {
      if (!Array.isArray(r)) return [r.inst, r.a, r.b];
      const at = (k) => r[cols.indexOf(k)];
      return [at("inst"), at("a"), at("b")];
    };
  sweep.append(h("summary", {}, `Sweep (${rows.length} rows)`));
  const about = pathSweep.about;
  if (about) sweep.append(h("p", {}, typeof about === "string" ? about : Object.entries(about).map(([k, v]) => `${k}: ${typeof v === "object" ? JSON.stringify(v) : v}`).join(" · ")));
  if (pathSweep.summary) {
    const dl = h("dl", {});
    for (const [k, v] of Object.entries(pathSweep.summary))
      dl.append(h("dt", {}, k), h("dd", {}, typeof v === "object" && v && !Array.isArray(v)
        ? Object.entries(v).map(([a, b]) => `${a}: ${typeof b === "object" && b && !Array.isArray(b) ? Object.entries(b).map(([c, d]) => `${c} ${fmt(d)}`).join(", ") : fmt(b)}`).join(" · ")
        : fmt(v)));
    sweep.append(dl);
  }
  const table = h("table", {},
    h("thead", {}, h("tr", {}, ...head.map((c) => h("th", {}, c)))),
    h("tbody", {}, ...rows.map((row) => {
      const tr = h("tr", { title: (!Array.isArray(row) && row.note) || "" }, ...cells(row).map((v) => h("td", {}, fmt(v)))),
        [inst, a, b] = ends(row);
      if (Array.isArray(a) && Array.isArray(b)) {
        tr.className = "go";
        tr.onclick = () => runCase(inst, a, b, pathSweep.space);
      }
      return tr;
    })));
  sweep.append(h("div", { className: "scroll" }, table));
}

function renderPathMenu() {
  const box = $("pathLayers");
  box.replaceChildren();
  for (const [k, label] of PATH_LAYERS) {
    const input = h("input", { type: "checkbox", checked: layer(k) });
    input.onchange = () => {
      pathPrefs.layers[k] = input.checked;
      savePathPrefs();
      draw();
    };
    box.append(h("label", { className: "row" }, input, h("span", {}, label)));
  }
  const rule = h("select", { ariaLabel: "Slope rule" },
    h("option", { value: "plane", selected: pathPrefs.rule === "plane" }, "plane (gen_walk's)"),
    h("option", { value: "steep", selected: pathPrefs.rule === "steep" }, "steepest triangle"));
  const max = h("input", { type: "range", min: 35, max: 70, step: 1, value: pathPrefs.max, ariaLabel: "Slope limit" }),
    out = h("output", {}, `${pathPrefs.max}°`);
  rule.onchange = () => {
    pathPrefs.rule = rule.value;
    savePathPrefs();
    draw();
  };
  max.oninput = () => {
    pathPrefs.max = +max.value;
    out.textContent = `${max.value}°`;
    savePathPrefs();
    draw();
  };
  box.append(
    h("div", { className: "row" }, h("span", {}, "Squares too steep past"), out),
    h("div", { className: "row" }, max),
    h("div", { className: "row" }, h("span", {}, "by"), rule),
    h("p", {}, "The slope only recolours the 4-yd squares: the addon's grid and its routes keep their own rules."),
  );
}

// Turned on or off (the Advanced toggle, a link, the panel's ×).
function pathToggled() {
  if (!pathOn()) {
    routePoints = [];
    routeGot = null;
    walk = null;
    hoverAt = null;
    if (state.camera && state.camera.zoom > maxZoom()) zoomAt(W / 2, H / 2, maxZoom());
  } else refreshWalk();
  renderPathPanel();
  draw();
}
$("pathClear").onclick = () => {
  routePoints = [];
  routeGot = null;
  renderPathPanel();
  draw();
  saveView();
};
$("pathClose").onclick = () => {
  state.tools.delete("path");
  const input = $("advanced").querySelector('input[data-tool="path"]');
  if (input) input.checked = false;
  pathToggled();
  settled();
};
for (const b of $("pathAB").querySelectorAll("button")) b.onclick = () => pathShow(b.dataset.v);
renderPathMenu();
