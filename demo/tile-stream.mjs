// Reconciles work against the *current* view. Completed results wait for the
// renderer's upload budget; network completion never uploads directly to the GPU.
// A failed job is tried again later (about 1, 2, 4, 8 s: the host 503s in bursts), then left.
const RETRIES = 4;
export class TileStream {
  constructor(changed, limit = 6) {
    this.changed = changed;
    this.limit = limit;
    this.active = new Map();
    this.ready = new Map();
    this.wanted = new Map();
    this.failed = new Map(); // key -> { tries, until }
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
          !this.waiting(j.key),
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
        this.waiting(job.key)
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
            this.fail(job.key);
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
  waiting(key) {
    const f = this.failed.get(key);
    return !!f && (f.tries >= RETRIES || performance.now() < f.until);
  }
  fail(key) {
    const tries = (this.failed.get(key)?.tries || 0) + 1;
    const delay = 2 ** (tries - 1) * (800 + Math.random() * 400);
    this.failed.set(key, { tries, until: performance.now() + delay });
    if (tries < RETRIES) {
      const epoch = this.epoch;
      setTimeout(() => { if (epoch === this.epoch) this.pump(); }, delay + 20);
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
        this.failed.set(key, { tries: RETRIES, until: Infinity }); // (a bad result: no retry)
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
