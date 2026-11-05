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
  fetch("ai/ai.json", { cache: "no-cache" }).then((r) => (r.ok ? r.json() : null)).then((d) => {
    over.ai = d;
    if (d) { buttons(); for (const fs of Object.values(d)) for (const f of fs) pic(`ai/${f.file}`); } // (all of them now: a few)
    if (again) again();
  }).catch(() => {});

  // The switches, as the addon's Feel "sea.on": in the menu's Show on Map page, kept for this viewer.
  const read = (k, dflt) => { try { const v = localStorage.getItem(`mm2.${k}`); return v ? v === "on" : dflt; } catch { return dflt; } };
  const on = { sea: read("sea", true), ai: read("ai", true) };
  const section = document.createElement("div"), head = document.createElement("label"), all = document.createElement("input"),
    title = document.createElement("span"), panel = document.createElement("div");
  section.className = "group";
  head.className = "row head";
  all.type = "checkbox";
  all.dataset.all = "mapArt"; // the section's header: all of it off or on (menu.js)
  title.textContent = "Map Art";
  head.append(all, title);
  panel.id = "mapArt";
  section.append(head, panel);
  bindHead(all);
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
    row.append(box, text);
    return row;
  };
  const buttons = () => { // (a layer's switch once it's there)
    if (over.ai && !shown.ai) { shown.ai = true; panel.append(toggle("ai", "Repaired Map Art")); }
  };
  const shown = {};
  panel.append(toggle("sea", "Ocean"));
  const place = () => { const sheet = document.getElementById("layerSheet"); if (sheet) sheet.append(section); };
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", place); else place();

  fetch("patches/patches.json").then((r) => (r.ok ? r.json() : null)).then((d) => { patches = d; if (again) again(); }).catch(() => {});

  // Each layer's pieces at their map's place on the world (parts: /api/maps). The ocean: one picture over the whole world
  // (sea/world-sea.webp, in world tiles), and past it the far water's swell (sea/swell.webp, seamless, laid on the world from
  // tile 0, 0 as gen_sea.py made the picture's far water, so they meet pixel for pixel at any size).
  // (a pattern a frame: its transform follows the camera)
  const pattern = (g, tex, tiles, zoom, toScreen) => {
    const fill = g.createPattern(tex, "repeat"), [ox, oy] = toScreen(0, 0), k = (tiles * zoom) / tex.width;
    fill.setTransform(new DOMMatrix([k, 0, 0, k, ox, oy]));
    return fill;
  };
  function draw(g, toScreen, zoom, parts, redraw) {
    again = redraw;
    const OFFSET = Object.fromEntries(parts.map((p) => [p.inst, p.offset]));
    for (const [i, [dx, dy]] of Object.entries(OFFSET)) for (const [col, row, png] of (patches && patches[i]) || []) {
      const p = pic(`patches/${png}`), [x, y] = toScreen(col + dx, row + dy);
      if (p) g.drawImage(p, x, y, zoom, zoom);
    }
    if (on.sea && sea) {
      const W = g.canvas.clientWidth || g.canvas.width, H = g.canvas.clientHeight || g.canvas.height;
      const ocean = pic(`sea/${sea.file}`), [x0, y0] = toScreen(sea.col, sea.row), w = sea.w * zoom, h = sea.h * zoom;
      // The fine swell, then the broad one over it at its alpha (the blend gen_sea.py baked into the picture's far water).
      const tex = sea.swell && pic(`sea/${sea.swell.file}`), tex2 = sea.over && pic(`sea/${sea.over.file}`);
      g.beginPath(); g.rect(0, 0, W, H); g.rect(x0, y0, w, h);
      g.fillStyle = tex ? pattern(g, tex, sea.swell.tiles, zoom, toScreen) : `rgb(${sea.deep.join(",")})`; g.fill("evenodd");
      if (tex && tex2) {
        g.save(); g.globalAlpha = sea.over.alpha;
        g.fillStyle = pattern(g, tex2, sea.over.tiles, zoom, toScreen); g.fill("evenodd");
        g.restore();
      }
      if (ocean) g.drawImage(ocean, x0, y0, w, h);
    }
    // A repaint shows as much as the tiles under it are sharp (tiles.js sharpShare): over the stand-in (which has it baked
    // in) it waits, and it sharpens with its neighbours, not on its own.
    if (on.ai) for (const [i, [dx, dy]] of Object.entries(OFFSET)) for (const f of (over.ai && over.ai[i]) || []) {
      const c = f.col + dx, r = f.row + dy, p = pic(`ai/${f.file}`), [x, y] = toScreen(c, r);
      if (!p || x > g.canvas.width || y > g.canvas.height || x + f.w * zoom < 0 || y + f.h * zoom < 0) continue;
      const a = typeof sharpShare === "function" ? sharpShare(c, r, c + f.w, r + f.h) : 1;
      if (a <= 0) continue;
      g.globalAlpha = a;
      g.drawImage(p, x, y, f.w * zoom, f.h * zoom);
      g.globalAlpha = 1;
    }
  }
  return { draw };
})();
