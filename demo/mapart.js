// The map's art layers in the hosted demo's 2D view, under the borders' overlay: the sea tiles' water, the ocean, the flat ground's
// texture, the rebuilt ground, the softened seams, the veil. Baked by tools/gen_*.py --bake and demo/export_patches.py; Blizzard's
// art, so gitignored like demo/tiles. core.js calls MapArt.draw right after drawBorders (demo/hosted/mapart.patch).
const MapArt = (() => {
  let patches = null, again = null;
  const pics = {}; // the sea tiles' water (Data/Patches.lua) and the rebuilt ground (tools/gen_fill.py --bake) by file
  const pic = (url) => {
    if (!pics[url]) { pics[url] = new Image(); pics[url].onload = () => again && again(); pics[url].src = url; }
    return pics[url].complete && pics[url].naturalWidth ? pics[url] : null;
  };
  let fill = null, seams = null, sea = null;
  const under = { ground: null, relief: null, quilt: null }, over = { bounds: null, ai: null }; // the flat ground's texture and shading (tools/gen_ground.py, gen_relief.py), under the rebuilt ground
  fetch("sea/sea.json").then((r) => (r.ok ? r.json() : null)).then((d) => { sea = d; if (again) again(); }).catch(() => {});
  for (const k of Object.keys(under)) fetch(`${k}/${k}.json`, { cache: "no-cache" }).then((r) => (r.ok ? r.json() : null)).then((d) => { under[k] = d; if (d) buttons(); if (again) again(); }).catch(() => {});
  fetch("bounds/bounds.json", { cache: "no-cache" }).then((r) => (r.ok ? r.json() : null)).then((d) => { over.bounds = d; if (d) buttons(); if (again) again(); }).catch(() => {});
  fetch("ai/ai.json", { cache: "no-cache" }).then((r) => (r.ok ? r.json() : null)).then((d) => { over.ai = d; if (d) buttons(); if (again) again(); }).catch(() => {});
  fetch("seams/seams.json").then((r) => (r.ok ? r.json() : null)).then((d) => { seams = d; if (again) again(); }).catch(() => {});
  fetch("fill/fill.json").then((r) => (r.ok ? r.json() : null)).then((d) => { fill = d; if (again) again(); }).catch(() => {});

  // The switches, as the addon's Feel "sea.on", "fill.on", "seams.on": in the Map sheet, kept for this viewer.
  const read = (k, dflt) => { try { const v = localStorage.getItem(`mm2.${k}`); return v ? v === "on" : dflt; } catch { return dflt; } };
  const on = { sea: read("sea", true), fill: read("fill", false), ai: read("ai", true), ground: read("ground", false), relief: read("relief", false), quilt: read("quilt", false), bounds: read("bounds", false), seams: read("seams", false) };
  const panel = document.createElement("div");
  panel.id = "mapArt";
  panel.style.cssText = "margin-top:10px;padding-top:6px;border-top:1px solid #fff2";
  const heading = document.createElement("div");
  heading.textContent = "Map art";
  heading.style.cssText = "padding:4px 7px;font-size:12px;opacity:.7";
  panel.append(heading);
  const button = (key, label) => {
    const b = document.createElement("button");
    b.className = "row";
    const show = () => { b.textContent = `${label}: ${on[key] ? "on" : "off"}`; b.setAttribute("aria-pressed", on[key]); };
    b.onclick = () => {
      on[key] = !on[key];
      try { localStorage.setItem(`mm2.${key}`, on[key] ? "on" : "off"); } catch {}
      show();
      if (again) again();
    };
    show();
    panel.append(b);
    return b;
  };
  const buttons = () => { // (a layer's switch once it's there)
    if (over.ai && !shown.ai) { shown.ai = true; slot.before(button("ai", "AI repaint")); }
    if (under.quilt && !shown.quilt) { shown.quilt = true; slot.before(button("quilt", "Tile texture")); }
    if (under.ground && !shown.ground) { shown.ground = true; slot.before(button("ground", "Game textures")); }
    if (under.relief && !shown.relief) { shown.relief = true; slot.before(button("relief", "Relief")); }
    if (over.bounds && !shown.bounds) { shown.bounds = true; slot.before(button("bounds", "Mute unreachable land")); }
  };
  const shown = {};
  button("sea", "Ocean");
  const slot = document.createElement("span");
  panel.append(slot);
  button("fill", "Rebuilt ground");
  button("seams", "Soften seams");
  const place = () => { const sheet = document.getElementById("mapSheet"); if (sheet) sheet.append(panel); };
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", place); else place();

  fetch("patches/patches.json").then((r) => (r.ok ? r.json() : null)).then((d) => { patches = d; if (again) again(); }).catch(() => {});

  function draw(g, toScreen, zoom, inst, redraw) {
    again = redraw;
    for (const [col, row, png] of (patches && patches[inst]) || []) {
      const p = pic(`patches/${png}`), [x, y] = toScreen(col, row);
      if (p) g.drawImage(p, x, y, zoom, zoom);
    }
    const ocean = on.sea && sea && sea.maps[inst];
    if (ocean) {
      const p = pic(`sea/${ocean.file}`), [x0, y0] = toScreen(ocean.col, ocean.row), W = g.canvas.clientWidth || g.canvas.width, H = g.canvas.clientHeight || g.canvas.height;
      const x1 = x0 + ocean.w * zoom, y1 = y0 + ocean.h * zoom;
      g.fillStyle = `rgb(${sea.deep.join(",")})`; // past the picture
      g.fillRect(0, 0, W, Math.max(0, y0)); g.fillRect(0, y1, W, Math.max(0, H - y1)); g.fillRect(0, y0, Math.max(0, x0), y1 - y0); g.fillRect(x1, y0, Math.max(0, W - x1), y1 - y0);
      if (p) g.drawImage(p, x0, y0, x1 - x0, y1 - y0);
    }
    for (const k of Object.keys(under)) if (on[k]) for (const f of (under[k] && under[k][inst]) || []) {
      const p = pic(`${k}/${f.file}`), [x, y] = toScreen(f.col, f.row);
      if (p) g.drawImage(p, x, y, f.w * zoom, f.h * zoom);
    }
    if (on.fill) for (const f of (fill && fill[inst]) || []) {
      const p = pic(`fill/${f.file}`), [x, y] = toScreen(f.col, f.row);
      if (p) g.drawImage(p, x, y, f.w * zoom, f.h * zoom);
    }
    if (on.seams) for (const f of (seams && seams[inst]) || []) {
      const p = pic(`seams/${f.file}`), [x, y] = toScreen(f.col, f.row);
      if (p) g.drawImage(p, x, y, f.w * zoom, f.h * zoom);
    }
    if (on.ai) for (const f of (over.ai && over.ai[inst]) || []) {
      const p = pic(`ai/${f.file}`), [x, y] = toScreen(f.col, f.row);
      if (p) g.drawImage(p, x, y, f.w * zoom, f.h * zoom);
    }
    if (on.bounds) for (const f of (over.bounds && over.bounds[inst]) || []) {
      const p = pic(`bounds/${f.file}`), [x, y] = toScreen(f.col, f.row);
      if (p) g.drawImage(p, x, y, f.w * zoom, f.h * zoom);
    }
  }
  return { draw };
})();
