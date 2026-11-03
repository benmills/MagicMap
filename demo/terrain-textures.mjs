import { TileStream } from "./tile-stream.mjs";

// One texture per tile across all mesh levels. Replacements fade from the last
// image (or the overview) and uploads are committed by the frame loop.
export class TerrainTextures {
  constructor(gl, changed) {
    this.gl = gl;
    this.changed = changed;
    this.cache = new Map();
    this.bytes = 0;
    this.stream = new TileStream(changed, 6);
    this.failed = this.stream.failed;
    this.anisotropy =
      gl.getExtension("EXT_texture_filter_anisotropic") ||
      gl.getExtension("WEBKIT_EXT_texture_filter_anisotropic");
    this.anisotropyLevel = this.anisotropy
      ? Math.min(
          8,
          gl.getParameter(this.anisotropy.MAX_TEXTURE_MAX_ANISOTROPY_EXT),
        )
      : 1;
  }
  get waiting() {
    return new Map(
      [...this.stream.active.values()]
        .map(({ job }) => [job.tile, job.size])
        .concat(
          [...this.stream.ready.values()].map(({ job }) => [
            job.tile,
            job.size,
          ]),
        ),
    );
  }
  // url(key, size): a tile's image; keys: the tiles that have one.
  setMap(url, keys, signal) {
    this.clear();
    this.url = url;
    this.keys = keys;
    this.signal = signal;
  }
  update(wants, hasOverview) {
    const jobs = [];
    for (const { key, size, priority } of wants) {
      if (!this.keys.has(key) || this.cache.get(key)?.size >= size) continue;
      const target =
        !this.cache.has(key) && !hasOverview ? Math.min(128, size) : size;
      jobs.push({
        key: `${key}:${target}`,
        tile: key,
        size: target,
        priority,
        run: async (signal) => {
          const response = await fetch(this.url(key, target), { signal });
          if (!response.ok) throw Error(`Texture ${response.status}`);
          return createImageBitmap(await response.blob());
        },
        apply: (bitmap) => this.upload(key, target, bitmap),
        discard: (bitmap) => bitmap.close(),
      });
    }
    this.stream.update(jobs);
  }
  upload(key, size, bitmap) {
    const gl = this.gl,
      texture = gl.createTexture();
    try {
      gl.bindTexture(gl.TEXTURE_2D, texture);
      gl.texImage2D(
        gl.TEXTURE_2D,
        0,
        gl.RGBA,
        gl.RGBA,
        gl.UNSIGNED_BYTE,
        bitmap,
      );
      gl.generateMipmap(gl.TEXTURE_2D);
      gl.texParameteri(
        gl.TEXTURE_2D,
        gl.TEXTURE_MIN_FILTER,
        gl.LINEAR_MIPMAP_LINEAR,
      );
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
      if (this.anisotropy)
        gl.texParameterf(
          gl.TEXTURE_2D,
          this.anisotropy.TEXTURE_MAX_ANISOTROPY_EXT,
          this.anisotropyLevel,
        );
      const old = this.cache.get(key),
        bytes = Math.ceil((bitmap.width * bitmap.height * 16) / 3);
      if (old?.previous) {
        gl.deleteTexture(old.previous.texture);
        this.bytes -= old.previous.bytes;
      }
      const previous = old ? { texture: old.texture, bytes: old.bytes } : null;
      this.cache.set(key, {
        texture,
        size,
        bytes,
        previous,
        since: performance.now(),
        used: performance.now(),
      });
      this.bytes += bytes;
    } catch (error) {
      gl.deleteTexture(texture);
      throw error;
    } finally {
      bitmap.close();
    }
  }
  get(key) {
    const entry = this.cache.get(key);
    if (entry) entry.used = performance.now();
    return entry;
  }
  bind(key, at, preview) {
    const e = this.get(key),
      gl = this.gl;
    if (!e) {
      preview.bindTexture(at);
      gl.uniform1f(at("textureBlend"), 1);
      return;
    }
    gl.uniform2f(at("tileOrigin"), Math.floor(key / 64), key % 64);
    gl.uniform2f(at("textureScale"), 1, 1);
    gl.uniform1i(at("textured"), 1);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, e.texture);
    const blend = Math.min(1, (performance.now() - e.since) / 180);
    gl.uniform1f(at("textureBlend"), blend);
    const previous = e.previous?.texture || preview.texture;
    gl.uniform1i(at("previousTextured"), previous ? 1 : 0);
    gl.uniform1i(at("previousImage"), 1);
    gl.activeTexture(gl.TEXTURE1);
    gl.bindTexture(gl.TEXTURE_2D, previous || null);
    if (e.previous || !preview.bounds) {
      gl.uniform2f(at("previousOrigin"), Math.floor(key / 64), key % 64);
      gl.uniform2f(at("previousScale"), 1, 1);
    } else {
      const [c0, r0, c1, r1] = preview.bounds;
      gl.uniform2f(at("previousOrigin"), c0, r0);
      gl.uniform2f(at("previousScale"), 1 / (c1 - c0), 1 / (r1 - r0));
    }
    gl.activeTexture(gl.TEXTURE0);
    if (blend < 1) this.changed();
    else if (e.previous) {
      gl.deleteTexture(e.previous.texture);
      this.bytes -= e.previous.bytes;
      e.previous = null;
    }
  }
  trim(keep, budget = 64 * 1024 * 1024) {
    for (const [key, e] of [...this.cache].sort(
      (a, b) => a[1].used - b[1].used,
    )) {
      if (this.bytes <= budget) break;
      if (keep.has(key)) continue;
      this.gl.deleteTexture(e.texture);
      if (e.previous) this.gl.deleteTexture(e.previous.texture);
      this.bytes -= e.bytes + (e.previous?.bytes || 0);
      this.cache.delete(key);
    }
  }
  clear() {
    this.stream.clear();
    for (const e of this.cache.values()) {
      this.gl.deleteTexture(e.texture);
      if (e.previous) this.gl.deleteTexture(e.previous.texture);
    }
    this.cache.clear();
    this.bytes = 0;
  }
}
