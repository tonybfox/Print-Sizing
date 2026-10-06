// Pure layout maths: turns settings + photos into a list of pages.
//
// A page is { w, h, items, placeholders, under, over } in millimetres:
//   items        photos to draw: { photo, x, y, w, h, rot, crop, cut }
//                rot is an extra 0/90° turn to fit the slot; crop is in the
//                photo's oriented space (see crop.js); cut is the outline to
//                cut along.
//   placeholders empty slots shown in the preview before photos are added.
//   under/over   guide marks drawn below / above the photos:
//                { t: 'line', x1, y1, x2, y2, lw, gray, dash? }
//                { t: 'rect', x, y, w, h, lw, gray, fill? }
//                { t: 'text', x, y, size (pt), text, gray }

import { computeCrop, FULL } from './crop.js';

const EPS = 1e-6;

export function orientPaper(paper, orientation) {
  const s = Math.min(paper.w, paper.h);
  const l = Math.max(paper.w, paper.h);
  return orientation === 'landscape' ? { w: l, h: s } : { w: s, h: l };
}

/** How many pieces of `piece` fit along `len` with `gap` between them. */
export function fitCount(len, piece, gap) {
  if (!(piece > 0) || piece > len + EPS) return 0;
  return Math.floor((len + gap + EPS) / (piece + gap));
}

/** Fraction of a cell a photo of `aspect` covers when fitted inside it. */
export function fitFraction(cellW, cellH, aspect) {
  const ca = cellW / cellH;
  return Math.min(ca / aspect, aspect / ca);
}

/** Pick columns × rows for `n` photos that shows them as large as possible. */
export function bestGrid(cw, ch, n, gap, aspects, autoRotate) {
  let best = null;
  for (let cols = 1; cols <= n; cols++) {
    const rows = Math.ceil(n / cols);
    const cellW = (cw - (cols - 1) * gap) / cols;
    const cellH = (ch - (rows - 1) * gap) / rows;
    if (cellW <= EPS || cellH <= EPS) continue;
    let score = 0;
    let turned = 0;
    for (const a of aspects) {
      const f0 = fitFraction(cellW, cellH, a);
      const f1 = autoRotate ? fitFraction(cellW, cellH, 1 / a) : 0;
      if (f1 > f0 * (1 + 1e-9)) turned++;
      score += Math.max(f0, f1) * cellW * cellH;
    }
    score /= aspects.length;
    const empty = cols * rows - n;
    const better = !best || score > best.score * (1 + 1e-9);
    const tie = best && score >= best.score * (1 - 1e-9);
    if (better || (tie && (empty < best.empty || (empty === best.empty && turned < best.turned))))
      best = { cols, rows, cellW, cellH, score, empty, turned };
  }
  return best;
}

/** Slot rectangles for a grid; a short last row is centred. */
export function gridSlots(g, n, gap, ox, oy, cw) {
  const slots = [];
  for (let i = 0; i < n; i++) {
    const r = Math.floor(i / g.cols);
    const c = i % g.cols;
    const inRow = Math.min(g.cols, n - r * g.cols);
    const rowW = inRow * g.cellW + (inRow - 1) * gap;
    const x0 = ox + (cw - rowW) / 2;
    slots.push({ x: x0 + c * (g.cellW + gap), y: oy + r * (g.cellH + gap), w: g.cellW, h: g.cellH });
  }
  return slots;
}

/**
 * Fit as many a × b pieces as possible into cw × ch. Tries both piece
 * orientations, plus a main block in one orientation with the leftover band
 * filled by turned pieces (every arrangement can still be cut with straight
 * cuts). Returns slots relative to the content area, centred.
 */
export function packPieces(cw, ch, a, b, gap) {
  if (!(a > 0) || !(b > 0)) return { count: 0, slots: [] };
  const square = Math.abs(a - b) < EPS;
  const orients = square ? [[a, b]] : [[a, b], [b, a]];
  let best = null;
  const blocksUsed = (p) => p.blocks.filter((bl) => bl.n).length;
  const consider = (p) => {
    if (!best || p.count > best.count || (p.count === best.count && blocksUsed(p) < blocksUsed(best))) best = p;
  };
  for (const [pw, ph] of orients) {
    const [qw, qh] = [ph, pw];
    // Rows of pw × ph across the top, leftover band below with turned pieces.
    const c1 = fitCount(cw, pw, gap);
    const r1max = fitCount(ch, ph, gap);
    for (let r1 = c1 ? r1max : 0; r1 >= 0; r1--) {
      const used = r1 * (ph + gap);
      const c2 = square ? 0 : fitCount(cw, qw, gap);
      const r2 = c2 ? fitCount(ch - used, qh, gap) : 0;
      consider({
        count: c1 * r1 + c2 * r2,
        dir: 'rows',
        blocks: [
          { w: pw, h: ph, cols: c1, rows: r1, n: c1 * r1 },
          { w: qw, h: qh, cols: c2, rows: r2, n: c2 * r2 },
        ],
      });
    }
    // Columns of pw × ph down the left, leftover band on the right.
    const r1b = fitCount(ch, ph, gap);
    const c1max = fitCount(cw, pw, gap);
    for (let c1 = r1b ? c1max : 0; c1 >= 0; c1--) {
      const used = c1 * (pw + gap);
      const r2 = square ? 0 : fitCount(ch, qh, gap);
      const c2 = r2 ? fitCount(cw - used, qw, gap) : 0;
      consider({
        count: r1b * c1 + c2 * r2,
        dir: 'cols',
        blocks: [
          { w: pw, h: ph, cols: c1, rows: r1b, n: c1 * r1b },
          { w: qw, h: qh, cols: c2, rows: r2, n: c2 * r2 },
        ],
      });
    }
  }
  return { count: best.count, slots: best.count ? packedSlots(best, cw, ch, gap) : [] };
}

function packedSlots(p, cw, ch, gap) {
  const blocks = p.blocks
    .filter((b) => b.n)
    .map((b) => ({ ...b, W: b.cols * b.w + (b.cols - 1) * gap, H: b.rows * b.h + (b.rows - 1) * gap }));
  const slots = [];
  if (p.dir === 'rows') {
    const total = blocks.reduce((s, b) => s + b.H, 0) + gap * (blocks.length - 1);
    let y = (ch - total) / 2;
    for (const b of blocks) {
      const x0 = (cw - b.W) / 2;
      for (let r = 0; r < b.rows; r++)
        for (let c = 0; c < b.cols; c++) slots.push({ x: x0 + c * (b.w + gap), y: y + r * (b.h + gap), w: b.w, h: b.h });
      y += b.H + gap;
    }
  } else {
    const total = blocks.reduce((s, b) => s + b.W, 0) + gap * (blocks.length - 1);
    let x = (cw - total) / 2;
    for (const b of blocks) {
      const y0 = (ch - b.H) / 2;
      for (let r = 0; r < b.rows; r++)
        for (let c = 0; c < b.cols; c++) slots.push({ x: x + c * (b.w + gap), y: y0 + r * (b.h + gap), w: b.w, h: b.h });
      x += b.W + gap;
    }
  }
  return slots;
}

/**
 * Sheet of photos: either `perPage` photos as large as possible, or pieces of
 * an exact size (pieceW × pieceH) packed as tightly as possible.
 *
 * o: { paper, orientation, margin, gap, sizing: 'count'|'size', perPage,
 *      pieceW, pieceH, fit: 'fit'|'fill', autoRotate, matchOrientation,
 *      guides: 'none'|'outline'|'marks', fillPage, photos }
 * photos: [{ aspect (oriented), copies, cx, cy, zoom }]
 */
export function buildSheet(o) {
  const photos = o.photos || [];
  const exact = o.sizing === 'size';
  const perPage = Math.max(1, Math.floor(o.perPage) || 1);
  const aspects = photos.length ? photos.map((p) => p.aspect) : [1.5];
  const orients = o.orientation === 'auto' ? ['portrait', 'landscape'] : [o.orientation];

  let best = null;
  let content = null;
  for (const orient of orients) {
    const page = orientPaper(o.paper, orient);
    const cw = page.w - 2 * o.margin;
    const ch = page.h - 2 * o.margin;
    if (cw <= EPS || ch <= EPS) continue;
    content = content || { cw, ch };
    let cand;
    if (exact) {
      const pk = packPieces(cw, ch, o.pieceW, o.pieceH, o.gap);
      if (!pk.count) continue;
      const slots = pk.slots.map((s) => ({ ...s, x: s.x + o.margin, y: s.y + o.margin }));
      cand = { orient, page, score: pk.count, slots };
    } else {
      const g = bestGrid(cw, ch, perPage, o.gap, aspects, o.autoRotate);
      if (!g) continue;
      cand = { orient, page, score: g.score, turned: g.turned, grid: g, slots: gridSlots(g, perPage, o.gap, o.margin, o.margin, cw) };
    }
    // On a tie prefer the page orientation that needs fewer photos turned.
    const tie = best && cand.score >= best.score * (1 - 1e-9) && cand.score <= best.score * (1 + 1e-9);
    if (!best || (!tie && cand.score > best.score) || (tie && (cand.turned || 0) < (best.turned || 0))) best = cand;
  }

  if (!best) {
    if (!content) return { pages: [], error: { code: 'margins' } };
    return { pages: [], error: { code: 'too-big', ...content } };
  }

  const n = best.slots.length;
  const entries = [];
  for (const p of photos) for (let i = 0; i < Math.max(1, Math.floor(p.copies) || 1); i++) entries.push(p);
  if (o.fillPage && entries.length % n) {
    const base = entries.slice();
    for (let i = 0; entries.length % n; i++) entries.push(base[i % base.length]);
  }

  const pages = [];
  if (!entries.length) pages.push(sheetPage(best.page, [], best.slots, o));
  for (let i = 0; i < entries.length; i += n) {
    const items = entries.slice(i, i + n).map((p, k) => placeInSlot(p, best.slots[k], o, exact));
    pages.push(sheetPage(best.page, items, [], o));
  }

  const s0 = best.slots[0];
  return {
    pages,
    info: {
      orientation: best.orient,
      page: best.page,
      perPage: n,
      cols: best.grid?.cols,
      rows: best.grid?.rows,
      slotW: s0.w,
      slotH: s0.h,
      photos: entries.length,
    },
  };
}

function placeInSlot(photo, slot, o, exact) {
  let rot = 0;
  if (exact) {
    let pw = o.pieceW;
    let ph = o.pieceH;
    if (o.matchOrientation && Math.abs(pw - ph) > EPS && Math.abs(photo.aspect - 1) > 0.01) {
      const L = Math.max(pw, ph);
      const S = Math.min(pw, ph);
      [pw, ph] = photo.aspect > 1 ? [L, S] : [S, L];
    }
    // The packer may have laid this slot sideways; turn the photo with it.
    if (Math.abs(pw - slot.w) > EPS) rot = 90;
  } else if (o.autoRotate) {
    const f0 = fitFraction(slot.w, slot.h, photo.aspect);
    const f1 = fitFraction(slot.w, slot.h, 1 / photo.aspect);
    if (f1 > f0 * (1 + 1e-9)) rot = 90;
  }

  if (o.fit === 'fill') {
    const target = rot ? slot.h / slot.w : slot.w / slot.h;
    return { photo, rot, ...slot, crop: computeCrop(photo.aspect, target, photo), cut: slot };
  }
  const shown = rot ? 1 / photo.aspect : photo.aspect;
  const w = Math.min(slot.w, slot.h * shown);
  const h = w / shown;
  const r = { x: slot.x + (slot.w - w) / 2, y: slot.y + (slot.h - h) / 2, w, h };
  return { photo, rot, ...r, crop: FULL, cut: exact ? slot : r };
}

function sheetPage(page, items, placeholders, o) {
  const under = [];
  const over = [];
  if (o.guides === 'outline') {
    for (const it of items) over.push({ t: 'rect', ...it.cut, lw: 0.2, gray: 0.6 });
  } else if (o.guides === 'marks') {
    for (const it of items) under.push(...cornerMarks(it.cut, 1, 4, 0.25));
  }
  return { w: page.w, h: page.h, items, placeholders: placeholders.slice(), under, over };
}

/** Short crop marks pointing outwards from each corner of r. */
export function cornerMarks(r, off, len, gray, lw = 0.15) {
  const out = [];
  for (const [x, sx] of [
    [r.x, -1],
    [r.x + r.w, 1],
  ]) {
    for (const [y, sy] of [
      [r.y, -1],
      [r.y + r.h, 1],
    ]) {
      out.push({ t: 'line', x1: x + sx * off, y1: y, x2: x + sx * (off + len), y2: y, lw, gray });
      out.push({ t: 'line', x1: x, y1: y + sy * off, x2: x, y2: y + sy * (off + len), lw, gray });
    }
  }
  return out;
}

export const rowName = (r) => (r < 26 ? String.fromCharCode(65 + r) : `R${r + 1}`);

/**
 * One image tiled across several pages.
 *
 * o: { paper, orientation, margin, overlap, sizeBy: 'grid'|'width'|'height',
 *      cols, rows, width, height, fill, guides, photo }
 */
export function buildPoster(o) {
  const photo = o.photo;
  const a = photo ? photo.aspect : 4 / 3;
  const m = o.margin;
  const ov = Math.max(0, o.overlap || 0);
  const orients = o.orientation === 'auto' ? ['portrait', 'landscape'] : [o.orientation];
  const fill = o.sizeBy === 'grid' && o.fill;

  let best = null;
  for (const orient of orients) {
    const page = orientPaper(o.paper, orient);
    const tw = page.w - 2 * m;
    const th = page.h - 2 * m;
    if (tw - ov < 5 || th - ov < 5) continue;
    const sx = tw - ov;
    const sy = th - ov;
    let PW;
    let PH;
    if (o.sizeBy === 'grid') {
      const cols = Math.max(1, Math.floor(o.cols) || 1);
      const rows = Math.max(1, Math.floor(o.rows) || 1);
      const W = cols * tw - (cols - 1) * ov;
      const H = rows * th - (rows - 1) * ov;
      if (fill) [PW, PH] = [W, H];
      else {
        PW = Math.min(W, H * a);
        PH = PW / a;
      }
    } else if (o.sizeBy === 'width') {
      PW = o.width;
      PH = PW / a;
    } else {
      PH = o.height;
      PW = PH * a;
    }
    if (!(PW > 0 && PH > 0)) continue;
    const cols = Math.max(1, Math.ceil((PW - ov) / sx - 1e-6));
    const rows = Math.max(1, Math.ceil((PH - ov) / sy - 1e-6));
    const n = cols * rows;
    const cand = { orient, page, tw, th, sx, sy, PW, PH, cols, rows, n, util: (PW * PH) / (n * tw * th) };
    cand.shapeMatch = fitFraction(PW, PH, a); // how little a fill crop removes
    if (!best || posterBetter(cand, best, o.sizeBy, fill)) best = cand;
  }

  if (!best) return { pages: [], error: { code: 'margins' } };
  if (best.n > 150) return { pages: [], error: { code: 'too-many', n: best.n } };

  const { page, tw, th, sx, sy, PW, PH, cols, rows } = best;
  const base = photo && fill ? computeCrop(a, PW / PH, photo) : FULL;
  const pages = [];
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      const x0 = c * sx;
      const y0 = r * sy;
      const w = Math.min(x0 + tw, PW) - x0;
      const h = Math.min(y0 + th, PH) - y0;
      const cut = { x: m, y: m, w, h };
      const pg = { w: page.w, h: page.h, items: [], placeholders: [], under: [], over: [], label: `${rowName(r)}${c + 1}` };
      if (photo) {
        const crop = { x: base.x + (base.w * x0) / PW, y: base.y + (base.h * y0) / PH, w: (base.w * w) / PW, h: (base.h * h) / PH };
        pg.items.push({ photo, rot: 0, ...cut, crop, cut });
      } else pg.placeholders.push(cut);
      if (o.guides) posterGuides(pg, { m, w, h, r, c, rows, cols, sx, sy, ov });
      pages.push(pg);
    }
  }
  return {
    pages,
    info: { orientation: best.orient, page, posterW: PW, posterH: PH, cols, rows, tw, th, sx, sy, overlap: ov, base },
  };
}

function posterBetter(a, b, sizeBy, fill) {
  const close = (x, y) => Math.abs(x - y) <= Math.max(Math.abs(x), Math.abs(y)) * 1e-6;
  if (sizeBy === 'grid') {
    const areaA = a.PW * a.PH;
    const areaB = b.PW * b.PH;
    if (!close(areaA, areaB)) return areaA > areaB;
    if (fill && !close(a.shapeMatch, b.shapeMatch)) return a.shapeMatch > b.shapeMatch;
    return a.n < b.n;
  }
  if (a.n !== b.n) return a.n < b.n;
  return a.util > b.util * (1 + 1e-9);
}

function posterGuides(pg, { m, w, h, r, c, rows, cols, sx, sy, ov }) {
  if (m < 2) return;
  const off = 1;
  const len = Math.min(5, m - 1.5);
  // Trim marks at the corners of the printed area.
  pg.under.push(...cornerMarks({ x: m, y: m, w, h }, off, len, 0.2));

  // Where the next page's edge lines up when overlapping.
  if (ov > 0) {
    const dash = [1, 0.8];
    if (c < cols - 1) {
      const x = m + sx;
      pg.under.push({ t: 'line', x1: x, y1: m - off, x2: x, y2: m - off - len, lw: 0.2, gray: 0.35, dash });
      pg.under.push({ t: 'line', x1: x, y1: m + h + off, x2: x, y2: m + h + off + len, lw: 0.2, gray: 0.35, dash });
    }
    if (r < rows - 1) {
      const y = m + sy;
      pg.under.push({ t: 'line', x1: m - off, y1: y, x2: m - off - len, y2: y, lw: 0.2, gray: 0.35, dash });
      pg.under.push({ t: 'line', x1: m + w + off, y1: y, x2: m + w + off + len, y2: y, lw: 0.2, gray: 0.35, dash });
    }
  }

  // Page label and a tiny map of where this page goes.
  if (m >= 4) {
    const size = Math.min(8, (m * 0.55) / 0.3528);
    const cap = size * 0.3528 * 0.72;
    const baseline = pg.h - m / 2 + cap / 2;
    pg.over.push({
      t: 'text',
      x: m,
      y: baseline,
      size,
      gray: 0.35,
      text: `${pg.label}   row ${rowName(r)} of ${rowName(rows - 1)}, column ${c + 1} of ${cols}`,
    });
    const cell = Math.min(2.6, (m - 1.6) / rows, 40 / cols);
    if (cell >= 0.7) {
      const mapW = cols * cell;
      const x0 = pg.w - m - mapW;
      const y0 = pg.h - m / 2 - (rows * cell) / 2;
      for (let rr = 0; rr < rows; rr++)
        for (let cc = 0; cc < cols; cc++) {
          const here = rr === r && cc === c;
          pg.over.push({
            t: 'rect',
            x: x0 + cc * cell,
            y: y0 + rr * cell,
            w: cell,
            h: cell,
            lw: 0.12,
            gray: 0.55,
            fill: here ? 0.35 : undefined,
          });
        }
    }
  }
}
