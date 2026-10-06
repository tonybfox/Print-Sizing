// Crop maths. All crops are normalised rectangles {x, y, w, h} in 0..1 of the
// image *after* the user's own rotation ("oriented" space), so the same crop
// works for the small preview and the full-resolution original.

export const FULL = Object.freeze({ x: 0, y: 0, w: 1, h: 1 });

export const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));

/** Aspect (w / h) of an image once rotated by `rot` degrees. */
export function orientedAspect(width, height, rot) {
  return rot % 180 ? height / width : width / height;
}

/**
 * The largest centred window of `targetAspect` inside an image of
 * `imgAspect`, shrunk by `zoom` and moved to centre (cx, cy) where possible.
 */
export function computeCrop(imgAspect, targetAspect, { cx = 0.5, cy = 0.5, zoom = 1 } = {}) {
  let w = 1;
  let h = 1;
  if (imgAspect > targetAspect) w = targetAspect / imgAspect;
  else h = imgAspect / targetAspect;
  const z = Math.max(1, zoom || 1);
  w /= z;
  h /= z;
  return { x: clamp(cx - w / 2, 0, 1 - w), y: clamp(cy - h / 2, 0, 1 - h), w, h };
}

/**
 * Map a crop in oriented space back onto the original (unrotated) image.
 * `rot` is the clockwise rotation the user applied to the original.
 */
export function toSourceRect(c, rot) {
  switch (((rot % 360) + 360) % 360) {
    case 90:
      return { x: c.y, y: 1 - c.x - c.w, w: c.h, h: c.w };
    case 180:
      return { x: 1 - c.x - c.w, y: 1 - c.y - c.h, w: c.w, h: c.h };
    case 270:
      return { x: 1 - c.y - c.h, y: c.x, w: c.h, h: c.w };
    default:
      return { x: c.x, y: c.y, w: c.w, h: c.h };
  }
}
