// Zone borders. Shares the page's globals (cam, ctx, toScreen, ...): classic scripts, one scope.

let lines = [];

async function loadBorders() {
  const b = await get(`/api/borders?inst=${INST}`);
  lines = b.lines.map(([kind, ...pts]) => {
    const cs = pts.filter((_, i) => i % 2 === 0), rs = pts.filter((_, i) => i % 2 === 1);
    return { kind, pts, c0: Math.min(...cs), c1: Math.max(...cs), r0: Math.min(...rs), r1: Math.max(...rs) };
  });
}

function drawBorders() {
  const [c0, r0] = toTile(0, 0), [c1, r1] = toTile(W, H);
  for (const l of lines) {
    if (l.c1 < c0 || l.c0 > c1 || l.r1 < r0 || l.r0 > r1) continue;
    ctx.strokeStyle = l.kind === 1 ? "rgba(255,230,150,.8)" : "rgba(255,255,255,.25)";
    ctx.lineWidth = l.kind === 1 ? 1.5 : 1;
    ctx.beginPath();
    for (let i = 0; i < l.pts.length; i += 2) {
      const [x, y] = toScreen(l.pts[i], l.pts[i + 1]);
      i ? ctx.lineTo(x, y) : ctx.moveTo(x, y);
    }
    ctx.stroke();
  }
}
