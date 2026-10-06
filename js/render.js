// Drawing pages and posters onto a <canvas> for the on-screen preview, and
// the shared routine that draws a cropped/rotated photo.

import { toSourceRect, FULL } from './crop.js';

/**
 * Draw `crop` (oriented space) of an image whose original pixels are
 * srcW × srcH, turned by userRot + placeRot, into the dest rectangle.
 */
export function drawPhoto(ctx, src, srcW, srcH, userRot, crop, placeRot, dx, dy, dw, dh) {
  const s = toSourceRect(crop, userRot);
  const R = (userRot + placeRot) % 360;
  // Keep the source rectangle inside the image; Safari skips draws that spill over.
  const sx = Math.max(0, s.x * srcW);
  const sy = Math.max(0, s.y * srcH);
  const sw = Math.min(srcW - sx, s.w * srcW);
  const sh = Math.min(srcH - sy, s.h * srcH);
  if (sw <= 0 || sh <= 0) return;
  ctx.save();
  ctx.translate(dx + dw / 2, dy + dh / 2);
  if (R) ctx.rotate((R * Math.PI) / 180);
  const swap = R % 180 !== 0;
  const w = swap ? dh : dw;
  const h = swap ? dw : dh;
  ctx.drawImage(src, sx, sy, sw, sh, -w / 2, -h / 2, w, h);
  ctx.restore();
}

const grayCss = (g) => {
  const v = Math.round(g * 255);
  return `rgb(${v},${v},${v})`;
};

function drawPrims(ctx, prims, k) {
  for (const p of prims) {
    ctx.save();
    if (p.t === 'line') {
      ctx.strokeStyle = grayCss(p.gray);
      ctx.lineWidth = Math.max(0.75, p.lw * k);
      ctx.setLineDash(p.dash ? p.dash.map((d) => d * k) : []);
      ctx.beginPath();
      ctx.moveTo(p.x1 * k, p.y1 * k);
      ctx.lineTo(p.x2 * k, p.y2 * k);
      ctx.stroke();
    } else if (p.t === 'rect') {
      if (p.fill !== undefined) {
        ctx.fillStyle = grayCss(p.fill);
        ctx.fillRect(p.x * k, p.y * k, p.w * k, p.h * k);
      }
      ctx.strokeStyle = grayCss(p.gray);
      ctx.lineWidth = Math.max(0.75, p.lw * k);
      ctx.strokeRect(p.x * k, p.y * k, p.w * k, p.h * k);
    } else if (p.t === 'text') {
      ctx.fillStyle = grayCss(p.gray);
      ctx.font = `${p.size * 0.3528 * k}px Helvetica, Arial, sans-serif`;
      ctx.textBaseline = 'alphabetic';
      ctx.fillText(p.text, p.x * k, p.y * k);
    }
    ctx.restore();
  }
}

/** Size a canvas for crisp drawing at CSS size cssW × cssH. Returns the 2D context. */
export function sizeCanvas(canvas, cssW, cssH) {
  const dpr = Math.min(3, window.devicePixelRatio || 1);
  canvas.style.width = `${cssW}px`;
  canvas.style.height = `${cssH}px`;
  canvas.width = Math.max(1, Math.round(cssW * dpr));
  canvas.height = Math.max(1, Math.round(cssH * dpr));
  const ctx = canvas.getContext('2d');
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.imageSmoothingQuality = 'high';
  return ctx;
}

/** Draw one page; canvas already sized. k = device px per mm. */
export function drawPage(ctx, page, k) {
  ctx.fillStyle = '#fff';
  ctx.fillRect(0, 0, page.w * k, page.h * k);
  drawPrims(ctx, page.under, k);
  for (const r of page.placeholders) {
    ctx.save();
    ctx.fillStyle = '#eef1f6';
    ctx.fillRect(r.x * k, r.y * k, r.w * k, r.h * k);
    ctx.strokeStyle = '#b6bfcc';
    ctx.lineWidth = Math.max(1, 0.3 * k);
    ctx.setLineDash([2 * k, 1.5 * k]);
    ctx.strokeRect(r.x * k, r.y * k, r.w * k, r.h * k);
    ctx.restore();
  }
  for (const it of page.items) {
    const p = it.photo;
    drawPhoto(ctx, p.preview, p.pw, p.ph, p.rot, it.crop, it.rot, it.x * k, it.y * k, it.w * k, it.h * k);
  }
  drawPrims(ctx, page.over, k);
}

/** The whole poster as it will look assembled, with page boundaries. */
export function drawPoster(ctx, plan, photo, k) {
  const { posterW, posterH, cols, rows, sx, sy, tw, th, overlap, base } = plan.info;
  const gw = (cols - 1) * sx + tw;
  const gh = (rows - 1) * sy + th;
  // Paper that ends up unused beyond the image.
  ctx.fillStyle = '#ffffff';
  ctx.fillRect(0, 0, gw * k, gh * k);
  ctx.save();
  ctx.strokeStyle = 'rgba(0,0,0,0.06)';
  ctx.lineWidth = 1;
  for (let d = -gh * k; d < gw * k; d += 8) {
    ctx.beginPath();
    ctx.moveTo(d, gh * k);
    ctx.lineTo(d + gh * k, 0);
    ctx.stroke();
  }
  ctx.restore();

  if (photo) {
    drawPhoto(ctx, photo.preview, photo.pw, photo.ph, photo.rot, base || FULL, 0, 0, 0, posterW * k, posterH * k);
  } else {
    ctx.fillStyle = '#eef1f6';
    ctx.fillRect(0, 0, posterW * k, posterH * k);
  }

  ctx.save();
  if (overlap > 0) {
    ctx.fillStyle = 'rgba(255,255,255,0.35)';
    for (let c = 1; c < cols; c++) ctx.fillRect(c * sx * k, 0, overlap * k, gh * k);
    for (let r = 1; r < rows; r++) ctx.fillRect(0, r * sy * k, gw * k, overlap * k);
  }
  ctx.lineWidth = Math.max(1, 0.35 * k);
  const seam = (x1, y1, x2, y2) => {
    ctx.setLineDash([]);
    ctx.strokeStyle = 'rgba(0,0,0,0.55)';
    ctx.beginPath();
    ctx.moveTo(x1, y1);
    ctx.lineTo(x2, y2);
    ctx.stroke();
    ctx.setLineDash([4, 3]);
    ctx.strokeStyle = 'rgba(255,255,255,0.95)';
    ctx.stroke();
  };
  for (let c = 1; c < cols; c++) seam(c * sx * k, 0, c * sx * k, gh * k);
  for (let r = 1; r < rows; r++) seam(0, r * sy * k, gw * k, r * sy * k);
  ctx.setLineDash([]);
  ctx.strokeStyle = 'rgba(0,0,0,0.35)';
  ctx.strokeRect(0.5, 0.5, gw * k - 1, gh * k - 1);

  // Page labels.
  const fs = Math.max(10, Math.min(16, Math.min(sx, sy) * k * 0.12));
  ctx.font = `600 ${fs}px -apple-system, system-ui, sans-serif`;
  ctx.textBaseline = 'top';
  for (const [i, pg] of plan.pages.entries()) {
    const c = i % cols;
    const r = Math.floor(i / cols);
    const x = c * sx * k + 4;
    const y = r * sy * k + 4;
    const w = ctx.measureText(pg.label).width + 8;
    ctx.fillStyle = 'rgba(0,0,0,0.55)';
    ctx.beginPath();
    ctx.roundRect ? ctx.roundRect(x, y, w, fs + 6, 4) : ctx.rect(x, y, w, fs + 6);
    ctx.fill();
    ctx.fillStyle = '#fff';
    ctx.fillText(pg.label, x + 4, y + 3);
  }
  ctx.restore();
  return { gw, gh };
}

export { drawPrims };
