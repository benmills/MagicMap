// ---- The menu (its Advanced page) and the place popup. Their facts come from the server. ----
const controls = $("controls"),
  layersEl = $("layers"),
  place = $("place");
let MAP_NAME = "";
function h(tag, props, ...kids) {
  const e = Object.assign(document.createElement(tag), props);
  for (const k of kids.flat(Infinity))
    if (k != null && k !== false && k !== "" && k !== 0) e.append(k);
  return e;
}
function placeSheets() {
  const style = document.documentElement.style;
  const viewport = window.visualViewport;
  const top = viewport?.offsetTop || 0, left = viewport?.offsetLeft || 0;
  const height = viewport?.height || innerHeight, width = viewport?.width || innerWidth;
  style.setProperty("--viewport-top", `${top}px`);
  style.setProperty("--viewport-left", `${left}px`);
  style.setProperty("--viewport-bottom", `${Math.max(0, innerHeight - top - height)}px`);
  style.setProperty("--viewport-right", `${Math.max(0, innerWidth - left - width)}px`);
  style.setProperty("--visible-height", `${height}px`);
  if (!place.hidden) positionPlace();
}

// The menu and its Advanced page: one shown at a time, in the same place.
const SHEETS = ["settings", "advanced"];
const sheetOpen = () => SHEETS.some((id) => !$(id).hidden);
function setSheet(id = null) {
  for (const name of SHEETS) $(name).hidden = name !== id;
  $("menuBtn").setAttribute("aria-expanded", String(!!id));
  $("advancedBtn").setAttribute("aria-expanded", String(id === "advanced"));
  if (id) {
    closePlace();
    syncHeads();
  }
  if (id === "advanced") drawSwatches();
  placeSheets();
}
const closeSheets = () => setSheet();
$("menuBtn").onclick = () => setSheet(sheetOpen() ? null : "settings");
$("advancedBtn").onclick = () => setSheet("advanced");
for (const button of document.querySelectorAll("[data-back]")) // a page's way back to the menu
  button.onclick = () => setSheet("settings");
document.addEventListener("pointerdown", (e) => {
  if (!e.target.closest("#controls, .sheet")) closeSheets();
  if (!e.target.closest("#place")) closePlace();
});

// The menu's two switches. Each turns its whole kind off or on and keeps what Advanced picked within it; turned on
// with nothing picked, it brings back the defaults.
function syncTop() {
  $("pinsAll").checked = pinsOn && LAYERS.some(([id]) => layerOn.has(id));
  $("namesAll").checked = layerOn.has("labels") && state.labelTiers.size > 0;
  layersEl.classList.toggle("off", !pinsOn);
}
$("pinsAll").onchange = () => {
  pinsOn = $("pinsAll").checked;
  if (pinsOn && !LAYERS.some(([id]) => layerOn.has(id)))
    for (const row of layersEl.querySelectorAll("[data-layer]"))
      if (viewState.DEFAULT_LAYERS.includes(row.dataset.layer)) {
        layerOn.add(row.dataset.layer);
        row.querySelector("input").checked = true;
      }
  syncHeads();
  draw();
  refreshPins();
  saveView();
};
$("namesAll").onchange = () => {
  const on = $("namesAll").checked;
  if (on && !state.labelTiers.size)
    for (const tier of viewState.DEFAULT_LABEL_TIERS) {
      state.labelTiers.add(tier);
      const box = document.querySelector(`[data-label-tier="${tier}"]`);
      if (box) box.checked = true;
    }
  const box = $("baseLayers").querySelector('[data-layer="labels"]');
  box.checked = on;
  box.onchange();
  syncHeads();
};

// Turning many off or on at once: a section's header (input[data-all], naming the box its switches are in)
// sets them all, and "Hide All" / "Show All" every one on the Show on Map part. A switch marked data-bulk="off" is
// only ever turned off this way. The headers show all (✓), some (–) or none.
const switchesIn = (el) => [...el.querySelectorAll('input[type="checkbox"]:not([data-all])')];
function setSwitches(boxes, on) {
  for (const box of boxes) {
    if (box.checked === on || (on && box.dataset.bulk === "off")) continue;
    box.checked = on;
    box.onchange?.({ target: box });
  }
  syncHeads();
}
function syncHeads() {
  for (const head of document.querySelectorAll("input[data-all]")) {
    const boxes = switchesIn($(head.dataset.all) || document.createElement("div")), on = boxes.filter((b) => b.checked).length;
    head.checked = boxes.length > 0 && on === boxes.length;
    head.indeterminate = on > 0 && on < boxes.length;
  }
  const any = switchesIn($("layerSheet")).some((b) => b.checked);
  $("allLayers").firstChild.textContent = any ? "Hide All" : "Show All";
  syncTop();
}
for (const head of document.querySelectorAll("input[data-all]")) bindHead(head);
function bindHead(head) {
  head.onchange = () => setSwitches(switchesIn($(head.dataset.all)), head.checked);
}
document.addEventListener("change", (e) => {
  if (e.target.dataset?.all) return;
  if (e.target.closest?.(".sheet")) syncHeads();
});
$("allLayers").onclick = () => {
  const boxes = switchesIn($("layerSheet"));
  setSwitches(boxes, !boxes.some((b) => b.checked));
};

// The layer icons, drawn again once the icons have loaded (and on opening): the first may have come before.
function drawSwatches() {
  for (const [layer, , , sample] of LAYERS) layersEl.querySelector(`[data-layer="${layer}"] canvas`)?.replaceWith(pinSwatch(layer, sample, 18));
}

// The pin layers: a toggle per layer, each with its icon as the legend. Picking one shows pins again.
function swatch(px, paint) {
  const c = h("canvas", { width: px * dpr, height: px * dpr });
  c.style.cssText = `width:${px}px;height:${px}px;flex:none`;
  const g = c.getContext("2d");
  g.scale(dpr, dpr);
  paint(g, px / 2);
  return c;
}
const pinSwatch = (layer, sample, px = 28) =>
  swatch(px, (g, m) =>
    drawPin(g, layer, sample, m, m, Math.min(1, px / PIN_SIZE[layer])),
  );
function renderLayers() {
  if (!layersEl.firstChild) {
    for (const [id, name, , sample] of LAYERS) {
      const box = h("input", { type: "checkbox", checked: layerOn.has(id) });
      box.onchange = () => {
        box.checked ? layerOn.add(id) : layerOn.delete(id);
        if (box.checked) pinsOn = true;
        draw();
        refreshPins();
        saveView();
      };
      const row = h(
        "label",
        { className: "row" },
        box,
        h("span", {}, name),
        h("small"),
        pinSwatch(id, sample, 18),
      );
      row.dataset.layer = id;
      layersEl.append(row);
    }
  }
  for (const [id, , minZoom] of LAYERS) {
    layersEl.querySelector(`[data-layer="${id}"] small`).textContent =
      state.camera.zoom < minZoom ? "zoom in" : "";
  }
  syncTop();
}

// The place popup: a tap on the map (or a pin) names the zone and the place there, with two ways in: closer on the
// map, or a flight down into 3D there. A drag, a tap elsewhere, Escape or the map moving closes it.
let placeSeq = 0,
  placeAt = null; // { col, row }
function openPlace(x, y, pin = null) {
  const hit = pin ? [pin.col, pin.row] : toTile(x, y);
  if (!hit || !hit.every(Number.isFinite)) return closePlace();
  const [col, row] = hit, seq = ++placeSeq;
  placeAt = { col, row };
  const pinName = pin && (pin.kind === "group"
    ? pin.members.map((m) => m.name).filter(Boolean).slice(0, 2).join(", ") + (pin.count > 2 ? ` +${pin.count - 2}` : "")
    : pin.name);
  const [title, sub] = place.querySelector(".names").children;
  title.textContent = pinName || "…";
  sub.textContent = "";
  $("place3D").hidden = state.mode === "3d";
  place.hidden = false;
  positionPlace();
  get(`/api/at?col=${col}&row=${row}`).then((a) => {
    if (seq !== placeSeq) return;
    const zone = a.zone?.name || a.area?.zone, spot = a.area?.subzone !== zone ? a.area?.subzone : null;
    const names = [...new Set([pinName, spot, zone].filter(Boolean))];
    title.textContent = names[0] || "Open sea";
    sub.textContent = names.slice(1).join(" · ");
    positionPlace();
  }).catch(() => {
    if (seq === placeSeq && title.textContent === "…") title.textContent = MAP_NAME;
  });
}
function closePlace() {
  if (place.hidden) return;
  placeSeq++;
  place.hidden = true;
}
// Over its point, its tail on it; below it when there's no room above; never past the screen's sides.
function positionPlace() {
  if (!placeAt) return;
  const [x, y] = toScreen(placeAt.col, placeAt.row), rect = canvas.getBoundingClientRect();
  const px = rect.left + (x * rect.width) / W, py = rect.top + (y * rect.height) / H;
  const box = place.getBoundingClientRect(), margin = 8;
  const below = py - box.height - 14 < margin;
  const left = clamp(px - box.width / 2, margin, innerWidth - box.width - margin);
  place.classList.toggle("below", below);
  place.style.left = `${left}px`;
  place.style.top = `${below ? py + 14 : py - box.height - 14}px`;
  place.style.setProperty("--tail", `${clamp(px - left, 14, box.width - 14)}px`);
}
$("placeZoom").onclick = () => {
  const at = placeAt;
  closePlace();
  if (at) zoomInAt(at.col, at.row);
};
$("place3D").onclick = run(() => {
  const at = placeAt;
  closePlace();
  if (at) return diveInAt(at.col, at.row);
});

addEventListener("keydown", (e) => {
  if (e.key !== "Escape") return;
  if (sheetOpen()) {
    closeSheets();
    $("menuBtn").focus();
  } else if (!place.hidden) {
    closePlace();
    canvas.focus({ preventScroll: true });
  }
});
