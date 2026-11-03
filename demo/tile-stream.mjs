// Reconciles work against the *current* view. Completed results wait for the
// renderer's upload budget; network completion never uploads directly to the GPU.
export class TileStream {
  constructor(changed, limit = 6) {
    this.changed = changed;
    this.limit = limit;
    this.active = new Map();
    this.ready = new Map();
    this.wanted = new Map();
    this.failed = new Set();
    this.epoch = 0;
    this.cancelled = 0;
  }
  update(jobs) {
    this.wanted = new Map(jobs.map((job) => [job.key, job]));
    for (const [key, job] of this.active)
      if (!this.wanted.has(key)) {
        job.controller.abort();
        this.active.delete(key);
        this.cancelled++;
      }
    for (const [key, result] of this.ready)
      if (!this.wanted.has(key)) {
        result.job.discard?.(result.value);
        this.ready.delete(key);
      }
    // Warm-up downloads must yield their slots when a new visible area needs
    // data, even if those old requests still fall inside the prefetch margin.
    const pending = [...this.wanted.values()]
      .filter(
        (j) =>
          !this.active.has(j.key) &&
          !this.ready.has(j.key) &&
          !this.failed.has(j.key),
      )
      .sort((a, b) => a.priority - b.priority);
    for (const job of pending) {
      if (this.active.size < this.limit) break;
      const worst = [...this.active].sort(
        (a, b) =>
          (this.wanted.get(b[0])?.priority ?? Infinity) -
          (this.wanted.get(a[0])?.priority ?? Infinity),
      )[0];
      if (!worst || this.wanted.get(worst[0]).priority <= job.priority + 3)
        break;
      worst[1].controller.abort();
      this.active.delete(worst[0]);
      this.cancelled++;
    }
    this.pump();
  }
  pump() {
    for (const job of [...this.wanted.values()].sort(
      (a, b) => a.priority - b.priority,
    )) {
      if (
        this.active.size >= this.limit ||
        this.active.size + this.ready.size >= this.limit + 2
      )
        break;
      if (
        this.active.has(job.key) ||
        this.ready.has(job.key) ||
        this.failed.has(job.key)
      )
        continue;
      const controller = new AbortController(),
        epoch = this.epoch;
      this.active.set(job.key, { job, controller });
      Promise.resolve()
        .then(() => job.run(controller.signal))
        .then((value) => {
          if (
            epoch !== this.epoch ||
            controller.signal.aborted ||
            !this.wanted.has(job.key)
          )
            job.discard?.(value);
          else this.ready.set(job.key, { job, value });
        })
        .catch((error) => {
          if (
            epoch === this.epoch &&
            !controller.signal.aborted &&
            error.name !== "AbortError"
          )
            this.failed.add(job.key);
        })
        .finally(() => {
          if (this.active.get(job.key)?.controller === controller)
            this.active.delete(job.key);
          if (epoch === this.epoch) {
            this.changed();
            this.pump();
          }
        });
    }
  }
  commit(limit = 1, budget = 3) {
    const start = performance.now();
    let count = 0;
    const pending = [...this.ready].sort(
      (a, b) =>
        (this.wanted.get(a[0])?.priority ?? Infinity) -
        (this.wanted.get(b[0])?.priority ?? Infinity),
    );
    for (const [key, { job, value }] of pending) {
      if (count >= limit || (count && performance.now() - start >= budget))
        break;
      this.ready.delete(key);
      this.wanted.delete(key);
      try {
        job.apply(value);
      } catch (error) {
        job.discard?.(value);
        this.failed.add(key);
      }
      count++;
    }
    if (this.ready.size) this.changed();
    this.pump();
  }
  clear() {
    this.epoch++;
    for (const { controller } of this.active.values()) controller.abort();
    for (const { job, value } of this.ready.values()) job.discard?.(value);
    this.active.clear();
    this.ready.clear();
    this.wanted.clear();
    this.failed.clear();
  }
}
