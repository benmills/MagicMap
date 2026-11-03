// ---- Sheets, search, cards and highlights: all their facts come from the server. ----
const ui = $("ui"),
  q = $("q"),
  results = $("results"),
  layersEl = $("layers"),
  layersBtn = $("layersBtn"),
  card = $("card"),
  hl = $("hl");
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
  style.setProperty("--visible-bottom", `${top + height}px`);
  style.setProperty("--below", `${ui.getBoundingClientRect().bottom + 6}px`);
  style.removeProperty("--controls-bottom");
  style.removeProperty("--controls-right");
  style.removeProperty("--notice-bottom");
  if (!card.hidden) {
    const r = card.getBoundingClientRect();
    if (r.left < innerWidth / 2 && r.width > innerWidth * 0.7) {
      style.setProperty("--controls-bottom", `${innerHeight - r.top + 8}px`);
      style.setProperty("--notice-bottom", `${innerHeight - r.top + 8}px`);
    } else {
      style.setProperty("--controls-right", `${innerWidth - r.left + 8}px`);
    }
  }
}
// All secondary surfaces share the same small transition, including async search.
function setSheet(id = null) {
  if (id && Review.isOn()) $("reviewBtn").click(); // one sheet in that spot
  if (id !== "results") requests?.ticket("find");
  results.hidden = id !== "results";
  for (const name of ["searchSheet", "settings", "layerSheet", "tools"])
    $(name).hidden = name !== (id === "results" ? "searchSheet" : id);
  for (const [button, sheet] of [["menuBtn", "settings"], ["layersBtn", "layerSheet"], ["toolsBtn", "tools"]])
    $(button).setAttribute("aria-expanded", String(sheet === id));
  if (id && id !== "results") q.blur();
  placeSheets();
}
function closeSheets() {
  setSheet();
  q.blur();
}
function setLayersOpen(open) { setSheet(open ? "layerSheet" : null); }
layersBtn.onclick = () => setLayersOpen($("layerSheet").hidden);
$("menuBtn").onclick = () => setSheet($("settings").hidden ? "settings" : null);
$("searchBtn").onclick = () => { setSheet("results"); q.focus(); };
for (const button of document.querySelectorAll("[data-close-sheet]"))
  button.onclick = () => { closeSheets(); $("menuBtn").focus(); };
document.addEventListener("pointerdown", (e) => {
  if (!e.target.closest("#ui, .sheet")) closeSheets();
});

// The layers sheet: a toggle per layer, each with its icon as the legend.
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
        draw();
        refreshPins();
        saveView();
      };
      const row = h(
        "label",
        { className: "row" },
        box,
        pinSwatch(id, sample),
        h("span", {}, name),
        h("small"),
      );
      row.dataset.layer = id;
      layersEl.append(row);
    }
    const key = (layer, sample, text) =>
      h("span", {}, pinSwatch(layer, sample, 20), text);
    layersEl.append(
      h(
        "div",
        { className: "legend" },
        ...Object.keys(FACTION).map((f) =>
          key(
            "flight",
            { faction: f },
            f === "AH" ? "Neutral" : FACTION_NAME[f],
          ),
        ),
        h(
          "div",
          {},
          "Services and quest givers glow in their faction's colour:",
        ),
        ...Object.keys(FACTION).map((f) =>
          key("service", { mark: "innkeeper", faction: f }, FACTION_NAME[f]),
        ),
        h("div", {}),
        ...Object.entries(SERVICE_NAME).map(([mark, name]) =>
          key("service", { mark }, name),
        ),
        h("div", {}),
        ...Object.keys(GAME_ICON.dungeon).map((mark) =>
          key("dungeon", { mark }, mark[0].toUpperCase() + mark.slice(1)),
        ),
        ...Object.keys(GAME_ICON.rare).map((mark) =>
          key("rare", { mark }, RANK[mark]),
        ),
        h(
          "span",
          {},
          swatch(20, (g, m) => drawRing(g, m, m, 0.9)),
          "Highlighted spawns",
        ),
      ),
    );
  }
  for (const [id, , minZoom] of LAYERS) {
    layersEl.querySelector(`[data-layer="${id}"] small`).textContent =
      state.camera.zoom < minZoom ? "zoom in to see" : "";
  }
}

// Search: Atlas.Find over NPCs, quests, objects and items.
let findTimer,
  findSeq = 0;
q.addEventListener("input", () => {
  clearTimeout(findTimer);
  const ticket = requests.ticket("find");
  const text = q.value.trim();
  results.replaceChildren(h("div", { className: "row" }, "Searching…"));
  if (text.length < 2) {
    results.replaceChildren(h("p", {}, "Search places, NPCs, quests and items."));
    return;
  }
  setSheet("results");
  findTimer = setTimeout(
    run(async () => {
      const seq = ++findSeq,
        found = await get(`/api/find?q=${encodeURIComponent(text)}`);
      if (seq !== findSeq || !requests.current(ticket)) return;
      results.replaceChildren(
        ...(found.length
          ? found.map((r) =>
              h(
                "button",
                { className: "row", onclick: run(() => pick(r)) },
                h("span", { className: `tag ${r.kind}` }, r.kind),
                h("span", {}, r.name),
                r.detail && h("small", {}, r.detail),
              ),
            )
          : [h("div", { className: "row" }, "No matches")]),
      );
      setSheet("results");
    }),
    200,
  );
});
q.addEventListener("focus", () => {
  setSheet("results");
});
q.addEventListener("keydown", (e) => {
  if (e.key === "Enter") results.querySelector("button")?.click();
});
async function pick(r) {
  closeSheets();
  if (r.kind === "place") return navigatePlace(r.id);
  if (r.kind === "poi") {
    await openCard("poi", r.id, { data: r });
    return fitTo([r]);
  }
  return openCard(r.kind, r.id, { highlight: true, fly: true });
}

// Entities, fetched once each.
const fetched = new Map();
const entity = (kind, id) => {
  const k = `${kind}:${id}`;
  if (!fetched.has(k))
    fetched.set(
      k,
      get(`/api/${kind}?id=${id}`).catch((e) => {
        fetched.delete(k);
        throw e;
      }),
    );
  return fetched.get(k);
};
const spawnsOf = (e) =>
  (e.spawns.find((s) => s.inst === state.inst)?.points || []).map(
    ([col, row]) => ({ col, row, kind: e.kind, id: e.id }),
  );
function elsewhere(e) {
  // where an entity is that this map doesn't show
  const parts = e.spawns
    .filter((s) => s.inst !== state.inst)
    .map(
      (s) =>
        `${s.points.length} spawn${s.points.length > 1 ? "s" : ""} on ${s.map}`,
    );
  for (const d of e.instances) parts.push(`inside ${d.name}`);
  return parts.join(", ");
}

// The highlight: a set of spawns drawn on top until cleared.
function setHighlight(text, points, from) {
  state.sources = [
    ...new Map(
      points
        .filter((p) => p.kind && p.id)
        .map((p) => [`${p.kind}:${p.id}`, { kind: p.kind, id: p.id }]),
    ).values(),
  ];
  highlight = points.length ? { pts: points, from } : null;
  hl.firstChild.textContent = text;
  hl.hidden = false;
  placeSheets();
  draw();
  saveView();
}
hl.lastChild.onclick = () => {
  highlight = null;
  state.sources = [];
  hl.hidden = true;
  placeSheets();
  draw();
  saveView();
};

// Fit into the largest useful rectangle left by the actual visible controls.
function visibleMapRect() {
  const headerStyle = getComputedStyle(ui);
  const start = mapPoint(parseFloat(headerStyle.left) + 4, parseFloat(headerStyle.top) + 4);
  const end = mapPoint(
    innerWidth - parseFloat(getComputedStyle($("scaleWrap")).right) - 4,
    innerHeight - parseFloat(getComputedStyle($("readout")).bottom) - 4,
  );
  let rect = { left: start.x, top: start.y, right: end.x, bottom: end.y };
  for (const el of [ui, card, $("viewControls")]) {
    if (el.hidden) continue;
    const bounds = el.getBoundingClientRect();
    const topLeft = mapPoint(bounds.left, bounds.top), bottomRight = mapPoint(bounds.right, bounds.bottom);
    const r = { left: topLeft.x, top: topLeft.y, right: bottomRight.x, bottom: bottomRight.y };
    if (r.right <= rect.left || r.left >= rect.right || r.bottom <= rect.top || r.top >= rect.bottom) continue;
    const choices = [
      { ...rect, top: r.bottom + 12 }, { ...rect, bottom: r.top - 12 },
      { ...rect, left: r.right + 12 }, { ...rect, right: r.left - 12 },
    ];
    rect = choices.reduce((best, candidate) =>
      Math.max(0, candidate.right - candidate.left) * Math.max(0, candidate.bottom - candidate.top) >
      Math.max(0, best.right - best.left) * Math.max(0, best.bottom - best.top) ? candidate : best);
  }
  return rect;
}
function centerFit(goal, rect, mode = state.mode) {
  const x = (rect.left + rect.right) / 2, y = (rect.top + rect.bottom) / 2;
  if (mode === "3d") {
    const keep = state.camera;
    terrain.setView(goal, W, H, state.yaw, state.tilt);
    const c = terrain.plane(x, y);
    goal.cx -= c[0] - goal.cx;
    goal.cy -= c[1] - goal.cy;
    terrain.setView(keep, W, H, state.yaw, state.tilt);
  } else {
    goal.cx -= (x - W / 2) / goal.zoom;
    goal.cy -= (y - H / 2) / goal.zoom;
  }
  return goal;
}
async function fitTo(points) {
  if (!points.length) return;
  const r = visibleMapRect();
  const goal = activeView().fit(points, Math.max(100, r.right - r.left), Math.max(100, r.bottom - r.top));
  // Automatic selections stop at the map imagery's native pixel density.
  goal.zoom = Math.min(goal.zoom, TEXELS / dpr);
  flyTo(centerFit(goal, r), 500);
}

// Highlight the spawns of some npcs / objects (a quest objective's or an item's sources) and fit to them.
async function showSources(refs, label, options = {}) {
  const ticket = requests.ticket("sources");
  if (
    refs.every((r) => r.kind === "flight") &&
    state.selection?.kind === "flight"
  ) {
    const flight = await entity("flight", state.selection.id);
    if (!requests.current(ticket)) return false;
    const destinations = flight.destinations.filter(
      (d) => d.inst === state.inst,
    );
    setHighlight(
      flight.name,
      destinations,
      flight.inst === state.inst ? [flight.col, flight.row] : null,
    );
    return true;
  }
  const es = await Promise.all(
    refs
      .filter((r) => r.kind === "npc" || r.kind === "object")
      .map((r) => entity(r.kind, r.id)),
  );
  if (!requests.current(ticket)) return false;
  const points = es.flatMap(spawnsOf);
  if (points.length) {
    setHighlight(`${label} · ${points.length} spawns`, points);
    if (!options.restore) await fitTo(points);
  } else {
    setHighlight(`${label}: no spawns on ${MAP_NAME}`, []);
    const status = card.querySelector(".status");
    if (status)
      status.textContent =
        es.map(elsewhere).filter(Boolean).join("; ") ||
        "No known outdoor spawns.";
  }
  return true;
}

// Cards: one entity each; refs inside open more cards (with a way back).
const stack = [];
const levels = (a, b) => a && (b && b !== a ? `lv ${a}–${b}` : `lv ${a}`);
const money = (c) =>
  [
    [Math.floor(c / 10000), "g"],
    [Math.floor(c / 100) % 100, "s"],
    [c % 100, "c"],
  ]
    .filter(([v]) => v)
    .map((x) => x.join(""))
    .join(" ");
const sub = (...parts) =>
  h("div", { className: "sub" }, parts.filter(Boolean).join(" · "));
function refButton(r, onclick) {
  return h(
    "button",
    { className: "ref", onclick },
    h("span", { className: `tag ${r.kind}` }, r.kind),
    h("span", {}, r.name),
    r.level && h("small", {}, `lv ${r.level}`),
    r.cost != null && h("small", {}, money(r.cost)),
  );
}
const follow = (r) =>
  run(() => openCard(r.kind, r.id, { highlight: true, fly: true }));
const refList = (title, refs) =>
  refs.length && [
    h("h3", {}, title),
    h(
      "div",
      { className: "refs" },
      refs.map((r) => refButton(r, follow(r))),
    ),
  ];
// Sources: tap to highlight their spawns, › for the card.
function sourceList(title, refs) {
  if (!refs.length) return null;
  return [
    h("h3", {}, title),
    h(
      "div",
      { className: "refs" },
      refs.length > 1 &&
        h(
          "button",
          { className: "ref", onclick: run(() => showSources(refs, title)) },
          h("span", {}, `◎ Show all ${refs.length} on the map`),
        ),
      refs.map((r) =>
        r.kind === "item"
          ? refButton(r, follow(r))
          : h(
              "div",
              { className: "src" },
              h(
                "button",
                {
                  className: "ref",
                  onclick: run(() => showSources([r], r.name)),
                },
                h("span", {}, `◎ ${r.name}`),
              ),
              h(
                "button",
                {
                  className: "x",
                  ariaLabel: `${r.name} details`,
                  onclick: follow(r),
                },
                "›",
              ),
            ),
      ),
    ),
  ];
}
function spawnInfo(e) {
  const here = spawnsOf(e).length,
    other = elsewhere(e);
  return [
    h(
      "p",
      {},
      here
        ? `${here} spawn${here > 1 ? "s" : ""} on ${MAP_NAME}`
        : `Not on ${MAP_NAME}.`,
    ),
    other &&
      h("p", { className: "note" }, `${here ? "Also" : "Found"} ${other}.`),
  ];
}
const RENDER = {
  group: (d) => [
    h("h2", {}, `${d.count} nearby places`),
    sub("Choose a location"),
    h("div", { className: "refs" }, d.members.map((p) =>
      h("button", { className: "ref", onclick: run(() => openPin(p)) },
        h("span", {}, p.name || `${p.kind} #${p.id}`),
        h("small", {}, LAYERS.find(([id]) => id === p.layer)?.[1] || p.kind)))),
  ],
  npc: (d) => [
    h("h2", {}, d.name),
    sub(
      d.subName && `<${d.subName}>`,
      "NPC",
      levels(d.minLevel, d.maxLevel),
      RANK[d.rank],
      FACTION_NAME[d.faction],
    ),
    d.services.length &&
      h(
        "div",
        { className: "chips" },
        d.services.map((s) => h("span", {}, s)),
      ),
    spawnInfo(d),
    refList("Starts", d.questStarts),
    refList("Ends", d.questEnds),
  ],
  object: (d) => [
    h("h2", {}, d.name),
    sub("Object", d.objectKind),
    spawnInfo(d),
    refList("Starts", d.questStarts),
    refList("Ends", d.questEnds),
  ],
  item: (d) => [
    h("h2", {}, d.name),
    sub("Item", d.requiredLevel && `requires lv ${d.requiredLevel}`),
    d.startQuest && refList("Starts quest", [d.startQuest]),
    sourceList("Dropped by", d.npcDrops),
    sourceList("Contained in", d.objectDrops),
    sourceList("Sold by", d.vendors),
    refList("Comes from", d.itemDrops),
  ],
  quest: (d) => [
    h("h2", {}, d.name),
    sub(
      "Quest",
      d.level && `lv ${d.level}`,
      d.requiredLevel && `requires ${d.requiredLevel}`,
      FACTION_NAME[d.faction] || "either faction",
      d.zone,
    ),
    d.objectivesText.map((t) => h("p", {}, t)),
    refList("Starts at", d.startedBy),
    refList("Ends at", d.finishedBy),
    d.objectives.map((o) => [
      o.kind === "item" &&
        refButton(
          { kind: "item", id: o.id, name: o.name || `Item #${o.id}` },
          follow({ kind: "item", id: o.id }),
        ),
      o.sources.length
        ? sourceList(`${o.kind}: ${o.name || o.text}`, o.sources)
        : [h("h3", {}, o.kind), h("p", {}, o.text || o.name || `#${o.id}`)],
    ]),
    d.triggerEnd && [
      h("h3", {}, "Explore"),
      h(
        "button",
        {
          className: "ref",
          onclick: () => {
            const points = spawnsOf({
              ...d.triggerEnd,
              kind: "quest",
              id: d.id,
            });
            if (points.length) {
              setHighlight(d.triggerEnd.text, points);
              fitTo(points);
            } else
              card.querySelector(".status").textContent = `Not on ${MAP_NAME}.`;
          },
        },
        h("span", {}, `◎ ${d.triggerEnd.text}`),
      ),
    ],
  ],
  flight: (d) => [
    h("h2", {}, d.name),
    sub("Flight point", FACTION_NAME[d.faction], d.area),
    refList(`Flies to (${d.destinations.length})`, d.destinations),
  ],
  dungeon: (d) => [
    h("h2", {}, d.name),
    sub(
      d.dungeonKind,
      d.minLevel && `from lv ${d.minLevel}`,
      d.maxPlayers && `${d.maxPlayers} players`,
    ),
    d.bosses.length && [
      h("h3", {}, "Bosses"),
      h(
        "div",
        { className: "chips" },
        d.bosses.map((b) => h("span", {}, b)),
      ),
    ],
  ],
  poi: (d) => [
    h("h2", {}, d.name),
    sub("Point of interest"),
    d.description && h("p", {}, d.description),
  ],
};
function renderCard() {
  const d = stack[stack.length - 1];
  const [title, ...body] = RENDER[d.kind](d); // the title sits in the bar, between back and close
  card.replaceChildren(
    h(
      "div",
      { className: "bar" },
      stack.length > 1 &&
        h(
          "button",
          {
            className: "x",
            ariaLabel: "Back",
            onclick: () => {
              stack.pop();
              renderCard();
            },
          },
          "‹",
        ),
      title,
      h(
        "button",
        { className: "x", ariaLabel: "Close", onclick: closeCard },
        "✕",
      ),
    ),
    h("div", {}, body),
    h("p", { className: "note status" }),
  );
  state.selection = d.kind === "group" ? null : { kind: d.kind, id: d.id };
  card.hidden = false;
  card.scrollTop = 0;
  placeSheets();
  saveView();
}
function closeCard() {
  cardSeq++;
  requests.ticket("sources");
  stack.length = 0;
  state.selection = null;
  card.hidden = true;
  placeSheets();
  saveView();
}
let cardSeq = 0;
async function openCard(kind, id, opts = {}) {
  requests.ticket("sources");
  const seq = ++cardSeq,
    epoch = requests.epoch,
    d = opts.data || (await entity(kind, id));
  if (seq !== cardSeq || epoch !== requests.epoch) return;
  if (card.hidden) stack.length = 0;
  state.selection = { kind, id };
  stack.push(d);
  renderCard();
  saveView();
  if (!opts.highlight) return;
  if (kind === "npc" || kind === "object") {
    const points = spawnsOf(d);
    if (!points.length) return; // the card says where it is instead
    setHighlight(
      `${d.name} · ${points.length} spawn${points.length > 1 ? "s" : ""}`,
      points,
    );
    if (opts.fly) fitTo(points);
  } else if (kind === "dungeon" && opts.fly) {
    if (d.col != null) fitTo([d]);
  } else if (kind === "flight") {
    const dests = d.destinations
      .filter((x) => x.inst === state.inst)
      .map((x) => ({ col: x.col, row: x.row, kind: "flight", id: x.id }));
    setHighlight(`${d.name} · flies to ${d.destinations.length}`, dests, [
      d.col,
      d.row,
    ]);
    if (opts.fly) fitTo([...dests, { col: d.col, row: d.row }]);
  }
}
function openPin(p) {
  closeSheets();
  if (p.kind === "group") return openCard("group", p.key, { data: p });
  if (p.kind === "poi") return openCard("poi", p.id, { data: { ...p } });
  else
    return openCard(p.kind, p.id, {
      highlight: p.kind !== "dungeon",
      fly: p.kind === "flight",
    }); // a flight point: show its routes
}
addEventListener("keydown", (e) => {
  if (e.key !== "Escape") return;
  const hasSheet = ["searchSheet", "settings", "layerSheet", "tools"].some((id) => !$(id).hidden);
  if (hasSheet || document.activeElement === q) {
    closeSheets();
    $("menuBtn").focus();
  } else if (!card.hidden) {
    closeCard();
    canvas.focus({ preventScroll: true });
  }
});
