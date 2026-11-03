import { upload, dispose } from "./terrain-render.mjs";

// Optional display-only overview. It never supplies inspection or picking data.
export class TerrainPreview {
  constructor(gl, changed, decoder) {
    this.gl = gl;
    this.changed = changed;
    this.decoder = decoder;
    this.epoch = 0;
    this.clear();
  }
  clear() {
    this.epoch++;
    dispose(this.gl, this.gpu);
    if (this.texture) this.gl.deleteTexture(this.texture);
    this.gpu = null;
    this.texture = null;
    this.ranges = new Map();
    this.bytes = 0;
    this.pending = false;
    this.failed = false;
  }
  async load(data, assetUrl, signal, offset) {
    this.clear();
    if (!data) return;
    const epoch = this.epoch;
    this.pending = true;
    let gpu, texture, bitmap;
    try {
      const response = async (file) => {
        const r = await fetch(assetUrl(file), { signal });
        if (!r.ok) throw Error(`Preview ${r.status}`);
        return r;
      };
      const [buffer, blob] = await Promise.all([
        response(data.mesh).then((r) => r.arrayBuffer()),
        data.image
          ? response(data.image)
              .then((r) => r.blob())
              .catch(() => null)
          : null,
      ]);
      if (epoch !== this.epoch || signal.aborted) return;
      const mesh = await this.decoder.decode(buffer, {
        spatialIndex: false,
        signal,
        offset,
      });
      const bounds = data.bounds;
      if (
        !Array.isArray(bounds) ||
        bounds.length !== 4 ||
        !bounds.every(Number.isFinite) ||
        bounds[2] <= bounds[0] ||
        bounds[3] <= bounds[1]
      )
        throw Error("Invalid preview bounds");
      const ranges = new Map();
      for (const t of data.tiles) {
        if (
          ![t.key, t.offset, t.count].every(Number.isInteger) ||
          t.offset < 0 ||
          t.count < 0 ||
          t.count % 3 ||
          t.offset + t.count > mesh.indices.length
        )
          throw Error("Invalid preview range");
        ranges.set(t.key, t);
      }
      if (blob) bitmap = await createImageBitmap(blob);
      if (epoch !== this.epoch || signal.aborted) return;
      const gl = this.gl;
      gpu = upload(gl, mesh);
      if (bitmap) {
        texture = gl.createTexture();
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
      }
      this.gpu = gpu;
      this.texture = texture;
      this.ranges = ranges;
      this.bounds = bounds;
      this.bytes =
        gpu.bytes +
        (bitmap ? Math.ceil((bitmap.width * bitmap.height * 16) / 3) : 0);
    } catch (error) {
      dispose(this.gl, gpu);
      if (texture) this.gl.deleteTexture(texture);
      if (epoch === this.epoch && error.name !== "AbortError")
        this.failed = true;
    } finally {
      bitmap?.close();
      if (epoch === this.epoch) {
        this.pending = false;
        this.changed();
      }
    }
  }
  bindTexture(at) {
    const gl = this.gl;
    gl.uniform1i(at("textured"), this.texture ? 1 : 0);
    gl.uniform1f(at("textureBlend"), 1);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, this.texture || null);
    if (this.bounds) {
      const [c0, r0, c1, r1] = this.bounds;
      gl.uniform2f(at("tileOrigin"), c0, r0);
      gl.uniform2f(at("textureScale"), 1 / (c1 - c0), 1 / (r1 - r0));
    }
  }
  draw(key, at) {
    const range = this.ranges.get(key);
    if (!this.gpu || !range?.count) return false;
    this.bindTexture(at);
    this.gl.bindVertexArray(this.gpu.vao);
    this.gl.drawElements(
      this.gl.TRIANGLES,
      range.count,
      this.gl.UNSIGNED_INT,
      range.offset * 4,
    );
    return true;
  }
}
