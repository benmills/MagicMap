// Optional scenery: untextured instanced geometry, never used by ground inspection.
import { upload, dispose } from "./terrain-render.mjs";
import { barycentric, TILE_YARDS } from "./terrain-scene.mjs";
export class WorldObjects {
  constructor(gl) {
    this.gl = gl;
    this.tiles = new Map();
    this.errors = 0;
  }
  clear() {
    for (const t of this.tiles.values())
      for (const g of t.groups) dispose(this.gl, g.gpu);
    this.tiles.clear();
    this.errors = 0;
  }
  add(key, data) {
    const gl = this.gl,
      groups = [];
    if (
      !Array.isArray(data.meshes) ||
      !Array.isArray(data.instances) ||
      data.instances.length > 50000
    )
      throw Error("Invalid scenery tile");
    try {
      for (const m of data.meshes) {
        if (
          !Array.isArray(m.positions) ||
          !Array.isArray(m.indices) ||
          m.positions.length % 3 ||
          m.indices.length % 3 ||
          m.positions.length > 3000000 ||
          m.indices.length > 6000000
        )
          throw Error("Invalid scenery mesh");
        if (
          m.positions.some((n) => !Number.isFinite(n)) ||
          m.indices.some(
            (n) => !Number.isInteger(n) || n < 0 || n >= m.positions.length / 3,
          )
        )
          throw Error("Invalid scenery geometry");
        const mesh = {
          positions: new Float32Array(m.positions),
          indices: new Uint32Array(m.indices),
        };
        const instances = data.instances.filter((i) => i.mesh === m.id);
        for (const i of instances)
          if (
            ![i.col, i.row, i.height, i.heading ?? 0, i.scale ?? 1].every(
              Number.isFinite,
            ) ||
            (i.scale ?? 1) <= 0
          )
            throw Error("Invalid scenery placement");
        if (!instances.length) continue;
        const gpu = upload(gl, mesh, true);
        groups.push({ mesh, instances, gpu });
        gl.bindVertexArray(gpu.vao);
        const values = new Float32Array(
          instances.flatMap((i) => [
            i.col,
            i.row,
            i.height,
            i.heading || 0,
            i.scale ?? 1,
            0,
          ]),
        );
        const b = gl.createBuffer();
        gpu.buffers.push(b);
        gl.bindBuffer(gl.ARRAY_BUFFER, b);
        gl.bufferData(gl.ARRAY_BUFFER, values, gl.STATIC_DRAW);
        for (const [loc, offset] of [
          [2, 0],
          [3, 12],
        ]) {
          gl.enableVertexAttribArray(loc);
          gl.vertexAttribPointer(loc, 3, gl.FLOAT, false, 24, offset);
          gl.vertexAttribDivisor(loc, 1);
        }
      }
    } catch (e) {
      for (const g of groups) dispose(gl, g.gpu);
      throw e;
    }
    gl.bindVertexArray(null);
    this.tiles.set(key, { groups });
  }
  draw(at, keys) {
    const gl = this.gl;
    gl.uniform1i(at("instanced"), 1);
    gl.uniform1i(at("textured"), 0);
    gl.uniform1i(at("analysis"), 0);
    gl.uniform1i(at("contours"), 0);
    gl.uniform3f(at("tint"), 0.63, 0.57, 0.43);
    for (const key of keys)
      for (const g of this.tiles.get(key)?.groups || []) {
        gl.bindVertexArray(g.gpu.vao);
        gl.drawElementsInstanced(
          gl.TRIANGLES,
          g.gpu.count,
          gl.UNSIGNED_INT,
          0,
          g.instances.length,
        );
      }
  }
  trim(keys) {
    for (const [k, t] of this.tiles)
      if (!keys.has(k)) {
        for (const g of t.groups) dispose(this.gl, g.gpu);
        this.tiles.delete(k);
      }
  }
  pick(x, y, project, keys) {
    let best = null;
    for (const key of keys)
      for (const g of this.tiles.get(key)?.groups || [])
        for (const inst of g.instances) {
          const v = g.mesh.positions,
            co = Math.cos(inst.heading || 0),
            si = Math.sin(inst.heading || 0),
            s = inst.scale ?? 1;
          const points = [];
          for (let j = 0; j < v.length; j += 3)
            points.push(
              project(
                inst.col + ((co * v[j] - si * v[j + 1]) * s) / TILE_YARDS,
                inst.row + ((si * v[j] + co * v[j + 1]) * s) / TILE_YARDS,
                inst.height + v[j + 2] * s,
              ),
            );
          for (let j = 0; j < g.mesh.indices.length; j += 3) {
            const p = [0, 1, 2].map((k) => points[g.mesh.indices[j + k]]),
              w = barycentric(x, y, ...p);
            if (!w) continue;
            const depth = w.reduce((a, b, k) => a + b * p[k][2], 0);
            if (!best || depth > best.depth) best = { ...inst, depth };
          }
        }
    return best;
  }
}
