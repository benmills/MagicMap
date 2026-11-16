// Ground tools share the view adapter. Scenery is deliberately excluded from all samples.
const CLASS = [
  "rgba(255,65,65,.35)",
  "rgba(50,210,110,.16)",
  "rgba(60,150,255,.3)",
  "rgba(255,145,30,.45)",
];
let walkOn = false,
  walkTimer,
  profilePoints = [];
function path(points) {
  ctx.beginPath();
  points.forEach(([x, y], i) => (i ? ctx.lineTo(x, y) : ctx.moveTo(x, y)));
  ctx.closePath();
}
function drawWalk() {
  ctx.strokeStyle = "rgba(0,0,0,.6)";
  ctx.lineWidth = 1;
  walk.rows.forEach((row, j) => {
    for (let i = 0; i < row.length; i++) {
      const v = parseInt(row[i], 16),
        c = (walk.c0 + i) / CHUNKS,
        r = (walk.r0 + j) / CHUNKS,
        s = 1 / CHUNKS;
      const p = [
        [c, r],
        [c + s, r],
        [c + s, r + s],
        [c, r + s],
      ].map((p) => toScreen(...p));
      path(p);
      ctx.fillStyle = CLASS[v % 4];
      ctx.fill();
      ctx.beginPath();
      if (!(v & 4)) {
        ctx.moveTo(...p[1]);
        ctx.lineTo(...p[2]);
      }
      if (!(v & 8)) {
        ctx.moveTo(...p[3]);
        ctx.lineTo(...p[2]);
      }
      ctx.stroke();
    }
  });
}
function refreshWalk() {
  clearTimeout(walkTimer);
  const ticket = requests.ticket("walk");
  if (!walkOn) {
    walk = null;
    draw();
    return;
  }
  walkTimer = setTimeout(
    run(async () => {
      const q = view().map((v, i) =>
        clamp(Math.floor(v * CHUNKS) + (i > 1 ? 1 : 0), 0, 1024),
      );
      if ((q[2] - q[0]) * (q[3] - q[1]) > 40000) {
        walk = null;
        draw();
        notice("Zoom in for the walk grid (at most 40,000 cells).");
        return;
      }
      const got = await get(
        `/api/walk?c0=${q[0]}&r0=${q[1]}&c1=${q[2]}&r1=${q[3]}`,
      );
      if (requests.current(ticket) && walkOn) {
        walk = got;
        draw();
      }
    }),
    150,
  );
}
// Measuring a profile: a tap is one of its two ends.
const profiling = () => $("profile").getAttribute("aria-pressed") === "true";
function profileTap(x, y) {
  const hit = activeView().pick(x, y);
  if (!hit) return notice("No loaded ground there.");
  profilePoints.push(hit);
  if (profilePoints.length > 2) profilePoints = [hit];
  renderProfile();
  draw();
}
function drawAnalysis() {
  if (
    state.mode === "2d" &&
    terrain?.inst === state.inst &&
    (state.tools.has("elevation") ||
      state.tools.has("slope") ||
      state.tools.has("contours"))
  ) {
    const step = Math.max(16, Math.ceil(Math.sqrt((W * H) / 3000)));
    for (let y = 0; y < H; y += step)
      for (let x = 0; x < W; x += step) {
        const [c, r] = toTile(x, y),
          s = terrain.sample(c, r);
        if (!s) continue;
        if (state.tools.has("elevation") || state.tools.has("slope")) {
          const v = state.tools.has("slope")
            ? clamp(s.slope / 60, 0, 1)
            : clamp((s.height + 100) / 1800, 0, 1);
          ctx.fillStyle = `hsla(${140 - v * 140},65%,50%,.38)`;
          ctx.fillRect(x, y, step, step);
        }
        if (state.tools.has("contours")) {
          const b = terrain.sample(c + step / state.camera.zoom, r);
          if (b && Math.floor(s.height / 25) !== Math.floor(b.height / 25)) {
            ctx.fillStyle = "rgba(245,225,173,.8)";
            ctx.fillRect(x, y, 1, step);
          }
        }
      }
  }
  if (profilePoints.length) {
    ctx.beginPath();
    profilePoints.forEach((p, i) => {
      const q = toScreen(...p);
      if (i) ctx.lineTo(...q);
      else ctx.moveTo(...q);
    });
    ctx.strokeStyle = "#7fe4cf";
    ctx.lineWidth = 3;
    ctx.stroke();
    for (const p of profilePoints) drawRing(ctx, ...toScreen(...p), 0.6);
  }
}
function renderProfile() {
  const el = $("profileResult");
  el.replaceChildren();
  if (profilePoints.length !== 2) {
    el.textContent = "Tap a second ground point to draw a profile.";
    return;
  }
  const [a, b] = profilePoints,
    n = 160,
    values = [];
  for (let i = 0; i <= n; i++)
    values.push(
      terrain?.sample(
        a[0] + ((b[0] - a[0]) * i) / n,
        a[1] + ((b[1] - a[1]) * i) / n,
      ) ?? null,
    );
  const known = values.filter(Boolean),
    distance = (Math.hypot(b[0] - a[0], b[1] - a[1]) * 1600) / 3;
  if (!known.length) {
    el.textContent = "No terrain samples loaded along this profile.";
    return;
  }
  const heights = known.map((s) => s.height),
    min = Math.min(...heights),
    max = Math.max(...heights),
    c = h("canvas", {
      width: 600,
      height: 180,
      ariaLabel: "Ground elevation profile",
    }),
    g = c.getContext("2d");
  c.style.width = "100%";
  g.strokeStyle = "#7fe4cf";
  g.lineWidth = 2;
  g.beginPath();
  let connected = false;
  values.forEach((s, i) => {
    if (!s) {
      connected = false;
      return;
    }
    const x = (i / n) * 580 + 10,
      y = 160 - ((s.height - min) / Math.max(1, max - min)) * 140;
    if (connected) g.lineTo(x, y);
    else g.moveTo(x, y);
    connected = true;
  });
  g.stroke();
  el.append(
    c,
    h(
      "p",
      {},
      `${distance.toFixed(0)} yd · elevation ${min.toFixed(0)}–${max.toFixed(0)} yd. ${values.length - known.length} gaps. ${known.some((s) => s.resolution !== "native") ? "Includes simplified terrain." : "Native terrain triangles."}`,
    ),
  );
}
// Finding a route: the addon's own search (atlas/Route.lua, /api/route) between two taps, drawn with what it did:
// every chunk A* closed (dark to bright in the order it closed them), the chunk path it found, the box it searched
// in, the line the addon draws (straightened and rounded), and where each end was moved to stand.
let routePoints = [],
  routeGot = null;
const routing = () => $("route").getAttribute("aria-pressed") === "true";
function routeTap(x, y) {
  const [c, r] = toTile(x, y);
  routePoints.push([c, r]);
  if (routePoints.length > 2) routePoints = [[c, r]];
  routeGot = null;
  renderRoute();
  draw();
  if (routePoints.length === 2) findRoute();
}
const findRoute = run(async () => {
  const [[c0, r0], [c1, r1]] = routePoints,
    ticket = requests.ticket("route");
  $("routeResult").textContent = "Searching…";
  const got = await get(`/api/route?c0=${c0}&r0=${r0}&c1=${c1}&r1=${r1}`);
  if (!requests.current(ticket) || routePoints.length !== 2) return;
  routeGot = got;
  renderRoute();
  draw();
});
function drawRoute() {
  const s = 1 / CHUNKS,
    g = routeGot;
  if (g && !g.error) {
    const cell = (gc, gr) => {
      const [x0, y0] = toScreen(gc * s, gr * s),
        [x1, y1] = toScreen((gc + 1) * s, (gr + 1) * s);
      return [x0, y0, Math.max(1, x1 - x0), Math.max(1, y1 - y0)];
    };
    const n = g.closed.length / 2;
    if ($("routeSearched")?.checked !== false)
      for (let i = 0; i < n; i++) {
        const [x, y, w, h] = cell(g.closed[2 * i], g.closed[2 * i + 1]);
        if (x > W || y > H || x + w < 0 || y + h < 0) continue;
        ctx.fillStyle = `hsla(${230 - (i / n) * 180},80%,55%,.28)`;
        ctx.fillRect(x, y, w, h);
      }
    const [bx0, by0] = toScreen(g.box[0] * s, g.box[1] * s),
      [bx1, by1] = toScreen((g.box[2] + 1) * s, (g.box[3] + 1) * s);
    ctx.setLineDash([4, 4]);
    ctx.strokeStyle = "rgba(255,255,255,.45)";
    ctx.lineWidth = 1;
    ctx.strokeRect(bx0, by0, bx1 - bx0, by1 - by0);
    ctx.setLineDash([]);
    ctx.fillStyle = "rgba(90,235,255,.55)";
    for (let i = 0; i < g.raw.length; i += 2) {
      const [x, y, w, h] = cell(g.raw[i], g.raw[i + 1]);
      ctx.fillRect(x, y, w, h);
    }
    if (g.way.length) {
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
    for (const [gc, gr] of g.snapped) {
      const [x, y, w, h] = cell(gc, gr);
      ctx.strokeStyle = "#fff";
      ctx.lineWidth = 1.5;
      ctx.strokeRect(x, y, w, h);
    }
  }
  for (const p of routePoints) drawRing(ctx, ...toScreen(...p), 0.6);
}
function renderRoute() {
  const el = $("routeResult"),
    g = routeGot;
  el.replaceChildren();
  if (!routing() && !g) return;
  if (routePoints.length < 2) {
    el.textContent = routePoints.length ? "Tap where to go." : "Tap where to start, then where to go.";
    return;
  }
  if (!g) return;
  if (g.error) {
    el.textContent = g.error;
    return;
  }
  const yd = (v) => `${Math.round(v).toLocaleString()} yd`,
    outcome = !g.found
      ? "No way found: the addon draws a straight line."
      : g.partial
        ? "No way all the way: it ends where it got nearest, then straight on (orange)."
        : "Found.",
    rows = [
      ["Map", g.map],
      ["Result", outcome + (g.capped ? ` Gave up at ${g.maxNodes.toLocaleString()} chunks.` : "")],
      ["Searched", `${g.nodes.toLocaleString()} chunks in ${g.ms} ms here (in game: ~${Math.max(1, Math.round(g.nodes / 25 / 60))} s of 1 ms frames)`],
      ["Distance", g.found ? `${yd(g.yards)} along the way, ${yd(g.straight)} straight (×${(g.yards / g.straight).toFixed(2)})` : yd(g.straight) + " straight"],
      ["Path", `${g.raw.length / 2} chunks, straightened to ${Math.max(0, g.turns.length / 2 - 2)} turns`],
    ];
  const dl = h("dl", {});
  for (const [k, v] of rows) dl.append(h("dt", {}, k), h("dd", {}, v));
  const sw = (c) => h("i", { style: `background:${c}` });
  const toggle = h("input", { type: "checkbox", id: "routeSearched", checked: true });
  toggle.onchange = draw;
  el.append(
    dl,
    h("p", { className: "key" }, sw("linear-gradient(90deg,hsla(230,80%,55%,.6),hsla(50,80%,55%,.6))"), "searched (first → last)",
      sw("rgba(90,235,255,.8)"), "A*'s chunks", sw("#ffd24c"), "the addon's line"),
    h("label", { className: "row" }, toggle, h("span", {}, "Show searched chunks")),
  );
}
