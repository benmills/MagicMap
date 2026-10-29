// Clouds over the map's broken art in the hosted demo's 2D view, as the addon draws them (ui/Clouds.lua):
// clouds/clouds.json (demo/export_clouds.py, from Data/Clouds.lua) and the game's puff (clouds/puff.png, from
// the install: Blizzard's art, so gitignored like demo/tiles). Over the borders, under the pins and names:
// core.js calls Clouds.draw right after drawBorders (demo/hosted/clouds.patch).
const Clouds = (() => {
  const TINT = [0.78, 0.75, 0.68]; // ui/Clouds.lua's
  let data = null, puff = null, again = null;

  const ready = () => { if (data && puff && again) again(); };
  fetch("clouds/clouds.json").then((r) => (r.ok ? r.json() : null)).then((d) => { data = d; ready(); }).catch(() => {});
  const img = new Image();
  img.onload = () => { // tinted once, as the addon's SetVertexColor
    const c = document.createElement("canvas");
    c.width = img.width; c.height = img.height;
    const g = c.getContext("2d");
    g.drawImage(img, 0, 0);
    const px = g.getImageData(0, 0, c.width, c.height);
    for (let i = 0; i < px.data.length; i += 4) for (let k = 0; k < 3; k++) px.data[i + k] *= TINT[k];
    g.putImageData(px, 0, 0);
    puff = c;
    ready();
  };
  img.src = "clouds/puff.png";

  // Each cloud: centre (x, y) and width w in tiles, turn 0-3 quarter turns clockwise, +4 mirrored first.
  function draw(g, toScreen, zoom, inst, redraw) {
    again = redraw;
    const list = data && puff && data[inst];
    if (!list) return;
    const aspect = puff.height / puff.width, W = g.canvas.clientWidth || g.canvas.width, H = g.canvas.clientHeight || g.canvas.height;
    for (let i = 0; i < list.length; i += 4) {
      const w = list[i + 2] * zoom, turn = list[i + 3], odd = turn % 2 === 1;
      const [x, y] = toScreen(list[i], list[i + 1]), h = odd ? w / aspect : w * aspect;
      if (x + w / 2 < 0 || y + h / 2 < 0 || x - w / 2 > W || y - h / 2 > H) continue;
      const pw = odd ? h : w, ph = odd ? w : h; // the puff's own width and height, before it's turned
      g.save();
      g.translate(x, y);
      g.rotate((turn % 4) * Math.PI / 2);
      if (turn >= 4) g.scale(-1, 1);
      g.drawImage(puff, -pw / 2, -ph / 2, pw, ph);
      g.restore();
    }
  }
  return { draw };
})();
