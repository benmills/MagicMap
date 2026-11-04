// Serializable view state. No browser dependencies: also used by the integration tests.
// A fresh view shows flight points, dungeon entrances and zone names; the rest is in the menu's Advanced page.
export const DEFAULT_LAYERS = ["flight", "dungeon", "labels"];
export const DEFAULT_LABEL_TIERS = ["zone"];
export const LABEL_TIERS = ["continent", "zone", "town", "subzone", "poi"];
export const LAYER_IDS = [
  "flight",
  "poi",
  "dungeon",
  "rare",
  "service",
  "quest",
  "labels",
  "mail",
  "herb",
  "ore",
  "scenery",
];
export const TOOL_IDS = [
  "elevation",
  "slope",
  "contours",
  "walk",
];
export const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
const number = (p, k, fallback, lo, hi) => {
  if (!p.has(k)) return fallback;
  const v = Number(p.get(k));
  return Number.isFinite(v) ? clamp(v, lo, hi) : fallback;
};
export function readView(hash, preferred = "2d") {
  const p = new URLSearchParams(hash.replace(/^#/, ""));
  const cx = number(p, "x", null, -64, 128),
    cy = number(p, "y", null, -64, 128);
  const mode = ["2d", "3d"].includes(p.get("view"))
    ? p.get("view")
    : preferred === "3d"
      ? "3d"
      : "2d";
  return {
    inst: Math.round(number(p, "map", 1, 0, 100000)),
    mode,
    // Motion is always an explicit choice, including remembered 3D views.
    flyover: mode === "3d" && p.get("fly") === "1",
    labelTiers: p.has("names")
      ? p
          .get("names")
          .split(",")
          .filter((t) => LABEL_TIERS.includes(t))
      : DEFAULT_LABEL_TIERS,
    camera:
      cx !== null && cy !== null
        ? { cx, cy, zoom: number(p, "z", 32, 4, 1024) }
        : null,
    yaw: number(p, "yaw", 0, -Math.PI, Math.PI),
    tilt: number(p, "tilt", 45, 0, 65),
    layers: p.has("layers")
      ? p
          .get("layers")
          .split(",")
          .filter((x) => LAYER_IDS.includes(x))
      : DEFAULT_LAYERS,
    pins: p.get("pins") !== "0", // the menu's Map Pins: off keeps the layers picked
    tools: (p.get("tools") || "")
      .split(",")
      .filter((x) => TOOL_IDS.includes(x)),
  };
}
export function writeView(s) {
  const p = new URLSearchParams({ map: s.inst, view: s.mode });
  p.set("fly", s.flyover ? "1" : "0");
  p.set("names", [...(s.labelTiers || DEFAULT_LABEL_TIERS)].sort().join(","));
  if (s.camera)
    for (const [k, v] of Object.entries({
      x: s.camera.cx,
      y: s.camera.cy,
      z: s.camera.zoom,
    }))
      p.set(k, v.toFixed(5));
  p.set("yaw", s.yaw.toFixed(5));
  p.set("tilt", s.tilt.toFixed(1));
  p.set("layers", [...s.layers].sort().join(","));
  if (s.pins === false) p.set("pins", "0");
  if (s.tools.size || s.tools.length)
    p.set("tools", [...s.tools].sort().join(","));
  return "#" + p.toString();
}
export function fitBounds([c0, r0, c1, r1], width, height, padding = 0.8) {
  return {
    cx: (c0 + c1) / 2,
    cy: (r0 + r1) / 2,
    zoom: clamp(
      Math.min(
        width / Math.max(0.6, c1 - c0),
        height / Math.max(0.6, r1 - r0),
      ) * padding,
      4,
      1024,
    ),
  };
}
// Each asynchronous operation captures a ticket before yielding, including its map epoch.
export class Requests {
  epoch = 0;
  sequences = new Map();
  controller = new AbortController();
  reset() {
    this.controller.abort();
    this.controller = new AbortController();
    this.epoch++;
    this.sequences.clear();
  }
  ticket(name) {
    const n = (this.sequences.get(name) || 0) + 1;
    this.sequences.set(name, n);
    return [this.epoch, name, n];
  }
  current([epoch, name, n]) {
    return epoch === this.epoch && n === this.sequences.get(name);
  }
}
