import {
  project,
  unproject,
  visibleBounds,
  sample,
  pickMesh,
} from "./terrain-scene.mjs";
import { program, upload, dispose, uniforms } from "./terrain-render.mjs";
import { fitBounds, clamp } from "./view-state.mjs";
import { WorldObjects } from "./world-objects.mjs";
import { TerrainTextures } from "./terrain-textures.mjs";
import { TileStream } from "./tile-stream.mjs";
import { TerrainDecoder } from "./terrain-decoder.mjs";
import { TerrainPreview } from "./terrain-preview.mjs";
import { renderDensity, textureResolution } from "./terrain-quality.mjs";
const intersects = (t, b) =>
  Math.floor(t.key / 64) + 1 >= b[0] &&
  Math.floor(t.key / 64) <= b[2] &&
  (t.key % 64) + 1 >= b[1] &&
  t.key % 64 <= b[3];
const safeFile = (base, file) => {
  if (
    typeof file !== "string" ||
    file.includes("..") ||
    file.startsWith("/") ||
    file.includes(":")
  )
    throw Error("Invalid asset path");
  return `${base}/${file}`;
};
export class TerrainView {
  constructor(canvas, changed, onLost) {
    this.canvas = canvas;
    this.changed = changed;
    this.onLost = onLost;
    const gl = canvas.getContext("webgl2", { alpha: false, antialias: true });
    if (!gl) throw Error("WebGL2 is unavailable. The 2D map is ready to use.");
    this.gl = gl;
    this.program = program(gl);
    this.cache = new Map();
    this.waiting = new Set();
    this.failed = new Set();
    this.active = 0;
    this.epoch = 0;
    this.controller = new AbortController();
    this.objects = new WorldObjects(gl);
    this.textures = new TerrainTextures(gl, changed);
    this.decoder = new TerrainDecoder();
    this.meshStream = new TileStream(changed, 6);
    this.displayed = new Map();
    this.previews = new Map(); // per map (inst): its overview, at its offset
    this.scenery = false;
    this.visible = [];
    this.focus = 0;
    this.focusPending = true;
    this.focusLocked = false;
    this.bytes = 0;
    canvas.addEventListener("webglcontextlost", (e) => {
      e.preventDefault();
      this.lost = true;
      this.controller.abort();
      this.textures.clear();
      this.meshStream.clear();
      for (const p of this.previews.values()) p.clear();
      onLost("WebGL context lost. Switched to 2D.");
    });
  }
  setMap(inst, assets) {
    this.controller.abort();
    this.controller = new AbortController();
    this.epoch++;
    for (const e of this.cache.values()) dispose(this.gl, e.gpu);
    this.cache.clear();
    this.displayed.clear();
    this.meshStream.clear();
    this.detailLevel = "coarse";
    this.lastCamera = null;
    this.focusAt = null;
    this.waiting.clear();
    this.failed.clear();
    this.bytes = 0;
    this.objects.clear();
    this.inst = inst;
    this.version = assets.version;
    this.manifest = assets.terrain.data;
    this.objectManifest = assets.objects.available ? assets.objects.data : null;
    this.tileAssets = new Set(assets.tiles);
    const src = new Map(this.manifest.tiles.map((t) => [t.key, t]));
    this.textures.setMap(
      (key, size) => {
        const t = src.get(key);
        return `tiles/${t.inst}/${size === 512 ? "" : size + "/"}${t.src}.webp?v=${encodeURIComponent(this.version)}`;
      },
      new Set([...this.tileAssets].filter((k) => src.has(k))),
      this.controller.signal,
    );
    // The world's maps: each one's files in terrain/<inst>/, its meshes moved by its offset.
    this.offsets = new Map(this.manifest.parts.map((p) => [p.inst, p.offset]));
    for (const p of this.previews.values()) p.clear();
    this.previews = new Map(
      this.manifest.parts.map((p) => {
        const preview = new TerrainPreview(this.gl, this.changed, this.decoder);
        preview.load(
          p.preview,
          (file) =>
            safeFile(`terrain/${p.inst}`, file) +
            `?v=${encodeURIComponent(this.version)}`,
          this.controller.signal,
          p.offset,
        );
        return [p.inst, preview];
      }),
    );
    this.visible = [];
    this.focus = 0;
    this.focusPending = true;
    this.focusLocked = false;
    this.min = Math.min(0, ...this.manifest.tiles.map((t) => t.min ?? 0));
    this.max = Math.max(0, ...this.manifest.tiles.map((t) => t.max ?? 0));
  }
  setView(camera, w, h, yaw, tilt) {
    this.camera = camera;
    this.w = w;
    this.h = h;
    this.yaw = yaw;
    this.tilt = tilt;
    this.focusOnGround();
  }
  focusOnGround() {
    if (this.focusLocked || !this.camera || !this.manifest) return;
    if (
      !this.focusPending &&
      this.focusAt?.cx === this.camera.cx &&
      this.focusAt?.cy === this.camera.cy
    )
      return;
    const ground = this.sample(this.camera.cx, this.camera.cy);
    if (ground) {
      this.focus = ground.height;
      this.focusPending = false;
      this.focusAt = { cx: this.camera.cx, cy: this.camera.cy };
    }
  }
  point(c, r, h) {
    return project(
      c,
      r,
      h,
      this.camera,
      this.w,
      this.h,
      this.yaw,
      this.tilt,
      this.focus,
    );
  }
  plane(x, y, h = this.focus) {
    return unproject(
      x,
      y,
      h,
      this.camera,
      this.w,
      this.h,
      this.yaw,
      this.tilt,
      this.focus,
    );
  }
  project(c, r) {
    return this.point(c, r, this.sample(c, r)?.height ?? this.focus).slice(
      0,
      2,
    );
  }
  fit(points, w, h) {
    const bounds = [
      Math.min(...points.map((p) => p.col)),
      Math.min(...points.map((p) => p.row)),
      Math.max(...points.map((p) => p.col)),
      Math.max(...points.map((p) => p.row)),
    ];
    const goal = fitBounds(bounds, w, h),
      p = points.map((p) => this.project(p.col, p.row));
    const dx =
        Math.max(...p.map((p) => p[0])) - Math.min(...p.map((p) => p[0])),
      dy = Math.max(...p.map((p) => p[1])) - Math.min(...p.map((p) => p[1]));
    goal.zoom = clamp(
      Math.min(
        w / Math.max(this.camera.zoom * 0.6, dx),
        h / Math.max(this.camera.zoom * 0.6, dy),
      ) *
        this.camera.zoom *
        0.8,
      4,
      1024,
    );
    return goal;
  }
  bounds() {
    return visibleBounds(
      this.camera,
      this.w,
      this.h,
      this.yaw,
      this.tilt,
      this.focus,
      this.min,
      this.max,
    );
  }
  lod() {
    const zoom = this.camera?.zoom || 0;
    if (zoom >= 560 || (this.detailLevel === "native" && zoom >= 450))
      this.detailLevel = "native";
    else if (zoom >= 90 || (this.detailLevel !== "coarse" && zoom >= 70))
      this.detailLevel = "detail";
    else this.detailLevel = "coarse";
    return this.detailLevel;
  }
  textureSize() {
    return textureResolution(
      this.camera.zoom,
      renderDensity(this.w, this.h, devicePixelRatio || 1),
    );
  }
  entry(key) {
    if (this.interacting && this.cache.has(this.displayed.get(key)))
      return this.cache.get(this.displayed.get(key));
    const lod = this.lod();
    return (
      this.cache.get(`${key}:${lod}`) ||
      (lod === "native" && this.cache.get(`${key}:detail`)) ||
      this.cache.get(`${key}:coarse`) ||
      this.cache.get(`${key}:detail`) ||
      this.cache.get(`${key}:native`)
    );
  }
  visibleTile(t, margin = 0) {
    const c = Math.floor(t.key / 64),
      r = t.key % 64;
    const p = [t.min ?? 0, t.max ?? 0].flatMap((z) =>
      [
        [c, r],
        [c + 1, r],
        [c, r + 1],
        [c + 1, r + 1],
      ].map((a) => this.point(...a, z)),
    );
    return (
      Math.max(...p.map((a) => a[0])) >= -margin &&
      Math.min(...p.map((a) => a[0])) <= this.w + margin &&
      Math.max(...p.map((a) => a[1])) >= -margin &&
      Math.min(...p.map((a) => a[1])) <= this.h + margin
    );
  }
  sample(c, r) {
    const key = Math.floor(c) * 64 + Math.floor(r),
      entry = this.entry(key);
    const got = entry && sample(entry.mesh, c, r);
    return got ? { ...got, resolution: entry.lod, groundOnly: true } : null;
  }
  pick(x, y) {
    let best = null;
    for (const t of this.visible) {
      const e = this.entry(t.key);
      if (!e) continue;
      const got = pickMesh(
        e.mesh,
        x,
        y,
        (...p) => this.point(...p),
        (...p) => this.plane(...p),
        t.min ?? this.min,
        t.max ?? this.max,
      );
      if (got && (!best || got.depth > best.depth)) best = got;
    }
    return best ? [best.col, best.row] : null;
  }
  async fetchFile(url, type, signal) {
    const r = await fetch(url, { signal });
    if (!r.ok) throw Error(`${r.status}: ${url}`);
    return type === "json" ? r.json() : r.arrayBuffer();
  }
  meshJob(t, lod, priority) {
    const key = `${t.key}:${lod}`;
    if (this.cache.has(key) || !t.lods[lod]) return null;
    return {
      key,
      priority,
      run: async (signal) => {
        const buffer = await this.fetchFile(
          safeFile(`terrain/${t.inst}`, t.lods[lod]) +
            `?v=${encodeURIComponent(this.version)}`,
          "buffer",
          signal,
        );
        return this.decoder.decode(buffer, {
          signal,
          offset: this.offsets.get(t.inst),
        });
      },
      apply: (mesh) => {
        const gpu = upload(this.gl, mesh);
        delete mesh.normals;
        this.cache.set(key, { mesh, gpu, lod, key, used: performance.now() });
        this.bytes += gpu.bytes + mesh.bytes;
        this.focusOnGround();
        this.changed();
      },
    };
  }
  requestObjects(t) {
    const key = `objects:${t.key}`;
    if (
      this.active >= 6 ||
      this.objects.tiles.has(t.key) ||
      this.waiting.has(key) ||
      this.failed.has(key)
    )
      return;
    const epoch = this.epoch,
      signal = this.controller.signal;
    this.waiting.add(key);
    this.active++;
    this.fetchFile(
      safeFile(`objects/${t.inst}`, t.file) +
        `?v=${encodeURIComponent(this.version)}`,
      "json",
      signal,
    )
      .then((data) => {
        const [dx, dy] = this.offsets.get(t.inst) || [0, 0];
        for (const i of data.instances || []) (i.col += dx), (i.row += dy);
        if (epoch === this.epoch && !this.lost) this.objects.add(t.key, data);
      })
      .catch((e) => {
        if (epoch === this.epoch && e.name !== "AbortError")
          this.failed.add(key);
      })
      .finally(() => {
        this.active--;
        if (epoch === this.epoch) this.waiting.delete(key);
        this.changed();
      });
  }
  render(tools = new Set()) {
    if (this.lost || !this.manifest) return;
    const gl = this.gl,
      dpr = renderDensity(this.w, this.h, devicePixelRatio || 1),
      w = Math.round(this.w * dpr),
      h = Math.round(this.h * dpr);
    if (this.canvas.width !== w || this.canvas.height !== h) {
      this.canvas.width = w;
      this.canvas.height = h;
    }
    gl.viewport(0, 0, w, h);
    gl.enable(gl.DEPTH_TEST);
    gl.clearColor(0.035, 0.065, 0.065, 1);
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    this.focusOnGround();
    const bounds = this.bounds();
    this.visible = this.manifest.tiles.filter(
      (t) => intersects(t, bounds) && this.visibleTile(t),
    );
    this.visible.sort(
      (a, b) =>
        Math.hypot(
          Math.floor(a.key / 64) + 0.5 - this.camera.cx,
          (a.key % 64) + 0.5 - this.camera.cy,
        ) -
        Math.hypot(
          Math.floor(b.key / 64) + 0.5 - this.camera.cx,
          (b.key % 64) + 0.5 - this.camera.cy,
        ),
    );
    // Refine the centre independently of slow outer tiles. The overview remains
    // underneath, so loading a particular source ADT never gates the whole view.
    const textureSize = this.textureSize(),
      meshJobs = [],
      imageJobs = [];
    const rank = (t) =>
      (Math.hypot(
        Math.floor(t.key / 64) + 0.5 - this.camera.cx,
        (t.key % 64) + 0.5 - this.camera.cy,
      ) *
        this.camera.zoom) /
      Math.max(this.w, this.h);
    const addMesh = (t, lod, priority) => {
      const job = this.meshJob(t, lod, priority);
      if (job) meshJobs.push(job);
    };
    for (const t of this.visible) {
      const priority = rank(t);
      if (!this.entry(t.key)) addMesh(t, "coarse", priority);
      else if (!this.interacting && this.lod() !== "coarse")
        addMesh(t, t.lods[this.lod()] ? this.lod() : "native", priority + 4);
      imageJobs.push({ key: t.key, size: textureSize, priority });
    }
    const visibleKeys = new Set(this.visible.map((t) => t.key));
    const nearBounds = bounds.map((v, i) => v + (i < 2 ? -2 : 2));
    const now = performance.now(),
      last = this.lastCamera,
      dt = last ? Math.max(16, now - last.time) : 16;
    const lead = {
      cx:
        this.camera.cx +
        clamp(last ? ((this.camera.cx - last.cx) * 200) / dt : 0, -2, 2),
      cy:
        this.camera.cy +
        clamp(last ? ((this.camera.cy - last.cy) * 200) / dt : 0, -2, 2),
    };
    this.lastCamera = { ...this.camera, time: now };
    const nearby = this.manifest.tiles.filter(
      (t) =>
        !visibleKeys.has(t.key) &&
        intersects(t, nearBounds) &&
        this.visibleTile(t, Math.max(this.w, this.h) * 0.6),
    );
    nearby.sort(
      (a, b) =>
        Math.hypot(
          Math.floor(a.key / 64) + 0.5 - lead.cx,
          (a.key % 64) + 0.5 - lead.cy,
        ) -
        Math.hypot(
          Math.floor(b.key / 64) + 0.5 - lead.cx,
          (b.key % 64) + 0.5 - lead.cy,
        ),
    );
    for (const t of nearby.slice(0, 48)) {
      addMesh(t, "coarse", 50 + rank(t));
      imageJobs.push({ key: t.key, size: 128, priority: 50 + rank(t) });
      visibleKeys.add(t.key);
    }
    this.meshStream.update(meshJobs);
    this.textures.update(
      imageJobs,
      [...this.previews.values()].every((p) => p.texture),
    );
    this.meshStream.commit(this.interacting ? 1 : 2, 3);
    this.textures.stream.commit(this.interacting ? 1 : 2, 3);
    const at = uniforms(
        gl,
        this.program,
        this.camera,
        this.w,
        this.h,
        this.yaw,
        this.tilt,
        this.focus,
      ),
      keep = new Set();
    gl.uniform1i(at("instanced"), 0);
    gl.uniform1i(
      at("analysis"),
      tools.has("slope") ? 2 : tools.has("elevation") ? 1 : 0,
    );
    gl.uniform1i(at("contours"), tools.has("contours") ? 1 : 0);
    gl.uniform3f(at("tint"), 0.34, 0.45, 0.32);
    for (const t of this.visible) {
      const e = this.entry(t.key);
      if (!e) {
        // Overview geometry is only a visual placeholder, never ground analysis.
        gl.uniform1i(at("analysis"), 0);
        gl.uniform1i(at("contours"), 0);
        this.previews.get(t.inst)?.draw(t.key, at);
        gl.uniform1i(
          at("analysis"),
          tools.has("slope") ? 2 : tools.has("elevation") ? 1 : 0,
        );
        gl.uniform1i(at("contours"), tools.has("contours") ? 1 : 0);
        continue;
      }
      this.displayed.set(t.key, e.key);
      keep.add(e.key);
      e.used = performance.now();
      gl.bindVertexArray(e.gpu.vao);
      this.textures.bind(t.key, at, this.previews.get(t.inst));
      gl.drawElements(gl.TRIANGLES, e.gpu.count, gl.UNSIGNED_INT, 0);
    }
    const objectTiles =
      this.scenery && this.camera.zoom >= 100
        ? (this.objectManifest?.tiles || []).filter((t) =>
            intersects(t, bounds),
          )
        : [];
    this.objectKeys = new Set(objectTiles.slice(0, 36).map((t) => t.key));
    if (!this.interacting)
      for (const t of objectTiles.slice(0, 36)) this.requestObjects(t);
    gl.uniform1f(at("textureBlend"), 1);
    if (this.scenery) this.objects.draw(at, this.objectKeys);
    this.objects.trim(this.objectKeys);
    gl.bindVertexArray(null);
    for (const e of [...this.cache.values()].sort((a, b) => a.used - b.used)) {
      if (this.bytes < 96 * 1024 * 1024) break;
      if (
        keep.has(e.key) ||
        (e.lod === "coarse" && visibleKeys.has(Number(e.key.split(":")[0])))
      )
        continue;
      dispose(gl, e.gpu);
      this.bytes -= e.mesh.bytes + e.gpu.bytes;
      this.cache.delete(e.key);
    }
    this.textures.trim(visibleKeys);
  }
  pickBuilding(x, y) {
    return this.scenery
      ? this.objects.pick(
          x,
          y,
          (...p) => this.point(...p),
          this.objectKeys || new Set(),
        )
      : null;
  }
  diagnostics() {
    const previews = [...this.previews.values()],
      sum = (f) => previews.reduce((n, p) => n + f(p), 0);
    return {
      visible: this.visible.length,
      loaded: this.visible.filter((t) => this.entry(t.key)).length,
      native: [...this.cache.values()].filter((e) => e.lod === "native").length,
      pending:
        this.active +
        this.meshStream.active.size +
        this.meshStream.ready.size +
        this.textures.waiting.size +
        sum((p) => Number(p.pending)),
      failed:
        this.failed.size +
        this.meshStream.failed.size +
        this.textures.failed.size +
        sum((p) => Number(p.failed)),
      memoryMB: Math.round(
        (this.bytes + this.textures.bytes + sum((p) => p.bytes)) / 1048576,
      ),
      backgroundMeshes: !!this.decoder.worker,
      cancelled: this.meshStream.cancelled + this.textures.stream.cancelled,
      previewReady: previews.some((p) => p.gpu),
      previewTiles: this.visible.filter(
        (t) =>
          !this.entry(t.key) &&
          this.previews.get(t.inst)?.ranges.get(t.key)?.count,
      ).length,
      pixelRatio: renderDensity(this.w, this.h, devicePixelRatio || 1),
      textureSize: this.textureSize(),
      textured: this.visible.filter((t) => this.textures.cache.has(t.key))
        .length,
      sceneryTiles: this.objects.tiles.size,
    };
  }
  dispose() {
    this.controller.abort();
    this.epoch++;
    for (const e of this.cache.values()) dispose(this.gl, e.gpu);
    this.objects.clear();
    this.textures.clear();
    for (const p of this.previews.values()) p.clear();
    this.meshStream.clear();
    this.decoder.dispose();
    this.gl.deleteProgram(this.program);
    this.cache.clear();
  }
}
