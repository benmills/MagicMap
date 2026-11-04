// Tile space is Atlas col/east, row/south; vertical units are game yards.
export const TILE_YARDS = 1600 / 3;
// A perspective camera, as a maps app's: it looks at (cx, cy, focus) from FOCAL screen heights away, so
// near ground is bigger than far ground and pans faster under the finger (parallax). zoom is px a tile
// at the focus. Points are rotated by yaw into (a: right, b: down the screen on the ground, z: up), the
// view tilted about the focus; d is depth toward the eye and w (1 at the focus) the perspective divide.
export const FOCAL = 1.8; // eye distance in screen heights: about a 31° vertical field of view
export const NEAR = 0.02; // nothing nearer the eye than this share of its distance is drawn
export const eyeDistance = (camera, heightPx) => (FOCAL * heightPx) / camera.zoom; // in tiles
export function project(
  c,
  r,
  height,
  camera,
  width,
  heightPx,
  yaw = 0,
  tilt = 0,
  focus = 0,
) {
  const co = Math.cos(yaw),
    si = Math.sin(yaw),
    t = (tilt * Math.PI) / 180;
  const dx = c - camera.cx,
    dy = r - camera.cy,
    z = (height - focus) / TILE_YARDS;
  const a = co * dx - si * dy,
    b = si * dx + co * dy,
    d = b * Math.sin(t) + z * Math.cos(t),
    w = Math.max(NEAR, 1 - d / eyeDistance(camera, heightPx));
  return [
    width / 2 + (a * camera.zoom) / w,
    heightPx / 2 + ((b * Math.cos(t) - z * Math.sin(t)) * camera.zoom) / w,
    d,
    1 / w, // how much bigger than at the focus things are drawn here
  ];
}
// The ground point at height under screen (x, y): the eye's ray through it met at that height; a ray
// above the horizon (or very far) is held FAR eye distances out.
const FAR = 4;
export function unproject(
  x,
  y,
  height,
  camera,
  width,
  heightPx,
  yaw = 0,
  tilt = 0,
  focus = 0,
) {
  const t = (tilt * Math.PI) / 180,
    co = Math.cos(yaw),
    si = Math.sin(yaw),
    st = Math.sin(t),
    ct = Math.cos(t);
  const e = eyeDistance(camera, heightPx),
    X = (x - width / 2) / camera.zoom,
    Y = (y - heightPx / 2) / camera.zoom,
    z = (height - focus) / TILE_YARDS;
  const den = e * ct + Y * st;
  let b = den > 1e-9 ? (Y * e - Y * z * ct + z * e * st) / den : -Infinity;
  b = Math.max(b, -FAR * e);
  const w = Math.max(NEAR, 1 - (b * st + z * ct) / e),
    a = X * w;
  return [camera.cx + co * a + si * b, camera.cy - si * a + co * b];
}
export function visibleBounds(
  camera,
  w,
  h,
  yaw,
  tilt,
  focus,
  min = -2000,
  max = 6000,
) {
  const points = [min, max].flatMap((z) =>
    [
      [0, 0],
      [w, 0],
      [0, h],
      [w, h],
    ].map((p) => unproject(...p, z, camera, w, h, yaw, tilt, focus)),
  );
  return [
    Math.min(...points.map((p) => p[0])),
    Math.min(...points.map((p) => p[1])),
    Math.max(...points.map((p) => p[0])),
    Math.max(...points.map((p) => p[1])),
  ];
}
export function barycentric(x, y, a, b, c) {
  const d = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1]);
  if (Math.abs(d) < 1e-12) return null;
  const u = ((b[1] - c[1]) * (x - c[0]) + (c[0] - b[0]) * (y - c[1])) / d;
  const v = ((c[1] - a[1]) * (x - c[0]) + (a[0] - c[0]) * (y - c[1])) / d;
  return u >= -1e-6 && v >= -1e-6 && u + v <= 1 + 1e-6
    ? [u, v, 1 - u - v]
    : null;
}
// MMT1: 12-byte header, float32 xyz vertices, uint32 triangle indices, little endian.
// offset: the map's place on the world, in tiles (a mesh is in its own map's).
export function parseMesh(buffer, { spatialIndex = true, offset = [0, 0] } = {}) {
  if (!(buffer instanceof ArrayBuffer) || buffer.byteLength < 12)
    throw Error("Truncated terrain mesh");
  const d = new DataView(buffer),
    magic = String.fromCharCode(...new Uint8Array(buffer, 0, 4));
  const nv = d.getUint32(4, true),
    ni = d.getUint32(8, true);
  if (
    magic !== "MMT1" ||
    nv > 1000000 ||
    ni > 6000000 ||
    ni % 3 ||
    buffer.byteLength !== 12 + nv * 12 + ni * 4
  )
    throw Error("Invalid MMT1 mesh");
  const positions = new Float32Array(nv * 3),
    indices = new Uint32Array(ni);
  for (let i = 0; i < positions.length; i++) {
    positions[i] = d.getFloat32(12 + i * 4, true) + (i % 3 < 2 ? offset[i % 3] : 0);
    if (!Number.isFinite(positions[i])) throw Error("Non-finite vertex");
  }
  for (let i = 0; i < ni; i++) {
    indices[i] = d.getUint32(12 + nv * 12 + i * 4, true);
    if (indices[i] >= nv) throw Error("Invalid triangle index");
  }
  const bins = new Map(),
    vertex = (i) => positions.subarray(i * 3, i * 3 + 3);
  // Spatial bins serve native triangle inspection and screen picking, including terrain holes.
  for (let i = 0; spatialIndex && i < ni; i += 3) {
    const vs = [
      vertex(indices[i]),
      vertex(indices[i + 1]),
      vertex(indices[i + 2]),
    ];
    const xs = vs.map((p) => p[0] * 16),
      ys = vs.map((p) => p[1] * 16);
    const x0 = Math.floor(Math.min(...xs)),
      x1 = Math.floor(Math.max(...xs)),
      y0 = Math.floor(Math.min(...ys)),
      y1 = Math.floor(Math.max(...ys));
    if ((x1 - x0 + 1) * (y1 - y0 + 1) > 4096)
      throw Error("Triangle exceeds terrain bin limit");
    for (let x = x0; x <= x1; x++)
      for (let y = y0; y <= y1; y++) {
        const k = `${x},${y}`;
        if (!bins.has(k)) bins.set(k, []);
        bins.get(k).push(i);
      }
  }
  return { positions, indices, bins, vertex, bytes: buffer.byteLength };
}
export function sample(mesh, c, r) {
  for (const i of mesh.bins.get(
    `${Math.floor(c * 16)},${Math.floor(r * 16)}`,
  ) || []) {
    const a = mesh.vertex(mesh.indices[i]),
      b = mesh.vertex(mesh.indices[i + 1]),
      d = mesh.vertex(mesh.indices[i + 2]);
    const weights = barycentric(c, r, a, b, d);
    if (!weights) continue;
    const ux = (b[0] - a[0]) * TILE_YARDS,
      uy = (b[1] - a[1]) * TILE_YARDS,
      uz = b[2] - a[2];
    const vx = (d[0] - a[0]) * TILE_YARDS,
      vy = (d[1] - a[1]) * TILE_YARDS,
      vz = d[2] - a[2];
    const nx = uy * vz - uz * vy,
      ny = uz * vx - ux * vz,
      nz = ux * vy - uy * vx;
    return {
      height: weights[0] * a[2] + weights[1] * b[2] + weights[2] * d[2],
      slope: (Math.atan2(Math.hypot(nx, ny), Math.abs(nz)) * 180) / Math.PI,
    };
  }
  return null;
}
export function pickMesh(mesh, x, y, projectPoint, unprojectPoint, min, max) {
  const a = unprojectPoint(x, y, min),
    b = unprojectPoint(x, y, max),
    candidates = new Set();
  const n = Math.max(
    1,
    Math.ceil(Math.max(Math.abs(a[0] - b[0]), Math.abs(a[1] - b[1])) * 32),
  );
  for (let j = 0; j <= n; j++) {
    const k = `${Math.floor((a[0] + ((b[0] - a[0]) * j) / n) * 16)},${Math.floor((a[1] + ((b[1] - a[1]) * j) / n) * 16)}`;
    for (const i of mesh.bins.get(k) || []) candidates.add(i);
  }
  let best = null;
  for (const i of candidates) {
    const v = [0, 1, 2].map((j) => mesh.vertex(mesh.indices[i + j])),
      p = v.map((a) => projectPoint(...a));
    const weights = barycentric(x, y, ...p);
    if (!weights) continue;
    const depth = weights.reduce((s, w, j) => s + w * p[j][2], 0);
    if (!best || depth > best.depth)
      best = {
        col: weights.reduce((s, w, j) => s + w * v[j][0], 0),
        row: weights.reduce((s, w, j) => s + w * v[j][1], 0),
        height: weights.reduce((s, w, j) => s + w * v[j][2], 0),
        depth,
      };
  }
  return best;
}

export function meshNormals(mesh, local = false) {
  const normals = new Float32Array(mesh.positions.length),
    p = mesh.positions,
    indices = mesh.indices;
  for (let i = 0; i < indices.length; i += 3) {
    const a = indices[i] * 3,
      b = indices[i + 1] * 3,
      c = indices[i + 2] * 3,
      s = local ? 1 : 533.333333;
    const ux = (p[b] - p[a]) * s,
      uy = (p[b + 1] - p[a + 1]) * s,
      uz = p[b + 2] - p[a + 2];
    const vx = (p[c] - p[a]) * s,
      vy = (p[c + 1] - p[a + 1]) * s,
      vz = p[c + 2] - p[a + 2];
    const n = [uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx];
    for (const j of [a, b, c])
      for (let k = 0; k < 3; k++) normals[j + k] += n[k];
  }
  for (let i = 0; i < normals.length; i += 3) {
    const len = Math.hypot(...normals.subarray(i, i + 3)) || 1;
    for (let j = 0; j < 3; j++) normals[i + j] /= len;
  }
  return normals;
}
