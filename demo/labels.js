// Map names. Shares the page's globals (cam, ctx, toScreen, ...): classic scripts, one scope.

let labels = [];

async function loadLabels() {
  labels = (await get(`/api/labels?inst=${INST}`)).labels;
}

// Labels: zones always, subzones zoomed in; heaviest first, and none over another.
const SUBZONE_ZOOM = 80;
function drawLabels() {
  ctx.textAlign = "center"; ctx.textBaseline = "alphabetic"; ctx.lineJoin = "round";
  const boxes = [];
  for (const l of labels) {
    if (l.kind === 2 && cam.zoom < SUBZONE_ZOOM) continue;
    const [x, y] = toScreen(l.col, l.row);
    if (x < -100 || x > W + 100 || y < -20 || y > H + 20) continue;
    ctx.font = l.kind === 1 ? "600 13px system-ui, -apple-system, sans-serif" : "500 11px system-ui, -apple-system, sans-serif";
    const w = (l.w ??= {})[ctx.font] ??= ctx.measureText(l.name).width;
    const b = [x - w / 2 - 3, y - 13, x + w / 2 + 3, y + 4];
    if (boxes.some((o) => b[0] < o[2] && b[2] > o[0] && b[1] < o[3] && b[3] > o[1])) continue;
    boxes.push(b);
    ctx.lineWidth = 3; ctx.strokeStyle = "#000"; ctx.strokeText(l.name, x, y);
    ctx.fillStyle = l.kind === 1 ? "#ffe9a0" : "rgba(255,255,255,.9)"; ctx.fillText(l.name, x, y);
  }
}
