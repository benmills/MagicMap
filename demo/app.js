// Composition root. Classic scripts keep the original canvas painters; pure view/terrain
// modules are loaded on demand. No bundler and no changes to the Atlas Lua contract.
let saveTimer,
  hashWritten = "";
function saveView({ immediate = false } = {}) {
  if (restoring || !viewState || !state.camera) return;
  clearTimeout(saveTimer);
  const write = () => {
    hashWritten = viewState.writeView({ ...state, layers: layerOn, marker });
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
  $("compass").title = "Reset bearing to north";
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
          updateDiagnostics();
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
async function setMode(mode, { remember = true } = {}) {
  const seq = ++modeSeq,
    epoch = requests.epoch;
  stopMotion();
  if (terrain) terrain.focusLocked = false;
  terrainLoading = mode === "3d";
  state.desiredMode = mode;
  updateViewControls();
  if (remember)
    try {
      localStorage.setItem("atlas.view", mode);
    } catch {}
  if (mode === "3d") {
    notice("Loading terrain…");
    try {
      await ensureTerrain();
      if (seq !== modeSeq || epoch !== requests.epoch) return;
      state.mode = "3d";
      const coverage = assets.terrain.data;
      notice(
        coverage.tiles.length < coverage.expectedTiles
          ? `Ground coverage: ${coverage.tiles.length}/${coverage.expectedTiles} ADT files. Unsampled ground remains unknown.`
          : "",
      );
    } catch (e) {
      if (seq !== modeSeq || epoch !== requests.epoch) return;
      state.mode = "2d";
      notice(`${e.message} Using 2D.`);
    }
  } else {
    state.mode = "2d";
    notice("");
  }
  terrainLoading = false;
  updateViewControls();
  draw();
  settled();
}
async function navigatePlace(uiMapID, inst = state.inst) {
  stopMotion();
  if (inst !== state.inst) await switchMap(inst);
  closeSheets();
  const r = visibleMapRect();
  const ticket = requests.ticket("fit"),
    got = await get(`/api/fit?uiMapID=${uiMapID}&w=${Math.max(100, r.right-r.left)}&h=${Math.max(100, r.bottom-r.top)}`);
  if (!requests.current(ticket)) return;
  if (got.inst !== state.inst) await switchMap(got.inst);
  flyTo(centerFit(got.cam, r), 450);
  $("zone").value = String(uiMapID);
}
async function switchMap(inst, { camera = null, keepSelection = true } = {}) {
  const m = maps.find((m) => m.inst === inst);
  if (!m) throw Error(`Unknown map ${inst}`);
  const previousSources = keepSelection ? [...state.sources] : [];
  const selectionSeq = cardSeq;
  stopMotion();
  requests.reset();
  const epoch = requests.epoch;
  ++modeSeq;
  terrainLoading = false;
  clearTimeout(pinTimer);
  clearTimeout(walkTimer);
  clearTimeout(hoverTimer);
  clearTimeout(findTimer);
  state.inst = inst;
  const visible = visibleMapRect();
  state.camera = camera || centerFit(viewState.fitBounds(
    m.bounds, visible.right - visible.left, visible.bottom - visible.top, 0.82,
  ), visible, "2d");
  state.mode = "2d";
  assets = null;
  tiles = [];
  pins = [];
  drawnPins = [];
  labels = [];
  labelState.clear();
  walk = null;
  marker = null;
  profilePoints = [];
  highlight = null;
  hl.hidden = true;
  state.sources = [];
  closeSheets();
  MAP_NAME = m.name;
  bg = rgb(m.bg || [0.03, 0.06, 0.06]);
  $("zone").replaceChildren(new Option("Go to a zone…", ""));
  for (const z of m.zones) $("zone").add(new Option(z.name, z.uiMapID));
  if (!keepSelection) closeCard();
  else if (stack.length) renderCard();
  updateViewControls();
  draw();
  notice(`Loading ${m.name}…`);
  const metadata = Promise.allSettled([
    loadTiles(),
    loadLabels(),
  ]);
  const got = await get(`/api/assets?inst=${inst}`);
  if (epoch !== requests.epoch) return;
  assets = got;
  // Start drawing terrain as soon as its index arrives; labels and borders can follow.
  if (state.desiredMode === "3d") await setMode("3d", { remember: false });
  const outcomes = await metadata;
  if (epoch !== requests.epoch) return;
  const failed = outcomes.filter((r) => r.status === "rejected");
  if (failed.length || state.desiredMode === "2d")
    notice(
      failed.length
        ? "Some map data could not load. Try another map or reload."
        : !assets.tiles.length
          ? "Map images are not installed here. Names, borders, search and pins remain available."
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
  if (previousSources.length && cardSeq === selectionSeq) {
    const restored = await showSources(previousSources, "Selected sources", {
      restore: true,
    });
    if (epoch !== requests.epoch) return false;
    if (restored) state.sources = previousSources;
  }
  draw();
  settled();
  renderLayers();
  return true;
}
function renderExtraLayers() {
  const box = $("baseLayers");
  box.replaceChildren();
  for (const [id, text] of [
    ["labels", "Place names"],
    ["scenery", "Buildings & scenery"],
  ]) {
    const input = h("input", { type: "checkbox", checked: layerOn.has(id) });
    input.dataset.layer = id;
    input.onchange = run(async () => {
      input.checked ? layerOn.add(id) : layerOn.delete(id);
      if (id === "labels") $("labelSublayers").disabled = !input.checked;
      if (id === "scenery") {
        if (!assets?.objects.available)
          notice(assets?.objects.reason || "Scenery unavailable.");
        else {
          await ensureTerrain();
          if (state.mode === "2d") notice("Buildings & scenery appear in 3D.");
          else if (state.camera.zoom < 100)
            notice("Zoom in to see buildings & scenery.");
        }
        if (terrain)
          terrain.scenery = input.checked && !!assets?.objects.available;
      }
      saveView();
      draw();
    });
    box.append(h("label", { className: "row" }, input, text));
    if (id === "labels") {
      const group = h("fieldset", {
        id: "labelSublayers",
        className: "label-sublayers",
        disabled: !input.checked,
      });
      group.setAttribute("aria-label", "Place name sub-layers");
      for (const [tier, title] of [
        ["continent", "Continents"],
        ["zone", "Major zones"],
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
        group.append(h("label", { className: "row" }, child, title));
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
  walkOn = state.tools.has("walk");
  state.desiredMode = restored.mode;
  closeCard();
  state.sources = [];
  const inst = maps[0].inst; // (one map; a link from before it opens here)
  const intro = restored.flyover && !restored.camera;
  let camera = restored.camera;
  if (!camera && (intro || !location.hash)) {
    const bounds = maps.find((m) => m.inst === inst).bounds;
    camera = {
      cx: (bounds[0] + bounds[2]) / 2,
      cy: (bounds[1] + bounds[3]) / 2,
      zoom: Math.min((W - 60) / (bounds[2] - bounds[0]), (H - 60) / (bounds[3] - bounds[1])),
    };
    if (!intro) camera = centerFit(camera, visibleMapRect(), "2d");
  }
  await switchMap(inst, { camera });
  if (restored.selection) {
    try {
      if (restored.selection.kind === "poi") {
        const found = await get(
          `/api/pins?inst=${state.inst}&c0=0&r0=0&c1=128&r1=64&zoom=1024&layers=poi`,
        );
        const p = found.find((p) => p.id === restored.selection.id);
        if (p) await openCard("poi", p.id, { data: p });
      } else await openCard(restored.selection.kind, restored.selection.id);
    } catch (e) {
      notice(`The linked selection is unavailable: ${e.message}`);
    }
  }
  if (restored.sources.length) {
    const flights = restored.sources.filter((r) => r.kind === "flight");
    if (flights.length && state.selection?.kind === "flight") {
      const d = await entity("flight", state.selection.id);
      setHighlight(
        d.name,
        d.destinations.filter((d) => d.inst === state.inst),
        [d.col, d.row],
      );
    } else
      await showSources(restored.sources, "Shared sources", { restore: true });
  }
  marker = restored.marker;
  renderExtraLayers();
  $("layers").replaceChildren();
  renderLayers();
  for (const input of $("tools").querySelectorAll("input[data-tool]"))
    input.checked = state.tools.has(input.dataset.tool);
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
  if (state.camera) flyTo(zoomGoal(W / 2, H / 2, state.camera.zoom * 1.5), 200);
};
$("zoomOut").onclick = () => {
  if (state.camera) flyTo(zoomGoal(W / 2, H / 2, state.camera.zoom / 1.5), 200);
};
$("compass").onclick = () => {
  stopMotion();
  state.yaw = 0;
  updateViewControls();
  draw();
  settled();
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
$("toolsBtn").onclick = () => {
  setSheet($("tools").hidden ? "tools" : null);
  updateDiagnostics();
};
$("share").onclick = run(async () => {
  clearTimeout(saveTimer);
  hashWritten = viewState.writeView({ ...state, layers: layerOn, marker });
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
    notice("Profile: tap two ground points; open Tools to see the chart.");
    try {
      await ensureTerrain();
    } catch (e) {
      notice(e.message);
    }
  }
  draw();
});
for (const input of $("tools").querySelectorAll("input[data-tool]"))
  input.onchange = run(async () => {
    const id = input.dataset.tool;
    if (id === "diagnostics") $("locationDiagnostics").hidden = !input.checked;
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
  maps = await get("/api/maps");
  // Pins have a drawn fallback; icon decoding must not gate the terrain.
  loadIcons()
    .then(draw)
    .catch(() => {
      if (!$("status").textContent)
        notice("Game icons unavailable; using simple pins.");
    });
  addEventListener("resize", resize);
  resize();
  await restoreView();
  // The map review: tools/maplint.py's issues, marked on the server (review.js, review_api.py).
  Review.mount({ ctx: () => ctx, toScreen, zoom: () => state.camera.zoom, inst: () => state.inst, draw,
    sheet: $("reviewSheet"), button: $("reviewBtn"), onOpen: () => setSheet(null),
    fly: run(async (i) => {
      if (i.inst !== state.inst) await switchMap(i.inst);
      return fitTo([{ col: i.bbox[0], row: i.bbox[1] }, { col: i.bbox[2], row: i.bbox[3] }]);
    }) }).catch(fail);
  const observer = new ResizeObserver(placeSheets);
  observer.observe(ui);
  observer.observe(card);
  window.visualViewport?.addEventListener("resize", resize);
  window.visualViewport?.addEventListener("scroll", placeSheets);
})().catch(fail);
