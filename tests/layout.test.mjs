import test from 'node:test';
import assert from 'node:assert/strict';
import { buildSheet, buildPoster, packPieces, bestGrid, fitCount } from '../js/layout.js';
import { computeCrop, toSourceRect } from '../js/crop.js';
import { PAPERS } from '../js/units.js';

const A4 = PAPERS.find((p) => p.id === 'a4');
const P4x6 = PAPERS.find((p) => p.id === '4x6');
const near = (a, b, eps = 1e-6) => assert.ok(Math.abs(a - b) <= eps, `${a} ≉ ${b}`);
const photo = (aspect, extra = {}) => ({ aspect, copies: 1, cx: 0.5, cy: 0.5, zoom: 1, ...extra });

const sheet = (extra) =>
  buildSheet({
    paper: A4, orientation: 'auto', margin: 5, gap: 3, sizing: 'count', perPage: 6,
    pieceW: 50.8, pieceH: 76.2, fit: 'fit', autoRotate: true, matchOrientation: true,
    guides: 'none', fillPage: false, photos: [], ...extra,
  });

test('fitCount handles exact fits and gaps', () => {
  assert.equal(fitCount(100, 50, 0), 2);
  assert.equal(fitCount(100, 50, 1), 1);
  assert.equal(fitCount(101, 50, 1), 2);
  assert.equal(fitCount(40, 50, 0), 0);
});

test('6 landscape photos on A4 go 2 across, 3 down, unrotated', () => {
  const r = sheet({ photos: [photo(1.5)], perPage: 6 });
  assert.equal(r.info.orientation, 'portrait');
  assert.equal(r.info.cols, 2);
  assert.equal(r.info.rows, 3);
  assert.equal(r.info.perPage, 6);
});

test('photos per page fills pages and keeps order', () => {
  const photos = [1, 2, 3, 4, 5, 6, 7].map((i) => photo(1.5, { id: i }));
  const r = sheet({ photos, perPage: 6 });
  assert.equal(r.pages.length, 2);
  assert.equal(r.pages[0].items.length, 6);
  assert.equal(r.pages[1].items.length, 1);
  assert.equal(r.pages[1].items[0].photo.id, 7);
});

test('copies and fill page', () => {
  const r = sheet({ photos: [photo(1.5, { copies: 2 })], perPage: 4 });
  assert.equal(r.pages[0].items.length, 2);
  const f = sheet({ photos: [photo(1.5)], perPage: 4, fillPage: true });
  assert.equal(f.pages.length, 1);
  assert.equal(f.pages[0].items.length, 4);
});

test('fit keeps photo aspect inside its slot and the page', () => {
  const r = sheet({ photos: [photo(1.5), photo(0.75)], perPage: 2 });
  for (const it of r.pages[0].items) {
    const shown = it.rot ? 1 / it.photo.aspect : it.photo.aspect;
    near(it.w / it.h, shown, 1e-9);
    assert.ok(it.x >= 5 - 1e-9 && it.y >= 5 - 1e-9);
    assert.ok(it.x + it.w <= 205 + 1e-9 && it.y + it.h <= 292 + 1e-9);
  }
});

test('fill crops to the slot shape', () => {
  const r = sheet({ photos: [photo(1.5)], perPage: 4, fit: 'fill' });
  const it = r.pages[0].items[0];
  const target = it.rot ? it.h / it.w : it.w / it.h;
  // crop aspect in pixels = (crop.w / crop.h) * imageAspect
  near((it.crop.w / it.crop.h) * 1.5, target, 1e-9);
});

test('exact 2x3 in on A4 packs pieces of exactly that size, inside the margins', () => {
  const r = sheet({ sizing: 'size', fit: 'fill', photos: [photo(2 / 3)], fillPage: true });
  const items = r.pages[0].items;
  assert.ok(items.length >= 10, `only ${items.length} per page`);
  for (const it of items) {
    const dims = [it.w, it.h].sort((a, b) => a - b);
    near(dims[0], 50.8);
    near(dims[1], 76.2);
    assert.ok(it.x >= 5 - 1e-9 && it.y >= 5 - 1e-9 && it.x + it.w <= 205 + 1e-9 && it.y + it.h <= 292 + 1e-9);
  }
  // No two pieces overlap (with the 3 mm gap respected).
  for (let i = 0; i < items.length; i++)
    for (let j = i + 1; j < items.length; j++) {
      const a = items[i], b = items[j];
      const sepX = Math.max(b.x - (a.x + a.w), a.x - (b.x + b.w));
      const sepY = Math.max(b.y - (a.y + a.h), a.y - (b.y + b.h));
      assert.ok(Math.max(sepX, sepY) >= 3 - 1e-6, `pieces ${i} and ${j} too close`);
    }
});

test('exact size: portrait photo in a turned slot is rotated, crop matches piece', () => {
  const r = sheet({ sizing: 'size', fit: 'fill', photos: [photo(0.75)], fillPage: true });
  for (const it of r.pages[0].items) {
    const turned = it.w > it.h; // slot lies landscape on the page
    assert.equal(it.rot, turned ? 90 : 0);
    near((it.crop.w / it.crop.h) * 0.75, 2 / 3, 1e-9); // printed piece is 2:3 portrait
  }
});

test('exact size with match orientation: landscape photo prints 3x2', () => {
  const r = sheet({ sizing: 'size', fit: 'fill', photos: [photo(1.5)] });
  const it = r.pages[0].items[0];
  near((it.crop.w / it.crop.h) * 1.5, 3 / 2, 1e-9);
  const off = sheet({ sizing: 'size', fit: 'fill', matchOrientation: false, photos: [photo(1.5)] });
  const it2 = off.pages[0].items[0];
  near((it2.crop.w / it2.crop.h) * 1.5, 2 / 3, 1e-9);
});

test('exact size too big for paper reports an error', () => {
  const r = sheet({ sizing: 'size', pieceW: 300, pieceH: 400, photos: [photo(1)] });
  assert.equal(r.error.code, 'too-big');
});

test('packPieces mixes orientations when it fits more', () => {
  const pure = Math.max(fitCount(200, 50.8, 3) * fitCount(287, 76.2, 3), fitCount(200, 76.2, 3) * fitCount(287, 50.8, 3));
  const mixed = packPieces(200, 287, 50.8, 76.2, 3);
  assert.ok(mixed.count >= pure);
  assert.equal(mixed.slots.length, mixed.count);
});

test('one photo filling a 6x4 sheet with no margin', () => {
  const r = buildSheet({
    paper: P4x6, orientation: 'auto', margin: 0, gap: 0, sizing: 'count', perPage: 1, fit: 'fill',
    autoRotate: true, guides: 'none', photos: [photo(1.5)],
  });
  assert.equal(r.info.orientation, 'landscape');
  const it = r.pages[0].items[0];
  near(it.w, 152.4);
  near(it.h, 101.6);
});

test('poster 2x2 A4 keeps the image aspect and uses 4 pages', () => {
  const r = buildPoster({
    paper: A4, orientation: 'auto', margin: 6, overlap: 0, sizeBy: 'grid', cols: 2, rows: 2,
    fill: false, guides: true, photo: photo(0.75),
  });
  assert.equal(r.pages.length, r.info.cols * r.info.rows);
  near(r.info.posterW / r.info.posterH, 0.75, 1e-9);
  // Tile crops together cover the whole image exactly once (no overlap).
  let area = 0;
  for (const p of r.pages) area += p.items[0].crop.w * p.items[0].crop.h;
  near(area, 1, 1e-9);
});

test('poster tiles by width with overlap', () => {
  const r = buildPoster({
    paper: A4, orientation: 'portrait', margin: 6, overlap: 10, sizeBy: 'width', width: 600,
    guides: true, photo: photo(1),
  });
  const { cols, rows, sx, posterW, posterH } = r.info;
  near(posterW, 600);
  near(posterH, 600);
  assert.equal(cols, Math.ceil((600 - 10) / sx));
  assert.equal(r.pages.length, cols * rows);
  // Adjacent tiles overlap by exactly 10 mm of poster.
  const a = r.pages[0].items[0].crop, b = r.pages[1].items[0].crop;
  near((a.x + a.w - b.x) * posterW, 10, 1e-6);
});

test('poster fill crops image to the grid shape', () => {
  const r = buildPoster({
    paper: A4, orientation: 'portrait', margin: 6, overlap: 0, sizeBy: 'grid', cols: 3, rows: 3,
    fill: true, guides: false, photo: photo(1.5),
  });
  near(r.info.posterW, 3 * 198);
  near(r.info.posterH, 3 * 285);
  near((r.info.base.w / r.info.base.h) * 1.5, r.info.posterW / r.info.posterH, 1e-9);
});

test('computeCrop centres and clamps', () => {
  const c = computeCrop(2, 1, { cx: 0.5, cy: 0.5, zoom: 1 });
  near(c.w, 0.5); near(c.h, 1); near(c.x, 0.25);
  const edge = computeCrop(2, 1, { cx: 0.99, cy: 0.5, zoom: 1 });
  near(edge.x, 0.5);
});

test('toSourceRect maps points consistently for each rotation', () => {
  // Rotate a point clockwise and compare to the rect mapping of a tiny crop.
  const rotPoint = (x, y, rot) => ({ 0: [x, y], 90: [1 - y, x], 180: [1 - x, 1 - y], 270: [y, 1 - x] })[rot];
  for (const rot of [0, 90, 180, 270]) {
    const src = [0.2, 0.3];
    const [u, v] = rotPoint(...src, rot);
    const tiny = 1e-4;
    const s = toSourceRect({ x: u - tiny / 2, y: v - tiny / 2, w: tiny, h: tiny }, rot);
    near(s.x + s.w / 2, src[0], 1e-9);
    near(s.y + s.h / 2, src[1], 1e-9);
  }
});
