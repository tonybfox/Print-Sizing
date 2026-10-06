// Turns a layout into a PDF: renders each photo crop at print resolution,
// then writes pages with the guides.

import { PdfBuilder } from './pdf.js';
import { toSourceRect } from './crop.js';
import { decodeFull, canvasToBlob, freeCanvas } from './images.js';
import { drawPhoto } from './render.js';

const MAX_PIXELS = 16e6; // iOS canvas limit is ~16.7 MP

function outputSize(item, srcW, srcH, dpi) {
  const s = toSourceRect(item.crop, item.photo.rot);
  const R = (item.photo.rot + item.rot) % 360;
  let pxW = s.w * srcW;
  let pxH = s.h * srcH;
  if (R % 180) [pxW, pxH] = [pxH, pxW];
  const tW = (item.w / 25.4) * dpi;
  const tH = (item.h / 25.4) * dpi;
  const scale = Math.min(1, pxW / tW, pxH / tH); // never upscale past the original
  let w = tW * scale;
  let h = tH * scale;
  if (w * h > MAX_PIXELS) {
    const f = Math.sqrt(MAX_PIXELS / (w * h));
    w *= f;
    h *= f;
  }
  return { w: Math.max(1, Math.round(w)), h: Math.max(1, Math.round(h)) };
}

const cropKey = (it) =>
  [it.photo.id, it.photo.rot, it.rot, it.crop.x, it.crop.y, it.crop.w, it.crop.h, it.w, it.h].map((v) => (typeof v === 'number' ? v.toFixed(4) : v)).join('|');

function drawPrimsPdf(pg, prims) {
  for (const p of prims) {
    if (p.t === 'line') pg.line(p.x1, p.y1, p.x2, p.y2, p);
    else if (p.t === 'rect') pg.rect(p.x, p.y, p.w, p.h, p);
    else if (p.t === 'text') pg.text(p.x, p.y, p.text, p);
  }
}

/**
 * pages: from layout. opts: { dpi, correction, title, onProgress(done, total) }
 * Returns a Blob (application/pdf).
 */
export async function makePdf(pages, { dpi = 300, correction = 1, title = 'Print Sizing', onProgress = () => {} } = {}) {
  const doc = new PdfBuilder();

  // One render job per distinct crop; grouped so each original is decoded once.
  const jobs = new Map();
  for (const page of pages)
    for (const it of page.items) {
      const key = cropKey(it);
      if (!jobs.has(key)) jobs.set(key, { item: it, id: null });
    }
  const byPhoto = new Map();
  for (const job of jobs.values()) {
    const p = job.item.photo;
    if (!byPhoto.has(p)) byPhoto.set(p, []);
    byPhoto.get(p).push(job);
  }

  let done = 0;
  onProgress(0, jobs.size);
  for (const [photo, list] of byPhoto) {
    const full = await decodeFull(photo);
    try {
      for (const job of list) {
        const it = job.item;
        const size = outputSize(it, full.w, full.h, dpi);
        const c = document.createElement('canvas');
        c.width = size.w;
        c.height = size.h;
        const ctx = c.getContext('2d');
        ctx.fillStyle = '#fff';
        ctx.fillRect(0, 0, size.w, size.h);
        ctx.imageSmoothingQuality = 'high';
        drawPhoto(ctx, full.img, full.w, full.h, photo.rot, it.crop, it.rot, 0, 0, size.w, size.h);
        const blob = await canvasToBlob(c, 'image/jpeg', 0.92);
        freeCanvas(c);
        job.id = doc.addJpeg(new Uint8Array(await blob.arrayBuffer()), size.w, size.h);
        onProgress(++done, jobs.size);
      }
    } finally {
      full.done();
    }
  }

  for (const page of pages) {
    const pg = doc.page(page.w, page.h);
    pg.scaleAboutCentre(correction);
    drawPrimsPdf(pg, page.under);
    for (const it of page.items) pg.image(jobs.get(cropKey(it)).id, it.x, it.y, it.w, it.h);
    drawPrimsPdf(pg, page.over);
    pg.end();
  }
  return new Blob(doc.build({ title }), { type: 'application/pdf' });
}

/** Ruler lengths that fit on a page of width w (mm). */
export function testRulers(w) {
  return {
    mm: Math.min(100, Math.floor((w - 24) / 10) * 10),
    inch: Math.min(4, Math.floor((w - 24) / 25.4)),
  };
}

/** A page with rulers so the printed size can be checked. */
export function makeTestPage(paper, correction = 1) {
  const W = Math.min(paper.w, paper.h);
  const H = Math.max(paper.w, paper.h);
  const doc = new PdfBuilder();
  const pg = doc.page(W, H);
  pg.scaleAboutCentre(correction);
  const x0 = 12;
  const small = W < 160;
  let y = 16;
  pg.text(x0, y, 'Print Sizing - printer size check', { size: small ? 11 : 14 });
  y += 7;
  pg.text(x0, y, `Correction applied: ${(correction * 100).toFixed(1)}%`, { size: 8, gray: 0.35 });
  y += 5;
  pg.text(x0, y, 'Measure the long line with a ruler and type the length into the app.', { size: small ? 6.5 : 8, gray: 0.35 });

  const { mm, inch } = testRulers(W);
  // Metric ruler.
  y += 18;
  pg.line(x0, y, x0 + mm, y, { lw: 0.35 });
  for (let i = 0; i <= mm; i++) {
    const len = i % 10 === 0 ? 5 : i % 5 === 0 ? 3.5 : 2;
    pg.line(x0 + i, y, x0 + i, y - len, { lw: i % 10 === 0 ? 0.25 : 0.12 });
    if (i % 10 === 0) pg.text(x0 + i - 0.9, y - 6.5, String(i / 10), { size: 6 });
  }
  pg.text(x0, y + 6, `This line should be exactly ${mm} mm (${mm / 10} cm)`, { size: 8 });

  // Imperial ruler.
  y += 24;
  const L = inch * 25.4;
  pg.line(x0, y, x0 + L, y, { lw: 0.35 });
  for (let i = 0; i <= inch * 8; i++) {
    const x = x0 + (i * 25.4) / 8;
    const len = i % 8 === 0 ? 5 : i % 4 === 0 ? 3.5 : i % 2 === 0 ? 2.5 : 1.6;
    pg.line(x, y, x, y - len, { lw: i % 8 === 0 ? 0.25 : 0.12 });
    if (i % 8 === 0) pg.text(x - 0.9, y - 6.5, String(i / 8), { size: 6 });
  }
  pg.text(x0, y + 6, `This line should be exactly ${inch} inches`, { size: 8 });

  // A square for eyeballing.
  y += 16;
  const sq = Math.min(50, W - 2 * x0);
  pg.rect(x0, y, sq, sq, { lw: 0.3 });
  pg.text(x0 + 2, y + 6, `${sq} x ${sq} mm square`, { size: 7, gray: 0.35 });
  pg.end();
  return { blob: new Blob(doc.build({ title: 'Printer size check' }), { type: 'application/pdf' }), rulers: { mm, inch } };
}
