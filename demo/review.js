// The map review (docs/hardening-plan.md M6): tools/maplint.py's issues on the map and in a list, each marked
// accepted / rejected / later with a note, saved on the server (demo/review_api.py) for everyone reviewing;
// tools/review.py reads the marks back.
// Its own scope: the page mounts it with a host (the camera and the drawing it doesn't own):
//   Review.mount({ ctx, toScreen, zoom, offset, draw, fly(issue), sheet, button, onOpen? })
//     ctx() the 2D context (CSS px), toScreen(col, row) -> [x, y], zoom() px per tile, offset(inst) -> [dx, dy]
//     its map's place on the world (none: not on it), fly(issue) shows an issue (its bbox), sheet the panel to fill, button the toggle.
//   Review.drawOverlay()  in the frame, over the tiles;  Review.tap(col, row) -> true if it took it.
const Review = (() => {
  const CHUNKS = 16;
  const STATUS = { open: "#ff3df0", accepted: "#5ad17a", rejected: "#8a8a8a", later: "#f2b84c" };
  const KEYS = { a: "accepted", r: "rejected", l: "later", o: null };
  const KIND = { "flat-land": "Flat land", "border-wrap": "Border wrap", "border-sliver": "Border sliver", "border-fragment": "Border fragment",
    "colour-block": "Colour block", "patch-edge": "Patch edge", seam: "Seam", "skipped-tile": "Skipped tile", "sea-edge": "Sea edge", data: "Data" };
  const MAPS = { "-1": "data", 0: "Eastern Kingdoms", 1: "Kalimdor", 2991: "Zephras Isle" };
  const store = (k, v) => { try { if (v === undefined) return localStorage.getItem(k) || ""; localStorage.setItem(k, v); } catch { return ""; } };
  let host, issues = [], byId = new Map(), marks = {}, updated = null, lint = {}, on = false, sel = null;
  let filter = { status: "open", kind: "", here: false }, list = [], poll;
  // An issue on the world: its place moved by its map's offset; inst 1 (the world), map its own.
  const onWorld = (i) => {
    const o = host.offset(i.inst);
    if (!o) return i;
    return { ...i, inst: 1, map: i.inst, centroid: i.centroid && [i.centroid[0] + o[0], i.centroid[1] + o[1]],
      bbox: i.bbox && [i.bbox[0] + o[0], i.bbox[1] + o[1], i.bbox[2] + o[0], i.bbox[3] + o[1]],
      mask: i.mask && { ...i.mask, x0: i.mask.x0 + o[0] * 16, y0: i.mask.y0 + o[1] * 16 } };
  };
  const asked = new URLSearchParams(location.hash.slice(1)).get("issue"); // a link's issue, read before the page rewrites the hash

  const statusOf = (i) => marks[i.id]?.status || "open";
  function el(tag, props, ...kids) {
    const e = Object.assign(document.createElement(tag), props);
    for (const k of kids.flat(Infinity)) if (k != null && k !== false && k !== "") e.append(k);
    return e;
  }
  async function json(path, opts) {
    const r = await fetch(path, opts);
    const body = await r.json().catch(() => ({}));
    if (!r.ok) throw Object.assign(Error(body.error || `${path}: ${r.status}`), { status: r.status });
    return body;
  }

  // ---- the marks ----
  function took(doc) {
    marks = doc.decisions || {}; updated = doc.updated;
  }
  async function refresh() {
    const doc = await json("/api/review");
    if (doc.updated === updated) return;
    took(doc);
    const typing = host.sheet.contains(document.activeElement) && /INPUT|TEXTAREA|SELECT/.test(document.activeElement.tagName);
    if (!typing) render();
    host.draw();
  }
  async function save(i, status, note) {
    let by = store("mm.review.by");
    if (!by) { by = (prompt("Your name, for the review's log:") || "").trim(); if (by) store("mm.review.by", by); }
    const send = () => json("/api/review", { method: "POST", headers: { "Content-Type": "application/json", "X-Review-Token": store("mm.review.token") },
      body: JSON.stringify({ id: i.id, status, note, by }) });
    try {
      took(await send());
    } catch (e) {
      if (e.status !== 401) throw e;
      const t = prompt("This review needs its token:");
      if (!t) return;
      store("mm.review.token", t.trim());
      took(await send());
    }
  }
  async function decide(status) {
    if (!sel) return;
    const before = list, at = before.indexOf(sel), note = host.sheet.querySelector(".rv-note")?.value ?? marks[sel.id]?.note ?? "";
    await save(sel, status, note);
    relist();
    const next = before.slice(at + 1).find((i) => list.includes(i)) || (list.includes(sel) ? sel : list[0]);
    select(next || null);
  }

  // ---- the list ----
  function relist() {
    list = issues.filter((i) => (filter.status === "all" || statusOf(i) === filter.status) && (!filter.kind || i.kind === filter.kind)
      && (!filter.here || i.inst >= 0));
  }
  function select(i, fly = true) {
    sel = i;
    render();
    if (i && fly && i.inst >= 0) host.fly(i);
    host.draw();
    host.sheet.querySelector(".rv-sel")?.scrollIntoView({ block: "nearest" });
  }
  function step(d) {
    if (!list.length) return;
    const at = list.indexOf(sel);
    select(list[at < 0 ? 0 : (at + d + list.length) % list.length]);
  }
  function link(i) {
    const u = new URL(location.href);
    u.hash = `map=${i.inst}&view=2d&x=${i.centroid[0].toFixed(3)}&y=${i.centroid[1].toFixed(3)}&z=128&issue=${encodeURIComponent(i.id)}`;
    return u.href;
  }
  const when = (at) => at ? new Date(at).toLocaleString(undefined, { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" }) : "";

  function detail(i) {
    const m = marks[i.id], st = statusOf(i);
    const note = el("textarea", { className: "rv-note", rows: 3, placeholder: "Note (why, what to try)…", value: m?.note || "" });
    note.onchange = () => save(i, m?.status || null, note.value).then(() => { relist(); render(); }).catch(fail);
    const btn = (status, label, key) => el("button", { className: `rv-btn${st === (status || "open") ? " on" : ""}`, title: `${label} (${key})`,
      onclick: () => decide(status).catch(fail) }, el("i", { style: `background:${STATUS[status || "open"]}` }), label);
    const copy = el("button", { className: "rv-link", onclick: () => navigator.clipboard?.writeText(link(i)).then(() => { copy.textContent = "Copied"; }) }, "Copy link");
    return el("div", { className: "rv-detail" },
      el("div", { className: "rv-head" }, el("span", { className: "rv-kind" }, KIND[i.kind] || i.kind), el("b", {}, i.zone !== "-" ? i.zone : ""),
        el("small", {}, `${MAPS[i.map ?? i.inst] || i.inst} · severity ${i.severity}`)),
      el("p", {}, i.desc),
      el("p", { className: "rv-metrics" }, Object.entries(i.metrics || {}).map(([k, v]) => `${k} ${typeof v === "number" ? +v.toFixed(3) : JSON.stringify(v)}`).join(" · ")),
      el("div", { className: "rv-btns" }, btn("accepted", "Accept", "a"), btn("rejected", "Reject", "r"), btn("later", "Later", "l"), btn(null, "Open", "o")),
      note,
      el("div", { className: "rv-foot" }, m ? `${m.by || "someone"} · ${when(m.at)}` : "not reviewed",
        el("span", {}, el("button", { className: "rv-link", onclick: () => step(-1), title: "Previous (k)" }, "‹ Prev"),
          el("button", { className: "rv-link", onclick: () => step(1), title: "Next (j)" }, "Next ›"), copy)),
      el("code", {}, i.id));
  }
  function render() {
    if (!on) return;
    relist();
    const counts = { open: 0, accepted: 0, rejected: 0, later: 0 };
    for (const i of issues) counts[statusOf(i)]++;
    const name = el("input", { className: "rv-by", placeholder: "Your name", value: store("mm.review.by") });
    name.onchange = () => store("mm.review.by", name.value.trim());
    const chip = (status, label, n) => el("button", { className: `rv-chip${filter.status === status ? " on" : ""}`,
      onclick: () => { filter.status = status; render(); host.draw(); } }, status !== "all" && el("i", { style: `background:${STATUS[status]}` }), `${label} ${n}`);
    const kinds = el("select", { className: "rv-kinds", onchange: (e) => { filter.kind = e.target.value; render(); host.draw(); } },
      el("option", { value: "" }, "All kinds"),
      [...new Set(issues.map((i) => i.kind))].map((k) => el("option", { value: k, selected: filter.kind === k }, `${KIND[k] || k} (${issues.filter((i) => i.kind === k).length})`)));
    const here = el("label", { className: "rv-here" }, el("input", { type: "checkbox", checked: filter.here,
      onchange: (e) => { filter.here = e.target.checked; render(); host.draw(); } }), "On the map");
    const rows = list.map((i) => el("button", { className: `rv-row${i === sel ? " rv-sel" : ""}`, onclick: () => select(i) },
      el("i", { style: `background:${STATUS[statusOf(i)]}` }), el("span", { className: "rv-kind" }, KIND[i.kind] || i.kind),
      el("span", { className: "rv-zone" }, i.zone !== "-" ? i.zone : i.desc), marks[i.id]?.note && el("span", { title: marks[i.id].note }, "✎"),
      el("small", {}, `${MAPS[i.map ?? i.inst]} · ${i.severity}`)));
    host.sheet.replaceChildren(
      el("div", { className: "rv-top" }, el("b", {}, "Map review"), name, el("button", { className: "x", ariaLabel: "Close review", onclick: () => toggle(false) }, "✕")),
      el("p", { className: "rv-src" }, lint.missing ? `No issues file on the server (${lint.missing}).`
        : `${issues.length} issues · build ${lint.build || "?"} · ${lint.commit || ""} · ${when(lint.generated)}`),
      el("div", { className: "rv-chips" }, chip("open", "Open", counts.open), chip("accepted", "Accepted", counts.accepted),
        chip("rejected", "Rejected", counts.rejected), chip("later", "Later", counts.later), chip("all", "All", issues.length)),
      el("div", { className: "rv-filters" }, kinds, here),
      sel ? detail(sel) : "",
      el("div", { className: "rv-list" }, rows.length ? rows : el("p", { className: "rv-src" }, "Nothing here.")),
      el("p", { className: "rv-src" }, "Keys: j / k next, previous · a accept · r reject · l later · o reopen"));
  }
  function fail(e) {
    const p = host.sheet.querySelector(".rv-src");
    if (p) p.textContent = `Couldn't save: ${e.message}`;
  }

  // ---- on the map ----
  function cells(i) { // a mask's chunks, [col, row] in chunks, decoded once
    if (i._cells || !i.mask) return i._cells;
    const { x0, y0, w, rle } = i.mask, out = [];
    let n = 0, lit = false;
    for (const run of rle) {
      if (lit) for (let k = n; k < n + run; k++) out.push([x0 + (k % w), y0 + Math.floor(k / w)]);
      n += run; lit = !lit;
    }
    return (i._cells = out);
  }
  function drawOne(g, i, chosen) {
    const colour = STATUS[statusOf(i)], [c0, r0, c1, r1] = i.bbox, z = host.zoom();
    let [x0, y0] = host.toScreen(c0, r0), [x1, y1] = host.toScreen(c1, r1);
    const pad = Math.max(0, 8 - (x1 - x0)) / 2, padY = Math.max(0, 8 - (y1 - y0)) / 2; // a seam is a line: keep it seen
    x0 -= pad; x1 += pad; y0 -= padY; y1 += padY;
    if (cells(i) && z / CHUNKS >= 1.5) {
      g.fillStyle = colour; g.globalAlpha = chosen ? 0.45 : 0.14;
      const s = z / CHUNKS;
      for (const [c, r] of cells(i)) { const [x, y] = host.toScreen(c / CHUNKS, r / CHUNKS); g.fillRect(x, y, s + 0.5, s + 0.5); }
      g.globalAlpha = 1;
    }
    g.setLineDash(chosen ? [] : [5, 4]);
    g.lineWidth = chosen ? 4 : 2.5; g.strokeStyle = "rgba(0,0,0,.55)"; g.strokeRect(x0, y0, x1 - x0, y1 - y0);
    g.lineWidth = chosen ? 2 : 1.2; g.strokeStyle = colour; g.strokeRect(x0, y0, x1 - x0, y1 - y0);
    g.setLineDash([]);
  }
  function drawOverlay() {
    if (!on || !issues.length) return;
    const g = host.ctx();
    g.save();
    for (const i of list) if (i.inst >= 0 && i !== sel) drawOne(g, i, false);
    if (sel && sel.inst >= 0) drawOne(g, sel, true);
    g.restore();
  }
  function tap(col, row) {
    if (!on) return false;
    const reach = 6 / host.zoom();
    const hit = list.filter((i) => i.inst >= 0 && col >= i.bbox[0] - reach && col <= i.bbox[2] + reach
      && row >= i.bbox[1] - reach && row <= i.bbox[3] + reach);
    if (!hit.length) return false;
    const inMask = (i) => !i.mask || cells(i).some(([c, r]) => Math.floor(col * CHUNKS) === c && Math.floor(row * CHUNKS) === r);
    const area = (i) => (i.bbox[2] - i.bbox[0]) * (i.bbox[3] - i.bbox[1]);
    hit.sort((a, b) => inMask(b) - inMask(a) || area(a) - area(b));
    select(hit[0], false);
    return true;
  }

  function toggle(open = !on) {
    on = open;
    host.sheet.hidden = !on;
    host.button.setAttribute("aria-pressed", on);
    clearInterval(poll);
    if (on) { host.onOpen?.(); render(); poll = setInterval(() => refresh().catch(() => {}), 15000); refresh().catch(() => {}); }
    host.draw();
  }
  addEventListener("keydown", (e) => {
    if (!on || e.metaKey || e.ctrlKey || e.altKey || /INPUT|TEXTAREA|SELECT/.test(document.activeElement?.tagName)) return;
    if (e.key === "j") step(1);
    else if (e.key === "k") step(-1);
    else if (e.key in KEYS && sel) decide(KEYS[e.key]).catch(fail);
    else return;
    e.preventDefault(); e.stopPropagation();
  }, true);

  async function mount(h) {
    host = h;
    host.sheet.classList.add("rv");
    host.button.onclick = () => toggle();
    const [l, doc] = await Promise.all([json("/api/lint"), json("/api/review").catch(() => ({}))]);
    lint = l; took(doc);
    issues = (l.issues || []).map(onWorld).sort((a, b) => (a.inst < 0) - (b.inst < 0) || a.kind.localeCompare(b.kind) || b.severity - a.severity);
    byId = new Map(issues.map((i) => [i.id, i]));
    if (asked && byId.has(asked)) { filter.status = "all"; toggle(true); select(byId.get(asked), false); }
  }

  return { mount, drawOverlay, tap, isOn: () => on };
})();
