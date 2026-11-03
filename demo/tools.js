// Ground tools share the view adapter. Scenery is deliberately excluded from all samples.
const CLASS = [
  "rgba(255,65,65,.35)",
  "rgba(50,210,110,.16)",
  "rgba(60,150,255,.3)",
  "rgba(255,145,30,.45)",
];
let walkOn = false,
  walkTimer,
  hoverTimer,
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
        $("toolNote").textContent =
          "Zoom in for the walk grid (at most 40,000 cells).";
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
function hoverInspect(x, y) {
  clearTimeout(hoverTimer);
  requests.ticket("inspect");
  hoverTimer = setTimeout(
    run(() => inspect(x, y, false)),
    65,
  );
}
async function inspect(x, y, mark) {
  if (state.camera.zoom < READOUT_ZOOM) {
    requests.ticket("inspect");
    readout.textContent = "";
    return;
  }
  const ticket = requests.ticket("inspect"),
    hit = activeView().pick(x, y);
  if (!hit) {
    readout.textContent = "No loaded ground under the pointer.";
    return;
  }
  const [col, row] = hit;
  if (mark) {
    marker = [col, row];
    draw();
    saveView();
    if ($("profile").getAttribute("aria-pressed") === "true") {
      profilePoints.push(hit);
      if (profilePoints.length > 2) profilePoints = [hit];
      renderProfile();
    }
  }
  const a = await get(`/api/at?col=${col}&row=${row}`);
  if (!requests.current(ticket)) return;
  const z = a.zone,
    ar = a.area,
    ground = terrain?.inst === state.inst ? terrain.sample(col, row) : null;
  readout.textContent =
    `${ar?.subzone || ar?.zone || z?.name || MAP_NAME}${z ? ` · ${(z.x * 100).toFixed(1)}, ${(z.y * 100).toFixed(1)}` : ""}` +
    (ground && (state.tools.has("elevation") || state.tools.has("slope"))
      ? ` · ${ground.height.toFixed(0)} yd · ${ground.slope.toFixed(0)}°`
      : "");
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
function settleReadout() { // (the camera moved: zoomed out past the readout's zoom, it goes)
  if (state.camera && state.camera.zoom < READOUT_ZOOM) readout.textContent = "";
}
function selectBuilding(building) {
  const detail = {
    inst: state.inst,
    buildingId: building.id,
    roomId: null,
    name: building.name || "Building",
    placement: building,
  };
  window.dispatchEvent(new CustomEvent("atlas:building-select", { detail }));
  notice(
    `${detail.name} · scenery selection. Room selection is not installed.`,
  );
}

