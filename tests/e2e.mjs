// End-to-end check in Chromium emulating an iPhone: builds PDFs through the
// real UI and measures the printed result with poppler (pdfinfo/pdftoppm).
//   node tests/e2e.mjs [outDir]
import { createServer } from 'node:http';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join, extname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';
import assert from 'node:assert/strict';

let pw;
try {
  pw = await import('playwright');
} catch {
  pw = await import('/opt/node22/lib/node_modules/playwright/index.mjs');
}
const { chromium, devices } = pw;

const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const out = resolve(process.argv[2] || join(tmpdir(), 'print-sizing-e2e'));
await mkdir(out, { recursive: true });

// --- Fixtures: images with a different colour in each quadrant (TL red, TR green, BL blue, BR yellow).
const COLORS = { red: [220, 30, 30], green: [30, 170, 60], blue: [30, 60, 220], yellow: [240, 200, 20] };
function bmp(w, h) {
  // 24-bit BMP; browsers decode it and it needs no encoder.
  const row = Math.ceil((w * 3) / 4) * 4;
  const buf = Buffer.alloc(54 + row * h);
  buf.write('BM', 0);
  buf.writeUInt32LE(buf.length, 2);
  buf.writeUInt32LE(54, 10);
  buf.writeUInt32LE(40, 14);
  buf.writeInt32LE(w, 18);
  buf.writeInt32LE(-h, 22); // top-down
  buf.writeUInt16LE(1, 26);
  buf.writeUInt16LE(24, 28);
  buf.writeUInt32LE(row * h, 34);
  for (let y = 0; y < h; y++)
    for (let x = 0; x < w; x++) {
      const c = y < h / 2 ? (x < w / 2 ? COLORS.red : COLORS.green) : x < w / 2 ? COLORS.blue : COLORS.yellow;
      const o = 54 + y * row + x * 3;
      buf[o] = c[2];
      buf[o + 1] = c[1];
      buf[o + 2] = c[0];
    }
  return buf;
}
const fixtures = {
  landscape: { name: 'landscape.bmp', mimeType: 'image/bmp', buffer: bmp(1200, 800) },
  portrait: { name: 'portrait.bmp', mimeType: 'image/bmp', buffer: bmp(800, 1200) },
  poster: { name: 'poster.bmp', mimeType: 'image/bmp', buffer: bmp(1600, 1200) },
};

// --- Static server.
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.png': 'image/png', '.webmanifest': 'application/manifest+json' };
const server = createServer(async (req, res) => {
  const path = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  const file = join(root, path.endsWith('/') ? path + 'index.html' : path);
  try {
    const body = await readFile(file);
    res.writeHead(200, { 'content-type': TYPES[extname(file)] || 'application/octet-stream' });
    res.end(body);
  } catch {
    res.writeHead(404).end();
  }
});
await new Promise((r) => server.listen(0, r));
const url = `http://localhost:${server.address().port}/`;

// --- PDF helpers.
function pdfInfo(file) {
  const info = execFileSync('pdfinfo', [file], { encoding: 'utf8' });
  const pages = Number(info.match(/Pages:\s+(\d+)/)[1]);
  const [, w, h] = info.match(/Page size:\s+([\d.]+) x ([\d.]+) pts/);
  return { pages, wmm: (w / 72) * 25.4, hmm: (h / 72) * 25.4 };
}
function renderPage(file, page, dpi) {
  const prefix = join(out, `r-${Date.now()}`);
  execFileSync('pdftoppm', ['-r', String(dpi), '-f', String(page), '-l', String(page), '-singlefile', file, prefix]);
  return readPpm(`${prefix}.ppm`);
}
function readPpm(path) {
  const buf = readFileSync(path);
  let pos = 0;
  const tok = () => {
    while (/\s/.test(String.fromCharCode(buf[pos]))) pos++;
    let s = '';
    while (!/\s/.test(String.fromCharCode(buf[pos]))) s += String.fromCharCode(buf[pos++]);
    return s;
  };
  assert.equal(tok(), 'P6');
  const w = Number(tok());
  const h = Number(tok());
  tok();
  pos++;
  return { w, h, px: (x, y) => [...buf.subarray(pos + (y * w + x) * 3, pos + (y * w + x) * 3 + 3)] };
}
const near = (c, ref, tol = 60) => c.every((v, i) => Math.abs(v - ref[i]) <= tol);
const colorName = (c) => Object.keys(COLORS).find((k) => near(c, COLORS[k])) || (c.every((v) => v > 235) ? 'white' : 'other');

/** Bounding boxes of coloured (non-white) blobs along a scan of the page. */
function coloredBoxes(img) {
  const seen = new Uint8Array(img.w * img.h);
  const boxes = [];
  for (let y = 0; y < img.h; y += 3)
    for (let x = 0; x < img.w; x += 3) {
      if (seen[y * img.w + x] || colorName(img.px(x, y)) === 'white' || colorName(img.px(x, y)) === 'other') continue;
      // flood fill over non-white pixels
      let minX = x, maxX = x, minY = y, maxY = y;
      const stack = [[x, y]];
      seen[y * img.w + x] = 1;
      while (stack.length) {
        const [cx, cy] = stack.pop();
        minX = Math.min(minX, cx); maxX = Math.max(maxX, cx); minY = Math.min(minY, cy); maxY = Math.max(maxY, cy);
        for (const [nx, ny] of [[cx + 1, cy], [cx - 1, cy], [cx, cy + 1], [cx, cy - 1]]) {
          if (nx < 0 || ny < 0 || nx >= img.w || ny >= img.h || seen[ny * img.w + nx]) continue;
          const n = colorName(img.px(nx, ny));
          if (n === 'white') continue;
          seen[ny * img.w + nx] = 1;
          stack.push([nx, ny]);
        }
      }
      if (maxX - minX > 20 && maxY - minY > 20) boxes.push({ x: minX, y: minY, w: maxX - minX + 1, h: maxY - minY + 1 });
    }
  return boxes;
}

// --- Run.
const browser = await chromium.launch();
const context = await browser.newContext({ ...devices['iPhone 13'] });
const page = await context.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
page.on('console', (m) => m.type() === 'error' && errors.push(m.text()));

async function shot(name) {
  await page.waitForTimeout(150);
  await page.screenshot({ path: join(out, `${name}.png`) });
}
async function makePdf(name) {
  await page.click('#btnPrint');
  await page.waitForSelector('#dlgReady[open]', { timeout: 30000 });
  const b64 = await page.evaluate(async () => {
    const buf = await (await fetch(document.getElementById('lnkSave').href)).arrayBuffer();
    let s = '';
    const bytes = new Uint8Array(buf);
    for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
    return btoa(s);
  });
  const file = join(out, `${name}.pdf`);
  await writeFile(file, Buffer.from(b64, 'base64'));
  await shot(`${name}-ready`);
  await page.click('#dlgReady [data-close]');
  return file;
}
const setLength = async (sel, v) => {
  await page.fill(sel, String(v));
  await page.locator(sel).blur();
};

await page.goto(url);
await page.evaluate(() => localStorage.clear());
await page.reload();
await shot('01-empty');
assert.equal(await page.isDisabled('#btnPrint'), true);

// 1) Photos per page on A4.
await page.setInputFiles('#fileSheet', [fixtures.landscape, fixtures.portrait]);
await page.waitForFunction(() => document.querySelectorAll('#thumbs .thumb:not(.add)').length === 2);
await page.click('.chip[data-value="4"]');
await shot('02-sheet-4up');
let f = await makePdf('sheet-4up');
let info = pdfInfo(f);
assert.equal(info.pages, 1);
assert.ok(Math.abs(info.wmm - 210) < 0.5 && Math.abs(info.hmm - 297) < 0.5, 'A4 page');
let img = renderPage(f, 1, 50);
let boxes = coloredBoxes(img);
assert.equal(boxes.length, 2, `expected 2 photos, saw ${boxes.length}`);
console.log('4-up boxes (50dpi):', boxes);

// 2) Exact 2 x 3 in, fill & crop, with fill-page.
await page.click('.seg[data-setting="sheet.sizing"] button[data-value="size"]');
await page.click('.seg[data-setting="unit"] button[data-value="in"] >> nth=0');
await setLength('input[data-setting="sheet.pieceW"]', 2);
await setLength('input[data-setting="sheet.pieceH"]', 3);
await page.click('label:has(input[data-setting="sheet.fillPage"])');
await shot('03-exact-2x3');
f = await makePdf('exact-2x3');
info = pdfInfo(f);
assert.equal(info.pages, 1);
img = renderPage(f, 1, 100);
boxes = coloredBoxes(img);
console.log(`exact 2x3: ${boxes.length} pieces`);
assert.ok(boxes.length >= 10, `expected at least 10 pieces, got ${boxes.length}`);
for (const b of boxes) {
  const [s, l] = [b.w, b.h].sort((a, c) => a - c);
  // 2 x 3 in at 100 dpi = 200 x 300 px (allow 2 px for anti-aliasing / outline)
  assert.ok(Math.abs(s - 200) <= 2 && Math.abs(l - 300) <= 2, `piece ${b.w}x${b.h} is not 2x3 in`);
}

// Every piece shows the whole picture either upright or turned clockwise to fit.
const corners = (b) =>
  [
    [b.x + 12, b.y + 12],
    [b.x + b.w - 12, b.y + 12],
    [b.x + 12, b.y + b.h - 12],
    [b.x + b.w - 12, b.y + b.h - 12],
  ].map(([x, y]) => colorName(img.px(x, y)));
for (const b of boxes) {
  const c = corners(b).join(',');
  assert.ok(['red,green,blue,yellow', 'blue,red,yellow,green'].includes(c), `piece corners ${c}`);
}

// 3) Crop editor: drag the crop on the first photo.
await page.click('#thumbs .thumb:not(.add) >> nth=0');
await page.waitForSelector('#dlgEdit[open]');
await shot('04-editor');
// The piece matches the photo's shape, so zoom in to have room to move.
await page.locator('#cropZoom').evaluate((el) => {
  el.value = '2';
  el.dispatchEvent(new Event('input', { bubbles: true }));
});
const box = await page.locator('#cropCanvas').boundingBox();
await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
await page.mouse.down();
await page.mouse.move(box.x + box.width / 2 + 200, box.y + box.height / 2, { steps: 5 });
await page.mouse.up();
const cx = await page.evaluate(() => window.__printSizing.state.photos[0].cx);
assert.ok(cx > 0.6, `crop should move right, cx=${cx}`);
await shot('05-editor-dragged');
await page.click('#dlgEdit button[value="done"]');

// 4) Poster: 2 x 2 A4 pages.
await page.click('.tabs button[data-value="poster"]');
await shot('06-poster-empty');
await page.setInputFiles('#filePoster', [fixtures.poster]);
await page.waitForFunction(() => !!window.__printSizing.state.poster);
await shot('07-poster-2x2');
f = await makePdf('poster-2x2');
info = pdfInfo(f);
const plan = await page.evaluate(() => window.__printSizing.state.plan.info);
console.log('poster', { cols: plan.cols, rows: plan.rows, w: plan.posterW, h: plan.posterH, orient: plan.orientation });
assert.equal(info.pages, plan.cols * plan.rows);
// Top-left page must be red at its top-left; bottom-right page yellow at its bottom-right.
img = renderPage(f, 1, 60);
let b = coloredBoxes(img)[0];
assert.equal(colorName(img.px(Math.round(b.x + b.w * 0.2), Math.round(b.y + b.h * 0.2))), 'red');
img = renderPage(f, info.pages, 60);
b = coloredBoxes(img)[0];
assert.equal(colorName(img.px(Math.round(b.x + b.w * 0.8), Math.round(b.y + b.h * 0.8))), 'yellow');

// 5) Poster by width with overlap.
await page.click('.seg[data-setting="poster.sizeBy"] button[data-value="width"]');
await page.click('.seg[data-setting="unit"] button[data-value="cm"] >> nth=1');
await setLength('input[data-setting="poster.width"]', 80);
await setLength('input[data-setting="poster.overlap"]', 1);
await shot('08-poster-80cm');
const p2 = await page.evaluate(() => window.__printSizing.state.plan.info);
assert.ok(Math.abs(p2.posterW - 800) < 1e-6);
console.log('poster 80cm:', p2.cols, 'x', p2.rows, p2.orientation);

// 6) Settings + test page.
await page.click('#btnSettings');
await page.waitForSelector('#dlgSettings[open]');
await shot('09-settings');
await page.click('#btnTestPage');
await page.waitForSelector('#dlgReady[open]');
await page.click('#dlgReady [data-close]');

// 7) Dark mode + desktop screenshots for a visual check.
await page.click('.tabs button[data-value="sheet"]');
await page.emulateMedia({ colorScheme: 'dark' });
await shot('10-dark');
await page.emulateMedia({ colorScheme: 'light' });
await page.setViewportSize({ width: 1280, height: 800 });
await shot('11-desktop');

assert.deepEqual(errors, [], 'console errors');
await browser.close();
server.close();
console.log(`e2e passed. Output in ${out}`);
