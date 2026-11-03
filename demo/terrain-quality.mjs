// Screen resolution, not mesh complexity, determines texture detail.
// Page zoom can raise the reported density above the display's nominal scale;
// bound the drawing buffer by pixels instead of imposing a density ceiling.
export function renderDensity(width, height, density = 1) {
  return Math.min(
    Math.max(1, density),
    Math.sqrt(8_000_000 / Math.max(1, width * height)),
  );
}

export function textureResolution(zoom, density = 1) {
  const pixels = zoom * density * 1.25;
  return [64, 128, 256, 512].find((size) => size >= pixels) || 512;
}

// Smooth, bounded pitch around the current tilt; starting/resuming never jumps.
export function flyoverPitch(tilt, seconds) {
  const amplitude = Math.min(8, tilt, 65 - tilt);
  return tilt + amplitude * Math.sin(seconds * 0.12);
}
