// Composition root. Classic scripts keep the original canvas painters; pure view/terrain
// modules are loaded on demand. No bundler and no changes to the Atlas Lua contract.
let saveTimer,
  hashWritten = "";
function saveView({ immediate = false } = {}) {
  if (restoring || !viewState || !state.camera) return;
  clearTimeout(saveTimer);
  const write = () => {
    hashWritten = viewState.writeView({ ...state, layers: layerOn, pins: pinsOn });
    history.replaceState(null, "", hashWritten);
  };
  if (immediate) write();
  else saveTimer = setTimeout(write, 180);
}
function updateViewControls() {
  const is3D = state.mode === "3d";
  $("viewBtn").setAttribute("aria-pressed", String(is3D));
  $("viewBtn").title = is3D ? "Switch to 2D map" : "Switch to 3D terrain";
  $("viewBtn").setAttribute("aria-busy", String(terrainLoading));
  $("tiltWrap").hidden = state.mode !== "3d";
  $("tilt").value = state.tilt;
  $("tiltValue").textContent = `${Math.round(state.tilt)}°`;
  $("compass").style.setProperty("--yaw", `${-state.yaw}rad`);
  // North in 2D only: a marker (2D is always north up); 3D has none.
  $("compass").hidden = is3D;
  $("map").setAttribute(
    "aria-label",
    `${MAP_NAME}, ${state.mode.toUpperCase()} map`,
  );
  $("terrain").hidden = state.mode !== "3d";
  $("gestureHint").textContent = matchMedia("(hover: hover)").matches
    ? "Drag to pan · Shift / right-drag to orbit"
    : "Two fingers: pinch, rotate, slide to tilt";
  updateFlyoverControl();
}
async function ensureTerrain() {
  if (!assets?.terrain.available)
    throw Error(assets?.terrain.reason || "Terrain assets unavailable.");
  const epoch = requests.epoch,
    mapAssets = assets,
    inst = state.inst;
  if (terrain?.lost) {
    terrain.dispose();
    terrain = null;
  }
  if (!terrain) {
    const { TerrainView } = await import("./terrain-3d.mjs");
    if (epoch !== requests.epoch || assets !== mapAssets)
      throw new DOMException(
        "Map changed while loading the renderer",
        "AbortError",
      );
    if (!terrain)
      terrain = new TerrainView(
        $("terrain"),
        () => {
          draw();
          if (profilePoints.length === 2) renderProfile();
        },
        (message) => {
          pauseFlyover();
          state.mode = "2d";
          updateViewControls();
          notice(message);
          draw();
          saveView();
        },
      );
  }
  if (terrain.inst !== inst) terrain.setMap(inst, mapAssets);
  terrain.scenery = layerOn.has("scenery") && assets.objects.available;
  terrain.setView(
    state.camera,
    W,
    H,
    state.mode === "3d" ? state.yaw : 0,
    state.mode === "3d" ? state.tilt : 0,
  );
  return terrain;
}
// Into 3D and out: a flight (flyover.js), from the view as it is to a tilted one of the same place (or the goal given:
// the place popup's), and back up, level, north and 2D. A link's or a remembered 3D view (animate: false) is there at once.
const goal3D = () => ({ ...state.camera, zoom: clamp(state.camera.zoom * 1.6, 96, maxZoom()), yaw: 0, tilt: 55 });
const goal2D = () => ({ ...state.camera, zoom: Math.max(MIN_3D_ZOOM, state.camera.zoom / 2), yaw: 0, tilt: 0 });
async function setMode(mode, { remember = true, animate = true, goal, centre = false, ms } = {}) {
  const seq = ++modeSeq,
    epoch = requests.epoch;
  stopMotion();
  if (terrain) terrain.focusLocked = false;
  state.desiredMode = mode;
  if (remember)
    try {
      localStorage.setItem("atlas.view", mode);
    } catch {}
  if (mode === "3d" && state.mode !== "3d") {
    terrainLoading = true;
    updateViewControls();
    notice("Loading terrain…");
    try {
      await ensureTerrain();
    } catch (e) {
      if (seq !== modeSeq || epoch !== requests.epoch) return;
      terrainLoading = false;
      state.desiredMode = "2d";
      notice(`${e.message} Using 2D.`);
      return updateViewControls();
    }
    if (seq !== modeSeq || epoch !== requests.epoch) return;
    terrainLoading = false;
    notice("");
    if (animate) await flight(goal || goal3D(), "3d", { centre, ms });
    else state.mode = "3d";
  } else if (mode === "2d" && state.mode === "3d") {
    terrainLoading = false;
    if (animate) await flight(goal || goal2D(), "2d", { ms });
    else state.mode = "2d";
  } else if (goal) await flight(goal, mode, { centre, ms });
  if (seq !== modeSeq || epoch !== requests.epoch) return;
  state.desiredMode = state.mode; // (a flight stopped part way: where it got to)
  updateViewControls();
  draw();
  settled();
}
// Zoomed out past 3D's limit (out3D): level the view, north, and the 2D map under it, quickly.
function leave3D() {
  out3D = false;
  if (state.mode !== "3d" || terrainLoading) return;
  setMode("2d", { goal: { ...state.camera, yaw: 0, tilt: 0 }, ms: 650 });
}
// The first view: close in, over Ashenvale and Mount Hyjal, about 120 tiles' worth of ground on any screen (a few zones).
const START = { cx: 35.0, cy: 25.5, area: 120 };
function startView() {
  return { cx: START.cx, cy: START.cy, zoom: Math.sqrt((W * H) / START.area) };
}
// The world's tiles, names and assets, afresh (a link's view restored: restoreView).
async function loadWorld(camera) {
  const m = world;
  stopMotion();
  requests.reset();
  const epoch = requests.epoch;
  ++modeSeq;
  terrainLoading = false;
  clearTimeout(pinTimer);
  clearTimeout(walkTimer);
  if (camera && ![camera.cx, camera.cy, camera.zoom].every(Number.isFinite)) camera = null;
  state.camera = camera || startView();
  state.mode = "2d";
  assets = null;
  tiles = [];
  pins = [];
  drawnPins = [];
  labels = [];
  labelState.clear();
  namesAfter = performance.now() + 1500; // (labels.js: until the first pins)
  walk = null;
  profilePoints = [];
  closeSheets();
  closePlace();
  MAP_NAME = m.name;
  bg = rgb(m.bg || [0.03, 0.06, 0.06]);
  updateViewControls();
  draw();
  notice(`Loading ${m.name}…`);
  const metadata = Promise.allSettled([
    loadTiles(),
    loadLabels(),
  ]);
  const got = await get("/api/assets");
  if (epoch !== requests.epoch) return;
  assets = got;
  // Start drawing terrain as soon as its index arrives; labels can follow. A remembered 3D waits
  // for a view near enough for it (a link's 3D view always is).
  if (state.desiredMode === "3d" && !(state.camera.zoom >= MIN_3D_ZOOM)) state.desiredMode = "2d"; // (NaN too)
  if (state.desiredMode === "3d") await setMode("3d", { remember: false, animate: false });
  const outcomes = await metadata;
  if (epoch !== requests.epoch) return;
  const failed = outcomes.filter((r) => r.status === "rejected");
  if (failed.length || state.desiredMode === "2d")
    notice(
      failed.length
        ? "Some map data could not load. Reload to try again."
        : !assets.tiles.length
          ? "Map images are not installed here. Names and pins remain available."
          : "",
    );
  if (epoch !== requests.epoch) return;
  if (
    state.tools.has("elevation") ||
    state.tools.has("slope") ||
    state.tools.has("contours")
  )
    try {
      await ensureTerrain();
    } catch (e) {
      notice(e.message);
    }
  draw();
  settled();
  renderLayers();
}
async function showScenery(input) {
  if (!assets?.objects.available) notice(assets?.objects.reason || "Scenery unavailable.");
  else {
    await ensureTerrain();
    if (state.mode === "2d") notice("Buildings & scenery appear in 3D.");
    else if (state.camera.zoom < 100) notice("Zoom in to see buildings & scenery.");
  }
  if (terrain) terrain.scenery = input.checked && !!assets?.objects.available;
}
function renderExtraLayers() {
  const box = $("baseLayers");
  box.replaceChildren();
  for (const [id, text] of [
    ["labels", "Place Names"],
    ["scenery", "Buildings & Scenery"],
  ]) {
    const input = h("input", { type: "checkbox", checked: layerOn.has(id) });
    input.dataset.layer = id;
    input.onchange = () => {
      input.checked ? layerOn.add(id) : layerOn.delete(id);
      if (id === "labels") $("labelSublayers").disabled = !input.checked;
      syncTop();
      saveView();
      draw();
      if (id === "scenery") run(showScenery)(input);
    };
    if (id === "scenery") input.dataset.bulk = "off"; // all on doesn't load the 3D terrain for it
    box.append(h("label", { className: "row" }, input, h("span", {}, text)));
    if (id === "labels") {
      const group = h("fieldset", {
        id: "labelSublayers",
        className: "label-sublayers",
        disabled: !input.checked,
      });
      group.setAttribute("aria-label", "Place name sub-layers");
      for (const [tier, title] of [
        ["continent", "Continents"],
        ["zone", "Zones"],
        ["town", "Towns"],
        ["subzone", "Subzones"],
        ["poi", "Landmarks"],
      ]) {
        const child = h("input", {
          type: "checkbox",
          checked: state.labelTiers.has(tier),
        });
        child.dataset.labelTier = tier;
        child.onchange = () => {
          child.checked
            ? state.labelTiers.add(tier)
            : state.labelTiers.delete(tier);
          draw();
          saveView();
        };
        group.append(h("label", { className: "row sub" }, child, h("span", {}, title)));
      }
      box.append(group);
    }
  }
}
async function restoreView() {
  restoring = true;
  stopMotion();
  const interaction = interactionEpoch;
  clearTimeout(saveTimer);
  let preference = "2d";
  try {
    preference = localStorage.getItem("atlas.view") || "2d";
  } catch {}
  const restored = viewState.readView(location.hash, preference);
  state.yaw = restored.yaw;
  state.tilt = restored.tilt;
  state.tools = new Set(restored.tools);
  state.labelTiers = new Set(restored.labelTiers);
  layerOn.clear();
  restored.layers.forEach((l) => layerOn.add(l));
  pinsOn = restored.pins;
  walkOn = state.tools.has("walk");
  state.desiredMode = restored.mode;
  const intro = restored.flyover && !restored.camera;
  let camera = restored.camera;
  if (!camera && (intro || !location.hash)) camera = startView();
  await loadWorld(camera);
  renderExtraLayers();
  $("layers").replaceChildren();
  renderLayers();
  for (const input of $("advanced").querySelectorAll("input[data-tool]"))
    input.checked = state.tools.has(input.dataset.tool);
  syncHeads();
  restoring = false;
  if (
    restored.flyover &&
    interaction === interactionEpoch &&
    !matchMedia("(prefers-reduced-motion: reduce)").matches
  )
    startFlyover({ intro });
  draw();
  settled();
}
$("viewBtn").onclick = run(() => {
  closeSheets();
  const mode = terrainLoading ? state.desiredMode : state.mode;
  return setMode(mode === "3d" ? "2d" : "3d");
});
$("zoomIn").onclick = () => {
  closeSheets();
  if (state.camera) flyTo(zoomGoal(W / 2, H / 2, state.camera.zoom * 1.5), 200);
};
$("zoomOut").onclick = () => {
  closeSheets();
  if (state.camera) flyTo(zoomGoal(W / 2, H / 2, state.camera.zoom / 1.5), 200);
};
$("tilt").oninput = (e) => {
  stopMotion();
  state.tilt = Number(e.target.value);
  updateViewControls();
  draw();
  settled();
};
$("rotateLeft").onclick = () => {
  stopMotion();
  state.yaw = Math.atan2(
    Math.sin(state.yaw - Math.PI / 8),
    Math.cos(state.yaw - Math.PI / 8),
  );
  updateViewControls();
  draw();
  settled();
};
$("rotateRight").onclick = () => {
  stopMotion();
  state.yaw = Math.atan2(
    Math.sin(state.yaw + Math.PI / 8),
    Math.cos(state.yaw + Math.PI / 8),
  );
  updateViewControls();
  draw();
  settled();
};
$("share").onclick = run(async () => {
  clearTimeout(saveTimer);
  hashWritten = viewState.writeView({ ...state, layers: layerOn, pins: pinsOn });
  history.replaceState(null, "", hashWritten);
  try {
    await navigator.clipboard.writeText(location.href);
    notice("View link copied.");
  } catch {
    notice("Your view is saved in the address bar. Copy the URL to share.");
  }
});
$("profile").onclick = run(async () => {
  const on = $("profile").getAttribute("aria-pressed") !== "true";
  $("profile").setAttribute("aria-pressed", String(on));
  profilePoints = [];
  $("profileResult").textContent = on
    ? "Tap two ground points on the map."
    : "";
  if (on) {
    closeSheets();
    notice("Profile: tap two ground points; open Advanced to see the chart.");
    try {
      await ensureTerrain();
    } catch (e) {
      notice(e.message);
    }
  }
  draw();
});
for (const input of $("advanced").querySelectorAll("input[data-tool]"))
  input.onchange = run(async () => {
    const id = input.dataset.tool;
    input.checked ? state.tools.add(id) : state.tools.delete(id);
    if (["elevation", "slope", "contours"].includes(id) && input.checked)
      try {
        await ensureTerrain();
      } catch (e) {
        notice(e.message);
      }
    walkOn = state.tools.has("walk");
    draw();
    settled();
  });
addEventListener(
  "hashchange",
  run(() => {
    if (location.hash !== hashWritten) return restoreView();
  }),
);
(async () => {
  await modulesReady;
  world = await get("/api/maps");
  // Pins have a drawn fallback; icon decoding must not gate the terrain.
  loadIcons()
    .then(draw)
    .catch(() => {
      if (!$("status").textContent)
        notice("Game icons unavailable; using simple pins.");
    });
  addEventListener("resize", resize);
  resize();
  // The page can start before its canvas has a size (a background tab, a pane not laid out yet): a camera worked
  // out then is NaN. Wait for one (polled: a hidden page gets no animation frames).
  for (let i = 0; !(W > 0 && H > 0) && i < 600; i++) {
    await new Promise((r) => setTimeout(r, 50));
    resize();
  }
  await restoreView();
  const observer = new ResizeObserver(placeSheets);
  observer.observe(place);
  window.visualViewport?.addEventListener("resize", resize);
  window.visualViewport?.addEventListener("scroll", placeSheets);
})().catch(fail);
