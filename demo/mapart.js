// The map's art layers in the 2D view, over the tiles, as the addon draws them: the patched sea tile's water (Data/Patches.lua),
// the ocean (ui/Sea.lua), the AI repaints (ui/Repaint.lua). Baked by demo/export_patches.py, tools/gen_sea.py --bake and
// tools/ai_map.py bake (README.md); Blizzard's art, so gitignored like demo/tiles. core.js calls MapArt.draw after the tiles.
const MapArt = (() => {
  let patches = null, again = null;
  const pics = {}; // by file
  const load = (url, tries) => { // a failed load (the host 503s in bursts) tries again: about 1, 2, 4, 8 s apart, not all at once
    const p = pics[url] = new Image();
    p.onload = () => again && again();
    p.onerror = () => { if (tries < 4) setTimeout(() => load(url, tries + 1), 2 ** tries * (1000 + Math.random() * 500)); };
    p.src = url;
  };
  const pic = (url) => {
    if (!pics[url]) load(url, 0);
    return pics[url].complete && pics[url].naturalWidth ? pics[url] : null;
  };
  let sea = null;
  const over = { ai: null };
  fetch("sea/sea.json").then((r) => (r.ok ? r.json() : null)).then((d) => { sea = d; if (again) again(); }).catch(() => {});
  fetch("ai/ai.json", { cache: "no-cache" }).then((r) => (r.ok ? r.json() : null)).then((d) => { over.ai = d; if (d) buttons(); if (again) again(); }).catch(() => {});

  // The switches, as the addon's Feel "sea.on": in the menu's Show on Map page, kept for this viewer.
  const read = (k, dflt) => { try { const v = localStorage.getItem(`mm2.${k}`); return v ? v === "on" : dflt; } catch { return dflt; } };
  const on = { sea: read("sea", true), ai: read("ai", true) };
  const heading = document.createElement("h3");
  heading.textContent = "Map art";
  const panel = document.createElement("div");
  panel.id = "mapArt";
  panel.className = "group";
  const toggle = (key, label) => {
    const row = document.createElement("label"), text = document.createElement("span"), box = document.createElement("input");
    row.className = "row";
    text.textContent = label;
    box.type = "checkbox";
    box.checked = on[key];
    box.onchange = () => {
      on[key] = box.checked;
      try { localStorage.setItem(`mm2.${key}`, on[key] ? "on" : "off"); } catch {}
      if (again) again();
    };
    row.append(text, box);
    return row;
  };
  const buttons = () => { // (a layer's switch once it's there)
    if (over.ai && !shown.ai) { shown.ai = true; panel.append(toggle("ai", "Repaired map art")); }
  };
  const shown = {};
  panel.append(toggle("sea", "Ocean"));
  const place = () => { const sheet = document.getElementById("layerSheet"); if (sheet) sheet.append(heading, panel); };
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", place); else place();

  fetch("patches/patches.json").then((r) => (r.ok ? r.json() : null)).then((d) => { patches = d; if (again) again(); }).catch(() => {});

  // Each layer's pieces at their map's place on the world (parts: /api/maps). Past the oceans' pictures: their colour; Zephras Isle,
  // which has no ocean of its own, lies over them, its near-black gone (sea/isle.webp, baked from its tiles).
  function draw(g, toScreen, zoom, parts, redraw) {
    again = redraw;
    const OFFSET = Object.fromEntries(parts.map((p) => [p.inst, p.offset])), isleBox = parts.find((p) => p.inst === 2991).bounds;
    for (const [i, [dx, dy]] of Object.entries(OFFSET)) for (const [col, row, png] of (patches && patches[i]) || []) {
      const p = pic(`patches/${png}`), [x, y] = toScreen(col + dx, row + dy);
      if (p) g.drawImage(p, x, y, zoom, zoom);
    }
    if (on.sea && sea) {
      const W = g.canvas.clientWidth || g.canvas.width, H = g.canvas.clientHeight || g.canvas.height;
      const oceans = Object.entries(sea.maps).map(([i, o]) => {
        const [dx, dy] = OFFSET[i], [x0, y0] = toScreen(o.col + dx, o.row + dy);
        return { p: pic(`sea/${o.file}`), x0, y0, w: o.w * zoom, h: o.h * zoom };
      });
      g.beginPath(); g.rect(0, 0, W, H);
      for (const o of oceans) g.rect(o.x0, o.y0, o.w, o.h);
      g.fillStyle = `rgb(${sea.deep.join(",")})`; g.fill("evenodd");
      for (const o of oceans) if (o.p) g.drawImage(o.p, o.x0, o.y0, o.w, o.h);
      const isle = pic("sea/isle.webp"), [c0, r0, c1, r1] = isleBox, [ix, iy] = toScreen(c0, r0);
      if (isle) g.drawImage(isle, ix, iy, (c1 - c0) * zoom, (r1 - r0) * zoom);
    }
    if (on.ai) for (const [i, [dx, dy]] of Object.entries(OFFSET)) for (const f of (over.ai && over.ai[i]) || []) {
      const p = pic(`ai/${f.file}`), [x, y] = toScreen(f.col + dx, f.row + dy);
      if (p) g.drawImage(p, x, y, f.w * zoom, f.h * zoom);
    }
  }
  return { draw };
})();
