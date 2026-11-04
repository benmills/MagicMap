// The flyover: a cinematic tour for recording. A set path down each continent, fast and low: the camera looks where
// it's going (its heading eased), swoops lower and higher, and glides over the ground (its height eased, never
// snapping to a hill). Between continents it fades to black and back. While it flies the page's controls are hidden
// (a clean frame); any click, tap, wheel or key stops it where it is. It never drives picking or ground analysis.
let flyoverFrame = null,
  interactionEpoch = 0;

// The routes, in world tiles (the places named on the map: Atlas labels). Kalimdor north to south, the Eastern
// Kingdoms south to north.
const FLY_ROUTES = [
  [[36.7, 17.3], [40.3, 19.5], [37.8, 21.8], [34.1, 20.6], [32.4, 25.4], [36.4, 27.0], [40.7, 28.3], [40.4, 31.3],
   [36.4, 32.5], [32.0, 34.2], [32.3, 37.9], [36.0, 40.0], [40.2, 42.2], [39.2, 45.3], [36.6, 47.6], [32.4, 48.9]],
  [[76.2, 49.8], [78.8, 46.4], [78.0, 42.8], [76.8, 40.7], [75.5, 39.3], [78.0, 39.8], [81.5, 40.3], [80.4, 38.0],
   [78.7, 35.7], [78.6, 32.4], [81.6, 33.4], [83.2, 29.7], [81.2, 25.5], [79.0, 24.0], [77.5, 22.2], [76.3, 18.8],
   [80.3, 19.8], [84.5, 17.4]],
];
const FLY = {
  speed: 0.75,      // tiles a second (a tile is 533 yards)
  zoom: [170, 320], // px a tile: the swoop, high to low
  swoop: 22,        // seconds for one swoop, low and back
  tilt: [58, 65],
  turn: 1.1,        // seconds the heading takes to follow the path
  lookAhead: 1.6,   // tiles ahead on the path the camera points at
  lift: 0.7,        // seconds the camera's height takes to follow the ground
  fade: 700,        // ms to black and back between routes
  ease: 2.5,        // seconds to get up to speed
};

// A route as a smooth path (Catmull-Rom through its places), sampled densely, with the distance along it.
function flyPath(route) {
  const pts = [];
  const at = (i) => route[Math.max(0, Math.min(route.length - 1, i))];
  for (let i = 0; i < route.length - 1; i++)
    for (let k = 0; k < 24; k++) {
      const t = k / 24, [p0, p1, p2, p3] = [at(i - 1), at(i), at(i + 1), at(i + 2)];
      const f = (j) => 0.5 * (2 * p1[j] + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t * t + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t * t * t);
      pts.push([f(0), f(1)]);
    }
  pts.push(route.at(-1));
  const dist = [0];
  for (let i = 1; i < pts.length; i++) dist.push(dist[i - 1] + Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]));
  const length = dist.at(-1);
  const point = (d) => {
    d = clamp(d, 0, length);
    let lo = 0, hi = dist.length - 1;
    while (hi - lo > 1) { const m = (lo + hi) >> 1; if (dist[m] <= d) lo = m; else hi = m; }
    const t = (d - dist[lo]) / Math.max(1e-9, dist[hi] - dist[lo]);
    return [pts[lo][0] + (pts[hi][0] - pts[lo][0]) * t, pts[lo][1] + (pts[hi][1] - pts[lo][1]) * t];
  };
  return { length, point };
}

// The page's controls off while it flies (body.flying: app.css), the button's state.
function updateFlyoverControl() {
  const button = $("flyover");
  button.hidden = state.mode !== "3d";
  button.disabled = state.mode !== "3d";
  button.setAttribute("aria-pressed", String(state.flyover));
  button.textContent = state.flyover ? "Ⅱ" : "▶";
  const label = state.flyover ? "Stop flyover" : "Start flyover";
  button.setAttribute("aria-label", label);
  button.title = label;
  document.body.classList.toggle("flying", !!state.flyover);
  $("flyoverHint").textContent =
    state.mode === "3d" ? "Click, tap or press a key to stop" : "Flyover is available in 3D";
}

let fade = null;
function setFade(on) {
  if (!fade) {
    fade = document.createElement("div");
    fade.id = "fade";
    document.body.append(fade);
  }
  fade.classList.toggle("on", on);
}

function pauseFlyover() {
  if (!state.flyover) return;
  state.flyover = false;
  cancelAnimationFrame(flyoverFrame);
  flyoverFrame = null;
  setFade(false);
  if (terrain) {
    terrain.focusLocked = false;
    finishGroundPan(); // rest on the ground at the centre, no pixel moving (core.js)
  }
  updateFlyoverControl();
  draw();
  settled();
  saveView({ immediate: true });
}

function startFlyover() {
  if (state.mode !== "3d" || !assets?.terrain.available || terrain.lost) return;
  stopMotion();
  closeSheets();
  const paths = FLY_ROUTES.map(flyPath);
  // Start on the route whose start is nearest; then the other, in turn, for as long as it runs.
  const near = (r) => Math.hypot(r[0][0] - state.camera.cx, r[0][1] - state.camera.cy);
  let route = near(FLY_ROUTES[0]) <= near(FLY_ROUTES[1]) ? 0 : 1;
  let d = 0, clock = 0, last = null, refreshed = 0, heading = null, height = null, leg = 0;
  let cut = null; // a cut between routes: { at: ms, swapped }
  const ground = (c, r) => terrain.sample(c, r)?.height;
  const headingAt = (path, d) => {
    const [x0, y0] = path.point(d), [x1, y1] = path.point(d + FLY.lookAhead);
    return Math.atan2(-(x1 - x0), -(y1 - y0)); // the travel's way at the screen's top (terrain-scene.mjs)
  };
  const place = (dt) => {
    const path = paths[route], s = dt / 1000;
    leg += s;
    d += FLY.speed * Math.min(1, leg / FLY.ease) * s;
    const [cx, cy] = path.point(d);
    const goal = headingAt(path, d);
    heading = heading === null ? goal : heading + mapMotion.angleDelta(goal, heading) * (1 - Math.exp(-s / FLY.turn));
    state.yaw = mapMotion.angleDelta(heading, 0);
    const swoop = 0.5 - 0.5 * Math.cos((2 * Math.PI * clock) / 1000 / FLY.swoop);
    const zoom = FLY.zoom[0] * (FLY.zoom[1] / FLY.zoom[0]) ** swoop;
    state.tilt = FLY.tilt[0] + (FLY.tilt[1] - FLY.tilt[0]) * swoop;
    state.camera = { cx, cy, zoom };
    const h = ground(cx, cy);
    if (height === null) height = terrain.focus; // eased from where it is, even when the ground comes in late
    if (h !== undefined) height += (h - height) * (1 - Math.exp(-s / FLY.lift));
    terrain.focusLocked = true;
    terrain.focus = height;
    return d >= path.length;
  };
  const jump = () => { // to a route's start, all fresh
    d = 0; leg = 0; heading = null; height = null;
    place(0);
  };
  state.flyover = true;
  updateFlyoverControl();
  setFade(true);
  cut = { at: 0, swapped: false, first: true };
  const step = (now) => {
    if (!state.flyover) return;
    if (document.hidden) last = null;
    else {
      // Hidden or stalled tabs must not jump forward on their next frame.
      const dt = last === null ? 0 : Math.min(50, now - last);
      last = now;
      clock += dt;
      if (cut) {
        cut.at += dt;
        if (!cut.swapped && cut.at >= FLY.fade) { // black: on to the next route
          if (!cut.first) route = (route + 1) % paths.length;
          jump();
          cut.swapped = true;
          settled();
        } else if (cut.swapped && cut.at >= FLY.fade * 2.2) { // a moment for its ground to come in, then back
          setFade(false);
          cut = null;
        }
        if (cut?.swapped) place(dt);
      } else if (place(dt)) {
        cut = { at: 0, swapped: false };
        setFade(true);
      }
      $("tilt").value = state.tilt;
      $("tiltValue").textContent = `${Math.round(state.tilt)}°`;
      $("compass").style.setProperty("--yaw", `${-state.yaw}rad`);
      draw();
      if (clock - refreshed > 600) {
        refreshed = clock;
        settled();
      }
    }
    flyoverFrame = requestAnimationFrame(step);
  };
  flyoverFrame = requestAnimationFrame(step);
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
