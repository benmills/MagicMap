// Input owns camera motion. Loading may improve the picture, never the gesture.
let motion = null,
  motionKind = null,
  wheelTimer = null,
  gestureFrame = null;
const pts = new Map();
let gesture = null,
  tap = null,
  lastTap = null;
const movingMap = () =>
  pts.size > 0 || motion !== null || wheelTimer !== null || state.flyover;

function lockGround() {
  if (state.mode !== "3d") return;
  terrain.setView(state.camera, W, H, state.yaw, state.tilt);
  terrain.focusLocked = true;
}
function stopMotion() {
  pauseFlyover();
  if (motion) cancelAnimationFrame(motion);
  motion = null;
  if (motionKind === "glide") finishGroundPan();
  motionKind = null;
  flown?.(false);
  flown = null;
  if (wheelTimer) {
    clearTimeout(wheelTimer);
    wheelTimer = null;
    finishGroundPan();
  }
}
let flown = null; // a flight's done(true) when it lands, done(false) if stopped
function flyTo(goal, ms = 350, done) {
  goal = { ...goal, zoom: clamp(goal.zoom, minZoom(), maxZoom()) };
  stopMotion();
  flown = done;
  const from = state.camera,
    t0 = performance.now();
  motionKind = "flight";
  const step = (now) => {
    const t = Math.min(1, (now - t0) / ms),
      e = 1 - (1 - t) ** 3;
    state.camera = {
      cx: from.cx + (goal.cx - from.cx) * e,
      cy: from.cy + (goal.cy - from.cy) * e,
      zoom: from.zoom * (goal.zoom / from.zoom) ** e,
    };
    draw();
    if (t < 1) motion = requestAnimationFrame(step);
    else {
      motion = null;
      motionKind = null;
      const landed = flown;
      flown = null;
      settled();
      landed?.(true);
    }
  };
  motion = requestAnimationFrame(step);
}
function zoomGoal(x, y, zoom) {
  const keep = state.camera;
  zoomAt(x, y, zoom);
  const goal = state.camera;
  state.camera = keep;
  if (state.mode === "3d") terrain.setView(keep, W, H, state.yaw, state.tilt);
  return goal;
}
function glide(vx, vy) {
  lockGround();
  motionKind = "glide";
  let last = performance.now();
  const step = (now) => {
    const dt = Math.min(32, now - last);
    last = now;
    const next = mapMotion.inertiaStep(vx, vy, dt);
    vx = next.vx;
    vy = next.vy;
    panBy(next.dx, next.dy);
    draw();
    if (Math.hypot(vx, vy) > 0.02) motion = requestAnimationFrame(step);
    else {
      motion = null;
      motionKind = null;
      finishGroundPan();
      draw();
      settled();
    }
  };
  motion = requestAnimationFrame(step);
}
function groundAnchor(x, y) {
  const p = toTile(x, y);
  return [
    ...p,
    state.mode === "3d" ? (terrain.sample(...p)?.height ?? terrain.focus) : 0,
  ];
}
function anchorAt(anchor, x, y) {
  if (state.mode === "3d")
    terrain.setView(state.camera, W, H, state.yaw, state.tilt);
  const p =
    state.mode === "3d" ? terrain.plane(x, y, anchor[2]) : flatView.pick(x, y);
  state.camera = {
    ...state.camera,
    cx: state.camera.cx + anchor[0] - p[0],
    cy: state.camera.cy + anchor[1] - p[1],
  };
}
function beginGesture(e, orbit = false) {
  if (state.mode === "3d")
    terrain.setView(state.camera, W, H, state.yaw, state.tilt);
  const point = mapMotion.pair([...pts.values()]);
  gesture = {
    start: point,
    camera: { ...state.camera },
    yaw: state.yaw,
    tilt: state.tilt,
    anchor: groundAnchor(point.x, point.y),
    orbit,
    mode: pts.size === 2 ? null : "pan",
    changed: false,
    samples: [{ x: point.x, y: point.y, t: e.timeStamp }],
    time: e.timeStamp,
  };
}
function applyGesture() {
  gestureFrame = null;
  if (!gesture || !pts.size) return;
  const p = mapMotion.pair([...pts.values()]),
    g = gesture;
  const dx = p.x - g.start.x,
    dy = p.y - g.start.y;
  if (Math.hypot(dx, dy) > 8) {
    tap = null;
    g.changed = true;
  }
  if (pts.size === 2) {
    tap = null;
    g.mode ||= mapMotion.twoFingerMode(g.start, p);
    if (!g.mode) return;
    g.changed = true;
    state.camera = { ...g.camera };
    if (g.mode === "tilt" && state.mode === "3d") {
      state.tilt = clamp(g.tilt + dy * 0.2, 0, 65);
      anchorAt(g.anchor, g.start.x, g.start.y);
    } else {
      const zoom = (g.camera.zoom * p.span) / Math.max(1, g.start.span);
      out3D = state.mode === "3d" && zoom < MIN_3D_ZOOM * 0.8;
      state.camera.zoom = clamp(zoom, minZoom(), maxZoom());
      if (state.mode === "3d")
        state.yaw = mapMotion.angleDelta(
          g.yaw + mapMotion.angleDelta(p.angle, g.start.angle),
          0,
        );
      anchorAt(g.anchor, p.x, p.y);
    }
    updateViewControls();
  } else if (g.orbit) {
    state.yaw = mapMotion.angleDelta(g.yaw + dx * 0.005, 0);
    state.tilt = clamp(g.tilt + dy * 0.15, 0, 65);
    updateViewControls();
  } else {
    // One world anchor for the entire gesture, even if meshes refine underneath.
    state.camera = { ...g.camera };
    anchorAt(g.anchor, p.x, p.y);
  }
  draw();
}
function flushGesture() {
  if (gestureFrame) {
    cancelAnimationFrame(gestureFrame);
    applyGesture();
  }
}
canvas.addEventListener("pointerdown", (e) => {
  if (!state.camera || pts.size >= 2) return;
  flushGesture();
  stopMotion();
  closeSheets();
  clearTimeout(hoverTimer);
  requests.ticket("inspect");
  if (!pts.size) lockGround();
  pts.set(e.pointerId, mapPoint(e.clientX, e.clientY));
  canvas.setPointerCapture(e.pointerId);
  const orbit =
    pts.size === 1 &&
    state.mode === "3d" &&
    e.pointerType === "mouse" &&
    (e.button === 2 || e.shiftKey);
  beginGesture(e, orbit);
  tap =
    pts.size === 1 && !orbit
      ? { ...mapPoint(e.clientX, e.clientY), t: e.timeStamp }
      : null;
  if (e.pointerType === "mouse") canvas.style.cursor = "grabbing";
});
canvas.addEventListener("pointermove", (e) => {
  if (!pts.has(e.pointerId)) {
    if (e.pointerType === "mouse" && state.camera && !movingMap()) {
      const point = mapPoint(e.clientX, e.clientY);
      hoverInspect(point.x, point.y);
      canvas.style.cursor = pinAt(point.x, point.y, 12)
        ? "pointer"
        : "grab";
    }
    return;
  }
  pts.set(e.pointerId, mapPoint(e.clientX, e.clientY));
  const p = mapMotion.pair([...pts.values()]);
  gesture.time = e.timeStamp;
  gesture.samples.push({ x: p.x, y: p.y, t: e.timeStamp });
  gesture.samples = gesture.samples.filter((p) => e.timeStamp - p.t < 140);
  if (!gestureFrame) gestureFrame = requestAnimationFrame(applyGesture);
});
function release(e, cancelled) {
  if (!pts.has(e.pointerId)) return;
  flushGesture();
  const g = gesture,
    wasSingle = pts.size === 1;
  pts.delete(e.pointerId);
  if (pts.size) {
    tap = null;
    beginGesture(e);
    gesture.changed = g.changed;
    return;
  }
  gesture = null;
  if (e.pointerType === "mouse") canvas.style.cursor = "grab";
  const [vx, vy] = mapMotion.releaseVelocity(g.samples, e.timeStamp);
  if (
    !cancelled &&
    wasSingle &&
    g.changed &&
    !g.orbit &&
    Math.hypot(vx, vy) > 0.12
  ) {
    glide(vx, vy);
  } else {
    if (state.mode === "3d") {
      if (g.changed && !g.orbit) finishGroundPan();
      else terrain.focusLocked = false;
    }
    draw();
    settled();
  }
  if (!cancelled && e.button !== 2 && tap && e.timeStamp - tap.t < 300) {
    if (
      lastTap &&
      e.timeStamp - lastTap.t < 300 &&
      Math.hypot(tap.x - lastTap.x, tap.y - lastTap.y) < 30 &&
      e.pointerType !== "mouse"
    ) {
      flyTo(zoomGoal(tap.x, tap.y, state.camera.zoom * 2), 250);
      lastTap = null;
    } else {
      const pin = pinAt(tap.x, tap.y, e.pointerType === "mouse" ? 12 : 22);
      const building =
        !pin && state.mode === "3d" && terrain.pickBuilding(tap.x, tap.y);
      if (pin) run(openPin)(pin);
      else if (building) selectBuilding(building);
      else if (Review.tap(...toTile(tap.x, tap.y))) {}
      else run(inspect)(tap.x, tap.y, true);
      lastTap = tap;
    }
  }
  tap = null;
}
canvas.addEventListener("pointerup", (e) => release(e, false));
canvas.addEventListener("pointercancel", (e) => release(e, true));
canvas.addEventListener("lostpointercapture", (e) => release(e, true));

canvas.addEventListener(
  "wheel",
  (e) => {
    e.preventDefault();
    if (!state.camera || pts.size) return;
    if (!wheelTimer) {
      stopMotion();
      lockGround();
    }
    clearTimeout(wheelTimer);
    // Trackpad translation stays translation; ctrl+wheel is a platform pinch.
    const trackpad =
      !e.ctrlKey &&
      e.deltaMode === 0 &&
      (Math.abs(e.deltaX) > 0 || Math.abs(e.deltaY) < 40);
    if (trackpad) panBy(-e.deltaX, -e.deltaY);
    else {
      const units = e.deltaMode === 1 ? 16 : e.deltaMode === 2 ? H : 1;
      const point = mapPoint(e.clientX, e.clientY);
      zoomAt(
        point.x,
        point.y,
        state.camera.zoom *
          Math.exp(-e.deltaY * units * (e.ctrlKey ? 0.01 : 0.002)),
      );
    }
    draw();
    wheelTimer = setTimeout(() => {
      wheelTimer = null;
      finishGroundPan();
      draw();
      settled();
    }, 140);
  },
  { passive: false },
);
canvas.addEventListener("dblclick", (e) => {
  const point = mapPoint(e.clientX, e.clientY);
  flyTo(zoomGoal(point.x, point.y, state.camera.zoom * 2), 250);
});
// Pointer gestures own touch zoom; don't let Safari also zoom the document.
for (const event of ["gesturestart", "gesturechange", "gestureend"])
  canvas.addEventListener(event, (e) => e.preventDefault(), { passive: false });
canvas.addEventListener("contextmenu", (e) => e.preventDefault());
function panBy(dx, dy) {
  if (state.mode === "3d")
    terrain.setView(state.camera, W, H, state.yaw, state.tilt);
  const a =
    state.mode === "3d"
      ? terrain.plane(W / 2, H / 2)
      : flatView.pick(W / 2, H / 2);
  const b =
    state.mode === "3d"
      ? terrain.plane(W / 2 + dx, H / 2 + dy)
      : flatView.pick(W / 2 + dx, H / 2 + dy);
  state.camera = {
    ...state.camera,
    cx: state.camera.cx + a[0] - b[0],
    cy: state.camera.cy + a[1] - b[1],
  };
}
$("zone").onchange = run(async (e) => {
  if (e.target.value) await navigatePlace(Number(e.target.value));
  e.target.blur();
});
