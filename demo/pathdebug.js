// Pathing debug (Advanced > Pathing Debug; tools=path in the link): the addon's walk grid and route search, shown
// to find where they're wrong. While it's on, the walk grid is always drawn, a tap sets a route's ends (start, then
// goal; a third starts again) and runs the addon's own search on them (atlas/Route.lua via /api/route), the map
// zooms in much closer (PATH_ZOOM: a 4-yd square some 40 px), and a panel in the top left holds the layers, the
// route's numbers and, under the mouse, the cell and square it's over. Layers (the panel's menu, remembered in this
// browser): each chunk's class, the crossings it lacks, cut-off pockets (regions other than the map's biggest:
// Data/WalkRegions.lua), the connectors (tools/walk_links.json), the 4-yd squares under each chunk (baked by
// demo/export_walkquads.py; their slope by a rule and a limit you pick, to try another than gen_walk's), and the
// search: every cell it closed (dark to bright, in order), its chunk path, the addon's line, its box.
const PATH_LAYERS = [
  ["cells", "Cell classes", true],
  ["crossings", "Missing crossings (black edges)", true],
  ["regions", "Cut-off pockets", true],
  ["links", "Connectors", true],
  ["quads", "4-yd squares (zoom in)", true],
  ["searched", "Cells searched", true],
  ["astar", "A*'s chunk path", true],
  ["line", "The addon's line", true],
  ["box", "Search box", false],
  ["dim", "Dim the map", false],
];
const CELL_FILL = ["rgba(255,65,65,.35)", "rgba(50,210,110,.16)", "rgba(60,150,255,.3)", "rgba(255,145,30,.45)"];
const CLASS_NAMES = ["blocked", "land", "water", "magma/slime"];
const QUAD_MIN_ZOOM = 640; // px a tile: a square 5 px, its layer worth drawing
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
  routePoints = [],
  routeGot = null;
const pathOn = () => state.tools.has("path");

// The walk grid around the view (/api/walk: classes, regions, connectors), fetched once the view settles.
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
      const got = await get(`/api/walk?c0=${q[0]}&r0=${q[1]}&c1=${q[2]}&r1=${q[3]}`);
      if (requests.current(ticket) && pathOn()) {
        walk = got;
        draw();
      }
    }),
    150,
  );
}
const walkAt = (gc, gr) => {
  const j = gr - walk?.r0, i = gc - walk?.c0;
  if (!walk || j < 0 || i < 0 || j >= walk.rows.length || i >= walk.rows[0].length) return null;
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
    quadsOn = layer("quads") && zoom >= QUAD_MIN_ZOOM;
  if (layer("dim")) {
    ctx.fillStyle = "rgba(0,0,0,.45)";
    ctx.fillRect(0, 0, W, H);
  }
  const cell = (gc, gr) => {
    const [x0, y0] = toScreen(gc * s, gr * s),
      [x1, y1] = toScreen((gc + 1) * s, (gr + 1) * s);
    return [x0, y0, x1, y1];
  };
  if (walk) {
    const alpha = quadsOn ? 0.35 : 1;
    ctx.save();
    ctx.globalAlpha = alpha;
    walk.rows.forEach((row, j) => {
      for (let i = 0; i < row.length; i++) {
        const v = parseInt(row[i], 16),
          [x0, y0, x1, y1] = cell(walk.c0 + i, walk.r0 + j);
        if (x0 > W || y0 > H || x1 < 0 || y1 < 0) continue;
        if (layer("cells")) {
          ctx.fillStyle = CELL_FILL[v % 4];
          ctx.fillRect(x0, y0, x1 - x0, y1 - y0);
        }
        const rg = walk.regions[j][i];
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
  if (walk) {
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
    if (layer("links"))
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
        ctx.fillText(l.name, (a[0] + b[0]) / 2 + 8, (a[1] + b[1]) / 2);
      }
  }
  const g = routeGot;
  if (g && !g.error) {
    const fill = (gc, gr) => {
      const [x0, y0, x1, y1] = cell(gc, gr);
      if (x0 > W || y0 > H || x1 < 0 || y1 < 0) return;
      ctx.fillRect(x0, y0, Math.max(1, x1 - x0), Math.max(1, y1 - y0));
    };
    const n = g.closed.length / 2;
    if (layer("searched"))
      for (let i = 0; i < n; i++) {
        ctx.fillStyle = `hsla(${230 - (i / n) * 180},80%,55%,.28)`;
        fill(g.closed[2 * i], g.closed[2 * i + 1]);
      }
    if (layer("box")) {
      const [bx0, by0] = toScreen(g.box[0] * s, g.box[1] * s),
        [bx1, by1] = toScreen((g.box[2] + 1) * s, (g.box[3] + 1) * s);
      ctx.setLineDash([4, 4]);
      ctx.strokeStyle = "rgba(255,255,255,.6)";
      ctx.lineWidth = 1;
      ctx.strokeRect(bx0, by0, bx1 - bx0, by1 - by0);
      ctx.setLineDash([]);
    }
    if (layer("astar")) {
      ctx.fillStyle = "rgba(90,235,255,.55)";
      for (let i = 0; i < g.raw.length; i += 2) fill(g.raw[i], g.raw[i + 1]);
    }
    if (layer("line") && g.way.length) {
      const line = () => {
        ctx.beginPath();
        g.way.forEach((p, i) => (i ? ctx.lineTo(...toScreen(...p)) : ctx.moveTo(...toScreen(...p))));
      };
      line();
      ctx.strokeStyle = "rgba(20,12,4,.8)";
      ctx.lineWidth = 5;
      ctx.stroke();
      line();
      ctx.strokeStyle = g.partial ? "#ff9a3c" : "#ffd24c";
      ctx.lineWidth = 2.5;
      ctx.setLineDash([8, 5]);
      ctx.stroke();
      ctx.setLineDash([]);
      ctx.fillStyle = "#fff";
      for (let i = 2; i < g.turns.length - 2; i += 2) {
        const [x, y] = toScreen((g.turns[i] + 0.5) * s, (g.turns[i + 1] + 0.5) * s);
        ctx.fillRect(x - 2, y - 2, 4, 4);
      }
    }
    ctx.strokeStyle = "#fff";
    ctx.lineWidth = 1.5;
    for (const [gc, gr] of [...g.snapped, ...(g.instead ? [g.instead] : [])]) {
      const [x0, y0, x1, y1] = cell(gc, gr);
      ctx.strokeRect(x0, y0, x1 - x0, y1 - y0);
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
  if (routePoints.length === 2) findRoute();
}
const findRoute = run(async () => {
  const [[c0, r0], [c1, r1]] = routePoints,
    ticket = requests.ticket("route");
  $("pathRoute").textContent = "Searching…";
  const got = await get(`/api/route?c0=${c0}&r0=${r0}&c1=${c1}&r1=${r1}`);
  if (!requests.current(ticket) || routePoints.length !== 2) return;
  routeGot = got;
  renderPathPanel();
  draw();
});

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
  if (w)
    text += `\n${CLASS_NAMES[w.v % 4]} · crosses east ${w.v & 4 ? "yes" : "no"}, south ${w.v & 8 ? "yes" : "no"} · ${w.region ? (w.region === 1 ? "main region" : `cut-off pocket r${w.region}`) : "nowhere to stand"}`;
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

function renderPathPanel() {
  const panel = $("pathDebug");
  panel.hidden = !pathOn();
  if (!pathOn()) return;
  const el = $("pathRoute"),
    g = routeGot;
  el.replaceChildren();
  const hint = quadsMissing ? " The 4-yd squares aren't baked here (demo/export_walkquads.py)." : "";
  if (routePoints.length < 2) {
    el.textContent = (routePoints.length ? "Tap where to go." : "Tap where to start, then where to go.") + hint;
    return;
  }
  if (!g) return;
  if (g.error) return void (el.textContent = g.error);
  const yd = (v) => `${Math.round(v).toLocaleString()} yd`,
    outcome = !g.found
      ? "No way: the addon draws a straight line."
      : g.partial
        ? "Partial: as near as it gets, then straight on (orange)."
        : "Found.",
    rows = [
      ["Result", outcome + (g.capped ? ` Gave up at ${g.maxNodes.toLocaleString()} cells.` : "")],
      ...(g.regions
        ? [["Regions", `start r${g.regions[0]}, goal r${g.regions[1]}: no walk joins them, so no search${g.instead ? "; routed to the nearest cell in yours" : ", none near enough"}`]]
        : []),
      ["Searched", `${g.nodes.toLocaleString()} cells, ${g.ms} ms here (in game ~${Math.max(1, Math.round(g.nodes / 25 / 60))} s at 1 ms a frame)`],
      ["Distance", g.found ? `${yd(g.yards)} along, ${yd(g.straight)} straight (×${(g.yards / g.straight).toFixed(2)})` : `${yd(g.straight)} straight`],
      ["Path", `${g.raw.length / 2} cells, ${Math.max(0, g.turns.length / 2 - 2)} turns`],
    ];
  const dl = h("dl", {});
  for (const [k, v] of rows) dl.append(h("dt", {}, k), h("dd", {}, v));
  el.append(dl);
  if (hint) el.append(h("p", {}, hint));
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
    h("p", {}, "The slope only recolours the 4-yd squares: the addon's grid and its routes keep gen_walk's 60° by the plane."),
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
};
$("pathClose").onclick = () => {
  state.tools.delete("path");
  const input = $("advanced").querySelector('input[data-tool="path"]');
  if (input) input.checked = false;
  pathToggled();
  settled();
};
renderPathMenu();
