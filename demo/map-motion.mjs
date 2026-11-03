export const angleDelta = (a, b) =>
  Math.atan2(Math.sin(a - b), Math.cos(a - b));

export function pair(points) {
  const [a, b] = points;
  return b
    ? {
        x: (a.x + b.x) / 2,
        y: (a.y + b.y) / 2,
        span: Math.hypot(b.x - a.x, b.y - a.y),
        angle: Math.atan2(b.y - a.y, b.x - a.x),
      }
    : { x: a.x, y: a.y, span: 0, angle: 0 };
}

export function twoFingerMode(start, current) {
  const scale = current.span / Math.max(1, start.span),
    rotation = angleDelta(current.angle, start.angle);
  const dx = current.x - start.x,
    dy = current.y - start.y;
  if (Math.abs(Math.log(scale)) > 0.04 || Math.abs(rotation) > 0.06)
    return "transform";
  if (Math.abs(dy) > 10 && Math.abs(dy) > Math.abs(dx) * 1.7) return "tilt";
  return Math.hypot(dx, dy) > 10 ? "transform" : null;
}

export function releaseVelocity(samples, now) {
  const last = samples.at(-1);
  if (!last || now - last.t > 80) return [0, 0];
  const first = samples.find((p) => last.t - p.t <= 100);
  if (!first || last.t - first.t < 12) return [0, 0];
  let x = (last.x - first.x) / (last.t - first.t),
    y = (last.y - first.y) / (last.t - first.t);
  const scale = Math.min(1, 2.5 / Math.hypot(x, y));
  return [x * scale, y * scale];
}

// Integrate exponential decay exactly so a flick travels the same distance at
// 60/120 Hz. Only a stalled frame's elapsed time is capped by the caller.
export function inertiaStep(vx, vy, dt) {
  const decay = Math.exp(-dt / 240),
    travel = 240 * (1 - decay);
  return { dx: vx * travel, dy: vy * travel, vx: vx * decay, vy: vy * decay };
}
