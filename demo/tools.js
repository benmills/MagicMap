// Ground tools share the view adapter. Scenery is deliberately excluded from all samples.
let profilePoints = [];
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
