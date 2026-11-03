// A slow, local sightseeing loop. It never drives picking or ground analysis.
let flyoverFrame = null,
  interactionEpoch = 0;

function updateFlyoverControl() {
  const button = $("flyover");
  button.hidden = state.mode !== "3d";
  button.disabled = state.mode !== "3d";
  button.setAttribute("aria-pressed", String(state.flyover));
  button.textContent = state.flyover ? "Ⅱ" : "▶";
  const label = state.flyover ? "Pause flyover" : "Start flyover";
  button.setAttribute("aria-label", label);
  button.title = label;
  $("flyoverHint").textContent =
    state.mode === "3d"
      ? "Drag or use a control to pause"
      : "Flyover is available in 3D";
}

function pauseFlyover() {
  if (!state.flyover) return;
  state.flyover = false;
  cancelAnimationFrame(flyoverFrame);
  flyoverFrame = null;
  updateFlyoverControl();
  settled();
  saveView({ immediate: true });
}

function startFlyover({ intro = false } = {}) {
  if (state.mode !== "3d" || !assets?.terrain.available || terrain.lost) return;
  stopMotion();
  const available = new Set(assets.terrain.data.tiles.map((t) => t.key));
  const land = tiles.filter((t) => !t.sea && available.has(t.key));
  if (intro && land.length) {
    // Start near Mulgore on a fresh visit; other maps use the nearest covered land.
    const current =
      Math.floor(state.camera.cx) * 64 + Math.floor(state.camera.cy);
    if (!land.some((t) => t.key === current)) {
      const nearest = land.reduce((best, t) =>
        Math.hypot(
          t.col + 0.5 - state.camera.cx,
          t.row + 0.5 - state.camera.cy,
        ) <
        Math.hypot(
          best.col + 0.5 - state.camera.cx,
          best.row + 0.5 - state.camera.cy,
        )
          ? t
          : best,
      );
      state.camera = {
        ...state.camera,
        cx: nearest.col + 0.5,
        cy: nearest.row + 0.5,
      };
    }
  }
  const origin = { ...state.camera },
    yaw = state.yaw,
    tilt = state.tilt;
  const groundKeys = new Set(land.map((t) => t.key));
  let radius = Math.min(1.2, W / origin.zoom / 4);
  // Keep a local tour over available land where possible, including small maps.
  while (
    radius > 0.06 &&
    Array.from({ length: 32 }, (_, i) => {
      const angle = (i * Math.PI) / 16;
      const c = origin.cx + radius * (Math.cos(angle) - 1);
      const r = origin.cy + radius * 0.65 * Math.sin(angle);
      return groundKeys.has(Math.floor(c) * 64 + Math.floor(r));
    }).some((onLand) => !onLand)
  )
    radius /= 2;

  let elapsed = 0,
    last = null,
    refreshed = 0;
  state.flyover = true;
  updateFlyoverControl();
  const step = (now) => {
    if (!state.flyover) return;
    if (document.hidden) last = null;
    else {
      // Hidden or stalled tabs must not jump forward on their next frame.
      if (last !== null) elapsed += Math.min(50, now - last);
      last = now;
      const angle = (elapsed / 1000) * 0.035;
      state.camera = {
        ...origin,
        cx: origin.cx + radius * (Math.cos(angle) - 1),
        cy: origin.cy + radius * 0.65 * Math.sin(angle),
      };
      const bearing = yaw + 0.18 * Math.sin(angle);
      state.yaw = Math.atan2(Math.sin(bearing), Math.cos(bearing));
      state.tilt = terrainQuality.flyoverPitch(tilt, elapsed / 1000);
      $("tilt").value = state.tilt;
      $("tiltValue").textContent = `${Math.round(state.tilt)}°`;
      $("compass").style.setProperty("--yaw", `${-state.yaw}rad`);
      draw();
      if (elapsed - refreshed > 1000) {
        refreshed = elapsed;
        settled();
      }
    }
    flyoverFrame = requestAnimationFrame(step);
  };
  flyoverFrame = requestAnimationFrame(step);
  draw();
  settled();
  saveView({ immediate: true });
}

// Interaction always wins, including keyboard search and controls during startup.
function interruptFlyover(e) {
  if (e.target.closest?.("#flyover, #share")) return;
  interactionEpoch++;
  pauseFlyover();
}
for (const name of [
  "pointerdown",
  "wheel",
  "keydown",
  "input",
  "change",
  "focusin",
])
  document.addEventListener(name, interruptFlyover, {
    capture: true,
    passive: true,
  });
$("flyover").onclick = () => (state.flyover ? pauseFlyover() : startFlyover());
