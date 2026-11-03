import { parseMesh, meshNormals } from "./terrain-scene.mjs";

export class TerrainDecoder {
  constructor() {
    this.next = 0;
    this.queue = [];
    this.active = null;
    try {
      this.worker = new Worker(
        new URL("./terrain-worker.mjs", import.meta.url),
        { type: "module" },
      );
      this.worker.onmessage = ({ data }) => {
        const job = this.active;
        if (!job || job.id !== data.id) return;
        this.active = null;
        job.signal?.removeEventListener("abort", job.abort);
        if (data.error) job.reject(Error(data.error));
        else {
          const mesh = data.mesh;
          mesh.vertex = (i) => mesh.positions.subarray(i * 3, i * 3 + 3);
          job.resolve(mesh);
        }
        this.pump();
      };
      this.worker.onerror = () => {
        // An unavailable worker must leave terrain usable, including file hosts
        // with restrictive policies. Subsequent preparation runs between frames.
        this.worker.terminate();
        this.worker = null;
        if (this.active) {
          this.active.signal?.removeEventListener("abort", this.active.abort);
          this.active.reject(
            new DOMException("Retry without worker", "AbortError"),
          );
          this.active = null;
        }
        this.pump();
      };
    } catch {
      this.worker = null;
    }
  }
  decode(buffer, { spatialIndex = true, signal } = {}) {
    return new Promise((resolve, reject) => {
      const job = {
        id: ++this.next,
        buffer,
        spatialIndex,
        signal,
        resolve,
        reject,
      };
      job.abort = () =>
        reject(new DOMException("Superseded terrain", "AbortError"));
      if (signal?.aborted) return job.abort();
      signal?.addEventListener("abort", job.abort, { once: true });
      this.queue.push(job);
      this.pump();
    });
  }
  pump() {
    if (this.active) return;
    while (this.queue.length) {
      const job = this.queue.shift();
      if (job.signal?.aborted) continue;
      this.active = job;
      if (this.worker)
        this.worker.postMessage(
          { id: job.id, buffer: job.buffer, spatialIndex: job.spatialIndex },
          [job.buffer],
        );
      else
        setTimeout(() => {
          try {
            if (!job.signal?.aborted) {
              const mesh = parseMesh(job.buffer, {
                spatialIndex: job.spatialIndex,
              });
              mesh.normals = meshNormals(mesh);
              job.resolve(mesh);
            }
          } catch (error) {
            job.reject(error);
          } finally {
            job.signal?.removeEventListener("abort", job.abort);
            this.active = null;
            this.pump();
          }
        }, 0);
      break;
    }
  }
  dispose() {
    this.worker?.terminate();
    this.worker = null;
    for (const job of [...this.queue, ...(this.active ? [this.active] : [])]) {
      job.signal?.removeEventListener("abort", job.abort);
      job.abort();
    }
    this.queue = [];
    this.active = null;
  }
}
