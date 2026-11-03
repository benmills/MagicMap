import test from "node:test";
import assert from "node:assert/strict";
import { readView, writeView, Requests, fitBounds } from "../view-state.mjs";
import {
  renderDensity,
  textureResolution,
  flyoverPitch,
} from "../terrain-quality.mjs";
import {
  project,
  unproject,
  visibleBounds,
  parseMesh,
  sample,
  pickMesh,
  TILE_YARDS,
} from "../terrain-scene.mjs";
const near = (a, b, eps = 1e-4) =>
  assert.ok(Math.abs(a - b) < eps, `${a} != ${b}`);
function mesh(vertices, indices) {
  const buffer = new ArrayBuffer(
      12 + vertices.length * 12 + indices.length * 4,
    ),
    v = new DataView(buffer);
  new Uint8Array(buffer).set([77, 77, 84, 49]);
  v.setUint32(4, vertices.length, true);
  v.setUint32(8, indices.length, true);
  vertices.flat().forEach((n, i) => v.setFloat32(12 + i * 4, n, true));
  indices.forEach((n, i) =>
    v.setUint32(12 + vertices.length * 12 + i * 4, n, true),
  );
  return parseMesh(buffer);
}
test("shared links round-trip map, camera, selection, sources, layers, tools and orientation", () => {
  const s = {
    inst: 1,
    mode: "3d",
    flyover: true,
    labelTiers: new Set(["zone", "town"]),
    camera: { cx: 32.2, cy: 45.6, zoom: 178.9 },
    yaw: -1.2,
    tilt: 52,
    layers: new Set(["flight", "labels", "scenery"]),
    tools: new Set(["walk", "coverage"]),
    selection: { kind: "quest", id: 33 },
    sources: [{ kind: "npc", id: 299 }],
    marker: [33, 41],
  };
  const got = readView(writeView(s));
  assert.deepEqual(got, {
    ...s,
    layers: ["flight", "labels", "scenery"],
    tools: ["coverage", "walk"],
    labelTiers: ["town", "zone"],
  });
});
test("first visit is a quiet 3D flyover; preferences and explicit links win", () => {
  assert.equal(readView("").mode, "3d");
  assert.equal(readView("").inst, 1);
  assert.equal(readView("").flyover, true);
  assert.deepEqual(readView("").layers, ["labels"]);
  assert.deepEqual(readView("").labelTiers, ["zone"]);
  assert.equal(readView("", "2d").mode, "2d");
  assert.equal(readView("", "2d").flyover, false);
  assert.equal(readView("#view=2d", "3d").mode, "2d");
  assert.equal(readView("#view=3d", "2d").mode, "3d");
  assert.equal(readView("#view=2d&fly=1").flyover, false);
  assert.equal(readView("#view=3d&fly=0").flyover, false);
  assert.equal(readView("#x=31&y=50").flyover, false);
  assert.equal(readView("#select=npc:448").flyover, false);
  assert.equal(readView("#x=31&y=50&fly=1").flyover, true);
  assert.deepEqual(readView("#names=subzone,zone,unknown").labelTiers, [
    "subzone",
    "zone",
  ]);
  assert.deepEqual(readView("#names=").labelTiers, []);
  assert.deepEqual(readView("#layers=quest,ore,borders").layers, [
    "quest",
    "ore",
    "borders",
  ]);
});
test("bad URL values cannot poison the camera", () => {
  const s = readView(
    "#map=NaN&x=Infinity&y=foo&z=-2&tilt=999&yaw=no&select=script:3&layers=garbage&tools=wat",
  );
  assert.equal(s.inst, 1);
  assert.equal(s.camera, null);
  assert.equal(s.tilt, 65);
  assert.equal(s.yaw, 0);
  assert.equal(s.selection, null);
  assert.deepEqual(s.layers, []);
});
test("retina textures remain sharp at distant mesh levels with a bounded framebuffer", () => {
  assert.equal(renderDensity(390, 844, 3), 3);
  assert(renderDensity(2560, 1440, 3) ** 2 * 2560 * 1440 <= 8_000_001);
  assert.equal(textureResolution(60, 3), 256);
  assert.equal(textureResolution(180, 3), 512);
  assert.equal(textureResolution(20, 3), 128);
  assert.equal(textureResolution(20, 1), 64);
});
test("flyover pitch starts without a jump and remains bounded over repeated cycles", () => {
  for (const tilt of [0, 3, 45, 62, 65]) {
    assert.equal(flyoverPitch(tilt, 0), tilt);
    for (let t = 0; t < 360; t += 0.5) {
      const angle = flyoverPitch(tilt, t);
      assert(angle >= 0 && angle <= 65);
      assert(Math.abs(angle - flyoverPitch(tilt, t + 0.01)) < 0.011);
    }
  }
  assert(flyoverPitch(45, 10) > 50);
  assert(flyoverPitch(45, 35) < 40);
});
test("request tickets invalidate older requests immediately and across round trips to the same map", () => {
  const r = new Requests(),
    a = r.ticket("pins"),
    b = r.ticket("pins"),
    c = r.ticket("walk");
  assert(!r.current(a));
  assert(r.current(b));
  assert(r.current(c));
  const signal = r.controller.signal;
  r.reset();
  assert(signal.aborted);
  r.ticket("pins");
  assert(!r.current(b));
});
test("projection and unprojection preserve position across tilt and bearing", () => {
  const cam = { cx: 32, cy: 48, zoom: 220 };
  for (const tilt of [0, 25, 65])
    for (const yaw of [0, 0.5, -2])
      for (const z of [-100, 0, 440]) {
        const p = project(33.1, 48.2, z, cam, 1200, 800, yaw, tilt, 30),
          q = unproject(p[0], p[1], z, cam, 1200, 800, yaw, tilt, 30);
        near(q[0], 33.1);
        near(q[1], 48.2);
      }
});
test("visible bounds cover all tilted viewport corners at min and max elevation", () => {
  const cam = { cx: 32, cy: 48, zoom: 220 },
    bounds = visibleBounds(cam, 1000, 700, 0.7, 65, 0, -900, 2200);
  for (const z of [-900, 2200])
    for (const x of [0, 1000])
      for (const y of [0, 700]) {
        const p = unproject(x, y, z, cam, 1000, 700, 0.7, 65, 0);
        assert(
          p[0] >= bounds[0] - 1e-9 &&
            p[0] <= bounds[2] + 1e-9 &&
            p[1] >= bounds[1] - 1e-9 &&
            p[1] <= bounds[3] + 1e-9,
        );
      }
});
test("native centre fan sampling preserves peaks and ground holes", () => {
  const m = mesh(
    [
      [32, 48, 0],
      [33, 48, 0],
      [33, 49, 0],
      [32, 49, 0],
      [32.5, 48.5, 100],
    ],
    [0, 1, 4, 1, 2, 4, 2, 3, 4],
  );
  near(sample(m, 32.5, 48.5).height, 100);
  near(sample(m, 32.5, 48.25).height, 50);
  assert.equal(sample(m, 32.1, 48.5), null);
  assert(sample(m, 32.5, 48.25).slope > 0);
});
test("screen picking uses the same triangles as rendering, including yaw, slope and holes", () => {
  const m = mesh(
    [
      [32, 48, 0],
      [33, 48, 100],
      [33, 49, 150],
      [32, 49, 50],
    ],
    [0, 1, 2, 0, 2, 3],
  );
  const camera = { cx: 32.5, cy: 48.5, zoom: 300 };
  const projectPoint = (...p) => project(...p, camera, 1200, 800, 0.6, 55, 0),
    unprojectPoint = (...p) => unproject(...p, camera, 1200, 800, 0.6, 55, 0);
  const z = sample(m, 32.4, 48.2).height,
    p = projectPoint(32.4, 48.2, z),
    hit = pickMesh(m, p[0], p[1], projectPoint, unprojectPoint, 0, 150);
  near(hit.col, 32.4);
  near(hit.row, 48.2);
  near(hit.height, z);
  assert.equal(
    pickMesh(m, -900, -900, projectPoint, unprojectPoint, 0, 150),
    null,
  );
});
test("slope is measured in game yards, never tile units", () => {
  const m = mesh(
    [
      [0, 0, 0],
      [1, 0, TILE_YARDS],
      [0, 1, 0],
    ],
    [0, 1, 2],
  );
  near(sample(m, 0.2, 0.2).slope, 45);
});
test("malformed geometry is rejected before GPU allocation", () => {
  assert.throws(() => parseMesh(new ArrayBuffer(8)));
  assert.throws(() => mesh([[0, 0, 0]], [0, 1, 2]));
  assert.throws(() => mesh([[NaN, 0, 0]], [0, 0, 0]));
});
test("fitting single and full-map locations stays finite and bounded", () => {
  for (const b of [
    [32, 48, 32, 48],
    [0, 0, 64, 64],
  ]) {
    const c = fitBounds(b, 390, 400);
    assert(Number.isFinite(c.zoom) && c.zoom >= 4 && c.zoom <= 1024);
  }
});
