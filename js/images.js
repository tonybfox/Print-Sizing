// Loading photos. We keep the original File (decoded again only when making
// the PDF) plus a small JPEG preview, which keeps memory low on the phone.

import { orientedAspect } from './crop.js';

let seq = 0;

export function loadImage(url) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.decoding = 'async';
    img.onload = () => (img.decode ? img.decode().catch(() => {}) : Promise.resolve()).then(() => resolve(img));
    img.onerror = () => reject(new Error('This image type could not be opened'));
    img.src = url;
  });
}

export function canvasToBlob(canvas, type = 'image/jpeg', quality = 0.9) {
  return new Promise((resolve, reject) =>
    canvas.toBlob((b) => (b ? resolve(b) : reject(new Error('Out of memory while preparing the image'))), type, quality),
  );
}

export function freeCanvas(c) {
  c.width = 0;
  c.height = 0;
}

export async function loadPhoto(file, maxPreview = 1024) {
  const src = URL.createObjectURL(file);
  let blob;
  let width;
  let height;
  let pw;
  let ph;
  try {
    const img = await loadImage(src);
    width = img.naturalWidth;
    height = img.naturalHeight;
    if (!width || !height) throw new Error('The image is empty');
    const scale = Math.min(1, maxPreview / Math.max(width, height));
    pw = Math.max(1, Math.round(width * scale));
    ph = Math.max(1, Math.round(height * scale));
    const c = document.createElement('canvas');
    c.width = pw;
    c.height = ph;
    const ctx = c.getContext('2d');
    ctx.fillStyle = '#fff';
    ctx.fillRect(0, 0, pw, ph);
    ctx.imageSmoothingQuality = 'high';
    ctx.drawImage(img, 0, 0, pw, ph);
    blob = await canvasToBlob(c, 'image/jpeg', 0.85);
    freeCanvas(c);
    img.src = '';
  } finally {
    URL.revokeObjectURL(src);
  }
  const url = URL.createObjectURL(blob);
  const preview = await loadImage(url);
  return {
    id: ++seq,
    name: file.name || 'photo',
    file,
    width,
    height,
    url,
    preview,
    pw,
    ph,
    copies: 1,
    rot: 0,
    aspect: width / height,
    cx: 0.5,
    cy: 0.5,
    zoom: 1,
  };
}

export function rotatePhoto(photo, delta) {
  photo.rot = (((photo.rot + delta) % 360) + 360) % 360;
  photo.aspect = orientedAspect(photo.width, photo.height, photo.rot);
  photo.cx = 0.5;
  photo.cy = 0.5;
  photo.zoom = 1;
}

export function releasePhoto(photo) {
  if (photo?.url) URL.revokeObjectURL(photo.url);
  if (photo?.preview) photo.preview.src = '';
}

/** Full-resolution decode for printing. Falls back to the preview. */
export async function decodeFull(photo) {
  const url = URL.createObjectURL(photo.file);
  try {
    const img = await loadImage(url);
    return { img, w: img.naturalWidth, h: img.naturalHeight, done: () => ((img.src = ''), URL.revokeObjectURL(url)) };
  } catch {
    URL.revokeObjectURL(url);
    return { img: photo.preview, w: photo.pw, h: photo.ph, done: () => {} };
  }
}
