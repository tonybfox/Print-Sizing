// Bottom-sheet editor for one photo: drag to choose the crop, pinch or use
// the slider to zoom, rotate, and set copies.

import { computeCrop, clamp, FULL } from './crop.js';
import { drawPhoto, sizeCanvas } from './render.js';
import { rotatePhoto } from './images.js';

const $ = (id) => document.getElementById(id);
const MAX_ZOOM = 6;

let cur = null; // { photo, getAspect, onChange, onRemove, onClose, allowCopies, noCropHint }
let view = { w: 1, h: 1 };
const pointers = new Map();

export const isEditorOpen = () => !!cur;

export function initEditor() {
  const dlg = $('dlgEdit');
  const canvas = $('cropCanvas');
  const zoom = $('cropZoom');

  dlg.addEventListener('close', () => {
    const done = cur;
    cur = null;
    pointers.clear();
    done?.onClose?.();
  });
  dlg.addEventListener('click', (e) => {
    if (e.target === dlg) dlg.close();
  });

  canvas.addEventListener('pointerdown', (e) => {
    if (!cur || !cur.getAspect()) return;
    canvas.setPointerCapture(e.pointerId);
    pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
  });
  const lift = (e) => pointers.delete(e.pointerId);
  canvas.addEventListener('pointerup', lift);
  canvas.addEventListener('pointercancel', lift);
  canvas.addEventListener('pointermove', (e) => {
    const prev = pointers.get(e.pointerId);
    if (!prev || !cur) return;
    const next = { x: e.clientX, y: e.clientY };
    if (pointers.size === 1) {
      pointers.set(e.pointerId, next);
      pan(next.x - prev.x, next.y - prev.y);
    } else {
      const [a, b] = [...pointers.values()];
      const d0 = Math.hypot(a.x - b.x, a.y - b.y);
      const m0 = { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
      pointers.set(e.pointerId, next);
      const [a2, b2] = [...pointers.values()];
      const d1 = Math.hypot(a2.x - b2.x, a2.y - b2.y);
      if (d0 > 0) cur.photo.zoom = clamp(cur.photo.zoom * (d1 / d0), 1, MAX_ZOOM);
      pan((a2.x + b2.x) / 2 - m0.x, (a2.y + b2.y) / 2 - m0.y);
    }
  });

  zoom.addEventListener('input', () => {
    if (!cur) return;
    cur.photo.zoom = clamp(Number(zoom.value), 1, MAX_ZOOM);
    changed();
  });

  $('rotL').addEventListener('click', () => rotate(-90));
  $('rotR').addEventListener('click', () => rotate(90));
  $('btnResetCrop').addEventListener('click', () => {
    if (!cur) return;
    Object.assign(cur.photo, { cx: 0.5, cy: 0.5, zoom: 1 });
    changed();
  });
  $('btnRemove').addEventListener('click', () => {
    const c = cur;
    dlg.close();
    c?.onRemove?.();
  });

  const st = $('copiesStepper');
  const input = st.querySelector('input');
  const setCopies = (v) => {
    if (!cur) return;
    cur.photo.copies = clamp(Math.round(v) || 1, 1, 200);
    input.value = cur.photo.copies;
    cur.onChange();
  };
  st.addEventListener('click', (e) => {
    const b = e.target.closest('button[data-step]');
    if (b && cur) setCopies(cur.photo.copies + Number(b.dataset.step));
  });
  input.addEventListener('change', () => setCopies(Number(input.value)));

  window.addEventListener('resize', () => cur && draw());
}

export function openEditor(opts) {
  cur = opts;
  pointers.clear();
  $('editTitle').textContent = opts.title || 'Photo';
  $('copiesRow').hidden = !opts.allowCopies;
  $('btnRemove').hidden = !opts.onRemove;
  $('copiesStepper').querySelector('input').value = opts.photo.copies;
  const dlg = $('dlgEdit');
  if (!dlg.open) dlg.showModal();
  requestAnimationFrame(draw);
}

/** Redraw after the layout changed underneath (e.g. new slot shape). */
export function redrawEditor() {
  if (cur) draw();
}

function rotate(delta) {
  if (!cur) return;
  rotatePhoto(cur.photo, delta);
  changed();
}

function pan(dx, dy) {
  const p = cur.photo;
  p.cx += dx / view.w;
  p.cy += dy / view.h;
  changed();
}

function changed() {
  const aspect = cur.getAspect();
  if (aspect) {
    // Keep the centre where the crop can actually reach, so dragging back responds at once.
    const p = cur.photo;
    const c = computeCrop(p.aspect, aspect, p);
    p.cx = clamp(p.cx, c.w / 2, 1 - c.w / 2);
    p.cy = clamp(p.cy, c.h / 2, 1 - c.h / 2);
  }
  cur.onChange();
  draw();
}

function draw() {
  if (!cur) return;
  const p = cur.photo;
  const wrap = $('cropWrap');
  const canvas = $('cropCanvas');
  const maxW = Math.max(50, wrap.clientWidth - 24);
  const maxH = Math.max(50, wrap.clientHeight - 24);
  let w = maxW;
  let h = w / p.aspect;
  if (h > maxH) {
    h = maxH;
    w = h * p.aspect;
  }
  const ctx = sizeCanvas(canvas, w, h);
  const dpr = canvas.width / w;
  ctx.scale(dpr, dpr);
  drawPhoto(ctx, p.preview, p.pw, p.ph, p.rot, FULL, 0, 0, 0, w, h);
  view = { w, h };

  const aspect = cur.getAspect();
  $('zoomRow').hidden = !aspect;
  $('btnResetCrop').hidden = !aspect;
  $('cropZoom').value = p.zoom;
  $('cropHint').textContent = aspect
    ? 'Drag to choose what gets printed. Pinch or use the slider to zoom in.'
    : cur.noCropHint || 'The whole photo is printed.';
  canvas.style.cursor = aspect ? 'move' : 'default';
  if (!aspect) return;

  const c = computeCrop(p.aspect, aspect, p);
  const r = { x: c.x * w, y: c.y * h, w: c.w * w, h: c.h * h };
  ctx.fillStyle = 'rgba(0,0,0,0.55)';
  ctx.beginPath();
  ctx.rect(0, 0, w, h);
  ctx.rect(r.x, r.y, r.w, r.h);
  ctx.fill('evenodd');
  ctx.strokeStyle = 'rgba(255,255,255,0.4)';
  ctx.lineWidth = 1;
  ctx.beginPath();
  for (const f of [1 / 3, 2 / 3]) {
    ctx.moveTo(r.x + r.w * f, r.y);
    ctx.lineTo(r.x + r.w * f, r.y + r.h);
    ctx.moveTo(r.x, r.y + r.h * f);
    ctx.lineTo(r.x + r.w, r.y + r.h * f);
  }
  ctx.stroke();
  ctx.strokeStyle = '#fff';
  ctx.lineWidth = 2;
  ctx.strokeRect(r.x + 1, r.y + 1, r.w - 2, r.h - 2);
}
