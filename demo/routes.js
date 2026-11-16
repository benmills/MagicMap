// The Routes page (routes.html): walk_cases.json's grid cases, previous walk vs new, run now by the server
// (/api/cases: each case on each side, its numbers and line). Each case is a pair of map views of the same box, the
// map's own tiles drawn straight onto a canvas when they load, then the route; no animation loop, so the page draws
// in a hidden pane. ?sides=31,2 in the address compares other walks (311 3.1.1, 31 main before v2, 2 v2).
const $ = (id) => document.getElementById(id);
function h(tag, props, ...kids) {
  const e = Object.assign(document.createElement(tag), props);
  for (const k of kids.flat(Infinity)) if (k != null && k !== false && k !== "") e.append(k);
  return e;
}
const TILE_YD = 1600 / 3;
const SIZES = [64, 128, 256, 512]; // the tile images' sizes (tiles/<inst>/<size>/: export_tiles.py; 512 at the top)
let tiles = new Map(), // world key -> { inst, src, sea }
  have = new Set(), // world keys with an image of this build
  version = "legacy";
const images = new Map(); // url -> Image (loaded or loading)
const views = []; // { canvas, box, run, a, b }

// A tile's image at the size this view wants, drawn on whatever asks once it's in.
function tileImage(t, size) {
  const url = (size === 512 ? `tiles/${t.inst}/${t.src}.webp` : `tiles/${t.inst}/${size}/${t.src}.webp`) + `?v=${encodeURIComponent(version)}`;
  let img = images.get(url);
  if (!img) {
    img = new Image();
    img.onload = redrawSoon;
    img.src = url;
    images.set(url, img);
  }
  return img.complete && img.naturalWidth ? img : null;
}
let redrawTimer = 0;
function redrawSoon() {
  clearTimeout(redrawTimer);
  redrawTimer = setTimeout(() => views.forEach(drawView), 40);
}

// The box a case's views show: its ends and every side's line, padded, at the canvas's 4:3.
function boxOf(points) {
  let [x0, y0, x1, y1] = [Infinity, Infinity, -Infinity, -Infinity];
  for (const [x, y] of points) {
    x0 = Math.min(x0, x);
    y0 = Math.min(y0, y);
    x1 = Math.max(x1, x);
    y1 = Math.max(y1, y);
  }
  let w = Math.max(x1 - x0, 0.12), hh = Math.max(y1 - y0, 0.09);
  w *= 1.2;
  hh *= 1.2;
  if (w / hh > 4 / 3) hh = (w * 3) / 4;
  else w = (hh * 4) / 3;
  const cx = (x0 + x1) / 2, cy = (y0 + y1) / 2;
  return [cx - w / 2, cy - hh / 2, cx + w / 2, cy + hh / 2];
}

function drawView(v) {
  const c = v.canvas, r = c.getBoundingClientRect(), dpr = window.devicePixelRatio || 1;
  if (!r.width) return;
  const W = Math.round(r.width * dpr), H = Math.round(r.height * dpr);
  if (c.width !== W || c.height !== H) Object.assign(c, { width: W, height: H });
  const g = c.getContext("2d"),
    [x0, y0, x1, y1] = v.box,
    k = W / (x1 - x0),
    P = (x, y) => [(x - x0) * k, (y - y0) * k];
  g.fillStyle = "#1d3340";
  g.fillRect(0, 0, W, H);
  const size = SIZES.find((s) => s >= k) || 512;
  for (let col = Math.floor(x0); col < Math.ceil(x1); col++)
    for (let row = Math.floor(y0); row < Math.ceil(y1); row++) {
      const key = col * 64 + row, t = tiles.get(key);
      if (!t || t.sea || !have.has(key)) continue;
      const img = tileImage(t, size);
      if (!img) continue;
      const [px, py] = P(col, row);
      g.drawImage(img, px, py, k + 0.5, k + 0.5);
    }
  const run = v.run, s = dpr;
  const line = (pts) => {
    g.beginPath();
    pts.forEach((p, i) => (i ? g.lineTo(...P(...p)) : g.moveTo(...P(...p))));
  };
  if (run.way && run.way.length > 1) {
    line(run.way);
    g.strokeStyle = "rgba(10,8,4,.85)";
    g.lineWidth = 6 * s;
    g.lineJoin = g.lineCap = "round";
    g.stroke();
    line(run.way);
    g.strokeStyle = run.partial ? "#ff9a3c" : "#ffd24c";
    g.lineWidth = 3 * s;
    g.stroke();
  } else {
    line([v.a, v.b]); // no way: the straight line the addon would draw, faint
    g.strokeStyle = "rgba(255,255,255,.55)";
    g.lineWidth = 2 * s;
    g.setLineDash([6 * s, 6 * s]);
    g.stroke();
    g.setLineDash([]);
  }
  for (const [p, colour, label] of [[v.a, "#4fe08a", "A"], [v.b, "#ff5a5a", "B"]]) {
    const [x, y] = P(...p);
    g.beginPath();
    g.arc(x, y, 7 * s, 0, 2 * Math.PI);
    g.fillStyle = colour;
    g.fill();
    g.lineWidth = 2 * s;
    g.strokeStyle = "#000";
    g.stroke();
    g.fillStyle = "#000";
    g.font = `bold ${10 * s}px system-ui`;
    g.textAlign = "center";
    g.textBaseline = "middle";
    g.fillText(label, x, y + 0.5 * s);
  }
  // A scale bar: a round number of yards, about a fifth of the width.
  const yd = ((x1 - x0) * TILE_YD) / 5, step = [10, 20, 25, 50, 100, 200, 250, 500, 1000, 2000, 2500, 5000].find((n) => n >= yd) || 5000,
    len = (step / TILE_YD) * k, bx = 10 * s, by = H - 12 * s;
  g.fillStyle = "rgba(0,0,0,.6)";
  g.fillRect(bx - 4 * s, by - 14 * s, len + 8 * s, 20 * s);
  g.fillStyle = "#fff";
  g.fillRect(bx, by, len, 2 * s);
  g.font = `${10 * s}px system-ui`;
  g.textAlign = "left";
  g.textBaseline = "alphabetic";
  g.fillText(`${step} yd`, bx, by - 3 * s);
}

// The full demo there, Pathing Debug on this walk, both ends set (view-state.mjs reads pv, pa, pb).
function demoLink(box, run, a, b) {
  const [x0, y0, x1, y1] = box,
    zoom = Math.min(6144, Math.max(32, Math.min(innerWidth / (x1 - x0), innerHeight / (y1 - y0)) * 0.8)),
    p = new URLSearchParams({ map: 1, view: "2d", x: ((x0 + x1) / 2).toFixed(5), y: ((y0 + y1) / 2).toFixed(5), z: zoom.toFixed(1),
      tools: "path", pv: run.v, pa: a.map((n) => n.toFixed(4)).join(","), pb: b.map((n) => n.toFixed(4)).join(",") });
  return `./#${p}`;
}

function caption(run, sideName, role) {
  const yd = (n) => `${Math.round(n).toLocaleString()} yd`;
  let result;
  if (run.error) result = h("span", { className: "error" }, run.error);
  else if (!run.found) result = h("span", { className: "none" }, "No way" + (run.regions ? ` (regions r${run.regions[0]} / r${run.regions[1]})` : ""));
  else if (run.partial) result = h("span", { className: "partial" }, "Partial: as near as it gets, then straight");
  else result = h("span", { className: "found" }, "Found");
  return h("figcaption", {},
    h("div", { className: "side" }, `${role} `, h("small", {}, sideName)),
    h("div", {}, result, run.capped ? h("span", { className: "none" }, " · gave up at the node cap") : null),
    run.error ? null : h("div", {}, run.found ? `${yd(run.yards)} along · ${yd(run.straight)} straight · ×${run.ratio.toFixed(2)}` : `${yd(run.straight)} straight`),
    run.error ? null : h("div", { className: "dim" }, `${run.nodes.toLocaleString()} nodes${run.nodes2 ? ` (${run.nodes2.toLocaleString()} on the tile graph)` : ""} · ${run.ms} ms`));
}

function render(data) {
  const main = $("cases"), [prev, next] = data.sides;
  main.replaceChildren();
  views.length = 0;
  for (const c of data.cases) {
    const card = h("article", { className: "case" },
      h("h2", {}, c.name),
      c.zone ? h("p", { className: "zone" }, c.zone) : null,
      c.should ? h("p", { className: "should" }, h("b", {}, "Should: "), c.should) : null,
      c.note ? h("p", { className: "note" }, c.note) : null);
    for (const dir of c.back ? ["ab", "ba"] : ["ab"]) {
      const runs = c.runs.filter((r) => r.dir === dir),
        [a, b] = dir === "ab" ? [c.a, c.b] : [c.b, c.a],
        box = boxOf([a, b, ...runs.flatMap((r) => r.way || [])]);
      if (c.back) card.append(h("h3", {}, dir === "ab" ? "A → B" : "Back: B → A"));
      const pair = h("div", { className: "pair" });
      for (const [side, role] of [[prev, "Previous"], [next, "New"]]) {
        const run = runs.find((r) => r.v === side.v) || { v: side.v, error: "not run" },
          canvas = h("canvas", { ariaLabel: `${c.name}: ${role} (${side.label})`, role: "img" });
        views.push({ canvas, box, run, a, b });
        pair.append(h("figure", {}, h("a", { href: demoLink(box, run, a, b), title: `Open in the map: Pathing Debug on ${side.label}` }, canvas), caption(run, side.label, role)));
      }
      card.append(pair);
    }
    main.append(card);
  }
  views.forEach(drawView);
}

(async () => {
  const json = (p) => fetch(p).then((r) => (r.ok ? r.json() : Promise.reject(Error(`${p.split("?")[0]}: ${r.status}`))));
  const sides = new URLSearchParams(location.search).get("sides");
  try {
    const [tl, assets, data] = await Promise.all([json("/api/tiles"), json("/api/assets"), json(`/api/cases${sides ? `?sides=${encodeURIComponent(sides)}` : ""}`)]);
    tiles = new Map(tl.tiles.map((t) => [t.key, t]));
    have = new Set(assets.tiles);
    version = assets.version || "legacy";
    $("status").textContent = `Previous: ${data.sides[0].label}. New: ${data.sides[1].label}. ${data.cases.length} cases, run just now.`;
    render(data);
  } catch (e) {
    $("status").textContent = `Couldn't run the routes: ${e.message}`;
  }
  let resizeTimer = 0;
  addEventListener("resize", () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => views.forEach(drawView), 100);
  });
})();
